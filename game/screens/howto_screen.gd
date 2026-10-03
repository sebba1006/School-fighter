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
	["STATUS", "DIZZY: 1 less move next turn. RAGE (William): more damage for 1-2 turns. BLOCK (Snorre): stops the next hit, then needs 2 turns to recharge. SUGAR RUSH (Snorre): 1.3x damage now, but no attack next turn."],
	["ONLINE", "Create a lobby and send the 5-letter code to your friends (up to 4 players). 2 players = 1v1, 3 = free for all, 4 = 2v2 or 1v1v1v1 (the host chooses). The host picks the map, rounds and turn timer."],
	["SANDBOX", "On Recess, standing in the sandbox hides you from throws and shots (slingshot, water gun, book lob, items). Punches, kicks, dashes and supers still hit."],
	["ITEMS", "With ITEMS ON, a broken locker gives the fighter who broke it an item 30% of the time (hold 1 at a time). Use it from the card above the joystick (or key 5) instead of attacking. BOOK: throw, 12 dmg + push. PENCILS: throw 3 for 3 dmg each. WATER BOTTLE: spill a puddle next to you; an enemy who walks in slips: 5 dmg, stops walking, DIZZY. HALL PASS (only when the map shrinks, from lockers or the mystery box): the detention zone can't hurt you for your next 2 turns."],
	["MYSTERY BOX", "With ITEMS ON a ? box drops near the middle every few turns. Walk onto it to get a MELEE GUARD or a RANGED GUARD (random). Using it: 20-45% less damage from that kind of attack for 1-2 turns."],
	["SHRINKING MAP", "With SHRINK ON, after 6 turns the edge of the map becomes a red DETENTION zone, and it grows every 4 turns. Start your turn in it and you lose 10 HP. Get to the middle!"],
	["BOSS FIGHT", "Team up (you + 2 CPUs, or friends online) against THE PRINCIPAL: 2250 HP, 3x3 tiles, never moves. Your hits on him count double and everyone gets +250 HP. After your team's turns he attacks: RULER SLAM hits everyone next to him (push 2), MEGAPHONE YELL hits everyone in line with him (push 3), DETENTION! hits one player anywhere, and TEACHERS, HELP ME! summons two teachers who chase and scold you. Below 25% HP he gets ANGRY and his attacks do 5 more damage. Every 150 HP he loses, a health apple drops: walk onto it to heal. Win TROPHIES for beating him in different ways."],
	["LUNCH LADY", "The second boss, unlocked by beating the Principal (pick her under BOSS in VS CPU, or with the BOSS button in an online lobby). Same rules, in her Kitchen: MYSTERY MEAT feeds one player next to her (damage and no attack on their next turn - never two turns in a row), GRAVY SPLASH hits everyone in line (push 3) and leaves slippery gravy puddles, TRAY FRISBEE bounces from player to player (up to 3 hits), and KITCHEN, HELP ME! calls two cooks. She has her own 3 trophies."],
	["GYM TEACHER", "The third boss, unlocked by beating the Lunch Lady. In his Gym: PUSH-UPS! makes one player next to him drop and do push-ups (damage, and no moving on their next turn - never two turns in a row), MEDICINE BALL rolls through everyone in line with him and pushes them all the way to the wall, WHISTLE! hits EVERY player on the floor and pushes them back 1, and TEAM, HUDDLE UP! calls two athletes. His own 3 trophies."],
	["FINAL BOSS", "The fourth boss, unlocked by beating the Gym Teacher: THE PRINCIPAL again, with 2500 HP. It starts as a normal fight in his office, but once he has lost 500 HP he gets FURIOUS and the fight moves to SPACE (asteroids instead of desks). In space he stays angry (+5 damage) and has new attacks: GRAVITY SLAM (next to him, push 2), LASER EYES (in line, DIZZY), METEOR SHOWER (up to 3 players) and BLACK HOLE (pulls everyone towards him). His own 3 trophies."],
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
