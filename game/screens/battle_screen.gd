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
	"not_your_turn": "NOT YOUR TURN",
	"not_in_turn": "WAIT FOR THE NEXT TURN",
	"offline": "NOT CONNECTED - RECONNECTING...",
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


## Local battle.
func setup(p_config: Dictionary) -> void:
	config = p_config
	battle = Battle.new(config)


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


func set_host(v: bool) -> void:
	if v == is_host:
		return
	is_host = v
	if overlay != null:
		_show_overlay(_overlay_event, _overlay_is_match)


func _name_of(f) -> String:
	if online():
		return "%s (%s)" % [str(config.players[f.id].get("name", "?")).to_upper(), f.def.name.to_upper()]
	return "P%d %s" % [f.id + 1, f.def.name.to_upper()]


func _my_turn() -> bool:
	return battle.phase == Battle.Phase.TURN and (not online() or battle.current().id == my_fighter)


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
	if not online():
		_start_round()
	elif battle.round_number > 0:
		_rebuild_from_state()
	else:
		_layout()
		_refresh()


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
	# first half of the fighters on the left, the rest on the right
	var n := panels.size()
	var left := ceili(n / 2.0)
	var w := 150.0 if n == 2 else 122.0
	for i in n:
		var box: Control = panels[i].box
		var x := 6.0 + i * (w + 6) if i < left else vs.x - 6 - w - (n - 1 - i) * (w + 6)
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
	if busy or _waiting or not _my_turn():
		return
	if mode == "aim":
		_cancel_aim()
	elif mode == "move":
		_send({"type": "undo"})


func _on_end_turn() -> void:
	if busy or mode == "over" or _waiting or not _my_turn():
		return
	mode = "move"
	_send({"type": "end_turn"})


func _atk(slot: int) -> Dictionary:
	if battle.order.is_empty():
		return battle.fighters[maxi(0, my_fighter)].def.attacks[0]
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
	if online():
		if not net.send({"t": "intent", "intent": intent}):
			_error("offline")
			return
		_waiting = true
		_refresh()
		return
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
			"forfeit":
				_popup(fighter_views[e.fighter], "LEFT THE GAME", UiTheme.CHALK_DIM, -40)
				if not fighter_views[e.fighter].knocked_out:
					await fighter_views[e.fighter].knock_out().finished
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
	var text := "%s'S TURN" % _name_of(f)
	if online() and f.id == my_fighter:
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
	if online() and round_label != null and battle.round_number > 0:
		_update_round_label()


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

	var in_turn := _my_turn() and mode != "over" and not _waiting
	# Online, the buttons always show your own fighter's moves.
	var bf = battle.fighters[my_fighter] if online() else f
	for slot in 5:
		var b := attack_buttons[slot]
		var atk: Dictionary = bf.def["super"] if slot == Battle.SUPER_SLOT else bf.def.attacks[slot]
		var key := "Q" if slot == Battle.SUPER_SLOT else str(slot + 1)
		b.text = "%s %s" % [key, atk.name.to_upper()]
		if slot == Battle.SUPER_SLOT and bf.meter < Battle.METER_MAX:
			b.text = "Q SUPER %d%%" % bf.meter
		b.disabled = busy or not in_turn or battle.attack_blocked_reason(bf.id, slot) != ""
		b.button_pressed = false
		b.modulate = UiTheme.GOLD if (slot == Battle.SUPER_SLOT and bf.meter >= Battle.METER_MAX) else Color.WHITE
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
	if battle.phase == Battle.Phase.TURN and not busy:
		tiles.append({"pos": f.pos, "kind": "current"})
	highlight.tiles = tiles
	highlight.queue_redraw()

	if Time.get_ticks_msec() < _hint_error_until:
		return
	hint_label.add_theme_color_override("font_color", UiTheme.CHALK_DIM)
	if _waiting:
		hint_label.text = "..."
	elif battle.phase != Battle.Phase.TURN or mode == "over":
		hint_label.text = ""
	elif online() and not _my_turn():
		hint_label.text = "WAITING FOR %s..." % _name_of(f)
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
		if f.dizzy_next or (battle.phase == Battle.Phase.TURN and battle.current() == f and battle.move_budget < f.move):
			st.append("DIZZY")
		p.status.text = " ".join(st)


func _error(code: String) -> void:
	_error_text(ERRORS.get(code, code.to_upper()))


func _error_text(text: String) -> void:
	hint_label.text = text
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
