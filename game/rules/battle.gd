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
## The held item (if any) is used like a 5th attack, in place of attacking.
const ITEM_SLOT := 5
## Breaking a locker (with items on) gives the breaker an item 30% of the time.
const ITEM_CHANCE := 30
const ITEM_IDS := ["book", "pencils", "water"]
const ITEMS := {
	"book": {"id": "book", "name": "Book", "type": "projectile", "range": 4, "damage": 12, "knockback": 1},
	"pencils": {"id": "pencils", "name": "Pencils", "type": "projectile", "range": 4, "damage": 3, "hits": 3},
	"water": {"id": "water", "name": "Water Bottle", "type": "spill"},
	"melee_guard": {"id": "melee_guard", "name": "Melee Guard", "type": "self_guard", "guard": "melee"},
	"ranged_guard": {"id": "ranged_guard", "name": "Ranged Guard", "type": "self_guard", "guard": "ranged"},
	# only drops when the map shrinks: the detention zone can't hurt you for your next 2 turns
	"hall_pass": {"id": "hall_pass", "name": "Hall Pass", "type": "self_pass", "turns": 2},
}
## With items on, a mystery box appears every few turns (one at a time) on a
## free tile near the middle. Walking onto it gives a Melee Guard or a Ranged
## Guard (random, and you see which). Using it cuts that kind of damage by
## 20-45% for 1-2 of your turns.
const BOX_ITEMS := ["melee_guard", "ranged_guard"]
const BOX_EVERY_TURNS := 4
const GUARD_PCT := [20, 45]
const GUARD_TURNS := [1, 2]
## Stepping in an enemy's puddle: this much damage, the walk stops, Dizzy next turn.
const PUDDLE_DAMAGE := 5
## Shrinking map (host setting): after SHRINK_START turns the outer ring becomes
## a detention zone, and it grows one ring every SHRINK_EVERY turns (never
## covering the middle). Starting your turn in it costs ZONE_DAMAGE HP.
const SHRINK_START := 6
const SHRINK_EVERY := 4
const ZONE_DAMAGE := 10
## Boss fight: three players (team 0) against the Principal (team 1).
const BOSS_TEAM := 1
const BOSS_PLAYER_HP := 250  # every player gets this much extra HP
const BOSS_RADIUS := 1  # 3x3 tiles
const RULER_DAMAGE := 24  # everyone right next to him, pushed back RULER_PUSH
const MEGAPHONE_DAMAGE := 15  # everyone in line with him, pushed back MEGAPHONE_PUSH
const DETENTION_DAMAGE := 24  # one player anywhere, + Dizzy
## Hits on the Principal count double, so 2250 HP doesn't take forever.
const BOSS_HIT_MULTIPLIER := 2
const RULER_PUSH := 2  # tiles the Ruler Slam pushes you back
const MEGAPHONE_PUSH := 3  # ...and the Megaphone Yell 3
## Teachers the Principal summons to help him (ids after his).
const TEACHERS := 2
const TEACHER_DAMAGE := 10
const SUMMON_CHANCE := 40  # % per turn once all teachers are gone
## Below this much HP (%) he gets ANGRY: his attacks do ANGRY_BONUS more damage.
const ANGRY_PCT := 25
const ANGRY_BONUS := 5
## The Lunch Lady: Gravy Splash leaves this many gravy puddles in her lanes
## (players who step in one slip), and Food Fight! also splashes the players
## right next to its target.
const GRAVY_PUDDLES := 3
const GRAVY_MAX := 3  # gravy puddles on the floor at once (older ones stay until stepped in)
const FOOD_FIGHT_DAMAGE := 18
const FOOD_SPLASH_DAMAGE := 8
const APPLE_EVERY := 150  # an apple drops each time he loses this much HP
const APPLE_HEAL := 60
## Host setting: everyone gets this much extra HP (0 = original).
const BONUS_HP_CHOICES := [0, 50, 100, 150]
const MAX_BONUS_HP := 150
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const SELF_TYPES := ["self_rage", "self_block", "self_sugar", "self_guard", "self_pass"]
## Attacks that can't reach someone hiding in a sandbox.
const RANGED_TYPES := ["projectile", "line", "lob"]

enum Phase { WAITING, TURN, ROUND_OVER, MATCH_OVER }

