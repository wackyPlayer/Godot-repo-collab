# Caballerito — A rocky tower

A top-down Godot 4 dungeon crawl across five floors.

| Floor | What happens |
| --- | --- |
| 1 | **The round chamber** (`scenes/tutorial.tscn`). Learn to walk and run, then the mage turns you into a rock. The sealed north door opens. |
| 2 | Generated floor, 8 rooms, 2-3 enemies per room. |
| 3 | Generated floor in a dim red, 10 rooms, 5-7 enemies per room. |
| 4 | Red as hell: a deep pulsing red, a red vignette and rising embers. A maze of 22 rooms with the stairs at least 8 rooms from the start. Every enemy has red eyes and chases as fast as you run. |
| 5 | **The sanctum**: one hall and the final cutscene. The mage laughs that there is no cure and you will be a rock forever, then the win screen. |

The win screen offers **endless mode** (floors 6 and beyond, still a rock,
with more enemies as you go), playing again, or quitting. Floor sizes, enemy
counts and speeds are set near the top of `scripts/room.gd`.

**Enemies** (`scripts/enemy.gd`): slime cubes (slow) and skeletons (faster,
see further). They wander near where they spawn and chase you on sight. They
wait a moment after you enter a room, and never spawn near the door you came
in by. On floor 4 every enemy takes 5 sword hits (red pips above its head
count them down); each hit that does not finish it flashes it, shoves it
back and stuns it for a moment. Contact is checked directly every frame: an enemy's body touching your lower
body costs a heart from any side. Enemies are not stopped by your body, so
they cannot be held off at arm's length. Floor 4 swaps in the red-eyed sheets (`assets/*_red.png`).

The floor tints colour only the room (floor, walls, blocks), so the player,
enemies and their red eyes stay readable. The mage is drawn at 3x, and the
camera pans to frame it during both cutscenes.

**The rock's trail** (`scripts/rock_trail.gd`): in rock form you scrape a pale
trail and scatter gravel behind you, and stone chips spray out behind you
while you move (the `Carving` particles in `scripts/knight.gd`). Each mark fades out and is gone 20
seconds later. Trails are kept per room, so they show where you just were,
which helps on floor 4.

**Items** (found in dead-end vaults; shown top right):

- **Sword:** kept for good once found. **Space** (or J) swings it in an arc
  toward the way you last moved, or along the brain heading. One hit
  defeats an enemy, even one trapped in a bubble.
- **Potion:** carried until you drink it with **Q**. It mends a heart every
  1.5 s (three times) and speeds you up by half for 8 s.
- **Bubble charm:** used automatically when an enemy hits you: the bubble
  takes the hit and traps that enemy for 8 s, harmless and floating.

Potions and bubbles are used up, and then reappear in the room they came
from, so you have to go back and pick them up again. You can carry several.
For brain play, map a signal to Swing sword or Drink potion in Settings.
The numbers are constants near the top of `scripts/room.gd`; set
`BUBBLE_BLOCKS_DAMAGE` to false if the hit should still cost a heart.

**Health:** three hearts at the top left: red while you are a knight, stone
once you are a rock. Touching an enemy costs a heart, knocks you back, and
leaves you blinking and safe for a moment. Running out shows a game-over menu: retry the same floor (same layout, full
hearts), go back to the round chamber, or quit.

Animated torches light every room. The FPS counter sits at the bottom left.
The soundtrack lives in the `Music` autoload (`scripts/music.gd`) and
crossfades between tracks: Glitcher's "Dyalla" for floors 1-4 and Evening
Telecast's "Final Boss" for the sanctum (endless floors alternate them).

Open `project.godot` in Godot 4 and press **F5**.

The game opens on the **main menu** (`scenes/main_menu.tscn`): Play, Settings
and Quit. Esc in game returns to it. Settings has three tabs:

- **Controls:** two keys per action, click one and press the new key.
  Backspace clears a key, Esc cancels. Saved to `user://settings.cfg`.
- **Brain interface:** play with a g.tec Unicorn headset (see below).
- **Audio & display:** music volume and fullscreen.

## Brain interface (three signals)

The game can be played hands-free with a headset that detects three things:
a **blink**, a **closed mouth** and **closed eyes**. The `BrainLink` autoload
(`scripts/brain_link.gd`) turns them into steering:

| Signal | Default action |
| --- | --- |
| Close mouth | Go / stop: walk along the heading, or stop |
| Blink | Turn the heading clockwise (up, right, down, left) |
| Eyes closed | Run on / off |

