extends RefCounted
## Battle rules engine. No graphics and no networking: the server feeds player
## intents in with apply() and sends the returned events to every client,
## which only animates them. Randomness comes from a seeded RNG so a battle
## replays the same way from the same seed and intents.
##
## Typical use:
##   var battle = Battle.new({"map": "classroom", "players": [...], "rounds": 3, "seed": 42})
##   events = battle.start_round()
##   result = battle.apply(fighter_id, {"type": "move", "dir": Vector2i.RIGHT})
##   result = battle.apply(fighter_id, {"type": "attack", "slot": 0, "dir": Vector2i.RIGHT})
##   result -> {"ok": true, "events": [...]} or {"ok": false, "error": "blocked"}

const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")
const Fighter = preload("res://rules/fighter.gd")

const SLAM_DAMAGE := 5
const METER_MAX := 100
const METER_PER_HP_DEALT := 2
const METER_PER_HP_TAKEN := 1
const LAST_STAND_PERCENT := 35
const LAST_STAND_BONUS := 3
const SUPER_SLOT := 4
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const SELF_TYPES := ["self_rage", "self_block", "self_sugar"]

enum Phase { WAITING, TURN, ROUND_OVER, MATCH_OVER }

var map_def: Dictionary
var width := 0
var height := 0
## Vector2i -> {"type": "D", "hp": 20}
var obstacles := {}
var fighters: Array[Fighter] = []
## Team ids in ascending order. 1v1 and 2v2 have two teams, a free-for-all has one per player.
var teams: Array[int] = []
## Fighter ids in turn order for the current round.
var order: Array[int] = []
var turn_index := 0
var phase := Phase.WAITING
var rounds_total := 1
var round_number := 0
## team id -> rounds won
var round_wins := {}
var match_winner := -1
## Tests can queue values here to control dice rolls.
var forced_rolls: Array[int] = []

## Tiles stepped onto this turn, so steps can be undone.
var path: Array[Vector2i] = []
var turn_start_pos := Vector2i.ZERO
var move_budget := 0

var _rng := RandomNumberGenerator.new()
var _first_team := -1
## Who acted last on each team this round (team -> fighter id), and the team
## that acted last overall. Turns always pass to the next team, and inside a
## team they rotate, so a 2v2 goes red, blue, red, blue even after a KO.
var _team_last := {}
var _last_team := -1


## config:
##   map: map id from maps.gd, or a map Dictionary
##   players: [{"char": "sebba", "team": 0}, ...] (2-4 players; fighter id = index)
##   rounds: 1-5 (default 1)
##   seed: RNG seed (default 0)
##   first_team: optional, forces which team starts every round
func _init(config: Dictionary) -> void:
	map_def = config.map if config.map is Dictionary else Maps.ALL[config.map]
	rounds_total = config.get("rounds", 1)
	_rng.seed = config.get("seed", 0)
	_first_team = config.get("first_team", -1)
	# Tests can pass their own fighter numbers; the game always uses Characters.ALL.
	var roster: Dictionary = config.get("characters", Characters.ALL)
	var players: Array = config.players
	for i in players.size():
		var p: Dictionary = players[i]
		fighters.append(Fighter.new(i, p["char"], p.team, roster[p["char"]]))
		if not teams.has(p.team):
			teams.append(p.team)
	teams.sort()
	for t in teams:
		round_wins[t] = 0


# ---------------------------------------------------------------- rounds

func start_round() -> Array:
	if phase == Phase.MATCH_OVER or phase == Phase.TURN:
		return []
	round_number += 1
	phase = Phase.TURN
	_load_map()
	for f in fighters:
		f.reset_for_round()
	_place_fighters()
	order = _build_order()
	_team_last.clear()
	turn_index = 0
	while not current().alive() and turn_index < order.size() - 1:
		turn_index += 1
	var events: Array = [{"type": "round_start", "round": round_number, "sudden_death": is_sudden_death(), "order": order.duplicate()}]
	events.append_array(_begin_turn())
	return events