var map_def: Dictionary
var width := 0
var height := 0
## Vector2i -> {"type": "D", "hp": 20}
var obstacles := {}
## Sandbox tiles (Vector2i -> true). Standing in one hides you from ranged attacks.
var sand := {}
## Water puddles on the floor: Vector2i -> id of the fighter who spilled it.
var puddles := {}
var items_on := false
## The mystery box's tile, or NO_BOX.
const NO_BOX := Vector2i(-1, -1)
var box := NO_BOX
var _turn_count := 0
var shrink_on := false
var boss_mode := false
## Which boss (a key of Characters.BOSSES) in a boss fight.
var boss_id := ""
## Health apples on the floor (boss fights): Vector2i -> HP they heal.
var apples := {}
var _apples_dropped := 0
## How many rings from the edge are detention zone right now (0 = none).
var zone_rings := 0
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
##   items: true = broken lockers can drop items (default off)
##   bonus_hp: extra HP for every fighter (0, 50, 100 or 150) for longer fights
##   shrink: true = the map shrinks (detention zone) as the round goes on
##   boss: true = boss fight: `players` are the team against the Principal
##     (the engine adds him as the last fighter); one round, Principal's Office
func _init(config: Dictionary) -> void:
	items_on = config.get("items", false) == true
	shrink_on = config.get("shrink", false) == true
	var which = config.get("boss", false)
	# true (the Principal, the first boss) or a boss id
	if which is String and Characters.BOSSES.has(which):
		boss_id = which
	elif typeof(which) == TYPE_BOOL and which:
		boss_id = "principal"
	boss_mode = boss_id != ""
	if boss_mode:
		var m = config.get("map")  # always the boss's own room unless a test passes a map
		map_def = m if m is Dictionary else Maps.BOSS_ROOMS[boss_id]
		rounds_total = 1
	else:
		map_def = config.map if config.map is Dictionary else Maps.ALL[config.map]
		rounds_total = config.get("rounds", 1)
	_rng.seed = config.get("seed", 0)
	_first_team = config.get("first_team", -1)
	# Tests can pass their own fighter numbers; the game always uses Characters.ALL.
	var roster: Dictionary = config.get("characters", Characters.ALL)
	var players: Array = config.players
	for i in players.size():
		var p: Dictionary = players[i]
		var team: int = 0 if boss_mode else p.team
		var fighter := Fighter.new(i, p["char"], team, roster[p["char"]])
		if boss_mode:
			fighter.max_hp += BOSS_PLAYER_HP
		else:
			fighter.max_hp += clampi(int(config.get("bonus_hp", 0)), 0, MAX_BONUS_HP)
		fighter.hp = fighter.max_hp
		fighters.append(fighter)
		if not teams.has(team):
			teams.append(team)
	if boss_mode:
		var info: Dictionary = Characters.BOSSES[boss_id]
		var boss := Fighter.new(players.size(), boss_id, BOSS_TEAM, info.def)
		boss.is_boss = true
		fighters.append(boss)
		teams.append(BOSS_TEAM)
		# the helpers (teachers / cooks) wait off the board (knocked out) until summoned
		for k in TEACHERS:
			var t := Fighter.new(fighters.size(), info.minion, BOSS_TEAM, info.minion_def)
			t.is_minion = true
			fighters.append(t)
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
		if f.is_minion:
			f.hp = 0
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
	var events: Array = [{"type": "move", "fighter": f.id, "from": from, "to": to}]
	if to == box:
		# Picked up: the steps so far can't be undone (no walking back off it).
		box = NO_BOX
		var pool := _item_pool(BOX_ITEMS)
		f.item = pool[_roll(0, pool.size() - 1)]
		events.append({"type": "item", "fighter": f.id, "item": f.item, "at": to, "from_box": true})
		move_budget -= path.size()
		path.clear()
		turn_start_pos = f.pos
	if apples.has(to):
		var healed := mini(apples[to], f.max_hp - f.hp)
		f.hp += healed
		apples.erase(to)
		events.append({"type": "heal", "fighter": f.id, "amount": healed, "hp": f.hp, "at": to})
	if puddles.has(to) and fighters[puddles[to]].team != f.team:
		_slip(f, to, events)
	return _ok(events)


