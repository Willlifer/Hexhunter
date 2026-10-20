# HANDOFF

## Where
`<repo>`, branch `dev`. No remote (H6). Godot 4.7 console binary in Downloads (CLAUDE.md). Playable exe: `dist\Hexhunt.exe` (opens the pond, lance). Re-export: `godot --headless --path . --export-release "Windows Desktop" dist/Hexhunt.exe`.

## Where it stands (2026-10-19, late)
Phase 2 is built and merged: weapons (glaive-lance, karambits, winged bow; daggers and bow kits), the rigged hunter with every weapon clip, four arenas (pond, cave, glade, caldera with pillars / vents / lava / sun / shade cells), four monsters (Swampfang, Colambros, Rimeslithe, Spirewalker) with brains and clips, potions on T. Self-test 165/165 in 23 suites. All four fights smoke-run clean on their biomes; frames in design/art/shots/<biome>/.
Waiting on the author's Phase 2 gate (L-10).

## Do this first
1. Author plays: `run.bat --arena caldera --fight colambros --weapon daggers`, `--arena cave --fight rimeslithe --weapon bow`, `--arena glade --fight spirewalker`, and the pond. Notes -> DECISIONS Author rows and the F1 panel.
2. L-12: the visual state hooks (quill glow, crystal tint, reed arcs, status icons).
3. Phase 3 (PLAN §3): hunt loop (world map, disturbance, cutscene, prep screen with element choice), drops, three upgrade slots per skill.

## Run
`test.bat`. `run.bat [--arena pond|cave|glade|caldera] [--fight swampfang|colambros|rimeslithe|spirewalker] [--weapon lance|daggers|bow] [--sandbox] [--seed N]`. `run.bat --bench` (all four generators). Previews: `godot --path . --script res://tools/player_preview.gd`, `res://tools/monster_preview_<id>.gd`, `res://tools/weapon_preview.gd`.

## Open questions
- Roared shapes are huge (L-11). Author decides after play.
- LEDGER L-2 (windowed checks not in CI), L-3, L-4, L-8, L-12, L-13.