func is_sudden_death() -> bool:
	return round_number > rounds_total


func current() -> Fighter:
	return fighters[order[turn_index]]


# ---------------------------------------------------------------- intents

func apply(fighter_id: int, intent: Dictionary) -> Dictionary:
	if phase != Phase.TURN:
		return _fail("not_in_turn")
	var f := current()
	if f.id != fighter_id:
		return _fail("not_your_turn")
	match intent.get("type"):
		"move":
			return _move(f, intent.get("dir"))
		"undo":
			return _undo(f)
		"attack":
			return _attack(f, int(intent.get("slot", -1)), intent.get("dir"), int(intent.get("dist", 0)))
		"end_turn":
			return _ok(_end_turn())
	return _fail("unknown_intent")


func _move(f: Fighter, dir) -> Dictionary:
	if not _valid_dir(dir):
		return _fail("bad_dir")
	var to: Vector2i = f.pos + dir
	# Stepping back onto the previous tile undoes the last step.
	if not path.is_empty():
		var prev: Vector2i = path[path.size() - 2] if path.size() >= 2 else turn_start_pos
		if to == prev:
			return _undo(f)
	if path.size() >= move_budget:
		return _fail("no_moves_left")
	if not _walkable(to):
		return _fail("blocked")
	var from := f.pos
	f.pos = to
	f.facing = dir
	path.append(to)
	return _ok([{"type": "move", "fighter": f.id, "from": from, "to": to}])


func _undo(f: Fighter) -> Dictionary:
	if path.is_empty():
		return _fail("nothing_to_undo")
	path.pop_back()
	var from := f.pos
	f.pos = path.back() if not path.is_empty() else turn_start_pos
	return _ok([{"type": "move", "fighter": f.id, "from": from, "to": f.pos, "undo": true}])


func _attack(f: Fighter, slot: int, dir, dist: int) -> Dictionary:
	if slot < 0 or slot > SUPER_SLOT:
		return _fail("bad_slot")
	var is_super := slot == SUPER_SLOT
	var atk: Dictionary = f.def["super"] if is_super else f.def.attacks[slot]
	var is_self: bool = SELF_TYPES.has(atk.type)
	if not is_self and not _valid_dir(dir):
		return _fail("bad_dir")
	if f.no_attack_now:
		return _fail("cannot_attack")
	if is_super and f.meter < METER_MAX:
		return _fail("super_not_ready")
	var err := _validate(f, atk, dir, dist)
	if err != "":
		return _fail(err)

	if not is_self:
		f.facing = dir
	if is_super:
		f.meter = 0
	var ctx := {"attacker": f, "dir": dir, "super": is_super, "events": []}
	ctx.events.append({"type": "attack", "fighter": f.id, "attack": atk.id, "super": is_super, "dir": dir, "dist": dist})
	_resolve(ctx, atk, dist)
	_check_round_end(ctx.events)
	if phase == Phase.TURN and not atk.get("free", false):
		ctx.events.append_array(_end_turn())
	return _ok(ctx.events)


func _validate(f: Fighter, atk: Dictionary, dir, dist: int) -> String:
	match atk.type:
		"lob":
			if dist < atk.min_range or dist > atk.max_range:
				return "bad_dist"
			if not _in_bounds(f.pos + dir * dist):
				return "bad_dist"
		"leap":
			if _leap_target(f, dir, atk["range"]).is_empty():
				return "no_target"
		"self_sugar":
			if f.sugar_active:
				return "already_active"
	return ""


# ---------------------------------------------------------------- attack types