## Walking into an enemy's puddle: the puddle is used up, the fighter takes a
## little damage, can't walk (or undo) any further this turn and is Dizzy next turn.
func _slip(f: Fighter, tile: Vector2i, events: Array) -> void:
	var owner: Fighter = fighters[puddles[tile]]
	puddles.erase(tile)
	events.append({"type": "slip", "fighter": f.id, "at": tile, "by": owner.id})
	var ctx := {"attacker": owner, "dir": f.facing, "super": false, "events": events}
	_deal(owner, f, PUDDLE_DAMAGE, ctx)
	path.clear()
	turn_start_pos = f.pos
	move_budget = 0
	_apply_status(ctx, f, "dizzy")
	_check_round_end(events)
	if phase == Phase.TURN and not f.alive():
		events.append_array(_end_turn())


func _undo(f: Fighter) -> Dictionary:
	if path.is_empty():
		return _fail("nothing_to_undo")
	path.pop_back()
	var from := f.pos
	f.pos = path.back() if not path.is_empty() else turn_start_pos
	return _ok([{"type": "move", "fighter": f.id, "from": from, "to": f.pos, "undo": true}])


## The attack in a slot: 0-3 attacks, 4 super, 5 the held item ({} if none).
func slot_attack(f: Fighter, slot: int) -> Dictionary:
	if slot == ITEM_SLOT:
		return ITEMS.get(f.item, {})
	if slot == SUPER_SLOT:
		return f.def["super"]
	if slot >= 0 and slot < SUPER_SLOT:
		return f.def.attacks[slot]
	return {}


func _attack(f: Fighter, slot: int, dir, dist: int) -> Dictionary:
	if slot < 0 or slot > ITEM_SLOT:
		return _fail("bad_slot")
	var is_super := slot == SUPER_SLOT
	if slot == ITEM_SLOT and f.item == "":
		return _fail("no_item")
	var atk: Dictionary = slot_attack(f, slot)
	var is_self: bool = SELF_TYPES.has(atk.type)
	if not is_self and not _valid_dir(dir):
		return _fail("bad_dir")
	if f.no_attack_now:
		return _fail("cannot_attack")
	if turns_until_ready(f, slot) > 0:
		return _fail("cooldown")
	if is_super and f.meter < METER_MAX:
		return _fail("super_not_ready")
	var err := _validate(f, atk, dir, dist)
	if err != "":
		return _fail(err)

	if not is_self:
		f.facing = dir
	if is_super:
		f.meter = 0
	if slot == ITEM_SLOT:
		f.item = ""
	if atk.has("cooldown"):
		# e.g. Block with cooldown 2: not on the next 2 own turns
		f.ready_at[slot] = f.own_turns + atk.cooldown + 1
	var ctx := {"attacker": f, "dir": dir, "super": is_super, "ranged": RANGED_TYPES.has(atk.type), "events": []}
	ctx.events.append({"type": "attack", "fighter": f.id, "attack": atk.id, "super": is_super, "item": slot == ITEM_SLOT, "dir": dir, "dist": dist})
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
		"spill":
			var t: Vector2i = f.pos + dir
			if not _walkable(t) or puddles.has(t):
				return "no_room"
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
				if obstacles.has(t) or (o != null and o.team != f.team and not sand.has(t)):
					for h in atk.get("hits", 1):
						ctx.boss_hit = false
						_hit_tile(ctx, t, atk.damage, atk)
					break
		"spill":
			var t: Vector2i = f.pos + dir
			puddles[t] = f.id
			ctx.events.append({"type": "puddle", "fighter": f.id, "at": t})
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
		"self_guard":
			var kind: String = atk.guard
			f.guard = {"kind": kind, "pct": _roll(GUARD_PCT[0], GUARD_PCT[1]), "turns": _roll(GUARD_TURNS[0], GUARD_TURNS[1])}
			ctx.events.append({"type": "status", "fighter": f.id, "status": "guard", "kind": kind, "pct": f.guard.pct, "turns": f.guard.turns})
		"self_pass":
			f.zone_safe = atk.turns
			ctx.events.append({"type": "status", "fighter": f.id, "status": "hall_pass", "turns": f.zone_safe})
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
	if t.is_boss:
		# he covers 9 tiles: an attack hits him once (Pencils reset this per pencil)
		if ctx.get("boss_hit", false):
			return
		ctx.boss_hit = true
	if ctx.get("ranged", false) and sand.has(tile):
		ctx.events.append({"type": "hidden", "fighter": t.id})
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
	if target.is_boss:
		amount *= BOSS_HIT_MULTIPLIER
	var guarded := 0
	if not target.guard.is_empty() and (target.guard.kind == "ranged") == ctx.get("ranged", false):
		guarded = amount - int(round(amount * (100 - target.guard.pct) / 100.0))
		amount -= guarded
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
	if src != target:
		src.match_damage += lost
	if target.is_boss:
		_drop_apples(target, ctx.events)
	ctx.events.append({"type": "damage", "fighter": target.id, "amount": amount, "absorbed": absorbed, "guarded": guarded, "hp": target.hp})
	# A super's own damage doesn't charge the attacker's meter.
	if not ctx.super:
		_gain_meter(ctx, src, lost * METER_PER_HP_DEALT)
	_gain_meter(ctx, target, lost * METER_PER_HP_TAKEN)
	if not target.alive():
		ctx.events.append({"type": "ko", "fighter": target.id})
		if src != target and src.team != target.team:
			src.match_kos += 1
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
	if t.is_boss:
		return  # far too big to push around
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
		var f: Fighter = ctx.attacker
		if items_on and o.type == "L" and f.alive() and _roll(1, 100) <= ITEM_CHANCE:
			var pool := _item_pool(ITEM_IDS)
			f.item = pool[_roll(0, pool.size() - 1)]
			ctx.events.append({"type": "item", "fighter": f.id, "item": f.item, "at": tile})


