extends "res://tests/test_case.gd"

const Bot = preload("res://ai/bot.gd")
const Maps = preload("res://rules/maps.gd")


func test_bot_finishes_matches_with_every_fighter() -> void:
	var chars := ["sebba", "william", "snorre", "mike", "leon"]
	for i in chars.size():
		var b := Battle.new({"map": Maps.ALL.keys()[i % Maps.ALL.size()], "rounds": 1, "seed": i,
			"players": [{"char": chars[i], "team": 0}, {"char": chars[(i + 1) % chars.size()], "team": 1}]})
		b.start_round()
		var turns := 0
		while b.phase == Battle.Phase.TURN and turns < 300:
			Bot.play_turn(b, 2.0)
			turns += 1
		check(b.phase == Battle.Phase.MATCH_OVER, "%s vs %s finished (%d turns)" % [chars[i], chars[(i + 1) % chars.size()], turns])
	done()


func test_bot_attacks_an_enemy_in_reach() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 2, 2)
	var p := Bot.plan(b)
	check(not p.intents.is_empty() and p.intents.back().type == "attack", "attacks instead of walking away")
	done()


func test_every_cpu_level_plays_legal_turns() -> void:
	for level in Bot.LEVELS:
		var b := Battle.new({"map": "classroom", "rounds": 1, "seed": 4, "characters": Fixture.ALL,
			"players": [{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}, {"char": "leon", "team": 2}]})
		b.start_round()
		var turns := 0
		while b.phase == Battle.Phase.TURN and turns < 300:
			var f := b.current()
			var p := Bot.plan_level(b, level)
			for t in p.path:
				check(b.apply(f.id, {"type": "move", "dir": t - b.current().pos}).ok, "%s: legal step" % level)
			for intent in p.intents:
				if b.phase != Battle.Phase.TURN or b.current().id != f.id:
					break
				b.apply(f.id, intent)
			if b.phase == Battle.Phase.TURN and b.current().id == f.id:
				b.apply(f.id, {"type": "end_turn"})
			turns += 1
		check(b.phase == Battle.Phase.MATCH_OVER, "%s: 1v1v1 finished" % level)
	done()


func test_bot_uses_items() -> void:
	for item in Battle.ITEM_IDS:
		var b := Battle.new({"map": "classroom", "rounds": 1, "seed": 9, "items": true, "characters": Fixture.ALL,
			"players": [{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}]})
		b.start_round()
		for f in b.fighters:
			f.item = item
		var used := false
		var turns := 0
		while b.phase == Battle.Phase.TURN and turns < 300:
			var had: String = b.current().item
			Bot.play_turn(b, 2.0)
			if had != "" and b.fighters.any(func(f): return f.item == "") :
				used = true
			turns += 1
		check(used, "%s got used" % item)
		check(b.phase == Battle.Phase.MATCH_OVER, "%s: match finished" % item)
	done()


func test_bot_goes_for_a_box_in_reach() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 0, 0)
	put(b, 1, 8, 4)
	b.box = Vector2i(2, 0)
	var p := Bot.plan(b)
	check(not p.path.is_empty() and p.path.back() == b.box, "walks onto the box")
	done()


func test_hurt_bot_puts_up_its_shield() -> void:
	var b := make(open_rows(), [["sebba", 0], ["mike", 1]])
	put(b, 0, 1, 2)
	put(b, 1, 4, 2)
	b.fighters[0].hp = 20
	b.fighters[0].item = "melee_guard"
	var p := Bot.plan(b)
	check(p.intents.any(func(i): return i.get("slot", -1) == Battle.ITEM_SLOT), "uses the shield")
	done()
