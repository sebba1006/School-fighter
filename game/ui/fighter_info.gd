extends RefCounted
## Text describing fighters and attacks, shown on the attack cards, the
## character select screens and the how-to-play screen.

const Characters = preload("res://rules/characters.gd")


## Short damage summary for one attack, e.g. "8 DMG, PUSH 2".
static func attack_info(atk: Dictionary) -> String:
	var parts := []
	match atk.type:
		"self_rage":
			return "+%d DMG, 1-%d TURNS" % [atk.bonus, atk.turns_max]
		"self_block":
			return "BLOCKS NEXT HIT" + (", %d-TURN WAIT" % atk.cooldown if atk.has("cooldown") else "")
		"self_sugar":
			return "X%s DMG THIS TURN" % str(atk.multiplier)
		"self_pass":
			return "NO DETENTION DMG %d TURNS" % atk.turns
		"shockwave":
			parts.append("%d / %d DMG" % [atk.inner_damage, atk.outer_damage])
		"projectile" when atk.has("damage_near"):
			return "%d CLOSE - %d FAR" % [atk.damage_near, atk.damage_far]
		"heal":
			return "+%d SELF, +%d-%d ALLY" % [atk.self_heal, atk.heal_min, atk.heal_max]
		"ray":
			parts.append("%d DMG ROW + BURN" % atk.damage)
		"bomb":
			parts.append("%d/%d DMG 3X3" % [atk.center_damage, atk.ring_damage])
		"dash":
			var most: int = atk.damage + atk.get("damage_per_tile", 0) * atk["range"]
			parts.append(("%d-%d DMG" % [atk.damage, most]) if most != atk.damage else ("%d DMG" % atk.damage))
		"leap":
			parts.append("%d DMG" % atk.damage)
			parts.append("-%d HP" % atk.self_damage)
		_:
			if atk.get("hits", 1) > 1:
				parts.append("%dX%d DMG" % [atk.hits, atk.damage])
			elif atk.has("damage"):
				parts.append("%d DMG" % atk.damage)
			else:
				parts.append("%d-%d DMG" % [atk.damage_min, atk.damage_max])
	if atk.has("range") and atk.type in ["projectile", "line"]:
		parts.append("%d TILES" % atk["range"])
	if atk.type == "lob":
		parts.append("%d-%d AWAY" % [atk.min_range, atk.max_range])
	if atk.get("knockback", 0) > 0:
		parts.append("PUSH %d" % atk.knockback)
	elif atk.has("knockback_max"):
		parts.append("PUSH %d-%d" % [atk.knockback_min, atk.knockback_max])
	if atk.get("status", "") == "dizzy" or atk.get("outer_status", "") == "dizzy":
		parts.append("DIZZY")
	return ", ".join(parts)


## A few lines about a fighter: stats, every attack with its damage, the super.
static func summary(id: String) -> String:
	var c: Dictionary = Characters.ALL[id]
	var lines := ["%s   HP %d   MOVES %d" % [c.name.to_upper(), c.hp, c.move]]
	var row := []
	for i in c.attacks.size():
		var a: Dictionary = c.attacks[i]
		row.append("%d %s: %s" % [i + 1, a.name.to_upper(), attack_info(a)])
		if row.size() == 2:
			lines.append("   ".join(row))
			row = []
	if not row.is_empty():
		lines.append("   ".join(row))
	var s: Dictionary = c["super"]
	var extra := "   PASSIVE: +3 DMG BELOW 35% HP" if c.get("passive") == "last_stand" else ""
	lines.append("SUPER %s: %s%s" % [s.name.to_upper(), attack_info(s), extra])
	return "\n".join(lines)
