extends Control
## Online: pick a nickname, create a lobby or join one with a code, then the
## lobby itself (players, fighter picks, host settings, ready / start).

signal back_requested

const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Config = preload("res://net/config.gd")
const FighterInfo = preload("res://ui/fighter_info.gd")

const TIMERS := [15, 30, 45, 60, 0]
const ERRORS := {
	"not_found": "NO LOBBY WITH THAT CODE",
	"full": "THAT LOBBY IS FULL (4 PLAYERS)",
	"in_match": "THAT LOBBY IS ALREADY PLAYING",
	"taken": "SOMEONE ALREADY PICKED THAT FIGHTER",
	"bad_char": "UNKNOWN FIGHTER",
	"pick_first": "PICK A FIGHTER FIRST",
	"need_players": "YOU NEED AT LEAST 2 PLAYERS",
	"not_everyone_picked": "EVERYONE MUST PICK A FIGHTER",
	"not_everyone_ready": "WAITING FOR EVERYONE TO PRESS READY",
	"teams_uneven": "2V2 NEEDS 2 PLAYERS ON EACH TEAM",
	"someone_offline": "SOMEONE IS OFFLINE",
	"server_full": "THE SERVER IS FULL, TRY AGAIN LATER",
}

var net: Node
var lobby := {}
var _welcomed := false
var _pending := {}

var _entry: VBoxContainer
var _lobby_view: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _server_edit: LineEdit
var _status: Label


func setup(p_net: Node, state := {}) -> void:
	net = p_net
	lobby = state


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
	margin.add_child(col)

	_entry = _build_entry()
	col.add_child(_entry)
	_lobby_view = VBoxContainer.new()
	_lobby_view.add_theme_constant_override("separation", 8)
	_lobby_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_lobby_view)
	_status = UiTheme.label("", 8, UiTheme.CHALK_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_status)

	net.message.connect(_on_message)
	net.status_changed.connect(_on_status)
	_welcomed = net.status == "online" and net.token != ""
	if not lobby.is_empty():
		_show_lobby()
	else:
		_show_entry()
		# Returning players reconnect straight away (and land back in their lobby).
		if net.player_name != "" and net.status == "offline":
			net.go_online(net.url, net.player_name)
	_on_status(net.status)


# ---------------------------------------------------------------- entry view

func _build_entry() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := UiTheme.label("PLAY ONLINE", 32, UiTheme.CHALK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var name_row := _row(box)
	name_row.add_child(_fixed(UiTheme.label("NICKNAME", 8, UiTheme.CHALK_DIM), 70))
	_name_edit = _edit("YOUR NAME", 12, 180)
	_name_edit.text = net.player_name
	name_row.add_child(_name_edit)

	var create := _big_button("CREATE LOBBY", _on_create)
	create.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(create)

	var join_row := _row(box)
	join_row.add_child(_fixed(UiTheme.label("OR JOIN", 8, UiTheme.CHALK_DIM), 70))
	_code_edit = _edit("CODE", 5, 110)
	_code_edit.text_changed.connect(func(t): var c := _code_edit.caret_column; _code_edit.text = t.to_upper(); _code_edit.caret_column = c)
	_code_edit.text_submitted.connect(func(_t): _on_join())
	join_row.add_child(_code_edit)
	join_row.add_child(_big_button("JOIN", _on_join))

	var server_row := _row(box)
	server_row.add_child(UiTheme.label("SERVER", 8, UiTheme.CHALK_DIM))
	_server_edit = LineEdit.new()
	_server_edit.text = net.url
	_server_edit.custom_minimum_size = Vector2(260, 16)
	_server_edit.add_theme_font_size_override("font_size", 8)
	server_row.add_child(_server_edit)

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): back_requested.emit())
	box.add_child(back)
	return box


func _on_create() -> void:
	_act({"t": "create"})


func _on_join() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.length() != 5:
		_set_status("THE CODE HAS 5 LETTERS", true)
		return
	_act({"t": "join", "code": code})


## Connects if needed (with the typed name), then sends `msg`.
func _act(msg: Dictionary) -> void:
	var name := _name_edit.text.strip_edges()
	if name == "":
		_set_status("TYPE A NICKNAME FIRST", true)
		return
	var url := _server_edit.text.strip_edges()
	if url == "":
		url = Config.DEFAULT_SERVER
	if _welcomed and url == net.url:
		net.player_name = name
		net.send({"t": "hello", "name": name, "token": net.token})
		net.send(msg)
		return
	_pending = msg
	if url != net.url:
		net.go_offline()
		_welcomed = false
	net.go_online(url, name)


