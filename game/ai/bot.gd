extends RefCounted
## A simple computer player. For the fighter whose turn it is, it tries every
## tile it can walk to and every attack in every direction, scores how much
## damage each would do to enemies, and picks the best. If nothing can hit,
## it walks toward the nearest enemy. Used for balance testing (and later a
## "play vs computer" mode).
##
## plan(battle) -> {"path": [tiles to step on], "intents": [intents after walking]}

const Battle = preload("res://rules/battle.gd")

const KO_BONUS := 40.0
## Items are a bonus (lost at the end of the round), so prefer using them.
const ITEM_BONUS := 6.0
## CPU difficulty for VS CPU fights. `noise` makes it pick worse moves more
## often; `lazy` is the chance it only walks and skips attacking that turn.
const LEVELS := {
	"easy": {"noise": 25.0, "lazy": 0.3},
	"normal": {"noise": 6.0, "lazy": 0.0},
	"hard": {"noise": 0.0, "lazy": 0.0},
}
const SELF_TYPES := ["self_rage", "self_block", "self_sugar"]
## Boss fights: grab a health apple in reach once below APPLE_WANT of max HP
## (leaving them for hurt players otherwise), and walk over to one (if there's
## nothing to hit) once below APPLE_HURT.
const APPLE_WANT := 0.7
const APPLE_HURT := 0.5


## `noise` adds a little randomness to each option's score, so the bot doesn't
## always pick the exact same move (more like a real player).
static func plan(b: Battle, noise := 0.0) -> Dictionary:
	var f := b.current()
	var enemies := []
	for o in b.fighters:
		if o.alive() and o.team != f.team:
			enemies.append(o)
	if enemies.is_empty():
		return {"path": [], "intents": [{"type": "end_turn"}]}

	var spots: Array[Vector2i] = [f.pos]
	spots.append_array(b.reachable_tiles())
	# Hurt and an apple in reach: eat it this turn, attacking from there if possible.
	var apple := _apple_in_reach(b, f, spots)
	if apple != NO_TILE:
		spots = [apple]
	elif not b.apples.is_empty() or not b.puddles.is_empty():
		# leave apples for whoever needs them, and keep out of enemy puddles
		spots = spots.filter(func(t): return t == f.pos or not _path(b, t).is_empty())
	var home := f.pos
	var best := {"score": 0.0}
	var best_any_attack := 0.0
	for p in spots:
		# only bother with spots near an enemy
		if _nearest(p, enemies) > 7:
			continue
		f.pos = p
		for slot in Battle.ITEM_SLOT + 1:
			if b.attack_blocked_reason(f.id, slot) != "":
				continue
			var atk := b.slot_attack(f, slot)
			if SELF_TYPES.has(atk.type) or atk.type == "spill":
				continue
			# Bomba: try dropping it on each enemy in range (and next to them)
			var aims: Array = [null]
			if atk.type == "bomb":
				aims = _bomb_aims(b, f, atk, enemies)
			for at in aims:
				for dir in ([Vector2i.RIGHT] if at != null else Battle.DIRS):
					var dists := [0]
					if atk.type == "lob":
						dists = range(atk.min_range, atk.max_range + 1)
					for dist in dists:
						var sc := _score(b, f, atk, dir, dist, at)
						if sc > 0.0 and noise > 0.0:
							sc += randf() * noise
						if slot == Battle.SUPER_SLOT:
							sc += 5.0
						if slot == Battle.ITEM_SLOT and sc > 0.0:
							sc += ITEM_BONUS
						if sc > 0.0 and b.in_zone(p, 1):
							sc -= Battle.ZONE_DAMAGE  # would start next turn in detention
						best_any_attack = maxf(best_any_attack, sc)
						if sc > best.score:
							best = {"score": sc, "pos": p, "intents": [{"type": "attack", "slot": slot, "dir": dir, "dist": dist, "at": at}]}
	f.pos = home

	# buffs
	for slot in 4:
		var atk: Dictionary = f.def.attacks[slot]
		if not SELF_TYPES.has(atk.type) or b.attack_blocked_reason(f.id, slot) != "":
			continue
		match atk.type:
			"self_sugar":
				# free action: worth it before a good hit
				if best.score >= 9.0 and best.has("intents"):
					var boosted: float = best.score * atk.multiplier - 6.0
					if boosted > best.score:
						best.score = boosted
						best.intents = [{"type": "attack", "slot": slot}] + best.intents
			"self_rage":
				if best.score < 6.0 and _nearest(home, enemies) <= 5:
					best = {"score": 6.0, "pos": _toward(b, enemies), "intents": [{"type": "attack", "slot": slot}]}
			"self_block":
				if best.score < 8.0 and _nearest(home, enemies) <= 3:
					best = {"score": 8.0, "pos": home, "intents": [{"type": "attack", "slot": slot}]}

	# Melee / Ranged Guard: put it up when enemies are close and there's no good hit.
	var hurt := f.hp * 2 < f.max_hp
	if Battle.BOX_ITEMS.has(f.item) and (best.score < 14.0 or hurt) and best.score < KO_BONUS and _nearest(home, enemies) <= 4 \
			and b.attack_blocked_reason(f.id, Battle.ITEM_SLOT) == "":
		best = {"score": 14.0, "pos": home, "intents": [{"type": "attack", "slot": Battle.ITEM_SLOT}]}
	# Hall Pass: use it when standing where the detention zone will be next turn.
	if f.item == "hall_pass" and f.zone_safe == 0 and best.score < KO_BONUS and b.in_zone(home, 1) \
			and b.attack_blocked_reason(f.id, Battle.ITEM_SLOT) == "":
		best = {"score": 16.0, "pos": home, "intents": [{"type": "attack", "slot": Battle.ITEM_SLOT}]}
	# Mystery box in reach and nothing great to do: go get it.
	if b.box != Battle.NO_BOX and best.score < 12.0 and f.item == "" and not _path(b, b.box).is_empty():
		return {"path": _path(b, b.box), "intents": [{"type": "end_turn"}]}
	# Water bottle: spill a puddle toward an enemy who is a few tiles away.
	if f.item == "water" and best.score < 12.0 and b.attack_blocked_reason(f.id, Battle.ITEM_SLOT) == "":
		for o in enemies:
			var gap: Vector2i = o.pos - home
			var dist := absi(gap.x) + absi(gap.y)
			var dir := Vector2i(signi(gap.x), 0) if absi(gap.x) >= absi(gap.y) else Vector2i(0, signi(gap.y))
			if dist >= 2 and dist <= 4 and b._walkable(home + dir) and not b.puddles.has(home + dir):
				best = {"score": 12.0, "pos": home, "intents": [{"type": "attack", "slot": Battle.ITEM_SLOT, "dir": dir}]}
				break
	if apple != NO_TILE and best.score < KO_BONUS:
		return {"path": _path(b, apple), "intents": best.get("intents", [{"type": "end_turn"}])}
	if best.has("intents"):
		return {"path": _path(b, best.pos), "intents": best.intents}
	# Badly hurt with nothing to hit: head for the nearest apple.
	if not b.apples.is_empty() and f.hp < f.max_hp * APPLE_HURT:
		return {"path": _path(b, _toward_tile(b, b.apples.keys())), "intents": [{"type": "end_turn"}]}
	# Nothing to hit: with a water bottle, walk closer and spill it toward the enemy.
	if f.item == "water" and b.attack_blocked_reason(f.id, Battle.ITEM_SLOT) == "":
		var spot := _toward(b, enemies)
		var target: Vector2i = enemies[0].pos
		for o in enemies:
			if _dist(spot, o.pos) < _dist(spot, target):
				target = o.pos
		var d := target - spot
		var dir := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
		if _dist(spot, target) <= 7 and dir != Vector2i.ZERO and b._walkable(spot + dir):
			return {"path": _path(b, spot), "intents": [{"type": "attack", "slot": Battle.ITEM_SLOT, "dir": dir}]}
	return {"path": _path(b, _toward(b, enemies)), "intents": [{"type": "end_turn"}]}


