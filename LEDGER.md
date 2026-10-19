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
| L-7 | Phase 1 gate: the author plays lance vs Swampfang in the pond start to finish and calls the feel | AWAITING PLAY | after lanes P, C, E merge to dev |
| L-2 | Windowed checks (`--shot`, the sandbox) are not in CI; CI runs import, self-test and the headless smoke run only | WATCH | A software-rendering capture on CI is open; the local command is `run.bat --fight swampfang --shot design/art/shots --cam 30,42` |
| L-3 | Element shaders were tuned for a white tile (Black | White); on natural ground the dark face and the glaze read, fire and water read, light's dark ring may need retuning on grass | WATCH | Lane C / Lane P judge on the pond |
| L-4 | Tile-effect "cards" (standing flames, light column, dark tendrils) are copied in but not yet drawn by HHArenaView | OWED | Lane P when the fight view is built |
| L-5 | Monster stub: `add_monster` has a footprint and HP only; no brain, no body | OWED | Lane E |
| L-6 | GitHub remote not created (H6: only when asked); `.github/workflows/ci.yml` is ready for it | DEFERRED | Author asks |

## Settled

| ID | Item | Date |
|----|------|------|
| S-1 | Phase 0 foundation: import clean, self-test 35/35, smoke run clean, rendered frames captured | 2026-10-19 |
| S-2 | Phase 0 gate passed by the author (faster walk, 50 m arena, 3x tile life; left-click will be the auto-attack) | 2026-10-19 |
