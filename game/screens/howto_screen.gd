extends Control
## How to play: the rules in short, plus every fighter's moves.

signal back_requested

const Characters = preload("res://rules/characters.gd")
const FighterInfo = preload("res://ui/fighter_info.gd")
const PixelArt = preload("res://art/pixel_art.gd")
const UiTheme = preload("res://ui/ui_theme.gd")

const SECTIONS := [
	["GOAL", "Knock out the other fighters. Win the most rounds to win the match."],
	["YOUR TURN", "First move: tap a blue tile, or use the joystick (up to 3 tiles). Then pick ONE attack. Attacking ends your turn. You can also just press END TURN."],
	["ATTACKING", "Tap an attack card on the right (the damage is written on it). Aim with the joystick or by tapping a tile, then press USE or tap the same tile again. Red tiles get hit. Purple tiles also make the enemy DIZZY."],
	["SUPER", "The gold bar fills when you deal damage (fast) and when you take damage (slower). When it is full, your super card lights up."],
	["DESKS AND LOCKERS", "They block walking and most throws. Push an enemy into one for +5 SLAM damage. Hit them enough and they break. Book Lob flies over them."],
	["STATUS", "DIZZY: 1 less move next turn. RAGE (William): more damage for 1-2 turns. BLOCK (Snorre): stops the next hit. SUGAR RUSH (Snorre): 1.3x damage now, but no attack next turn."],
	["ONLINE", "Create a lobby and send the 5-letter code to your friends (up to 4 players). 2 players = 1v1, 3 = free for all, 4 = 2v2. The host picks the map, rounds and turn timer."],
	["ITEMS", "With ITEMS ON, a broken locker gives the fighter who broke it an item 30% of the time (hold 1 at a time). Use it from the card above the joystick (or key 5) instead of attacking. BOOK: throw, 12 dmg + push. PENCILS: throw 3 for 3 dmg each. WATER BOTTLE: spill a puddle next to you; an enemy who walks in slips: 5 dmg, stops walking, DIZZY."],
	["VS CPU", "Fight the computer: 1v1, 1v1v1, or 2v2 with a CPU teammate. Pick each CPU's fighter (or RANDOM) and EASY, NORMAL or HARD."],
	["PC KEYS", "WASD move/aim - 1 2 3 4 attacks - Q super - SPACE use - Z undo - E end turn - ESC cancel aiming."],
]


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(70, 22)
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	head.add_child(UiTheme.label("HOW TO PLAY", 16, UiTheme.CHALK, true))
	outer.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	for sec in SECTIONS:
		col.add_child(UiTheme.label(sec[0], 8, UiTheme.GOLD))
		col.add_child(_text(sec[1]))

	col.add_child(UiTheme.label("THE FIGHTERS", 16, UiTheme.CHALK, true))
	for id in Characters.ALL:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var pic := TextureRect.new()
		pic.texture = PixelArt.character(id)
		pic.custom_minimum_size = Vector2(32, 48)
		row.add_child(pic)
		var info := _text(FighterInfo.summary(id))
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		col.add_child(row)


func _text(t: String) -> Label:
	var l := UiTheme.label(t.to_upper(), 8, UiTheme.CHALK_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 200
	return l