# ---------------------------------------------------------------- turns

func _begin_turn() -> Array:
	var f := current()
	var events: Array = []
	if f.shield.get("kind") == "block":
		f.shield = {}
		events.append({"type": "status_end", "fighter": f.id, "status": "block"})
	if not f.guard.is_empty():
		f.guard.turns -= 1
		if f.guard.turns <= 0:
			f.guard = {}
			events.append({"type": "status_end", "fighter": f.id, "status": "guard"})
	_turn_count += 1
	if items_on and box == NO_BOX and _turn_count % BOX_EVERY_TURNS == 0:
		_spawn_box(events)
	if shrink_on and _turn_count >= SHRINK_START and (_turn_count - SHRINK_START) % SHRINK_EVERY == 0 \
			and zone_rings < max_zone_rings():
		zone_rings += 1
		events.append({"type": "shrink", "rings": zone_rings})
		if box != NO_BOX and in_zone(box):
			box = NO_BOX
			events.append({"type": "box_gone"})
	var safe := f.zone_safe > 0  # Hall Pass
	if safe:
		f.zone_safe -= 1
		if in_zone(f.pos):
			events.append({"type": "zone_safe", "fighter": f.id})
		if f.zone_safe == 0:
			events.append({"type": "status_end", "fighter": f.id, "status": "hall_pass"})
	if in_zone(f.pos) and f.alive() and not f.is_boss and not safe:
		var lost := mini(ZONE_DAMAGE, f.hp)
		f.hp -= lost
		events.append({"type": "damage", "fighter": f.id, "amount": lost, "absorbed": 0, "guarded": 0, "hp": f.hp, "zone": true})
		var ctx := {"attacker": f, "dir": Vector2i.ZERO, "super": false, "events": events}
		_gain_meter(ctx, f, lost * METER_PER_HP_TAKEN)
		if not f.alive():
			events.append({"type": "ko", "fighter": f.id})
			_check_round_end(events)
			if phase == Phase.TURN:
				events.append_array(_end_turn())
			return events
	f.own_turns += 1
	move_budget = maxi(0, f.move - (1 if f.dizzy_next else 0))
	for o in fighters:
		o.dizzy_now = false
	f.dizzy_now = f.dizzy_next
	f.dizzy_next = false
	f.no_attack_now = f.no_attack_next
	f.no_attack_next = false
	path.clear()
	turn_start_pos = f.pos
	events.append({"type": "turn_start", "fighter": f.id, "move_budget": move_budget, "can_attack": not f.no_attack_now})
	if (f.is_boss or f.is_minion) and phase == Phase.TURN:
		if f.is_boss and not f.angry and f.hp * 100 <= f.max_hp * ANGRY_PCT:
			f.angry = true
			events.append({"type": "angry", "fighter": f.id, "bonus": ANGRY_BONUS})
		events.append_array(_boss_act(f) if f.is_boss else _teacher_act(f))
		_check_round_end(events)
		if phase == Phase.TURN:
			events.append_array(_end_turn())
	return events


