extends Control
## Online: pick a nickname, create a lobby, join one with a code or from the
## list of open lobbies, then the lobby itself (players, fighter picks, host
## settings, ready / start, kick).

signal back_requested

const Characters = preload("res://rules/characters.gd")
const Maps = preload("res://rules/maps.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Config = preload("res://net/config.gd")
const FighterInfo = preload("res://ui/fighter_info.gd")
const FighterPicker = preload("res://ui/fighter_picker.gd")
const Battle = preload("res://rules/battle.gd")
const Achievements = preload("res://stats/achievements.gd")
const Progress = preload("res://stats/progress.gd")

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
	"kicked": "YOU WERE REMOVED FROM THAT LOBBY",
	"boss_max_3": "A BOSS FIGHT IS FOR 1-3 PLAYERS",
}
const LIST_EVERY_MS := 4000

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
var _open_list: VBoxContainer
var _next_list := 0


## From BOSS FIGHT -> WITH FRIENDS ONLINE: the lobby you create starts with this boss on.
var _boss_for_new_lobby := ""


func setup(p_net: Node, state := {}, boss_id := "") -> void:
	net = p_net
	lobby = state
	_boss_for_new_lobby = boss_id


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
	_lobby_view.add_theme_constant_override("separation", 6)
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
		# Connect straight away: returning players land back in their lobby,
		# and everyone gets the list of open lobbies.
		if net.status == "offline":
			net.go_online(net.url, net.player_name)
	_on_status(net.status)
	if _boss_for_new_lobby != "" and lobby.is_empty():
		_set_status("BOSS FIGHT WITH FRIENDS: CREATE A LOBBY, THEN SEND THE CODE TO YOUR FRIENDS", false)


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

	box.add_child(UiTheme.label("OPEN LOBBIES", 8, UiTheme.CHALK_DIM))
	box.get_child(box.get_child_count() - 1).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_open_list = VBoxContainer.new()
	_open_list.add_theme_constant_override("separation", 3)
	_open_list.custom_minimum_size.y = 20
	box.add_child(_open_list)
	_show_open_lobbies([])

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


func _process(_delta: float) -> void:
	if _entry.visible and net.status == "online" and Time.get_ticks_msec() >= _next_list:
		_next_list = Time.get_ticks_msec() + LIST_EVERY_MS
		net.send({"t": "list"})


