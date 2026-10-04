extends "res://tests/test_case.gd"

const A = preload("res://stats/achievements.gd")
const Tracker = preload("res://stats/achievement_tracker.gd")


func _fresh() -> Dictionary:
	return {"unlocked": {}, "counters": {}, "sets": {}}


func _cfg(chars: Array, teams: Array, map := "classroom", cpus := []) -> Dictionary:
	var players := []
	for i in chars.size():
		var p := {"char": chars[i], "team": teams[i]}
		if i < cpus.size() and cpus[i] != "":
			p.cpu = cpus[i]
		players.append(p)
	return {"map": map, "players": players, "rounds": 1, "characters": Fixture.ALL}


func _play(b: Battle, t: Tracker, r: Dictionary) -> void:
	for e in r.events:
		t.feed(e)


func test_list_is_thirty_two_unique_achievements() -> void:
	eq(A.LIST.size(), 32, "32 achievements (5 leagues of 5 + the legend league of 7)")
	var ids := {}
	for a in A.LIST:
		ids[a.id] = true
	eq(ids.size(), 32, "unique ids")
	eq(A.LIST[0].id, "first_win", "easiest first")
	eq(A.LIST[19].id, "online_legend", "hardest last")
	done()


func test_winning_unlocks_first_blood_and_counts_wins() -> void:
	var cfg := _cfg(["sebba", "mike"], [0, 1], "cafeteria")
	var b := Battle.new(cfg)
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	for e in b.start_round():
		t.feed(e)
	var me := b.current()
	var foe := b.fighters[1 - me.id]
	foe.hp = 1
	foe.pos = me.pos + Vector2i(0, 1)
	var r := b.apply(me.id, {"type": "attack", "slot": 0, "dir": Vector2i(0, 1)})
	_play(b, t, r)
	if me.id == 0:
		check(t.new_unlocks.has("first_win"), "first blood")
		eq(t.data.counters.get("cafeteria_wins", 0), 1, "a cafeteria win")
		eq(t.data.sets.maps, ["cafeteria"], "map visited")
		eq(t.data.counters.get("wins_sebba", 0), 1, "a win with sebba")
	else:
		check(t.new_unlocks.is_empty(), "the other player won: nothing for us")
	done()


func test_combo_and_coolness_from_a_super() -> void:
	var cfg := _cfg(["sebba", "mike"], [0, 1])
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[0].meter = Battle.METER_MAX
	_play(b, t, attack(b, 0, Battle.SUPER_SLOT, R))
	check(t.new_unlocks.has("combo"), "30+ damage in a turn")
	eq(t.data.counters.supers, 1, "a super counted")
	end_turn(b, 1)
	b.fighters[1].hp = 3
	b.fighters[0].meter = Battle.METER_MAX
	_play(b, t, attack(b, 0, Battle.SUPER_SLOT, R))
	check(t.new_unlocks.has("coolness"), "KO with a super")
	done()


func test_item_master_and_slippery() -> void:
	var cfg := _cfg(["sebba", "mike"], [0, 1])
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	put(b, 0, 1, 2)
	put(b, 1, 4, 2)
	b.fighters[0].item = "book"
	b.fighters[1].hp = 2
	_play(b, t, attack(b, 0, Battle.ITEM_SLOT, R))
	check(t.new_unlocks.has("item_master"), "KO with an item")

	var b2 := make(open_rows(), [["sebba", 0], ["mike", 1]])
	var t2 := Tracker.new(_fresh(), b2, cfg, [0], false)
	put(b2, 0, 3, 2)
	put(b2, 1, 6, 2)
	b2.fighters[0].item = "water"
	_play(b2, t2, attack(b2, 0, Battle.ITEM_SLOT, R))
	step(b2, 1, L)
	_play(b2, t2, step(b2, 1, L))
	check(t2.new_unlocks.has("slippery"), "they slipped in my puddle")
	done()