# ---------------------------------------------------------------- lobby view

func _show_entry() -> void:
	_entry.visible = true
	_lobby_view.visible = false


func _show_lobby() -> void:
	_entry.visible = false
	_lobby_view.visible = true
	for c in _lobby_view.get_children():
		c.queue_free()
	var me := _me()
	var host: bool = lobby.host_pid == lobby.you_pid
	var members: Array = lobby.members
	var four := members.size() == 4

	var head := _row(_lobby_view)
	head.add_child(UiTheme.label("LOBBY CODE", 8, UiTheme.CHALK_DIM))
	head.add_child(UiTheme.label(lobby.code, 32, UiTheme.GOLD, true))
	head.add_child(UiTheme.label("SEND THIS CODE TO YOUR FRIENDS", 8, UiTheme.CHALK_DIM))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	_lobby_view.add_child(body)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.custom_minimum_size = Vector2(300, 0)
	body.add_child(list)
	list.add_child(UiTheme.label("PLAYERS %d/4" % members.size(), 8, UiTheme.CHALK_DIM))
	for m in members:
		list.add_child(_player_row(m, host, four))
	if members.size() == 3:
		list.add_child(UiTheme.label("3 PLAYERS = FREE FOR ALL", 8, UiTheme.CHALK_DIM))
	elif four:
		list.add_child(UiTheme.label("4 PLAYERS = 2V2" + (" - TAP A TEAM TO SWAP" if host else ""), 8, UiTheme.CHALK_DIM))

	var pick_box := VBoxContainer.new()
	pick_box.add_theme_constant_override("separation", 4)
	body.add_child(pick_box)
	pick_box.add_child(UiTheme.label("YOUR FIGHTER", 8, UiTheme.CHALK_DIM))
	var picks := HBoxContainer.new()
	picks.add_theme_constant_override("separation", 4)
	pick_box.add_child(picks)
	for id in Characters.ALL:
		var b := Button.new()
		b.text = Characters.ALL[id].name.to_upper().replace(" & ", " &\n")
		b.icon = PixelArt.character(id)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.custom_minimum_size = Vector2(46, 76)
		b.toggle_mode = true
		b.set_pressed_no_signal(me.get("char") == id)
		b.disabled = members.any(func(m): return m.char == id and m.pid != lobby.you_pid)
		b.pressed.connect(func(): net.send({"t": "pick", "char": id}))
		picks.add_child(b)

	if me.get("char", "") != "":
		var info := UiTheme.label(FighterInfo.summary(me.char), 8, UiTheme.CHALK_DIM)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lobby_view.add_child(info)

	var settings: Dictionary = lobby.settings
	var srow := _row(_lobby_view)
	if host:
		srow.add_child(UiTheme.label("MAP", 8, UiTheme.CHALK_DIM))
		for id in Maps.ALL:
			var b := Button.new()
			b.text = Maps.ALL[id].name.to_upper()
			b.toggle_mode = true
			b.set_pressed_no_signal(settings.map == id)
			b.pressed.connect(func(): net.send({"t": "settings", "map": id}))
			srow.add_child(b)
		srow = _row(_lobby_view)  # rounds and timer go on their own row
		srow.add_child(UiTheme.label("ROUNDS", 8, UiTheme.CHALK_DIM))
		srow.add_child(_small("-", func(): net.send({"t": "settings", "rounds": maxi(1, settings.rounds - 1)})))
		srow.add_child(UiTheme.label(str(settings.rounds), 16, UiTheme.CHALK))
		srow.add_child(_small("+", func(): net.send({"t": "settings", "rounds": mini(5, settings.rounds + 1)})))
		srow.add_child(_fixed(Control.new(), 8))
		srow.add_child(UiTheme.label("TURN TIMER", 8, UiTheme.CHALK_DIM))
		var t := Button.new()
		t.text = _timer_text(settings.timer)
		t.custom_minimum_size = Vector2(40, 20)
		t.pressed.connect(func():
			var i := TIMERS.find(settings.timer)
			net.send({"t": "settings", "timer": TIMERS[(i + 1) % TIMERS.size()]}))
		srow.add_child(t)
	else:
		srow.add_child(UiTheme.label("MAP %s   ROUNDS %d   TURN TIMER %s" % [
			Maps.ALL[settings.map].name.to_upper(), settings.rounds, _timer_text(settings.timer)], 8, UiTheme.CHALK_DIM))

	var brow := _row(_lobby_view)
	if host:
		brow.add_child(_big_button("START MATCH", func(): net.send({"t": "start"})))
	else:
		var ready: bool = me.get("ready", false)
		var r := _big_button("NOT READY" if ready else "READY!", func(): net.send({"t": "ready", "ready": not ready}))
		r.modulate = Color.WHITE if ready else UiTheme.GOLD
		brow.add_child(r)
	brow.add_child(_big_button("LEAVE", func(): net.send({"t": "leave"})))
	if host:
		_set_status("YOU ARE THE HOST - START WHEN EVERYONE IS READY", false)
	elif me.get("char", "") == "":
		_set_status("PICK YOUR FIGHTER, THEN PRESS READY", false)


