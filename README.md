# School Fighter

A turn-based, grid-based online fighting game for 2–4 players, inspired by the
combat in *South Park: The Fractured But Whole*. Built with Godot 4.

See [PLAN.md](PLAN.md) for the full design: characters, maps, rules and milestones.

## Status

- **M0 Project setup:** done
- **M1 Rules engine:** done. All the fighting rules, with no graphics yet
- **M2 Local battle:** done. Two players on one device, touch or keyboard
- **VS CPU:** done. 1v1, 1v1v1 or 2v2 (with a CPU teammate) against the
  computer player (`ai/bot.gd`), with EASY / NORMAL / HARD
- **Boss fight:** team up against THE PRINCIPAL (2250 HP, 3x3, summons teachers), then unlock THE LUNCH LADY, THE GYM TEACHER and the final battle in SPACE and win trophies
- **Achievements:** 20 to unlock, with an ACHIEVEMENTS screen
- **Shrinking map:** optional detention zone that closes in from the edges
- **Victory screen:** MVP (most damage) and most KOs
- **Open lobbies:** lobbies are public by default and show up in a list on
  the join screen (just the code and player count); the host can make the
  lobby private (code only) and kick players
- **Items:** broken lockers can drop a book, pencils or a water bottle
  (puddle trap), and a mystery box drops a Melee Guard or Ranged Guard.
  ITEMS ON/OFF setting
- **M3–M5 Online:** done. Lobbies with codes, 2–4 players (1v1, free-for-all,
  2v2), host settings, turn timer, reconnecting, back to lobby
- **M6+ Content and polish:** next

## Layout

```
game/                 Godot 4 project (open game/project.godot)
  main.gd             entry point, keyboard controls
  screens/            setup screen, battle screen, fighter sprites
  ui/                 theme and on-screen joystick
  art/pixel_art.gd    all pixel art, drawn from code
  fonts/              Silkscreen pixel font (SIL Open Font License)
  tools/              dev tools (screenshots)
  net/                online play
    server.gd         WebSocket server: players, lobby codes
    lobby.gd          one lobby: members, settings, the match (server is the referee)
    client.gd         the game's connection, reconnects by itself
    wire.gd           JSON messages
    config.gd         default server address
  rules/              pure game logic, shared by client and server
    characters.gd     Sebba, William, Snorre, Mike: stats and attacks
    maps.gd           Classroom, Hallway, Gym
    fighter.gd        one fighter's state during a round
    battle.gd         the rules engine: intents in, events out
  tests/              unit tests for the rules
```

## Playing

**In the browser:** https://sebba1006.github.io/School-fighter/ (local battles:
two players take turns on the same device; turn phones sideways). It updates by
itself every time `main` changes.

**In Godot:** open `game/project.godot` in Godot 4.5 (desktop or the Android editor app) and
press Play.

| | PC | Touch |
|---|---|---|
| Move / aim | WASD or arrows | joystick, or tap a blue tile to walk there |
| Pick attack | 1 2 3 4, Q for super | attack cards on the right (damage shown) |
| Use attack | Space, or the same key again | USE, the same card again, or tap the aimed tile twice |
| Undo a step / back | Z | UNDO / BACK |
| End turn | E | END TURN |

Book Lob: push the same direction again to throw further.

Also in the game: **HOW TO PLAY** on the menu (rules and every fighter's
moves), fighter info on the character select screens, a **LEAVE** button
during a match (online this counts as forfeiting), and a **SOUND** on/off
button, **STATS** (your online record, damage, KOs, supers and wins per
fighter, saved on the device) and **CHAT** emotes during online matches
(GG, NICE!, HAHA, OOPS, NOOO, GOOD LUCK). All sounds and the chiptune music are generated in code
(`game/audio/audio.gd`), no audio files.

## Online play

The browser version and the apps connect to the online server
(`net/config.gd` has the default address; it can be changed on the online
screen). One player creates a lobby and shares the 5-letter code; up to 4 can
join. 2 players = 1v1, 3 = free-for-all, 4 = 2v2 (the host sets teams).

The server is this same Godot project run headless:

```
PORT=9080 godot --headless --path game -- --server
```

It is deployed on [Render](https://render.com) from `render.yaml` +
`server/Dockerfile` (free plan: it sleeps after 15 minutes without players and
takes up to a minute to wake up).

How it stays fair: the server keeps its own copy of every battle and checks
each move. Accepted moves are sent to every player, whose game applies the
same move to its own copy. The rules are deterministic, so all copies stay
identical, and each move carries a fingerprint of the battle so a game that
ever drifts asks the server for a fresh copy.

## Balance check

A computer player (`game/ai/bot.gd`) can play every matchup on every map
and print win rates:

```
godot --headless --path game -s res://tools/balance_sim.gd -- 30
```

## Running the tests

Needs [Godot 4.5](https://godotengine.org/download) on your PATH as `godot`.

```
godot --headless --path game -s res://tests/run_tests.gd
```

It prints `N passed, 0 failed` and exits with code 1 if anything fails.

Online end-to-end test (a real server plus 2, 3 or 4 bot players over
WebSockets, including a dropped connection that has to rejoin):

```
godot --headless --path game -s res://tools/net_smoke.gd -- 4
```
