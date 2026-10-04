extends Control
## Your achievements in leagues of five (bronze, silver, gold, diamond, boss),
## each in a framed box: unlocked ones light up, locked ones show how far along you are.

signal back_requested

const UiTheme = preload("res://ui/ui_theme.gd")
const Achievements = preload("res://stats/achievements.gd")
const Characters = preload("res://rules/characters.gd")
const Progress = preload("res://stats/progress.gd")

var _grid: GridContainer
var _count: Label
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
	head.add_child(UiTheme.label("ACHIEVEMENTS", 16, UiTheme.CHALK, true))
	_count = UiTheme.label("", 8, UiTheme.GOLD)
	head.add_child(_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var reset := Button.new()
	reset.text = "RESET"
	reset.custom_minimum_size = Vector2(70, 22)
	reset.pressed.connect(func():
		if _confirm_reset:
			Achievements.reset()
			_confirm_reset = false
			reset.text = "RESET"
			_fill()
		else:
			_confirm_reset = true
			reset.text = "SURE?")
	head.add_child(reset)
	outer.add_child(head)

	# the league boxes, two by two (scroll down for the boss league)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	_fill()


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for c in Characters.ALL:  # catch up on any level achievements already earned
		Achievements.unlock_mastery(c, Progress.level(c))
	var data := Achievements.load_data()
	_count.text = "%d / %d UNLOCKED" % [Achievements.unlocked_count(data), Achievements.LIST.size() + Achievements.mastery_list().size()]
	for league in Achievements.LEAGUES.size():
		_grid.add_child(_league_box(league, data))
	_grid.add_child(_mastery_box(data))


## One framed box: "BRONZE LEAGUE  3/5" and its five achievements.
func _league_box(league: int, data: Dictionary) -> Control:
	var info: Dictionary = Achievements.LEAGUES[league]
	var color: Color = info.color
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(0.35), 0.22)  # a light tint of the league color
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(305, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	box.add_child(col)
	var first := Achievements.league_start(league)
	var size := Achievements.league_size(league)
	var got := 0
	for i in range(first, first + size):
		if data.unlocked.has(Achievements.LIST[i].id):
			got += 1
	var title := UiTheme.label("%s  %d/%d" % [info.name, got, size], 8, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for i in range(first, first + size):
		col.add_child(_entry(i + 1, Achievements.LIST[i], data, color))
	return box


## FIGHTER MASTERY: one row per fighter with their 4 level achievements and
## their level now.
func _mastery_box(data: Dictionary) -> Control:
	var color: Color = Achievements.MASTERY.color
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.18)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(305, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var all := Achievements.mastery_list()
	var got := all.filter(func(a): return data.unlocked.has(a.id)).size()
	var title := UiTheme.label("%s  %d/%d" % [Achievements.MASTERY.name, got, all.size()], 8, color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for c in Characters.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name := UiTheme.label("%s  LV %d" % [Characters.ALL[c].get("short", Characters.ALL[c].name).to_upper(), Progress.level(c)], 8, UiTheme.CHALK)
		name.custom_minimum_size.x = 120
		row.add_child(name)
		for lv in Achievements.MASTERY_LEVELS:
			var done: bool = data.unlocked.has("lv%d_%s" % [lv, c])
			row.add_child(UiTheme.label("MASTER" if lv == 100 else "LV%d" % lv, 8, UiTheme.GOLD if done else UiTheme.CHALK_DIM.darkened(0.3)))
		col.add_child(row)
	return box


func _entry(number: int, a: Dictionary, data: Dictionary, color: Color) -> Control:
	var done: bool = data.unlocked.has(a.id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var p := Achievements.progress(data, a)
	var title := "%d. %s" % [number, a.name.to_upper()]
	if done:
		title += "  - UNLOCKED!"
	elif p[1] > 1:
		title += "  (%d/%d)" % [p[0], p[1]]
	box.add_child(UiTheme.label(title, 8, color if done else UiTheme.CHALK))
	var desc := UiTheme.label(a.desc.to_upper(), 8, UiTheme.CHALK if done else UiTheme.CHALK_DIM)
	desc.clip_text = true
	desc.custom_minimum_size.x = 290
	box.add_child(desc)
	return box
