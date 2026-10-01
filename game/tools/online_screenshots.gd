extends SceneTree
## Dev tool: two game instances side by side against a running server, going
## through create -> join -> pick -> start -> fight, saving screenshots.
## Start a server first:  PORT=9124 godot --headless --path game -- --server
## Then (needs a display):  godot --path game -s res://tools/online_screenshots.gd -- <out_dir> [ws://127.0.0.1:9124]

var out := "/tmp"
var url := "ws://127.0.0.1:9124"
var games: Array = []  # [{"vp": SubViewport, "main": Node}]


func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		url = args[1]
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(640, 360)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var main: Node = load("res://main.tscn").instantiate()
		main.persist_online = false
		vp.add_child(main)
		games.append({"vp": vp, "main": main})
	await _wait(0.3)
	await _snap(0, "o1_menu")

	var a: Node = games[0].main
	var b: Node = games[1].main
	a.show_online({})
	b.show_online({})
	await _wait(0.2)
	a._screen._name_edit.text = "Sebba"
	a._screen._server_edit.text = url
	a._screen._on_create()
	if not await _until(func(): return a._screen.lobby.get("code", "") != "", 8.0):
		_fail("no lobby code: " + a._screen._status.text)
		return
	var code: String = a._screen.lobby.code
	print("lobby ", code)
	b._screen._name_edit.text = "Tom"
	b._screen._server_edit.text = url
	b._screen._code_edit.text = code
	await _snap(1, "o2_join_screen")
	b._screen._on_join()
	if not await _until(func(): return b._screen.lobby.get("members", []).size() == 2, 5.0):
		_fail("join failed: " + b._screen._status.text)
		return
	a.client.send({"t": "pick", "char": "sebba"})
	b.client.send({"t": "pick", "char": "mike"})
	a.client.send({"t": "settings", "map": "classroom", "rounds": 3, "timer": 30})
	await _wait(0.4)
	b.client.send({"t": "ready", "ready": true})
	await _wait(0.4)
	await _snap(0, "o3_lobby_host")
	await _snap(1, "o4_lobby_guest")

	a.client.send({"t": "start"})
	var started := func():
		return games.all(func(g): return g.main._screen.has_method("setup_online") and g.main._screen.battle.round_number == 1 and not g.main._screen.busy)
	if not await _until(started, 8.0):
		_fail("battle did not start")
		return
	await _wait(0.3)
	await _snap(0, "o5_battle_a")
	await _snap(1, "o6_battle_b")

	# whoever has the turn walks two steps and aims an attack
	var sa = a._screen
	var sb = b._screen
	var turn = sa if sa.battle.current().id == sa.my_fighter else sb
	var other = sb if turn == sa else sa
	var who := 0 if turn == sa else 1
	var dir := Vector2i.RIGHT if turn.battle.current().pos.x < 5 else Vector2i.LEFT
	for i in 2:
		turn._on_dir(dir)
		await _until(func(): return not turn._waiting and not turn.busy, 3.0)
	turn._on_attack_pressed(1)
	await _wait(0.2)
	await _snap(who, "o7_aiming")
	other._on_dir(Vector2i.UP)  # not their turn: only shows a message
	await _wait(0.1)
	await _snap(1 - who, "o8_waiting")
	turn._confirm()
	var passed := func():
		return sa.battle.state_hash() == sb.battle.state_hash() and not sa.busy and not sb.busy and sa.battle.current().id != turn.my_fighter
	if not await _until(passed, 6.0):
		_fail("turn did not pass / copies differ")
		return
	await _wait(0.4)
	await _snap(0, "o9_after_a")
	await _snap(1, "o10_after_b")
	# emotes: A opens CHAT and sends "GG"; B should see a bubble
	sa._toggle_emotes()
	await _wait(0.2)
	await _snap(0, "o11_chat_open")
	sa._emote_panel.get_child(0).pressed.emit()
	await _wait(0.5)
	await _snap(1, "o12_emote_seen")
	print("ONLINE UI OK")
	quit(0)


func _fail(msg: String) -> void:
	print("ONLINE UI FAILED: ", msg)
	await _snap(0, "fail_a")
	await _snap(1, "fail_b")
	quit(1)


func _snap(i: int, name: String) -> void:
	await RenderingServer.frame_post_draw
	games[i].vp.get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()
