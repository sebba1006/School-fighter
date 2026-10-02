extends SceneTree
## Bug hunt: plays whole matches through the real battle screen with CPUs only
## (every map, 1v1v1, 1v1v1v1, 2v2 and boss fights) and prints how each ended.
## Needs a display:  xvfb-run godot --path game -s res://tools/playthrough.gd
const Maps = preload("res://rules/maps.gd")
const Characters = preload("res://rules/characters.gd")

func _init() -> void:
	Engine.time_scale = 10.0
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	var chars: Array = Characters.ALL.keys()
	var maps: Array = Maps.ALL.keys()
	var cases := []
	var k := 0
	for m in maps:
		cases.append({"map": m, "rounds": 2, "items": true, "shrink": k % 2 == 0, "bonus_hp": 0, "players": _pl(chars, k, [0, 1])})
		k += 1
	cases.append({"map": "gym", "rounds": 1, "items": true, "players": _pl(chars, 1, [0, 1, 2])})
	cases.append({"map": "schoolyard", "rounds": 1, "items": true, "shrink": true, "players": _pl(chars, 2, [0, 1, 2, 3])})
	cases.append({"map": "cafeteria", "rounds": 1, "items": true, "bonus_hp": 150, "players": _pl(chars, 3, [0, 0, 1, 1])})
	for s in 3:
		cases.append({"boss": true, "items": true, "players": _pl(chars, s, [0, 0, 0])})
	for c in cases:
		c["seed"] = k
		k += 1
		main.show_battle(c)
		var screen = main._screen
		var t0 := Time.get_ticks_msec()
		var b = screen.battle
		while not (b.phase == 3 and screen.mode == "over") and Time.get_ticks_msec() - t0 < 240000:
			await create_timer(0.5).timeout
			if screen.overlay != null and b.phase == 2 and not screen.busy:
				screen._next_round()
		print("CASE %s boss=%s players=%d -> mode=%s phase=%s round=%d winner=%d turns=%d" % [c.get("map", "office"), c.get("boss", false), c.players.size(), screen.mode, b.phase, b.round_number, b.match_winner, b._turn_count])
	quit()

func _pl(chars: Array, k: int, teams: Array) -> Array:
	var out := []
	for i in teams.size():
		out.append({"char": chars[(k + i * 2) % chars.size()], "team": teams[i], "cpu": "hard"})
	return out
