# The hunt loop (Lane H, H48)

The kickoff's hunt, start to finish: you explore a region map, a site stirs,
you walk up to it, the monster bursts out angry, you prepare, you fight, you
take your spoils, you are back on the map.

```
map ---approach---> ambush ---> prep ---play---> fight ---> results ---continue---> map
 |                               \---back---> map
 \---Esc---> (end)
```

| Screen | Script | What it does | Ends with |
|---|---|---|---|
| map | `src/game/hunt/world_map.gd` `HHWorldMap` | A 200 m region seen from 170 m up: four sites in the four biome looks (pond, cave mound, glade, caldera), the hunter as a token with a true-hex ring, one site pulsing rings and motes. Right-click runs (8 m/s, `hunt_run_mps`), drag orbits, wheel zooms. Site names fade in when the cursor is near them. | `{ result: "approach", monster, arena, site }` within `hunt_approach_m` (4 m) of the stirring site; `{ result: "quit" }` on Esc |
| ambush | `ambush.gd` `HHAmbush` | The monster's arena loads; the hunter stands at the player spawn; the monster spawn pulses; at 0.9 s the monster erupts (scale-up, rise, roar clip, a spray of the biome's motes, a stage light); the camera swings from the hunter onto it; at 1.7 s its name slams in. 3.8 s. | `{ result: "ambushed" }`, or `"skipped"` on any key / click |
| prep | Lane L's lobby (`HHLobby` / `src/game/lobby/lobby.gd`), else `prep_stub.gd` | cfg.locked = `["arena", "monster"]`: the prep screen may change weapon, elements, upgrades, never the hunt's arena or monster (HHHuntFlow enforces it even if the screen returns them changed). | `{ result: "play", cfg }` or `"back"` |
| fight | `shell.play(cfg)` -> HHFight | The fight as it is. | `{ result: "win"|"fallen"|"abort", cfg, ticks, hp, monster_hp, max_hp, monster_max_hp }` |
| results | `results.gd` `HHResults` | VICTORY / FALLEN, time, damage dealt and taken, HP left, the drops as cards (name, skill letter, blurb from `HHUpgrades.TABLE`). On a win: `HHDrops.roll(monster, rng, weapon, save.owned)` (rng seeded from the launch seed + tick count, so a replay rolls the same), `save.own(id)` per drop, `save.record_hunt(...)`, `save.save()` (R-U2). Both classes are found by name and skipped when absent: "(no drops yet)". | `{ result: "continue", drops, summary }` on Continue / Enter / Space |

`HHHuntFlow` (`hunt_flow.gd`) is the pure transition table; `HHHunt`
(`hunt.gd`) drives it against a shell; `HHHuntKit` holds the hunt's feel
numbers (`TUNE`, registered as `hunt_*` so the F1 panel can edit them), the
arena loader (boot.gd's `_load_arena`, copied), bodies by duck type, and the
ring / mote helpers. `HHHuntShellStub`, `HHHuntFightWatch` and
`HHHuntPrepStub` let the loop run and test before Lanes L and U are in.

## Run it

- Headless: `godot --headless --path . -- --self-test` runs `tests/test_hunt.gd`
  (12 tests: the flow walk, locked keys, seeded site pick, approach radius,
  run pace, ambush timeline and roar clips, results with and without
  HHDrops / HHSave, the driver against a stub shell with and without `play()`).
- Windowed, today: `godot --path . --script res://tools/hunt_run.gd -- --seed 2 --weapon daggers`
  plays the whole loop on the stub shell (prep is the stub; F10 aborts a fight).
- Windowed, once wired: `run.bat --hunt [--seed N] [--weapon id]` (boot.gd, Lane L / integrator).
- Review renders: `godot --path . --script res://tools/hunt_preview.gd [-- --seeds 1,2 --monsters swampfang,... --lurk 0.6]`
  writes `design/hunt/shots/map_seed<N>.png`, `ambush_<id>_lurk.png`,
  `ambush_<id>_peak.png`, `results_win.png`.

## What the integrator wires

1. `boot.gd`: `--hunt` -> `HHHunt.start(shell, { seed, weapon })` where
   `shell` is HHShell (or `HHHuntShellStub.new()` added to the tree until it
   lands). Nothing else: HHHunt parents itself to the shell and runs.
2. HHShell: `show_screen(screen: Node, cfg)` must add the screen and call
   `screen.setup(cfg)`; `play(cfg)` must return the node whose
   `finished(result)` carries the fight payload (HHFight itself once it has
   the signal). HHHunt duck-types both and falls back to hosting screens and
   building an HHFight itself when they are missing.
3. The lobby: when shown with `cfg.locked = ["arena", "monster"]`, grey those
   tiles out and emit `finished({ result: "play", cfg })` / `{ result: "back" }`.
4. Optional: lift `HHCameraRig.DIST_MAX` to a var (H502) so the map can drop
   its scaled parent.
