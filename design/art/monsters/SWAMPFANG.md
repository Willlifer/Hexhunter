# Swampfang: review renders

`tools/monster_preview.gd` (windowed) writes `swampfang_view_<front34|side|back34>.png`
in `aggravated_idle` and `swampfang_<clip>.png` for every clip at its `key` time
(HHSwampfangClips.CLIPS). Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_swampfang.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview.gd`.

Reference: `design/kickoff/ref/monster_swampfang.png`. Scale bar in every shot: the
player rig's 2.2 m capsule; the ground carries the 1 m hex grid.

Rig v2 (Phase 3.5): 2674 tris, 9.76 m nose to tail, 4.05 m to the sail tips, 33 bones
(adds `fin_0..fin_2`, the sail fold bones), roles hide / belly / frill / fin / mouth /
teeth / eye / claw. Built by `build_monster_swampfang.py` with `monster_rig/ext_swampfang.py`
(skull, deep jaw, throat, brows, sails, plates) and `monster_rig/shapes_mb.py` (the
shared Lane MB primitives: loft, sail, leaf, boss, thick limb).

## Phase 3.5 gauntlet (Lane MB)

`godot --path . --script res://tools/monster_preview.gd -- --gauntlet N` renders the
reference's pose and camera (`dark_spray` at 1.3 s: jaws open, head forward; from its
left, 8 deg up) and writes `design/visual_pass/MB/swampfang_round<N>.png` (reference
left, render right, `tools/gauntlet_compare_mb.gd`) plus the three turntable views.
`-- --water` renders the submerged clips under a water plane at the gameplay camera
(`design/visual_pass/MB/swampfang_water_*`). The author's verdict on the old model was
"looks and acts great": every change below moves toward the reference without
touching the colours, the frill, the eyes, the weak hind legs or a clip name.

0. Baseline (`swampfang_round0.png`, the Phase 2 rig in `frill_roar`). Five biggest
   differences: (1) silhouette: a thin pointed snout and a box lower jaw where the
   reference has a massive skull and a deep jaw; low back, thin tube forearms;
   (2) posture: comparable (low, front-heavy), the head too small to lead it;
   (3) signature features: no cream throat, small spike fins instead of the big swept
   sails, no back plates, small hands; (4) palette: blue / lavender and the red frill
   right, but no cream anywhere to break the blue; (5) surface: smooth tubes.
1. New head and limbs (`swampfang_round1.png`). The skull is its own loft (wide brow,
   long broad snout, flat dark-red palate), the lower jaw a deep loft (red mouth on top,
   cream under, six teeth a side), a cream throat pouch runs from the jaw hinge to the
   chest, heavy brow ridges over the eyes. Front legs are muscled limbs (upper-arm and
   forearm bulges), broad paws, three fingers with long pale claws. Four swept red
   sails (crest, two dorsal, tail) with ribs and a dark-root-to-bright-tip ramp.
   Raised hex plates down the back and tail. Look: the head and arms read like the
   reference now; the plates were too many and too tall (a studded turtle); the throat
   hid in shadow; the snout tip pinched.
2. Plates cut to one row a side, 7 cm tall; the snout widened and deepened; the throat
   deepened and moved back to the chest; the front sail swept further back. Look: the
   back reads as scaled, not studded; the throat still read grey in shadow.
3. The cream goes higher: the throat's lower 80% and the body belly from 0.12 below the
   axis (was 0.3). Look: the cream throat and belly band now show in the side view as
   in the reference. Remaining gap: the reference holds its head high on an arched
   neck; ours carries it level with the back (the clips set the head, and every clip
   was tuned on that neck: left).
4. Clip pass, no geometry change (`swampfang_round4.png`, the final comparison). The
   sails got fold bones because they broke the kickoff's calm ("floats half-submerged,
   only the frill showing"): `calm_float`, `swim` and the end of `dive` lay them flat,
   `surface_lunge` and `frill_roar` snap them up, `aggravated_idle` ripples them,
   `collapse` droops them; `calm_float` and `swim` also drop the tail so the tail sail
   stays under, and the submerged depth went from 2.1 to 2.5 m (the taller skull broke
   the surface while swimming). Every clip re-rendered at its key time and looked at.

Verdict: closer, yes. Head, jaw, throat, arms, plates and sails all moved toward the
reference; colours, frill and behaviour unchanged.

## Phase 2 rounds (Lane E)

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
