extends "res://tests/test_case.gd"


func test_punch_deals_damage_and_fills_meters() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	check(attack(b, 0, 0, R).ok, "punch")
	eq(hp(b, 1), 71, "mike hp")
	eq(b.fighters[0].meter, 28, "attacker meter (2 per hp dealt)")
	eq(b.fighters[1].meter, 14, "victim meter (1 per hp taken)")
	eq(b.current().id, 1, "turn passes")
	done()


func test_kick_knockback_slams_into_map_edge() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 6, 2)
	put(b, 1, 7, 2)
	var r := attack(b, 0, 1, R)
	check(has_event(r, "slam"), "slam event")
	eq(b.fighters[1].pos, Vector2i(8, 2), "pushed 1 tile before the edge")
	eq(hp(b, 1), 85 - 8 - 5, "kick + slam")
	done()


func test_knockback_into_desk_damages_the_desk() -> void:
	var b := make([
		"1.......2",
		".........",
		"....D....",
	], [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	attack(b, 0, 1, R)
	eq(b.fighters[1].pos, Vector2i(3, 2), "stopped by desk")
	eq(hp(b, 1), 72, "kick + slam")
	eq(b.obstacles[Vector2i(4, 2)].hp, 15, "desk took slam damage")
	done()


func test_knockback_into_enemy_hurts_both() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["william", 2]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	put(b, 2, 4, 2)
	attack(b, 0, 1, R)
	eq(b.fighters[1].pos, Vector2i(3, 2), "mike stops next to william")
	eq(hp(b, 1), 72, "mike: kick + slam")
	eq(hp(b, 2), 110, "william: slam")
	done()


func test_knockback_never_hurts_attackers_teammate() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["william", 0], ["snorre", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	put(b, 2, 4, 2)
	put(b, 3, 8, 4)
	attack(b, 0, 1, R)
	eq(hp(b, 1), 72, "mike still slams")
	eq(hp(b, 2), 115, "william (sebba's ally) unhurt")
	done()


func test_sweep_hits_enemies_around_but_not_allies() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["william", 0], ["snorre", 1]])
	put(b, 0, 4, 2)
	put(b, 1, 3, 1)
	put(b, 2, 4, 3)
	put(b, 3, 5, 3)
	attack(b, 0, 2, R)
	eq(hp(b, 1), 77, "mike")
	eq(hp(b, 3), 87, "snorre")
	eq(hp(b, 2), 115, "william (ally)")
	done()


func test_charge_damage_grows_with_distance() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 4, 2)
	attack(b, 0, 3, R)
	eq(b.fighters[0].pos, Vector2i(3, 2), "ran 3 tiles")
	eq(hp(b, 1), 85 - 17, "8 + 3*3")
	eq(b.fighters[1].pos, Vector2i(5, 2), "knockback 1")

	var b2 := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b2, 0, 0, 2)
	put(b2, 1, 5, 2)
	attack(b2, 0, 3, R)
	eq(hp(b2, 1), 85 - 20, "max charge: 8 + 3*4")
	done()


func test_charge_into_desk_damages_it() -> void:
	var b := make([
		"1.......2",
		".........",
		"...D.....",
	], [["sebba", 0], ["mike", 1]])
	put(b, 0, 0, 2)
	attack(b, 0, 3, R)
	eq(b.fighters[0].pos, Vector2i(2, 2), "stopped before desk")
	eq(b.obstacles[Vector2i(3, 2)].hp, 20 - 14, "desk took 8 + 3*2")
	done()


func test_slingshot_is_blocked_by_desks_and_passes_allies() -> void:
	var rows := [
		"1.......2",
		"1.......2",
		"...D.....",
	]
	var b := make(rows, [["mike", 0], ["sebba", 1], ["william", 0], ["snorre", 1]])
	put(b, 0, 0, 2)
	put(b, 2, 1, 2)
	put(b, 1, 5, 2)
	attack(b, 0, 1, R)
	eq(b.obstacles[Vector2i(3, 2)].hp, 9, "desk took the shot")
	eq(hp(b, 1), 100, "sebba behind cover")
	eq(hp(b, 2), 115, "william (ally) not hit")

	var b2 := make(open_rows(), [["mike", 0], ["sebba", 1], ["william", 0], ["snorre", 1]])
	put(b2, 0, 0, 2)
	put(b2, 2, 1, 2)
	put(b2, 1, 5, 2)
	attack(b2, 0, 1, R)
	eq(hp(b2, 1), 89, "sebba hit through ally")
	done()


