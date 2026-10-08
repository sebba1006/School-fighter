extends RefCounted
## Frozen copy of the fighters for the rules tests. The tests check how rules
## work (knockback, shields, Dizzy...) with these fixed numbers, so balance
## changes in rules/characters.gd don't break them. Don't tune numbers here.
##
## Attack types (resolved in battle.gd):
##   melee       hits the tile in front (fixed `damage`, or a random roll
##               between `damage_min` and `damage_max`)
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
		"hp": 100,
		"move": 3,
		"passive": "last_stand",
		"attacks": [
			{"id": "shoulder_tackle", "name": "Shoulder Tackle", "type": "dash", "range": 2, "damage": 10, "knockback": 1},
			{"id": "punch", "name": "Punch", "type": "melee", "damage": 12},
			{"id": "rage", "name": "Rage", "type": "self_rage", "bonus": 2, "shield": 0, "turns_min": 1, "turns_max": 2},
			{"id": "head_slam", "name": "Head Slam", "type": "melee", "damage": 9, "status": "dizzy"},
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
	"leon": {
		"name": "Leon",
		"hp": 95,
		"move": 3,
		"attacks": [
			{"id": "jab", "name": "Jab", "type": "melee", "damage": 13},
			{"id": "hook", "name": "Hook", "type": "melee", "damage": 10, "knockback": 1},
			{"id": "ball_throw", "name": "Ball Throw", "type": "projectile", "range": 4, "damage": 8},
			{"id": "eraser_flick", "name": "Eraser Flick", "type": "projectile", "range": 3, "damage": 6, "status": "dizzy"},
		],
		"super": {"id": "triple_uppercut", "name": "Triple Uppercut", "type": "melee", "damage_min": 30, "damage_max": 38},
	},
	"halvor": {
		"name": "Halvor",
		"hp": 90,
		"move": 3,
		"attacks": [
			{"id": "paper_plane", "name": "Paper Plane", "type": "projectile", "range": 6, "damage": 11},
			{"id": "snowball", "name": "Snowball", "type": "lob", "min_range": 2, "max_range": 5, "damage": 8},
			{"id": "spitball", "name": "Spitball", "type": "projectile", "range": 4, "damage": 6, "status": "dizzy"},
			{"id": "back_off", "name": "Back Off!", "type": "melee", "damage": 6, "knockback": 2},
		],
		"super": {"id": "bomba", "name": "Bomba", "type": "bomb", "min_range": 2, "max_range": 5, "center_damage": 30, "ring_damage": 13},
	},
	"seif": {
		"name": "Seif",
		"hp": 90,
		"move": 3,
		"attacks": [
			{"id": "pebble_shot", "name": "Pebble Shot", "type": "projectile", "range": 5, "damage": 10},
			{"id": "rubber_band", "name": "Rubber Band", "type": "projectile", "range": 3, "damage": 6, "status": "dizzy"},
			{"id": "pea_shooter", "name": "Pea Shooter", "type": "projectile", "range": 4, "damage": 3, "hits": 3},
			{"id": "ankle_kick", "name": "Ankle Kick", "type": "melee", "damage": 9, "knockback": 1},
		],
		"super": {"id": "mega_slingshot", "name": "Mega Slingshot", "type": "projectile", "range": 6, "damage_near": 30, "damage_far": 12},
	},
	"yacob": {
		"name": "Yacob",
		"hp": 100,
		"move": 3,
		"attacks": [
			{"id": "cracker", "name": "Cracker Snack", "type": "heal", "range": 4, "self_heal": 10, "heal_min": 10, "heal_max": 18, "cooldown": 1},
			{"id": "hoodie_punch", "name": "Punch", "type": "melee", "damage": 11},
			{"id": "crumb_spray", "name": "Crumb Spray", "type": "line", "range": 3, "damage": 6, "status": "dizzy"},
			{"id": "backpack_swing", "name": "Backpack Swing", "type": "around", "damage": 8},
		],
		"super": {"id": "heat_ray", "name": "Super Heat Ray", "type": "ray", "damage": 23, "status": "burn"},
	},
}
