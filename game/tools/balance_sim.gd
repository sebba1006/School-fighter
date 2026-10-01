extends SceneTree
## Balance check: the computer plays every fighter against every other fighter
## on every map and prints win rates. 50% everywhere = perfectly balanced.
##   godot --headless --path game -s res://tools/balance_sim.gd -- [matches per pair per map=6]

const Battle = preload("res://rules/battle.gd")
const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")
const Bot = preload("res://ai/bot.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var per := int(args[0]) if not args.is_empty() else 6
	var chars: Array = Characters.ALL.keys()
	var wins := {}   # [a, b] -> a's wins vs b
	var games := {}
	var total_wins := {}
	var total_games := {}
	var turns_total := 0
	var matches := 0
	var t0 := Time.get_ticks_msec()
	for c in chars:
		total_wins[c] = 0
		total_games[c] = 0
	for i in chars.size():
		for j in range(i + 1, chars.size()):
			var a: String = chars[i]
			var b: String = chars[j]
			for map_id in Maps.ALL:
				for m in per:
					# swap sides and who starts so neither gets an edge
					var swap := m % 2 == 1
					var left := b if swap else a
					var right := a if swap else b
					var battle := Battle.new({"map": map_id, "rounds": 1, "seed": 1000 * m + i * 37 + j,
						"first_team": (m / 2) % 2, "players": [{"char": left, "team": 0}, {"char": right, "team": 1}]})
					battle.start_round()
					seed(1000 * m + i * 37 + j)
					var turns := 0
					while battle.phase == Battle.Phase.TURN and turns < 300:
						Bot.play_turn(battle, 4.0)
						turns += 1
					turns_total += turns
					matches += 1
					var winner_char := ""
					if battle.match_winner == 0:
						winner_char = left
					elif battle.match_winner == 1:
						winner_char = right
					for c in [a, b]:
						total_games[c] += 1
					if winner_char != "":
						total_wins[winner_char] += 1
						var loser := b if winner_char == a else a
						wins[[winner_char, loser]] = wins.get([winner_char, loser], 0) + 1
					games[[a, b]] = games.get([a, b], 0) + 1
	print("%d matches, %.1f turns per match on average, %.1f s" % [matches, float(turns_total) / matches, (Time.get_ticks_msec() - t0) / 1000.0])
	print("")
	print("OVERALL WIN RATE")
	for c in chars:
		print("  %-8s %5.1f%%" % [c, 100.0 * total_wins[c] / maxi(1, total_games[c])])
	print("")
	print("ROW beats COLUMN (%)")
	var header := "          "
	for c in chars:
		header += "%-9s" % c
	print(header)
	for a in chars:
		var line := "  %-8s" % a
		for b in chars:
			if a == b:
				line += "   -     "
				continue
			var key := [a, b] if games.has([a, b]) else [b, a]
			line += "%5.0f    " % (100.0 * wins.get([a, b], 0) / maxi(1, games.get(key, 0)))
		print(line)
	quit()
