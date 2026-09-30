# School Fighter — Game Plan

A turn-based, grid-based online fighting game inspired by the combat of
*South Park: The Fractured But Whole*. Up to 4 players join a lobby with a
short code and fight on pixel-art school maps.

> Status: **planning**. Nothing is built yet. Items marked **TBD** are decided
> later (mostly characters and numbers).

---

## 1. Decisions so far

| Topic | Decision |
|---|---|
| Players per lobby | 2–4. **2 = 1v1**, **3 = free-for-all (1v1v1)**, **4 = 2v2** |
| Joining | Host creates lobby → gets a short code → others type the code |
| Identity | Type a nickname, no accounts |
| Turn | **Move, then attack.** Move tile-by-tile up to your move range, then use 1 attack or the super (or skip). Attacking ends the turn |
| Moves | Each character has **4 attacks + 1 super** |
| Move range | **Per character** (default 3 tiles) |
| Super meter | Fills from damage. **Dealing damage gives more meter than taking it.** Super damage is **fixed** (not scaled by meter) |
| Grid | Bigger boards with obstacles. **Several maps, host picks** |
| Obstacles | Block movement, block attacks (cover), bonus damage when knocked into, **breakable** (have HP) |
| Turn order | Alternating. 2v2: A1 → B1 → A2 → B2. FFA: P1 → P2 → P3. Random starter |
| Friendly fire | Off. Area attacks skip teammates |
| Teams (2v2) | Host assigns |
| Rounds | Host picks 1–5 rounds |
| Turn timer | Host picks 15 / 30 / 45 / 60 s / off (default 30 s) |
| Disconnect | Match pauses, 60 s to rejoin, otherwise that player loses/is KO'd |
| Controls – PC | WASD move/aim, 1–4 attacks, Q super, Space confirm, Esc cancel |
| Controls – mobile | Virtual joystick (move/aim) + 5 on-screen buttons + confirm |
| Platforms | **Android first**, **website** too, iOS later (maybe PC) |
| Engine | **Godot 4** (GDScript). One project exports Android, Web, iOS, PC |
| Art | **Real pixel art, all made by Claude**. References can be anything: photos, sketches, screenshots or just a description |
| Characters | **4 at launch**, based on the owner and friends. **Unique picks** (no duplicates in a lobby). See section 2b |

---

## 2. Combat rules (v1 draft)

### Turn flow
1. **Start of turn**: status effects tick (if we add any), timer starts.
2. **Move phase**: step 1 tile per WASD press / joystick flick, up to
   `moveRange`. Can't walk through obstacles or players. Can undo steps
   until you attack or end the turn.
3. **Action phase**: pick attack 1–4 or super (if meter full), aim a
   direction (up/down/left/right), and the valid target tiles light up.
   Confirm to fire, or press "End turn" to skip.
4. **Resolve** (server): damage, knockback, obstacle damage, meter gain, KOs.
5. Next player. If the timer runs out, the turn ends where you stand
   with no attack.

### Attacks
Each attack is data, not code:
```
name, damage, shape (tile offsets relative to facing),
range, knockback (tiles), blockedByObstacles (bool),
effect (optional: heal, push, pull, stun… TBD)
```
Example shapes: melee (1 tile in front), line (up to 4 tiles, stops at first
obstacle/player), cone, cross around self, lob (ignores cover).

### Knockback
- Target slides N tiles away from the attacker.
- Hits an **obstacle or the map edge**: target takes **slam damage** (TBD, ~5)
  and the obstacle takes damage too.
- Hits **another player**: both take slam damage (never a teammate of the
  attacker, because friendly fire is off).

### Super meter
- Max 100. **Dealing** damage gives **1.0 meter per HP**, **taking** damage
  gives **0.5 meter per HP** (numbers can be tuned).
- Full meter → super is available. Using it resets the meter to 0.
- Super damage/shape is fixed per character.
- Meter resets every round.

### Rounds and winning
- A round ends when only one player (FFA) or one team (1v1/2v2) is left
  standing. In 2v2, KO'd players' turns are skipped.
- Host picks 1–5 rounds. The player/team with the most round wins takes
  the match. If an even round count ends tied, play one sudden-death round.
- HP, meter, positions and obstacles reset each round.

---

## 2b. Characters

4 characters at launch, each based on a real person (nicknames only).
A lobby holds max 4 players, so unique picks always work.

