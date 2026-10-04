extends "res://tests/test_case.gd"

const Progress = preload("res://stats/progress.gd")
const PixelArt = preload("res://art/pixel_art.gd")


func test_level_curve() -> void:
	eq(Progress.level_info(0).level, 1, "start at level 1")
	eq(Progress.level_info(Progress.xp_to_next(1)).level, 2, "first level up")
	eq(Progress.level_info(Progress.total_for(100)).level, 100, "max level")
	eq(Progress.level_info(Progress.total_for(100) + 5000).level, 100, "never above 100")
	var matches := float(Progress.total_for(100)) / 115.0  # a typical match
	check(matches > 120 and matches < 160, "about 140 matches to level 100 (%d)" % matches)
	done()


func test_match_xp() -> void:
	var lose := Progress.xp_for_match(false, 0, 0, false)
	var win := Progress.xp_for_match(true, 200, 2, false)
	eq(lose, Progress.XP_BASE, "just playing gives XP")
	eq(win, Progress.XP_BASE + Progress.XP_WIN + 40 + 2 * Progress.XP_PER_KO, "winning, damage (max 40) and KOs add up")
	eq(Progress.xp_for_match(false, 800, 0, false), Progress.XP_BASE + Progress.XP_DAMAGE_MAX, "huge boss-fight damage is capped")
	check(Progress.xp_for_match(true, 5000, 9, true) <= Progress.XP_MAX_PER_MATCH, "capped")
	done()


func test_unlocks() -> void:
	eq(Progress.unlocks_at(25), ["SKIN: STYLE 2"], "first skin at 25")
	eq(Progress.unlocks_at(100), ["SKIN: GOLDEN", "NAME TAG: RAINBOW"], "level 100: gold skin and rainbow tag")
	eq(Progress.unlocks_at(5), ["NAME TAG: BLUE"], "first tag color at 5")
	done()


func test_every_skin_draws() -> void:
	for c in preload("res://rules/characters.gd").ALL:
		for s in 5:
			check(PixelArt.character(c, false, s) != null, "%s skin %d" % [c, s])
	done()
