# HANDOFF

## Where
`<repo>`, branch `dev`. No remote (H6). Godot 4.7 console binary in Downloads (CLAUDE.md). Playable: `dist\Hexhunt.exe` opens the lobby; beside it `Lobby.bat`, `Hunt.bat` and twelve fight bats. Re-export: `godot --headless --path . --export-release "Windows Desktop" dist/Hexhunt.exe`, then copy `launchers/*.bat` into `dist/`.

## Where it stands (2026-10-20, co-op)
Phases 0-3 and the visual pass passed. Phase 4 co-op merged: host-authoritative state streaming over ENet (src/net: HHNet, HHSession, HHSnapshot, HHReplicator; 11.7 KB/s per client with four hunters), sim co-op rules (four spawns, monster HP x1.6 per extra hunter, downed + revive, aggro with a 2 s commit; H53, H54), the game side (party fight with nameplates, rings and party frames, lobby "Play together" panel, co-op hunt loop, --host / --join / --name / --port / --peers, Host.bat / Join.bat), the host leaving ends the fight for all (H55). Self-test 288/288 in 39 suites. Two real processes and the exported exe agree as host and client.
Then the combat-feel pass (H56-H58, Lane W, H950-H970): charged Q on all weapons, Shift dash (2 charges), thrown heal-zone potion, range rings, run 6 m/s, 0.3 s recovery, dash/movement-skill escapes, lance/dagger 3-hit strings, facing lock, hit-stop, exposed windows, monster hits interrupt. 327/327 in 41 suites; solo and co-op smoke clean from the exported exe.
Waiting on the author's play (LEDGER L-27 co-op, L-31 combat feel).

## Do this first
1. Author plays co-op on a LAN (Host.bat / Join.bat). Notes -> DECISIONS Author rows.
2. LEDGER L-28..L-30 (internet play, client lag, co-op rough edges).
3. Phase 5: web export (WebSocket transport through HHNet.make_peer, a relay), Vercel, tune pass.

## Run
`test.bat`. `run.bat` (lobby). `run.bat --hunt`. Co-op: `run.bat --host [--name X]`, `run.bat --join <address> [--name X]`; smoke: `--host --port N --peers 2 --arena pond --fight swampfang --autoplay --seconds 20` and `--join 127.0.0.1 --port N --autoplay --seconds 20` in two shells. `run.bat --arena <id> --fight <monster> --weapon <id> [--element e --backup e] [--seed N]`; `--autoplay --seconds N` prints damage by cause. F1 tune panel, F3 debug read-out. Previews: `tools/fx_preview.gd`, `tools/arena_compare.gd`, `tools/gauntlet_compare_{ma,mb}.gd`, `tools/ui_thumbs.gd` (rerun after any model or arena change), `tools/hunt_preview.gd`.

## Notes
- The player's files live in `%APPDATA%\Godot\app_userdata\Hexhunt` (hunter.json, hexhunt_last.json, hexhunt_runs.json, hexhunt_tune.cfg). Worktrees share that folder; the self-test redirects to scratch files. Don't delete the author's files.
- `art/monsters/monsters.json` is edited by every monster lane: merge it row by row (never commit a conflicted file: check for markers).
- Old agent worktrees under `.claude/worktrees` are merged; removing them was blocked by the permission layer.
