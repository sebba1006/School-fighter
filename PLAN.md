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
| Turn order | Alternating teams, always. 2v2: red → blue → red → blue; inside a team the players take turns, also after a KO (A1 → B1 → A1 → B2 if A2 is out). FFA: P1 → P2 → P3. Round 1 starts with a random team; later rounds start with the team that did not act last |
| Friendly fire | Off. Area attacks skip teammates |
| Teams (2v2) | Host assigns |
| Rounds | Host picks 1–5 rounds |
| Turn timer | Host picks 15 / 30 / 45 / 60 s / off (default 30 s) |
| Disconnect | Match pauses, 60 s to rejoin, otherwise that player loses/is KO'd |
| Controls – PC | WASD move/aim, 1–4 attacks, Q super, Space confirm, Esc cancel |
| Controls – mobile | Big joystick bottom-left; right column with attack cards (name + damage), UNDO, END TURN, USE. Reachable tiles are blue: tap one to walk there. Tap a tile to aim, tap it again to attack |
| Platforms | **Android first**, **website** too, iOS later (maybe PC) |
| Engine | **Godot 4** (GDScript). One project exports Android, Web, iOS, PC |
| Art | **Real pixel art, all made by Claude**. References can be anything: photos, sketches, screenshots or just a description |
| Characters | **5**, based on the owner and friends. **Unique picks** (no duplicates in a lobby). See section 2b |

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
- Max 100. **Dealing** damage gives **2 meter per HP**, **taking** damage
  gives **1 meter per HP**. That works out to about 4–5 solid hits per super,
  so roughly 1–2 supers per round (numbers can be tuned).
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
- **Stats**: HP 100, move 3. *(Nerfed after playtesting: was 115.)*
- **Passive – Last Stand**: below 35% HP (34 HP or less), all his attacks do **+3 damage**.

| Slot | Attack | Shape | Effect |
|---|---|---|---|
| 1 | Shoulder Tackle | Rush up to 2 tiles in a line | Hits first enemy, knockback 1 |
| 2 | Punch | 1 tile in front | Solid damage |
| 3 | Rage | Self | For **1–2 of his turns (random)**: **+2 damage** on attacks. No shield. Uses his action *(nerfed: was +8 and a 15 HP shield)* |
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
- **Look**: short brown hair, **black hoodie, black pants**. Carries a slingshot. Light skin, medium height (between Sebba and William).
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

### Leon (5/6): half close range, half (weaker) long range
- **Look**: light brown hair, light skin, blue t-shirt, light gray pants
  (black shoes are a guess).
- **Stats**: HP 95, move 3.