## Turns (counting everyone's) until the zone next appears or grows, or -1 if it
## won't (shrinking off, round over, or already as small as it gets). 1 = at the
## start of the next turn.
func turns_until_shrink() -> int:
	if not shrink_on or phase != Phase.TURN or zone_rings >= max_zone_rings():
		return -1
	var next := SHRINK_START
	while next <= _turn_count:
		next += SHRINK_EVERY
	return next - _turn_count


## True if `t` is inside the detention zone (`extra` more rings = where it will be next).
func in_zone(t: Vector2i, extra := 0) -> bool:
	var rings := zone_rings + extra
	if rings <= 0:
		return false
	rings = mini(rings, max_zone_rings())
	return mini(mini(t.x, t.y), mini(width - 1 - t.x, height - 1 - t.y)) < rings


## The zone stops a ring before the very middle, so there's always room to fight
## (Classroom: 2 rings, Hallway: 1).
func max_zone_rings() -> int:
	return maxi(1, (mini(width, height) - 1) / 2 - 1)


## Items that can drop: `base`, plus the Hall Pass when the map shrinks.
func _item_pool(base: Array) -> Array:
	return base + ["hall_pass"] if shrink_on else base


## Drops the mystery box on a free tile, preferring the middle of the map.
func _spawn_box(events: Array) -> void:
	var middle: Array[Vector2i] = []
	var any: Array[Vector2i] = []
	for y in height:
		for x in width:
			var t := Vector2i(x, y)
			if not _walkable(t) or puddles.has(t) or in_zone(t):
				continue
			any.append(t)
			if absi(x * 2 - (width - 1)) <= width / 2:
				middle.append(t)
	var pool := middle if not middle.is_empty() else any
	if pool.is_empty():
		return
	box = pool[_roll(0, pool.size() - 1)]
	events.append({"type": "box", "at": box})


# ---------------------------------------------------------------- the boss

## Every tile the boss stands on.
func footprint(f: Fighter) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-BOSS_RADIUS, BOSS_RADIUS + 1):
		for dx in range(-BOSS_RADIUS, BOSS_RADIUS + 1):
			out.append(f.pos + Vector2i(dx, dy))
	return out


func boss() -> Fighter:
	for f in fighters:
		if f.is_boss:
			return f
	return null


