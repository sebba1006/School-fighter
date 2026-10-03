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
	var dir := "/tmp/claude-0/-home-user-School-fighter/3f461093-9289-5f35-91b2-1e89856457f4/scratchpad"
	out = dir
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
	var a: Node = games[0].main
	var b: Node = games[1].main
	a.show_cpu("boss")
	await _wait(0.3)
	await _snap(0, "bf_cpu_screen")
	a._screen.online_boss_requested.emit("principal")
	await _wait(0.3)
	await _snap(0, "bf_online_entry")
	a._screen._name_edit.text = "Sebba"
	a._screen._server_edit.text = url
	a._screen._on_create()
	if not await _until(func(): return a._screen.lobby.get("settings", {}).get("boss", false), 8.0):
		_fail("boss not on: " + str(a._screen.lobby))
		return
	var code: String = a._screen.lobby.code
	print("boss lobby ", code, " boss=", a._screen.lobby.settings.boss_id)
	b.show_online({})
	await _wait(0.2)
	b._screen._name_edit.text = "Tom"
	b._screen._server_edit.text = url
	b._screen._code_edit.text = code
	b._screen._on_join()
	if not await _until(func(): return b._screen.lobby.get("members", []).size() == 2, 5.0):
		_fail("join failed: " + b._screen._status.text)
		return
	print("friend joined the boss lobby: ", b._screen.lobby.members.size(), " players")
	await _wait(0.3)
	await _snap(0, "bf_lobby_host")
	quit()


func _fail(why: String) -> void:
	print("FAIL ", why)
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
