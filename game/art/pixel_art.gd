extends RefCounted
## Draws the game's pixel art from code: characters (32x48) and map tiles
## (32x32, tall obstacles 32x48). Shapes are painted onto a grid of material
## names, then a shading pass (light from the top-left) and an outline pass
## turn them into real pixel art. Textures are cached.

const TILE := 32
const CHAR_W := 32
const CHAR_H := 48
const OUTLINE := Color("17121c")

## material -> [base, shade, highlight], or a single colour for flat materials
const PAL := {
	"skin": ["f2c7a5", "d49b78", "fbdcc2"],
	"hairBrown": ["7a4a26", "553117", "9a6437"],
	"hairChestnut": ["94602f", "6a401c", "b98049"],
	"hairDark": ["5a3a22", "3b2514", "7a5432"],
	"hairBlond": ["e8c25a", "bf922f", "f7df8e"],
	"hairLightBrown": ["a87a4a", "805a32", "c89a66"],
	"teeGray": ["9a9ba3", "72737c", "babbc2"],
	"teeWhite": ["eceef1", "c3c7cf", "ffffff"],
	"teeBlack": ["393943", "26262d", "50505c"],
	"teeBlue": ["3f78c9", "2b5595", "6b9be0"],
	"red": ["c8323a", "912029", "e3585d"],
	"hoodie": ["3b3b46", "26262e", "53535f"],
	"pocket": ["2e2e37", "22222a", "3b3b46"],
	"pantsBlack": ["2c2c34", "1d1d23", "3d3d47"],
	"pantsGray": ["6f7079", "54555d", "8a8b94"],
	"pantsLightGray": ["a4a6ae", "82848c", "c0c2c9"],
	"shoeBlack": ["1f1f25", "141418", "34343d"],
	"shoeRed": ["b62c33", "7f1c22", "d64b50"],
	"shoeBrown": ["5b3a26", "3f2718", "77513a"],
	"blade": ["cfd6e0", "98a1b0", "ffffff"],
	"guard": ["d4a640", "a07722", "f0cd6b"],
	"grip": ["6b3f22", "4a2a15", "8a5634"],
	"wood": ["9a6a3c", "6f4a26", "bd8a55"],
	"deskTop": ["c9955a", "a0723f", "e2b47c"],
	"deskFront": ["a6763f", "80592c", "bd8a55"],
	"teacherTop": ["8a5a34", "66401f", "a8744a"],
	"teacherFront": ["6f4526", "52321a", "86573a"],
	"metal": ["8f96a3", "656b77", "b5bcc7"],
	"locker": ["58789d", "3f5877", "7394ba"],
	"benchTop": ["d2a05c", "a87a3e", "e8bd7e"],
	"ballRed": ["d9463b", "a32d25", "f0776c"],
	"ballBlue": ["3f78c9", "2b5595", "6b9be0"],
	"ballOrange": ["e8893a", "b9651f", "f5ab69"],
	"tableTop": ["dfe3e8", "b9bec7", "f3f5f8"],
	"tableEdge": ["9aa2ad", "7a828d", "b4bbc4"],
	"benchBlue": ["4f7fc4", "3a5f96", "6f9be0"],
	"steel": ["b8bfc9", "8f96a3", "d8dde4"],
	"steelDark": ["8f96a3", "6c727d", "a9b0ba"],
	"foodYellow": ["e8c84a", "b99a2a", "f5df7f"],
	"foodGreen": ["6cbf5a", "4c9640", "8fd77f"],
	"beagleTan": ["c8894a", "9e6534", "e0a86e"],
	"beagleBlack": ["3a332f", "241f1c", "524842"],
	"beagleWhite": ["f2efe8", "cdc8be", "ffffff"],
	"beagleEar": ["a8703c", "7e5129", "c08550"],
	"oldMuzzle": ["dcd8cf", "b9b4aa", "f0eee8"],
	"fence": ["9aa3ad", "6f7884", "c3cad2"],
	"leaf": ["4f9a45", "36702f", "74bf63"],
	"trunk": ["7a5232", "573821", "9a6c45"],
	"bikeRed": ["c8423a", "92281f", "e56a5f"],
	"labTop": ["3a3f48", "272b32", "565c67"],
	"labCab": ["e4e8ec", "b9c0c8", "f7f9fb"],
	"glass": ["a9d4ec", "7fb2d1", "d6eef9"],
	"flask": ["7fd36b", "58a848", "a8e898"],
	"bone": ["ece6d2", "c4bca4", "fffaea"],
	"pencil": ["f0c330", "c4961c", "f8dc72"],
	"pencilWood": ["e8c79a", "c9a272", "f5dfbf"],
	"eraser": ["e88aa0", "c46a80", "f5b3c3"],
	"puddle": ["7fbbe6", "5d9cd0", "b8def5"],
	"slide": ["f2c64a", "c99a26", "f8de86"],
	"suit": ["4a4f5c", "343844", "626879"],
	"greyHair": ["b9b9bd", "8f8f95", "dadade"],
	"apple": ["d9363b", "a3232a", "f06a6d"],
	"gravy": ["8a5a2b", "6a4220", "b07a45"],
	"hairnet": ["d9d4c7", "b3ad9f", "f0ece2"],
	"curlyRed": ["b5502e", "8a3a1f", "d4734d"],
	"dressPink": ["d9829b", "b0607a", "efa6ba"],
	"apron": ["f1f1ec", "cfd0c8", "ffffff"],
	"chefHat": ["f4f4f0", "d2d3cc", "ffffff"],
	"eye": "ffffff",
	"pupil": "1a1420",
	"mouth": "7a2e2e",
	"frame": "1a1420",
	"string": "e6e6ea",
	"teeth": "ffffff",
	"seam": "34495f",
	"handle": "c9d3de",
	"crack": "2a1d14",
}

