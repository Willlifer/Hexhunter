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

The author's tracks (H431): 4-bar loops at 120 BPM (~8 s) and two stings,
44.1 kHz 16-bit WAV, imported as QOA (looping set in each `.import`). The
originals, as the author named them, sit in `audio/source/` (git-ignored,
`.gdignore`d); `audio/music/` holds the clean-named copies the game plays.
`HHMusic` (src/game/music.gd) picks them:

| track | where |
|---|---|
| sting_title | once, on the first screen |
| lobby_1_drums -> lobby_2_chords_melody -> lobby_3_chords_bass -> lobby_4_full | lobby and world map: one layer more each loop, then the full mix holds |
| prefight_a, prefight_b (every third loop) | the ambush and the hunt's prep lobby |
| sting_fight, then fight | a fight starts |
| fight_enrage | from the next loop once the monster is below half HP or enraged (NORMAL) |
| victory | once on a win, then the lobby build again |

Not used: "Basic Drums and Chords" (0.63 s; it reads like a cut-off export).
Level: `music_db` / `music_on` on the F1 panel (the Music bus).
