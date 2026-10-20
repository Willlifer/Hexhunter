# HANDOFF

## Where
`<repo>`, branch `dev`. No remote (H6). Godot 4.7 console binary in Downloads (CLAUDE.md). Playable: `dist\Hexhunt.exe` opens the lobby; beside it `Lobby.bat`, `Hunt.bat` and twelve fight bats. Re-export: `godot --headless --path . --export-release "Windows Desktop" dist/Hexhunt.exe`, then copy `launchers/*.bat` into `dist/`.

## Where it stands (2026-10-20)
Phases 0-3 passed. Phase 3.5 visual pass merged: monsters gauntlet-tested against the kickoff references (MA: Colambros biped, Rimeslithe hunched dragon; MB: Swampfang sails and jaw, Spirewalker toad-crab with plant mound), wind-up effects for every telegraph plus breath vs charge, arena-event, reaction and skill effects, point lights (FX), arenas and world map (ENV), HUD/lobby/results/ambush (UI). Balance: reactions are multiples of the caster's auto attack with strongest-plus-chain (H50); basics x2.4; each arena fires its own telegraphed event (H51). Self-test 249/249 in 34 suites.
Waiting on the author's look (LEDGER L-22).

## Do this first
1. Author plays the new exe. Notes -> DECISIONS Author rows.
2. LEDGER L-23..L-26 (Rimeslithe fins and cave contrast, cave frame dips, quiet tells, caldera snowline).
3. Phase 4: co-op (PLAN §3).

## Run
`test.bat`. `run.bat` (lobby). `run.bat --hunt`. `run.bat --arena <id> --fight <monster> --weapon <id> [--element e --backup e] [--seed N]`; `--autoplay --seconds N` prints damage by cause. F1 tune panel, F3 debug read-out. Previews: `tools/fx_preview.gd`, `tools/arena_compare.gd`, `tools/gauntlet_compare_{ma,mb}.gd`, `tools/ui_thumbs.gd` (rerun after any model or arena change), `tools/hunt_preview.gd`.

## Notes
- The player's files live in `%APPDATA%\Godot\app_userdata\Hexhunt` (hunter.json, hexhunt_last.json, hexhunt_runs.json, hexhunt_tune.cfg). Worktrees share that folder; the self-test redirects to scratch files. Don't delete the author's files.
- `art/monsters/monsters.json` is edited by every monster lane: merge it row by row (never commit a conflicted file: check for markers).
- Old agent worktrees under `.claude/worktrees` are merged; removing them was blocked by the permission layer.
