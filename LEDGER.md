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
| L-10 | Phase 2 gate: the author plays each monster on its biome with each weapon (`run.bat --arena cave --fight rimeslithe --weapon bow` etc.) | AWAITING PLAY | dist\Hexhunt.exe |
| L-11 | Roared shapes are now huge (thrash 72 hexes, Colambros back-roll 65): intended per H41 but untested by a human | AWAITING PLAY | author |
| L-12 | Visual hooks the monster lanes asked for: Colambros quills glow when smouldering, Rimeslithe crystals tint by cold, Spirewalker reed arcs by charge; HUD icons for slow / freeze / poison / paralysis | OWED | Lane P, Phase 3 |
| L-13 | Hunter hood reads as a ring helmet from the front; Black | White weapon glbs in art/weapons/bw_temp still used by the body until the loader points at Lane A's coloured set | OWED | Lane B follow-up |
| L-2 | Windowed checks (`--shot`, the sandbox) are not in CI; CI runs import, self-test and the headless smoke run only | WATCH | A software-rendering capture on CI is open; the local command is `run.bat --fight swampfang --shot design/art/shots --cam 30,42` |
| L-3 | Element shaders were tuned for a white tile (Black | White); on natural ground the dark face and the glaze read, fire and water read, light's dark ring may need retuning on grass | WATCH | Lane C / Lane P judge on the pond |
| L-4 | Tile-effect "cards" (standing flames, light column, dark tendrils) are copied in but not yet drawn by HHArenaView | OWED | Lane P when the fight view is built |
| L-8 | The autoplay bot does not dodge; a 40 s smoke run ends with the player dead to thrash_splash. Fine for a smoke test, but the fight tuning (thrash 15%, every ~3.7 s, 42-hex ring) is untested by a human | AWAITING PLAY | author plays the pond |
| L-6 | GitHub remote not created (H6: only when asked); `.github/workflows/ci.yml` is ready for it | DEFERRED | Author asks |

## Settled

| ID | Item | Date |
|----|------|------|
| S-1 | Phase 0 foundation: import clean, self-test 35/35, smoke run clean, rendered frames captured | 2026-10-19 |
| S-2 | Phase 0 gate passed by the author (faster walk, 50 m arena, 3x tile life; left-click will be the auto-attack) | 2026-10-19 |
| S-4 | Phase 1 gate passed; notes H31-H41 applied (free movement, right-click act, own-element immunity, 3x HP, 3x tile life, wind-ups, repositioning, potions, wide roars) | 2026-10-19 |
| S-5 | Phase 2 build: lanes A, B, C/D, E x3 merged; 165/165 in 23 suites; every monster smoke-run on its biome; frames captured | 2026-10-19 |
| S-3 | Phase 1 build: lanes P, C, E, F merged to dev; self-test 71/71 in 11 suites; pond smoke run with the Swampfang brain clean; frames captured | 2026-10-19 |
