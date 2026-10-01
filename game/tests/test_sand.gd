extends "res://tests/test_case.gd"


## Sand in column 5; Mike (1) hides at (5, 2).
func _rows() -> Array:
	return [
		"1.......2",
		"1....s..2",
		".....s...",
		".....s...",
		".........",
	]


func test_sand_hides_from_projectiles() -> void:
	var b := make(_rows(), [["mike", 0], ["sebba", 1]])
	put(b, 0, 2, 2)
	put(b, 1, 5, 2)
	var before := hp(b, 1)
	var r := attack(b, 0, 1, R)  # Slingshot
	eq(hp(b, 1), before, "the slingshot flies past")
	check(not has_event(r, "damage"), "no hit")
	done()


func test_sand_hides_from_lines_and_lobs() -> void:
	var b := make(_rows(), [["mike", 0], ["sebba", 1]])
	put(b, 0, 3, 2)
	put(b, 1, 5, 2)
	var before := hp(b, 1)
	var r := attack(b, 0, 2, R)  # Water Gun (line of 3)
	check(has_event(r, "hidden"), "hidden event")
	eq(hp(b, 1), before, "water gun can't reach")
	check(not b.fighters[1].dizzy_next, "no dizzy either")
	end_turn(b, 1)
	r = attack(b, 0, 3, R, 2)  # Book Lob onto the sand tile
	eq(hp(b, 1), before, "book lob can't reach")
	done()


func test_melee_still_hits_in_sand() -> void:
	var b := make(_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 4, 2)
	put(b, 1, 5, 2)
	var before := hp(b, 1)
	attack(b, 0, 0, R)  # Punch
	check(hp(b, 1) < before, "punch lands")
	done()


func test_sand_is_walkable() -> void:
	var b := make(_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 4, 2)
	check(step(b, 0, R).ok, "walk into the sandbox")
	done()


func test_recess_map_has_a_sandbox_and_slides() -> void:
	var b := Battle.new({"map": "recess", "players": [{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}]})
	b.start_round()
	eq(b.sand.size(), 6, "3x2 sandbox")
	eq(b.obstacles[Vector2i(2, 2)].hp, 60, "slide ladder 60 HP")
	eq(b.obstacles[Vector2i(3, 2)].type, "Z", "slide")
	done()