const LOOKS := {
	"sebba": {"legs": 10, "hair": "hairBrown", "hair_style": "neat", "shirt": "teeGray", "sleeve": "teeGray", "pants": "pantsBlack", "shoes": "shoeBlack", "glasses": true, "mouth": "flat", "pupil": 1},
	"william": {"legs": 13, "hair": "hairBlond", "hair_style": "swept", "shirt": "teeBlack", "sleeve": "red", "stripe": "red", "pants": "pantsBlack", "shoes": "shoeRed", "glasses": true, "mouth": "smile", "pupil": 0},
	"snorre": {"legs": 9, "hair": "hairChestnut", "hair_style": "messy", "shirt": "teeWhite", "sleeve": "teeWhite", "pants": "pantsGray", "shoes": "shoeBrown", "sword": true, "mouth": "smile", "pupil": 0},
	"leon": {"legs": 11, "hair": "hairLightBrown", "hair_style": "swoop", "shirt": "teeBlue", "sleeve": "teeBlue", "pants": "pantsLightGray", "shoes": "shoeBlack", "mouth": "smile", "pupil": 1},
	"mike": {"legs": 11, "hair": "hairDark", "hair_style": "short", "shirt": "hoodie", "sleeve": "hoodie", "hoodie": true, "pants": "pantsBlack", "shoes": "shoeBlack", "slingshot": true, "mouth": "smirk", "pupil": 1},
	# the athletes the Gym Teacher calls: red jersey, white stripe, sweatband
	"athlete": {"legs": 12, "hair": "hairBlond", "hair_style": "headband", "shirt": "red", "sleeve": "red", "stripe": "teeWhite", "pants": "pantsBlack", "shoes": "shoeRed", "mouth": "smirk", "pupil": 0},
	# the cooks the Lunch Lady calls: tall white chef's hat and apron
	"cook": {"legs": 12, "hair": "hairBrown", "hair_style": "chef", "shirt": "apron", "sleeve": "apron", "stripe": "dressPink", "pants": "pantsGray", "shoes": "shoeBlack", "mouth": "smirk", "pupil": 1},
	# the teachers the Principal summons: green shirt and red tie
	"teacher": {"legs": 13, "hair": "hairDark", "hair_style": "neat", "shirt": "leaf", "sleeve": "leaf", "tie": "red", "pants": "pantsGray", "shoes": "shoeBrown", "glasses": true, "mouth": "flat", "pupil": 0},
}

static var _cache := {}


# ---------------------------------------------------------------- painter

class Painter:
	## Skins: materials painted as other materials (e.g. "teeGray" -> "red").
	static var remap := {}
	var w: int
	var h: int
	var g := []

	func _init(p_w: int, p_h: int) -> void:
		w = p_w
		h = p_h
		for y in h:
			var row := []
			row.resize(w)
			row.fill("")
			g.append(row)

	func px(x: int, y: int, m: String) -> void:
		if x >= 0 and x < w and y >= 0 and y < h:
			g[y][x] = remap.get(m, m)

	func rect(x0: int, y0: int, x1: int, y1: int, m: String) -> void:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				px(x, y, m)

	func ell(cx: float, cy: float, rx: float, ry: float, m: String, max_y := 9999) -> void:
		for y in range(floori(cy - ry) - 1, ceili(cy + ry) + 2):
			if y > max_y:
				continue
			for x in range(floori(cx - rx) - 1, ceili(cx + rx) + 2):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0:
					px(x, y, m)

	func at(x: int, y: int) -> String:
		if x < 0 or y < 0 or x >= w or y >= h:
			return ""
		return g[y][x]

	## Shading + outline -> Image.
	func bake() -> Image:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in h:
			for x in w:
				var k: String = g[y][x]
				if k == "":
					var edge := at(x + 1, y) != "" or at(x - 1, y) != "" or at(x, y + 1) != "" or at(x, y - 1) != ""
					if edge:
						img.set_pixel(x, y, OUTLINE)
					continue
				var p = PAL[k]
				if p is String:
					img.set_pixel(x, y, Color(p))
					continue
				var same := func(a: String) -> bool: return a == k or (a != "" and PAL[a] is String)
				var r := at(x + 1, y)
				var b := at(x, y + 1)
				var l := at(x - 1, y)
				var a := at(x, y - 1)
				var shade: bool = not same.call(r) or not same.call(b) or (a != "" and not same.call(a))
				var light: bool = not shade and (not same.call(l) or a == "")
				img.set_pixel(x, y, Color(p[1] if shade else (p[2] if light else p[0])))
		return img


# ---------------------------------------------------------------- characters

## Skins (unlocked by levelling a fighter up): 0 = the normal look, then three
## new outfits and a golden one. Each is a list of material swaps.
const GOLD := {"teeGray": "guard", "teeBlack": "guard", "teeWhite": "guard", "teeBlue": "guard",
	"hoodie": "guard", "pocket": "pencil", "red": "pencil", "pantsBlack": "foodYellow", "pantsGray": "foodYellow",
	"pantsLightGray": "foodYellow", "shoeBlack": "guard", "shoeRed": "guard", "shoeBrown": "guard"}
const SKINS := {
	"sebba": [{}, {"teeGray": "teeBlue", "pantsBlack": "pantsGray"}, {"teeGray": "red", "shoeBlack": "shoeRed"},
		{"teeGray": "leaf", "pantsBlack": "pantsLightGray", "shoeBlack": "shoeBrown"}, GOLD],
	"william": [{}, {"teeBlack": "teeWhite", "red": "teeBlue", "shoeRed": "shoeBlack"},
		{"teeBlack": "suit", "red": "slide", "shoeRed": "shoeBrown"}, {"teeBlack": "leaf", "red": "teeBlack"}, GOLD],
	"snorre": [{}, {"teeWhite": "teeBlack", "pantsGray": "pantsBlack"}, {"teeWhite": "dressPink", "shoeBrown": "shoeRed"},
		{"teeWhite": "teeBlue", "pantsGray": "pantsLightGray", "shoeBrown": "shoeBlack"}, GOLD],
	"leon": [{}, {"teeBlue": "red", "pantsLightGray": "pantsBlack"}, {"teeBlue": "leaf", "shoeBlack": "shoeBrown"},
		{"teeBlue": "slide", "pantsLightGray": "pantsGray", "shoeBlack": "shoeRed"}, GOLD],
	"mike": [{}, {"hoodie": "red", "pocket": "bikeRed"}, {"hoodie": "teeBlue", "pocket": "ballBlue", "pantsBlack": "pantsGray"},
		{"hoodie": "leaf", "pocket": "foodGreen", "shoeBlack": "shoeRed"}, GOLD],
	"dogs": [{}, {"beagleTan": "hairDark", "beagleEar": "beagleBlack"}, {"beagleTan": "teeWhite", "beagleEar": "beagleBlack"},
		{"beagleTan": "red", "beagleEar": "bikeRed"},
		{"beagleTan": "guard", "beagleBlack": "foodYellow", "beagleEar": "pencil", "oldMuzzle": "slide"}],
}


