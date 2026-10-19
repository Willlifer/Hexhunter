# audio

Lane F. Sound effects and the handoff to the author's music.

## sfx/

Borrowed unchanged from Gamers Gauntlet `game/audio/sfx` (H15). Both the
`.wav` (44.1 kHz 16-bit PCM, mastered to -16 LUFS, -1 dB peak) and the `.ogg`
of every variant are here; Godot imports both, play the `.ogg` in builds and
keep the `.wav` as the master. `sfx/sfx.json` lists each sound with its
variant count, bus, loop flag, per-variant levels, and a `use` naming the
Hexhunt event it is for. `copy_from_gauntlet.py` re-does the copy and
rewrites the manifest; run it with `python -I` if Gauntlet's sounds change.

| use | sounds |
|---|---|
| paint:fire / water / ice / thunder / wind / dark / light | elem_fire, elem_water, elem_ice, elem_thunder, elem_wind, elem_dark, elem_light (3 each) |
| detonate | tile_detonate (3) |
| gale | tile_gale (2) |
| overfreeze | tile_glaze (2) |
| overheat | hit_crit (3) |
| douse | cast_whoom (3) |
| hurt | hit_flesh (4), hit_glance (3) |
| stagger | hit_block (3) |
| death | ko_thud (2) |
| step | step_stone (6) |
| swing | swing_light (4), swing_heavy (3), hit_miss (3) |
| bow | bow_draw (2), bow_release (3), arrow_thunk (3) |
| heal | heal (2) |

Playback wiring (an `HHSfx` helper that picks a random variant per event) is
not here yet; it belongs to whichever lane first plays a sound, through the
integrator. `tests/test_audio_sfx.gd` checks every listed file exists and
every required event has at least one sound.

## Music

Not in the repo. The drum loops and chord MIDI live in
`D:\Music Studio\Claude Playground\hexhunt\` (script, `midi/`, README). The
author mixes them in Ableton and writes the melody; finished loops come back
here as `audio/music/*.ogg` in Phase 2.
