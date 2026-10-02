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


func test_list_is_twenty_unique_achievements() -> void:
	eq(A.LIST.size(), 20, "20 achievements")
	var ids := {}
	for a in A.LIST:
		ids[a.id] = true
	eq(ids.size(), 20, "unique ids")
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