## The Principal's turn: picks one attack and does it. Run by the engine (it's
## deterministic, so every online copy does the same thing).
##  - TEACHERS, HELP ME! sometimes, once none of his teachers are left
##  - Ruler Slam if someone is right next to him (usually)
##  - Megaphone Yell if someone is in line with him (often)
##  - otherwise DETENTION! on one player anywhere
func _boss_act(f: Fighter) -> Array:
	var events: Array = []
	var ring: Array = []  # players right next to him
	var lane: Array = []  # players in line with him (rows/columns he covers)
	var targets: Array = []
	for p in fighters:
		if p.team == BOSS_TEAM or not p.alive():
			continue
		targets.append(p)
		var d := p.pos - f.pos
		var reach := BOSS_RADIUS + 1
		if maxi(absi(d.x), absi(d.y)) == reach:
			ring.append(p)
		if absi(d.x) <= BOSS_RADIUS or absi(d.y) <= BOSS_RADIUS:
			lane.append(p)
	if targets.is_empty():
		return events
	var ctx := {"attacker": f, "dir": Vector2i.ZERO, "super": false, "events": events}
	var rage := ANGRY_BONUS if f.angry else 0
	var names: Dictionary = Characters.BOSSES[boss_id]
	var helpers := fighters.filter(func(o): return o.is_minion)
	if f.own_turns >= 2 and not helpers.is_empty() and helpers.all(func(o): return not o.alive()) \
			and _roll(1, 100) <= SUMMON_CHANCE:
		_summon(f, helpers, events)
	elif not ring.is_empty() and _roll(1, 100) <= 70:
		var tiles: Array = []
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if maxi(absi(dx), absi(dy)) == 2 and _in_bounds(f.pos + Vector2i(dx, dy)):
					tiles.append(f.pos + Vector2i(dx, dy))
		events.append({"type": "boss_attack", "fighter": f.id, "attack": names.ring, "tiles": tiles})
		ctx.ranged = false
		for p in ring:
			if p.alive() and _deal(f, p, RULER_DAMAGE + rage, ctx) and p.alive():
				_knockback(ctx, p, _away(f, p), RULER_PUSH)
	elif not lane.is_empty() and _roll(1, 100) <= 60:
		var tiles: Array = []
		for y in height:
			for x in width:
				var d := Vector2i(x, y) - f.pos
				var inside := absi(d.x) <= BOSS_RADIUS and absi(d.y) <= BOSS_RADIUS
				if not inside and (absi(d.x) <= BOSS_RADIUS or absi(d.y) <= BOSS_RADIUS):
					tiles.append(Vector2i(x, y))
		events.append({"type": "boss_attack", "fighter": f.id, "attack": names.lane, "tiles": tiles})
		ctx.ranged = true
		for p in lane:
			if p.alive() and _deal(f, p, MEGAPHONE_DAMAGE + rage, ctx) and p.alive():
				_knockback(ctx, p, _away(f, p), MEGAPHONE_PUSH)
		if boss_id == "lunch_lady":
			_spill_gravy(f, tiles, events)
	elif boss_id == "lunch_lady":
		# Food Fight!: a tray of food at one player, splashing whoever is next to them
		var p: Fighter = targets[_roll(0, targets.size() - 1)]
		var tiles: Array = [p.pos]
		for d in DIRS:
			if _in_bounds(p.pos + d):
				tiles.append(p.pos + d)
		events.append({"type": "boss_attack", "fighter": f.id, "attack": names.far, "tiles": tiles, "target": p.id})
		ctx.ranged = true
		var splashed := targets.filter(func(o): return o != p and absi(o.pos.x - p.pos.x) + absi(o.pos.y - p.pos.y) == 1)
		_deal(f, p, FOOD_FIGHT_DAMAGE + rage, ctx)
		for o in splashed:
			if o.alive():
				_deal(f, o, FOOD_SPLASH_DAMAGE + rage, ctx)
	else:
		var p: Fighter = targets[_roll(0, targets.size() - 1)]
		events.append({"type": "boss_attack", "fighter": f.id, "attack": names.far, "tiles": [p.pos], "target": p.id})
		ctx.ranged = true
		if _deal(f, p, DETENTION_DAMAGE + rage, ctx) and p.alive():
			_apply_status(ctx, p, "dizzy")
	return events


## Gravy Splash: a few gravy puddles land on free tiles of the splashed lanes.
func _spill_gravy(f: Fighter, lane_tiles: Array, events: Array) -> void:
	var free: Array = lane_tiles.filter(func(t): return _walkable(t) and not puddles.has(t) and not apples.has(t) and t != box)
	var already := puddles.values().filter(func(owner): return owner == f.id).size()
	for i in mini(GRAVY_PUDDLES, GRAVY_MAX - already):
		if free.is_empty():
			return
		var t: Vector2i = free.pop_at(_roll(0, free.size() - 1))
		puddles[t] = f.id
		events.append({"type": "puddle", "fighter": f.id, "at": t, "gravy": true})


## Calls the helpers in: each one appears on a free tile right next to the boss.
func _summon(f: Fighter, helpers: Array, events: Array) -> void:
	var spots: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t := f.pos + Vector2i(dx, dy)
			if maxi(absi(dx), absi(dy)) == 2 and _walkable(t) and not apples.has(t) and t != box:
				spots.append(t)
	var placed := []
	for m in helpers:
		if spots.is_empty():
			break
		var t: Vector2i = spots.pop_at(_roll(0, spots.size() - 1))
		m.reset_for_round()
		m.pos = t
		m.facing = Vector2i.LEFT if t.x < f.pos.x else Vector2i.RIGHT
		placed.append({"fighter": m.id, "at": t})
	events.append({"type": "summon", "fighter": f.id, "teachers": placed})


