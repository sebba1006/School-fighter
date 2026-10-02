extends Control
## Title screen: play online or a local battle on one device.

signal online_pressed
signal local_pressed
signal cpu_pressed
signal boss_pressed
signal howto_pressed
signal stats_pressed
signal achievements_pressed

const Characters = preload("res://rules/characters.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Audio = preload("res://audio/audio.gd")


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var title := UiTheme.label("SCHOOL FIGHTER", 32, UiTheme.CHALK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for id in Characters.ALL:
		var t := TextureRect.new()
		t.texture = PixelArt.character(id)
		t.custom_minimum_size = Vector2(32, 48)
		row.add_child(t)
	col.add_child(row)

	for item in [["PLAY ONLINE", online_pressed], ["VS CPU", cpu_pressed], ["BOSS FIGHT", boss_pressed], ["LOCAL BATTLE", local_pressed]]:
		var b := Button.new()
		b.text = item[0]
		b.add_theme_font_override("font", UiTheme.title_font())
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(180, 30)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if item[0] == "BOSS FIGHT":
			b.add_theme_color_override("font_color", UiTheme.HIT)
			b.add_theme_color_override("font_hover_color", UiTheme.HIT)
		var sig: Signal = item[1]
		b.pressed.connect(func():
			Audio.play("click")
			sig.emit())
		col.add_child(b)

	var small := HBoxContainer.new()
	small.alignment = BoxContainer.ALIGNMENT_CENTER
	small.add_theme_constant_override("separation", 6)
	for item in [["HOW TO PLAY", howto_pressed], ["STATS", stats_pressed], ["ACHIEVEMENTS", achievements_pressed]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(87, 24)
		var sig: Signal = item[1]
		b.pressed.connect(func():
			Audio.play("click")
			sig.emit())
		small.add_child(b)
	col.add_child(small)

	var sub := UiTheme.label("online: 2-4 players, each on their own device", 8, UiTheme.CHALK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var sound := Button.new()
	sound.custom_minimum_size = Vector2(90, 20)
	sound.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sound.text = "SOUND ON" if Audio.is_enabled() else "SOUND OFF"
	sound.pressed.connect(func():
		Audio.set_enabled(not Audio.is_enabled())
		Audio.play("click")
		sound.text = "SOUND ON" if Audio.is_enabled() else "SOUND OFF")
	col.add_child(sound)
	Audio.start_music()
