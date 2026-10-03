extends RefCounted
## Character definitions: pure data shared by the client and the server.
## Numbers are the first-pass values from PLAN.md, to be tuned in playtests.
##
## Attack types (resolved in battle.gd):
##   melee       hits the tile in front (fixed `damage`, or a random roll
##               between `damage_min` and `damage_max`; knockback can also be
##               random with `knockback_min` / `knockback_max`)
##   around      hits all 8 tiles around the user
##   dash        runs up to `range` tiles, then hits whatever is directly ahead
##   projectile  hits the first enemy or obstacle within `range` tiles
##   line        hits every enemy within `range` tiles, stopped by obstacles
##   lob         hits a plus shape `min_range`..`max_range` tiles away, over obstacles
##   shockwave   two rings around the tile in front (inner damage, outer damage + status)
##   leap        jumps on the closest enemy within `range` tiles and jumps back
##   self_rage / self_block / self_sugar   buffs on the user

const ALL := {
	"sebba": {
		"name": "Sebba",
		"hp": 95,
		"move": 3,
		"attacks": [
			{"id": "punch", "name": "Punch", "type": "melee", "damage": 13},
			{"id": "kick", "name": "Kick", "type": "melee", "damage": 8, "knockback": 1},
			{"id": "sweep", "name": "Sweep", "type": "around", "damage": 8},
			{"id": "charge", "name": "Charge", "type": "dash", "range": 3, "damage": 6, "damage_per_tile": 2, "knockback": 1},
		],
		"super": {"id": "mega_barrage", "name": "Mega Barrage", "type": "melee", "damage": 32},
	},
	"william": {
		"name": "William",
		"hp": 100,
		"move": 3,
		"passive": "last_stand",
		"attacks": [
			{"id": "shoulder_tackle", "name": "Shoulder Tackle", "type": "dash", "range": 2, "damage": 10, "knockback": 1},
			{"id": "punch", "name": "Punch", "type": "melee", "damage": 11},
			{"id": "rage", "name": "Rage", "type": "self_rage", "bonus": 2, "shield": 0, "turns_min": 1, "turns_max": 2},
			{"id": "head_slam", "name": "Head Slam", "type": "melee", "damage": 9, "status": "dizzy"},
		],
		"super": {"id": "body_smash", "name": "Body Smash", "type": "melee", "damage": 35},
	},
	"snorre": {
		"name": "Snorre",
		"hp": 105,
		"move": 3,
		"attacks": [
			{"id": "stab", "name": "Stab", "type": "melee", "damage": 15},
			{"id": "block", "name": "Block", "type": "self_block", "cooldown": 2},
			{"id": "dual_spin", "name": "Dual Spin", "type": "around", "damage": 12},
			{"id": "sugar_rush", "name": "Sugar Rush", "type": "self_sugar", "multiplier": 1.3, "free": true},
		],
		"super": {"id": "mega_sword", "name": "Mega Sword", "type": "shockwave", "inner_damage": 28, "outer_damage": 11, "outer_status": "dizzy"},
	},
	"mike": {
		"name": "Mike",
		"hp": 95,
		"move": 3,
		"attacks": [
			{"id": "shove", "name": "Shove", "type": "melee", "damage": 7, "knockback": 2},
			{"id": "slingshot", "name": "Slingshot", "type": "projectile", "range": 5, "damage": 11},
			{"id": "water_gun", "name": "Water Gun", "type": "line", "range": 3, "damage": 7, "status": "dizzy"},
			{"id": "book_lob", "name": "Book Lob", "type": "lob", "min_range": 2, "max_range": 4, "damage": 10},
		],
		"super": {"id": "flying_tackle", "name": "Flying Tackle", "type": "leap", "range": 3, "damage": 45, "status": "dizzy", "self_damage": 10, "self_damage_over_obstacle": 15, "self_status": "dizzy"},
	},
	"leon": {
		"name": "Leon",
		"hp": 95,
		"move": 3,
		"attacks": [
			{"id": "jab", "name": "Jab", "type": "melee", "damage": 13},
			{"id": "hook", "name": "Hook", "type": "melee", "damage": 10, "knockback": 1},
			{"id": "ball_throw", "name": "Ball Throw", "type": "projectile", "range": 4, "damage": 9},
			{"id": "eraser_flick", "name": "Eraser Flick", "type": "projectile", "range": 3, "damage": 6, "status": "dizzy"},
		],
		"super": {"id": "triple_uppercut", "name": "Triple Uppercut", "type": "melee", "damage_min": 30, "damage_max": 38},
	},
	"dogs": {
		"name": "Lucy & Charlie",
		"short": "Lucy+Charlie",
		"hp": 110,
		"move": 3,
		"attacks": [
			{"id": "bite", "name": "Bite", "type": "melee", "damage": 10},
			{"id": "pounce", "name": "Pounce", "type": "dash", "range": 2, "damage": 9, "knockback": 1},
			{"id": "zoomies", "name": "Zoomies", "type": "around", "damage": 8},
			{"id": "bark", "name": "Bark", "type": "line", "range": 2, "damage": 5, "status": "dizzy"},
		],
		"super": {"id": "mega_woof", "name": "Mega Woof", "type": "melee", "damage_min": 30, "damage_max": 40, "knockback_min": 1, "knockback_max": 2},
	},
}