func test_counters_unlock_at_their_goal() -> void:
	var cfg := _cfg(["sebba", "mike"], [0, 1])
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	t.data.counters.lockers = 24
	t.feed({"type": "attack", "fighter": 0})
	t.feed({"type": "obstacle_broken", "at": Vector2i(0, 0), "obstacle": "L"})
	check(t.new_unlocks.has("locker_breaker"), "25th locker")
	t.feed({"type": "obstacle_broken", "at": Vector2i(1, 0), "obstacle": "D"})
	eq(t.data.counters.lockers, 25, "desks don't count")
	eq(A.progress(t.data, A.by_id("box_hunter")), [0, 5], "progress for one not started")
	done()


func test_modes_and_hard_cpu() -> void:
	var cfg := _cfg(["sebba", "mike", "leon", "snorre"], [0, 1, 2, 3], "classroom", ["", "hard", "easy", "easy"])
	var b := Battle.new(cfg)
	b.start_round()
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	check(t.new_unlocks.has("last_one"), "won a 1v1v1v1")
	check(t.new_unlocks.has("cpu_crusher"), "beat a hard CPU")
	eq(t.data.counters.ffa4_wins, 1, "counts towards Fighting Champion")
	check(not t.new_unlocks.has("teamwork"), "not a 2v2")
	var cfg2 := _cfg(["sebba", "mike", "leon", "snorre"], [0, 0, 1, 1])
	var b2 := Battle.new(cfg2)
	b2.start_round()
	var t2 := Tracker.new(_fresh(), b2, cfg2, [0], true)
	t2.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	check(t2.new_unlocks.has("teamwork"), "won a 2v2")
	eq(t2.data.counters.online_wins, 1, "online win counted")
	done()


func test_comeback_and_survivor() -> void:
	var cfg := _cfg(["sebba", "mike"], [0, 1])
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	b.shrink_on = true
	b.zone_rings = 1
	b.fighters[0].hp = 12
	t.feed({"type": "round_end", "round": 1, "winner_team": 0, "wins": {}})
	check(t.new_unlocks.has("comeback"), "won with less than 20 HP")
	check(t.new_unlocks.has("survivor"), "no detention damage on a shrinking map")
	var t2 := Tracker.new(_fresh(), b, cfg, [0], false)
	t2.feed({"type": "damage", "fighter": 0, "amount": 10, "absorbed": 0, "hp": 2, "zone": true})
	t2.feed({"type": "round_end", "round": 1, "winner_team": 0, "wins": {}})
	check(not t2.new_unlocks.has("survivor"), "took detention damage")
	done()


func test_set_achievements() -> void:
	var cfg := _cfg(["sebba", "mike"], [0, 1], "recess")
	var b := Battle.new(cfg)
	b.start_round()
	var data := _fresh()
	data.sets.maps = Maps_all_but("recess")
	data.counters.wins_sebba = 9
	var t := Tracker.new(data, b, cfg, [0], false)
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	check(t.new_unlocks.has("world_tour"), "won on the last map")
	check(t.new_unlocks.has("main_character"), "10 wins with Sebba")
	done()


func Maps_all_but(skip: String) -> Array:
	var out := []
	for m in preload("res://rules/maps.gd").ALL:
		if m != skip:
			out.append(m)
	return out


func test_four_leagues_of_five() -> void:
	eq(A.league_start(A.LEAGUES.size() - 1) + A.league_size(A.LEAGUES.size() - 1), A.LIST.size(), "every achievement is in a league")
	eq(A.league_of("slip_n_slide"), 5, "legend league")
	eq(A.league_of("schools_out"), 5, "legend league, hardest last")
	eq(A.league_of("first_win"), 0, "bronze")
	eq(A.league_of("combo"), 1, "silver")
	eq(A.league_of("wall_slam"), 2, "gold")
	eq(A.league_of("online_legend"), 3, "diamond")
	done()



