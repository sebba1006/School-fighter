extends "res://tests/test_case.gd"

const Stats = preload("res://stats/stats.gd")


func test_online_and_local_results_add_up() -> void:
	var before_played: int = Stats.get_value("online", "played")
	var before_wins: int = Stats.get_value("online", "wins")
	var before_leon: int = Stats.get_value("online_fighters", "leon_wins")
	var before_dmg: int = Stats.get_value("online", "damage")
	Stats.record_online("leon", true, 40, 1, 1)
	Stats.record_online("leon", false, 10, 0, 0)
	eq(Stats.get_value("online", "played"), before_played + 2, "played")
	eq(Stats.get_value("online", "wins"), before_wins + 1, "wins")
	eq(Stats.get_value("online_fighters", "leon_wins"), before_leon + 1, "leon wins")
	eq(Stats.get_value("online", "damage"), before_dmg + 50, "damage")
	var local_before: int = Stats.get_value("local_fighters", "mike_wins")
	Stats.record_local(["mike", "snorre"], ["mike"])
	eq(Stats.get_value("local_fighters", "mike_wins"), local_before + 1, "local mike win")
	done()
