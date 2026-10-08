extends "res://tests/test_case.gd"
## Seif's Mega Slingshot: 30 damage point blank, down to 12 at 6 tiles.

const Bot = preload("res://ai/bot.gd")


func shoot(b: Battle) -> Dictionary:
	b.fighters[0].meter = Battle.METER_MAX
	return attack(b, 0, Battle.SUPER_SLOT, R)


func test_mega_slingshot_damage_by_distance() -> void:
	var expected := {1: 30, 2: 26, 3: 23, 4: 19, 5: 16, 6: 12}
	for d in expected:
		var b := make(["1.......2", ".........", ".........", ".........", "........."], [["seif", 0], ["sebba", 1]])
		put(b, 0, 0, 2)
		put(b, 1, d, 2)
		var before := hp(b, 1)
		check(shoot(b).ok, "fires at %d tiles" % d)
		eq(before - hp(b, 1), expected[d], "%d tiles away" % d)
	done()


func test_mega_slingshot_range_and_desks() -> void:
	var b := make(["1.......2", ".........", ".........", ".........", "........."], [["seif", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 7, 2)
	var before := hp(b, 1)
	check(shoot(b).ok, "fires")
	eq(hp(b, 1), before, "7 tiles is out of reach")
	var b2 := make(["1.......2", ".........", "..D......", ".........", "........."], [["seif", 0], ["sebba", 1]])
	put(b2, 0, 0, 2)
	put(b2, 1, 4, 2)
	var hp2 := hp(b2, 1)
	shoot(b2)
	eq(hp(b2, 1), hp2, "a desk in the way takes the rock")
	done()


func test_cpu_uses_mega_slingshot() -> void:
	var b := make(open_rows(), [["seif", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 3, 2)
	b.fighters[0].meter = Battle.METER_MAX
	var p := Bot.plan(b)
	eq(p.intents.back().get("slot"), Battle.SUPER_SLOT, "fires the super")
	done()
