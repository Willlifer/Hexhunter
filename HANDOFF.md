# HANDOFF

## Where
`<repo>`, branch `dev`. No remote (H6). Godot 4.7 console binary in Downloads (CLAUDE.md). Playable exe: `dist\Hexhunt.exe` (re-export with `godot --headless --path . --export-release "Windows Desktop" dist/Hexhunt.exe`).

## Where it stands (2026-10-19, evening)
Phase 0 gate passed (H26). Author's gate notes applied: walk 10 ticks/hex, run 7 (H22); arena 50 m across (H23); tile charge lasts 3x (H24); left-click becomes the auto-attack, paint stays a sandbox tool (H25). Self-test 35/35, smoke clean.
Phase 1 is open. Merged to dev: Lane P (lance kit, auto-attack, HUD, F1 panel, telegraphs, brain/monster_move contracts), Lane F (sfx + HHSfx; MIDI in D:\Music Studio\Claude Playground\hexhunt), Lane C (pond generator, bench via --bench, arenas/pond.json; the exe opens on the pond). Lane E (Swampfang rig, clips, brain) still in its worktree.

## Do this first
1. Lane P: `src/core/sim.gd` orders for `attack` (left-click target), `cast {skill, aim}`; lance skills as data in `src/weapons/lance.gd`; HUD bar; F1 tune panel.
2. When a lane hands back: run its suite + the full self-test in its worktree, merge to `dev`, re-export the exe for the author.
3. Phase 1 gate (L-7): the author plays lance vs Swampfang in the pond.

## Run
`test.bat`. `run.bat` or `dist\Hexhunt.exe`. Shots: `run.bat --shot design/art/shots --cam 34,44`.

## Open questions
- None blocking. LEDGER L-3 (light ring on grass), L-4 (FX cards), L-2 (windowed checks not in CI).
