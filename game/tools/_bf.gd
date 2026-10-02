extends SceneTree
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://main.tscn").instantiate()
	main.persist_online = false
	root.add_child(main)
	await create_timer(0.3).timeout
	main.show_battle({"boss": true, "seed": 7, "players": [
		{"char": "sebba", "team": 0}, {"char": "mike", "team": 0, "cpu": "normal"}, {"char": "leon", "team": 0, "cpu": "normal"}]})
	await create_timer(1.5).timeout
	var bs = main._screen
	var b = bs.battle
	await _snap(out + "/bf1_start.png")
	var shot := false
	var t0 := Time.get_ticks_msec()
	var apple_shot := false
	while Time.get_ticks_msec() - t0 < 40000 and b.phase == 1:
		await process_frame
		if not shot and bs.busy and b.current().is_boss == false and b.fighters[3].hp < 2000 and bs.get_children().any(func(c): return false):
			pass
		if bs._my_turn() and not bs.busy:
			# walk next to the boss and punch if possible, else end turn
			var me = b.fighters[0]
			var target := Vector2i(b.boss().pos.x - 2, b.boss().pos.y)
			if me.pos != target and not b.route_to(target).is_empty():
				bs._on_tile_tapped(target)
				await create_timer(1.0).timeout
				continue
			if me.pos == target:
				bs._on_attack_pressed(0)
				bs._on_dir(Vector2i.RIGHT)
				bs._confirm()
			else:
				bs._on_end_turn()
			await create_timer(0.3).timeout
		if not apple_shot and not bs.apple_nodes.is_empty():
			apple_shot = true
			await create_timer(0.5).timeout
			await _snap(out + "/bf3_apple.png")
	await _snap(out + "/bf4_end.png")
	print("boss hp ", b.boss().hp, " players ", b.fighters.slice(0, 3).map(func(f): return f.hp), " phase ", b.phase)
	quit()
func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