func _boss_cfg(chars: Array, cpus: Array) -> Dictionary:
	var players := []
	for i in chars.size():
		var p := {"char": chars[i], "team": 0}
		if cpus[i]:
			p.cpu = "normal"
		players.append(p)
	return {"boss": true, "players": players, "characters": Fixture.ALL}


func test_beating_the_boss_gives_trophies() -> void:
	var cfg := _boss_cfg(["sebba", "mike", "leon"], [false, true, true])
	var b := Battle.new(cfg)
	b.start_round()
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	for id in ["solo", "untouchable", "with_sebba"]:
		check(t.new_trophies.has(id), "trophy " + id)
	check(not t.new_trophies.has("friends"), "not with friends")
	check(t.new_unlocks.has("boss_slayer"), "first trophy")
	check(t.new_unlocks.has("trophy_collector"), "3 trophies at once")
	check(t.new_unlocks.has("not_a_scratch"), "untouchable achievement")
	check(not t.new_unlocks.has("teamwork"), "a boss win isn't a 2v2")
	done()


func test_friends_trophy_and_ko() -> void:
	var cfg := _boss_cfg(["sebba", "mike", "leon"], [false, false, true])
	var b := Battle.new(cfg)
	b.start_round()
	b.fighters[2].hp = 0  # the CPU went down
	var t := Tracker.new(_fresh(), b, cfg, [1], true)
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	check(t.new_trophies.has("friends"), "2 real players")
	check(t.new_trophies.has("with_mike"), "mike trophy")
	check(not t.new_trophies.has("untouchable"), "someone was KO'd")
	done()


func test_trophy_list_has_one_per_fighter() -> void:
	eq(A.trophy_list().size(), A.TROPHIES.size() + preload("res://rules/characters.gd").ALL.size() + A.LUNCH_TROPHIES.size() + A.GYM_TROPHIES.size() + A.FINAL_TROPHIES.size(),
		"3 + one per fighter + 3 for each later boss")
	eq(A.goal(A.by_id("trophy_master")), A.trophy_list().size(), "trophy master needs them all")
	done()


func test_losing_to_the_boss_gives_nothing() -> void:
	var cfg := _boss_cfg(["sebba", "mike", "leon"], [false, true, true])
	var b := Battle.new(cfg)
	b.start_round()
	var teacher: int = b.fighters.filter(func(f): return f.is_minion)[0].id
	var t := Tracker.new(_fresh(), b, cfg, [0, teacher], false)  # even if a teacher slipped into "yours"
	t.feed({"type": "match_end", "winner_team": Battle.BOSS_TEAM, "wins": {}})
	check(t.new_trophies.is_empty(), "no trophy for losing")
	check(not t.new_unlocks.has("first_win"), "not a win")
	done()


func test_old_teacher_trophies_are_cleaned_up() -> void:
	var data := {"unlocked": {"boss_slayer": true, "first_win": true}, "counters": {},
		"sets": {"trophies": ["with_teacher"], "fighters": ["teacher", "mike"]}}
	A._clean(data)
	eq(data.sets.trophies, [], "teacher trophy gone")
	eq(data.sets.fighters, ["mike"], "teacher isn't a fighter")
	check(not data.unlocked.has("boss_slayer"), "boss slayer needs a real trophy")
	check(data.unlocked.has("first_win"), "other unlocks kept")
	done()



func test_lunch_lady_unlocks_after_the_principal() -> void:
	var data := _fresh()
	check(A.boss_unlocked(data, "principal"), "the Principal is always open")
	check(not A.boss_unlocked(data, "lunch_lady"), "the Lunch Lady starts locked")
	data.sets["trophies"] = ["with_mike"]
	check(A.boss_unlocked(data, "lunch_lady"), "any Principal trophy unlocks her (old saves)")
	data = _fresh()
	var cfg := _boss_cfg(["sebba", "mike", "leon"], [false, true, true])
	var b := Battle.new(cfg)
	b.start_round()
	var t := Tracker.new(data, b, cfg, [0], false)
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	check(A.boss_unlocked(t.data, "lunch_lady"), "beating him unlocks her")
	done()


