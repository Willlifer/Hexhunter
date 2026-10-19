# Hexhunt

A co-op hunting game in Godot 4.7 (GDScript, no plugins). A party of 1-4
with medieval weapons and elemental attunement hunts four rampaging monsters
in 35 m arenas. Third-person MMO camera, OSRS-style true-hex movement, League-
style Q/W/E/R kiting, Black | White's element reactions painted on the ground.
The author's kickoff is preserved verbatim in `design/kickoff/KICKOFF.md` with
the reference images beside it; read it for intent, DECISIONS for the rulings.

## Start here

1. `HANDOFF.md`: the state right now and what to do first.
2. `LEDGER.md`: what is owed, blocked, awaiting play, or settled.
3. `PLAN.md`: phases, gates, lanes. The gate the author checks next is at the top.
4. Open only the guide leaves your task needs (below).

## Which doc answers what (and which wins)

| Doc | Answers | Lifespan |
|---|---|---|
| `guide/*.md` | **How the game works now**: layout and run, core contracts, mesh pipeline, lanes. Current truth. | Edited in place |
| `DECISIONS.md` | **Why and when** a rule became what it is, and who ruled (Author / Claude / both). Append-only; superseded rows marked in place. | Permanent |
| `LEDGER.md` | What's owed, blocked, awaiting play, or watched. One row per item, four-test rule. | Weeks |
| `HANDOFF.md` | State now and what to do first. Rewritten each session, 40 lines or fewer. | One session |
| `PLAN.md` | Phases with gates, lanes with owned files and DECISIONS blocks. | Project |
| `design/kickoff/` | The author's brief and reference images. Historical intent. | Permanent |
| `history/` | Session summaries. Orientation only. | Permanent |

If a guide leaf and DECISIONS disagree, the guide is current unless the DECISIONS row is newer. Then fix the guide.

## Guide leaves

- `guide/01-layout-and-run.md`: folders, the Godot binary, every command, the self-test, review renders.
- `guide/02-core-contracts.md`: HHHex, HHArena, HHCharge, HHSim, HHPhases, HHFormulas, HHTune. What each owns and what a lane may call.
- `guide/03-mesh-pipeline.md`: Blender for rigs and weapons (Black | White's build scripts), GKMesh for arenas and props, manifests, previews, tests.
- `guide/04-lanes.md`: the lane protocol (worktrees, owned files, DECISIONS blocks, merge rule).

## Run and verify

The console binary is `<godot>`.
Run from the repo root:

- `--headless --path . --import`, after adding scripts or classes.
- `--headless --path . -- --self-test`: all suites, exit 0 or 1, JSON report. **Must be green.**
- `--headless --path . -- --fight swampfang --autoplay`: the smoke run. Zero `SCRIPT ERROR` lines.
- `--path . -- --fight swampfang --shot design/art/shots --cam 30,42`: real rendered frames for review.
- `test.bat` does import + self-test. `run.bat [args]` opens the sandbox windowed.

`--seed N` fixes the sim. Tests and the smoke run default to seed 1.

## Standing author preferences

- **The author verifies by playing** and by looking at renders. Show images and say what you looked at. Never claim visuals you didn't see; never forge a test result or a number.
- **Minor ambiguities:** make the call that makes the game more fun or more emergent, log it in DECISIONS as "Claude, decided", keep going. Ask when it is genuinely the author's call.
- **Monsters are weight.** Slow, telegraphed, heavy; ground shapes show danger before it lands. Colambros is the one fast exception.
- **Feel numbers live in `src/core/tune.gd`** and the F1 panel, never scattered.
- **Reuse, don't port blindly.** Gamers Gauntlet's `game/src/core` and `src/game` are a copy of Black | White; take core code from Black | White itself, kit code from Gauntlet's `src/kit`.

## Project rules

- The rules core (`src/core`) never touches nodes. Every combat number goes through `HHFormulas` with a breakdown. Seeds reproduce; `HHSim.state_hash()` proves it.
- The sim is order-driven: every action is an order into `step()`. Co-op later is wiring, not a rewrite (H7).
- Content is data: arenas are JSON (`arenas/`), monsters and weapons carry manifests.
- Parallel lanes: each has an owned file set and a reserved DECISIONS block (PLAN §6). No lane edits another lane's files; shared contracts change only through the integrator.
- Git (H6): work on `dev`; `main` moves only at a phase gate. Lanes are worktrees off `dev`, merged by the integrator after their suite and the full self-test pass.
