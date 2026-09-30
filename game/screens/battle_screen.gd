extends Control
## Local battle: draws the board, reads joystick / keyboard / buttons, sends
## intents to the rules engine and animates the events that come back.
## All game logic lives in rules/battle.gd; this file only shows it.

signal menu_requested
signal rematch_requested

const Battle = preload("res://rules/battle.gd")
const Maps = preload("res://rules/maps.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Joystick = preload("res://ui/joystick.gd")
const FighterView = preload("res://screens/fighter_view.gd")

const TILE := 32
const TOP_H := 30
const BOTTOM_H := 56

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
}
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
var undo_button: Button
var ok_button: Button
var end_button: Button
var joystick: Control
var bottom_bar: VBoxContainer
var overlay: PanelContainer
var _hint_error_until := 0


func setup(p_config: Dictionary) -> void:
	config = p_config
	battle = Battle.new(config)


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	floor_layer.z_index = -1000
	highlight.z_index = -900
	board.add_child(floor_layer)
	board.add_child(highlight)
	_build_hud()
	get_viewport().size_changed.connect(_layout)
	_start_round()


# ---------------------------------------------------------------- building

func _build_board() -> void:
	for n in obstacle_nodes.values():
		n.queue_free()
	obstacle_nodes.clear()
	floor_layer.size = Vector2i(battle.width, battle.height)
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
	_layout()


func _build_hud() -> void:
	var n := battle.fighters.size()
	for f in battle.fighters:
		var color: Color = UiTheme.TEAM[battle.teams.find(f.team)]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.add_child(UiTheme.label("P%d %s" % [f.id + 1, f.def.name.to_upper()], 8, color))
		var status := UiTheme.label("", 8, UiTheme.GOLD)
		head.add_child(status)
		box.add_child(head)
		var hp_row := HBoxContainer.new()
		hp_row.add_theme_constant_override("separation", 3)
		var hp := Bar.new()
		hp.color = UiTheme.HIT
		hp.custom_minimum_size = Vector2(110, 6)
		hp_row.add_child(hp)
		var hp_text := UiTheme.label("", 8, UiTheme.CHALK)
		hp_row.add_child(hp_text)
		box.add_child(hp_row)
		var meter := Bar.new()
		meter.color = UiTheme.GOLD
		meter.custom_minimum_size = Vector2(110, 3)
		box.add_child(meter)
		add_child(box)
		panels.append({"box": box, "hp": hp, "hp_text": hp_text, "meter": meter, "status": status})

	round_label = UiTheme.label("", 8, UiTheme.CHALK_DIM)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(round_label)

	joystick = Joystick.new()
	joystick.flicked.connect(_on_dir)
	add_child(joystick)

	bottom_bar = VBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 4)
	add_child(bottom_bar)
	var attacks_row := HBoxContainer.new()
	attacks_row.add_theme_constant_override("separation", 4)
	bottom_bar.add_child(attacks_row)
	for slot in 5:
		var b := Button.new()
		b.clip_text = true
		b.custom_minimum_size = Vector2(92, 22)
		b.pressed.connect(_on_attack_pressed.bind(slot))
		b.focus_mode = Control.FOCUS_NONE
		attacks_row.add_child(b)
		attack_buttons.append(b)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	bottom_bar.add_child(action_row)
	hint_label = UiTheme.label("", 8, UiTheme.CHALK_DIM)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.clip_text = true
	action_row.add_child(hint_label)
	undo_button = _small_button(action_row, "UNDO", _on_undo)
	ok_button = _small_button(action_row, "USE", _confirm)
	end_button = _small_button(action_row, "END TURN", _on_end_turn)


