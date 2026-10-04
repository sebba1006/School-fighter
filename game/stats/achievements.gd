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
	{"id": "survivor", "name": "Survivor", "desc": "Win a shrinking-map round with no detention damage"},
	{"id": "cpu_crusher", "name": "CPU Crusher", "desc": "Beat a Hard CPU"},
	{"id": "locker_breaker", "name": "Locker Breaker", "desc": "Break 25 lockers", "counter": "lockers", "goal": 25},
	{"id": "champion", "name": "Fighting Champion", "desc": "Win 5 1v1v1v1s", "counter": "ffa4_wins", "goal": 5},
	{"id": "food_fight", "name": "Food Fight", "desc": "Win on the Cafeteria 10 times", "counter": "cafeteria_wins", "goal": 10},
	{"id": "world_tour", "name": "World Tour", "desc": "Win on every map", "set": "maps"},
	{"id": "main_character", "name": "Main Character", "desc": "Win 10 matches with the same fighter", "counter": "best_fighter_wins", "goal": 10},
	{"id": "all_fighters", "name": "Jack of All Trades", "desc": "Win with every fighter", "set": "fighters"},
	{"id": "online_legend", "name": "Online Legend", "desc": "Win 25 online matches", "counter": "online_wins", "goal": 25},
	# boss league: collecting trophies from beating the Principal
	{"id": "boss_slayer", "name": "Boss Slayer", "desc": "Win your first trophy", "set": "trophies", "goal": 1},
	{"id": "not_a_scratch", "name": "Not A Scratch", "desc": "Beat a boss with nobody KO'd"},
	{"id": "trophy_collector", "name": "Trophy Collector", "desc": "Collect 3 trophies", "set": "trophies", "goal": 3},
	{"id": "trophy_hunter", "name": "Trophy Hunter", "desc": "Collect 6 trophies", "set": "trophies", "goal": 6},
	{"id": "trophy_master", "name": "Trophy Master", "desc": "Collect every trophy", "set": "trophies"},
	# legend league: the later bosses (7 achievements)
	{"id": "slip_n_slide", "name": "Slip 'n' Slide", "desc": "Slip in the Lunch Lady's gravy"},
	{"id": "lunch_is_served", "name": "Lunch Is Served", "desc": "Beat the Lunch Lady"},
	{"id": "apple_a_day", "name": "Apple A Day", "desc": "Eat 10 health apples", "counter": "apples", "goal": 10},
	{"id": "teachers_pet", "name": "Teacher's Pet", "desc": "KO 10 boss helpers", "counter": "helper_kos", "goal": 10},
	{"id": "gym_class_hero", "name": "Gym Class Hero", "desc": "Beat the Gym Teacher"},
	{"id": "to_infinity", "name": "To Infinity", "desc": "Beat the final boss in space"},
	{"id": "schools_out", "name": "School's Out", "desc": "Beat all 4 bosses", "set": "bosses", "goal": 4},
]

## FIGHTER MASTERY: 4 per fighter, for reaching these levels with them.
const MASTERY_LEVELS := [25, 50, 75, 100]
const MASTERY := {"name": "FIGHTER MASTERY", "color": Color("eef2e6")}

## Trophies for beating the Principal in different ways (plus one per fighter,
## see trophy_list()).
const TROPHIES := [
	{"id": "solo", "name": "Solo Win", "desc": "Beat the Principal with 2 CPU teammates"},
	{"id": "friends", "name": "Friends Win", "desc": "Beat him with 2-3 real players"},
	{"id": "untouchable", "name": "Untouchable", "desc": "Beat him with nobody KO'd"},
]
## The Lunch Lady's trophies (shown after the fighter trophies).
const LUNCH_TROPHIES := [
	{"id": "ll_solo", "name": "Lunch Lady: Solo", "desc": "Beat the Lunch Lady with 2 CPU teammates", "boss": "lunch_lady"},
	{"id": "ll_friends", "name": "Lunch Lady: Friends", "desc": "Beat her with 2-3 real players", "boss": "lunch_lady"},
	{"id": "ll_untouchable", "name": "Lunch Lady: Clean Plate", "desc": "Beat her with nobody KO'd", "boss": "lunch_lady"},
]
## The Gym Teacher's trophies.
const GYM_TROPHIES := [
	{"id": "gt_solo", "name": "Gym Teacher: Solo", "desc": "Beat the Gym Teacher with 2 CPU teammates", "boss": "gym_teacher"},
	{"id": "gt_friends", "name": "Gym Teacher: Friends", "desc": "Beat him with 2-3 real players", "boss": "gym_teacher"},
	{"id": "gt_untouchable", "name": "Gym Teacher: No Laps", "desc": "Beat him with nobody KO'd", "boss": "gym_teacher"},
]
## The final boss's trophies.
const FINAL_TROPHIES := [
	{"id": "fp_solo", "name": "Final Boss: Solo", "desc": "Beat the final Principal with 2 CPU teammates", "boss": "final_principal"},
	{"id": "fp_friends", "name": "Final Boss: Friends", "desc": "Beat him in space with 2-3 real players", "boss": "final_principal"},
	{"id": "fp_untouchable", "name": "Final Boss: Out Of This World", "desc": "Beat him with nobody KO'd", "boss": "final_principal"},
]
## Trophy id prefix for each boss's own trophies (the Principal's have none).
const TROPHY_PREFIX := {"principal": "", "lunch_lady": "ll_", "gym_teacher": "gt_", "final_principal": "fp_"}
## The list is split into leagues of 5, easiest first.
const LEAGUES := [
	{"name": "BRONZE LEAGUE", "color": Color("cd8a4e")},
	{"name": "SILVER LEAGUE", "color": Color("c3cad6")},
	{"name": "GOLD LEAGUE", "color": Color("f2c14e")},
	{"name": "DIAMOND LEAGUE", "color": Color("7fe3f2")},
	{"name": "BOSS LEAGUE", "color": Color("e8575e")},
	{"name": "LEGEND LEAGUE", "color": Color("b08cf0"), "size": 7},
]
const PER_LEAGUE := 5
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
	_clean(data)
	return data