## `bob` is the second idle frame (upper body 1px lower); `skin` is 0-4 (see SKINS).
static func character(char_id: String, bob := false, skin := 0) -> Texture2D:
	var key := "char_%s_%s_%d" % [char_id, bob, skin]
	if not _cache.has(key):
		var swaps: Array = SKINS.get(char_id, [{}])
		Painter.remap = swaps[clampi(skin, 0, swaps.size() - 1)]
		var img := _dogs_image(bob) if char_id == "dogs" else _character_image(LOOKS[char_id], bob)
		Painter.remap = {}
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


static func _character_image(c: Dictionary, bob: bool) -> Image:
	var p := Painter.new(CHAR_W, CHAR_H)
	var T := 10
	var u := 1 if bob else 0
	var pants_top: int = 45 - c.legs
	var tt: int = pants_top - T + u
	var hcy: int = pants_top - T - 8 + u

	if c.get("sword", false):
		var x := 4
		var y := tt - 7
		for t in 24:
			var m := "grip" if t < 3 else "blade"
			p.px(x, y, m)
			if t > 0 and t < 23:
				p.px(x + 1, y, m)
			if t == 3:
				for o in [[2, -2], [1, -1], [-1, 1], [-2, 2], [0, 0], [1, 0]]:
					p.px(x + o[0], y + o[1], "guard")
			x += 1
			y += 1
	if c.get("hoodie", false):
		p.ell(16, tt - 1, 10, 3, "hoodie")

	p.rect(10, pants_top, 21, 44, c.pants)
	p.rect(15, pants_top + 2, 16, 44, "")
	p.rect(9, 45, 14, 46, c.shoes)
	p.rect(17, 45, 22, 46, c.shoes)

	var hoodie: bool = c.get("hoodie", false)
	p.rect(10, tt, 21, pants_top + 1 if hoodie else pants_top, c.shirt)
	p.rect(7, tt, 24, tt, c.sleeve)
	var sleeve_rows := T - 1 if hoodie else 3
	for r in range(1, T):
		var m: String = c.sleeve if r <= sleeve_rows else "skin"
		p.rect(7, tt + r, 8, tt + r, m)
		p.rect(23, tt + r, 24, tt + r, m)
	p.rect(7, tt + T, 8, tt + T + 1, "skin")
	p.rect(23, tt + T, 24, tt + T + 1, "skin")
	if not hoodie:
		p.rect(14, tt, 17, tt, "skin")
		p.rect(15, tt + 1, 16, tt + 1, "skin")
	if c.has("stripe"):
		p.rect(10, tt + 3, 21, tt + 4, c.stripe)
	if c.has("tie"):
		p.rect(15, tt + 1, 16, tt + 6, c.tie)
		p.px(15, tt + 7, c.tie)
	if hoodie:
		p.rect(12, tt + 6, 19, tt + 8, "pocket")
		p.rect(14, tt + 1, 14, tt + 3, "string")
		p.rect(17, tt + 1, 17, tt + 3, "string")

	p.ell(16, hcy, 8, 8, "skin")
	p.rect(7, hcy, 7, hcy + 1, "skin")
	p.rect(24, hcy, 24, hcy + 1, "skin")

	var h: String = c.hair
	var top := hcy - 8
	p.ell(16, hcy - 4, 9, 6, h, hcy - 4)
	p.rect(8, hcy - 3, 9, hcy - 2, h)
	p.rect(22, hcy - 3, 23, hcy - 2, h)
	match c.hair_style:
		"neat":
			p.rect(10, hcy - 3, 13, hcy - 3, h)
			p.px(10, hcy - 2, h)
		"swept":
			p.rect(15, hcy - 3, 21, hcy - 3, h)
			p.rect(19, hcy - 2, 21, hcy - 2, h)
			for x in [12, 13, 18]:
				p.px(x, top - 3, h)
		"messy":
			for x in [10, 11, 13, 14, 17, 19, 20]:
				p.px(x, hcy - 3, h)
			p.px(11, hcy - 2, h)
			p.px(19, hcy - 2, h)
			p.px(10, top - 2, h)
			p.px(15, top - 3, h)
			p.px(16, top - 3, h)
			p.px(21, top - 2, h)
		"short":
			p.rect(17, hcy - 3, 21, hcy - 3, h)
			p.px(21, hcy - 2, h)
		"headband":  # short spiky hair with a white sweatband
			for x in [11, 14, 17, 20]:
				p.px(x, top - 2, h)
			p.rect(8, hcy - 4, 23, hcy - 3, "teeWhite")
		"chef":  # a tall white chef's hat over short hair
			p.rect(9, top - 6, 22, hcy - 4, "chefHat")
			p.ell(12, top - 6, 4, 3, "chefHat")
			p.ell(19, top - 6, 4, 3, "chefHat")
			p.ell(15.5, top - 8, 4, 3, "chefHat")
		"swoop":
			# fringe swept to one side with a little flick on top
			p.rect(10, hcy - 3, 16, hcy - 3, h)
			p.rect(10, hcy - 2, 12, hcy - 2, h)
			p.px(14, top - 3, h)
			p.px(15, top - 3, h)
			p.px(16, top - 2, h)

	p.rect(11, hcy - 1, 13, hcy + 1, "eye")
	p.rect(18, hcy - 1, 20, hcy + 1, "eye")
	var pu: int = c.get("pupil", 0)
	p.rect(12 + pu, hcy, 12 + pu, hcy + 1, "pupil")
	p.rect(19 + pu, hcy, 19 + pu, hcy + 1, "pupil")

	var my := hcy + 4
	match c.mouth:
		"flat":
			p.rect(14, my, 17, my, "mouth")
		"smile":
			p.px(13, my - 1, "mouth")
			p.px(18, my - 1, "mouth")
			p.rect(14, my, 17, my, "mouth")
		"smirk":
			p.rect(15, my, 18, my, "mouth")
			p.px(19, my - 1, "mouth")

	if c.get("glasses", false):
		for x0 in [10, 17]:
			p.rect(x0, hcy - 2, x0 + 4, hcy - 2, "frame")
			p.rect(x0, hcy + 2, x0 + 4, hcy + 2, "frame")
			p.rect(x0, hcy - 2, x0, hcy + 2, "frame")
			p.rect(x0 + 4, hcy - 2, x0 + 4, hcy + 2, "frame")
		p.rect(15, hcy - 1, 16, hcy - 1, "frame")
		p.px(9, hcy - 1, "frame")
		p.px(22, hcy - 1, "frame")

	if c.get("slingshot", false):
		var hy := tt + T
		p.px(25, hy, "skin")
		p.px(26, hy, "skin")
		p.rect(27, hy - 1, 27, hy + 1, "wood")
		for o in [[26, -2], [28, -2], [26, -3], [28, -3]]:
			p.px(o[0], hy + o[1], "wood")
	return p.bake()


