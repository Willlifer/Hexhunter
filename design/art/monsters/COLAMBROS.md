# Colambros: review renders

`tools/monster_preview_colambros.gd` (windowed) writes `colambros_view_<front34|side|back34>.png`
in `aggravated_idle` and `colambros_<clip>.png` for every clip at its `key` time
(HHColambrosClips.CLIPS). Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_colambros.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview_colambros.gd`.

Reference: `design/kickoff/ref/monster_colambros.png` (a brute wyvern standing tall on
its hind legs). Scale bar in every shot: the player rig's 2.2 m capsule; the ground
carries the 1 m hex grid. The rest pose is the biped stance (H320); `run` and `charge`
drop it to all fours.

## Rounds

1. Looked at all 21 PNGs. Colour, the hyena-lizard head, the ears and the quill ridge
   (bone spikes darkening to the points) read at once. Wrong: every rear FOOT floated
   below its shin: the ankle sat 0.52 m up and rigkit snaps the foot box to the ground,
   so the wrist ball never bridged the gap (worst in `walk`, the swing foot was a loose
   block). The biped stance read as a horizontal lizard: the forequarters were only
   0.6 m above the hips. `run`'s arm paws hovered 0.3 m up. `back_roll` was entirely
   under the floor: the roll pivoted on an axis at 0.85 m and the root was dropped
   again on top. `tail_lash` whipped 150 deg and tucked the tail under the body.
   `leap_stomp` keyed before the squash. `quill_gnaw` could not reach the flank.
2. Ankles lowered to 0.30 m (feet attached everywhere); forequarters raised ~0.35 m
   (chest 2.62, skull 3.0: the biped reads, the player looks it in the eye); arms
   lengthened and the quad stance pitched 32 deg so the paws reach the ground;
   back_roll pivots on the hips' height and drops 0.9 m (now lies on its back, belly
   up, legs kicking in the windmill); tail_lash 100 deg (the sweep is visible from
   above); leap keyed at 1.48 s (a visible squash); gnaw curls the spine 42 deg
   (the head reaches the flank). In `run` the rear thigh popped above the back line at
   the bound's peak.
3. Bound hip amplitude 28 -> 20 deg, quad drop 0.36: the sprint reads as a low
   all-fours gallop with the ridge rippling. Looked again at the three views and
   `run`, `charge`, `aggravated_idle`, `bald_idle`, `hit_react`, `collapse`, `death`:
   all read. Accepted.

## Known, accepted at this scale

- Limb joints are hard intersections (H302); the arms are three tubes and a paw box.
- Quills are opaque spikes; "glowing tips" when smouldering is a view-side material
  change on the `quill` role (Requests).
- The bald window flattens the quills along the spine rather than removing them.
