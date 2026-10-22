# 01 Layout and run

## Folders

| Path | What |
|------|------|
| `project.godot`, `scenes/boot.tscn` | The project. Main scene is a one-node boot script. |
| `src/core/` | The rules core: node-free, seeded. `hex.gd` (HHHex), `tune.gd` (HHTune), `formulas.gd` (HHFormulas), `charge.gd` (HHCharge), `phases.gd` (HHPhases), `arena.gd` (HHArena), `sim.gd` (HHSim). |
| `src/game/` | The scene side: `boot.gd` (flags), `fight.gd` (HHFight: steps the sim, input to orders, draws), `arena_view.gd` (HHArenaView), `camera_rig.gd` (HHCameraRig), `tile_fx.gd` (HHTileFX), `look.gd` (HHLook). |
| `src/kit/` | Gamers Gauntlet's kit, verbatim: `gk_mesh.gd`, `gk_materials.gd`, `gk_def.gd`, `gk_asset.gd`. |
| `src/arena/`, `src/monster/`, `src/weapons/` | Lane C, E, A/B homes (empty until Phase 1). |
| `shaders/` | `tile_*.gdshader` + `tile_fx.gdshaderinc` + `tile_cards.gdshaderinc` (Black | White, verbatim); `gk_surface*.gdshader(inc)` (Gauntlet, verbatim). |
| `tests/` | `self_test.gd` (the runner) and `test_*.gd` suites. |
| `tools/` | `one_suite.gd`, `capture.gd` (HHCapture). |
| `arenas/` | Arena JSON (HHArena.to_dict). Empty until Lane C. |
| `art/`, `audio/` | Built assets (glb + manifests), sound. |
| `design/kickoff/` | The brief and reference images. `design/art/` review renders (local). |
| `.github/workflows/ci.yml` | Import, self-test, smoke run. |

## Commands

Binary: `<godot>` (`%GODOT%` in the bat files). Run from the repo root.

| Command | Does |
|---------|------|
| `godot --headless --path . --import` | Import; needed after a new `class_name` or asset. |
| `godot --headless --path . -- --self-test` | Every `tests/test_*.gd`; exit 0 = green; report at `user://self_test_report.json`. |
| `SUITE=test_charge [ONLY=test_douse] godot --headless --path . --script res://tools/one_suite.gd` | One suite while iterating. |
| `godot --headless --path . -- --fight swampfang --autoplay` | The smoke run: scripted walk and every reaction; prints the event log and the state hash. |
| `godot --path . -- [--fight swampfang] [--seed N] [--arena id] [--cam dist,pitch]` | The sandbox, windowed. |
| `godot --path . -- --fight swampfang --shot <dir> [--count n] [--every s] [--cam 30,42]` | Rendered frames to `<dir>/shot_NN.png`, then quit. Needs a window. |
| `-- --tune key=value` | Override one HHTune number for the run. |
| `godot --path . -- [flags] --preload` / `--no-preload` | Force the boot preload (HHPreload, H460) on or off. By default the browser runs it before the first screen (`preload_on_web`) and the desktop skips it (`preload_on_desktop`); headless and `--shot` never do. It prints each step's time, and a windowed fight prints its own build and warm time. |

`test.bat` = import + self-test. `run.bat [args]` = the sandbox.

## Sandbox controls (Phase 0)

Right-click walks (true-hex snapped). Left-click paints the selected element (keys 1-7: fire water ice thunder wind dark light). W swaps active and backup element. Shift runs. Space stops. Middle-drag or right-drag orbits; wheel zooms; arrows orbit and pitch. Escape quits.

## Suites (Phase 0)

| Suite | Guards |
|-------|--------|
| `test_hex` | odd-r math, roundtrips, lines, rays |
| `test_charge` | axis + decay, douse, fuse, glaze/shatter, gale, overheat, overfreeze, authored, propagation rules |
| `test_arena` | round shape, heightfield and bowl, BFS path, walk-into-reach, cliffs, JSON roundtrip |
| `test_sim` | walk arrives on time, glide, stop/run, standing fire, crossing fire, detonation damage, swap and statuses, stagger, walk into reach, determinism, win/dead |
| `test_core_misc` | formulas, phases, tune, tile-fx mapping, GKMesh |

Add a suite per lane: `tests/test_<lane>_*.gd`. A test method takes `c: HHSelfTest.HHCheck` and calls `ok / eq / near`.

## Open checks (need a window)

Listed in LEDGER L-2. Local command: `run.bat --fight swampfang --shot design/art/shots --cam 30,42`, then look at the PNGs.
