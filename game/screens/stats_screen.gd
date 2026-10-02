extends Control
## Your stats: online results and fighters, plus local battles on this device.

signal back_requested

const Characters = preload("res://rules/characters.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Stats = preload("res://stats/stats.gd")
const Achievements = preload("res://stats/achievements.gd")

var _body: VBoxContainer
var _confirm_reset := false


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 22)
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	head.add_child(UiTheme.label("YOUR STATS", 16, UiTheme.CHALK, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var reset := Button.new()
	reset.text = "RESET"
	reset.custom_minimum_size = Vector2(70, 22)
	reset.pressed.connect(func():
		if _confirm_reset:
			Stats.reset()
			_confirm_reset = false
			reset.text = "RESET"
			_fill()
		else:
			_confirm_reset = true
			reset.text = "SURE?")
	head.add_child(reset)
	outer.add_child(head)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	outer.add_child(_body)
	_fill()


func _fill() -> void:
	for c in _body.get_children():
		c.queue_free()
	var played: int = Stats.get_value("online", "played")
	var wins: int = Stats.get_value("online", "wins")
	var losses: int = Stats.get_value("online", "losses")
	var ach := Achievements.load_data()
	_body.add_child(UiTheme.label("ACHIEVEMENTS: %d / %d UNLOCKED (SEE THE ACHIEVEMENTS SCREEN)" % [
		Achievements.unlocked_count(ach), Achievements.LIST.size()], 8, UiTheme.GOLD))
	_body.add_child(UiTheme.label("ONLINE", 8, UiTheme.GOLD))
	var rate := "-" if played == 0 else "%d%%" % roundi(100.0 * wins / played)
	_body.add_child(_line("MATCHES %d    WINS %d    LOSSES %d    WIN RATE %s" % [played, wins, losses, rate]))
	_body.add_child(_line("DAMAGE DEALT %d    KOS %d    SUPERS USED %d" % [
		Stats.get_value("online", "damage"), Stats.get_value("online", "kos"), Stats.get_value("online", "supers")]))

	_body.add_child(UiTheme.label("FIGHTERS (ONLINE)          LOCAL BATTLES ON THIS DEVICE: %d" % Stats.get_value("local", "played"), 8, UiTheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	_body.add_child(grid)
	for h in ["", "FIGHTER", "PLAYED / WINS", "WIN RATE", "LOCAL WINS"]:
		grid.add_child(UiTheme.label(h, 8, UiTheme.CHALK_DIM))
	var favorite := ""
	var most := 0
	for id in Characters.ALL:
		var p: int = Stats.get_value("online_fighters", id + "_played")
		var w: int = Stats.get_value("online_fighters", id + "_wins")
		if p > most:
			most = p
			favorite = id
		var pic := TextureRect.new()
		pic.texture = PixelArt.character(id)
		pic.custom_minimum_size = Vector2(16, 24)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		grid.add_child(pic)
		grid.add_child(UiTheme.label(Characters.ALL[id].name.to_upper(), 8, UiTheme.CHALK))
		grid.add_child(UiTheme.label("%d / %d" % [p, w], 8, UiTheme.CHALK))
		grid.add_child(UiTheme.label("-" if p == 0 else "%d%%" % roundi(100.0 * w / p), 8, UiTheme.CHALK))
		grid.add_child(UiTheme.label("%d" % Stats.get_value("local_fighters", id + "_wins"), 8, UiTheme.CHALK))
	if favorite != "":
		_body.add_child(_line("FAVORITE FIGHTER: %s" % Characters.ALL[favorite].name.to_upper()))
	if played == 0:
		_body.add_child(_line("PLAY AN ONLINE MATCH TO START YOUR STATS!"))


func _line(t: String) -> Label:
	return UiTheme.label(t, 8, UiTheme.CHALK)