func _show_open_lobbies(list: Array) -> void:
	for c in _open_list.get_children():
		c.queue_free()
	if list.is_empty():
		var none := UiTheme.label("NO OPEN LOBBIES RIGHT NOW - CREATE ONE!" if net.status == "online" else "...", 8, UiTheme.CHALK_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_open_list.add_child(none)
		return
	for item in list.slice(0, 3):
		var row := _row(_open_list)
		row.add_child(_fixed(UiTheme.label("LOBBY %s" % item.code, 8, UiTheme.GOLD), 80))
		row.add_child(_fixed(UiTheme.label("%d/4 PLAYERS - WAITING" % item.players, 8, UiTheme.CHALK), 150))
		var code: String = item.code
		row.add_child(_small("JOIN", func(): _act({"t": "join", "code": code})))


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
	_next_list = 0  # refresh the open-lobby list right away


func _show_lobby() -> void:
	_entry.visible = false
	_lobby_view.visible = true
	for c in _lobby_view.get_children():
		c.queue_free()
	var me := _me()
	var host: bool = lobby.host_pid == lobby.you_pid
	var members: Array = lobby.members
	# 4 players: 2v2 (teams) or everyone for themselves, the host picks
	var four_ffa: bool = lobby.settings.get("four", "2v2") == "ffa"
	var four := members.size() == 4 and not four_ffa

	var head := _row(_lobby_view)
	head.add_child(UiTheme.label("LOBBY CODE", 8, UiTheme.CHALK_DIM))
	head.add_child(UiTheme.label(lobby.code, 32, UiTheme.GOLD, true))
	var public: bool = lobby.settings.get("public", true)
	head.add_child(UiTheme.label("SEND THIS CODE TO YOUR FRIENDS" + (" - ANYONE CAN JOIN FROM THE LIST" if public else " - PRIVATE"), 8, UiTheme.CHALK_DIM))

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
	if members.size() == 3 and not lobby.settings.get("boss", false):
		list.add_child(UiTheme.label("3 PLAYERS = FREE FOR ALL", 8, UiTheme.CHALK_DIM))
	if lobby.settings.get("boss", false):
		list.add_child(UiTheme.label("BOSS FIGHT: CPUS FILL THE TEAM UP TO 3", 8, UiTheme.HIT))
	elif members.size() == 4 or (host and members.size() >= 2):
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 6)
		var mode_text := "4 PLAYERS = FREE FOR ALL" if four_ffa else ("4 PLAYERS = 2V2" + (" - TAP A TEAM" if host and four else ""))
		mrow.add_child(UiTheme.label(mode_text, 8, UiTheme.CHALK_DIM))
		if host:
			mrow.add_child(_small("SWITCH TO 2V2" if four_ffa else "SWITCH TO 1V1V1V1",
				func(): net.send({"t": "settings", "four": "2v2" if four_ffa else "ffa"})))
		list.add_child(mrow)

	# right of the player list: what your fighter does
	var info := UiTheme.label(FighterInfo.summary(me.char) if me.get("char", "") != "" else "PICK YOUR FIGHTER BELOW", 8, UiTheme.CHALK_DIM)
	info.custom_minimum_size.x = 280
	body.add_child(info)

	# your fighter: one full-width row (room for more fighters later)
	var picker := FighterPicker.new()
	var taken := []
	for m in members:
		if m.char != "" and m.pid != lobby.you_pid:
			taken.append(m.char)
	picker.show_state(me.get("char", ""), taken)
	picker.picked.connect(func(id): net.send({"t": "pick", "char": id, "skin": Progress.chosen_skin(id), "tag": Progress.chosen_tag(id), "title": Progress.title_on(id)}))
	_lobby_view.add_child(picker)

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
			b.disabled = settings.get("boss", false)  # the boss has his own room
			srow.add_child(b)
		# BOSS cycles: off -> the Principal -> the Lunch Lady (once you've unlocked her) -> off
		var boss_on: bool = settings.get("boss", false)
		var boss_id: String = settings.get("boss_id", "principal")
		var bb := Button.new()
		bb.text = Characters.BOSSES[boss_id].def.short.to_upper() if boss_on else "BOSS"
		bb.toggle_mode = true
		bb.set_pressed_no_signal(boss_on)
		bb.add_theme_color_override("font_color", UiTheme.HIT)
		bb.add_theme_color_override("font_pressed_color", UiTheme.HIT)
		bb.pressed.connect(func():
			var order: Array = Characters.BOSSES.keys()
			if not boss_on:
				net.send({"t": "settings", "boss": true, "boss_id": order[0]})
				return
			var next := order.find(boss_id) + 1
			if next < order.size() and Achievements.boss_unlocked(Achievements.load_data(), order[next]):
				net.send({"t": "settings", "boss_id": order[next]})
			else:
				net.send({"t": "settings", "boss": false, "boss_id": order[0]}))
		srow.add_child(bb)
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
		srow.add_child(_fixed(Control.new(), 8))
		srow.add_child(UiTheme.label("ITEMS", 8, UiTheme.CHALK_DIM))
		var it := Button.new()
		var items_on: bool = settings.get("items", true)
		it.text = "ON" if items_on else "OFF"
		it.custom_minimum_size = Vector2(40, 20)
		it.pressed.connect(func(): net.send({"t": "settings", "items": not items_on}))
		srow.add_child(it)
		srow.add_child(_fixed(Control.new(), 8))
		srow.add_child(_fixed(Control.new(), 8))
		var bonus: int = settings.get("bonus_hp", 0)
		var hpb := Button.new()
		hpb.text = _bonus_text(bonus)
		hpb.custom_minimum_size = Vector2(76, 20)
		hpb.pressed.connect(func():
			var choices: Array = Battle.BONUS_HP_CHOICES
			net.send({"t": "settings", "bonus_hp": choices[(choices.find(bonus) + 1) % choices.size()]}))
		srow.add_child(hpb)
		srow.add_child(_fixed(Control.new(), 8))
		var shrink: bool = settings.get("shrink", false)
		var shb := Button.new()
		shb.text = "SHRINK ON" if shrink else "SHRINK OFF"
		shb.custom_minimum_size = Vector2(70, 20)
		shb.pressed.connect(func(): net.send({"t": "settings", "shrink": not shrink}))
		srow.add_child(shb)
		srow.add_child(_fixed(Control.new(), 8))
		var is_public: bool = settings.get("public", true)
		var pub := Button.new()
		pub.text = "PUBLIC" if is_public else "PRIVATE"
		pub.custom_minimum_size = Vector2(56, 20)
		pub.pressed.connect(func(): net.send({"t": "settings", "public": not is_public}))
		srow.add_child(pub)
	else:
		if settings.get("boss", false):
			srow.add_child(UiTheme.label("BOSS FIGHT VS %s!   TIMER %s   ITEMS %s" % [
				Characters.BOSSES[settings.get("boss_id", "principal")].def.name.to_upper(),
				_timer_text(settings.timer), "ON" if settings.get("items", true) else "OFF"], 8, UiTheme.HIT))
		else:
			srow.add_child(UiTheme.label("MAP %s   ROUNDS %d   TIMER %s   ITEMS %s   %s   SHRINK %s" % [
				Maps.ALL[settings.map].name.to_upper(), settings.rounds, _timer_text(settings.timer),
				"ON" if settings.get("items", true) else "OFF", _bonus_text(settings.get("bonus_hp", 0)),
				"ON" if settings.get("shrink", false) else "OFF"], 8, UiTheme.CHALK_DIM))

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
	row.add_child(_fixed(UiTheme.label(who, 8, color), 100))
	var char_name: String = Characters.ALL[m.char].get("short", Characters.ALL[m.char].name).to_upper() if m.char != "" else "..."
	row.add_child(_fixed(UiTheme.label(char_name, 8, UiTheme.GOLD if m.char != "" else UiTheme.CHALK_DIM), 64))
	var state := "OFFLINE" if not m.connected else ("HOST" if m.pid == lobby.host_pid else ("READY" if m.ready else "NOT READY"))
	row.add_child(_fixed(UiTheme.label(state, 8, UiTheme.HEAL if state == "READY" or state == "HOST" else UiTheme.CHALK_DIM), 56))
	if host and m.pid != lobby.you_pid:
		row.add_child(_small("KICK", func(): net.send({"t": "kick", "pid": m.pid})))
	elif host:
		row.add_child(_fixed(Control.new(), 34))  # keeps the team buttons in line
	if four:
		var team_name := "BLUE" if m.team == 0 else "RED"
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


func _bonus_text(bonus: int) -> String:
	return "HP: ORIGINAL" if bonus == 0 else "HP: +%d" % bonus


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
			if _boss_for_new_lobby != "":
				# turn the boss on in the lobby you just made (as its host)
				if msg.get("host_pid", -1) == msg.get("you_pid", -2) and msg.members.size() == 1:
					net.send({"t": "settings", "boss": true, "boss_id": _boss_for_new_lobby})
				_boss_for_new_lobby = ""
			_show_lobby()
		"left":
			lobby = {}
			_show_entry()
			_set_status("", false)
		"kicked":
			lobby = {}
			_show_entry()
			_set_status("THE HOST REMOVED YOU FROM THE LOBBY", true)
		"lobbies":
			_show_open_lobbies(msg.list)
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