## Drops things an old bug saved: wins "as" a teacher counted as a fighter and a
## trophy (and could unlock the first boss league achievement with no real trophy).
static func _clean(data: Dictionary) -> void:
	var real := {}
	for t in trophy_list():
		real[t.id] = true
	data.sets["trophies"] = data.sets.get("trophies", []).filter(func(id): return real.has(id))
	data.sets["fighters"] = data.sets.get("fighters", []).filter(func(id): return Characters.ALL.has(id))
	for a in LIST:
		if a.get("set", "") == "trophies" and data.unlocked.has(a.id) and data.sets.trophies.size() < goal(a):
			data.unlocked.erase(a.id)


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
	for a in mastery_list():
		if a.id == id:
			return a
	return {}


## How many achievements a league holds (5, the legend league 7).
static func league_size(league: int) -> int:
	return LEAGUES[league].get("size", PER_LEAGUE)


## Index in LIST of a league's first achievement.
static func league_start(league: int) -> int:
	var start := 0
	for i in league:
		start += league_size(i)
	return start


## The 4 FIGHTER MASTERY achievements of every fighter (Lv 25, 50, 75, 100).
static func mastery_list() -> Array:
	var out := []
	for c in Characters.ALL:
		var n: String = Characters.ALL[c].get("short", Characters.ALL[c].name)
		for lv in MASTERY_LEVELS:
			out.append({"id": "lv%d_%s" % [lv, c], "name": "%s Master" % n if lv == 100 else "%s Lv %d" % [n, lv],
				"desc": "Get %s to level %d" % [n, lv], "char": c, "level": lv})
	return out


## The league box an achievement's popup uses (MASTERY for the level ones).
static func toast_league(id: String) -> Dictionary:
	if id.begins_with("lv"):
		return MASTERY
	return LEAGUES[league_of(id)]


## A fighter reached `level`: unlocks (and saves) its mastery achievements up
## to it, and returns the newly unlocked ids.
static func unlock_mastery(char_id: String, level: int) -> Array:
	var data := load_data()
	var out := []
	for lv in MASTERY_LEVELS:
		var id := "lv%d_%s" % [lv, char_id]
		if level >= lv and not data.unlocked.has(id):
			data.unlocked[id] = true
			out.append(id)
	if not out.is_empty():
		save_data(data)
	return out


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


## Which league (0 = bronze ... 3 = diamond) an achievement is in.
static func league_of(id: String) -> int:
	var i := 0
	for a in LIST:
		if a.id == id:
			break
		i += 1
	for league in LEAGUES.size():
		if i < league_start(league) + league_size(league):
			return league
	return 0


## Every trophy: the three above plus "beat him as <fighter>" for each fighter.
static func trophy_list() -> Array:
	var out: Array = TROPHIES.duplicate()
	for id in Characters.ALL:
		var n: String = Characters.ALL[id].name
		out.append({"id": "with_" + id, "name": "%s Trophy" % n, "desc": "Beat the Principal as %s" % n, "fighter": id})
	out.append_array(LUNCH_TROPHIES)
	out.append_array(GYM_TROPHIES)
	out.append_array(FINAL_TROPHIES)
	return out


## Bosses unlock in order: the Principal is always open; each next one opens
## once you've beaten the one before (any trophy from it counts too).
static func boss_unlocked(data: Dictionary, id: String) -> bool:
	var order: Array = Characters.BOSSES.keys()
	var i := order.find(id)
	if i <= 0:
		return i == 0
	var before: String = order[i - 1]
	if data.sets.get("bosses", []).has(before):
		return true
	for t in data.sets.get("trophies", []):
		if trophy_by_id(t).get("boss", "principal") == before:
			return true
	return false


static func trophy_by_id(id: String) -> Dictionary:
	for t in trophy_list():
		if t.id == id:
			return t
	return {}


static func goal(a: Dictionary) -> int:
	if a.has("goal"):
		return a.goal
	match a.get("set", ""):
		"trophies":
			return trophy_list().size()
		"maps":
			return Maps.ALL.size()
		"fighters":
			return Characters.ALL.size()
	return 1


static func unlocked_count(data: Dictionary) -> int:
	return data.unlocked.size()
