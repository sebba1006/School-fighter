extends "res://tests/test_case.gd"


func test_forfeit_in_1v1_ends_the_match() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	var events := b.forfeit(1)
	eq(b.phase, Battle.Phase.MATCH_OVER, "match over")
	eq(b.match_winner, 0, "the player who stayed wins")
	check(events.any(func(e): return e.type == "match_end"), "match_end event")
	done()


func test_forfeit_on_own_turn_passes_the_turn() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["william", 0], ["snorre", 1]])
	eq(b.current().id, 0, "sebba's turn")
	b.forfeit(0)
	eq(b.current().id, 1, "mike's turn next")
	eq(b.phase, Battle.Phase.TURN, "2v2 goes on with william")
	done()


func test_forfeited_player_stays_out_next_round() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["snorre", 2]], 3)
	b.forfeit(2)
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 1
	attack(b, 0, 0, R)
	eq(b.phase, Battle.Phase.ROUND_OVER, "round over")
	b.start_round()
	eq(hp(b, 2), 0, "still out")
	check(not b.order.is_empty() and b.current().id != 2, "never gets a turn")
	done()


func test_forfeit_between_rounds_can_end_the_match() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]], 3)
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	b.fighters[1].hp = 1
	attack(b, 0, 0, R)
	eq(b.phase, Battle.Phase.ROUND_OVER, "between rounds")
	b.forfeit(0)
	eq(b.match_winner, 1, "mike wins because sebba left")
	done()


func test_state_hash_matches_for_identical_battles() -> void:
	var a := make(open_rows(), [["sebba", 0], ["mike", 1]])
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	eq(a.state_hash(), b.state_hash(), "same start")
	step(a, 0, R)
	check(a.state_hash() != b.state_hash(), "differs after a move")
	step(b, 0, R)
	eq(a.state_hash(), b.state_hash(), "same again")
	done()


func test_round_never_starts_on_a_forfeited_player() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1], ["snorre", 2]], 3)
	b.forfeit(0)
	put(b, 1, 1, 2)
	put(b, 2, 2, 2)
	b.fighters[2].hp = 1
	attack(b, 1, 0, R)
	eq(b.phase, Battle.Phase.ROUND_OVER, "round over")
	b.start_round()
	check(b.current().id != 0, "first turn skips sebba (team 0 always starts in tests)")
	done()
