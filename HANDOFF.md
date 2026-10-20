# HANDOFF

## Where
`<repo>`, branch `dev`. No remote (H6). Godot 4.7 console binary in Downloads (CLAUDE.md). Playable: `dist\Hexhunt.exe` opens the lobby; beside it `Lobby.bat`, `Hunt.bat` (straight to the world map) and twelve fight bats. Re-export: `godot --headless --path . --export-release "Windows Desktop" dist/Hexhunt.exe`, then copy `launchers/*.bat` into `dist/`.

## Where it stands (2026-10-19, night)
Phase 2 gate passed ("loved all of the fights"; fire tuned down H46). Phase 3 built by four lanes and merged: lobby + shell + registry (Lane L, H450-H460), hunt loop map -> ambush -> prep -> fight -> results (Lane H, H500-H509), twelve upgrades + drops + save (Lane U, H550-H559), monster state visuals + HUD status icons + coloured weapons + cowl (Lane V, H600-H610). Integrator wiring H611-H613: bodies bound to the sim, shell.play returns the fight and takes the hunt's callback, GO HUNTING button and `--hunt`, "Unlock all upgrades (testing)", tests isolated from the player's save. Self-test 227/227 in 29 suites.
Waiting on the author's Phase 3 gate (LEDGER L-16).

## Do this first
1. Author plays: lobby (any setup, unlock and slot upgrades) and a full hunt. Notes -> DECISIONS Author rows.
2. LEDGER L-17 (upgrade balance), L-18 (state glows), L-19 (lobby thumbnails, element hint, run history).
3. Phase 4: co-op (PLAN §3).

## Run
`test.bat`. `run.bat` (lobby). `run.bat --hunt [--seed N] [--weapon id]`. `run.bat --arena <pond|cave|glade|caldera> --fight <swampfang|colambros|rimeslithe|spirewalker> --weapon <lance|daggers|bow> [--element e --backup e] [--seed N]`. Previews: `tools/hunt_preview.gd`, `tools/monster_state_preview.gd`, `tools/player_preview.gd`, `tools/monster_preview_<id>.gd`. `--shot-lobby <dir>`.

## Notes
- The player's files live in `%APPDATA%\Godot\app_userdata\Hexhunt` (hunter.json, hexhunt_last.json, hexhunt_tune.cfg). Worktrees share that folder; the self-test redirects to scratch files (H613). Don't delete the author's files.
- Old agent worktrees under `.claude/worktrees` are merged; removing them was blocked by the permission layer.
