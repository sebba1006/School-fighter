extends "res://tests/test_case.gd"


func test_moves_up_to_move_range() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 0, 2)
	for i in 3:
		check(step(b, 0, R).ok, "step %d should work" % i)
	eq(step(b, 0, R).error, "no_moves_left", "4th step")
	eq(b.fighters[0].pos, Vector2i(3, 2), "position")
	done()


func test_blocked_by_obstacles_fighters_and_edges() -> void:
	var b := make([
		"1.D.....2",
		".........",
		".........",
	], [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 0)
	eq(step(b, 0, R).error, "blocked", "desk")
	eq(step(b, 0, U).error, "blocked", "map edge")
	put(b, 1, 1, 1)
	eq(step(b, 0, D).error, "blocked", "other fighter")
	done()


func test_stepping_back_undoes_a_step() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 0, 2)
	step(b, 0, R)
	step(b, 0, R)
	check(step(b, 0, L).ok, "step back")
	eq(b.fighters[0].pos, Vector2i(1, 2), "after undo")
	eq(b.path.size(), 1, "path length after undo")
	check(step(b, 0, R).ok, "step again 1")
	check(step(b, 0, D).ok, "step again 2")
	eq(step(b, 0, D).error, "no_moves_left", "budget still 3")
	check(b.apply(0, {"type": "undo"}).ok, "explicit undo")
	eq(b.fighters[0].pos, Vector2i(2, 2), "after explicit undo")
	done()


func test_not_your_turn() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	eq(step(b, 1, R).error, "not_your_turn", "mike moving on sebba's turn")
	done()


func test_dizzy_removes_one_move_for_one_turn() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 2, 2)
	end_turn(b, 0)
	check(attack(b, 1, 2, L).ok, "water gun")
	eq(b.current().id, 0, "sebba's turn")
	eq(b.move_budget, 2, "dizzy move budget")
	end_turn(b, 0)
	end_turn(b, 1)
	eq(b.move_budget, 3, "dizzy wears off")
	done()


func test_blue_area_stays_the_same_all_turn() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 4, 2)
	var before := b.turn_reachable()
	step(b, 0, R)
	step(b, 0, R)
	var after := b.turn_reachable()
	before.sort()
	after.sort()
	eq(after, before, "same tiles after walking")
	done()


func test_route_steps_back_when_needed() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 4, 2)
	step(b, 0, R)
	step(b, 0, R)  # at (6, 2), 1 move left
	var route := b.route_to(Vector2i(3, 2))  # 3 tiles left of the start: only reachable by going back
	check(not route.is_empty(), "there is a way")
	for t in route:
		check(b.apply(0, {"type": "move", "dir": t - b.fighters[0].pos}).ok, "each step works")
	eq(b.fighters[0].pos, Vector2i(3, 2), "arrived")
	eq(b.path.size(), 1, "the steps back were undone, so it only used 1 move")
	done()


func test_route_back_to_the_start() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 4, 2)
	step(b, 0, R)
	step(b, 0, D)
	var route := b.route_to(Vector2i(4, 2))
	for t in route:
		b.apply(0, {"type": "move", "dir": t - b.fighters[0].pos})
	eq(b.fighters[0].pos, Vector2i(4, 2), "back at the start")
	check(b.path.is_empty(), "all steps undone")
	done()