## Lucy (the puppy) lying on the back of Charlie (the older beagle), side view.
static func _dogs_image(bob: bool) -> Image:
	var p := Painter.new(CHAR_W, CHAR_H)
	# Charlie: the big one, standing, facing right
	p.rect(2, 27, 3, 34, "beagleTan")  # tail up
	p.rect(2, 26, 3, 27, "beagleWhite")
	p.ell(14, 37, 11, 5.5, "beagleTan")
	p.ell(13, 34, 8, 2.5, "beagleBlack")
	p.rect(7, 40, 21, 42, "beagleWhite")
	p.rect(22, 35, 24, 41, "beagleWhite")
	for x in [5, 9, 18, 22]:
		p.rect(x, 41, x + 1, 46, "beagleWhite")
	p.ell(26, 30, 4.5, 4.5, "beagleTan")
	p.rect(27, 31, 31, 34, "oldMuzzle")  # grey old-dog muzzle
	p.rect(26, 26, 27, 30, "oldMuzzle")
	p.rect(30, 31, 31, 32, "pupil")
	p.px(28, 29, "pupil")
	p.rect(22, 28, 24, 35, "beagleEar")
	# Lucy: the puppy, lying on his back (breathes with the idle bob).
	# Kept one row above him so the outline separates the two dogs.
	var o := 1 if bob else 0
	p.rect(3, 23 + o, 3, 27 + o, "beagleTan")
	p.px(3, 22 + o, "beagleWhite")
	p.ell(10, 28 + o, 6, 2.5, "beagleTan", 30 + o)
	p.ell(9, 26.5 + o, 4, 1.5, "beagleBlack")
	p.ell(15, 22 + o, 3.5, 3.5, "beagleTan")  # head up, looking ahead
	p.rect(17, 22 + o, 20, 24 + o, "beagleWhite")
	p.px(20, 22 + o, "pupil")
	p.px(16, 21 + o, "pupil")
	p.rect(15, 18 + o, 15, 21 + o, "beagleWhite")
	p.rect(12, 21 + o, 13, 26 + o, "beagleEar")
	p.rect(15, 29 + o, 18, 30, "beagleWhite")  # front paws
	return p.bake()


# ---------------------------------------------------------------- the boss

## The Principal: 96x128 (3 tiles wide, standing on his 3x3 tiles). Bald, grey
## at the sides, glasses, mustache, angry eyebrows, grey suit, red tie, and a
## big ruler in his hand. `bob` is the idle frame.
static func boss(bob := false) -> Texture2D:
	var key := "boss_%s" % bob
	if not _cache.has(key):
		var p := Painter.new(96, 128)
		var u := 1 if bob else 0
		# shoes and legs
		p.rect(28, 120, 45, 126, "shoeBlack")
		p.rect(51, 120, 68, 126, "shoeBlack")
		p.rect(31, 92, 45, 120, "suit")
		p.rect(51, 92, 65, 120, "suit")
		# jacket, shirt, tie
		p.rect(18, 52 + u, 78, 96, "suit")
		p.rect(40, 52 + u, 56, 72, "teeWhite")
		for i in 8:  # jacket lapels closing into a V
			p.rect(40, 66 + i + u, 40 + i, 66 + i + u, "suit")
			p.rect(56 - i, 66 + i + u, 56, 66 + i + u, "suit")
		p.rect(46, 54 + u, 50, 80 + u, "red")
		p.rect(45, 53 + u, 51, 56 + u, "red")
		# arms; the right hand holds the ruler
		p.rect(8, 56 + u, 19, 92, "suit")
		p.rect(8, 92, 19, 99, "skin")
		p.rect(77, 56 + u, 88, 86, "suit")
		p.rect(78, 86, 90, 94, "skin")
		p.rect(86, 30 + u, 91, 100, "foodYellow")
		for y in range(34, 98, 6):
			p.rect(86, y + u, 88, y + u, "pupil")
		# neck and head
		p.rect(40, 44 + u, 56, 53 + u, "skin")
		p.ell(48, 28 + u, 19, 21, "skin")
		p.rect(28, 22 + u, 32, 36 + u, "greyHair")
		p.rect(64, 22 + u, 68, 36 + u, "greyHair")
		p.rect(26, 26 + u, 29, 33 + u, "skin")  # ears
		p.rect(67, 26 + u, 70, 33 + u, "skin")
		# angry eyebrows, glasses, eyes
		for i in 9:  # thick eyebrows slanting down to the middle: angry
			p.rect(34 + i, 19 + i / 3 + u, 34 + i, 21 + i / 3 + u, "pupil")
			p.rect(62 - i, 19 + i / 3 + u, 62 - i, 21 + i / 3 + u, "pupil")
		p.rect(34, 25 + u, 45, 32 + u, "frame")
		p.rect(51, 25 + u, 62, 32 + u, "frame")
		p.rect(35, 26 + u, 44, 31 + u, "eye")
		p.rect(52, 26 + u, 61, 31 + u, "eye")
		p.rect(46, 27 + u, 50, 28 + u, "frame")
		p.rect(39, 27 + u, 41, 30 + u, "pupil")
		p.rect(55, 27 + u, 57, 30 + u, "pupil")
		# nose, mustache, frown
		p.rect(47, 32 + u, 49, 36 + u, "skin")
		p.rect(39, 37 + u, 57, 40 + u, "greyHair")
		p.rect(36, 39 + u, 39, 41 + u, "greyHair")
		p.rect(57, 39 + u, 60, 41 + u, "greyHair")
		p.rect(43, 43 + u, 53, 43 + u, "mouth")
		p.px(42, 44 + u, "mouth")
		p.px(54, 44 + u, "mouth")
		_cache[key] = ImageTexture.create_from_image(p.bake())
	return _cache[key]


## Any boss's big sprite by id ("principal" or "lunch_lady").
static func boss_sprite(id: String, bob := false) -> Texture2D:
	match id:
		"lunch_lady":
			return lunch_lady(bob)
		"gym_teacher":
			return gym_teacher(bob)
	return boss(bob)


