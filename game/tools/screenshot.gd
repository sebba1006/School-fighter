extends SceneTree
## Dev tool: runs the game for a moment and saves screenshots.
## Needs a display (use xvfb-run on a server):
##   godot --path game -s res://tools/screenshot.gd -- <out_dir>

func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "/tmp"
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	await _snap(out + "/0_menu.png")
	main.show_setup()
	await _frames(10)
	await _snap(out + "/1_setup.png")

	main.show_battle({"map": "classroom", "rounds": 3, "seed": 5, "first_team": 0,
		"players": [{"char": "sebba", "team": 0}, {"char": "mike", "team": 1}]})
	await create_timer(1.2).timeout
	await _snap(out + "/2_battle_start.png")

	var screen = main._screen
	var b = screen.battle
	for d in [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.DOWN]:
		screen._on_dir(d)
		await create_timer(0.3).timeout
	screen._on_attack_pressed(3)
	await _frames(5)
	await _snap(out + "/3_aim_charge.png")
	screen._confirm()
	await create_timer(2.0).timeout
	await _snap(out + "/4_after_charge.png")

	main.show_battle({"map": "gym", "rounds": 1, "seed": 5, "first_team": 1,
		"players": [{"char": "william", "team": 0}, {"char": "snorre", "team": 1}]})
	await create_timer(1.2).timeout
	screen = main._screen
	screen.battle.fighters[1].meter = 100
	screen._refresh()
	screen._on_attack_pressed(4)
	await _frames(5)
	await _snap(out + "/5_gym_super_aim.png")

	main.show_battle({"map": "hallway", "rounds": 1, "seed": 5, "first_team": 0,
		"players": [{"char": "mike", "team": 0}, {"char": "william", "team": 1}]})
	await create_timer(1.2).timeout
	screen = main._screen
	screen._on_attack_pressed(3)
	screen._on_dir(Vector2i.RIGHT)
	await _frames(5)
	await _snap(out + "/6_hallway_lob.png")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
