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
			for dir in Battle.DIRS:
				var dists := [0]
				if atk.type == "lob":
					dists = range(atk.min_range, atk.max_range + 1)
				for dist in dists:
					var sc := _score(b, f, atk, dir, dist)
					if sc > 0.0 and noise > 0.0:
						sc += randf() * noise
					if slot == Battle.SUPER_SLOT:
						sc += 5.0
					if slot == Battle.ITEM_SLOT and sc > 0.0:
						sc += ITEM_BONUS
					best_any_attack = maxf(best_any_attack, sc)
					if sc > best.score:
						best = {"score": sc, "pos": p, "intents": [{"type": "attack", "slot": slot, "dir": dir, "dist": dist}]}
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

	# Water bottle: spill a puddle toward an enemy who is a few tiles away.
	if f.item == "water" and best.score < 12.0 and b.attack_blocked_reason(f.id, Battle.ITEM_SLOT) == "":
		for o in enemies:
			var gap: Vector2i = o.pos - home
			var dist := absi(gap.x) + absi(gap.y)
			var dir := Vector2i(signi(gap.x), 0) if absi(gap.x) >= absi(gap.y) else Vector2i(0, signi(gap.y))
			if dist >= 2 and dist <= 4 and b._walkable(home + dir) and not b.puddles.has(home + dir):
				best = {"score": 12.0, "pos": home, "intents": [{"type": "attack", "slot": Battle.ITEM_SLOT, "dir": dir}]}
				break
	if best.has("intents"):
		return {"path": b.path_to(best.pos), "intents": best.intents}
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
			return {"path": b.path_to(spot), "intents": [{"type": "attack", "slot": Battle.ITEM_SLOT, "dir": dir}]}
	return {"path": b.path_to(_toward(b, enemies)), "intents": [{"type": "end_turn"}]}


## Expected damage to enemies (plus a bonus for knock-outs) if `atk` were used now.
static func _score(b: Battle, f, atk: Dictionary, dir: Vector2i, dist: int) -> float:
	var tiles := b.preview(f.id, _slot_of(f, atk), dir, dist)
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


static func _damage(atk: Dictionary, kind: String, run: int) -> float:
	match atk.type:
		"shockwave":
			return float(atk.inner_damage if kind == "hit" else atk.outer_damage)
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


## The reachable tile closest to an enemy (where to walk when nothing can hit).
static func _toward(b: Battle, enemies: Array) -> Vector2i:
	var f := b.current()
	var best := f.pos
	var best_d := _nearest(f.pos, enemies)
	for t in b.reachable_tiles():
		var d := _nearest(t, enemies)
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
			return {"path": b.path_to(_toward(b, enemies)), "intents": [{"type": "end_turn"}]}
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
