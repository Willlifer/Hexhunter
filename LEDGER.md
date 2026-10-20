# LEDGER

One row per tracked item. An item belongs here only if it passes all four tests:
1. It's discrete.
2. It has a state that can change.
3. Forgetting it costs something.
4. No test already guards it.

States: BLOCKED / OWED / AWAITING PLAY / WATCH / DEFERRED. IDs never change.

## Live

| ID | Item | State | Unblocked by / note |
|----|------|-------|---------------------|
| L-10 | Phase 2 gate: the author plays each monster on its biome with each weapon | PASSED 2026-10-19 ("very fun, loved all of the fights"); fire burn "way too strong" -> fire_stand 3.0->1.2, fire_cross 1.5->0.6, burn 2.0->1.0 (H46) | dist\Hexhunt.exe + launchers/ |
| L-11 | Roared shapes are now huge (thrash 72 hexes, Colambros back-roll 65): intended per H41 but untested by a human | PASSED 2026-10-19: no complaint about size after play; stays | author |
| L-12 | Visual hooks the monster lanes asked for: Colambros quills glow when smouldering, Rimeslithe crystals tint by cold, Spirewalker reed arcs by charge; HUD icons for slow / freeze / poison / paralysis | SETTLED 2026-10-19 (Lane V, H600-H611) | - |
| L-13 | Hunter hood reads as a ring helmet from the front; Black | White weapon glbs in art/weapons/bw_temp still used by the body until the loader points at Lane A's coloured set | SETTLED 2026-10-19 (Lane V: cowl hood, coloured weapons, bw_temp deleted) | - |
| L-2 | Windowed checks (`--shot`, the sandbox) are not in CI; CI runs import, self-test and the headless smoke run only | WATCH | A software-rendering capture on CI is open; the local command is `run.bat --fight swampfang --shot design/art/shots --cam 30,42` |
| L-3 | Element shaders were tuned for a white tile (Black | White); on natural ground the dark face and the glaze read, fire and water read, light's dark ring may need retuning on grass | WATCH | Lane C / Lane P judge on the pond |
| L-4 | Tile-effect "cards" (standing flames, light column, dark tendrils) are copied in but not yet drawn by HHArenaView | OWED | Lane P when the fight view is built |
| L-8 | The autoplay bot does not dodge; smoke runs end with the player dead. Fine for a smoke test | CLOSED: the author has played all four fights (L-10) | - |
| L-6 | GitHub remote not created (H6: only when asked); `.github/workflows/ci.yml` is ready for it | DEFERRED | Author asks |

## Settled

| ID | Item | Date |
|----|------|------|
| S-1 | Phase 0 foundation: import clean, self-test 35/35, smoke run clean, rendered frames captured | 2026-10-19 |
| S-2 | Phase 0 gate passed by the author (faster walk, 50 m arena, 3x tile life; left-click will be the auto-attack) | 2026-10-19 |
| S-4 | Phase 1 gate passed; notes H31-H41 applied (free movement, right-click act, own-element immunity, 3x HP, 3x tile life, wind-ups, repositioning, potions, wide roars) | 2026-10-19 |
| S-5 | Phase 2 build: lanes A, B, C/D, E x3 merged; 165/165 in 23 suites; every monster smoke-run on its biome; frames captured | 2026-10-19 |
| S-3 | Phase 1 build: lanes P, C, E, F merged to dev; self-test 71/71 in 11 suites; pond smoke run with the Swampfang brain clean; frames captured | 2026-10-19 |
| L-14 | Swampfang barely moves between attacks in play (reposition 70% / walk 10 ticks turns in place when the player stays close); the other three roam more. Author noted it without asking for a change | WATCH | Lane P, revisit with the next pond tune pass |
| L-15 | Every fight started the hunter on fire/water | SETTLED 2026-10-19: the lobby picks any two of seven (Lane L) | - |
| L-16 | Phase 3 gate: the author plays the lobby (every setup, Unlock all upgrades, slot some) and a full hunt (`Hunt.bat` or GO HUNTING): map, ambush, prep, fight, results, drops | PASSED 2026-10-19 ("damn actually very fun"); visual pass next (H49) | - |
| L-17 | Balance flags from Lane U: Exchange Nova paints 37 hexes on a 1 s cooldown with no wind-up (strongest upgrade); Hunting Knives add three 60-damage strikes every 6 s; Cluster Shot and Aftershock always land because brains do not dodge player telegraphs | AWAITING PLAY | author slots them; numbers are F1 keys `upgrade_*`, `daggers_up_*`, `bow_up_*`, `lance_up_*` |
| L-18 | Readability flags from Lane V: Colambros' smoulder glow is weak at 30 m on caldera ground; Rimeslithe's crystals read pale blue even at rest; Spirewalker charged turns the whole reed bed violet; the ward and projectile markers are covered only by headless tests | AWAITING PLAY | author looks; fixes are view-only |
| L-19 | Lobby picks blind: tiles are colour + name, no thumbnails; element strip's active/backup alternation is not shown until used; returning from a fight shows only a one-line result | SETTLED 2026-10-19 (Lane UI: thumbnails, element hint, run history, H800-H813) | - |
| L-20 | The world map is readable but sparse: four sites on rolling grass, no roads or landmarks | SETTLED 2026-10-19 (Lane ENV: paths, lake, tower, stones, forest edge) | - |
| L-21 | Map uses a x5 scaled parent because HHCameraRig clamps distance at 40 m (Lane H R-H4) | SETTLED 2026-10-19 (HHCameraRig.dist_max per instance, H761) | - |