func test_beating_the_lunch_lady_gives_her_trophies() -> void:
	var cfg := _boss_cfg(["sebba", "mike", "leon"], [false, true, true])
	cfg.boss = "lunch_lady"
	var b := Battle.new(cfg)
	b.start_round()
	var t := Tracker.new(_fresh(), b, cfg, [0], false)
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	for id in ["ll_solo", "ll_untouchable"]:
		check(t.new_trophies.has(id), "trophy " + id)
	check(not t.new_trophies.has("solo"), "not the Principal's trophy")
	check(not t.new_trophies.has("with_sebba"), "fighter trophies are the Principal's")
	check(t.new_unlocks.has("not_a_scratch"), "nobody KO'd counts for any boss")
	done()



func test_gym_teacher_unlocks_after_the_lunch_lady() -> void:
	var data := _fresh()
	data.sets["bosses"] = ["principal"]
	check(not A.boss_unlocked(data, "gym_teacher"), "locked until the Lunch Lady is beaten")
	data.sets["trophies"] = ["ll_solo"]
	check(A.boss_unlocked(data, "gym_teacher"), "her trophy unlocks him")
	done()


func test_beating_the_gym_teacher_gives_his_trophies() -> void:
	var cfg := _boss_cfg(["sebba", "mike", "leon"], [false, false, true])
	cfg.boss = "gym_teacher"
	var b := Battle.new(cfg)
	b.start_round()
	var t := Tracker.new(_fresh(), b, cfg, [0], true)
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	for id in ["gt_friends", "gt_untouchable"]:
		check(t.new_trophies.has(id), "trophy " + id)
	check(t.data.sets.bosses.has("gym_teacher"), "remembered as beaten")
	done()



func test_legend_league_from_boss_fights() -> void:
	var cfg := _boss_cfg(["sebba", "mike", "leon"], [false, true, true])
	cfg.boss = "lunch_lady"
	var b := Battle.new(cfg)
	b.start_round()
	var data := _fresh()
	data.sets["bosses"] = ["principal", "gym_teacher", "final_principal"]
	var t := Tracker.new(data, b, cfg, [0], false)
	var cook: int = b.fighters.filter(func(f): return f.is_minion)[0].id
	for i in 10:
		t.feed({"type": "attack", "fighter": 0})
		t.feed({"type": "ko", "fighter": cook})
	t.feed({"type": "ko", "fighter": cook, "fled": true})
	eq(int(t.data.counters.get("helper_kos", 0)), 10, "fled helpers don't count")
	check(t.new_unlocks.has("teachers_pet"), "10 helper KOs")
	for i in 10:
		t.feed({"type": "heal", "fighter": 0, "amount": 60, "hp": 100, "at": Vector2i(1, 1)})
	check(t.new_unlocks.has("apple_a_day"), "10 apples")
	t.feed({"type": "slip", "fighter": 0, "at": Vector2i(2, 2), "by": b.boss().id})
	check(t.new_unlocks.has("slip_n_slide"), "slipped in gravy")
	t.feed({"type": "match_end", "winner_team": 0, "wins": {}})
	check(t.new_unlocks.has("lunch_is_served"), "beat the Lunch Lady")
	check(t.new_unlocks.has("schools_out"), "all 4 bosses")
	done()


func test_mastery_achievements_for_levels() -> void:
	eq(A.mastery_list().size(), preload("res://rules/characters.gd").ALL.size() * 4, "4 per fighter")
	eq(A.by_id("lv100_snorre").name, "Snorre Master", "level 100 is the master one")
	eq(A.toast_league("lv25_mike").name, "FIGHTER MASTERY", "its own popup color")
	done()
