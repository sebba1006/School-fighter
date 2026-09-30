extends RefCounted
## Map definitions (see PLAN.md section 2c).
## Legend: L locker, D desk, T teacher's desk, B bench, C ball cart,
## 1 / 2 team spawns (left / right), . floor.
## `ffa_spawns` are the three corner spawns used in a 3-player free-for-all.

const OBSTACLE_HP := {"L": 60, "D": 20, "T": 40, "B": 30, "C": 15}

const ALL := {
	"classroom": {
		"name": "Classroom",
		"rows": [
			"LLLLLLLLLL",
			"1........2",
			"1.D.DD.D.2",
			"....TT....",
			"..D.DD.D..",
			"..........",
			"LLLLLLLLLL",
		],
		"ffa_spawns": [[0, 1], [9, 1], [0, 5]],
	},
	"hallway": {
		"name": "Hallway",
		"rows": [
			"LLLLLLLLLLLLLL",
			"1....D..D....2",
			"1..D......D..2",
			".....D..D.....",
			"LLLLLLLLLLLLLL",
		],
		"ffa_spawns": [[0, 1], [13, 1], [0, 3]],
	},
	"gym": {
		"name": "Gym",
		"rows": [
			"LLLLLLLLLL",
			"1........2",
			"1........2",
			"...B..B...",
			"....CC....",
			"...B..B...",
			"..........",
			"LLLLLLLLLL",
		],
		"ffa_spawns": [[0, 1], [9, 1], [0, 6]],
	},
}