func _resolve(ctx: Dictionary, atk: Dictionary, dist: int) -> void:
	var f: Fighter = ctx.attacker
	var dir = ctx.dir
	match atk.type:
		"melee":
			var dmg: int = atk.damage if atk.has("damage") else _roll(atk.damage_min, atk.damage_max)
			_hit_tile(ctx, f.pos + dir, dmg, atk)
		"around":
			for d in AROUND:
				_hit_tile(ctx, f.pos + d, atk.damage)
		"dash":
			var run := 0
			while run < atk["range"] and _walkable(f.pos + dir):
				var from := f.pos
				f.pos += dir
				run += 1
				ctx.events.append({"type": "move", "fighter": f.id, "from": from, "to": f.pos, "dash": true})
			_hit_tile(ctx, f.pos + dir, atk.damage + atk.get("damage_per_tile", 0) * run, atk)
		"projectile":
			for d in range(1, atk["range"] + 1):
				var t: Vector2i = f.pos + dir * d
				if not _in_bounds(t):
					break
				var o := _fighter_at(t)
				if obstacles.has(t) or (o != null and o.team != f.team):
					_hit_tile(ctx, t, atk.damage, atk)
					break
		"line":
			for d in range(1, atk["range"] + 1):
				var t: Vector2i = f.pos + dir * d
				if not _in_bounds(t):
					break
				_hit_tile(ctx, t, atk.damage, atk)
				if obstacles.has(t):
					break
		"lob":
			var center: Vector2i = f.pos + dir * dist
			for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if _in_bounds(center + d):
					_hit_tile(ctx, center + d, atk.damage, atk)
		"shockwave":
			var impact: Vector2i = f.pos + dir
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var t := impact + Vector2i(dx, dy)
					if t == f.pos or not _in_bounds(t):
						continue
					if maxi(absi(dx), absi(dy)) <= 1:
						_hit_tile(ctx, t, atk.inner_damage)
					else:
						_hit_tile(ctx, t, atk.outer_damage, {"status": atk.outer_status})
		"leap":
			var target := _leap_target(f, dir, atk["range"])
			var victim: Fighter = target.fighter
			ctx.events.append({"type": "leap", "fighter": f.id, "to": victim.pos, "over_obstacle": target.over_obstacle})
			_hit_tile(ctx, victim.pos, atk.damage, atk)
			var cost: int = atk.self_damage_over_obstacle if target.over_obstacle else atk.self_damage
			var lost := mini(cost, f.hp - 1)
			f.hp -= lost
			ctx.events.append({"type": "self_damage", "fighter": f.id, "amount": lost, "hp": f.hp})
			_apply_status(ctx, f, atk.self_status)
		"self_rage":
			f.rage_turns = _roll(atk.turns_min, atk.turns_max)
			f.rage_fresh = true
			f.rage_bonus = atk.bonus
			if atk.get("shield", 0) > 0:
				f.shield = {"kind": "hp", "amount": atk.shield}
			ctx.events.append({"type": "status", "fighter": f.id, "status": "rage", "turns": f.rage_turns, "shield": atk.shield})
		"self_block":
			f.shield = {"kind": "block"}
			ctx.events.append({"type": "status", "fighter": f.id, "status": "block"})
		"self_sugar":
			f.sugar_active = true
			f.sugar_multiplier = atk.multiplier
			f.no_attack_next = true
			ctx.events.append({"type": "status", "fighter": f.id, "status": "sugar_rush"})


## Closest enemy along a line, jumping over allies and obstacles.
## Returns {} or {"fighter": Fighter, "over_obstacle": bool}.
func _leap_target(f: Fighter, dir, reach: int) -> Dictionary:
	var over := false
	for d in range(1, reach + 1):
		var t: Vector2i = f.pos + dir * d
		if not _in_bounds(t):
			break
		var o := _fighter_at(t)
		if o != null and o.team != f.team:
			return {"fighter": o, "over_obstacle": over}
		if obstacles.has(t):
			over = true
	return {}


## Damages whatever stands on a tile. Allies and the attacker are never hit.
func _hit_tile(ctx: Dictionary, tile: Vector2i, base: int, opts := {}) -> void:
	var f: Fighter = ctx.attacker
	if obstacles.has(tile):
		_damage_obstacle(ctx, tile, _attack_damage(f, base))
		return
	var t := _fighter_at(tile)
	if t == null or t.team == f.team:
		return
	if not _deal(f, t, _attack_damage(f, base), ctx):
		return
	if not t.alive():
		return
	_apply_status(ctx, t, opts.get("status", ""))
	var kb: int = opts.get("knockback", 0)
	if opts.has("knockback_max"):
		kb = _roll(opts.knockback_min, opts.knockback_max)
	if kb > 0:
		_knockback(ctx, t, ctx.dir, kb)


