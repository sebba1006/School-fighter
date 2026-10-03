extends RefCounted
## Map definitions (see PLAN.md section 2c).
## Legend: L locker, D desk, T teacher's desk, B bench, C ball cart,
## F lunch table, K food counter, N fence, R tree, Y bike rack, A lab table,
## G glass cabinet, S skeleton, H slide ladder, Z / W slide (going down to the
## right / left), s sandbox (floor you can stand in: hides you from throws and
## shots), 1 / 2 team spawns (left / right), . floor.
## `floor` picks the floor art (default: classroom lino).
## `ffa_spawns` are the corner spawns used in a free-for-all (3 or 4 players).

const OBSTACLE_HP := {"L": 20, "D": 20, "T": 40, "B": 30, "C": 15, "F": 25, "K": 50,
	"N": 60, "R": 45, "Y": 30, "A": 35, "G": 10, "S": 15,
	"H": 60, "Z": 60, "W": 60, "X": 80}

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
		"ffa_spawns": [[0, 1], [9, 1], [0, 5], [9, 5]],
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
		"ffa_spawns": [[0, 1], [13, 1], [0, 3], [13, 3]],
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
		"ffa_spawns": [[0, 1], [9, 1], [0, 6], [9, 6]],
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
		"ffa_spawns": [[0, 1], [11, 1], [0, 5], [11, 5]],
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
		"ffa_spawns": [[0, 1], [10, 1], [0, 6], [10, 6]],
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
		"ffa_spawns": [[0, 1], [9, 1], [0, 5], [9, 5]],
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
		"ffa_spawns": [[0, 1], [10, 1], [0, 6], [10, 6]],
	},
}


## The Principal's Office: the boss fight room. The boss (3x3) stands in the
## middle at `boss`; the three players start on the left ("1").
const BOSS_ROOM := {
	"name": "Principal's Office",
	"floor": "carpet",
	"boss": [5, 4],
	"rows": [
		"LLLLLLLLLLL",
		"1..........",
		".D.......D.",
		"1..........",
		"...........",
		"1..........",
		".D.......D.",
		"...........",
		"LLLLLLLLLLL",
	],
	"ffa_spawns": [[0, 1], [0, 3], [0, 5]],
}

## The Lunch Lady's kitchen (boss fights): counters along the top, stoves in
## the corners, the same size and spawns as the Principal's Office.
const KITCHEN := {
	"name": "The Kitchen",
	"floor": "cafeteria",
	"boss": [5, 4],
	"rows": [
		"KKKKKKKKKKK",
		"1..........",
		".F.......F.",
		"1..........",
		"...........",
		"1..........",
		".F.......F.",
		"...........",
		"KKKKKKKKKKK",
	],
	"ffa_spawns": [[0, 1], [0, 3], [0, 5]],
}

## The Gym Teacher's gym (boss fights): benches in the corners, the same size
## and spawns as the other boss rooms.
const BOSS_GYM := {
	"name": "The Gym",
	"floor": "gym",
	"boss": [5, 4],
	"rows": [
		"LLLLLLLLLLL",
		"1..........",
		".B.......B.",
		"1..........",
		"...........",
		"1..........",
		".B.......B.",
		"...........",
		"LLLLLLLLLLL",
	],
	"ffa_spawns": [[0, 1], [0, 3], [0, 5]],
}

## Where the final fight goes when the Principal gets furious: open space with
## a few asteroids (X). Fighters keep their places; an asteroid that would land
## on someone is left out.
const SPACE := {
	"name": "Space",
	"floor": "space",
	"boss": [5, 4],
	"rows": [
		"...........",
		"...........",
		"..X.....X..",
		"...........",
		"...........",
		"...........",
		"..X.....X..",
		"...........",
		"...........",
	],
	"ffa_spawns": [[0, 1], [0, 3], [0, 5]],
}

## Boss id -> its room.
const BOSS_ROOMS := {"principal": BOSS_ROOM, "lunch_lady": KITCHEN, "gym_teacher": BOSS_GYM, "final_principal": BOSS_ROOM}

