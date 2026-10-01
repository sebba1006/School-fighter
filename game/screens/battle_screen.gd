extends Control
## Battle screen: draws the board, reads joystick / keyboard / buttons, sends
## intents to the rules engine and animates the events that come back.
## All game logic lives in rules/battle.gd; this file only shows it.
##
## Local mode: intents go straight into the local battle.
## Online mode (`net` set): intents go to the server, and every accepted move
## ("op") comes back from it and is applied to the local copy of the battle,
## in the same order for everyone.

signal menu_requested
signal rematch_requested
## Online: the player pressed LEAVE.
signal leave_requested

const Battle = preload("res://rules/battle.gd")
const Maps = preload("res://rules/maps.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Joystick = preload("res://ui/joystick.gd")
const FighterView = preload("res://screens/fighter_view.gd")
const FighterInfo = preload("res://ui/fighter_info.gd")
const Audio = preload("res://audio/audio.gd")
const Stats = preload("res://stats/stats.gd")
const Bot = preload("res://ai/bot.gd")

const TILE := 32
const TOP_H := 30
## Right column (attacks, UNDO, END TURN, USE) and the joystick's corner on the left.
const SIDE_W := 124
const JOY_COL := 128
const JOY_RADIUS := 50.0
const HINT_H := 18

const ERRORS := {
	"blocked": "CAN'T WALK THERE",
	"no_moves_left": "NO MOVES LEFT - PICK AN ATTACK OR END TURN",
	"nothing_to_undo": "NOTHING TO UNDO",
	"cannot_attack": "SUGAR CRASH - NO ATTACK THIS TURN",
	"super_not_ready": "SUPER NOT READY - FILL THE METER",
	"no_target": "NO ENEMY IN REACH",
	"bad_dist": "OUT OF RANGE",
	"bad_dir": "PICK A DIRECTION",
	"already_active": "ALREADY ON A SUGAR RUSH",
	"not_your_turn": "NOT YOUR TURN",
	"not_in_turn": "WAIT FOR THE NEXT TURN",
	"offline": "NOT CONNECTED - RECONNECTING...",
	"no_item": "NO ITEM - BREAK A LOCKER TO FIND ONE",
	"no_room": "NO ROOM TO SPILL THERE",
}
## Quick-chat emotes (online). The server only relays the number.
## New ones go at the end: the number is what gets sent.
const EMOTES := ["GG", "NICE!", "HAHA", "OOPS", "NOOO", "GOOD LUCK",
	"HI!", "WOW", "SORRY", "THANKS", "WATCH THIS!", "LUCKY!", "HELP ME!", "NICE TEAM", "SO CLOSE", "REMATCH?"]
const STATUS_TEXT := {
	"dizzy": ["DIZZY", UiTheme.DIZZY],
	"rage": ["RAGE!", UiTheme.HIT],
	"block": ["BLOCK", UiTheme.CHALK],
	"sugar_rush": ["SUGAR RUSH!", UiTheme.GOLD],
}

var config: Dictionary
var battle: Battle

var board := Node2D.new()
var floor_layer := FloorLayer.new()
var highlight := HighlightLayer.new()
var obstacle_nodes := {}  # Vector2i -> Sprite2D
var puddle_nodes := {}  # Vector2i -> Sprite2D
var box_node: Sprite2D = null  # the mystery box, when there is one
var fighter_views: Array = []

var busy := false
var mode := "move"  # "move", "aim" or "over"
var aim_slot := -1
var aim_dir := Vector2i.RIGHT
var aim_dist := 2

var panels: Array = []  # per fighter: {"hp": Bar, "meter": Bar, "hp_text": Label, "status": Label}
var round_label: Label
var hint_label: Label
var attack_buttons: Array[Button] = []
var attack_names: Array[Label] = []
var attack_infos: Array[Label] = []
var super_bar: Bar
var item_button: Button  # the held item, above the joystick (hidden when empty)
var item_name: Label
var item_info: Label
var item_icon: TextureRect
var undo_button: Button
var ok_button: Button
var end_button: Button
var joystick: Control
var leave_button: Button
var sound_button: Button
var chat_button: Button
var _emote_panel: GridContainer
var _confirm_box: PanelContainer
## Tiles still to walk after tapping a blue tile.
var _auto_path: Array[Vector2i] = []
## Last tile tapped while aiming; tapping it again uses the attack.
var _aim_tap := Vector2i(-99, -99)
var overlay: PanelContainer
var _overlay_event := {}
var _overlay_is_match := false
var _hint_error_until := 0

# online
var net: Node = null
var my_fighter := -1
var is_host := false
var _waiting := false  # sent an intent, waiting for the server
var _ops: Array = []
var _playing_ops := false
var _turn_end_at := 0  # msec, 0 = no timer
## fighter id -> HP currently shown in the top bars
var _hp_shown := {}
# for your stats
var _last_attacker := -1
var _my_damage := 0
var _my_kos := 0
var _my_supers := 0
var _stats_saved := false
var _cpu_running := false  # a CPU fighter is playing its turn


## Local battle.
## Local battle. Players with a "cpu" level ("easy", "normal", "hard") are
## played by the computer; against CPUs you are always fighter 0.
func setup(p_config: Dictionary) -> void:
	config = p_config
	battle = Battle.new(config)
	if vs_cpu():
		my_fighter = 0


## Online battle. `past_ops` are replayed silently (rejoining a running match).
func setup_online(p_config: Dictionary, p_net: Node, you: int, host: bool, past_ops := [], turn_ms := -1) -> void:
	config = p_config
	net = p_net
	my_fighter = you
	is_host = host
	battle = Battle.new(config)
	for op in past_ops:
		_apply_op(op)
	_turn_end_at = Time.get_ticks_msec() + turn_ms if turn_ms >= 0 else 0
	net.message.connect(_on_net_message)


func online() -> bool:
	return net != null


## Local match against the computer.
func vs_cpu() -> bool:
	return not online() and config.players.any(func(p): return p.has("cpu"))


func _is_cpu(id: int) -> bool:
	return not online() and config.players[id].has("cpu")


func set_host(v: bool) -> void:
	if v == is_host:
		return
	is_host = v
	if overlay != null:
		_show_overlay(_overlay_event, _overlay_is_match)


func _name_of(f) -> String:
	if online():
		return "%s (%s)" % [str(config.players[f.id].get("name", "?")).to_upper(), f.def.name.to_upper()]
	if _is_cpu(f.id):
		return "CPU %s" % f.def.name.to_upper()
	if vs_cpu():
		return "YOU (%s)" % f.def.name.to_upper()
	return "P%d %s" % [f.id + 1, f.def.name.to_upper()]


func _my_turn() -> bool:
	if battle.phase != Battle.Phase.TURN or battle.order.is_empty():
		return false
	if online():
		return battle.current().id == my_fighter
	return not _is_cpu(battle.current().id)


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # taps on the board reach _unhandled_input
	add_child(board)
	floor_layer.z_index = -1000
	highlight.z_index = -900
	board.add_child(floor_layer)
	board.add_child(highlight)
	_build_hud()
	get_viewport().size_changed.connect(_layout)
	Audio.start_music()
	if not online():
		_start_round()
	elif battle.round_number > 0:
		_rebuild_from_state()
	else:
		_layout()
		_refresh()


# ---------------------------------------------------------------- building

func _build_board() -> void:
	for n in obstacle_nodes.values() + puddle_nodes.values():
		n.queue_free()
	obstacle_nodes.clear()
	puddle_nodes.clear()
	for t in battle.puddles:
		_add_puddle(t)
	if box_node != null:
		box_node.queue_free()
		box_node = null
	if battle.box != Battle.NO_BOX:
		_add_box(battle.box)
	floor_layer.size = Vector2i(battle.width, battle.height)
	floor_layer.style = battle.map_def.get("floor", "lino")
	floor_layer.sand = battle.sand
	floor_layer.queue_redraw()
	for t in battle.obstacles:
		var s := Sprite2D.new()
		s.texture = PixelArt.obstacle(battle.obstacles[t].type, false, t.y == 0)
		s.centered = false
		s.position = Vector2(t.x * TILE, t.y * TILE - 16)
		s.z_index = t.y * 10
		board.add_child(s)
		obstacle_nodes[t] = s
	if fighter_views.is_empty():
		for f in battle.fighters:
			var v := FighterView.new()
			v.setup(f.char_id, UiTheme.TEAM[battle.teams.find(f.team)])
			board.add_child(v)
			fighter_views.append(v)
	for f in battle.fighters:
		var v = fighter_views[f.id]
		v.knocked_out = false
		v.set_tile(f.pos)
		v.get_child(0).rotation = 0
		v.get_child(0).position = Vector2(0, -16)
		v.get_child(0).modulate = Color.WHITE
		if not f.alive():
			v.knock_out()
	_layout()


func _build_hud() -> void:
	var n := battle.fighters.size()
	for f in battle.fighters:
		var color: Color = UiTheme.TEAM[battle.teams.find(f.team)]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.add_child(UiTheme.label(_name_of(f), 8, color))
		var status := UiTheme.label("", 8, UiTheme.GOLD)
		head.add_child(status)
		box.add_child(head)
		var hp_row := HBoxContainer.new()
		hp_row.add_theme_constant_override("separation", 3)
		var hp := Bar.new()
		hp.color = UiTheme.HIT
		hp.custom_minimum_size = Vector2(110 if n == 2 else 80, 6)
		hp_row.add_child(hp)
		var hp_text := UiTheme.label("", 8, UiTheme.CHALK)
		hp_row.add_child(hp_text)
		box.add_child(hp_row)
		var meter := Bar.new()
		meter.color = UiTheme.GOLD
		meter.custom_minimum_size = Vector2(110 if n == 2 else 80, 3)
		box.add_child(meter)
		add_child(box)
		panels.append({"box": box, "hp": hp, "hp_text": hp_text, "meter": meter, "status": status})

	round_label = UiTheme.label("", 8, UiTheme.CHALK_DIM)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(round_label)
	leave_button = _top_button("LEAVE", _ask_leave)
	sound_button = _top_button("SOUND ON" if Audio.is_enabled() else "SOUND OFF", _toggle_sound)
	if online():
		chat_button = _top_button("CHAT", _toggle_emotes)
		_emote_panel = GridContainer.new()
		_emote_panel.columns = 4
		_emote_panel.add_theme_constant_override("h_separation", 3)
		_emote_panel.add_theme_constant_override("v_separation", 3)
		_emote_panel.z_index = 4080
		_emote_panel.visible = false
		for i in EMOTES.size():
			var b := Button.new()
			b.text = EMOTES[i]
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func():
				net.send({"t": "emote", "id": i})
				_emote_panel.visible = false)
			_emote_panel.add_child(b)
		add_child(_emote_panel)

	joystick = Joystick.new()
	joystick.radius = JOY_RADIUS
	joystick.flicked.connect(_on_dir)
	add_child(joystick)

	# attack cards: name on top, damage underneath
	for slot in 5:
		var b := Button.new()
		b.custom_minimum_size = Vector2(SIDE_W, 32)
		b.size = b.custom_minimum_size
		b.pressed.connect(_on_attack_pressed.bind(slot))
		b.focus_mode = Control.FOCUS_NONE
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.position = Vector2(6, 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name := UiTheme.label("", 8, UiTheme.CHALK)
		var info := UiTheme.label("", 8, UiTheme.GOLD)
		for l in [name, info]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.clip_text = true
			l.custom_minimum_size.x = SIDE_W - 12
			col.add_child(l)
		b.add_child(col)
		if slot == Battle.SUPER_SLOT:
			# how full the super meter is, along the bottom of the card
			super_bar = Bar.new()
			super_bar.color = UiTheme.GOLD
			super_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			super_bar.position = Vector2(3, 27)
			super_bar.size = Vector2(SIDE_W - 6, 3)
			b.add_child(super_bar)
		add_child(b)
		attack_buttons.append(b)
		attack_names.append(name)
		attack_infos.append(info)
	item_button = Button.new()
	item_button.custom_minimum_size = Vector2(JOY_COL - 12, 32)
	item_button.size = item_button.custom_minimum_size
	item_button.focus_mode = Control.FOCUS_NONE
	item_button.pressed.connect(_on_attack_pressed.bind(Battle.ITEM_SLOT))
	item_icon = TextureRect.new()
	item_icon.position = Vector2(4, 8)
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_button.add_child(item_icon)
	var icol := VBoxContainer.new()
	icol.add_theme_constant_override("separation", 1)
	icol.position = Vector2(24, 4)
	icol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_name = UiTheme.label("", 8, UiTheme.CHALK)
	item_info = UiTheme.label("", 8, UiTheme.GOLD)
	for l in [item_name, item_info]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.clip_text = true
		l.custom_minimum_size.x = JOY_COL - 40
		icol.add_child(l)
	item_button.add_child(icol)
	item_button.visible = false
	add_child(item_button)
	undo_button = _side_button("UNDO", _on_undo, 22, 8)
	end_button = _side_button("END TURN", _on_end_turn, 26, 8)
	ok_button = _side_button("USE", _confirm, 44, 16)

	hint_label = UiTheme.label("", 8, UiTheme.CHALK_DIM)
	hint_label.clip_text = true
	add_child(hint_label)


## Saves this match to your stats once (online: your result; local: who won).
func _record_stats(winner_team: int) -> void:
	if _stats_saved or vs_cpu():
		return
	_stats_saved = true
	if online():
		var me = battle.fighters[my_fighter]
		Stats.record_online(me.char_id, me.team == winner_team, _my_damage, _my_kos, _my_supers)
	else:
		var played := []
		var winners := []
		for f in battle.fighters:
			played.append(f.char_id)
			if f.team == winner_team:
				winners.append(f.char_id)
		Stats.record_local(played, winners)


func _top_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	# slim buttons: same look as the theme, much less padding
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box: StyleBoxFlat = UiTheme.theme().get_stylebox(state, "Button").duplicate()
		box.content_margin_top = 1
		box.content_margin_bottom = 1
		box.content_margin_left = 4
		box.content_margin_right = 4
		b.add_theme_stylebox_override(state, box)
	b.custom_minimum_size = Vector2(56, 0)
	b.size = Vector2(56, 12)
	b.pressed.connect(callback)
	add_child(b)
	return b


func _toggle_emotes() -> void:
	Audio.play("click")
	_emote_panel.visible = not _emote_panel.visible
	_layout()


## A speech bubble over a fighter for a couple of seconds.
func _show_emote(fighter_id: int, id: int) -> void:
	if id < 0 or id >= EMOTES.size() or fighter_id < 0 or fighter_id >= fighter_views.size():
		return
	Audio.play("turn")
	var v: Node2D = fighter_views[fighter_id]
	var bubble := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.CHALK
	box.border_color = Color("17121c")
	box.set_border_width_all(1)
	box.set_content_margin_all(3)
	bubble.add_theme_stylebox_override("panel", box)
	bubble.add_child(UiTheme.label(EMOTES[id], 8, Color("17121c")))
	bubble.z_index = 4050
	board.add_child(bubble)
	bubble.size = bubble.get_combined_minimum_size()
	bubble.position = v.position + Vector2(16 - bubble.size.x / 2.0, -40)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bubble.queue_free)