func test_water_gun_hits_whole_line_and_dizzies() -> void:
	var b := make(open_rows(), [["mike", 0], ["sebba", 1], ["william", 0], ["snorre", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 1, 2)
	put(b, 3, 3, 2)
	attack(b, 0, 2, R)
	eq(hp(b, 1), 94, "sebba")
	eq(hp(b, 3), 89, "snorre")
	eq(b.current().id, 1, "sebba's turn next")
	eq(b.move_budget, 2, "sebba dizzy this turn")
	check(b.fighters[3].dizzy_next, "snorre dizzy on his next turn")
	done()


func test_book_lob_flies_over_desks() -> void:
	var b := make([
		"1.......2",
		".........",
		".D.......",
		".........",
		".........",
	], [["mike", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 3, 2)
	eq(attack(b, 0, 3, R, 1).error, "bad_dist", "too close")
	eq(attack(b, 0, 3, R, 5).error, "bad_dist", "too far")
	check(attack(b, 0, 3, R, 3).ok, "lob 3 tiles")
	eq(hp(b, 1), 91, "sebba hit over the desk")
	eq(b.obstacles[Vector2i(1, 2)].hp, 20, "desk untouched")
	done()


func test_mega_sword_inner_and_outer_rings() -> void:
	var b := make(open_rows(), [["snorre", 0], ["mike", 1], ["william", 0], ["sebba", 1]])
	put(b, 0, 2, 2)
	put(b, 1, 4, 3)
	put(b, 2, 3, 1)
	put(b, 3, 5, 2)
	b.fighters[0].meter = 100
	check(attack(b, 0, 4, R).ok, "mega sword")
	eq(hp(b, 1), 55, "mike in inner ring")
	eq(hp(b, 3), 88, "sebba in outer ring")
	check(b.fighters[3].dizzy_next, "outer ring dizzy")
	check(not b.fighters[1].dizzy_next, "inner ring not dizzy")
	eq(hp(b, 2), 115, "ally unhurt")
	eq(b.fighters[0].meter, 0, "super empties meter and doesn't refill it")
	done()


func test_flying_tackle() -> void:
	var b := make(open_rows(), [["mike", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 3, 2)
	b.fighters[0].meter = 100
	check(attack(b, 0, 4, R).ok, "flying tackle")
	eq(hp(b, 1), 55, "45 damage")
	eq(b.move_budget, 2, "sebba dizzy on his turn")
	eq(hp(b, 0), 75, "costs mike 10")
	check(b.fighters[0].dizzy_next, "mike dizzy too")
	eq(b.fighters[0].pos, Vector2i(0, 2), "mike jumps back")
	done()


func test_flying_tackle_over_desk_costs_more_and_never_kos_mike() -> void:
	var b := make([
		"1.......2",
		".........",
		".D.......",
	], [["mike", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 3, 2)
	b.fighters[0].meter = 100
	attack(b, 0, 4, R)
	eq(hp(b, 0), 70, "over a desk costs 15")

	var b2 := make(open_rows(), [["mike", 0], ["sebba", 1]])
	put(b2, 0, 0, 2)
	put(b2, 1, 2, 2)
	b2.fighters[0].meter = 100
	b2.fighters[0].hp = 8
	attack(b2, 0, 4, R)
	eq(hp(b2, 0), 1, "stays at 1 hp")
	done()


func test_flying_tackle_needs_a_target() -> void:
	var b := make(open_rows(), [["mike", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 5, 2)
	b.fighters[0].meter = 100
	eq(attack(b, 0, 4, R).error, "no_target", "enemy 5 tiles away")
	eq(b.fighters[0].meter, 100, "meter kept")
	eq(b.current().id, 0, "still mike's turn")
	done()


func test_super_needs_full_meter() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[0].meter = 99
	eq(attack(b, 0, 4, R).error, "super_not_ready", "99 meter")
	b.fighters[0].meter = 100
	check(attack(b, 0, 4, R).ok, "100 meter")
	eq(hp(b, 1), 50, "mega barrage 35")
	done()


func test_obstacles_break() -> void:
	var b := make([
		"1.......2",
		".........",
		"..D......",
	], [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 8, 0)
	attack(b, 0, 0, R)
	end_turn(b, 1)
	var r := attack(b, 0, 0, R)
	check(has_event(r, "obstacle_broken"), "desk broken after 28 damage")
	check(not b.obstacles.has(Vector2i(2, 2)), "tile is free")
	done()