func _attack_damage(f: Fighter, base: int) -> int:
	var dmg := float(base)
	if f.def.get("passive") == "last_stand" and f.hp * 100 < f.max_hp * LAST_STAND_PERCENT:
		dmg += LAST_STAND_BONUS
	if f.rage_turns > 0:
		dmg += f.rage_bonus
	if f.sugar_active:
		dmg *= f.sugar_multiplier
	return int(round(dmg))


## Returns false when the hit was stopped by a Block.
func _deal(src: Fighter, target: Fighter, amount: int, ctx: Dictionary) -> bool:
	if target.shield.get("kind") == "block":
		target.shield = {}
		ctx.events.append({"type": "blocked", "fighter": target.id})
		return false
	var absorbed := 0
	if target.shield.get("kind") == "hp":
		absorbed = mini(amount, target.shield.amount)
		target.shield.amount -= absorbed
		if target.shield.amount == 0:
			target.shield = {}
	var lost := mini(amount - absorbed, target.hp)
	target.hp -= lost
	ctx.events.append({"type": "damage", "fighter": target.id, "amount": amount, "absorbed": absorbed, "hp": target.hp})
	# A super's own damage doesn't charge the attacker's meter.
	if not ctx.super:
		_gain_meter(ctx, src, lost * METER_PER_HP_DEALT)
	_gain_meter(ctx, target, lost * METER_PER_HP_TAKEN)
	if not target.alive():
		ctx.events.append({"type": "ko", "fighter": target.id})
	return true


func _gain_meter(ctx: Dictionary, f: Fighter, amount: int) -> void:
	if amount <= 0 or not f.alive():
		return
	var before := f.meter
	f.meter = mini(METER_MAX, f.meter + amount)
	if f.meter != before:
		ctx.events.append({"type": "meter", "fighter": f.id, "meter": f.meter})


func _apply_status(ctx: Dictionary, f: Fighter, status: String) -> void:
	if status == "dizzy":
		f.dizzy_next = true
		ctx.events.append({"type": "status", "fighter": f.id, "status": "dizzy"})


func _knockback(ctx: Dictionary, t: Fighter, dir: Vector2i, tiles: int) -> void:
	var attacker: Fighter = ctx.attacker
	for i in tiles:
		var next := t.pos + dir
		var other := _fighter_at(next)
		if not _in_bounds(next) or obstacles.has(next) or other != null:
			ctx.events.append({"type": "slam", "fighter": t.id, "at": next})
			_deal(attacker, t, SLAM_DAMAGE, ctx)
			if obstacles.has(next):
				_damage_obstacle(ctx, next, SLAM_DAMAGE)
			if other != null and other != attacker and other.team != attacker.team:
				_deal(attacker, other, SLAM_DAMAGE, ctx)
			return
		var from := t.pos
		t.pos = next
		ctx.events.append({"type": "knockback", "fighter": t.id, "from": from, "to": next})


func _damage_obstacle(ctx: Dictionary, tile: Vector2i, amount: int) -> void:
	var o: Dictionary = obstacles[tile]
	o.hp -= amount
	ctx.events.append({"type": "obstacle_damage", "at": tile, "amount": amount, "hp": maxi(o.hp, 0)})
	if o.hp <= 0:
		obstacles.erase(tile)
		ctx.events.append({"type": "obstacle_broken", "at": tile, "obstacle": o.type})


# ---------------------------------------------------------------- turns

