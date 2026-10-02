extends RefCounted
## Achievements, saved on this device (user://achievements.cfg), listed from
## easiest to hardest. Every kind of match counts (online, local, VS CPU) except
## the online-only one.
##
## stats/achievement_tracker.gd watches each match and counts the progress.

const Battle = preload("res://rules/battle.gd")
const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")

const PATH := "user://achievements.cfg"

## counter: progress key counted up to goal. set: progress key holding a list
## (goal = how many fighters / maps there are).
const LIST := [
	{"id": "first_win", "name": "First Blood", "desc": "Win your first match"},
	{"id": "teamwork", "name": "Teamwork", "desc": "Win a 2v2"},
	{"id": "last_one", "name": "Last One Standing", "desc": "Win a 1v1v1v1"},
	{"id": "item_master", "name": "Item Master", "desc": "KO someone with an item"},
	{"id": "slippery", "name": "Slippery", "desc": "Make someone slip in your puddle"},
	{"id": "combo", "name": "Combo Breaker", "desc": "Deal 30+ damage in one turn"},
	{"id": "coolness", "name": "Coolness", "desc": "KO someone with a super"},
	{"id": "comeback", "name": "Comeback Kid", "desc": "Win a round with less than 20 HP left"},
	{"id": "box_hunter", "name": "Box Hunter", "desc": "Grab 5 mystery boxes", "counter": "boxes", "goal": 5},
	{"id": "super_star", "name": "Super Star", "desc": "Use 10 supers", "counter": "supers", "goal": 10},
	{"id": "wall_slam", "name": "Wall Slam", "desc": "Slam enemies into things 10 times", "counter": "slams", "goal": 10},
	{"id": "survivor", "name": "Survivor", "desc": "Win a round on a shrinking map without detention damage"},
	{"id": "cpu_crusher", "name": "CPU Crusher", "desc": "Beat a Hard CPU"},
	{"id": "locker_breaker", "name": "Locker Breaker", "desc": "Break 25 lockers", "counter": "lockers", "goal": 25},
	{"id": "champion", "name": "Fighting Champion", "desc": "Win 5 1v1v1v1s", "counter": "ffa4_wins", "goal": 5},
	{"id": "food_fight", "name": "Food Fight", "desc": "Win on the Cafeteria 10 times", "counter": "cafeteria_wins", "goal": 10},
	{"id": "world_tour", "name": "World Tour", "desc": "Win on every map", "set": "maps"},
	{"id": "main_character", "name": "Main Character", "desc": "Win 10 matches with the same fighter", "counter": "best_fighter_wins", "goal": 10},
	{"id": "all_fighters", "name": "Jack of All Trades", "desc": "Win with every fighter", "set": "fighters"},
	{"id": "online_legend", "name": "Online Legend", "desc": "Win 25 online matches", "counter": "online_wins", "goal": 25},
]
const COMBO_DAMAGE := 30
const COMEBACK_HP := 20

## Set to false by tests and tools so they don't touch the real file.
static var enabled := true


## Saved progress: {"unlocked": {id: true}, "counters": {key: n}, "sets": {key: [values]}}
static func load_data() -> Dictionary:
	var data := {"unlocked": {}, "counters": {}, "sets": {}}
	if not enabled:
		return data
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in data:
			data[key] = cfg.get_value("achievements", key, data[key])
	return data


static func save_data(data: Dictionary) -> void:
	if not enabled:
		return
	var cfg := ConfigFile.new()
	for key in data:
		cfg.set_value("achievements", key, data[key])
	cfg.save(PATH)


static func reset() -> void:
	save_data({"unlocked": {}, "counters": {}, "sets": {}})


static func by_id(id: String) -> Dictionary:
	for a in LIST:
		if a.id == id:
			return a
	return {}


## How far along an achievement is: [done, goal] (goal 1 for one-off ones).
static func progress(data: Dictionary, a: Dictionary) -> Array:
	if data.unlocked.has(a.id):
		var g := goal(a)
		return [g, g]
	if a.has("counter"):
		return [mini(int(data.counters.get(a.counter, 0)), a.goal), a.goal]
	if a.has("set"):
		return [data.sets.get(a.set, []).size(), goal(a)]
	return [0, 1]


static func goal(a: Dictionary) -> int:
	if a.has("goal"):
		return a.goal
	match a.get("set", ""):
		"maps":
			return Maps.ALL.size()
		"fighters":
			return Characters.ALL.size()
	return 1


static func unlocked_count(data: Dictionary) -> int:
	return data.unlocked.size()
