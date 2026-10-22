# 04 Lanes

A lane is one Claude Code session in its own git worktree off `dev`, with an owned file set and a reserved DECISIONS block (PLAN §6). The integrator is Lane P (session 0 until Phase 1 starts).

## Protocol
1. `git worktree add ../hexhunt-<lane> -b lane/<lane> dev` from the repo root.
2. Work only in the owned paths. A needed change outside them is a request to the integrator (a line in HANDOFF under "Requests"), never an edit.
3. Log calls in DECISIONS inside the lane's block, as `Claude, decided` or `Author`.
4. Before handing back: `test.bat` green in the worktree, the lane's own suite present, preview renders captured where a mesh or scene was made.
5. The integrator merges `lane/<lane>` into `dev` (after the full self-test), then `git worktree remove`.

## Phase 1 lanes

| Lane | Owns | Block | Delivers |
|------|------|-------|----------|
| P | `src/game/**`, `src/core/**`, `tests/test_play_*`, `tests/test_core_*` | H400-H449 | lance kit (Q Pierce, W Exchange, E Guard, R Eruption), basic attack, target + walk-into-range, stagger/statuses on hit, HUD bar, F1 tune panel, fight.gd integration |
| C | `src/arena/**`, `arenas/**`, `tests/test_arena_*` | H200-H249 | pond generator (GKDef), water depth + lilypad cover cells, bench tool, JSON export, preview |
| E | `src/monster/**`, `art/monsters/**`, `tools/blender/build_monster_*.py`, `tests/test_monster_*` | H300-H349 | Monster Rig Builder, Swampfang model + clips, brain (calm/aggravated/threatened), telegraphed attacks as hex sets |
| F | `<music workspace>\hexhunt\**`, `audio/**` | H350-H399 | 4-5 drum loops at 120 BPM, chord MIDI, sfx copy-in from Gauntlet |

Shared contracts (`guide/02-core-contracts.md`) change only through Lane P. Lane E and Lane C get a stub in `src/core` from Lane P if they need a hook that does not exist yet.