### Sebba (1/4): balanced brawler
- **Look**: light skin, short brown hair, glasses, gray t-shirt, black pants,
  black shoes. Short (about 140–160 cm), so he is drawn a bit shorter than the rest.
- **Stats**: HP 100, move 3.
- **Style**: up-close melee, plus a charge to close the gap.

| Slot | Attack | Shape | Effect |
|---|---|---|---|
| 1 | Punch | 1 tile in front | Solid damage |
| 2 | Kick | 1 tile in front | Low damage, big knockback |
| 3 | Sweep | All 8 tiles around self | Lower damage, hits everyone adjacent |
| 4 | Charge | Dash in a line, up to 4 tiles | Stops at first enemy, knockback; damage grows with distance run |
| Super | Mega Barrage | 1 adjacent enemy | Rapid flurry of punches, big fixed damage |

### William (2/4): wrestler bruiser
- **Look**: blond hair, glasses, light skin. Tallest of the three
  (about 150–168 cm). Mostly **black and red** clothes.
- **Stats**: HP 115, move 3.
- **Passive – Last Stand**: below 35% HP (40 HP or less), all his attacks do **+3 damage**.

| Slot | Attack | Shape | Effect |
|---|---|---|---|
| 1 | Shoulder Tackle | Rush up to 2 tiles in a line | Hits first enemy, knockback 1 |
| 2 | Punch | 1 tile in front | Solid damage |
| 3 | Rage | Self | For **1–2 of his turns (random)**: **+8 damage** on attacks and a **15 HP shield**. Both end together; the shield never heals real HP. Uses his action |
| 4 | Head Slam | 1 tile in front | Damage + **Dizzy** |
| Super | Body Smash | 1 adjacent enemy | Pro-wrestling body slam, big fixed damage. Rocks fly up around him (visual only) |

### Snorre (3/4): sugar-fuelled swordsman
- **Look**: brown hair, light skin, shortest of the three (about 140–155 cm).
  Carries a sword. **White t-shirt, gray pants**.
- **Stats**: HP 95, move 3.

| Slot | Attack | Shape | Effect |
|---|---|---|---|
| 1 | Stab | 1 tile in front | Solid damage |
| 2 | Block | Self | Shield that blocks **1 attack** completely. Gone at the start of his next turn if unused. Uses his action |
| 3 | Dual Spin | All 8 tiles around self | Lower damage, hits everyone adjacent |
| 4 | Sugar Rush | Self | **Free action** (he can still attack this turn). This turn his attacks do **1.3× damage**. On his **next turn he cannot attack** (he can still move) |
| Super | Mega Sword | Jumps, slams sword into the ground | Shockwave. **Inner ring** (tiles next to the impact): big damage. **Outer ring**: smaller damage + **Dizzy** |

### Mike (4/4): ranged thrower
- **Look**: short brown hair. Rest **TBD** (height, skin, clothes, glasses?).
- **Stats**: HP 85, move 3. Lowest HP, so rushing him down is the counter.
- **Style**: uses a mix of school stuff (slingshot, water gun, books). The only
  ranged character, so he gives the roster its long-range threat.

| Slot | Attack | Shape | Effect |
|---|---|---|---|
| 1 | Shove | 1 tile in front | Low damage, **knockback 2** (gets enemies off him) |
| 2 | Slingshot | Straight line, up to 5 tiles | Hits the first enemy. **Stopped by obstacles** |
| 3 | Water Gun | Line of 3 tiles | Low damage + **Dizzy**. Stopped by obstacles |
| 4 | Book Lob | Target tile 2–4 tiles away, plus-shape (5 tiles) | **Arcs over obstacles**. Medium damage |
| Super | Flying Tackle | Closest enemy in a straight line, **up to 3 tiles** | Leaps onto the enemy, tackles them to the ground and punches them: big fixed damage + **Dizzy**. Mike then **jumps back to where he started**. **Cost**: Mike loses **10 HP** (**15 HP** if he leaped over an obstacle) and becomes **Dizzy** himself. The self-damage can't KO him (minimum 1 HP) |

### Shared status effects
| Effect | Meaning |
|---|---|
| **Dizzy** | Move range −1 on the target's next turn |
| **Shield** | Absorbs damage before HP. Doesn't stack (a new shield replaces the old one) |

---

## 3. Lobby and online

