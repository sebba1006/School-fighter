extends "res://tests/test_case.gd"


func _kinds(list: Array) -> Dictionary:
	var out := {}
	for e in list:
		out[e.pos] = e.kind
	return out


func test_reachable_tiles_respect_budget_and_walls() -> void:
	var b := make([
		"1.D.....2",
		".........",
		".........",
	], [["sebba", 0], ["mike", 1]])
	put(b, 0, 0, 0)
	var tiles := b.reachable_tiles()
	check(tiles.has(Vector2i(1, 0)), "next tile")
	check(tiles.has(Vector2i(0, 2)), "2 steps down")
	check(tiles.has(Vector2i(2, 1)), "around the desk")
	check(not tiles.has(Vector2i(2, 0)), "desk tile")
	check(not tiles.has(Vector2i(3, 0)), "4 steps away (around the desk)")
	step(b, 0, R)
	eq(b.reachable_tiles().has(Vector2i(1, 2)), true, "2 steps left after moving")
	eq(b.reachable_tiles().has(Vector2i(3, 1)), false, "too far with 2 steps")
	done()


func test_preview_matches_what_attacks_hit() -> void:
	var b := make([
		"1.......2",
		".........",
		"....D....",
	], [["mike", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 6, 2)
	var sling := _kinds(b.preview(0, 1, R))
	eq(sling.get(Vector2i(4, 2)), "hit", "slingshot stops at the desk")
	check(not sling.has(Vector2i(5, 2)), "nothing past the desk")
	var water := _kinds(b.preview(0, 2, R))
	eq(water.get(Vector2i(3, 2)), "dizzy", "water gun marks dizzy")
	var lob := _kinds(b.preview(0, 3, R, 4))
	eq(lob.size(), 4, "plus shape, clipped at the bottom edge")
	eq(_kinds(b.preview(0, 0, null)).size(), 0, "no direction, no preview")
	done()


func test_preview_self_and_dash() -> void:
	var b := make(open_rows(), [["sebba", 0], ["snorre", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 3, 2)
	var charge := _kinds(b.preview(0, 3, R))
	eq(charge.get(Vector2i(1, 2)), "path", "runs")
	eq(charge.get(Vector2i(3, 2)), "hit", "hits snorre")
	var block := b.preview(1, 1, null)
	eq(block.size(), 1, "block previews one tile")
	eq(block[0].kind, "self", "self kind")
	done()