## A teacher's turn: walk (up to 3 tiles) towards the nearest player and tell
## them off if next to them.
func _teacher_act(f: Fighter) -> Array:
	var events: Array = []
	var targets := fighters.filter(func(o): return o.team != BOSS_TEAM and o.alive())
	if targets.is_empty():
		return events
	var near := func(t: Vector2i) -> int:
		var best := 999
		for o in targets:
			best = mini(best, absi(o.pos.x - t.x) + absi(o.pos.y - t.y))
		return best
	if near.call(f.pos) > 1:
		var came := _walk_area(f, f.pos, f.move)
		var goal := f.pos
		for t in came:
			if apples.has(t) or t == box:
				continue
			if near.call(t) < near.call(goal):
				goal = t
		var steps: Array[Vector2i] = []
		var t := goal
		while t != f.pos:
			steps.push_front(t)
			t = came[t]
		for to in steps:
			var from := f.pos
			f.facing = to - from
			f.pos = to
			events.append({"type": "move", "fighter": f.id, "from": from, "to": to})
	var victim: Fighter = null
	for o in targets:
		if absi(o.pos.x - f.pos.x) + absi(o.pos.y - f.pos.y) == 1 and (victim == null or o.hp < victim.hp):
			victim = o
	if victim != null:
		f.facing = victim.pos - f.pos
		var ctx := {"attacker": f, "dir": f.facing, "super": false, "events": events, "ranged": false}
		events.append({"type": "boss_attack", "fighter": f.id, "attack": Characters.BOSSES[boss_id].minion_attack, "tiles": [victim.pos], "target": victim.id})
		_deal(f, victim, TEACHER_DAMAGE, ctx)
	return events


## The straight direction from the boss out towards `p`.
func _away(f: Fighter, p: Fighter) -> Vector2i:
	var d := p.pos - f.pos
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


## Each time the boss loses another APPLE_EVERY HP, a health apple drops on a
## free tile near him (but not right next to him, where his ruler reaches).
func _drop_apples(f: Fighter, events: Array) -> void:
	while f.alive() and f.max_hp - f.hp >= APPLE_EVERY * (_apples_dropped + 1):
		_apples_dropped += 1
		var spots: Array[Vector2i] = []
		for y in height:
			for x in width:
				var t := Vector2i(x, y)
				var d := maxi(absi(x - f.pos.x), absi(y - f.pos.y))
				if d >= 3 and d <= 4 and _walkable(t) and not apples.has(t) and not puddles.has(t) and t != box:
					spots.append(t)
		if spots.is_empty():
			continue
		var t: Vector2i = spots[_roll(0, spots.size() - 1)]
		apples[t] = APPLE_HEAL
		events.append({"type": "apple", "at": t})


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
	# when the Principal goes down, his teachers run off too
	var b := boss()
	if b != null and not b.alive():
		for m in fighters:
			if m.is_minion and m.alive():
				m.hp = 0
				events.append({"type": "ko", "fighter": m.id})
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
	puddles.clear()
	apples.clear()
	_apples_dropped = 0
	sand.clear()
	box = NO_BOX
	_turn_count = 0
	zone_rings = 0
	for y in height:
		for x in width:
			var ch: String = rows[y][x]
			if Maps.OBSTACLE_HP.has(ch):
				obstacles[Vector2i(x, y)] = {"type": ch, "hp": Maps.OBSTACLE_HP[ch]}
			elif ch == "s":
				sand[Vector2i(x, y)] = true


func _place_fighters() -> void:
	if boss_mode:
		var spawns := _spawn_tiles("1")
		var k := 0
		for f in fighters:
			if f.is_boss or f.is_minion:
				f.pos = Vector2i(map_def.boss[0], map_def.boss[1])
				f.facing = Vector2i.LEFT
			else:
				f.pos = spawns[k % spawns.size()]
				f.facing = Vector2i.RIGHT
				k += 1
		return
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
	if boss_mode:
		# everyone in order, then the boss: plain rotation over the living
		for k in range(1, order.size() + 1):
			var i := (turn_index + k) % order.size()
			if fighters[order[i]].alive():
				turn_index = i
				return
		return
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
	if boss_mode:
		# the players, then his teachers, then the Principal himself
		var list: Array[int] = []
		for f in fighters:
			if not f.is_boss:
				list.append(f.id)
		list.append(boss().id)
		return list
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
	var parts := [phase, round_number, turn_index, move_budget, path.size(), _rng.state, _last_team, _team_last, box, _turn_count, zone_rings, _apples_dropped]
	for f in fighters:
		parts.append_array([f.hp, f.pos.x, f.pos.y, f.meter, f.shield.get("kind", ""), f.shield.get("amount", 0),
			f.dizzy_next, f.rage_turns, f.sugar_active, f.no_attack_next, f.no_attack_now, f.forfeited, f.item, f.guard, f.own_turns, f.ready_at, f.angry, f.zone_safe])
	var tiles := obstacles.keys()
	tiles.sort()
	for t in tiles:
		parts.append_array([t.x, t.y, obstacles[t].hp])
	var fruit := apples.keys()
	fruit.sort()
	for t in fruit:
		parts.append_array([t.x, t.y, apples[t]])
	var wet := puddles.keys()
	wet.sort()
	for t in wet:
		parts.append_array([t.x, t.y, puddles[t]])
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