### Lobby flow
```
Main menu → enter nickname
  ├─ Create lobby → code shown (e.g. K7QZP) → you are host
  └─ Join lobby  → type code → "Lobby full" / "Not found" / "Match in progress" errors
Lobby screen:
  - player list (2–4), character pick, Ready button
  - host settings: map, rounds (1–5), turn timer, teams (for 4 players)
  - host presses Start when everyone is ready (min 2 players)
```
- Codes: 5 chars from an unambiguous alphabet (no 0/O, 1/I/L).
- If the host leaves the lobby, host passes to the next player.
- Empty lobbies are deleted after 5 minutes.
- After the match: **Rematch** (same lobby) or **Leave**.

### Network model
- **Server-authoritative.** Clients only send *intents*
  (`move(x,y)`, `attack(slot, dir)`, `end_turn`). The server validates them,
  runs the rules, and broadcasts the result. Nobody can cheat damage.
- Turn-based, so lag isn't a problem.
- Transport: **WebSockets** (`WebSocketMultiplayerPeer`), because it works
  on Android, iOS, PC **and the web build**.
- Server: a **headless Godot** build of the same project, so the rules code
  is shared 100% between client and server. It runs many lobbies in one
  process.
- Hosting: Docker container on Fly.io / Render / Railway, with TLS (`wss://`),
  which the web version needs.
- Reconnect: the client keeps a session token. Reconnecting within 60 s puts
  you back in your slot.

---

## 4. Architecture

```
/game                     Godot 4 project
  /rules                  pure game logic, no nodes/graphics (shared by client + server)
    grid.gd               tiles, obstacles, pathing, line-of-sight
    attack_def.gd         attack data + shape resolution
    battle_state.gd       HP, positions, meter, turn order, rounds
    resolver.gd           apply intent -> list of events (damage, move, KO…)
  /data
    characters/*.tres     stats, 4 attacks, super
    maps/*.tres           size, spawn points, obstacles
  /net
    server.gd             lobbies, codes, validation, broadcasting
    client.gd             connect, send intents, receive events
  /scenes
    Menu, Lobby, Battle, Results
  /ui                     HUD, mobile joystick + buttons
  /art                    sprites, tilesets, fonts
/server                   Dockerfile + headless export config
/tests                    GUT unit tests for /rules
```
Rule: **everything in `/rules` is deterministic and testable** with no
rendering. The server feeds intents in, events come out, and clients just
animate the events.

---

## 5. Art spec (pixel art)

- Tile size **32×32**. Characters about **32×48** (can stand taller than a tile).
- Render at native resolution, scale up by whole numbers with nearest-neighbor
  filtering (no blurry pixels).
- Real pixel art: dark outlines, 3–4 shade steps per color, a small shared
  palette. No flat rectangles.
- Per character animations: idle (4f), walk (4f), attack ×4 (4–6f each),
  super (8f+), hurt (2f), KO (4f), victory (4f).
- Per map: floor tileset, walls, obstacles (desk, locker, table…) with
  intact/damaged/broken states.
- Workflow: you send references (photos, sketches, screenshots, or just a
  description) and Claude makes all the sprites. No pixel-art skills needed.

---

## 6. Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 | Project setup | Godot project, folder layout, test runner, README |
| M1 | Rules engine | Grid, move, 4 attacks, super, meter, knockback, obstacles, rounds. All unit-tested |
| M2 | Local battle | Playable hot-seat 1v1 on one device with placeholder sprites + one test map |
| M3 | Online 1v1 | Headless server, nicknames, create/join by code, synced battle |
| M4 | 3–4 players | FFA + 2v2, host settings (map/rounds/timer/teams), turn order |
| M5 | Robustness | Turn timer, reconnect, host migration, rematch, lobby cleanup |
| M6 | Content | Characters + maps from the design session (TBD) |
| M7 | Pixel art | Real sprites/tilesets from your references, animations, effects, sound |
| M8 | Ship | Android build (+ Play Store, $25 once), web build hosted, iOS later (needs a Mac + $99/yr) |

---

## 7. Still to decide (next sessions)

- **Characters**: Mike's super and full look.
- **Maps**: which ones (classroom, cafeteria, gym…?), sizes, obstacle layouts.
- **Numbers**: HP, damage, slam damage, obstacle HP, meter rates.
- **Status effects**: bleed/burn/stun/heal, or none?
- **Timing minigame** (press at the right moment for bonus damage): not
  decided yet.
- **Game name**, menu style, music/sound.
