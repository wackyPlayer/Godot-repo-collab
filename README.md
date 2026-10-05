# Caballerito — The Violet Keep

A top-down Godot 4 dungeon crawl. The game opens with a short prologue
(`scenes/tutorial.tscn`): the knight learns to walk and run, then meets the
mage, who turns them into a rock. The north door then opens into the dungeon
(`scenes/room.tscn`), which you explore in rock form. Every run builds a new
keep: a branching floor of rooms joined by doors, with stairs down in the
deepest dead end and items (sword, potion, bubble charm) waiting in other dead
ends. Each floor down adds two more rooms.

Open `project.godot` in Godot 4 and press **F5**.

Rooms are 704 pixels wide and 768 pixels tall: the original width and twice the
original height. A `Camera2D` child of the knight follows it at 1x zoom in both
the prologue and dungeon. Door transitions and reset move the camera immediately.
The HUD and minimap stay fixed on screen.

| Control | Action |
| --- | --- |
| WASD or arrow keys | Walk, including diagonals |
| Hold Shift | Run |
| R | Return to the door you entered the room by |
| Esc | Close the demo |

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
`VioletKeep` node to replay a specific dungeon (0 = random each run).

`scripts/tutorial.gd` extends `room.gd` with the prologue's lessons and the
mage's curse scene. `scripts/room.gd` turns the current room into walls, door triggers, blocks and
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
