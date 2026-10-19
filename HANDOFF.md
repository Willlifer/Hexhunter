# HANDOFF

## Where
`<repo>`, branch `dev`. No remote (H6). Godot 4.7 console binary in Downloads (CLAUDE.md).

## Where it stands (2026-10-19)
Phase 0 Foundation is built and green. Waiting on the author's Phase 0 gate check (LEDGER L-1).
- import clean; `-- --self-test` 35/35 in 5 suites; `-- --fight swampfang --autoplay` clean (every reaction fires, hash printed).
- Rendered frames: `design/art/shots/shot_00..06.png` (grass floor, hedge ring, stone skirt bowl, player capsule, monster sphere, true-hex + destination outlines, fire / glaze / dark painted hexes).
- Core: HHHex, HHTune, HHFormulas, HHCharge (douse, fuse, glaze, gale, overheat, overfreeze), HHArena (heightfield + BFS), HHSim (30 Hz orders, glide, statuses, stagger, walk-into-reach, determinism), HHPhases.
- View: HHArenaView (GKMesh floor, tile shaders), HHCameraRig, HHFight sandbox, HHCapture.
- Docs: CLAUDE, PLAN, DECISIONS (H1-H21), LEDGER, guide/01-04.

## Do this first
1. Author: `run.bat --fight swampfang` and look at the shots. Say go, or what to change.
2. On go: open Phase 1. Create worktrees for lanes P, C, E, F (guide/04-lanes.md). Lane P is the integrator and keeps `src/core`.
3. Lane P's first job: the lance kit as orders (Q Pierce line, W Exchange, E Guard, R Eruption) plus the basic attack, then the HUD bar and the F1 tune panel.

## Run
`test.bat` (import + self-test). `run.bat [--fight swampfang] [--seed N] [--cam 30,42]`. Shots: `run.bat --fight swampfang --shot design/art/shots --cam 30,42`.

## Open questions
- None blocking. Watch items in LEDGER: light's dark ring on grass (L-3), the FX cards not drawn yet (L-4).
