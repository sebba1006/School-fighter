extends Node
## Entry point: registers the keyboard controls and switches between screens.
## Started with `-- --server` it runs the online game server instead (no UI).

const UiTheme = preload("res://ui/ui_theme.gd")
const MenuScreen = preload("res://screens/menu_screen.gd")
const SetupScreen = preload("res://screens/setup_screen.gd")
const OnlineScreen = preload("res://screens/online_screen.gd")
const BattleScreen = preload("res://screens/battle_screen.gd")
const Server = preload("res://net/server.gd")
const Client = preload("res://net/client.gd")
const Config = preload("res://net/config.gd")
const Audio = preload("res://audio/audio.gd")
const HowtoScreen = preload("res://screens/howto_screen.gd")
const StatsScreen = preload("res://screens/stats_screen.gd")
const Stats = preload("res://stats/stats.gd")

const KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"attack_1": [KEY_1],
	"attack_2": [KEY_2],
	"attack_3": [KEY_3],
	"attack_4": [KEY_4],
	"attack_super": [KEY_Q],
	"confirm": [KEY_SPACE],
	"end_turn": [KEY_E, KEY_ENTER],
	"undo": [KEY_Z, KEY_BACKSPACE],
	"cancel": [KEY_ESCAPE],
}

var _screen: Node
var _last_config := {}
var client: Node
var _lobby := {}
## Tests running two games in one process turn this off so they don't share a saved login.
var persist_online := true


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--server"):
		_run_server()
		return
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	RenderingServer.set_default_clear_color(UiTheme.BOARD)
	get_viewport().size_changed.connect(_fit_screen)
	if not persist_online:
		Stats.enabled = false  # test runs don't touch the real stats
	if Audio.instance == null:
		add_child(Audio.new())
	client = Client.new()
	client.persist = persist_online
	add_child(client)
	client.message.connect(_on_net_message)
	show_menu()


func _run_server() -> void:
	var port := int(OS.get_environment("PORT")) if OS.get_environment("PORT").is_valid_int() else Config.DEFAULT_PORT
	var server := Server.new()
	add_child(server)
	if server.start(port) != OK:
		push_error("could not listen on port %d" % port)
		get_tree().quit(1)


func _swap(screen: Node) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(screen)
	_fit_screen()


## Screens fill the window. (Main isn't a Control, so anchors alone don't
## follow the window when it resizes, e.g. while a web page is loading.)
func _fit_screen() -> void:
	if _screen is Control:
		_screen.position = Vector2.ZERO
		_screen.set_deferred("size", get_viewport().get_visible_rect().size)


func show_menu() -> void:
	var m := MenuScreen.new()
	m.online_pressed.connect(func(): show_online(_lobby if client.status == "online" else {}))
	m.local_pressed.connect(show_setup)
	m.stats_pressed.connect(func():
		var st := StatsScreen.new()
		st.back_requested.connect(show_menu)
		_swap(st))
	m.howto_pressed.connect(func():
		var h := HowtoScreen.new()
		h.back_requested.connect(show_menu)
		_swap(h))
	_swap(m)


func show_setup() -> void:
	var s := SetupScreen.new()
	s.start_requested.connect(show_battle)
	s.back_requested.connect(show_menu)
	_swap(s)


func show_online(state := {}) -> void:
	var o := OnlineScreen.new()
	o.setup(client, state)
	o.back_requested.connect(func():
		client.send({"t": "leave"})
		client.go_offline()
		_lobby = {}
		show_menu())
	_swap(o)


func _on_net_message(msg: Dictionary) -> void:
	match msg.get("t"):
		"lobby":
			_lobby = msg
			if _screen is BattleScreen and _screen.online():
				if not msg.in_match:
					show_online(msg)  # the host took everyone back to the lobby
				else:
					_screen.set_host(msg.host_pid == msg.you_pid)
		"left":
			_lobby = {}
		"match_start":
			_start_online_battle(msg.config, msg.you, [], -1)
		"match_sync":
			# A battle screen already open handles it itself (after a reconnect).
			if not (_screen is BattleScreen and _screen.online()):
				_start_online_battle(msg.config, msg.you, msg.ops, msg.turn_ms)


func _start_online_battle(config: Dictionary, you: int, past_ops: Array, turn_ms: int) -> void:
	var b := BattleScreen.new()
	b.setup_online(config, client, you, _lobby.get("host_pid", -1) == _lobby.get("you_pid", -2), past_ops, turn_ms)
	b.leave_requested.connect(func():
		client.send({"t": "leave"})
		_lobby = {}
		show_online({}))
	_swap(b)


func show_battle(config: Dictionary) -> void:
	_last_config = config
	var b := BattleScreen.new()
	b.setup(config)
	b.menu_requested.connect(show_menu)
	b.rematch_requested.connect(func(): show_battle(_last_config))
	_swap(b)