## Expected damage to enemies (plus a bonus for knock-outs) if `atk` were used now.
static func _score(b: Battle, f, atk: Dictionary, dir: Vector2i, dist: int, at = null) -> float:
	var tiles := b.preview(f.id, _slot_of(f, atk), dir, dist, at)
	var run := 0
	for t in tiles:
		if t.kind == "path":
			run += 1
	var total := 0.0
	for t in tiles:
		if t.kind == "path":
			continue
		var o = b._fighter_at(t.pos)
		if o == null or o == f or o.team == f.team:
			continue
		if Battle.RANGED_TYPES.has(atk.type) and b.sand.has(t.pos):
			continue  # hiding in the sandbox
		var dmg := _damage(atk, t.kind, run)
		if f.def.get("passive") == "last_stand" and f.hp * 100 < f.max_hp * Battle.LAST_STAND_PERCENT:
			dmg += Battle.LAST_STAND_BONUS
		if f.rage_turns > 0:
			dmg += f.rage_bonus
		if t.kind == "dizzy":
			dmg += 3.0
		if atk.get("knockback", 0) > 0 or atk.has("knockback_max"):
			dmg += 2.0
		if o.shield.get("kind") == "block":
			dmg = 1.0
		total += dmg
		if dmg >= o.hp:
			total += KO_BONUS
	if atk.type == "leap" and total > 0:
		total -= atk.self_damage
	return total


## Bomba targets worth trying: every enemy in range, and the tiles next to
## them (to catch two at once).
static func _bomb_aims(b: Battle, f, atk: Dictionary, enemies: Array) -> Array:
	var tiles := b.bomb_tiles(f, atk)
	var out := []
	for e in enemies:
		for d in [Vector2i.ZERO] + Array(Battle.AROUND):
			var t: Vector2i = e.pos + d
			if tiles.has(t) and not out.has(t):
				out.append(t)
	return out


