extends "res://tests/test_case.gd"


func _battle(shrink: bool) -> Battle:
	var b := make(["1.......2", "1.......2", ".........", ".........", ".........", ".........", "........."],
		[["sebba", 0], ["mike", 1]], 3)
	b.shrink_on = shrink
	return b


func _pass_turns(b: Battle, n: int) -> Array:
	var events := []
	for i in n:
		events.append_array(end_turn(b, b.current().id).events)
	return events


func test_no_zone_when_off() -> void:
	var b := _battle(false)
	_pass_turns(b, 20)
	eq(b.zone_rings, 0, "never shrinks")
	done()


func test_zone_grows_on_schedule_and_stops() -> void:
	var b := _battle(true)
	# turn 1 already started; the zone appears when turn SHRINK_START begins
	_pass_turns(b, Battle.SHRINK_START - 2)
	eq(b.zone_rings, 0, "not yet")
	var ev := _pass_turns(b, 1)
	eq(b.zone_rings, 1, "first ring")
	check(ev.any(func(e): return e.type == "shrink"), "shrink event")
	_pass_turns(b, Battle.SHRINK_EVERY)
	eq(b.zone_rings, 2, "second ring")
	_pass_turns(b, Battle.SHRINK_EVERY * 5)
	eq(b.zone_rings, b.max_zone_rings(), "stops before the middle")
	check(not b.in_zone(Vector2i(4, 3)), "the middle is always safe")
	check(b.in_zone(Vector2i(0, 0)), "corner is in the zone")
	done()


func test_starting_a_turn_in_the_zone_hurts() -> void:
	var b := _battle(true)
	b.zone_rings = 1
	put(b, 1, 0, 3)  # Mike on the edge
	var before := hp(b, 1)
	var r := end_turn(b, 0)
	eq(before - hp(b, 1), Battle.ZONE_DAMAGE, "detention damage")
	check(r.events.any(func(e): return e.type == "damage" and e.get("zone", false)), "marked as zone damage")
	put(b, 0, 4, 3)  # Sebba in the middle
	before = hp(b, 0)
	end_turn(b, 1)
	eq(hp(b, 0), before, "safe in the middle")
	done()


func test_zone_can_knock_out() -> void:
	var b := _battle(true)
	b.zone_rings = 1
	put(b, 1, 0, 3)
	b.fighters[1].hp = 5
	end_turn(b, 0)
	eq(b.phase, Battle.Phase.ROUND_OVER, "Mike went down in detention")
	eq(b.round_wins[0], 1, "Sebba wins the round")
	done()


func test_match_damage_and_kos_are_counted() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 5
	attack(b, 0, 0, R)
	eq(b.fighters[0].match_kos, 1, "one KO")
	eq(b.fighters[0].match_damage, 5, "damage that actually landed")
	b.start_round()
	eq(b.fighters[0].match_kos, 1, "kept across rounds")
	done()


func test_turns_until_shrink_counts_down() -> void:
	var off := _battle(false)
	eq(off.turns_until_shrink(), -1, "off: no warning")
	var b := _battle(true)
	eq(b.turns_until_shrink(), Battle.SHRINK_START - 1, "counts down from the start")
	_pass_turns(b, Battle.SHRINK_START - 2)
	eq(b.turns_until_shrink(), 1, "next turn")
	_pass_turns(b, 1)
	eq(b.zone_rings, 1, "it happened")
	eq(b.turns_until_shrink(), Battle.SHRINK_EVERY, "then the next growth")
	_pass_turns(b, Battle.SHRINK_EVERY * 10)
	eq(b.turns_until_shrink(), -1, "no warning once it's as small as it gets")
	done()


func test_hall_pass_keeps_you_safe_for_two_turns() -> void:
	var b := _battle(true)
	b.zone_rings = 1
	put(b, 0, 0, 3)  # Sebba on the edge, in the zone
	put(b, 1, 8, 3)
	b.fighters[0].item = "hall_pass"
	var hp0 := hp(b, 0)
	var r := b.apply(0, {"type": "attack", "slot": Battle.ITEM_SLOT})
	check(r.ok, "used the hall pass")
	check(r.events.any(func(e): return e.type == "status" and e.status == "hall_pass"), "hall pass status")
	eq(b.fighters[0].item, "", "used up")
	put(b, 1, 4, 3)  # Mike steps out of the zone
	end_turn(b, 1)  # Sebba's 1st turn after: safe
	eq(hp(b, 0), hp0, "safe turn 1")
	end_turn(b, 0)
	var r2 := end_turn(b, 1)  # Sebba's 2nd turn after: safe, and the pass ends
	eq(hp(b, 0), hp0, "safe turn 2")
	check(r2.events.any(func(e): return e.type == "status_end" and e.status == "hall_pass"), "pass runs out")
	end_turn(b, 0)
	end_turn(b, 1)  # 3rd turn: hurts again
	eq(hp0 - hp(b, 0), Battle.ZONE_DAMAGE, "detention damage again")
	done()


func test_hall_pass_only_drops_when_shrinking() -> void:
	var b := _battle(false)
	check(not b._item_pool(Battle.ITEM_IDS).has("hall_pass"), "not without shrinking")
	b.shrink_on = true
	check(b._item_pool(Battle.ITEM_IDS).has("hall_pass"), "lockers can drop it")
	check(b._item_pool(Battle.BOX_ITEMS).has("hall_pass"), "boxes can drop it")
	done()
