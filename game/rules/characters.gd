extends RefCounted
## Character definitions: pure data shared by the client and the server.
## Numbers are the first-pass values from PLAN.md, to be tuned in playtests.
##
## Attack types (resolved in battle.gd):
##   melee       hits the tile in front
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
		"hp": 100,
		"move": 3,
		"attacks": [
			{"id": "punch", "name": "Punch", "type": "melee", "damage": 14},
			{"id": "kick", "name": "Kick", "type": "melee", "damage": 8, "knockback": 2},
			{"id": "sweep", "name": "Sweep", "type": "around", "damage": 8},
			{"id": "charge", "name": "Charge", "type": "dash", "range": 4, "damage": 8, "damage_per_tile": 3, "knockback": 1},
		],
		"super": {"id": "mega_barrage", "name": "Mega Barrage", "type": "melee", "damage": 35},
	},
	"william": {
		"name": "William",
		"hp": 115,
		"move": 3,
		"passive": "last_stand",
		"attacks": [
			{"id": "shoulder_tackle", "name": "Shoulder Tackle", "type": "dash", "range": 2, "damage": 12, "knockback": 1},
			{"id": "punch", "name": "Punch", "type": "melee", "damage": 14},
			{"id": "rage", "name": "Rage", "type": "self_rage", "bonus": 8, "shield": 15, "turns_min": 1, "turns_max": 2},
			{"id": "head_slam", "name": "Head Slam", "type": "melee", "damage": 10, "status": "dizzy"},
		],
		"super": {"id": "body_smash", "name": "Body Smash", "type": "melee", "damage": 35},
	},
	"snorre": {
		"name": "Snorre",
		"hp": 95,
		"move": 3,
		"attacks": [
			{"id": "stab", "name": "Stab", "type": "melee", "damage": 15},
			{"id": "block", "name": "Block", "type": "self_block"},
			{"id": "dual_spin", "name": "Dual Spin", "type": "around", "damage": 9},
			{"id": "sugar_rush", "name": "Sugar Rush", "type": "self_sugar", "multiplier": 1.3, "free": true},
		],
		"super": {"id": "mega_sword", "name": "Mega Sword", "type": "shockwave", "inner_damage": 30, "outer_damage": 12, "outer_status": "dizzy"},
	},
	"mike": {
		"name": "Mike",
		"hp": 85,
		"move": 3,
		"attacks": [
			{"id": "shove", "name": "Shove", "type": "melee", "damage": 5, "knockback": 2},
			{"id": "slingshot", "name": "Slingshot", "type": "projectile", "range": 5, "damage": 11},
			{"id": "water_gun", "name": "Water Gun", "type": "line", "range": 3, "damage": 6, "status": "dizzy"},
			{"id": "book_lob", "name": "Book Lob", "type": "lob", "min_range": 2, "max_range": 4, "damage": 9},
		],
		"super": {"id": "flying_tackle", "name": "Flying Tackle", "type": "leap", "range": 3, "damage": 45, "status": "dizzy", "self_damage": 10, "self_damage_over_obstacle": 15, "self_status": "dizzy"},
	},
}
