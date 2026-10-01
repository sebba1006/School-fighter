extends Control
## Local match setup: each player picks a fighter (no duplicates), then the map
## and number of rounds.

signal start_requested(config: Dictionary)
signal back_requested

const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const FighterInfo = preload("res://ui/fighter_info.gd")
const Battle = preload("res://rules/battle.gd")

var picks := ["sebba", "william"]
var map_id := "classroom"
var rounds := 3
var items := true
var bonus_hp := 0

var _char_buttons := [{}, {}]  # per player: char_id -> Button
var _map_buttons := {}
var _rounds_label: Label
var _info: Label


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)

	var title := UiTheme.label("SCHOOL FIGHTER", 32, UiTheme.CHALK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiTheme.label("local battle - 2 players on one device", 8, UiTheme.CHALK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var players := HBoxContainer.new()
	players.alignment = BoxContainer.ALIGNMENT_CENTER
	players.add_theme_constant_override("separation", 24)
	col.add_child(players)
	for p in 2:
		players.add_child(_player_picker(p))

	_info = UiTheme.label("", 8, UiTheme.CHALK_DIM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.custom_minimum_size.y = 40
	col.add_child(_info)

	var options := HBoxContainer.new()
	options.alignment = BoxContainer.ALIGNMENT_CENTER
	options.add_theme_constant_override("separation", 6)
	col.add_child(options)
	options.add_child(UiTheme.label("MAP", 8, UiTheme.CHALK_DIM))
	for id in Maps.ALL:
		var b := _toggle(Maps.ALL[id].name.to_upper())
		b.pressed.connect(func(): map_id = id; _refresh())
		_map_buttons[id] = b
		options.add_child(b)
	# rounds and items on a second row (all the maps fill the first one)
	options = HBoxContainer.new()
	options.alignment = BoxContainer.ALIGNMENT_CENTER
	options.add_theme_constant_override("separation", 6)
	col.add_child(options)
	options.add_child(UiTheme.label("ROUNDS", 8, UiTheme.CHALK_DIM))
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(20, 20)
	minus.pressed.connect(func(): rounds = maxi(1, rounds - 1); _refresh())
	options.add_child(minus)
	_rounds_label = UiTheme.label("3", 16, UiTheme.CHALK)
	_rounds_label.custom_minimum_size = Vector2(16, 0)
	_rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options.add_child(_rounds_label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(20, 20)
	plus.pressed.connect(func(): rounds = mini(5, rounds + 1); _refresh())
	options.add_child(plus)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	options.add_child(gap)
	options.add_child(_items_toggle())
	options.add_child(_bonus_button())

	var start := Button.new()
	start.text = "START FIGHT"
	start.add_theme_font_override("font", UiTheme.title_font())
	start.add_theme_font_size_override("font_size", 16)
	start.custom_minimum_size = Vector2(160, 30)
	start.pressed.connect(_start)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 30)
	back.pressed.connect(func(): back_requested.emit())
	buttons.add_child(back)
	buttons.add_child(start)
	col.add_child(buttons)

	_info.text = FighterInfo.summary(picks[0])
	_refresh()


func _player_picker(p: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiTheme.label("PLAYER %d" % (p + 1), 8, UiTheme.TEAM[p]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	for id in Characters.ALL:
		var b := _toggle(Characters.ALL[id].name.to_upper().replace(" & ", " &\n"))
		b.icon = PixelArt.character(id)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = Vector2(46, 76)
		b.pressed.connect(func(): picks[p] = id; _info.text = FighterInfo.summary(id); _refresh())
		_char_buttons[p][id] = b
		row.add_child(b)
	return box


## Extra HP for everyone (longer fights): ORIGINAL, +50, +100, +150.
func _bonus_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(80, 20)
	b.text = "HP: ORIGINAL"
	b.pressed.connect(func():
		var choices: Array = Battle.BONUS_HP_CHOICES
		bonus_hp = choices[(choices.find(bonus_hp) + 1) % choices.size()]
		b.text = "HP: ORIGINAL" if bonus_hp == 0 else "HP: +%d" % bonus_hp)
	return b


## "ITEMS ON/OFF": broken lockers can drop items.
func _items_toggle() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(70, 20)
	b.text = "ITEMS ON"
	b.pressed.connect(func():
		items = not items
		b.text = "ITEMS ON" if items else "ITEMS OFF")
	return b


func _toggle(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	return b


func _refresh() -> void:
	for p in 2:
		var other: String = picks[1 - p]
		for id in _char_buttons[p]:
			var b: Button = _char_buttons[p][id]
			b.set_pressed_no_signal(picks[p] == id)
			b.disabled = id == other
	for id in _map_buttons:
		_map_buttons[id].set_pressed_no_signal(id == map_id)
	_rounds_label.text = str(rounds)


func _start() -> void:
	start_requested.emit({
		"map": map_id,
		"rounds": rounds,
		"items": items, "bonus_hp": bonus_hp,
		"players": [{"char": picks[0], "team": 0}, {"char": picks[1], "team": 1}],
		"seed": randi(),
	})