## The Gym Teacher: 96x128. Red cap, big mustache, blue tracksuit with white
## stripes, a whistle on a cord, and a clipboard in his hand.
static func gym_teacher(bob := false) -> Texture2D:
	var key := "gym_teacher_%s" % bob
	if not _cache.has(key):
		var p := Painter.new(96, 128)
		var u := 1 if bob else 0
		# sneakers and tracksuit trousers with a stripe
		p.rect(26, 119, 45, 126, "teeWhite")
		p.rect(51, 119, 70, 126, "teeWhite")
		p.rect(26, 124, 45, 126, "red")
		p.rect(51, 124, 70, 126, "red")
		p.rect(30, 92, 45, 119, "teeBlue")
		p.rect(51, 92, 66, 119, "teeBlue")
		p.rect(30, 92, 31, 119, "teeWhite")
		p.rect(65, 92, 66, 119, "teeWhite")
		# jacket: broad shoulders, white shoulder stripes, zip
		p.rect(16, 52 + u, 80, 96, "teeBlue")
		p.rect(16, 52 + u, 80, 55 + u, "teeWhite")
		p.rect(47, 56 + u, 49, 96, "steel")
		# arms: the left one holds a clipboard, the right one is on his hip
		p.rect(5, 56 + u, 16, 88, "teeBlue")
		p.rect(5, 56 + u, 6, 88, "teeWhite")
		p.rect(2, 70 + u, 20, 94 + u, "wood")  # clipboard
		p.rect(4, 74 + u, 18, 92 + u, "teeWhite")
		for y in [78, 82, 86]:
			p.rect(6, y + u, 15, y + u, "pantsGray")
		p.rect(8, 68 + u, 14, 71 + u, "steel")
		p.rect(80, 56 + u, 91, 84, "teeBlue")
		p.rect(90, 56 + u, 91, 84, "teeWhite")
		p.rect(81, 84, 91, 91, "skin")
		# whistle on a cord
		for i in 10:
			p.px(41 + i / 2, 54 + i + u, "string")
			p.px(55 - i / 2, 54 + i + u, "string")
		p.rect(45, 64 + u, 51, 68 + u, "steel")
		p.rect(51, 65 + u, 53, 66 + u, "steel")
		# neck, head, cap with a brim
		p.rect(40, 44 + u, 56, 53 + u, "skin")
		p.ell(48, 30 + u, 19, 20, "skin")
		p.ell(48, 15 + u, 20, 9, "red")
		p.rect(28, 15 + u, 68, 19 + u, "red")
		p.rect(46, 9 + u, 50, 11 + u, "teeWhite")  # cap badge
		p.rect(46, 19 + u, 76, 22 + u, "bikeRed")  # brim sticking out to the side
		p.rect(26, 26 + u, 29, 33 + u, "skin")
		p.rect(67, 26 + u, 70, 33 + u, "skin")
		# eyes, eyebrows, big brown mustache, open shouting mouth
		p.rect(35, 24 + u, 44, 25 + u, "hairDark")
		p.rect(52, 24 + u, 61, 25 + u, "hairDark")
		p.rect(37, 27 + u, 43, 31 + u, "eye")
		p.rect(53, 27 + u, 59, 31 + u, "eye")
		p.rect(40, 28 + u, 42, 31 + u, "pupil")
		p.rect(54, 28 + u, 56, 31 + u, "pupil")
		p.rect(46, 32 + u, 50, 36 + u, "skin")
		p.rect(36, 37 + u, 60, 41 + u, "hairDark")
		p.rect(34, 40 + u, 37, 43 + u, "hairDark")
		p.rect(59, 40 + u, 62, 43 + u, "hairDark")
		p.rect(44, 42 + u, 52, 46 + u, "mouth")
		_cache[key] = ImageTexture.create_from_image(p.bake())
	return _cache[key]


## The Lunch Lady: 96x128 like the Principal. Red curly hair under a hairnet,
## pink dress, big white apron with a gravy stain, and a ladle in her hand.
static func lunch_lady(bob := false) -> Texture2D:
	var key := "lunch_lady_%s" % bob
	if not _cache.has(key):
		var p := Painter.new(96, 128)
		var u := 1 if bob else 0
		# shoes, legs, wide dress
		p.rect(30, 120, 44, 126, "shoeBlack")
		p.rect(52, 120, 66, 126, "shoeBlack")
		p.rect(33, 104, 43, 120, "skin")
		p.rect(53, 104, 63, 120, "skin")
		p.ell(48, 86 + u, 32, 24, "dressPink")
		p.rect(16, 54 + u, 80, 104, "dressPink")
		# apron with a gravy stain, and its strings
		p.rect(28, 60 + u, 68, 106, "apron")
		p.rect(24, 58 + u, 72, 60 + u, "apron")
		p.ell(56, 88 + u, 5, 4, "gravy")
		p.ell(36, 76 + u, 3, 2, "gravy")
		p.rect(40, 70 + u, 56, 74 + u, "apron")
		# arms: the left one on her hip, the right one holds the ladle up
		p.rect(6, 56 + u, 17, 84, "dressPink")
		p.rect(6, 84, 17, 92, "skin")
		p.rect(79, 56 + u, 90, 80, "dressPink")
		p.rect(80, 80, 91, 88, "skin")
		p.rect(84, 26 + u, 87, 82, "steel")  # ladle handle
		p.ell(85.5, 22 + u, 8, 6, "steel")  # ladle bowl
		p.ell(85.5, 20 + u, 6, 3, "gravy")
		# neck and head, red curls under a hairnet
		p.rect(40, 46 + u, 56, 54 + u, "skin")
		p.ell(48, 30 + u, 20, 21, "skin")
		p.ell(48, 12 + u, 22, 10, "curlyRed")
		for x in [26, 30, 64, 68]:
			p.ell(x, 24 + u, 4, 6, "curlyRed")
		p.ell(48, 10 + u, 21, 8, "hairnet")
		for x in range(30, 68, 5):  # net lines
			p.rect(x, 4 + u, x, 16 + u, "curlyRed")
		# eyes with heavy eyeshadow, a mole, big frown with lipstick
		p.rect(36, 26 + u, 44, 29 + u, "dressPink")
		p.rect(52, 26 + u, 60, 29 + u, "dressPink")
		p.rect(37, 28 + u, 43, 32 + u, "eye")
		p.rect(53, 28 + u, 59, 32 + u, "eye")
		p.rect(40, 29 + u, 42, 32 + u, "pupil")
		p.rect(54, 29 + u, 56, 32 + u, "pupil")
		p.rect(46, 33 + u, 50, 38 + u, "skin")
		p.rect(58, 37 + u, 59, 38 + u, "pupil")  # mole
		p.rect(41, 43 + u, 55, 44 + u, "red")
		p.px(40, 45 + u, "red")
		p.px(56, 45 + u, "red")
		_cache[key] = ImageTexture.create_from_image(p.bake())
	return _cache[key]


