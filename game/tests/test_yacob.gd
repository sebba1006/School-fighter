extends "res://tests/test_case.gd"
## Yacob: Cracker Snack (heal yourself 10, a teammate 10-18), Super Heat Ray
## (the whole row, 23 damage + Burn: -5 HP at the start of 3 own turns).

const Bot = preload("res://ai/bot.gd")


func snack(b: Battle, at: Vector2i) -> Dictionary:
	return b.apply(0, {"type": "attack", "slot": 0, "dir": R, "at": at})


func test_cracker_heals_self_10() -> void:
	var b := make(open_rows(), [["yacob", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	b.fighters[0].hp = 50
	var r := snack(b, Vector2i(1, 2))
	check(r.ok, "eats a cracker")
	eq(hp(b, 0), 60, "+10 on himself")
	check(has_event(r, "heal"), "heal event")
	done()


func test_cracker_heals_teammate_10_to_18() -> void:
	var seen := {}
	for i in 30:
		var b := make(open_rows(), [["yacob", 0], ["sebba", 1], ["mike", 0], ["leon", 1]])
		b._rng.seed = i
		put(b, 0, 1, 2)
		put(b, 2, 4, 3)
		b.fighters[2].hp = 30
		check(snack(b, Vector2i(4, 3)).ok, "throws a cracker 3 tiles")
		var got := hp(b, 2) - 30
		check(got >= 10 and got <= 18, "teammate heal %d in 10-18" % got)
		seen[got] = true
	check(seen.size() > 3, "it varies")
	done()


func test_cracker_rules() -> void:
	var b := make(open_rows(), [["yacob", 0], ["sebba", 1], ["mike", 0], ["leon", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 1, 2)
	put(b, 2, 5, 2)
	put(b, 3, 8, 4)
	eq(snack(b, Vector2i(1, 2)).error, "not_a_teammate", "no crackers for enemies")
	b.fighters[2].hp = 50
	eq(snack(b, Vector2i(5, 2)).error, "not_a_teammate", "5 tiles is too far")
	eq(snack(b, Vector2i(0, 2)).error, "full_hp", "already full")
	b.fighters[0].hp = 50
	check(snack(b, Vector2i(0, 2)).ok, "ok when hurt")
	done()


func test_cracker_has_a_cooldown() -> void:
	var b := make(open_rows(), [["yacob", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	b.fighters[0].hp = 40
	check(snack(b, Vector2i(1, 2)).ok, "first cracker")
	end_turn(b, 1)
	eq(snack(b, Vector2i(1, 2)).error, "cooldown", "not on the very next turn")
	done()


func test_heat_ray_hits_the_whole_row_and_burns() -> void:
	var b := make([
		"1.......2",
		"1.......2",
		"...D.....",
		".........",
		".........",
	], [["yacob", 0], ["sebba", 1], ["mike", 1], ["leon", 0]])
	put(b, 0, 0, 2)
	put(b, 1, 2, 2)  # in front of the desk
	put(b, 2, 8, 2)  # far end, behind the desk
	put(b, 3, 5, 2)  # a teammate in the way
	var hps := [hp(b, 1), hp(b, 2), hp(b, 3)]
	b.fighters[0].meter = Battle.METER_MAX
	var r := attack(b, 0, Battle.SUPER_SLOT, R)
	check(r.ok, "fires")
	# (the next enemy's turn starts right away, with its first burn tick)
	for i in 2:
		var e = b.fighters[i + 1]
		eq(hps[i] - e.hp - (Battle.BURN_TURNS - e.burn_turns) * Battle.BURN_DAMAGE, 23, "hit %d by the ray" % (i + 1))
		check(e.burn_turns > 0, "burning")
	eq(hp(b, 3), hps[2], "teammates are safe")
	check(not b.obstacles.has(Vector2i(3, 2)) or b.obstacles[Vector2i(3, 2)].hp < 20, "the desk gets scorched")
	done()


func test_burn_ticks_3_turns_and_can_ko() -> void:
	var b := make(open_rows(), [["yacob", 0], ["sebba", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 4, 2)
	b.fighters[0].meter = Battle.METER_MAX
	var start := hp(b, 1)
	check(attack(b, 0, Battle.SUPER_SLOT, R).ok, "ray")
	eq(hp(b, 1), start - 23 - 5, "ray, then the first tick as Sebba's turn starts")
	for i in 3:
		end_turn(b, 1)
		end_turn(b, 0)
	eq(hp(b, 1), start - 23 - 15, "only 3 ticks")
	eq(b.fighters[1].burn_turns, 0, "burn over")
	eq(b.fighters[0].match_damage, 23 + 15, "burn counts as Yacob's damage")
	# a burn can finish someone off
	var b2 := make(open_rows(), [["yacob", 0], ["sebba", 1]])
	put(b2, 0, 1, 2)
	put(b2, 1, 4, 2)
	b2.fighters[1].hp = 26
	b2.fighters[0].meter = Battle.METER_MAX
	attack(b2, 0, Battle.SUPER_SLOT, R)
	eq(hp(b2, 1), 0, "ray leaves 3, then the burn finishes it")
	eq(b2.fighters[0].match_kos, 1, "KO goes to Yacob")
	done()


func test_cpu_heals_a_hurt_teammate() -> void:
	var b := make(open_rows(), [["yacob", 0], ["sebba", 1], ["mike", 0], ["leon", 1]])
	put(b, 0, 0, 2)
	put(b, 1, 8, 4)
	put(b, 2, 2, 2)
	put(b, 3, 8, 0)
	b.fighters[2].hp = 20
	var p := Bot.plan(b)
	var last: Dictionary = p.intents.back()
	eq(last.get("slot"), 0, "picks Cracker Snack")
	eq(last.get("at"), b.fighters[2].pos, "for the hurt teammate")
	done()
