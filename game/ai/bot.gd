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
		for slot in 5:
			if b.attack_blocked_reason(f.id, slot) != "":
				continue
			var atk: Dictionary = f.def["super"] if slot == Battle.SUPER_SLOT else f.def.attacks[slot]
			if SELF_TYPES.has(atk.type):
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

	if best.has("intents"):
		return {"path": b.path_to(best.pos), "intents": best.intents}
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
		var dmg := _damage(atk, t.kind, run)
		if f.def.get("passive") == "last_stand" and f.hp * 100 < f.max_hp * Battle.LAST_STAND_PERCENT:
			dmg += Battle.LAST_STAND_BONUS
		if f.rage_turns > 0:
			dmg += f.rage_bonus
		if t.kind == "dizzy":
			dmg += 3.0
		if atk.get("knockback", 0) > 0:
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
		return float(atk.damage)
	return (atk.damage_min + atk.damage_max) / 2.0


static func _slot_of(f, atk: Dictionary) -> int:
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