func _toggle_sound() -> void:
	Audio.set_enabled(not Audio.is_enabled())
	Audio.play("click")
	_refresh()


## LEAVE asks first; online, leaving in the middle of a match counts as a loss.
func _ask_leave() -> void:
	if _confirm_box != null:
		return
	Audio.play("click")
	_confirm_box = PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_confirm_box.add_child(col)
	var title := UiTheme.label("LEAVE THE MATCH?", 16, UiTheme.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var note := "YOU LOSE THIS MATCH (FORFEIT)" if online() and battle.phase != Battle.Phase.MATCH_OVER else "THE MATCH WILL END"
	var l := UiTheme.label(note, 8, UiTheme.CHALK_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	row.add_child(_overlay_button("LEAVE", func():
		if online():
			if battle.phase != Battle.Phase.MATCH_OVER:
				_record_stats(-1)  # leaving early counts as a loss
			leave_requested.emit()
		else:
			menu_requested.emit()))
	row.add_child(_overlay_button("KEEP PLAYING", func():
		_confirm_box.queue_free()
		_confirm_box = null))
	_confirm_box.z_index = 4095
	add_child(_confirm_box)
	var vs := get_viewport_rect().size
	_confirm_box.custom_minimum_size = Vector2(260, 70)
	_confirm_box.position = Vector2(floorf((vs.x - 260) / 2.0), floorf((vs.y - 70) / 2.0))


func _side_button(text: String, callback: Callable, h: float, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(SIDE_W, h)
	b.size = b.custom_minimum_size
	b.focus_mode = Control.FOCUS_NONE
	if font_size > 8:
		b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(callback)
	add_child(b)
	return b


func _layout() -> void:
	var vs := get_viewport_rect().size
	var bw := battle.width * TILE
	var bh := battle.height * TILE
	var right_x := vs.x - SIDE_W - 6
	# The board sits between the joystick corner and the right column. A board
	# too wide for that (the Hallway) moves left and to the top instead, above
	# the joystick.
	var area_l := float(JOY_COL)
	var area_r := right_x - 6
	var top := TOP_H + 16.0
	var avail := vs.y - top - HINT_H
	var y := top + floorf(maxf(0.0, avail - bh) / 2.0)
	if bw > area_r - area_l:
		area_l = 4.0
		y = top
	board.position = Vector2(floorf(area_l + maxf(0.0, area_r - area_l - bw) / 2.0), y)

	# top bar: fighters spread across, round info in the middle
	# first half of the fighters on the left, the rest on the right
	var n := panels.size()
	var left := ceili(n / 2.0)
	var w := 150.0 if n == 2 else 122.0
	for i in n:
		var box: Control = panels[i].box
		var x := 6.0 + i * (w + 6) if i < left else vs.x - 6 - w - (n - 1 - i) * (w + 6)
		box.position = Vector2(floorf(x), 3)
	round_label.position = Vector2(floorf(vs.x / 2.0 - 60), 2)
	round_label.size = Vector2(120, 10)
	# small buttons in a centred row under the round label
	var tops := [leave_button, chat_button, sound_button] if chat_button != null else [leave_button, sound_button]
	var row_w := 0.0
	for tb in tops:
		tb.size = tb.get_combined_minimum_size()
		row_w += tb.size.x + 4
	var tx := floorf((vs.x - row_w + 4) / 2.0)
	for tb in tops:
		tb.position = Vector2(tx, 13)
		tx += tb.size.x + 4
	if _emote_panel != null:
		_emote_panel.size = _emote_panel.get_combined_minimum_size()
		# centred over the board, between the joystick column and the attack cards
		var mid := (JOY_COL + right_x) / 2.0
		_emote_panel.position = Vector2(floorf(mid - _emote_panel.size.x / 2.0), 30)

	# joystick: big, bottom-left
	joystick.position = Vector2(8, vs.y - joystick.custom_minimum_size.y - 8)
	item_button.position = Vector2(6, joystick.position.y - item_button.size.y - 4)
	# right column: attacks from the top, actions at the bottom (USE lowest, easy to reach)
	var y2 := TOP_H + 4.0
	for b in attack_buttons:
		b.position = Vector2(right_x, y2)
		y2 += b.size.y + 3
	ok_button.position = Vector2(right_x, vs.y - 6 - ok_button.size.y)
	end_button.position = Vector2(right_x, ok_button.position.y - 4 - end_button.size.y)
	undo_button.position = Vector2(right_x, end_button.position.y - 4 - undo_button.size.y)
	hint_label.position = Vector2(JOY_COL, vs.y - HINT_H + 4)
	hint_label.size = Vector2(right_x - JOY_COL - 6, 10)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = board.get_global_transform_with_canvas().affine_inverse() * event.position
		var t := Vector2i(floori(local.x / TILE), floori(local.y / TILE))
		if battle._in_bounds(t):
			_on_tile_tapped(t)
		return
	if not event is InputEventKey or not event.pressed:
		return
	var dirs := {"move_up": Vector2i.UP, "move_down": Vector2i.DOWN, "move_left": Vector2i.LEFT, "move_right": Vector2i.RIGHT}
	for action in dirs:
		if event.is_action_pressed(action, true):
			_on_dir(dirs[action])
			return
	for i in 4:
		if event.is_action_pressed("attack_%d" % (i + 1)):
			_on_attack_pressed(i)
			return
	if event is InputEventKey and event.keycode == KEY_5:
		_on_attack_pressed(Battle.ITEM_SLOT)
	elif event.is_action_pressed("attack_super"):
		_on_attack_pressed(Battle.SUPER_SLOT)
	elif event.is_action_pressed("confirm"):
		if mode == "over" and overlay != null:
			return
		_confirm()
	elif event.is_action_pressed("undo"):
		_on_undo()
	elif event.is_action_pressed("cancel"):
		_cancel_aim()
	elif event.is_action_pressed("end_turn"):
		_on_end_turn()


## Tapping the board: walk to a blue tile, or aim at a tile (tap it again to use).
func _on_tile_tapped(t: Vector2i) -> void:
	if busy or mode == "over" or _waiting or battle.order.is_empty():
		return
	if not _my_turn():
		_error("not_your_turn")
		return
	var f := battle.current()
	if mode == "move":
		if t == f.pos:
			return
		var path := battle.path_to(t)
		if path.is_empty():
			_error("blocked")
			return
		_auto_path = path
		return
	var atk := _atk(aim_slot)
	if atk.type.begins_with("self"):
		if t == f.pos:
			_confirm()
		return
	var d := t - f.pos
	if d == Vector2i.ZERO:
		return
	var dir := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	var dist := aim_dist
	if atk.type == "lob":
		dist = clampi(maxi(absi(d.x), absi(d.y)), atk.min_range, atk.max_range)
	if t == _aim_tap and dir == aim_dir and dist == aim_dist:
		_confirm()
		return
	_aim_tap = t
	aim_dir = dir
	aim_dist = dist
	_refresh()


func _on_dir(dir: Vector2i) -> void:
	if busy or mode == "over" or _waiting:
		return
	if not _my_turn():
		_error("not_your_turn")
		return
	if mode == "move":
		_send({"type": "move", "dir": dir})
		return
	var atk := _atk(aim_slot)
	if atk.type == "lob" and dir == aim_dir:
		aim_dist = aim_dist + 1 if aim_dist < atk.max_range else atk.min_range
	else:
		aim_dir = dir
	_refresh()


func _on_attack_pressed(slot: int) -> void:
	if busy or mode == "over" or _waiting or not _my_turn():
		return
	Audio.play("click")
	if mode == "aim" and aim_slot == slot:
		_confirm()
		return
	var reason := battle.attack_blocked_reason(battle.current().id, slot)
	if reason != "":
		_error(reason)
		return
	mode = "aim"
	aim_slot = slot
	_aim_tap = Vector2i(-99, -99)
	aim_dir = battle.current().facing
	var atk := _atk(slot)
	if atk.type == "lob":
		aim_dist = atk.min_range
	if atk.type == "leap":
		for d in Battle.DIRS:
			if not battle._leap_target(battle.current(), d, atk["range"]).is_empty():
				aim_dir = d
				break
	_refresh()


func _confirm() -> void:
	if busy or mode != "aim":
		return
	_send({"type": "attack", "slot": aim_slot, "dir": aim_dir, "dist": aim_dist})


func _cancel_aim() -> void:
	if mode == "aim":
		mode = "move"
		_refresh()


func _on_undo() -> void:
	if busy or _waiting or not _my_turn():
		return
	if mode == "aim":
		_cancel_aim()
	elif mode == "move":
		_send({"type": "undo"})


func _on_end_turn() -> void:
	if busy or mode == "over" or _waiting or not _my_turn():
		return
	Audio.play("click")
	mode = "move"
	_send({"type": "end_turn"})


func _atk(slot: int) -> Dictionary:
	if battle.order.is_empty():
		return battle.fighters[maxi(0, my_fighter)].def.attacks[0]
	var atk := battle.slot_attack(battle.current(), slot)
	return atk if not atk.is_empty() else battle.current().def.attacks[0]


# ---------------------------------------------------------------- engine

func _start_round() -> void:
	mode = "move"
	_hp_shown.clear()
	var events := battle.start_round()
	_build_board()
	_refresh()
	busy = true
	await _play(events)
	busy = false
	_refresh()


## Returns false if the move was refused.
func _send(intent: Dictionary) -> bool:
	if online():
		if not net.send({"t": "intent", "intent": intent}):
			_error("offline")
			return false
		_waiting = true
		_refresh()
		return true
	var r := battle.apply(battle.current().id, intent)
	if not r.ok:
		if not _is_cpu(battle.current().id):
			_error(r.error)
		return false
	if intent.type == "attack":
		mode = "move"
	busy = true
	_refresh()
	await _play(r.events)
	busy = false
	_refresh()
	return true


## Plays the current CPU fighter's whole turn through the normal animations.
func _cpu_turn() -> void:
	_cpu_running = true
	var f := battle.current()
	await get_tree().create_timer(0.35).timeout
	var p := Bot.plan_level(battle, config.players[f.id].cpu)
	for t in p.path:
		if not _cpu_still_on(f) or not await _send({"type": "move", "dir": t - f.pos}):
			break
	if _cpu_still_on(f) and not p.intents.is_empty() and p.intents[0].type == "attack":
		await get_tree().create_timer(0.25).timeout
	for intent in p.intents:
		if not _cpu_still_on(f) or not await _send(intent):
			break
	if _cpu_still_on(f):
		await _send({"type": "end_turn"})
	_cpu_running = false


func _cpu_still_on(f) -> bool:
	return is_inside_tree() and battle.phase == Battle.Phase.TURN and battle.current() == f


func _play(events: Array) -> void:
	var round_end := {}
	var match_end := {}
	var leaper := -1
	for i in events.size():
		var e: Dictionary = events[i]
		match e.type:
			"move":
				Audio.play("step")
				await fighter_views[e.fighter].move_to(e.to, 0.06 if e.get("dash", false) else 0.09).finished
			"knockback":
				await fighter_views[e.fighter].move_to(e.to, 0.07).finished
			"attack":
				_last_attacker = e.fighter
				if e["super"] and e.fighter == my_fighter:
					_my_supers += 1
				var f = battle.fighters[e.fighter]
				if e.get("item", false):
					await _use_item_anim(e, events, i)
					continue
				var atk: Dictionary = f.def["super"] if e["super"] else f.def.attacks[_slot_of(f, e.attack)]
				if e["super"]:
					Audio.play("super")
					await _super_cutin(f, atk)
					await _super_move(e, f, atk)
				else:
					_popup(fighter_views[e.fighter], atk.name.to_upper() + "!", UiTheme.CHALK, -30)
					Audio.play("bark" if atk.id == "bark" else "whoosh")
					if e.dir is Vector2i and atk.type != "leap" and atk.type != "dash":
						await fighter_views[e.fighter].lunge(e.dir).finished
			"leap":
				leaper = e.fighter
				_fx("dust", _px_center(fighter_views[e.fighter].position))
				await fighter_views[e.fighter].leap_to(e.to, 0.28).finished
				Audio.play("slam")
				_fx("spark", _tile_center(e.to), {"scale": 1.4})
				_fx("dust", _tile_center(e.to) + Vector2(0, 10))
				await _shake(4)
			"damage":
				var v = fighter_views[e.fighter]
				Audio.play("hit")
				v.flash(UiTheme.HIT)
				_hp_shown[e.fighter] = e.hp
				if _last_attacker == my_fighter and e.fighter != my_fighter:
					_my_damage += e.amount - e.absorbed
				var text := "-%d" % (e.amount - e.absorbed)
				if e.absorbed > 0:
					text += " (SHIELD %d)" % e.absorbed
				if e.get("guarded", 0) > 0:
					text += " (GUARD %d)" % e.guarded
				_popup(v, text, UiTheme.HIT)
				_refresh_panels()
				await get_tree().create_timer(0.18).timeout
			"hidden":
				_popup(fighter_views[e.fighter], "HIDDEN!", UiTheme.CHALK, -36)
				await get_tree().create_timer(0.2).timeout
			"blocked":
				Audio.play("block")
				_popup(fighter_views[e.fighter], "BLOCKED!", UiTheme.CHALK)
				await get_tree().create_timer(0.25).timeout
			"slam":
				Audio.play("slam")
				_popup(fighter_views[e.fighter], "SLAM!", UiTheme.GOLD, -44)
				await _shake()
			"obstacle_damage":
				var s: Sprite2D = obstacle_nodes.get(e.at)
				if s != null:
					if battle.obstacles.has(e.at):
						var kind: String = battle.obstacles[e.at].type
						if e.hp * 2 <= Maps.OBSTACLE_HP[kind]:
							s.texture = PixelArt.obstacle(kind, true, e.at.y == 0)
					s.modulate = Color(1.6, 1.6, 1.6)
					create_tween().tween_property(s, "modulate", Color.WHITE, 0.2)
			"obstacle_broken":
				var s: Sprite2D = obstacle_nodes.get(e.at)
				if s != null:
					obstacle_nodes.erase(e.at)
					Audio.play("break")
					var tw := create_tween().set_parallel()
					tw.tween_property(s, "modulate:a", 0.0, 0.25)
					tw.tween_property(s, "position:y", s.position.y + 6, 0.25)
					tw.chain().tween_callback(s.queue_free)
			"box":
				Audio.play("turn")
				_add_box(e.at, true)
				_popup_at(_tile_center(e.at) + Vector2(0, -20), "MYSTERY BOX!", UiTheme.GOLD)
				await get_tree().create_timer(0.35).timeout
			"item":
				if e.item == "shield" and box_node != null:
					box_node.queue_free()
					box_node = null
				Audio.play("pickup")
				var name: String = Battle.ITEMS[e.item].name.to_upper()
				_popup(fighter_views[e.fighter], "GOT %s!" % name, UiTheme.GOLD, -44)
				var icon := Sprite2D.new()
				icon.texture = PixelArt.item_icon(e.item)
				icon.position = _tile_center(e.at)
				icon.z_index = 4000
				board.add_child(icon)
				var tw := create_tween()
				tw.tween_property(icon, "position", icon.position + Vector2(0, -14), 0.2)
				tw.tween_property(icon, "position", fighter_views[e.fighter].position + Vector2(0, -20), 0.25)
				tw.tween_callback(icon.queue_free)
				await tw.finished
				_refresh()
			"puddle":
				Audio.play("splash")
				_add_puddle(e.at, true)
				await get_tree().create_timer(0.25).timeout
			"slip":
				Audio.play("slip")
				var pn: Sprite2D = puddle_nodes.get(e.at)
				if pn != null:
					puddle_nodes.erase(e.at)
					create_tween().tween_property(pn, "modulate:a", 0.0, 0.4).finished.connect(pn.queue_free)
				var sv = fighter_views[e.fighter]
				_popup(sv, "SLIP!", UiTheme.DIZZY, -40)
				var body: Node2D = sv.get_child(0)
				var tw := create_tween()
				tw.tween_property(body, "rotation", -0.5, 0.1)
				tw.tween_property(body, "rotation", 0.0, 0.2)
				await tw.finished
			"ko":
				if _last_attacker == my_fighter and e.fighter != my_fighter:
					_my_kos += 1
				Audio.play("ko")
				_popup(fighter_views[e.fighter], "KO!", UiTheme.HIT, -40)
				await fighter_views[e.fighter].knock_out().finished
			"status" when e.status == "guard":
				Audio.play("block")
				_popup(fighter_views[e.fighter], "%s GUARD -%d%%" % [e.kind.to_upper(), e.pct], UiTheme.CHALK, -36)
				fighter_views[e.fighter].flash(Color("8fc6ea"))
				await get_tree().create_timer(0.3).timeout
			"status":
				if STATUS_TEXT.has(e.status):
					var st: Array = STATUS_TEXT[e.status]
					Audio.play("dizzy" if e.status == "dizzy" else "turn")
					_popup(fighter_views[e.fighter], st[0], st[1], -36)
					await get_tree().create_timer(0.2).timeout
			"self_damage":
				_hp_shown[e.fighter] = e.hp
				_refresh_panels()
				_popup(fighter_views[e.fighter], "-%d" % e.amount, UiTheme.HIT, -20)
				if leaper == e.fighter:
					await fighter_views[e.fighter].leap_to(battle.fighters[e.fighter].pos, 0.25).finished
					fighter_views[e.fighter].set_tile(battle.fighters[e.fighter].pos)
			"forfeit":
				_popup(fighter_views[e.fighter], "LEFT THE GAME", UiTheme.CHALK_DIM, -40)
				if not fighter_views[e.fighter].knocked_out:
					await fighter_views[e.fighter].knock_out().finished
			"turn_start":
				if not online() or e.fighter == my_fighter:
					Audio.play("turn")
				_refresh()
				await _turn_banner(battle.fighters[e.fighter])
			"round_end":
				round_end = e
			"match_end":
				match_end = e
				_record_stats(e.winner_team)
	if not match_end.is_empty() or not round_end.is_empty():
		Audio.play("win")
	if not match_end.is_empty():
		_show_overlay(match_end, true)
	elif not round_end.is_empty():
		_show_overlay(round_end, false)


## Item use: the item flies to what it hits (book, pencils) or splashes in
## front of the user (water bottle; the "puddle" event draws the puddle).
func _use_item_anim(e: Dictionary, events: Array, i: int) -> void:
	var atk: Dictionary = Battle.ITEMS[e.attack]
	var v = fighter_views[e.fighter]
	_popup(v, atk.name.to_upper() + "!", UiTheme.GOLD, -30)
	Audio.play("whoosh")
	if atk.type == "spill":
		await v.lunge(e.dir).finished
		return
	if atk.type == "self_guard":
		return  # the "guard" status event shows it
	var from: Vector2 = v.position + Vector2(0, -16)
	var to: Vector2 = from + Vector2(e.dir) * TILE * atk["range"]
	for j in range(i + 1, events.size()):
		var n: Dictionary = events[j]
		if n.type == "damage" or n.type == "blocked":
			to = fighter_views[n.fighter].position + Vector2(0, -16)
			break
		if n.type == "obstacle_damage":
			to = _tile_center(n.at)
			break
		if n.type == "turn_end":
			break
	var count: int = atk.get("hits", 1)
	var last: Tween
	for k in count:
		var sp := Sprite2D.new()
		sp.texture = PixelArt.item_icon(e.attack)
		sp.position = from
		sp.z_index = 4000
		board.add_child(sp)
		var tw := create_tween().set_parallel()
		tw.tween_property(sp, "position", to, 0.22).set_delay(k * 0.07)
		tw.tween_property(sp, "rotation", TAU * 1.5, 0.22).set_delay(k * 0.07)
		tw.chain().tween_callback(sp.queue_free)
		last = tw
	await last.finished


func _add_box(t: Vector2i, drop := false) -> void:
	box_node = Sprite2D.new()
	box_node.texture = PixelArt.mystery_box()
	box_node.centered = false
	box_node.position = Vector2(t.x * TILE, t.y * TILE)
	box_node.z_index = t.y * 10 - 4
	board.add_child(box_node)
	if drop:
		box_node.position.y -= 40
		create_tween().tween_property(box_node, "position:y", t.y * TILE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _add_puddle(t: Vector2i, grow := false) -> void:
	var sp := Sprite2D.new()
	sp.texture = PixelArt.puddle()
	sp.centered = false
	sp.position = Vector2(t.x * TILE, t.y * TILE)
	sp.modulate = Color(1, 1, 1, 0.9)
	sp.z_index = t.y * 10 - 5
	board.add_child(sp)
	puddle_nodes[t] = sp
	if grow:
		sp.scale = Vector2(0.2, 0.2)
		sp.position += Vector2(TILE, TILE) * 0.4
		var tw := create_tween().set_parallel()
		tw.tween_property(sp, "scale", Vector2.ONE, 0.25)
		tw.tween_property(sp, "position", Vector2(t.x * TILE, t.y * TILE), 0.25)


func _slot_of(f, attack_id: String) -> int:
	for i in f.def.attacks.size():
		if f.def.attacks[i].id == attack_id:
			return i
	return 0


# ---------------------------------------------------------------- effects

func _popup(v: Node2D, text: String, color: Color, dy := -24) -> void:
	var l := UiTheme.label(text, 8, color)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color("17121c"))
	l.z_index = 4000
	l.position = v.position + Vector2(16 - text.length() * 2.5, dy)
	board.add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 14, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


func _shake(strength := 3) -> void:
	var home := board.position
	var tw := create_tween()
	for i in 4 + strength:
		tw.tween_property(board, "position", home + Vector2(strength if i % 2 == 0 else -strength, 1), 0.03)
	tw.tween_property(board, "position", home, 0.03)
	await tw.finished


# ---------------------------------------------------------------- supers

## The cut-in before every super: the screen darkens, the fighter slides in big
## and the super's name flies in from the other side.
func _super_cutin(f, atk: Dictionary) -> void:
	var vs := get_viewport_rect().size
	var color: Color = UiTheme.TEAM[battle.teams.find(f.team)]
	var layer := Control.new()
	layer.z_index = 4085
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = vs
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = vs
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var band := ColorRect.new()
	band.color = Color(color.darkened(0.55), 0.92)
	band.position = Vector2(0, floorf(vs.y / 2.0 - 46))
	band.size = Vector2(vs.x, 92)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.scale = Vector2(1, 0)
	band.pivot_offset = Vector2(0, 46)
	layer.add_child(band)
	var pic := TextureRect.new()
	pic.texture = PixelArt.character(f.char_id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	pic.size = Vector2(80, 120)
	pic.position = Vector2(-90, floorf(vs.y / 2.0 - 70))
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pic)
	var name := UiTheme.label(atk.name.to_upper() + "!!", 32, UiTheme.GOLD, true)
	name.add_theme_constant_override("outline_size", 6)
	name.add_theme_color_override("font_outline_color", Color("17121c"))
	name.position = Vector2(vs.x + 10, floorf(vs.y / 2.0 - 20))
	layer.add_child(name)
	var who := UiTheme.label(f.def.name.to_upper(), 8, UiTheme.CHALK)
	who.position = Vector2(vs.x + 10, floorf(vs.y / 2.0 + 18))
	layer.add_child(who)

	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim, "color:a", 0.45, 0.12)
	tw.tween_property(band, "scale:y", 1.0, 0.12)
	tw.tween_property(pic, "position:x", 40.0, 0.22)
	tw.tween_property(name, "position:x", 140.0, 0.22)
	tw.tween_property(who, "position:x", 142.0, 0.26)
	await tw.finished
	await get_tree().create_timer(0.5).timeout
	var out := create_tween().set_parallel()
	out.tween_property(layer, "modulate:a", 0.0, 0.15)
	out.tween_property(pic, "position:x", vs.x, 0.15)
	await out.finished
	layer.queue_free()


## Each fighter's own super animation (the damage numbers come right after).
func _super_move(e: Dictionary, f, atk: Dictionary) -> void:
	var v = fighter_views[f.id]
	var home: Vector2 = v.position
	var dir: Vector2i = e.dir if e.dir is Vector2i else Vector2i.RIGHT
	var target: Vector2i = f.pos + dir
	var tpx := _tile_center(target)
	var tv = _view_at(target)
	match atk.id:
		"mega_barrage":
			# a flurry of quick punches
			for i in 8:
				var tw := create_tween()
				tw.tween_property(v, "position", home + Vector2(dir) * 8 + Vector2(0, randf_range(-3, 3)), 0.035)
				tw.tween_property(v, "position", home, 0.035)
				_fx("spark", tpx + Vector2(randf_range(-9, 9), randf_range(-16, 4)), {"scale": 0.7})
				if i % 2 == 0:
					Audio.play("hit")
				if tv != null:
					tv.flash(Color(1.8, 1.8, 1.8))
				await tw.finished
			_fx("spark", tpx, {"scale": 1.5})
			await _shake(3)
		"body_smash":
			# big jump, then crash down onto the enemy: rocks everywhere
			var up := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			up.tween_property(v, "position", home + Vector2(dir) * 10 + Vector2(0, -34), 0.22)
			await up.finished
			var down := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			down.tween_property(v, "position", home + Vector2(dir) * 14, 0.09)
			await down.finished
			Audio.play("slam")
			for i in 14:
				_fx("rock", tpx + Vector2(randf_range(-10, 10), 8), {"vel": Vector2(randf_range(-110, 110), randf_range(-190, -90))})
			_fx("spark", tpx, {"scale": 1.6})
			_fx("dust", tpx + Vector2(0, 10))
			await _shake(6)
			create_tween().tween_property(v, "position", home, 0.12)
		"mega_sword":
			# leap up, slam the sword down, shockwave rolls out in two rings
			var up := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			up.tween_property(v, "position", home + Vector2(0, -32), 0.2)
			await up.finished
			var down := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			down.tween_property(v, "position", home + Vector2(dir) * 6, 0.08)
			await down.finished
			Audio.play("slam")
			var tiles := []
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var t := target + Vector2i(dx, dy)
					if t != f.pos and battle._in_bounds(t):
						tiles.append([t, UiTheme.HIT if maxi(absi(dx), absi(dy)) <= 1 else UiTheme.DIZZY])
			_fx("tiles", Vector2.ZERO, {"tiles": tiles})
			_fx("ring", tpx, {"radius": 40.0})
			_fx("ring", tpx, {"radius": 84.0, "delay": 0.1})
			for i in 6:
				_fx("rock", tpx + Vector2(randf_range(-6, 6), 6), {"vel": Vector2(randf_range(-80, 80), randf_range(-150, -70))})
			await _shake(5)
			create_tween().tween_property(v, "position", home, 0.12)
		"mega_woof":
			# Charlie and Lucy bark together: big WOOF, sound waves roll at the enemy
			var tw := create_tween()
			tw.tween_property(v, "position", home + Vector2(dir) * -4, 0.1)
			tw.tween_property(v, "position", home + Vector2(dir) * 6, 0.06)
			await tw.finished
			Audio.play("woof")
			_popup_at(home + Vector2(4, -34), "WOOF!", UiTheme.GOLD)
			var mouth := _tile_center(f.pos) + Vector2(dir) * 12
			for i in 3:
				_fx("ring", mouth + Vector2(dir) * (i * 10), {"radius": 18.0 + i * 8, "delay": i * 0.08})
			_fx("spark", tpx, {"scale": 1.3})
			await _shake(5)
			create_tween().tween_property(v, "position", home, 0.12)
		"triple_uppercut":
			# three uppercuts, the enemy pops higher each time
			for i in 3:
				var tw := create_tween()
				tw.tween_property(v, "position", home + Vector2(dir) * 9 + Vector2(0, -6), 0.06)
				tw.tween_property(v, "position", home, 0.08)
				Audio.play("hit")
				_fx("spark", tpx + Vector2(0, -6 - i * 6), {"scale": 0.8 + i * 0.3})
				_popup_at(tpx + Vector2(-6, -40 - i * 8), "%d!" % (i + 1), UiTheme.GOLD)
				if tv != null:
					var pop := create_tween()
					pop.tween_property(tv, "position:y", tv.position.y - 8 - i * 6, 0.08)
					pop.tween_property(tv, "position:y", tv.position.y, 0.1)
				await get_tree().create_timer(0.2).timeout
			await _shake(4)
		_:
			if e.dir is Vector2i and atk.type != "leap":
				await v.lunge(dir).finished


func _tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE + 16, t.y * TILE + 16)


## Centre of a fighter's tile from a fighter view's position.
func _px_center(p: Vector2) -> Vector2:
	return p + Vector2(16, 20)


func _view_at(t: Vector2i):
	for f in battle.fighters:
		if f.pos == t:
			return fighter_views[f.id]
	return null


func _popup_at(p: Vector2, text: String, color: Color) -> void:
	var l := UiTheme.label(text, 16, color, true)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color("17121c"))
	l.z_index = 4000
	l.position = p
	board.add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", p.y - 12, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


