# Swampfang: review renders

`tools/monster_preview.gd` (windowed) writes `swampfang_view_<front34|side|back34>.png`
in `aggravated_idle` and `swampfang_<clip>.png` for every clip at its `key` time
(HHSwampfangClips.CLIPS). Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_swampfang.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview.gd`.

Reference: `design/kickoff/ref/monster_swampfang.png`. Scale bar in every shot: the
player rig's 2.2 m capsule; the ground carries the 1 m hex grid.

## Rounds

1. Every colour washed out (frill white): vertex colours written to Blender's
   scene-linear `.color`; fixed with `color_srgb`. Frill was a star of needles from
   one point: rebuilt as webbed fans rooted around the neck ring. Eyes inside the
   skull (x 0.6 < ring half-width 0.72): moved out and enlarged, skull widened.
   Death-roll rolled about the ground origin (only the feet showed): `_roll_about`
   pivots on the body axis. Dark spray whipped the nose 41 deg into the floor:
   whip reduced to ~14 deg. Calm float showed the whole back: sunk to the eyes.
2. Hide right, every other role white: Blender 5.2's exporter writes `COLOR_0`
   white for every primitive after the first that shares a colour attribute
   (primitive_extract.py stores the key instead of `COLOR_0`). Probed the .blend
   (colours correct), the glb (white past the first primitive) and Godot (same).
   Fixed by exporting one mesh object per role (H303).
3. All roles coloured; frill reads as a gill collar; eyes visible; roll belly-up
   with legs tucked; walk stride and bite-back read. Dive's tail slap was under
   the surface at its key: slap moved to 1.15 s with hips held up and the paddle
   lifted 75 deg. Thrash camera moved overhead to see the whip.
4. All sixteen clips rendered: dive shows the paddle slapping with the head under;
   water_jet thrusts jaws-open on a braced stance; surface_lunge bursts
   near-vertical, frill flared; hit_react, stagger, collapse, death (onto its
   side) read. Accepted.

## Known, accepted at this scale

- Limb joints are hard intersections (box knees); the body loft is continuous.
- The frill web's inner face is the shadow side (dark red) from behind.
- Submerged clips (calm_float, swim, dive end) sink through the ground plane here;
  in the pond the water surface sits at the floor height, which is the intent.