| Slot | Attack | Shape | Effect |
|---|---|---|---|
| 1 | Jab | 1 tile in front | 13 damage |
| 2 | Hook | 1 tile in front | 10 damage, knockback 1 |
| 3 | Ball Throw | First enemy within 4 tiles | 8 damage (weaker and shorter than Mike's Slingshot) |
| 4 | Eraser Flick | First enemy within 3 tiles | 6 damage + Dizzy |
| Super | Triple Uppercut | 1 adjacent enemy | **30–38 damage** (random roll) |

### Lucy & Charlie (6/6): the dog duo
- **Look**: two beagles. Charlie is the big, older one (grey muzzle), and
  Lucy, the puppy, lies on top of him.
- **Stats**: HP 110, move 3. Their attacks are a bit weaker than the others'.

| Slot | Attack | Shape | Effect |
|---|---|---|---|
| 1 | Bite | 1 tile in front | 11 damage |
| 2 | Pounce | Dash up to 2 tiles | 9 damage, knockback 1 |
| 3 | Zoomies | All 8 tiles around | 7 damage |
| 4 | Bark | Line of 2 tiles | 5 damage + Dizzy |
| Super | Mega Woof | 1 adjacent enemy | A big WOOF: **30–40 damage** and **pushed 1 or 2 tiles** (both random) |

### Shared status effects
| Effect | Meaning |
|---|---|
| **Dizzy** | Move range −1 on the target's next turn |
| **Shield** | Absorbs damage before HP. Doesn't stack (a new shield replaces the old one) |

### First-pass numbers (to tune in playtests)
Slam damage (knocked into an obstacle, wall or player): **5**.

| Character | 1 | 2 | 3 | 4 | Super |
|---|---|---|---|---|---|
| Sebba | Punch 14 | Kick 8, knockback 2 | Sweep 8 | Charge 8 + 3 per tile run (max 20), knockback 1 | Mega Barrage 35 |
| William | Tackle 10, knockback 1 | Punch 12 | Rage (+2 dmg) | Head Slam 9 + Dizzy | Body Smash 35 |
| Snorre | Stab 15 | Block | Dual Spin 9 | Sugar Rush (1.3×) | Mega Sword: inner 30, outer 12 + Dizzy |
| Mike | Shove 5, knockback 2 | Slingshot 11 | Water Gun 6 + Dizzy | Book Lob 9 | Flying Tackle 45 + Dizzy (self: −10/−15 HP, Dizzy) |

### Balance pass (computer simulation)
`tools/balance_sim.gd` lets a computer player (`ai/bot.gd`) fight every
matchup on every map (1200 matches). Before tuning, Sebba won 99% (walk
away, then a long-run-up Charge) and Snorre/Mike were around 20%. After:

| Fighter | Overall win rate | Changes |
|---|---|---|
| Sebba | 55% | HP 95, Kick push 1, Charge 7 + 2/tile up to 3 tiles (max 13), Mega Barrage 32 |
| William | 42% | (nerfed earlier: HP 100, Rage +2, Tackle 10, Punch 12, Head Slam 9) |
| Snorre | 50% | HP 100, Stab 16, Dual Spin 10, Mega Sword 28 / 11 |
| Mike | 49% | HP 95, Shove 7, Slingshot 12, Water Gun 7, Book Lob 10 |
| Leon | 54% | Jab 14, Ball Throw 9 |
| Lucy & Charlie | 52% | Added later at these numbers, no changes needed (6-fighter run: Sebba 58, William 44, Snorre 51, Mike 42, Leon 53) |

Known lopsided matchup: Mike beats Snorre almost every time in the
simulation (Snorre can't close the distance). Watch for it in real games.

### Balance pass 2 (after playtests)
Playtesters found Leon's Jab (14) and Lucy & Charlie's Bite (11) too strong.
The simulation was made fairer first: best-of-3, a mix of HP settings
(original / +50 / +100) and a little randomness, because with short fights
"how many hits to KO" decided whole matchups (one damage point could flip a
matchup from 10% to 90%). With all 7 maps (2100 matches):

| Fighter | Before | After | Changes |
|---|---|---|---|
| Sebba | 61% | 44% | Punch 14 → 13, Charge 7 → 6 (+2 per tile) |
| William | 43% | 57% | Punch 12 → 11 (stronger mostly because others got nerfed) |
| Snorre | 58% | 54% | HP 100 → 105, Dual Spin 10 → 12 |
| Mike | 35% | 43% | Slingshot 12 → 11 |
| Leon | 62% | 54% | Jab 14 → 13 |
| Lucy & Charlie | 40% | 48% | Bite 11 → 10, Zoomies 7 → 8 |

No more lopsided matchups: Mike vs Snorre went from 98% to 49%.

**Snorre nerf (playtest):** he still won too often in real games. Stab 16 → 15
(about 20 with Sugar Rush instead of 21) and **Block now has a cooldown**: after
using it he can't Block on his next 2 turns (the card shows "READY IN 2 TURNS").
Any attack can get a `cooldown`. Sim: Snorre 52% → 47%. The most
one-sided pair now is Lucy & Charlie vs Mike (76%).

---

## 2c. Maps

7 maps. The host picks one in the lobby. Every map follows the same rule:
**lockers along the sides, desks (or other cover) in the middle**.

- Spawns: **opposite ends**. 1v1 and 2v2 use the left edge vs. the right edge.
  FFA uses 3 corners.
- Everything is breakable, but lockers are very tough.

| Obstacle | HP | Notes |
|---|---|---|
| Desk | 20 | Main cover in the middle |
| Teacher's desk | 40 | Classroom only |
| Bench | 30 | Gym only |
| Ball cart | 15 | Gym only |
| Locker | 20 | Side walls (was 60; lowered so items drop more often) |

Legend: `L` locker, `D` desk, `T` teacher's desk, `B` bench, `C` ball cart,
`1`/`2` team spawns, `.` floor. All layouts are mirrored left↔right so neither side has an advantage. They're first drafts to be tuned in playtests.

### Classroom (10×7)
```
L L L L L L L L L L
1 . . . . . . . . 2
1 . D . D D . D . 2
. . . . T T . . . .
. . D . D D . D . .
. . . . . . . . . .
L L L L L L L L L L
```

### Hallway (14×5): long and narrow, great for Mike's line attacks
```
L L L L L L L L L L L L L L
1 . . . . D . . D . . . . 2
1 . . D . . . . . . D . . 2
. . . . . D . . D . . . . .
L L L L L L L L L L L L L L
```

### Gym (10×8): open floor, brawler-friendly
```
L L L L L L L L L L
1 . . . . . . . . 2
1 . . . . . . . . 2
. . . B . . B . . .
. . . . C C . . . .
. . . B . . B . . .
. . . . . . . . . .
L L L L L L L L L L
```

### Cafeteria (12×7): long lunch tables, food counter along the top wall
```
K K K K K K K K K K K K
1 . . . . . . . . . . 2
1 . F F F . . F F F . 2
. . . . . . . . . . . .
. . F F F . . F F F . .
. . . . . . . . . . . .
L L L L L L L L L L L L
```
`F` lunch table (25 HP), `K` food counter (50 HP). Blue and white tiled floor.

### Schoolyard (11×8): outside, big and open, good for long range
```
N N N N N N N N N N N
1 . . . . . . . . . 2
1 . R . . . . . R . 2
. . . . B . B . . . .
. . . . . . . . . . .
. . R . Y Y Y . R . .
. . . . . . . . . . .
N N N N N N N N N N N
```
`N` fence (60 HP), `R` tree (45 HP), `Y` bike rack (30 HP), `B` bench. Grass floor.
11 wide (not 12) so it fits next to the joystick.

### Science Lab (10×7): tight, with fragile glass cabinets
```
L L G G L L G G L L
1 . . . . . . . . 2
1 . A A . . A A . 2
S . . . G G . . . S
. . A A . . A A . .
. . . . . . . . . .
L L L L L L L L L L
```
`A` lab table (35 HP), `G` glass cabinet (only 10 HP, breaks easily), `S`
skeleton (15 HP). White tiled floor.

### Recess (11×8): playground with a sandbox and two slides
```
N N N N N N N N N N N
1 . . . . . . . . . 2
1 . H Z . . . W H . 2
. . . . s s s . . . .
. . . . s s s . . . .
. . R . . . . . R . .
. . . . . . . . . . .
N N N N N N N N N N N
```
`H` slide ladder, `Z`/`W` slide (60 HP each), `s` **sandbox**: you can walk
in it, and standing in it **hides you from throws and shots** (projectiles,
lines, lobs and thrown items fly past or miss). Melee, dashes, spins, leaps
and shockwaves still hit. Grass floor.

---

## 2c-2. Items (Dad's idea)

A setting: **ITEMS ON/OFF** (host online, or on the local / VS CPU setup; on by default).

- When a **locker** breaks, the fighter who broke it (attack, or slamming
  someone into it) gets an item **30%** of the time. Other obstacles drop nothing.
- You hold **1 item**; a new one replaces the old. Items are lost when the round ends.
- Using an item **is your attack for the turn** (you can still move first).
  It's the card above the joystick, or key **5**.

| Item | What it does |
|---|---|
| Book | Thrown: first enemy in a line up to 4 tiles, 12 damage, push 1 |
| Pencils | Thrown: first enemy in a line up to 4 tiles, 3 hits of 3 damage |
| Water bottle | Spill a puddle on the tile in front of you. An enemy who walks into it slips: 5 damage, stops walking (no undo), Dizzy next turn. The puddle is then gone. Your own team walks over it safely. Pushes and dashes don't trigger it |
| Melee Guard / Ranged Guard (mystery box only) | Two separate items; the box gives one at random and you see which. Using it cuts that kind of damage (melee, or throws/shots) by **20–45%** (random) for **1–2 of your turns** (random) |

**Mystery box (Mom's idea):** with items on, a "?" box drops on a free tile
near the middle every 4 turns (one at a time). Whoever walks onto it first gets
a **Melee Guard** or **Ranged Guard** (replacing any item). Steps taken before the pickup can't be undone.

---

## 2d. Rule details (decided while building M1)

Small rules the design didn't cover, as implemented in `game/rules/battle.gd`:

- **Attacks hit desks and lockers too.** Any attack that covers an obstacle's
  tile damages it, which is how cover gets broken.
- **Stepping back onto your previous tile undoes that step**, so a misclick on
  the joystick doesn't waste a move.
- **Charge / Shoulder Tackle** run up to their range (4 / 2 tiles), then hit
  whatever is directly ahead. So Charge reaches an enemy up to 5 tiles away, and
  its damage counts the tiles actually run (8 + 3 × 4 = 20 max).
- **Slingshot and Flying Tackle pass teammates.** Water Gun, Book Lob and area
  attacks skip teammates too (no friendly fire).
- **Mega Sword** lands on the tile in front of Snorre. The 3×3 around that tile is
  the inner ring (30), the next ring out is the outer ring (12 + Dizzy).
- **Block** stops the whole hit: damage, knockback and Dizzy.
- **Bonuses apply to supers too** (Rage +8, Last Stand +3, Sugar Rush ×1.3).
- **A super's own damage doesn't fill the attacker's meter** (the victim still
  gains meter).
- **Dizzy** always affects the victim's next turn, even when Mike gives it to
  himself during his own turn.
- **Match end:** the match stops as soon as the leader can't be caught. If a
  round ends with everyone knocked out at once, nobody gets the point.

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
| M0 ✅ | Project setup | Godot project, folder layout, test runner, README |
| M1 ✅ | Rules engine | Grid, move, 4 attacks, super, meter, knockback, obstacles, rounds. All unit-tested |
| M2 ✅ | Local battle | Playable hot-seat 1v1 on one device with placeholder sprites + one test map |
| ✅ | VS CPU | 1v1, 1v1v1 or 2v2 with a CPU teammate vs the computer player; you pick each CPU's fighter (or random) and EASY / NORMAL / HARD. In a 1-round sim, Hard beats Easy 97%, Hard beats Normal 66%, Normal beats Easy 92%. VS CPU matches don't count in stats |
| ✅ | Boss fight | THE PRINCIPAL: 2250 HP, 3x3, never moves, in the Principal's Office (11x9). Team of 3 (CPUs fill the gaps; online the server plays them); players +250 HP; hits on him count double. After the team (and his teachers) he does Ruler Slam (next to him, 24, push 2), Megaphone Yell (in line, 15, push 3), DETENTION! (one player, 24 + Dizzy) or, once no teachers are left (40% a turn from his 2nd turn), TEACHERS, HELP ME!: two teachers (40 HP, move 3) appear next to him, walk at the nearest player and Scold (10). They leave when he's beaten. Below 25% HP he gets ANGRY: +5 damage on his attacks. An apple (+60 HP) drops for every 150 HP he loses; CPUs only grab one below 70% HP. An all-CPU team wins ~28% in `tools/boss_sim.gd` (target 20-40%). BOSS FIGHT menu button, VS CPU mode BOSS, online lobby BOSS toggle (1-3 players) |
| ✅ | Lunch Lady boss | Second boss, unlocked by beating the Principal (any Principal trophy counts). Same rules in her Kitchen: Mystery Meat (one player next to her: 20 + no attack next turn, never twice in a row), Gravy Splash (in line, 12, push 3, leaves up to 3 gravy puddles at once that make you slip), Tray Frisbee (bounces between up to 3 players within 5 tiles of each other, 16 each), KITCHEN, HELP ME! (two cooks). 3 trophies of her own. Picked under BOSS in VS CPU or by cycling the BOSS button online. CPU team wins ~27% in `tools/boss_sim.gd -- 200 4 lunch_lady`. CPUs now also walk around enemy puddles. |
| ✅ | Gym Teacher boss | Third boss, unlocked by beating the Lunch Lady. The Gym (wooden floor, benches): Push-Ups! (one player next to him: 40 + no moving next turn), Medicine Ball (in line: 22, rolled back up to 6 tiles, slam at the wall), WHISTLE! (every player 26 + push 1), TEAM, HUDDLE UP! (two athletes). 3 trophies (gt_). CPU team wins ~22%.  |
| ✅ | Final boss (boss 4) | The Principal again (2500 HP), unlocked by beating the Gym Teacher. Office phase like boss 1 until he has lost 500 HP; then a cutscene (zoom in, he turns red, shake, white flash) and the fight moves to Space (star floor, 4 asteroids that skip occupied tiles). In space he's angry for good: Gravity Slam (next to him 20, push 2), Laser Eyes (in line 11 + Dizzy), Meteor Shower (up to 3 players, 12), Black Hole (everyone 4 and pulled 2 tiles in). 3 trophies (fp_). CPU team wins ~13%. (The user's idea.) |
| ✅ | Hall Pass | Item (lockers / mystery box, only with SHRINK on): no detention zone damage for your next 2 turns. |
| ✅ | Trophies | 3 + one per fighter for beating the Principal (solo, with friends, nobody KO'd, as each fighter); TROPHIES screen; a 5th BOSS LEAGUE of achievements (first trophy, Untouchable, 3 / 6 / all trophies) |
| ✅ | Achievements | 20 achievements, easiest first (First Blood ... Online Legend), saved on the device. All match types count (Online Legend only online). Popup when unlocked, ACHIEVEMENTS screen from the menu with progress, summary on STATS. Logic in `stats/achievements.gd` + `stats/achievement_tracker.gd` |
| ✅ | 1v1v1v1 | With 4 players the host can switch between 2V2 and FREE FOR ALL (everyone gets their own corner). VS CPU has a 1V1V1V1 mode too. A 1v1 or 1v1v1 never uses lobby teams |
| ✅ | Shrinking map | Setting SHRINK ON/OFF (off by default). After 6 turns the outer ring becomes a red DETENTION zone; it grows a ring every 4 turns and stops one ring before the middle. Starting your turn in it costs 10 HP (can KO). The mystery box never lands in it. A red countdown at the top warns: "MAP STARTS SHRINKING IN 4 TURNS" / "DETENTION ZONE GROWS NEXT TURN!" |
| ✅ | Victory screen | The match-end screen shows the MVP (most damage dealt) and Most KOs over the whole match |
| ✅ | Extra HP setting | Host (and local / VS CPU setup) picks HP: ORIGINAL, +50, +100 or +150 for every fighter, for longer fights |
| ✅ | Open lobbies | Public/private lobby (public by default). The join screen lists open lobbies (public, waiting, not full: code + player count only) with JOIN. Host can KICK; kicked players can't rejoin that lobby |
| M3 ✅ | Online 1v1 | Headless server, nicknames, create/join by code, synced battle |
| M4 ✅ | 3–4 players | FFA + 2v2, host settings (map/rounds/timer/teams), turn order |
| M5 ✅ | Robustness | Turn timer, reconnect, host migration, rematch, lobby cleanup |
| M6 | Content | Characters + maps from the design session (TBD) |
| M7 | Pixel art | Real sprites/tilesets from your references, animations, effects, sound |
| M8 | Ship | Android build (+ Play Store, $25 once), web build hosted, iOS later (needs a Mac + $99/yr) |

---

## 7. Still to decide (next sessions)

- **Maps**: tune the draft layouts in playtests. More maps later (cafeteria?).
- **Numbers**: first pass is done (section 2b). Tune in playtests.
- **Status effects**: bleed/burn/stun/heal, or none?
- **Timing minigame** (press at the right moment for bonus damage): **later**,
  a stretch goal after the core game ships.
- **Game name**, menu style, music/sound.