## Spawns a short visual effect on the board (sparks, rocks, dust, rings, tile flashes).
func _fx(kind: String, at: Vector2, opts := {}) -> void:
	var fx := Fx.new()
	fx.kind = kind
	fx.position = at
	fx.opts = opts
	fx.z_index = 3000
	board.add_child(fx)


func _super_flash() -> void:
	var r := ColorRect.new()
	r.color = Color(UiTheme.GOLD, 0.35)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 4070
	add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.3)
	tw.tween_callback(r.queue_free)
	await get_tree().create_timer(0.15).timeout


func _turn_banner(f) -> void:
	var color: Color = UiTheme.TEAM[battle.teams.find(f.team)]
	var text := "%s'S TURN" % _name_of(f)
	if (online() or vs_cpu()) and f.id == my_fighter:
		text = "YOUR TURN!"
	var l := UiTheme.label(text, 16, color, true)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color("17121c"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vs := get_viewport_rect().size
	l.size = Vector2(vs.x, 20)
	l.position = Vector2(0, floorf(vs.y / 2.0 - 30))
	l.z_index = 4080
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)
	await get_tree().create_timer(0.3).timeout


func _show_overlay(e: Dictionary, is_match: bool) -> void:
	_close_overlay()
	mode = "over"
	_overlay_event = e
	_overlay_is_match = is_match
	var winners := []
	for f in battle.fighters:
		if f.team == e.winner_team:
			winners.append(_name_of(f))
	var winner := " & ".join(winners) if not winners.is_empty() else "NOBODY"
	if online() and battle.fighters[my_fighter].team == e.winner_team:
		winner = "YOU"
	var score := []
	for t in battle.teams:
		score.append(str(e.wins[t]))
	overlay = PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(col)
	var verb := "WIN" if winner == "YOU" or winners.size() > 1 else "WINS"
	var title_text := ("%s %s THE MATCH!" if is_match else "%s %s ROUND %d") % ([winner, verb] if is_match else [winner, verb, e["round"]])
	if e.winner_team == -1:
		title_text = "ROUND %d IS A DRAW" % e["round"]
	var title := UiTheme.label(title_text, 16, UiTheme.GOLD, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sc := UiTheme.label("SCORE  " + " - ".join(score), 8, UiTheme.CHALK)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	if online():
		if is_match:
			if is_host:
				row.add_child(_overlay_button("BACK TO LOBBY", func(): net.send({"t": "to_lobby"})))
			else:
				row.add_child(UiTheme.label("WAITING FOR THE HOST", 8, UiTheme.CHALK_DIM))
			row.add_child(_overlay_button("LEAVE", func(): leave_requested.emit()))
		elif is_host:
			row.add_child(_overlay_button("SUDDEN DEATH" if battle.round_number >= battle.rounds_total else "NEXT ROUND", _next_round))
		else:
			row.add_child(UiTheme.label("WAITING FOR THE HOST TO START THE NEXT ROUND", 8, UiTheme.CHALK_DIM))
	elif is_match:
		var again := Button.new()
		again.text = "REMATCH"
		again.custom_minimum_size = Vector2(80, 24)
		again.pressed.connect(func(): rematch_requested.emit())
		row.add_child(again)
		var menu := Button.new()
		menu.text = "MENU"
		menu.custom_minimum_size = Vector2(80, 24)
		menu.pressed.connect(func(): menu_requested.emit())
		row.add_child(menu)
	else:
		var next := Button.new()
		next.text = "SUDDEN DEATH" if battle.round_number >= battle.rounds_total else "NEXT ROUND"
		next.custom_minimum_size = Vector2(100, 24)
		next.pressed.connect(_next_round)
		row.add_child(next)
	overlay.z_index = 4090  # above everything on the board
	add_child(overlay)
	overlay.custom_minimum_size = Vector2(300, 80)
	var vs := get_viewport_rect().size
	overlay.position = Vector2(floorf((vs.x - 300) / 2.0), floorf((vs.y - 80) / 2.0))
	_refresh()


func _overlay_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(100, 24)
	b.pressed.connect(callback)
	return b


func _close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


func _next_round() -> void:
	if online():
		net.send({"t": "next_round"})
		return
	_close_overlay()
	_start_round()


# ---------------------------------------------------------------- online

func _on_net_message(msg: Dictionary) -> void:
	match msg.get("t"):
		"emote":
			_show_emote(int(msg.get("fighter", -1)), int(msg.get("id", -1)))
		"op":
			_ops.append(msg)
			if not _playing_ops:
				_drain_ops()
		"error":
			if _waiting:
				_waiting = false
				_error(msg.get("code", "error"))
				_refresh()
		"match_sync":
			_ops.clear()
			battle = Battle.new(msg.config)
			for op in msg.ops:
				_apply_op(op)
			my_fighter = msg.you
			_turn_end_at = Time.get_ticks_msec() + msg.turn_ms if msg.turn_ms >= 0 else 0
			_waiting = false
			busy = false
			mode = "move"
			_rebuild_from_state()


## Plays queued ops one after another (each one's animation finishes first).
func _drain_ops() -> void:
	_playing_ops = true
	while not _ops.is_empty() and is_inside_tree():
		var op: Dictionary = _ops.pop_front()
		if op.op == "start_round":
			_close_overlay()
			mode = "move"
		var events := _apply_op(op)
		if op.op == "start_round":
			_hp_shown.clear()
			_build_board()
		if battle.state_hash() != op.hash:
			# Our copy drifted from the server's: ask for the full match again.
			_ops.clear()
			net.send({"t": "sync"})
			break
		if op.op == "intent" and op.fighter == my_fighter:
			_waiting = false
			if op.intent.get("type") == "attack":
				mode = "move"
		if op.get("timeout", false) and op.fighter == my_fighter:
			mode = "move"
			_error_text("TIME'S UP!")
		_turn_end_at = Time.get_ticks_msec() + op.turn_ms if op.turn_ms >= 0 else 0
		busy = true
		_refresh()
		await _play(events)
		busy = false
		_refresh()
	_playing_ops = false


func _apply_op(op: Dictionary) -> Array:
	match op.op:
		"start_round":
			return battle.start_round()
		"intent":
			return battle.apply(op.fighter, op.intent).events
		"forfeit":
			return battle.forfeit(op.fighter)
	return []


## Redraws everything from the battle state, e.g. after rejoining.
func _rebuild_from_state() -> void:
	_hp_shown.clear()
	_close_overlay()
	_build_board()
	_refresh()
	if battle.phase == Battle.Phase.MATCH_OVER:
		_show_overlay({"winner_team": battle.match_winner, "wins": battle.round_wins, "round": battle.round_number}, true)
	elif battle.phase == Battle.Phase.ROUND_OVER:
		var winner := -1
		for f in battle.fighters:
			if f.alive():
				winner = f.team
		_show_overlay({"winner_team": winner, "wins": battle.round_wins, "round": battle.round_number}, false)


func _process(_delta: float) -> void:
	if not online() and not busy and not _cpu_running and mode != "over" and overlay == null \
			and _confirm_box == null and battle.phase == Battle.Phase.TURN and not battle.order.is_empty() \
			and _is_cpu(battle.current().id):
		_cpu_turn()
	if online() and round_label != null and battle.round_number > 0:
		_update_round_label()
	if not _auto_path.is_empty() and not busy and not _waiting:
		if mode != "move" or not _my_turn():
			_auto_path.clear()
		else:
			var next: Vector2i = _auto_path.pop_front()
			_send({"type": "move", "dir": next - battle.current().pos})


func _update_round_label() -> void:
	var rtxt := "ROUND %d OF %d" % [battle.round_number, battle.rounds_total]
	if battle.is_sudden_death():
		rtxt = "SUDDEN DEATH"
	if online():
		if net.status != "online":
			round_label.text = "RECONNECTING..."
			round_label.add_theme_color_override("font_color", UiTheme.HIT)
			return
		if _turn_end_at > 0 and battle.phase == Battle.Phase.TURN:
			var secs := ceili(maxf(0.0, _turn_end_at - Time.get_ticks_msec()) / 1000.0)
			rtxt += "  %ds" % secs
			round_label.add_theme_color_override("font_color", UiTheme.HIT if secs <= 5 else UiTheme.CHALK_DIM)
			round_label.text = rtxt
			return
	round_label.add_theme_color_override("font_color", UiTheme.CHALK_DIM)
	round_label.text = rtxt


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	_refresh_panels()
	if battle.order.is_empty():
		hint_label.text = "STARTING..."
		for b in attack_buttons:
			b.disabled = true
		return
	var f := battle.current()
	for v in fighter_views:
		v.active = false
	if battle.phase == Battle.Phase.TURN and not busy:
		fighter_views[f.id].active = true

	_update_round_label()
	sound_button.text = "SOUND ON" if Audio.is_enabled() else "SOUND OFF"
	sound_button.size = sound_button.get_combined_minimum_size()

	var in_turn := _my_turn() and mode != "over" and not _waiting
	# Online, the buttons always show your own fighter's moves.
	var bf = battle.fighters[my_fighter] if my_fighter >= 0 else f
	for slot in 5:
		var b := attack_buttons[slot]
		var atk: Dictionary = bf.def["super"] if slot == Battle.SUPER_SLOT else bf.def.attacks[slot]
		var key := "Q" if slot == Battle.SUPER_SLOT else str(slot + 1)
		attack_names[slot].text = "%s %s" % [key, atk.name.to_upper()]
		attack_infos[slot].text = FighterInfo.attack_info(atk)
		if slot == Battle.SUPER_SLOT:
			super_bar.value = float(bf.meter) / Battle.METER_MAX
			super_bar.queue_redraw()
			if bf.meter < Battle.METER_MAX:
				attack_names[slot].text = "Q SUPER %d%%" % bf.meter
		b.disabled = busy or not in_turn or battle.attack_blocked_reason(bf.id, slot) != ""
		attack_names[slot].modulate = Color(1, 1, 1, 0.45) if b.disabled else Color.WHITE
		attack_infos[slot].modulate = attack_names[slot].modulate
		b.button_pressed = false
		b.modulate = UiTheme.GOLD if (slot == Battle.SUPER_SLOT and bf.meter >= Battle.METER_MAX) else Color.WHITE
		if mode == "aim" and slot == aim_slot:
			b.modulate = Color(1.4, 1.4, 1.2)
	item_button.visible = bf.item != ""
	if bf.item != "":
		var it: Dictionary = Battle.ITEMS[bf.item]
		item_icon.texture = PixelArt.item_icon(bf.item)
		item_name.text = "5 " + it.name.to_upper()
		match it.type:
			"spill":
				item_info.text = "PUDDLE: SLIP + DIZZY"
			"self_guard":
				item_info.text = "-20-45% DMG"
			_:
				item_info.text = FighterInfo.attack_info(it)
		item_button.disabled = busy or not in_turn or battle.attack_blocked_reason(bf.id, Battle.ITEM_SLOT) != ""
		item_button.modulate = Color(1.4, 1.4, 1.2) if mode == "aim" and aim_slot == Battle.ITEM_SLOT else Color.WHITE
	undo_button.disabled = busy or not in_turn or (mode == "move" and battle.path.is_empty())
	undo_button.text = "BACK" if mode == "aim" else "UNDO"
	ok_button.disabled = busy or mode != "aim"
	end_button.disabled = busy or not in_turn

	# highlights
	var tiles := []
	if in_turn and not busy:
		if mode == "move":
			for t in battle.reachable_tiles():
				tiles.append({"pos": t, "kind": "reach"})
		elif mode == "aim":
			tiles = battle.preview(f.id, aim_slot, aim_dir, aim_dist)
	if battle.phase == Battle.Phase.TURN and not busy:
		tiles.append({"pos": f.pos, "kind": "current"})
	highlight.tiles = tiles
	highlight.queue_redraw()

	if Time.get_ticks_msec() < _hint_error_until:
		return
	hint_label.add_theme_color_override("font_color", UiTheme.CHALK_DIM)
	if not _auto_path.is_empty():
		hint_label.text = "WALKING..."
	elif _waiting:
		hint_label.text = "..."
	elif battle.phase != Battle.Phase.TURN or mode == "over":
		hint_label.text = ""
	elif online() and not _my_turn():
		hint_label.text = "WAITING FOR %s..." % _name_of(f)
	elif _is_cpu(f.id):
		hint_label.text = "%s IS THINKING..." % _name_of(f)
	elif mode == "move":
		var left := battle.move_budget - battle.path.size()
		var extra := "  (DIZZY)" if f.dizzy_now else ""
		if f.no_attack_now:
			extra += "  SUGAR CRASH: NO ATTACK"
		hint_label.text = "MOVES LEFT %d%s - TAP A BLUE TILE OR USE THE JOYSTICK" % [left, extra]
	else:
		var atk := _atk(aim_slot)
		var txt := "%s: AIM WITH THE JOYSTICK OR TAP A TILE (TAP AGAIN = USE)" % atk.name.to_upper()
		if atk.type == "lob":
			txt = "%s: TAP WHERE TO THROW (DISTANCE %d), THEN USE" % [atk.name.to_upper(), aim_dist]
		elif atk.type.begins_with("self"):
			txt = "%s: PRESS AGAIN OR USE" % atk.name.to_upper()
		elif atk.type == "spill":
			txt = "WATER BOTTLE: PICK WHERE TO SPILL (NEXT TO YOU), THEN USE"
		hint_label.text = txt


func _refresh_panels() -> void:
	for f in battle.fighters:
		var p: Dictionary = panels[f.id]
		# While a move is animating, bars show HP as of the last hit shown so far
		# (the rules engine already has the final numbers).
		if not busy:
			_hp_shown[f.id] = f.hp
		var hp_now: int = _hp_shown.get(f.id, f.hp)
		p.hp.value = float(hp_now) / f.max_hp
		p.hp.queue_redraw()
		p.hp_text.text = "%d" % hp_now
		p.meter.value = float(f.meter) / Battle.METER_MAX
		p.meter.color = UiTheme.GOLD if f.meter >= Battle.METER_MAX else UiTheme.GOLD.darkened(0.35)
		p.meter.queue_redraw()
		var st := []
		if not f.alive():
			st.append("KO")
		if f.rage_turns > 0:
			st.append("RAGE")
		if f.shield.get("kind") == "hp":
			st.append("SHIELD %d" % f.shield.amount)
		if f.shield.get("kind") == "block":
			st.append("BLOCK")
		if f.sugar_active:
			st.append("SUGAR")
		if f.no_attack_next or f.no_attack_now:
			st.append("CRASH")
		if not f.guard.is_empty():
			st.append("%s GUARD" % ("MELEE" if f.guard.kind == "melee" else "RANGED"))
		if f.item != "":
			st.append(Battle.ITEMS[f.item].name.to_upper())
		if f.dizzy_next or f.dizzy_now:
			st.append("DIZZY")
		p.status.text = " ".join(st)


func _error(code: String) -> void:
	_error_text(ERRORS.get(code, code.to_upper()))


func _error_text(text: String) -> void:
	_auto_path.clear()
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", UiTheme.HIT)
	_hint_error_until = Time.get_ticks_msec() + 1500
	get_tree().create_timer(1.55).timeout.connect(func():
		if is_inside_tree():
			_refresh())


# ---------------------------------------------------------------- drawing helpers

class FloorLayer extends Node2D:
	var size := Vector2i.ZERO
	var style := "lino"
	var sand := {}  # sandbox tiles, with a wooden edge around the box

	func _draw() -> void:
		for y in size.y:
			for x in size.x:
				var t := Vector2i(x, y)
				draw_texture(PixelArt.floor_tile((x + y) % 2 == 1, "sand" if sand.has(t) else style), Vector2(x * 32, y * 32))
		var wood := Color("9a6a3c")
		for t in sand:
			var p := Vector2(t.x * 32, t.y * 32)
			if not sand.has(t + Vector2i.UP):
				draw_rect(Rect2(p, Vector2(32, 3)), wood)
			if not sand.has(t + Vector2i.DOWN):
				draw_rect(Rect2(p + Vector2(0, 29), Vector2(32, 3)), wood)
			if not sand.has(t + Vector2i.LEFT):
				draw_rect(Rect2(p, Vector2(3, 32)), wood)
			if not sand.has(t + Vector2i.RIGHT):
				draw_rect(Rect2(p + Vector2(29, 0), Vector2(3, 32)), wood)


class HighlightLayer extends Node2D:
	const COLORS := {
		"reach": Color("5b9bf0"),
		"path": Color("f2c14e"),
		"hit": Color("e8575e"),
		"dizzy": Color("b08cf0"),
		"self": Color("f2c14e"),
	}
	var tiles := []

	func _draw() -> void:
		for t in tiles:
			var r := Rect2(t.pos.x * 32 + 1, t.pos.y * 32 + 1, 30, 30)
			if t.kind == "current":
				draw_rect(r, Color("f2c14e"), false, 1.0)
				continue
			var c: Color = COLORS[t.kind]
			if t.kind == "reach":
				draw_rect(r, Color(c, 0.38))
				draw_rect(r, Color(c, 0.95), false, 1.0)
			elif t.kind == "path":
				draw_rect(r, Color(c, 0.18))
				draw_rect(r.grow(-10), Color(c, 0.7))
			elif t.kind in ["hit", "dizzy", "self"]:
				draw_rect(r, Color(c, 0.35))
				draw_rect(r, Color(c, 0.9), false, 1.0)
			else:
				draw_rect(r, c)


## One short-lived effect. Draws itself and frees itself when done.
class Fx extends Node2D:
	var kind := "spark"
	var opts := {}
	var t := 0.0
	var _vel := Vector2.ZERO
	var _rot := 0.0

	func _ready() -> void:
		_vel = opts.get("vel", Vector2.ZERO)
		_rot = randf() * TAU

	func _life() -> float:
		match kind:
			"rock":
				return 0.7
			"ring":
				return 0.45 + opts.get("delay", 0.0)
			"tiles":
				return 0.55
			"dust":
				return 0.4
		return 0.25

	func _process(delta: float) -> void:
		t += delta
		if kind == "rock":
			_vel.y += 420.0 * delta
			position += _vel * delta
			_rot += delta * 9.0
		if t >= _life():
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := clampf(t / _life(), 0.0, 1.0)
		match kind:
			"spark":
				var sc: float = opts.get("scale", 1.0)
				for i in 8:
					var a := _rot + i * TAU / 8.0
					var d := Vector2(cos(a), sin(a))
					var r0 := 3.0 * sc + k * 6.0 * sc
					var r1 := r0 + (8.0 - k * 6.0) * sc
					draw_line(d * r0, d * r1, Color(1, 0.95, 0.6, 1.0 - k), 2.0)
				draw_circle(Vector2.ZERO, 4.0 * sc * (1.0 - k), Color(1, 1, 1, 1.0 - k))
			"rock":
				draw_set_transform(Vector2.ZERO, _rot)
				draw_rect(Rect2(-3, -3, 6, 6), Color("8a6a46"))
				draw_rect(Rect2(-3, -3, 6, 6), Color("17121c"), false, 1.0)
				draw_set_transform(Vector2.ZERO)
			"dust":
				for i in 5:
					var off := Vector2(-12 + i * 6, 0) + Vector2(0, -k * 6)
					draw_circle(off, 3.0 + k * 5.0, Color(0.85, 0.82, 0.75, 0.7 * (1.0 - k)))
			"ring":
				var delay: float = opts.get("delay", 0.0)
				if t < delay:
					return
				var kk := clampf((t - delay) / 0.45, 0.0, 1.0)
				var r: float = lerpf(6.0, opts.get("radius", 60.0), kk)
				draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(1, 0.85, 0.4, 1.0 - kk), 3.0)
			"tiles":
				for item in opts.get("tiles", []):
					var tile: Vector2i = item[0]
					var c: Color = item[1]
					draw_rect(Rect2(tile.x * 32 + 1, tile.y * 32 + 1, 30, 30), Color(c, 0.6 * (1.0 - k)))


class Bar extends Control:
	var value := 1.0
	var color := Color.RED

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("152a22"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(floorf(size.x * clampf(value, 0, 1)), size.y)), color)
		draw_rect(Rect2(Vector2.ZERO, size), Color("3e6555"), false, 1.0)
