extends Control
## Fight against the computer: pick the mode (1v1, 1v1v1, 1v1v1v1 or 2v2 with a CPU
## teammate), the CPU difficulty, every fighter, the map and rounds.
## You are always player 1. Tap a slot (YOU / CPU) to choose its fighter below.

signal start_requested(config: Dictionary)
signal back_requested
## Boss mode: play the chosen boss online with friends instead of CPUs.
signal online_boss_requested(boss_id: String)

const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const FighterInfo = preload("res://ui/fighter_info.gd")
const FighterPicker = preload("res://ui/fighter_picker.gd")
const Battle = preload("res://rules/battle.gd")
const Audio = preload("res://audio/audio.gd")
const Achievements = preload("res://stats/achievements.gd")

const MODES := {"1v1": "1V1", "ffa": "1V1V1", "ffa4": "1V1V1V1", "2v2": "2V2", "boss": "BOSS"}
const LEVELS := {"easy": "EASY", "normal": "NORMAL", "hard": "HARD"}
const RANDOM := "random"

var mode := "1v1"
var level := "normal"
var picks := ["sebba", RANDOM, RANDOM, RANDOM]  # slot 0 = you
var slot := 0  # which slot the fighter row is choosing for
var map_id := "classroom"
var rounds := 3
var items := true
var bonus_hp := 0
var shrink := false

var _mode_buttons := {}
var _level_buttons := {}
var _slot_row: HBoxContainer
var _picker: FighterPicker
var _map_buttons := {}
var _normal_only: Array[Control] = []  # hidden in a boss fight (no map, rounds, HP or shrink)
var _boss_note: Label
var _boss_row: HBoxContainer  # which boss (later ones unlock in order)
var _boss_buttons := {}
var boss_id := "principal"
var _friends_button: Button
var _rounds_label: Label
var _info: Label


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)

	var title := UiTheme.label("VS CPU", 24, UiTheme.CHALK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var top := _row(col)
	top.add_child(UiTheme.label("MODE", 8, UiTheme.CHALK_DIM))
	for id in MODES:
		var b := _toggle(MODES[id])
		b.pressed.connect(func(): mode = id; slot = mini(slot, _slot_count() - 1); _rebuild_slots(); _refresh())
		_mode_buttons[id] = b
		top.add_child(b)
	# CPU difficulty (hidden in a boss fight: the CPUs there are always NORMAL)
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 4)
	top.add_child(levels)
	_normal_only.append(levels)
	levels.add_child(_gap(12))
	levels.add_child(UiTheme.label("CPU", 8, UiTheme.CHALK_DIM))
	for id in LEVELS:
		var b := _toggle(LEVELS[id])
		b.pressed.connect(func(): level = id; _refresh())
		_level_buttons[id] = b
		levels.add_child(b)

	_slot_row = _row(col)
	_slot_row.add_theme_constant_override("separation", 6)

	_picker = FighterPicker.new(true)
	_picker.picked.connect(_pick)
	col.add_child(_picker)

	_info = UiTheme.label("", 8, UiTheme.CHALK_DIM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.custom_minimum_size.y = 40
	col.add_child(_info)

	_boss_row = _row(col)
	_boss_row.add_child(UiTheme.label("BOSS", 8, UiTheme.CHALK_DIM))
	var saved := Achievements.load_data()
	for id in Characters.BOSSES:
		var b := _toggle(Characters.BOSSES[id].def.short.to_upper())
		b.custom_minimum_size = Vector2(110, 20)
		if not Achievements.boss_unlocked(saved, id):
			b.disabled = true
			b.text = "LOCKED: BEAT %s" % Characters.BOSSES.values()[Characters.BOSSES.keys().find(id) - 1].def.short.to_upper()
			b.custom_minimum_size.x = 0  # as wide as its text
		b.pressed.connect(func(): boss_id = id; _refresh())
		_boss_buttons[id] = b
		_boss_row.add_child(b)
	_boss_note = UiTheme.label("", 8, UiTheme.HIT)
	_boss_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_boss_note)
	var options := _row(col)
	_normal_only.append(options)
	options.add_child(UiTheme.label("MAP", 8, UiTheme.CHALK_DIM))
	for id in Maps.ALL:
		var b := _toggle(Maps.ALL[id].name.to_upper())
		b.pressed.connect(func(): map_id = id; _refresh())
		_map_buttons[id] = b
		options.add_child(b)
	options = _row(col)  # rounds and items on their own row
	var rounds_box := HBoxContainer.new()
	rounds_box.add_theme_constant_override("separation", 4)
	options.add_child(rounds_box)
	_normal_only.append(rounds_box)
	rounds_box.add_child(UiTheme.label("ROUNDS", 8, UiTheme.CHALK_DIM))
	rounds_box.add_child(_small("-", func(): rounds = maxi(1, rounds - 1); _refresh()))
	_rounds_label = UiTheme.label("3", 16, UiTheme.CHALK)
	_rounds_label.custom_minimum_size = Vector2(16, 0)
	_rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rounds_box.add_child(_rounds_label)
	rounds_box.add_child(_small("+", func(): rounds = mini(5, rounds + 1); _refresh()))
	rounds_box.add_child(_gap(16))
	var it := Button.new()
	it.custom_minimum_size = Vector2(70, 20)
	it.text = "ITEMS ON"
	it.pressed.connect(func():
		items = not items
		it.text = "ITEMS ON" if items else "ITEMS OFF")
	options.add_child(it)
	var hpb := Button.new()
	hpb.custom_minimum_size = Vector2(80, 20)
	hpb.text = "HP: ORIGINAL"
	hpb.pressed.connect(func():
		var choices: Array = Battle.BONUS_HP_CHOICES
		bonus_hp = choices[(choices.find(bonus_hp) + 1) % choices.size()]
		hpb.text = "HP: ORIGINAL" if bonus_hp == 0 else "HP: +%d" % bonus_hp)
	options.add_child(hpb)
	_normal_only.append(hpb)
	var shb := Button.new()
	shb.custom_minimum_size = Vector2(76, 20)
	shb.text = "SHRINK OFF"
	shb.pressed.connect(func():
		shrink = not shrink
		shb.text = "SHRINK ON" if shrink else "SHRINK OFF")
	options.add_child(shb)
	_normal_only.append(shb)

	var buttons := _row(col)
	buttons.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 30)
	back.pressed.connect(func(): back_requested.emit())
	buttons.add_child(back)
	var start := Button.new()
	start.text = "START FIGHT"
	start.add_theme_font_override("font", UiTheme.title_font())
	start.add_theme_font_size_override("font_size", 16)
	start.custom_minimum_size = Vector2(160, 30)
	start.pressed.connect(_start)
	buttons.add_child(start)
	_friends_button = Button.new()
	_friends_button.text = "WITH FRIENDS ONLINE"
	_friends_button.custom_minimum_size = Vector2(150, 30)
	_friends_button.add_theme_color_override("font_color", UiTheme.HIT)
	_friends_button.pressed.connect(func():
		Audio.play("click")
		online_boss_requested.emit(boss_id))
	buttons.add_child(_friends_button)

	_rebuild_slots()
	_refresh()