## A trophy cup (24x24): gold if won, a dark grey shape if not yet.
static func trophy(won: bool) -> Texture2D:
	var key := "trophy_%s" % won
	if not _cache.has(key):
		var m := "guard" if won else "pantsGray"
		var p := Painter.new(24, 24)
		p.rect(5, 3, 18, 4, m)  # rim
		p.ell(11.5, 8, 6.5, 6, m)
		p.rect(2, 5, 4, 10, m)  # handles
		p.rect(19, 5, 21, 10, m)
		p.rect(10, 13, 13, 17, m)  # stem
		p.rect(7, 18, 16, 20, m)  # base
		if won:
			p.rect(8, 5, 9, 9, "teeWhite")  # shine
		_cache[key] = ImageTexture.create_from_image(p.bake())
	return _cache[key]


## A health apple lying on a tile (boss fights).
static func apple() -> Texture2D:
	if not _cache.has("apple"):
		var p := Painter.new(TILE, TILE)
		p.ell(16, 19, 8, 7.5, "apple")
		p.rect(15, 8, 16, 12, "trunk")
		p.ell(20, 9, 3.5, 2, "leaf")
		p.rect(12, 15, 13, 17, "teeWhite")  # shine
		_cache["apple"] = ImageTexture.create_from_image(p.bake())
	return _cache["apple"]


# ---------------------------------------------------------------- items

## 16x16 icon for an item: "book", "pencils" or "water".
static func item_icon(id: String) -> Texture2D:
	var key := "item_" + id
	if not _cache.has(key):
		var p := Painter.new(16, 16)
		match id:
			"book":
				p.rect(2, 3, 13, 13, "red")
				p.rect(3, 12, 13, 13, "teeWhite")  # page edges
				p.rect(2, 3, 3, 13, "pantsBlack")  # spine
				p.rect(6, 6, 11, 7, "guard")
			"pencils":
				for i in 3:
					var y := 3 + i * 4
					p.rect(4, y, 12, y + 1, "pencil")
					p.rect(13, y, 13, y + 1, "pencilWood")
					p.px(14, y, "pupil")
					p.rect(2, y, 3, y + 1, "eraser")
			"melee_guard":  # shield with a red fist mark
				p.ell(8, 7, 6, 6.5, "steel")
				p.rect(2, 2, 13, 7, "steel")
				p.rect(5, 5, 10, 9, "red")
				p.rect(5, 4, 9, 4, "red")
			"ranged_guard":  # shield with a blue target
				p.ell(8, 7, 6, 6.5, "steel")
				p.rect(2, 2, 13, 7, "steel")
				p.ell(8, 7, 3.5, 3.5, "teeBlue")
				p.ell(8, 7, 1.5, 1.5, "teeWhite")
			"hall_pass":  # a yellow card on a red lanyard, with a little stamp
				p.rect(6, 0, 6, 3, "red")
				p.rect(9, 0, 9, 3, "red")
				p.rect(6, 0, 9, 0, "red")
				p.rect(3, 4, 12, 14, "pencil")
				p.rect(4, 5, 11, 5, "teeWhite")
				p.rect(4, 7, 9, 7, "pantsBlack")
				p.rect(4, 9, 8, 9, "pantsBlack")
				p.ell(10, 12, 1.5, 1.5, "red")
			"water":
				p.rect(5, 4, 10, 14, "glass")
				p.rect(6, 2, 9, 3, "glass")
				p.rect(6, 1, 9, 1, "ballBlue")
				p.rect(5, 8, 10, 10, "ballBlue")  # label
		_cache[key] = ImageTexture.create_from_image(p.bake())
	return _cache[key]


## The mystery box (a "?" crate) sitting on a floor tile.
static func mystery_box() -> Texture2D:
	if not _cache.has("box"):
		var p := Painter.new(TILE, TILE)
		p.rect(6, 8, 25, 27, "deskTop")
		p.rect(6, 8, 25, 10, "deskFront")
		p.rect(6, 25, 25, 27, "deskFront")
		# a "?" in gold
		for c in [[13, 13], [14, 12], [15, 12], [16, 12], [17, 12], [18, 13], [18, 14], [17, 15], [16, 16], [15, 17], [15, 18], [15, 21], [15, 22]]:
			p.px(c[0], c[1], "guard")
			p.px(c[0] + 1, c[1], "guard")
		_cache["box"] = ImageTexture.create_from_image(p.bake())
	return _cache["box"]


## A water puddle lying on a floor tile.
static func puddle(gravy := false) -> Texture2D:
	var key := "puddle_%s" % gravy
	if not _cache.has(key):
		var m := "gravy" if gravy else "puddle"
		var p := Painter.new(TILE, TILE)
		p.ell(15, 17, 12, 7, m)
		p.ell(24, 21, 5, 4, m)
		p.ell(8, 12, 4, 3, m)
		p.rect(10, 14, 13, 14, "apron" if gravy else "teeWhite")  # shine
		_cache[key] = ImageTexture.create_from_image(p.bake())
	return _cache[key]


# ---------------------------------------------------------------- tiles