## Every tile the current fighter can stand on this turn: everything within
## the whole move budget from where the turn started (stepping back undoes a
## step, so these stay reachable after walking). Doesn't include the start tile.
func turn_reachable() -> Array[Vector2i]:
	var f := current()
	var out: Array[Vector2i] = []
	for t in _walk_area(f, turn_start_pos, move_budget):
		if t != turn_start_pos:
			out.append(t)
	return out


## Tiles to step on to get to `t` this turn, or [] if it can't be reached.
## Walks back along this turn's steps first when that's the only (or a
## shorter) way, since stepping back onto the previous tile undoes a step.
func route_to(t: Vector2i) -> Array[Vector2i]:
	var f := current()
	if t == f.pos:
		return []
	var steps: Array[Vector2i] = [turn_start_pos]
	steps.append_array(path)  # steps[k] = where the fighter stood after k steps
	var back: Array[Vector2i] = []
	for k in range(path.size(), -1, -1):
		if k < path.size():
			back.append(steps[k])  # step back onto the previous tile
		var came := _walk_area(f, steps[k], move_budget - k)
		if came.has(t):
			var fwd: Array[Vector2i] = []
			var at := t
			while at != steps[k]:
				fwd.push_front(at)
				at = came[at]
			return back + fwd
	return []


## Breadth-first walk from `from` for `moves` steps. Returns tile -> the tile it
## was reached from. The fighter's own tile doesn't block.
func _walk_area(f: Fighter, from: Vector2i, moves: int) -> Dictionary:
	var came := {from: from}
	var frontier: Array[Vector2i] = [from]
	for i in moves:
		var next: Array[Vector2i] = []
		for p in frontier:
			for d in DIRS:
				var n: Vector2i = p + d
				if came.has(n) or not _in_bounds(n) or obstacles.has(n):
					continue
				var o := _fighter_at(n)
				if o != null and o != f:
					continue
				came[n] = p
				next.append(n)
		frontier = next
	return came


## Shortest walk for the current fighter to `t` within the moves left this
## turn, as the list of tiles to step on, or [] if it can't get there.
## Tiles in `avoid` (other than `t`) aren't walked over.
func path_to(t: Vector2i, avoid := {}) -> Array[Vector2i]:
	var f := current()
	var left := move_budget - path.size()
	var came := {f.pos: f.pos}
	var frontier: Array[Vector2i] = [f.pos]
	for i in left:
		var next: Array[Vector2i] = []
		for p in frontier:
			for d in DIRS:
				var n: Vector2i = p + d
				if came.has(n) or not _walkable(n) or (avoid.has(n) and n != t):
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
	var atk := slot_attack(f, slot)
	if atk.is_empty():
		return []
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
				if obstacles.has(t) or (o != null and o.team != f.team and not sand.has(t)):
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
		"spill":
			add.call(f.pos + dir, "dizzy")
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


## For attacks with a cooldown: how many more of the fighter's own turns until it
## can be used again (0 = ready). Counts the current turn if it's theirs.
func turns_until_ready(f: Fighter, slot: int) -> int:
	return maxi(0, int(f.ready_at.get(slot, 0)) - f.own_turns)


## Short reason an attack can't be used right now, or "" if it can.
func attack_blocked_reason(fighter_id: int, slot: int) -> String:
	var f := fighters[fighter_id]
	if f.no_attack_now:
		return "cannot_attack"
	if slot == ITEM_SLOT and f.item == "":
		return "no_item"
	if turns_until_ready(f, slot) > 0:
		return "cooldown"
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
		if not f.alive():
			continue
		if f.pos == t:
			return f
		if f.is_boss and absi(t.x - f.pos.x) <= BOSS_RADIUS and absi(t.y - f.pos.y) <= BOSS_RADIUS:
			return f
	return null


func _walkable(t: Vector2i) -> bool:
	return _in_bounds(t) and not obstacles.has(t) and _fighter_at(t) == null


func _ok(events: Array) -> Dictionary:
	return {"ok": true, "events": events}


func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "events": []}