func _small_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(64 if text == "END TURN" else 44, 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _layout() -> void:
	var vs := get_viewport_rect().size
	var bw := battle.width * TILE
	var bh := battle.height * TILE
	var avail := vs.y - TOP_H - BOTTOM_H - 16
	board.position = Vector2(floorf((vs.x - bw) / 2.0), TOP_H + 16 + floorf(maxf(0.0, avail - bh) / 2.0))

	# top bar: fighters spread across, round info in the middle
	var n := panels.size()
	for i in n:
		var box: Control = panels[i].box
		var x := 6.0 + i * (vs.x - 12) / n
		if n == 2 and i == 1:
			x = vs.x - 156
		box.position = Vector2(floorf(x), 3)
	round_label.position = Vector2(floorf(vs.x / 2.0 - 60), 4)
	round_label.size = Vector2(120, 10)

	# bottom bar: joystick on the left, attack buttons + actions to its right
	joystick.position = Vector2(4, vs.y - joystick.custom_minimum_size.y - 2)
	var bar_w := minf(vs.x - 76, 5 * 92 + 4 * 4)
	bottom_bar.position = Vector2(72, vs.y - BOTTOM_H + 4)
	bottom_bar.size = Vector2(bar_w, BOTTOM_H - 8)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
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
	if event.is_action_pressed("attack_super"):
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


func _on_dir(dir: Vector2i) -> void:
	if busy or mode == "over":
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
	if busy or mode == "over":
		return
	if mode == "aim" and aim_slot == slot:
		_confirm()
		return
	var reason := battle.attack_blocked_reason(battle.current().id, slot)
	if reason != "":
		_error(reason)
		return
	mode = "aim"
	aim_slot = slot
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
	if busy:
		return
	if mode == "aim":
		_cancel_aim()
	elif mode == "move":
		_send({"type": "undo"})


func _on_end_turn() -> void:
	if busy or mode == "over":
		return
	mode = "move"
	_send({"type": "end_turn"})


func _atk(slot: int) -> Dictionary:
	var f := battle.current()
	return f.def["super"] if slot == Battle.SUPER_SLOT else f.def.attacks[slot]


# ---------------------------------------------------------------- engine

func _start_round() -> void:
	mode = "move"
	var events := battle.start_round()
	_build_board()
	_refresh()
	busy = true
	await _play(events)
	busy = false
	_refresh()


func _send(intent: Dictionary) -> void:
	var r := battle.apply(battle.current().id, intent)
	if not r.ok:
		_error(r.error)
		return
	if intent.type == "attack":
		mode = "move"
	busy = true
	_refresh()
	await _play(r.events)
	busy = false
	_refresh()


func _play(events: Array) -> void:
	var round_end := {}
	var match_end := {}
	var leaper := -1
	for e in events:
		match e.type:
			"move":
				await fighter_views[e.fighter].move_to(e.to, 0.06 if e.get("dash", false) else 0.09).finished
			"knockback":
				await fighter_views[e.fighter].move_to(e.to, 0.07).finished
			"attack":
				var f = battle.fighters[e.fighter]
				var atk: Dictionary = f.def["super"] if e["super"] else f.def.attacks[_slot_of(f, e.attack)]
				_popup(fighter_views[e.fighter], atk.name.to_upper() + ("!!" if e["super"] else "!"), UiTheme.GOLD if e["super"] else UiTheme.CHALK, -30)
				if e["super"]:
					await _super_flash()
				if e.dir is Vector2i and atk.type != "leap" and atk.type != "dash":
					await fighter_views[e.fighter].lunge(e.dir).finished
			"leap":
				leaper = e.fighter
				await fighter_views[e.fighter].leap_to(e.to, 0.28).finished
			"damage":
				var v = fighter_views[e.fighter]
				v.flash(UiTheme.HIT)
				var text := "-%d" % (e.amount - e.absorbed)
				if e.absorbed > 0:
					text += " (SHIELD %d)" % e.absorbed
				_popup(v, text, UiTheme.HIT)
				_refresh_panels()
				await get_tree().create_timer(0.18).timeout
			"blocked":
				_popup(fighter_views[e.fighter], "BLOCKED!", UiTheme.CHALK)
				await get_tree().create_timer(0.25).timeout
			"slam":
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
					var tw := create_tween().set_parallel()
					tw.tween_property(s, "modulate:a", 0.0, 0.25)
					tw.tween_property(s, "position:y", s.position.y + 6, 0.25)
					tw.chain().tween_callback(s.queue_free)
			"ko":
				_popup(fighter_views[e.fighter], "KO!", UiTheme.HIT, -40)
				await fighter_views[e.fighter].knock_out().finished
			"status":
				if STATUS_TEXT.has(e.status):
					var st: Array = STATUS_TEXT[e.status]
					_popup(fighter_views[e.fighter], st[0], st[1], -36)
					await get_tree().create_timer(0.2).timeout
			"self_damage":
				_popup(fighter_views[e.fighter], "-%d" % e.amount, UiTheme.HIT, -20)
				if leaper == e.fighter:
					await fighter_views[e.fighter].leap_to(battle.fighters[e.fighter].pos, 0.25).finished
					fighter_views[e.fighter].set_tile(battle.fighters[e.fighter].pos)
			"turn_start":
				_refresh()
				await _turn_banner(battle.fighters[e.fighter])
			"round_end":
				round_end = e
			"match_end":
				match_end = e
	if not match_end.is_empty():
		_show_overlay(match_end, true)
	elif not round_end.is_empty():
		_show_overlay(round_end, false)


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


func _shake() -> void:
	var home := board.position
	var tw := create_tween()
	for i in 4:
		tw.tween_property(board, "position", home + Vector2(3 if i % 2 == 0 else -3, 1), 0.03)
	tw.tween_property(board, "position", home, 0.03)
	await tw.finished


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
	var l := UiTheme.label("P%d  %s'S TURN" % [f.id + 1, f.def.name.to_upper()], 16, color, true)
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
	mode = "over"
	var winner := "NOBODY"
	for f in battle.fighters:
		if f.team == e.winner_team:
			winner = "P%d %s" % [f.id + 1, f.def.name.to_upper()]
	var score := []
	for t in battle.teams:
		score.append(str(e.wins[t]))
	overlay = PanelContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(col)
	var title_text := ("%s WINS THE MATCH!" if is_match else "%s WINS ROUND %d") % ([winner] if is_match else [winner, e["round"]])
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
	if is_match:
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
	overlay.custom_minimum_size = Vector2(260, 80)
	var vs := get_viewport_rect().size
	overlay.position = Vector2(floorf((vs.x - 260) / 2.0), floorf((vs.y - 80) / 2.0))
	_refresh()


func _next_round() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	_start_round()


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	_refresh_panels()
	var f := battle.current()
	for v in fighter_views:
		v.active = false
	if battle.phase == Battle.Phase.TURN and not busy:
		fighter_views[f.id].active = true

	var rtxt := "ROUND %d OF %d" % [battle.round_number, battle.rounds_total]
	if battle.is_sudden_death():
		rtxt = "SUDDEN DEATH"
	round_label.text = rtxt

	var in_turn := battle.phase == Battle.Phase.TURN and mode != "over"
	for slot in 5:
		var b := attack_buttons[slot]
		var atk := _atk(slot)
		var key := "Q" if slot == Battle.SUPER_SLOT else str(slot + 1)
		b.text = "%s %s" % [key, atk.name.to_upper()]
		if slot == Battle.SUPER_SLOT and f.meter < Battle.METER_MAX:
			b.text = "Q SUPER %d%%" % f.meter
		b.disabled = busy or not in_turn or battle.attack_blocked_reason(f.id, slot) != ""
		b.button_pressed = false
		b.modulate = UiTheme.GOLD if (slot == Battle.SUPER_SLOT and f.meter >= Battle.METER_MAX) else Color.WHITE
		if mode == "aim" and slot == aim_slot:
			b.modulate = Color(1.4, 1.4, 1.2)
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
		tiles.append({"pos": f.pos, "kind": "current"})
	highlight.tiles = tiles
	highlight.queue_redraw()

	if Time.get_ticks_msec() < _hint_error_until:
		return
	hint_label.add_theme_color_override("font_color", UiTheme.CHALK_DIM)
	if not in_turn:
		hint_label.text = ""
	elif mode == "move":
		var left := battle.move_budget - battle.path.size()
		var extra := "  (DIZZY)" if battle.move_budget < f.move else ""
		if f.no_attack_now:
			extra += "  SUGAR CRASH: NO ATTACK"
		hint_label.text = "MOVES LEFT %d%s - MOVE, PICK AN ATTACK OR END TURN" % [left, extra]
	else:
		var atk := _atk(aim_slot)
		var txt := "%s: AIM WITH JOYSTICK / WASD, PRESS AGAIN OR USE" % atk.name.to_upper()
		if atk.type == "lob":
			txt = "%s: PUSH THE SAME WAY AGAIN FOR DISTANCE (%d)" % [atk.name.to_upper(), aim_dist]
		elif atk.type.begins_with("self"):
			txt = "%s: PRESS AGAIN OR USE" % atk.name.to_upper()
		hint_label.text = txt


func _refresh_panels() -> void:
	for f in battle.fighters:
		var p: Dictionary = panels[f.id]
		p.hp.value = float(f.hp) / f.max_hp
		p.hp.queue_redraw()
		p.hp_text.text = "%d" % f.hp
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
		if f.dizzy_next or (battle.current() == f and battle.move_budget < f.move and battle.phase == Battle.Phase.TURN):
			st.append("DIZZY")
		p.status.text = " ".join(st)


func _error(code: String) -> void:
	hint_label.text = ERRORS.get(code, code.to_upper())
	hint_label.add_theme_color_override("font_color", UiTheme.HIT)
	_hint_error_until = Time.get_ticks_msec() + 1500
	get_tree().create_timer(1.55).timeout.connect(func():
		if is_inside_tree():
			_refresh())


# ---------------------------------------------------------------- drawing helpers

class FloorLayer extends Node2D:
	var size := Vector2i.ZERO

	func _draw() -> void:
		for y in size.y:
			for x in size.x:
				draw_texture(PixelArt.floor_tile((x + y) % 2 == 1), Vector2(x * 32, y * 32))


class HighlightLayer extends Node2D:
	const COLORS := {
		"reach": Color(1, 1, 1, 0.16),
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
			if t.kind == "path":
				draw_rect(r, Color(c, 0.18))
				draw_rect(r.grow(-10), Color(c, 0.7))
			elif t.kind in ["hit", "dizzy", "self"]:
				draw_rect(r, Color(c, 0.35))
				draw_rect(r, Color(c, 0.9), false, 1.0)
			else:
				draw_rect(r, c)


class Bar extends Control:
	var value := 1.0
	var color := Color.RED

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("152a22"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(floorf(size.x * clampf(value, 0, 1)), size.y)), color)
		draw_rect(Rect2(Vector2.ZERO, size), Color("3e6555"), false, 1.0)
