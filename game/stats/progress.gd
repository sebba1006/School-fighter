extends RefCounted
## Fighter levels, saved on this device (user://progress.cfg): VS CPU, boss and
## online matches give XP to the fighter you played (local battles don't, you
## could just let the other side win), up to level 100 (about 140 matches), and
## levels unlock skins and name tag colors for that fighter.

const PATH := "user://progress.cfg"
const MAX_LEVEL := 100

## XP for one match: a base, plus winning, damage, KOs and beating a boss.
const XP_BASE := 40
const XP_WIN := 40
const XP_PER_DAMAGE := 0.25
const XP_DAMAGE_MAX := 40  # damage XP stops here (boss fights deal a LOT of damage)
const XP_PER_KO := 15
const XP_BOSS_WIN := 40
const XP_MAX_PER_MATCH := 160

## Skins: 0 is the normal look; the rest unlock at these levels (the last one is gold).
const SKIN_LEVELS := [1, 25, 50, 75, 100]
const SKIN_NAMES := ["CLASSIC", "STYLE 2", "STYLE 3", "STYLE 4", "GOLDEN"]

## Name tag colors over your fighter, and the level each one unlocks at.
const TAGS := [
	{"id": "white", "name": "WHITE", "level": 1, "color": Color("eef2e6")},
	{"id": "blue", "name": "BLUE", "level": 5, "color": Color("6b9be0")},
	{"id": "green", "name": "GREEN", "level": 10, "color": Color("74bf63")},
	{"id": "red", "name": "RED", "level": 35, "color": Color("e8575e")},
	{"id": "purple", "name": "PURPLE", "level": 60, "color": Color("b08cf0")},
	{"id": "gold", "name": "GOLD", "level": 90, "color": Color("f2c14e")},
	{"id": "rainbow", "name": "RAINBOW", "level": 100, "color": Color("ffffff")},
]

## Set to false by tests and tools so they don't touch the real file.
static var enabled := true


## XP needed to go from `level` to the next one (82 at level 1, 278 at 99):
## about 140 matches to level 100.
static func xp_to_next(level: int) -> int:
	return 80 + 2 * level


## Total XP needed to reach `level` from level 1.
static func total_for(level: int) -> int:
	var sum := 0
	for l in range(1, mini(level, MAX_LEVEL)):
		sum += xp_to_next(l)
	return sum


## {"level", "into" (XP into this level), "need" (XP for the next level; 0 at max)}.
static func level_info(xp: int) -> Dictionary:
	var level := 1
	var left := xp
	while level < MAX_LEVEL and left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	if level >= MAX_LEVEL:
		return {"level": MAX_LEVEL, "into": 0, "need": 0}
	return {"level": level, "into": left, "need": xp_to_next(level)}


static func xp_for_match(won: bool, damage: int, kos: int, boss_win: bool) -> int:
	var xp := XP_BASE + mini(int(damage * XP_PER_DAMAGE), XP_DAMAGE_MAX) + kos * XP_PER_KO
	if won:
		xp += XP_WIN
	if boss_win:
		xp += XP_BOSS_WIN
	return mini(xp, XP_MAX_PER_MATCH)


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	if enabled:
		cfg.load(PATH)
	return cfg


static func xp(char_id: String) -> int:
	return int(_load().get_value("xp", char_id, 0))


static func level(char_id: String) -> int:
	return level_info(xp(char_id)).level


## Gives XP to a fighter. Returns {"from": old level, "to": new level, "xp": gained}.
static func add_xp(char_id: String, amount: int) -> Dictionary:
	var cfg := _load()
	var before := int(cfg.get_value("xp", char_id, 0))
	var from: int = level_info(before).level
	var after := mini(before + maxi(0, amount), total_for(MAX_LEVEL))
	cfg.set_value("xp", char_id, after)
	if enabled:
		cfg.save(PATH)
	return {"from": from, "to": level_info(after).level, "xp": after - before}


static func skin_unlocked(char_id: String, skin: int) -> bool:
	return skin >= 0 and skin < SKIN_LEVELS.size() and level(char_id) >= SKIN_LEVELS[skin]


static func tag_by_id(id: String) -> Dictionary:
	for t in TAGS:
		if t.id == id:
			return t
	return TAGS[0]


static func tag_unlocked(char_id: String, id: String) -> bool:
	return level(char_id) >= tag_by_id(id).level


## The skin / tag color picked for a fighter (falls back to the default if it
## isn't unlocked any more, e.g. after a reset).
static func chosen_skin(char_id: String) -> int:
	var s := int(_load().get_value("skin", char_id, 0))
	return s if skin_unlocked(char_id, s) else 0


static func chosen_tag(char_id: String) -> String:
	var t := str(_load().get_value("tag", char_id, "white"))
	return t if tag_unlocked(char_id, t) else "white"


static func choose_skin(char_id: String, skin: int) -> void:
	if not enabled or not skin_unlocked(char_id, skin):
		return
	var cfg := _load()
	cfg.set_value("skin", char_id, skin)
	cfg.save(PATH)


static func choose_tag(char_id: String, id: String) -> void:
	if not enabled or not tag_unlocked(char_id, id):
		return
	var cfg := _load()
	cfg.set_value("tag", char_id, id)
	cfg.save(PATH)


## What reaching a level unlocks, as short lines for the level-up message.
static func unlocks_at(level: int) -> Array:
	var out := []
	var s := SKIN_LEVELS.find(level)
	if s > 0:
		out.append("SKIN: " + SKIN_NAMES[s])
	for t in TAGS:
		if t.level == level and t.level > 1:
			out.append("NAME TAG: " + t.name)
	return out


static func reset() -> void:
	if enabled:
		ConfigFile.new().save(PATH)