func _begin_turn() -> Array:
	var f := current()
	var events: Array = []
	if f.shield.get("kind") == "block":
		f.shield = {}
		events.append({"type": "status_end", "fighter": f.id, "status": "block"})
	move_budget = maxi(0, f.move - (1 if f.dizzy_next else 0))
	f.dizzy_next = false
	f.no_attack_now = f.no_attack_next
	f.no_attack_next = false
	path.clear()
	turn_start_pos = f.pos
	events.append({"type": "turn_start", "fighter": f.id, "move_budget": move_budget, "can_attack": not f.no_attack_now})
	return events


func _end_turn() -> Array:
	var f := current()
	var events: Array = []
	if f.rage_turns > 0:
		if f.rage_fresh:
			f.rage_fresh = false
		else:
			f.rage_turns -= 1
			if f.rage_turns == 0:
				f.rage_bonus = 0
				if f.shield.get("kind") == "hp":
					f.shield = {}
				events.append({"type": "status_end", "fighter": f.id, "status": "rage"})
	f.sugar_active = false
	f.no_attack_now = false
	events.append({"type": "turn_end", "fighter": f.id})
	_advance_turn()
	events.append_array(_begin_turn())
	return events


func _check_round_end(events: Array) -> void:
	var alive_teams: Array[int] = []
	for f in fighters:
		if f.alive() and not alive_teams.has(f.team):
			alive_teams.append(f.team)
	if alive_teams.size() > 1:
		return
	var winner: int = alive_teams[0] if alive_teams.size() == 1 else -1
	if winner != -1:
		round_wins[winner] += 1
	if phase == Phase.TURN:
		_last_team = current().team  # the next round starts with the other team
	phase = Phase.ROUND_OVER
	events.append({"type": "round_end", "round": round_number, "winner_team": winner, "wins": round_wins.duplicate()})
	var mw := _decided_winner()
	if mw != -1:
		phase = Phase.MATCH_OVER
		match_winner = mw
		events.append({"type": "match_end", "winner_team": mw, "wins": round_wins.duplicate()})


## The match is decided once the leader can't be caught in the rounds left.
## A tie after the last round means sudden-death rounds until someone leads.
func _decided_winner() -> int:
	# Teams where everyone forfeited are out of the match.
	var ranked: Array[int] = []
	for f in fighters:
		if not f.forfeited and not ranked.has(f.team):
			ranked.append(f.team)
	if ranked.size() == 1:
		return ranked[0]
	ranked.sort_custom(func(a, b): return round_wins[a] > round_wins[b])
	var remaining := maxi(0, rounds_total - round_number)
	if round_wins[ranked[0]] > round_wins[ranked[1]] + remaining:
		return ranked[0]
	return -1


# ---------------------------------------------------------------- setup

func _load_map() -> void:
	var rows: Array = map_def.rows
	height = rows.size()
	width = rows[0].length()
	obstacles.clear()
	for y in height:
		for x in width:
			var ch: String = rows[y][x]
			if Maps.OBSTACLE_HP.has(ch):
				obstacles[Vector2i(x, y)] = {"type": ch, "hp": Maps.OBSTACLE_HP[ch]}


func _place_fighters() -> void:
	if teams.size() == 2:
		for side in 2:
			var spawns := _spawn_tiles(str(side + 1))
			var k := 0
			for f in fighters:
				if f.team == teams[side]:
					f.pos = spawns[k]
					f.facing = Vector2i.RIGHT if side == 0 else Vector2i.LEFT
					k += 1
	else:
		for f in fighters:
			var s: Array = map_def.ffa_spawns[teams.find(f.team)]
			f.pos = Vector2i(s[0], s[1])
			f.facing = Vector2i.RIGHT if f.pos.x < width / 2 else Vector2i.LEFT