## The boss (boss fights only, not pickable). He never moves; his attacks are
## run by the rules engine (see Battle._boss_act). The attack list is only text
## for the info screens.
const BOSS := {
	"name": "The Principal", "short": "Principal", "hp": 2250, "move": 0,
	"attacks": [
		{"id": "ruler_slam", "name": "Ruler Slam", "type": "boss"},
		{"id": "megaphone", "name": "Megaphone Yell", "type": "boss"},
		{"id": "detention", "name": "Detention!", "type": "boss"},
		{"id": "glare", "name": "Glare", "type": "boss"},
	],
	"super": {"id": "none", "name": "-", "type": "boss"},
}

## The teachers the Principal summons (boss fights only, played by the rules engine).
const TEACHER := {
	"name": "Teacher", "short": "Teacher", "hp": 40, "move": 3,
	"attacks": [
		{"id": "scold", "name": "Scold", "type": "boss"},
		{"id": "scold", "name": "Scold", "type": "boss"},
		{"id": "scold", "name": "Scold", "type": "boss"},
		{"id": "scold", "name": "Scold", "type": "boss"},
	],
	"super": {"id": "none", "name": "-", "type": "boss"},
}

## The Lunch Lady: the second boss (unlocked by beating the Principal). Same
## size and rules as him, her own attacks (see Battle._boss_act).
const LUNCH_LADY := {
	"name": "The Lunch Lady", "short": "Lunch Lady", "hp": 2250, "move": 0,
	"attacks": [
		{"id": "mystery_meat", "name": "Mystery Meat", "type": "boss"},
		{"id": "gravy", "name": "Gravy Splash", "type": "boss"},
		{"id": "tray", "name": "Tray Frisbee", "type": "boss"},
		{"id": "glare", "name": "Glare", "type": "boss"},
	],
	"super": {"id": "none", "name": "-", "type": "boss"},
}

## The cooks the Lunch Lady calls for help.
const COOK := {
	"name": "Cook", "short": "Cook", "hp": 40, "move": 3,
	"attacks": [
		{"id": "spatula", "name": "Spatula Slap", "type": "boss"},
		{"id": "spatula", "name": "Spatula Slap", "type": "boss"},
		{"id": "spatula", "name": "Spatula Slap", "type": "boss"},
		{"id": "spatula", "name": "Spatula Slap", "type": "boss"},
	],
	"super": {"id": "none", "name": "-", "type": "boss"},
}

## The Gym Teacher: the third boss (unlocked by beating the Lunch Lady).
const GYM_TEACHER := {
	"name": "The Gym Teacher", "short": "Gym Teacher", "hp": 2250, "move": 0,
	"attacks": [
		{"id": "push_ups", "name": "Push-Ups!", "type": "boss"},
		{"id": "medicine_ball", "name": "Medicine Ball", "type": "boss"},
		{"id": "whistle", "name": "Whistle!", "type": "boss"},
		{"id": "glare", "name": "Glare", "type": "boss"},
	],
	"super": {"id": "none", "name": "-", "type": "boss"},
}

## The athletes the Gym Teacher calls in.
const ATHLETE := {
	"name": "Athlete", "short": "Athlete", "hp": 40, "move": 3,
	"attacks": [
		{"id": "tackle", "name": "Tackle", "type": "boss"},
		{"id": "tackle", "name": "Tackle", "type": "boss"},
		{"id": "tackle", "name": "Tackle", "type": "boss"},
		{"id": "tackle", "name": "Tackle", "type": "boss"},
	],
	"super": {"id": "none", "name": "-", "type": "boss"},
}

## The final boss: the Principal again (unlocked by beating the Gym Teacher).
## A normal Principal fight until he has lost FINAL_SPACE_AT HP, then he gets
## furious, the fight moves to space, and he uses his space attacks.
const FINAL_PRINCIPAL := {
	"name": "The Principal", "short": "Final Boss", "hp": 2500, "move": 0,
	"attacks": [
		{"id": "gravity_slam", "name": "Gravity Slam", "type": "boss"},
		{"id": "laser_eyes", "name": "Laser Eyes", "type": "boss"},
		{"id": "meteor", "name": "Meteor Shower", "type": "boss"},
		{"id": "black_hole", "name": "Black Hole", "type": "boss"},
	],
	"super": {"id": "none", "name": "-", "type": "boss"},
}

## Every boss, in unlock order: the rules for each one's turn live in
## Battle._boss_act; here are its fighter, room, helpers and attack names.
const BOSSES := {
	"principal": {"def": BOSS, "minion": "teacher", "minion_def": TEACHER,
		"ring": "ruler_slam", "lane": "megaphone", "far": "detention",
		"summon": "TEACHERS, HELP ME!", "summon_banner": "TEACHERS INCOMING!", "minion_attack": "scold"},
	"lunch_lady": {"def": LUNCH_LADY, "minion": "cook", "minion_def": COOK,
		"ring": "mystery_meat", "lane": "gravy", "far": "tray",
		"summon": "KITCHEN, HELP ME!", "summon_banner": "COOKS INCOMING!", "minion_attack": "spatula"},
	"gym_teacher": {"def": GYM_TEACHER, "minion": "athlete", "minion_def": ATHLETE,
		"ring": "push_ups", "lane": "medicine_ball", "far": "whistle",
		"summon": "TEAM, HUDDLE UP!", "summon_banner": "ATHLETES INCOMING!", "minion_attack": "tackle"},
	"final_principal": {"def": FINAL_PRINCIPAL, "minion": "teacher", "minion_def": TEACHER,
		"ring": "ruler_slam", "lane": "megaphone", "far": "detention",
		"summon": "TEACHERS, HELP ME!", "summon_banner": "TEACHERS INCOMING!", "minion_attack": "scold",
		# in space
		"space_ring": "gravity_slam", "space_lane": "laser_eyes", "space_far": "meteor", "space_far2": "black_hole"},
}
