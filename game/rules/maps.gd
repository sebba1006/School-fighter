extends RefCounted
## Map definitions (see PLAN.md section 2c).
## Legend: L locker, D desk, T teacher's desk, B bench, C ball cart,
## F lunch table, K food counter, N fence, R tree, Y bike rack, A lab table,
## G glass cabinet, S skeleton, H slide ladder, Z / W slide (going down to the
## right / left), s sandbox (floor you can stand in: hides you from throws and
## shots), 1 / 2 team spawns (left / right), . floor.
## `floor` picks the floor art (default: classroom lino).
## `ffa_spawns` are the three corner spawns used in a 3-player free-for-all.

const OBSTACLE_HP := {"L": 20, "D": 20, "T": 40, "B": 30, "C": 15, "F": 25, "K": 50,
	"N": 60, "R": 45, "Y": 30, "A": 35, "G": 10, "S": 15,
	"H": 60, "Z": 60, "W": 60}

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
	"cafeteria": {
		"name": "Cafeteria",
		"floor": "cafeteria",
		"rows": [
			"KKKKKKKKKKKK",
			"1..........2",
			"1.FFF..FFF.2",
			"............",
			"..FFF..FFF..",
			"............",
			"LLLLLLLLLLLL",
		],
		"ffa_spawns": [[0, 1], [11, 1], [0, 5]],
	},
	"schoolyard": {
		"name": "Schoolyard",
		"floor": "grass",
		"rows": [
			"NNNNNNNNNNN",
			"1.........2",
			"1.R.....R.2",
			"....B.B....",
			"...........",
			"..R.YYY.R..",
			"...........",
			"NNNNNNNNNNN",
		],
		"ffa_spawns": [[0, 1], [10, 1], [0, 6]],
	},
	"lab": {
		"name": "Science Lab",
		"floor": "lab",
		"rows": [
			"LLGGLLGGLL",
			"1........2",
			"1.AA..AA.2",
			"S...GG...S",
			"..AA..AA..",
			"..........",
			"LLLLLLLLLL",
		],
		"ffa_spawns": [[0, 1], [9, 1], [0, 5]],
	},
	"recess": {
		"name": "Recess",
		"floor": "grass",
		"rows": [
			"NNNNNNNNNNN",
			"1.........2",
			"1.HZ...WH.2",
			"....sss....",
			"....sss....",
			"..R.....R..",
			"...........",
			"NNNNNNNNNNN",
		],
		"ffa_spawns": [[0, 1], [10, 1], [0, 6]],
	},
}