## Floor tile. `alt` shifts the checker so tiles don't repeat identically.
## Styles: "lino" (classroom beige) or "cafeteria" (blue and white).
static func floor_tile(alt := false, style := "lino") -> Texture2D:
	var key := "floor_%s_%s" % [alt, style]
	if not _cache.has(key):
		var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
		var a := Color("d8cdb4")
		var b := Color("c9bc9f")
		if style == "cafeteria":
			a = Color("e9eef3")
			b = Color("b9cde6")
		elif style == "lab":
			a = Color("e3e6ea")
			b = Color("d3d8de")
		elif style == "gym":  # polished wooden gym floor
			a = Color("dcae6c")
			b = Color("cf9f5e")
		for y in TILE:
			for x in TILE:
				var col: Color
				if style == "grass":
					# mown stripes plus scattered blades (same pattern every time)
					col = Color("6fae4f") if (int(y / 16.0) + (1 if alt else 0)) % 2 == 0 else Color("64a246")
					var n := (x * 7 + y * 13 + (5 if alt else 0)) % 23
					if n == 0:
						col = Color("4f8a37")
					elif n == 11:
						col = Color("86c262")
				elif style == "carpet":
					# the Principal's office: dark red carpet with a small diamond pattern
					col = Color("7a3036") if (x + y + (4 if alt else 0)) % 8 != 0 and (x - y + 64) % 8 != 0 else Color("8d3c42")
				elif style == "sand":
					col = Color("e6cf8f") if (x * 5 + y * 11 + (3 if alt else 0)) % 17 != 0 else Color("c9ae68")
					if (x * 13 + y * 7) % 29 == 0:
						col = Color("f3e2b0")
				elif style == "space":
					# deep space with a scatter of stars (the same pattern every time)
					col = Color("0d0b1f")
					var n := (x * 17 + y * 31 + (11 if alt else 0)) % 97
					if n == 0:
						col = Color("ffffff")
					elif n == 40 or n == 71:
						col = Color("8b85c9")
					elif (x * 3 + y * 5 + (7 if alt else 0)) % 61 == 0:
						col = Color("f2c14e")
				elif style == "gym":
					# long planks, with a painted court line along one edge of every other tile
					col = a if (int(y / 8.0) + (1 if alt else 0)) % 2 == 0 else b
					if y % 8 == 0:
						col = col.darkened(0.12)
					if alt and x == 3:
						col = Color("e8eef2")
				elif style == "lab":
					var check := (int(x / 16.0) + int(y / 16.0) + (1 if alt else 0)) % 2 == 0
					col = a if check else b
					if x % 16 == 0 or y % 16 == 0:
						col = col.darkened(0.12)
				else:
					var check := (int(x / 8.0) + int(y / 8.0) + (1 if alt else 0)) % 2 == 0
					col = a if check else b
					if x == 0 or y == 0:
						col = col.darkened(0.08)
				img.set_pixel(x, y, col)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## Obstacle art. Size is 32x48 so tall things (lockers) can rise above their tile;
## the bottom 32 rows sit on the tile. `damaged` adds cracks. Lockers are only
## `tall` along the top wall; elsewhere they stay inside their tile so they
## don't hide the row above.
static func obstacle(kind: String, damaged := false, tall := true) -> Texture2D:
	var key := "obs_%s_%s_%s" % [kind, damaged, tall]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_obstacle_image(kind, damaged, tall))
	return _cache[key]


