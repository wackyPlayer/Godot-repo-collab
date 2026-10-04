# Caballerito — The Violet Keep

A playable top-down Godot 4 room built from the three supplied PNGs. The stone
image forms the floor, perimeter walls, and four solid pillars. The knight uses
all four frames of each original idle and walk sheet.

Open `project.godot` in Godot 4 and press **F5**.

| Control | Action |
| --- | --- |
| WASD or arrow keys | Walk, including diagonals |
| Hold Shift | Run |
| R | Return to the starting position |
| Esc | Close the demo |

The foot collider slides along walls and blocks. Depth sorting allows the knight
to walk behind pillars. Nearest-neighbor filtering keeps the sprites crisp.
The original image files were copied unchanged into `assets/`.

Edit the room layout in `scenes/room.tscn`, floor and boundaries in
`scripts/room.gd`, and movement or animation in `scripts/knight.gd`.

Headless movement/collision checks:

```powershell
godot --headless --path . --script res://tests/room_smoke.gd
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
