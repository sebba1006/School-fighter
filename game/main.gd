extends Node
## Entry point: registers the keyboard controls and switches between screens.

const UiTheme = preload("res://ui/ui_theme.gd")
const SetupScreen = preload("res://screens/setup_screen.gd")
const BattleScreen = preload("res://screens/battle_screen.gd")

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


func _ready() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	RenderingServer.set_default_clear_color(UiTheme.BOARD)
	show_setup()


func _swap(screen: Node) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	add_child(screen)


func show_setup() -> void:
	var s := SetupScreen.new()
	s.start_requested.connect(show_battle)
	_swap(s)


func show_battle(config: Dictionary) -> void:
	_last_config = config
	var b := BattleScreen.new()
	b.setup(config)
	b.menu_requested.connect(show_setup)
	b.rematch_requested.connect(func(): show_battle(_last_config))
	_swap(b)