static func _obstacle_image(kind: String, damaged: bool, tall: bool) -> Image:
	var p := Painter.new(TILE, 48)
	var o := 16  # tile top inside the 48px image
	match kind:
		"X":  # an asteroid floating in space (the final boss)
			p.ell(16, o + 15, 13, 11, "steelDark")
			p.ell(14, o + 13, 10, 8, "steel")
			p.ell(10, o + 11, 3, 2.5, "steelDark")  # craters
			p.ell(20, o + 18, 3.5, 2.5, "steelDark")
			p.ell(19, o + 9, 2, 1.5, "steelDark")
			p.rect(8, o + 7, 10, o + 7, "teeWhite")  # shine
		"L":  # locker
			var top := 2 if tall else o + 1
			var k := 1.0 if tall else 0.6  # squash the details into a short locker
			p.rect(2, top, 29, o + 29, "locker")
			p.rect(15, top + 1, 16, o + 28, "seam")
			for i in 3:
				var y := top + roundi((6 + i * 3) * k)
				p.rect(5, y, 11, y, "seam")
				p.rect(20, y, 26, y, "seam")
			var hy := top + roundi(20 * k)
			p.rect(12, hy, 12, hy + 3, "handle")
			p.rect(19, hy, 19, hy + 3, "handle")
			if damaged:
				for c in [[7, 30], [8, 31], [8, 32], [9, 33], [23, 36], [24, 37], [24, 38]]:
					p.px(c[0], c[1], "crack")
		"D":  # desk
			p.rect(3, o + 6, 28, o + 14, "deskTop")
			p.rect(3, o + 15, 28, o + 18, "deskFront")
			p.rect(5, o + 19, 6, o + 28, "metal")
			p.rect(25, o + 19, 26, o + 28, "metal")
			p.rect(5, o + 24, 26, o + 24, "metal")
			if damaged:
				for c in [[10, o + 7], [11, o + 8], [11, o + 9], [12, o + 10], [20, o + 12], [21, o + 13]]:
					p.px(c[0], c[1], "crack")
		"T":  # teacher's desk
			p.rect(1, o + 3, 30, o + 11, "teacherTop")
			p.rect(1, o + 12, 30, o + 29, "teacherFront")
			p.rect(4, o + 16, 27, o + 16, "seam")
			p.rect(14, o + 14, 17, o + 14, "handle")
			if damaged:
				for c in [[8, o + 5], [9, o + 6], [9, o + 7], [10, o + 8], [22, o + 20], [23, o + 21], [23, o + 22]]:
					p.px(c[0], c[1], "crack")
		"B":  # gym bench
			p.rect(1, o + 12, 30, o + 17, "benchTop")
			p.rect(4, o + 18, 6, o + 27, "metal")
			p.rect(25, o + 18, 27, o + 27, "metal")
			if damaged:
				for c in [[12, o + 13], [13, o + 14], [13, o + 15], [14, o + 16]]:
					p.px(c[0], c[1], "crack")
		"F":  # lunch table: segments join up into long tables, with a bench in front
			p.rect(0, o + 6, 31, o + 14, "tableTop")
			p.rect(0, o + 15, 31, o + 17, "tableEdge")
			p.rect(14, o + 18, 17, o + 22, "steelDark")
			p.rect(0, o + 24, 31, o + 27, "benchBlue")
			p.rect(3, o + 28, 4, o + 30, "steelDark")
			p.rect(27, o + 28, 28, o + 30, "steelDark")
			if damaged:
				for c in [[8, o + 7], [9, o + 8], [9, o + 9], [10, o + 10], [22, o + 12], [23, o + 13]]:
					p.px(c[0], c[1], "crack")
		"K":  # food counter: steel front, food along the top
			var top := 2 if tall else o + 1
			p.rect(0, top + 6, 31, o + 29, "steel")
			p.rect(0, top + 6, 31, top + 8, "steelDark")
			p.rect(2, o + 18, 29, o + 18, "seam")
			p.ell(6, top + 4, 3, 3, "ballRed")
			p.ell(15.5, top + 4, 4, 2.5, "foodYellow")
			p.ell(25, top + 4, 3, 3, "foodGreen")
			if damaged:
				for c in [[9, o + 22], [10, o + 23], [10, o + 24], [11, o + 25], [21, o + 12], [22, o + 13]]:
					p.px(c[0], c[1], "crack")
		"N":  # chain-link fence
			var top := 2 if tall else o + 4
			p.rect(1, top, 2, o + 29, "fence")
			p.rect(29, top, 30, o + 29, "fence")
			p.rect(0, top, 31, top + 1, "fence")
			for y in range(top + 3, o + 28, 4):
				for x in range(3, 29, 4):
					p.px(x + ((y >> 2) % 2) * 2, y, "fence")
			p.rect(0, o + 28, 31, o + 29, "fence")
			if damaged:
				p.rect(12, o + 10, 18, o + 16, "")
		"R":  # tree: round crown, may poke a little above its tile
			p.rect(13, o + 18, 18, o + 29, "trunk")
			p.ell(15.5, o + 8, 13, 11, "leaf")
			p.ell(9, o + 13, 6, 5, "leaf")
			p.ell(22, o + 13, 6, 5, "leaf")
			if damaged:
				for c in [[14, o + 21], [15, o + 22], [15, o + 23], [16, o + 24]]:
					p.px(c[0], c[1], "crack")
		"Y":  # bike rack (a steel hoop) with a red bike in it, side view
			p.rect(3, o + 12, 28, o + 13, "metal")
			p.rect(3, o + 12, 4, o + 29, "metal")
			p.rect(27, o + 12, 28, o + 29, "metal")
			for wx in [9, 23]:
				p.ell(wx, o + 23, 6, 6, "shoeBlack")
				p.ell(wx, o + 23, 4.5, 4.5, "")
				p.px(wx, o + 23, "metal")
			for i in 8:  # frame: rear wheel -> pedals -> front wheel, and up to the seat
				p.px(9 + i, o + 23 - i / 2, "bikeRed")
				p.px(9 + i, o + 22 - i / 2, "bikeRed")
			p.rect(16, o + 18, 22, o + 19, "bikeRed")
			p.rect(21, o + 15, 22, o + 23, "bikeRed")
			p.rect(13, o + 16, 14, o + 20, "bikeRed")
			p.rect(11, o + 15, 15, o + 15, "pupil")  # seat
			p.rect(20, o + 14, 24, o + 14, "pupil")  # handlebar
			if damaged:
				p.rect(15, o + 18, 17, o + 19, "crack")
		"A":  # lab table: black top, white cupboards, a flask
			p.rect(1, o + 8, 30, o + 12, "labTop")
			p.rect(2, o + 13, 29, o + 29, "labCab")
			p.rect(15, o + 14, 16, o + 28, "seam")
			p.rect(12, o + 20, 12, o + 22, "handle")
			p.rect(19, o + 20, 19, o + 22, "handle")
			p.rect(7, o + 2, 8, o + 4, "glass")
			p.ell(7.5, o + 6, 3, 2.5, "flask")
			if damaged:
				for c in [[6, o + 15], [7, o + 16], [7, o + 17], [8, o + 18], [24, o + 22], [25, o + 23]]:
					p.px(c[0], c[1], "crack")
		"G":  # glass cabinet: breaks easily
			var top := 2 if tall else o + 2
			p.rect(3, top, 28, o + 29, "wood")
			p.rect(5, top + 2, 26, o + 27, "glass")
			p.rect(15, top + 2, 16, o + 27, "wood")
			var shelf := top + int((o + 27 - top) / 2.0)
			p.rect(5, shelf, 26, shelf, "wood")
			p.ell(9, shelf - 3, 2, 2.5, "flask")
			p.ell(21, shelf - 3, 2, 2.5, "ballRed")
			p.rect(9, o + 24, 12, o + 26, "bone")
			if damaged:
				for c in [[6, top + 4], [7, top + 5], [8, top + 6], [8, top + 7], [20, o + 20], [21, o + 19], [22, o + 18], [23, o + 18]]:
					p.px(c[0], c[1], "crack")
		"S":  # classroom skeleton on a stand
			p.ell(16, o + 1, 4, 4, "bone")
			p.px(14, o + 1, "pupil")
			p.px(17, o + 1, "pupil")
			p.rect(15, o + 5, 16, o + 18, "bone")
			for y in [8, 10, 12]:
				p.rect(11, o + y, 20, o + y, "bone")
			p.rect(9, o + 7, 10, o + 15, "bone")
			p.rect(21, o + 7, 22, o + 15, "bone")
			p.rect(13, o + 18, 14, o + 25, "bone")
			p.rect(17, o + 18, 18, o + 25, "bone")
			p.rect(15, o + 25, 16, o + 28, "metal")
			p.rect(10, o + 29, 21, o + 29, "metal")
			if damaged:
				p.rect(21, o + 7, 22, o + 15, "")
		"H":  # slide ladder with the platform on top
			p.rect(2, o - 6, 29, o - 3, "ballRed")
			p.rect(6, o - 2, 7, o + 29, "metal")
			p.rect(24, o - 2, 25, o + 29, "metal")
			for y in range(o + 2, o + 28, 5):
				p.rect(8, y, 23, y, "metal")
			if damaged:
				for c in [[10, o - 5], [11, o - 4], [20, o + 12], [21, o + 13]]:
					p.px(c[0], c[1], "crack")
		"Z", "W":  # the slide itself, going down to the right (Z) or left (W)
			for x in TILE:
				var sx := x if kind == "Z" else TILE - 1 - x
				var y := o - 4 + int(x * 24.0 / 31.0)
				p.rect(sx, y - 1, sx, y - 1, "ballRed")
				p.rect(sx, y, sx, y + 4, "slide")
			var leg := 25 if kind == "Z" else 5
			p.rect(leg, o + 19, leg + 1, o + 29, "metal")
			if damaged:
				for c in [[12, o + 6], [13, o + 7], [14, o + 8], [15, o + 8]]:
					var cx: int = c[0] if kind == "Z" else TILE - 1 - c[0]
					p.px(cx, c[1], "crack")
		"C":  # ball cart
			p.rect(3, o + 12, 28, o + 24, "metal")
			p.rect(5, o + 14, 26, o + 22, "")
			p.ell(10, o + 12, 5, 5, "ballRed")
			p.ell(21, o + 12, 5, 5, "ballBlue")
			p.ell(15.5, o + 7, 5, 5, "ballOrange")
			p.rect(5, o + 25, 7, o + 28, "metal")
			p.rect(24, o + 25, 26, o + 28, "metal")
			if damaged:
				p.rect(13, o + 16, 18, o + 18, "crack")
	return p.bake()
