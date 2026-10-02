extends Control
## Title screen: play online or a local battle on one device.

signal online_pressed
signal local_pressed
signal cpu_pressed
signal boss_pressed
signal howto_pressed
signal stats_pressed
signal achievements_pressed
signal trophies_pressed

const Characters = preload("res://rules/characters.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Audio = preload("res://audio/audio.gd")

var _title: Label
var _hoppers: Array = []  # [TextureRect, char id] of the fighters hopping under the title
var _t := 0.0


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
	_title = title

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for id in Characters.ALL:
		# a fixed-size slot so the fighter can hop inside it
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(32, 48)
		var t := TextureRect.new()
		t.texture = PixelArt.character(id)
		t.size = Vector2(32, 48)
		slot.add_child(t)
		row.add_child(slot)
		_hoppers.append([t, id])
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
	for item in [["HOW TO PLAY", howto_pressed], ["STATS", stats_pressed], ["ACHIEVEMENTS", achievements_pressed], ["TROPHIES", trophies_pressed]]:
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

	var audio_row := HBoxContainer.new()
	audio_row.alignment = BoxContainer.ALIGNMENT_CENTER
	audio_row.add_theme_constant_override("separation", 6)
	var sound := Button.new()
	sound.custom_minimum_size = Vector2(90, 20)
	sound.text = "SOUND ON" if Audio.is_enabled() else "SOUND OFF"
	sound.pressed.connect(func():
		Audio.set_enabled(not Audio.is_enabled())
		Audio.play("click")
		sound.text = "SOUND ON" if Audio.is_enabled() else "SOUND OFF")
	audio_row.add_child(sound)
	# MUSIC: SCHOOL -> HYPE -> CHILL -> BOSS
	var music := Button.new()
	music.custom_minimum_size = Vector2(110, 20)
	music.text = "MUSIC: " + Audio.music_name()
	music.pressed.connect(func():
		Audio.next_music()
		music.text = "MUSIC: " + Audio.music_name())
	audio_row.add_child(music)
	col.add_child(audio_row)
	Audio.start_music()


## The fighters take turns hopping in a wave, and the title gently pulses.
func _process(delta: float) -> void:
	_t += delta
	for i in _hoppers.size():
		var t: TextureRect = _hoppers[i][0]
		var k := fposmod(_t * 1.6 - i * 0.18, 2.0)
		var hop := sin(k * PI) * 7.0 if k < 1.0 else 0.0
		t.position.y = -roundf(hop)
		var bob := int(_t * 2.5 + i) % 2 == 1
		t.texture = PixelArt.character(_hoppers[i][1], bob)
	if _title != null:
		_title.pivot_offset = _title.size / 2.0
		var sc := 1.0 + 0.03 * sin(_t * 2.2)
		_title.scale = Vector2(sc, sc)
