# Visual pass (Phase 3.5): shared brief for every lane

Author, 2026-10-19, after playing the lobby and a hunt: "damn actually very fun, lets do
visual pass on everything, perform a gauntlet test to bring the monster models a bit
closer to the reference models. make attacks telegraphed not only by highlighted tiles,
but on visual effects like wind whipping up before turning to ice, and something to
distinguish between colambros's fire breath and charge. I think it's great though, lets
keep going."

## What a gauntlet test is here
The term comes from the kickoff ("gauntlet test them to the below references"; Lane A
did it for the weapons, DECISIONS H109). For each asset:
1. Render the asset in the reference's pose and camera angle, and build ONE comparison
   image with the reference on the left and the render on the right at the same height
   (a small GDScript tool is fine: load both textures, blit side by side, save PNG).
2. Look at that image with the Read tool. Write down, in the lane's design doc, the
   five biggest differences in this order: silhouette and proportions, posture/stance,
   the signature features, palette and value contrast, surface detail.
3. Fix the top differences, re-render, look again. At least three rounds. Each round
   gets a numbered entry with what was wrong and what changed.
4. Grade honestly. The previous review rounds accepted a Colambros that plainly stands
   on four legs as "the biped reads". If the comparison image does not show it, it is
   not done. Never claim a visual you did not look at.

The kickoff's written description of each monster (`design/kickoff/KICKOFF.md` lines
197-275) is the authority; the reference image is art direction. Where they disagree,
the text wins and the image supplies the look. Low-poly flat-shaded is the style; the
goal is "a bit closer to the reference", read at the 30 m / 44 deg gameplay camera
first and in close-up second.

## Rules for every lane
- Your own git worktree off `dev`; touch only your owned paths (your prompt lists them).
  Anything else is a "Request" line in `DECISIONS-lane-<X>.md`.
- Log calls as rows in `DECISIONS-lane-<X>.md` in DECISIONS.md's row format, inside your
  reserved block.
- Sim behaviour does not change: footprints, telegraph shapes and timings, damage, brain
  logic, clip NAMES (brains call them) and role material names that `monster_body.gd`
  drives (`quill`, `crystal`, `eye`, beads/reeds roles: grep `_drive_state`) stay.
- `godot --headless --path . -- --self-test` green before hand-back (the runner finds
  `tests/test_*.gd` itself). Smoke: `--arena <id> --fight <monster> --autoplay --seconds 20`
  with zero SCRIPT ERROR lines.
- The player's files in `%APPDATA%\Godot\app_userdata\Hexhunt` are shared by every
  worktree and the author may be playing: never delete or write `hunter.json`,
  `hexhunt_last.json` or `hexhunt_tune.cfg`.
- Review renders go under `design/art/...` or `design/visual_pass/<lane>/`. Final
  comparison images are committed (force-add if gitignored) so the author can see them.
- Godot: `<godot>`.
  Blender 5.2: `<blender>` (glTF
  exporter: one mesh object per colour role, H303).
- GDScript: `:=` cannot infer from a Dictionary read or Variant; write `var x: Type =`.
- Commit messages end with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TkDAFjAZfbyuVMBwWarbCq
- Hand-back report: branch, commits, test totals, the comparison image paths, every
  Request, and three honest observations about what still reads badly.