An arrow at the player's feet shows the heading: faint while standing,
bright while walking, doubled while running. Each signal can be remapped in
Settings to Turn, Go / stop, Run, Back to door or Nothing. In menus a blink
moves to the next button and a closed mouth presses it, so the whole game,
menus included, works without a keyboard.

The detector can deliver signals in either of two ways, whichever is easier:

- **UDP:** send the word (BLINK, MOUTH or EYES by default, editable) as a
  short text message to the game's port (default 1000). For example,
  Unicorn Speller's network output, or a few lines in any language.
- **Keys:** send a key press (B, M or E by default, rebindable). The same
  keys also let you try the controls on a keyboard.

Setup: Settings > Brain interface > tick **Use the brain interface**. The
status line shows "Listening on UDP port 1000" and the last signal received.
Each signal has a **Test** button. Without the headset you can also run
`python tools/send_brain_command.py BLINK`. **Ignore repeats** (default
0.4 s) makes a signal reported twice in quick succession count once.

The dungeon's start room never has a room directly below it, since you
arrive there from below.

## How the procedural rooms work

`scripts/dungeon_generator.gd` is pure data and runs in two passes:

1. **Floor plan.** Rooms grow outward on a grid from the start room. A new
   room may only touch the room it grows from, which keeps the plan branching
   with natural dead ends (the same rule *The Binding of Isaac* uses). A few
   extra doors then add small loops. The deepest dead end becomes the
   stairwell, and up to two others become item vaults.
2. **Interiors.** Each room picks a hand-drawn 20x10 template (`#` block,
   `.` floor) or a mirrored random rubble pattern, flipped at
   random. Templates are centred inside the taller 20x22 interior, preserving
   connected walls and block sizes. The approach to every door and the room
   centre are cleared, then a flood fill checks that every door is reachable.
   Layouts that fail are
   re-rolled. Decorations go against the north wall the same way.

Add a room design by appending a template to `LAYOUTS`. The generator handles
mirroring, door clearance and reachability. Set `dungeon_seed` on the
`RockyTower` node to replay a specific dungeon (0 = random each run).

`scripts/tutorial.gd` extends `room.gd` with the round chamber (a ring wall
with curved collision), the lessons and the mage's curse scene. `scripts/room.gd` turns the current room into walls, door triggers, blocks and
drawing, and runs the HUD and minimap. `scripts/knight.gd` handles movement
and animation.

## Collision

The knight's origin sits at the bottom of its feet. Its 18x6 collider is as
wide as its body, so the sprite cannot sink into anything beside it. The
sprite is shifted 5px because the feet in the art are off-centre. Each stone
block's art fills exactly the floor tile its collider covers. Touching blocks
draw as one continuous wall, with edges and front faces only on the outside.
The side and south walls are drawn on a layer above the knight (`FrontWalls`),
so anything poking past solid walls (like the plume) is hidden behind them.
Open doorway floors and thresholds draw below the knight; only their solid
jambs draw above it. Door callbacks check the whole open passage so the wider
foot collider cannot miss a transition. Continuous trim follows the inner
floor opening and outer perimeter, joining all four corners. Decorations and
the mage collide only at their base, so the knight can step behind them.

Headless checks for the dungeon (generator, movement, collision, doors) and
the prologue (lessons, curse, door):

```powershell
godot --headless --path . --script res://tests/room_smoke.gd
godot --headless --path . --script res://tests/tutorial_smoke.gd
godot --headless --path . --script res://tests/floors_smoke.gd
godot --headless --path . --script res://tests/menu_smoke.gd
godot --headless --path . --script res://tests/items_smoke.gd
godot --headless --path . --script res://tests/contact_smoke.gd
godot --headless --path . --script res://tests/door_regression.gd
```

Check doorway visibility and all four rendered corners with a graphics backend:

```powershell
godot --path . --script res://tests/door_visual.gd
```

Render one room of each kind into `artifacts/`:

```powershell
godot --path . --script res://tests/capture_room.gd
```

GitHub repository: [wackyPlayer/Godot-repo-collab](https://github.com/wackyPlayer/Godot-repo-collab).
The demo is on branch `codex/violet-keep-demo`, based on the existing repository
history. Git authentication uses the existing Git Credential Manager sign-in.

For the first push, run `git push` from this folder. It automatically connects
this local branch to the same branch on GitHub.

To save and push later changes from this project folder:

```powershell
git add .
git commit -m "Describe your changes"
git push
```

Godot's `.godot/` cache and capture logs are excluded from Git. Sprite sources,
scenes, scripts, and resource UID files are included.
