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
