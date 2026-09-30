# School Fighter

A turn-based, grid-based online fighting game for 2–4 players, inspired by the
combat in *South Park: The Fractured But Whole*. Built with Godot 4.

See [PLAN.md](PLAN.md) for the full design: characters, maps, rules and milestones.

## Status

- **M0 Project setup:** done
- **M1 Rules engine:** done. All the fighting rules, with no graphics yet
- **M2 Local battle:** next

## Layout

```
game/                 Godot 4 project
  rules/              pure game logic, shared by client and server
    characters.gd     Sebba, William, Snorre, Mike: stats and attacks
    maps.gd           Classroom, Hallway, Gym
    fighter.gd        one fighter's state during a round
    battle.gd         the rules engine: intents in, events out
  tests/              unit tests for the rules
```

## Running the tests

Needs [Godot 4.5](https://godotengine.org/download) on your PATH as `godot`.

```
godot --headless --path game -s res://tests/run_tests.gd
```

It prints `N passed, 0 failed` and exits with code 1 if anything fails.
