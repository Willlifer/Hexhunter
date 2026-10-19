# HANDOFF

## Where
`<repo>`, branch `dev`. No remote (H6). Godot 4.7 console binary in Downloads (CLAUDE.md). Playable exe: `dist\Hexhunt.exe` (opens the pond fight).

## Where it stands (2026-10-19, night)
Phase 1 First Fight is built. All four lanes merged to dev: P (lance kit, auto-attack, HUD, F1 panel, telegraphs, HHSfx), C (pond generator, bench `--bench`, arenas/pond.json), E (rigkit Blender builder, Swampfang glb + 16 clips + brain), F (sfx manifest, MIDI loops outside the repo). Self-test 71/71 in 11 suites. Pond smoke run with the brain is clean.
Waiting on the author's Phase 1 gate (L-7): play lance vs Swampfang in the pond and call the feel.

## Do this first
1. Author plays `dist\Hexhunt.exe`. Notes go into DECISIONS (Author rows) and HHTune / HHSwampfang.TUNE.
2. L-9: trigger hit_react / stagger / collapse / death clips on the body from sim events (hurt, stagger, death).
3. On the gate: Phase 2 fan-out (PLAN §3): lanes A weapons, B weapon animation, C biome tooling, D maps, E three monsters, F music handoff.

## Run
`test.bat`. `run.bat` (pond fight) or `run.bat --sandbox` (paint tool). `run.bat --bench` (pond bench). Smoke: `godot --headless --path . -- --arena pond --fight swampfang --autoplay --seconds 40`. Shots: `run.bat --arena pond --fight swampfang --shot design/art/shots --cam 24,48 --seconds 24`. Monster previews: `godot --path . --script res://tools/monster_preview.gd`.

## Open questions
- Feel: thrash_splash hits 15% on a 42-hex ring every ~3.7 s; the bot cannot dodge it, a human should. The author decides.
- LEDGER L-2 (windowed checks not in CI), L-3 (light's ring on grass), L-4 (FX cards), L-8, L-9.