func _slot_count() -> int:
	return {"1v1": 2, "ffa": 3, "ffa4": 4, "2v2": 4, "boss": 3}[mode]


## Opens the screen straight in a mode (the menu's BOSS FIGHT button uses "boss").
func set_mode(m: String) -> void:
	mode = m
	slot = 0


## Team of each slot: 2v2 = you + CPU teammate vs two CPUs; otherwise everyone alone.
func _team(i: int) -> int:
	if mode == "boss":
		return 0
	if mode == "2v2":
		return 0 if i < 2 else 1
	return i


func _slot_title(i: int) -> String:
	if i == 0:
		return "YOU"
	if mode == "boss":
		return "TEAMMATE %d" % i
	if mode == "2v2" and i == 1:
		return "TEAMMATE"
	return "CPU %d" % (i if mode != "2v2" else i - 1)


func _rebuild_slots() -> void:
	for c in _slot_row.get_children():
		c.queue_free()
	for i in _slot_count():
		var b := _toggle("")
		b.custom_minimum_size = Vector2(96, 26)
		b.pressed.connect(func(): slot = i; Audio.play("click"); _refresh())
		b.set_meta("slot", i)
		_slot_row.add_child(b)


func _pick(id: String) -> void:
	Audio.play("click")
	picks[slot] = id
	_refresh()


## Fighters picked by slots other than `except` (RANDOM doesn't count).
func _taken(except: int) -> Array:
	var out := []
	for i in _slot_count():
		if i != except and picks[i] != RANDOM:
			out.append(picks[i])
	return out


func _refresh() -> void:
	for id in _mode_buttons:
		_mode_buttons[id].set_pressed_no_signal(id == mode)
	for id in _level_buttons:
		_level_buttons[id].set_pressed_no_signal(id == level)
	for b in _slot_row.get_children():
		if b.is_queued_for_deletion():
			continue
		var i: int = b.get_meta("slot")
		var pick: String = picks[i]
		b.text = "%s: %s" % [_slot_title(i), "?" if pick == RANDOM else Characters.ALL[pick].get("short", Characters.ALL[pick].name).to_upper()]
		b.set_pressed_no_signal(i == slot)
		b.add_theme_color_override("font_color", UiTheme.TEAM[_team(i)])
		b.add_theme_color_override("font_pressed_color", UiTheme.TEAM[_team(i)])
	_picker.show_state(picks[slot], _taken(slot))
	var shown: String = picks[slot]
	_info.text = "A RANDOM FIGHTER NOBODY ELSE PICKED" if shown == RANDOM else FighterInfo.summary(shown)
	for id in _map_buttons:
		_map_buttons[id].set_pressed_no_signal(id == map_id)
	_rounds_label.text = str(rounds)
	for c in _normal_only:
		c.visible = mode != "boss"
	_boss_note.visible = mode == "boss"
	_boss_row.visible = mode == "boss"
	_friends_button.visible = mode == "boss"
	for id in _boss_buttons:
		_boss_buttons[id].set_pressed_no_signal(id == boss_id)
	_boss_note.text = "YOU + 2 CPU TEAMMATES VS %s (%d HP)  -  EVERYONE GETS +250 HP  -  CPUS ON NORMAL" % [
		Characters.BOSSES[boss_id].def.name.to_upper(), Characters.BOSSES[boss_id].def.hp]


func _start() -> void:
	Audio.play("click")
	var chosen := _taken(-1)
	var pool := Characters.ALL.keys().filter(func(c): return not chosen.has(c))
	pool.shuffle()
	var players := []
	for i in _slot_count():
		var c: String = picks[i]
		if c == RANDOM:
			c = pool.pop_back()
		var p := {"char": c, "team": _team(i)}
		if i > 0:
			p["cpu"] = "normal" if mode == "boss" else level
		players.append(p)
	if mode == "boss":
		start_requested.emit({"boss": boss_id, "items": items, "players": players, "seed": randi()})
		return
	start_requested.emit({"map": map_id, "rounds": rounds, "items": items, "bonus_hp": bonus_hp, "shrink": shrink, "players": players, "seed": randi()})


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 4)
	parent.add_child(r)
	return r


func _toggle(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	return b


func _small(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(20, 20)
	b.pressed.connect(cb)
	return b


func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c
