extends "res://tests/test_case.gd"


func test_rage_lasts_one_turn() -> void:
	var b := make(open_rows(), [["william", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.forced_rolls = [1]
	check(attack(b, 0, 2).ok, "rage")
	eq(b.fighters[0].shield, {}, "rage gives no shield")
	eq(b.current().id, 1, "rage uses the attack")
	attack(b, 1, 0, L)
	eq(hp(b, 0), 86, "sebba's punch lands fully")
	attack(b, 0, 1, R)
	eq(hp(b, 1), 100 - 14, "boosted punch 12 + 2")
	end_turn(b, 1)
	attack(b, 0, 1, R)
	eq(hp(b, 1), 86 - 12, "normal punch again")
	done()


func test_rage_can_last_two_turns() -> void:
	var b := make(open_rows(), [["william", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.forced_rolls = [2]
	attack(b, 0, 2)
	end_turn(b, 1)
	attack(b, 0, 1, R)
	end_turn(b, 1)
	attack(b, 0, 1, R)
	eq(hp(b, 1), 100 - 14 - 14, "two boosted punches")
	end_turn(b, 1)
	attack(b, 0, 1, R)
	eq(hp(b, 1), 72 - 12, "then normal")
	done()


func test_block_stops_one_hit_including_knockback() -> void:
	var b := make(open_rows(), [["snorre", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	attack(b, 0, 1)
	var r := attack(b, 1, 1, L)
	check(has_event(r, "blocked"), "blocked event")
	eq(hp(b, 0), 95, "no damage")
	eq(b.fighters[0].pos, Vector2i(1, 2), "no knockback")
	eq(b.fighters[0].shield, {}, "block used up")
	done()


func test_block_expires_at_start_of_own_turn() -> void:
	var b := make(open_rows(), [["snorre", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	attack(b, 0, 1)
	end_turn(b, 1)
	eq(b.fighters[0].shield, {}, "gone on snorre's turn")
	end_turn(b, 0)
	attack(b, 1, 0, L)
	eq(hp(b, 0), 81, "punch lands")
	done()


func test_sugar_rush() -> void:
	var b := make(open_rows(), [["snorre", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	check(attack(b, 0, 3).ok, "sugar rush")
	eq(b.current().id, 0, "free action: still snorre's turn")
	eq(attack(b, 0, 3).error, "already_active", "can't stack")
	attack(b, 0, 0, R)
	eq(hp(b, 1), 80, "stab 15 * 1.3 = 19.5, rounds to 20")
	end_turn(b, 1)
	eq(attack(b, 0, 0, R).error, "cannot_attack", "sugar crash")
	check(step(b, 0, D).ok, "can still move")
	end_turn(b, 0)
	end_turn(b, 1)
	step(b, 0, U)
	check(attack(b, 0, 0, R).ok, "can attack again")
	eq(hp(b, 1), 65, "normal stab")
	done()


func test_last_stand_below_35_percent() -> void:
	var b := make(open_rows(), [["william", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[0].hp = 35
	attack(b, 0, 1, R)
	eq(hp(b, 1), 88, "35 hp: normal 12")
	end_turn(b, 1)
	b.fighters[0].hp = 34
	attack(b, 0, 1, R)
	eq(hp(b, 1), 88 - 15, "34 hp: 12 + 3")
	done()


func test_head_slam_dizzies() -> void:
	var b := make(open_rows(), [["william", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	attack(b, 0, 3, R)
	eq(hp(b, 1), 91, "9 damage")
	eq(b.move_budget, 2, "sebba dizzy on his turn")
	done()


func test_block_cooldown_skips_two_own_turns() -> void:
	# real Snorre (Block has a 2-turn cooldown)
	var b := Battle.new({"map": "classroom", "rounds": 1, "seed": 1, "first_team": 0,
		"players": [{"char": "snorre", "team": 0}, {"char": "mike", "team": 1}]})
	b.start_round()
	var block_slot := 1
	check(b.apply(0, {"type": "attack", "slot": block_slot}).ok, "block works")
	end_turn(b, 0)
	end_turn(b, 1)
	eq(b.attack_blocked_reason(0, block_slot), "cooldown", "not on his next turn")
	eq(b.turns_until_ready(b.fighters[0], block_slot), 2, "ready in 2 turns")
	eq(b.apply(0, {"type": "attack", "slot": block_slot}).get("error"), "cooldown", "refused")
	end_turn(b, 0)
	end_turn(b, 1)
	eq(b.turns_until_ready(b.fighters[0], block_slot), 1, "ready in 1 turn")
	end_turn(b, 0)
	end_turn(b, 1)
	eq(b.attack_blocked_reason(0, block_slot), "", "ready again on the third turn")
	done()
