extends "res://tests/test_case.gd"


func _boss_battle(chars := ["sebba", "mike", "leon"]) -> Battle:
	var players := []
	for c in chars:
		players.append({"char": c, "team": 0})
	var b := Battle.new({"boss": true, "players": players, "seed": 3, "characters": Fixture.ALL})
	b.start_round()
	return b


func test_boss_setup() -> void:
	var b := _boss_battle()
	var boss := b.boss()
	check(boss != null and boss.is_boss, "the Principal is there")
	eq(boss.id, 3, "added after the players")
	eq(boss.max_hp, 2000, "2000 HP")
	eq(b.fighters[0].max_hp, Fixture.ALL.sebba.hp + Battle.BOSS_PLAYER_HP, "+250 HP for players")
	eq(b.teams, [0, 1] as Array[int], "players vs boss")
	eq(b.current().id, 0, "players go first")
	eq(b._fighter_at(boss.pos + Vector2i(1, 1)), boss, "he covers 3x3 tiles")
	check(not b._walkable(boss.pos + Vector2i(-1, 0)), "can't walk through him")
	done()


func test_turn_order_players_then_boss() -> void:
	var b := _boss_battle()
	var seen: Array[int] = []
	for i in 6:
		seen.append(b.current().id)
		var r := end_turn(b, b.current().id)
		if r.events.any(func(e): return e.type == "boss_attack"):
			seen.append(3)
	eq(seen.slice(0, 7), [0, 1, 2, 3, 0, 1, 2] as Array[int], "A B C, boss, A B C")
	done()


func test_attacks_hit_the_boss_once() -> void:
	var b := _boss_battle(["snorre", "mike", "leon"])
	var boss := b.boss()
	put(b, 0, boss.pos.x - 2, boss.pos.y)  # right next to his left side
	var before := boss.hp
	attack(b, 0, 2, R)  # Dual Spin covers 3 of his tiles
	eq(before - boss.hp, Fixture.ALL.snorre.attacks[2].damage * Battle.BOSS_HIT_MULTIPLIER, "hit once (double damage), not three times")
	done()


func test_boss_cannot_be_pushed() -> void:
	var b := _boss_battle()
	var boss := b.boss()
	var at := boss.pos
	put(b, 0, boss.pos.x - 2, boss.pos.y)
	attack(b, 0, 1, R)  # Kick: push 1
	eq(boss.pos, at, "didn't move")
	done()


func test_ruler_slam_hits_and_pushes_neighbours() -> void:
	var b := _boss_battle()
	var boss := b.boss()
	put(b, 0, boss.pos.x - 2, boss.pos.y)
	b.forced_rolls.assign([1])  # choose Ruler Slam
	end_turn(b, 0)
	end_turn(b, 1)
	var hp_before := b.fighters[0].hp
	var r := end_turn(b, 2)  # boss acts
	check(r.events.any(func(e): return e.type == "boss_attack" and e.attack == "ruler_slam"), "ruler slam")
	eq(hp_before - b.fighters[0].hp, Battle.RULER_DAMAGE, "ruler damage")
	eq(b.fighters[0].pos, Vector2i(boss.pos.x - 3, boss.pos.y), "pushed back 1")
	eq(b.current().id, 0, "back to the players")
	done()


func test_detention_hits_someone_far_away() -> void:
	var b := _boss_battle()
	for f in b.fighters:
		if not f.is_boss:
			put(b, f.id, 0, f.id * 2 + 1)
	# nobody next to him; spawns at x=0 rows 1/3/5: row 3 and 5 are in line, so force the roll
	b.forced_rolls.assign([100, 0])  # skip megaphone (roll 100 > 60), detention on player 0
	end_turn(b, 0)
	end_turn(b, 1)
	var before := b.fighters[0].hp
	var r := end_turn(b, 2)
	check(r.events.any(func(e): return e.type == "boss_attack" and e.attack == "detention"), "detention")
	eq(before - b.fighters[0].hp, Battle.DETENTION_DAMAGE, "detention damage")
	check(b.fighters[0].dizzy_now, "dizzy on their next turn")
	done()


func test_apples_drop_and_heal() -> void:
	var b := _boss_battle()
	var boss := b.boss()
	var ctx := {"attacker": b.fighters[0], "dir": Vector2i.ZERO, "super": false, "events": []}
	b._deal(b.fighters[0], boss, (Battle.APPLE_EVERY * 2 + 5) / Battle.BOSS_HIT_MULTIPLIER + 1, ctx)
	eq(b.apples.size(), 2, "two apples for 500+ damage")
	var apple: Vector2i = b.apples.keys()[0]
	var f := b.current()
	f.hp = 100
	f.pos = apple + Vector2i(-1, 0) if b._walkable(apple + Vector2i(-1, 0)) else apple + Vector2i(1, 0)
	b.turn_start_pos = f.pos
	var r := step(b, f.id, apple - f.pos)
	check(has_event(r, "heal"), "healed")
	eq(f.hp, 100 + Battle.APPLE_HEAL, "apple heal")
	check(not b.apples.has(apple), "apple eaten")
	done()


func test_beating_the_boss_wins() -> void:
	var b := _boss_battle()
	var boss := b.boss()
	boss.hp = 5
	put(b, 0, boss.pos.x - 2, boss.pos.y)
	attack(b, 0, 0, R)
	eq(b.phase, Battle.Phase.MATCH_OVER, "over")
	eq(b.match_winner, 0, "the players win")
	done()


func test_boss_wins_if_everyone_is_down() -> void:
	var b := _boss_battle()
	for f in b.fighters:
		if not f.is_boss:
			f.hp = 1
			put(b, f.id, b.boss().pos.x - 2, b.boss().pos.y - 1 + f.id)
	b.forced_rolls.assign([1])  # ruler slam
	end_turn(b, 0)
	end_turn(b, 1)
	end_turn(b, 2)
	eq(b.match_winner, Battle.BOSS_TEAM, "the Principal wins")
	done()