func _player_row(m: Dictionary, host: bool, four: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var color := UiTheme.CHALK if m.connected else UiTheme.CHALK_DIM.darkened(0.3)
	var mark := "*" if m.pid == lobby.host_pid else " "
	var who := "%s %s%s" % [mark, str(m.name).to_upper(), "  (YOU)" if m.pid == lobby.you_pid else ""]
	row.add_child(_fixed(UiTheme.label(who, 8, color), 130))
	var char_name: String = Characters.ALL[m.char].name.to_upper() if m.char != "" else "..."
	row.add_child(_fixed(UiTheme.label(char_name, 8, UiTheme.GOLD if m.char != "" else UiTheme.CHALK_DIM), 64))
	var state := "OFFLINE" if not m.connected else ("HOST" if m.pid == lobby.host_pid else ("READY" if m.ready else "NOT READY"))
	row.add_child(_fixed(UiTheme.label(state, 8, UiTheme.HEAL if state == "READY" or state == "HOST" else UiTheme.CHALK_DIM), 64))
	if four:
		var team_name := "TEAM %s" % ("BLUE" if m.team == 0 else "RED")
		if host:
			var b := _small(team_name, func(): net.send({"t": "team", "pid": m.pid, "team": 1 - m.team}))
			b.modulate = UiTheme.TEAM[m.team]
			row.add_child(b)
		else:
			row.add_child(UiTheme.label(team_name, 8, UiTheme.TEAM[m.team]))
	return row


func _me() -> Dictionary:
	for m in lobby.get("members", []):
		if m.pid == lobby.you_pid:
			return m
	return {}


func _timer_text(secs: int) -> String:
	return "OFF" if secs == 0 else "%dS" % secs


# ---------------------------------------------------------------- network

func _on_message(msg: Dictionary) -> void:
	match msg.get("t"):
		"welcome":
			_welcomed = true
			_name_edit.text = msg.name
			if not _pending.is_empty():
				net.send(_pending)
				_pending = {}
		"lobby":
			lobby = msg
			_set_status("", false)
			_show_lobby()
		"left":
			lobby = {}
			_show_entry()
			_set_status("", false)
		"error":
			_set_status(ERRORS.get(msg.code, str(msg.code).to_upper()), true)


func _on_status(s: String) -> void:
	if s != "online":
		_welcomed = false
	match s:
		"connecting":
			_set_status("CONNECTING TO THE SERVER... (A SLEEPING SERVER CAN TAKE UP TO A MINUTE TO WAKE UP)", false)
		"online":
			if _status.text.begins_with("CONNECTING"):
				_set_status("CONNECTED", false)
		"offline":
			pass


# ---------------------------------------------------------------- helpers

func _set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.HIT if is_error else UiTheme.CHALK_DIM)


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 6)
	parent.add_child(r)
	return r


func _fixed(c: Control, w: float) -> Control:
	c.custom_minimum_size.x = w
	if c is Label:
		c.clip_text = true
	return c


func _edit(placeholder: String, max_len: int, w: float) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(w, 26)
	e.add_theme_font_size_override("font_size", 16)
	return e


func _big_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 26)
	b.pressed.connect(callback)
	return b


func _small(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(20, 20)
	b.pressed.connect(callback)
	return b