func _spawn_tiles(ch: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if map_def.rows[y][x] == ch:
				out.append(Vector2i(x, y))
	return out


## Hands the turn to the next team that still has someone standing, and to
## that team's next living fighter after the one who acted last.
func _advance_turn() -> void:
	var cur := current()
	_team_last[cur.team] = cur.id
	_last_team = cur.team
	var ti := teams.find(cur.team)
	for k in range(1, teams.size() + 1):
		var t: int = teams[(ti + k) % teams.size()]
		var members: Array[int] = []
		for id in order:
			if fighters[id].team == t:
				members.append(id)
		var start := members.find(_team_last.get(t, -1)) + 1
		for j in members.size():
			var id := members[(start + j) % members.size()]
			if fighters[id].alive():
				turn_index = order.find(id)
				return


func _build_order() -> Array[int]:
	var by_team := {}
	for t in teams:
		by_team[t] = []
	for f in fighters:
		by_team[f.team].append(f.id)
	# Round 1 starts with a random team; later rounds carry on the
	# alternation from where the last round stopped.
	var start: int = _first_team
	if start == -1 and _last_team != -1:
		start = teams[(teams.find(_last_team) + 1) % teams.size()]
	elif start == -1:
		start = teams[_roll(0, teams.size() - 1)]
	var rotated := teams.duplicate()
	while rotated[0] != start:
		rotated.push_back(rotated.pop_front())
	var longest := 0
	for t in teams:
		longest = maxi(longest, by_team[t].size())
	var out: Array[int] = []
	for i in longest:
		for t in rotated:
			if i < by_team[t].size():
				out.append(by_team[t][i])
	return out


# ---------------------------------------------------------------- online helpers

## Takes a player out of the match (used when they disconnect for too long).
## They are knocked out now and in every later round.
func forfeit(fighter_id: int) -> Array:
	var f := fighters[fighter_id]
	if f.forfeited or phase == Phase.MATCH_OVER:
		return []
	f.forfeited = true
	var events: Array = [{"type": "forfeit", "fighter": fighter_id}]
	if phase != Phase.TURN:
		var mw := _decided_winner()
		if mw != -1:
			phase = Phase.MATCH_OVER
			match_winner = mw
			events.append({"type": "match_end", "winner_team": mw, "wins": round_wins.duplicate()})
		return events
	var was_current := current().id == fighter_id
	if f.alive():
		f.hp = 0
		events.append({"type": "ko", "fighter": fighter_id})
	_check_round_end(events)
	if phase == Phase.TURN and was_current:
		events.append_array(_end_turn())
	return events


## A fingerprint of everything that matters in the battle. The server sends it
## with every move so clients can tell if their copy got out of sync.
func state_hash() -> int:
	var parts := [phase, round_number, turn_index, move_budget, path.size(), _rng.state, _last_team, _team_last]
	for f in fighters:
		parts.append_array([f.hp, f.pos.x, f.pos.y, f.meter, f.shield.get("kind", ""), f.shield.get("amount", 0),
			f.dizzy_next, f.rage_turns, f.sugar_active, f.no_attack_next, f.no_attack_now, f.forfeited])
	var tiles := obstacles.keys()
	tiles.sort()
	for t in tiles:
		parts.append_array([t.x, t.y, obstacles[t].hp])
	return hash(str(parts))


# ---------------------------------------------------------------- previews (read-only, for the UI)

## Tiles the current fighter can still walk to this turn, with the steps left.
func reachable_tiles() -> Array[Vector2i]:
	var f := current()
	var left := move_budget - path.size()
	var out: Array[Vector2i] = []
	var seen := {f.pos: 0}
	var frontier: Array[Vector2i] = [f.pos]
	for i in left:
		var next: Array[Vector2i] = []
		for t in frontier:
			for d in DIRS:
				var n := t + d
				if not seen.has(n) and _walkable(n):
					seen[n] = i + 1
					next.append(n)
					out.append(n)
		frontier = next
	return out


## Shortest walk for the current fighter to `t` within the moves left this
## turn, as the list of tiles to step on, or [] if it can't get there.
func path_to(t: Vector2i) -> Array[Vector2i]:
	var f := current()
	var left := move_budget - path.size()
	var came := {f.pos: f.pos}
	var frontier: Array[Vector2i] = [f.pos]
	for i in left:
		var next: Array[Vector2i] = []
		for p in frontier:
			for d in DIRS:
				var n: Vector2i = p + d
				if came.has(n) or not _walkable(n):
					continue
				came[n] = p
				next.append(n)
		frontier = next
	if not came.has(t) or t == f.pos:
		return []
	var out: Array[Vector2i] = []
	var at := t
	while at != f.pos:
		out.push_front(at)
		at = came[at]
	return out


## What an attack would do, without doing it.
## Returns [{"pos": Vector2i, "kind": "hit" | "dizzy" | "path" | "self"}, ...]
func preview(fighter_id: int, slot: int, dir, dist := 0) -> Array:
	var f := fighters[fighter_id]
	if slot < 0 or slot > SUPER_SLOT:
		return []
	var atk: Dictionary = f.def["super"] if slot == SUPER_SLOT else f.def.attacks[slot]
	var out := []
	var add := func(t: Vector2i, kind: String) -> void:
		if _in_bounds(t):
			out.append({"pos": t, "kind": kind})
	if SELF_TYPES.has(atk.type):
		add.call(f.pos, "self")
		return out
	if not _valid_dir(dir):
		return []
	var hit_kind := "dizzy" if atk.get("status", "") == "dizzy" else "hit"
	match atk.type:
		"melee":
			add.call(f.pos + dir, hit_kind)
		"around":
			for d in AROUND:
				add.call(f.pos + d, hit_kind)
		"dash":
			var at := f.pos
			var run := 0
			while run < atk["range"] and _walkable(at + dir):
				at += dir
				run += 1
				add.call(at, "path")
			add.call(at + dir, hit_kind)
		"projectile":
			for d in range(1, atk["range"] + 1):
				var t: Vector2i = f.pos + dir * d
				if not _in_bounds(t):
					break
				var o := _fighter_at(t)
				if obstacles.has(t) or (o != null and o.team != f.team):
					add.call(t, hit_kind)
					break
				add.call(t, "path")
		"line":
			for d in range(1, atk["range"] + 1):
				var t: Vector2i = f.pos + dir * d
				if not _in_bounds(t):
					break
				add.call(t, hit_kind)
				if obstacles.has(t):
					break
		"lob":
			var center: Vector2i = f.pos + dir * clampi(dist, atk.min_range, atk.max_range)
			for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				add.call(center + d, hit_kind)
		"shockwave":
			var impact: Vector2i = f.pos + dir
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var t := impact + Vector2i(dx, dy)
					if t != f.pos:
						add.call(t, "hit" if maxi(absi(dx), absi(dy)) <= 1 else "dizzy")
		"leap":
			var target := _leap_target(f, dir, atk["range"])
			var reach: int = atk["range"]
			if not target.is_empty():
				reach = maxi(absi(target.fighter.pos.x - f.pos.x), absi(target.fighter.pos.y - f.pos.y))
			for d in range(1, reach + 1):
				add.call(f.pos + dir * d, "path")
			if not target.is_empty():
				out[out.size() - 1].kind = hit_kind
	return out


## Short reason an attack can't be used right now, or "" if it can.
func attack_blocked_reason(fighter_id: int, slot: int) -> String:
	var f := fighters[fighter_id]
	if f.no_attack_now:
		return "cannot_attack"
	if slot == SUPER_SLOT and f.meter < METER_MAX:
		return "super_not_ready"
	if slot == 3 and f.def.attacks[3].type == "self_sugar" and f.sugar_active:
		return "already_active"
	return ""


# ---------------------------------------------------------------- helpers

func _roll(lo: int, hi: int) -> int:
	if not forced_rolls.is_empty():
		return forced_rolls.pop_front()
	return _rng.randi_range(lo, hi)


func _valid_dir(dir) -> bool:
	return dir is Vector2i and DIRS.has(dir)


func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < width and t.y < height


func _fighter_at(t: Vector2i) -> Fighter:
	for f in fighters:
		if f.alive() and f.pos == t:
			return f
	return null


func _walkable(t: Vector2i) -> bool:
	return _in_bounds(t) and not obstacles.has(t) and _fighter_at(t) == null


func _ok(events: Array) -> Dictionary:
	return {"ok": true, "events": events}


func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "events": []}