static func _damage(atk: Dictionary, kind: String, run: int) -> float:
	match atk.type:
		"shockwave":
			return float(atk.inner_damage if kind == "hit" else atk.outer_damage)
		"bomb":
			return float(atk.center_damage if kind == "hit" else atk.ring_damage)
		"dash":
			return float(atk.damage + atk.get("damage_per_tile", 0) * run)
	if atk.has("damage"):
		return float(atk.damage * atk.get("hits", 1))
	return (atk.damage_min + atk.damage_max) / 2.0


static func _dist(a: Vector2i, c: Vector2i) -> int:
	return absi(a.x - c.x) + absi(a.y - c.y)


static func _slot_of(f, atk: Dictionary) -> int:
	if Battle.ITEMS.has(atk.get("id", "")) and Battle.ITEMS[atk.id] == atk:
		return Battle.ITEM_SLOT
	if atk == f.def["super"]:
		return Battle.SUPER_SLOT
	return f.def.attacks.find(atk)


static func _nearest(p: Vector2i, enemies: Array) -> int:
	var best := 999
	for o in enemies:
		best = mini(best, absi(o.pos.x - p.x) + absi(o.pos.y - p.y))
	return best


const NO_TILE := Vector2i(-99, -99)


## Path to `t`, going around health apples unless this fighter wants one
## ([] if there's no way around: pick somewhere else).
static func _path(b: Battle, t: Vector2i) -> Array[Vector2i]:
	var f := b.current()
	var avoid := _wet(b, f)  # never walk into an enemy's puddle (you'd slip)
	if not b.apples.is_empty() and f.hp >= f.max_hp * APPLE_WANT:
		if b.apples.has(t):
			return [] as Array[Vector2i]
		avoid.merge(b.apples)
	if avoid.has(t):
		return [] as Array[Vector2i]
	return b.path_to(t, avoid) if not avoid.is_empty() else b.path_to(t)


## Puddles `f` would slip in (enemies' water, the Lunch Lady's gravy).
static func _wet(b: Battle, f) -> Dictionary:
	var out := {}
	for t in b.puddles:
		if b.fighters[b.puddles[t]].team != f.team:
			out[t] = true
	return out


## The closest health apple this fighter can walk onto this turn, if it's
## missing enough HP to want one (NO_TILE if not).
static func _apple_in_reach(b: Battle, f, spots: Array[Vector2i]) -> Vector2i:
	if b.apples.is_empty() or f.hp >= f.max_hp * APPLE_WANT:
		return NO_TILE
	var best := NO_TILE
	var best_steps := 999
	for t in b.apples:
		if not spots.has(t):
			continue
		var steps := _path(b, t).size()
		if steps < best_steps:
			best = t
			best_steps = steps
	return best


## The reachable tile closest to any of `targets`.
static func _toward_tile(b: Battle, targets: Array) -> Vector2i:
	var f := b.current()
	var best := f.pos
	var best_d := 999
	for t in [f.pos] + Array(b.reachable_tiles()):
		for g in targets:
			var d := absi(g.x - t.x) + absi(g.y - t.y)
			if d < best_d:
				best = t
				best_d = d
	return best


## The reachable tile closest to an enemy (where to walk when nothing can hit).
static func _toward(b: Battle, enemies: Array) -> Vector2i:
	var f := b.current()
	var best := f.pos
	var best_d := _nearest(f.pos, enemies) + (20 if b.in_zone(f.pos, 1) else 0)
	var skip_apples := f.hp >= f.max_hp * APPLE_WANT
	for t in b.reachable_tiles():
		if (skip_apples and not b.apples.is_empty() or not b.puddles.is_empty()) and _path(b, t).is_empty():
			continue  # only reachable over an apple or through a puddle
		var d := _nearest(t, enemies) + (20 if b.in_zone(t, 1) else 0)
		if d < best_d and d >= 1:
			best = t
			best_d = d
	return best


## plan() for a CPU difficulty level ("easy", "normal" or "hard").
static func plan_level(b: Battle, level: String) -> Dictionary:
	var cfg: Dictionary = LEVELS.get(level, LEVELS.normal)
	if randf() < cfg.lazy:
		var f := b.current()
		var enemies := []
		for o in b.fighters:
			if o.alive() and o.team != f.team:
				enemies.append(o)
		if not enemies.is_empty():
			return {"path": _path(b, _toward(b, enemies)), "intents": [{"type": "end_turn"}]}
	return plan(b, cfg.noise)


## Plays one whole turn for the current fighter using plan().
static func play_turn(b: Battle, noise := 0.0) -> void:
	var f := b.current()
	var p := plan(b, noise)
	for t in p.path:
		var r := b.apply(f.id, {"type": "move", "dir": t - b.current().pos})
		if not r.ok:
			break
	for intent in p.intents:
		if b.phase != Battle.Phase.TURN or b.current().id != f.id:
			return
		var r := b.apply(f.id, intent)
		if not r.ok:
			break
	if b.phase == Battle.Phase.TURN and b.current().id == f.id:
		b.apply(f.id, {"type": "end_turn"})
