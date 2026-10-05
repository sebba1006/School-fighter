extends "res://tests/test_case.gd"
## Halvor's BOMBA: aimed at any tile 2-5 away, 30 in the middle, 13 around it.

const Bot = preload("res://ai/bot.gd")


func bomba(b: Battle, at: Vector2i) -> Dictionary:
	b.fighters[0].meter = Battle.METER_MAX
	return b.apply(0, {"type": "attack", "slot": Battle.SUPER_SLOT, "dir": R, "dist": 0, "at": at})


func test_bomba_hits_3x3_with_a_big_middle() -> void:
	var b := make([
		"1.......2",
		"1.......2",
		"..D......",
		".........",
		".........",
	], [["halvor", 0], ["sebba", 1], ["mike", 1], ["leon", 0]])
	put(b, 0, 0, 2)
	put(b, 1, 4, 3)  # the middle
	put(b, 2, 5, 4)  # diagonal next to it
	put(b, 3, 3, 2)  # Halvor's teammate, inside the blast
	var hps := [hp(b, 1), hp(b, 2), hp(b, 3)]
	var r := bomba(b, Vector2i(4, 3))
	check(r.ok, "bomba over the desk")
	eq(hps[0] - hp(b, 1), 30, "middle takes 30")
	eq(hps[1] - hp(b, 2), 13, "around takes 13")
	eq(hp(b, 3), hps[2], "teammates are safe")
	eq(b.fighters[0].facing, R, "faces towards the bomb")
	eq(b.fighters[0].meter, 0, "meter used")
	done()


func test_bomba_range_and_target() -> void:
	var b := make(open_rows(), [["halvor", 0], ["sebba", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 8, 2)
	eq(bomba(b, Vector2i(1, 3)).error, "bad_dist", "1 tile away is too close")
	eq(bomba(b, Vector2i(6, 2)).error, "bad_dist", "6 tiles away is too far")
	eq(bomba(b, Vector2i(3, 9)).error, "bad_dist", "off the board")
	b.fighters[0].meter = Battle.METER_MAX
	eq(b.apply(0, {"type": "attack", "slot": Battle.SUPER_SLOT, "dir": R}).error, "bad_dist", "needs a tile")
	check(bomba(b, Vector2i(5, 4)).ok, "5 away diagonally is fine")
	done()


func test_bomba_hits_the_boss_once() -> void:
	var b := Battle.new({"boss": true, "players": [{"char": "halvor", "team": 0}], "seed": 3})
	b.start_round()
	while b.current().id != 0:
		b.apply(b.current().id, {"type": "end_turn"})
	var boss := b.boss()
	b.fighters[0].pos = boss.pos + Vector2i(-4, 0)
	var before := boss.hp
	check(bomba(b, boss.pos).ok, "bomb on the boss")
	eq(before - boss.hp, 30 * Battle.BOSS_HIT_MULTIPLIER, "boss takes the middle hit only once")
	done()


func test_cpu_drops_bomba_on_two_enemies() -> void:
	var b := make(open_rows(), [["halvor", 0], ["sebba", 1], ["mike", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 5, 2)
	put(b, 2, 6, 3)
	b.fighters[0].meter = Battle.METER_MAX
	var p := Bot.plan(b)
	var last: Dictionary = p.intents.back()
	eq(last.get("slot"), Battle.SUPER_SLOT, "uses the super")
	check(last.get("at") is Vector2i, "aims it at a tile")
	done()
