# School Fighter

A turn-based, grid-based online fighting game for 2–4 players, inspired by the
combat in *South Park: The Fractured But Whole*. Built with Godot 4.

See [PLAN.md](PLAN.md) for the full design: characters, maps, rules and milestones.

## Status

- **M0 Project setup:** done
- **M1 Rules engine:** done. All the fighting rules, with no graphics yet
- **M2 Local battle:** done. Two players on one device, touch or keyboard
- **M3 Online 1v1:** next

## Layout

```
game/                 Godot 4 project (open game/project.godot)
  main.gd             entry point, keyboard controls
  screens/            setup screen, battle screen, fighter sprites
  ui/                 theme and on-screen joystick
  art/pixel_art.gd    all pixel art, drawn from code
  fonts/              Silkscreen + Pixelify Sans (SIL Open Font License)
  tools/              dev tools (screenshots)
  rules/              pure game logic, shared by client and server
    characters.gd     Sebba, William, Snorre, Mike: stats and attacks
    maps.gd           Classroom, Hallway, Gym
    fighter.gd        one fighter's state during a round
    battle.gd         the rules engine: intents in, events out
  tests/              unit tests for the rules
```

## Playing

Open `game/project.godot` in Godot 4.5 (desktop or the Android editor app) and
press Play.

| | PC | Touch |
|---|---|---|
| Move / aim | WASD or arrows | joystick |
| Pick attack | 1 2 3 4, Q for super | attack buttons |
| Use attack | Space, or the same key again | USE, or the same button again |
| Undo a step / back | Z | UNDO / BACK |
| End turn | E | END TURN |

Book Lob: push the same direction again to throw further.

## Running the tests

Needs [Godot 4.5](https://godotengine.org/download) on your PATH as `godot`.

```
godot --headless --path game -s res://tests/run_tests.gd
```

It prints `N passed, 0 failed` and exits with code 1 if anything fails.
