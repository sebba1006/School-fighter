extends "res://tests/test_case.gd"

func _rows() -> Array:
	return [
		"1..L....2",
		"1.......2",
		".........",
		".........",
		".........",
	]


## Sebba (0) punches a nearly broken locker at (3, 0).
func _break_locker(b: Battle) -> Dictionary:
	put(b, 0, 2, 0)
	b.obstacles[Vector2i(3, 0)].hp = 1
	return attack(b, 0, 0, R)


func test_items_off_never_drop() -> void:
	var b := make(_rows(), [["sebba", 0], ["mike", 1]])
	var r := _break_locker(b)
	check(has_event(r, "obstacle_broken"), "locker broke")
	check(not has_event(r, "item"), "no item when items are off")
	eq(b.fighters[0].item, "", "empty hands")
	done()


func test_broken_locker_can_drop_an_item() -> void:
	var b := make(_rows(), [["sebba", 0], ["mike", 1]])
	b.items_on = true
	b.forced_rolls.assign([30, 1])  # 30 <= 30% chance, item #1 = pencils
	var r := _break_locker(b)
	check(has_event(r, "item"), "item event")
	eq(b.fighters[0].item, "pencils", "the breaker gets it")

	var b2 := make(_rows(), [["sebba", 0], ["mike", 1]])
	b2.items_on = true
	b2.forced_rolls.assign([31])
	_break_locker(b2)
	eq(b2.fighters[0].item, "", "31 is above the 30% chance: nothing")
	done()


func test_only_lockers_drop_items() -> void:
	var b := make(["1..D....2", "1.......2", ".........", ".........", "........."], [["sebba", 0], ["mike", 1]])
	b.items_on = true
	b.forced_rolls.assign([1, 0])
	put(b, 0, 2, 0)
	b.obstacles[Vector2i(3, 0)].hp = 1
	var r := attack(b, 0, 0, R)
	check(has_event(r, "obstacle_broken") and not has_event(r, "item"), "desks drop nothing")
	done()


func test_book_throw_uses_up_the_item() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 5, 2)
	eq(b.attack_blocked_reason(0, Battle.ITEM_SLOT), "no_item", "nothing to use yet")
	eq(attack(b, 0, Battle.ITEM_SLOT, R).get("error"), "no_item", "can't use an empty slot")
	b.fighters[0].item = "book"
	var before := hp(b, 1)
	var r := attack(b, 0, Battle.ITEM_SLOT, R)
	check(r.ok, "thrown")
	eq(before - hp(b, 1), 12, "book damage")
	eq(b.fighters[1].pos, Vector2i(6, 2), "pushed 1 tile")
	eq(b.fighters[0].item, "", "item used up")
	check(b.current().id == 1, "using an item ends the turn")
	done()


func test_pencils_hit_three_times() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 4, 2)
	b.fighters[0].item = "pencils"
	var before := hp(b, 1)
	var r := attack(b, 0, Battle.ITEM_SLOT, R)
	var hits: int = r.events.filter(func(e): return e.type == "damage").size()
	eq(hits, 3, "three pencils")
	eq(before - hp(b, 1), 9, "3 x 3 damage")
	done()


func test_puddle_makes_enemies_slip() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 3, 2)
	put(b, 1, 7, 2)
	b.fighters[0].item = "water"
	var r := attack(b, 0, Battle.ITEM_SLOT, R)
	check(has_event(r, "puddle"), "spilled")
	check(b.puddles.has(Vector2i(4, 2)), "puddle in front")
	# Mike walks left into it: 5 damage, stuck there, dizzy next turn
	var before := hp(b, 1)
	step(b, 1, L)
	step(b, 1, L)
	r = step(b, 1, L)
	check(has_event(r, "slip"), "slipped")
	eq(before - hp(b, 1), Battle.PUDDLE_DAMAGE, "slip damage")
	eq(b.fighters[1].pos, Vector2i(4, 2), "stopped on the puddle")
	check(not b.puddles.has(Vector2i(4, 2)), "puddle used up")
	eq(step(b, 1, L).get("error"), "no_moves_left", "can't keep walking")
	eq(b.apply(1, {"type": "undo"}).get("error"), "nothing_to_undo", "can't undo the slip")
	check(b.fighters[1].dizzy_next, "dizzy next turn")
	done()


func test_your_own_team_walks_over_puddles() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 3, 2)
	b.fighters[0].item = "water"
	attack(b, 0, Battle.ITEM_SLOT, R)
	end_turn(b, 1)
	var r := step(b, 0, R)
	check(not has_event(r, "slip"), "no slip on your own puddle")
	check(b.puddles.has(Vector2i(4, 2)), "puddle still there")
	done()


func test_cannot_spill_onto_a_fighter_or_wall() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 3, 2)
	put(b, 1, 4, 2)
	b.fighters[0].item = "water"
	eq(attack(b, 0, Battle.ITEM_SLOT, R).get("error"), "no_room", "someone is standing there")
	eq(b.fighters[0].item, "water", "still holding it")
	done()


func test_items_and_puddles_reset_each_round() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	put(b, 0, 3, 2)
	put(b, 1, 3, 3)
	b.fighters[0].item = "water"
	attack(b, 0, Battle.ITEM_SLOT, R)
	b.fighters[1].item = "book"
	b.fighters[1].hp = 1
	b.fighters[0].pos = Vector2i(3, 2)
	end_turn(b, 1)
	attack(b, 0, 0, Vector2i.DOWN)
	eq(b.phase, Battle.Phase.ROUND_OVER, "round over")
	b.start_round()
	check(b.puddles.is_empty(), "puddles gone")
	eq(b.fighters[1].item, "", "items gone")
	done()
