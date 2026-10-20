# Spirewalker: review renders

`tools/monster_preview_spirewalker.gd` (windowed) writes `spirewalker_view_<front34|side|back34>.png`
in `aggravated_idle` and `spirewalker_<clip>.png` for every clip at its `key` time
(HHSpirewalkerClips.CLIPS). Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_spirewalker.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview_spirewalker.gd`.

Reference: `design/kickoff/ref/monster_spirewalker.png` (a flat, broad, plant-backed
lizard). Scale bar in every shot: the player rig's 2.2 m capsule; the ground carries
the 1 m hex grid. Body: 2714 tris, 7.6 m across the claws, 7.9 m nose to tail, the
carapace top at 1.9 m, the reed tips at 3.8 m; radius-2 footprint.

## Rounds

1. Six legs read as a crab splay from every angle; the carapace is flat (rz 0.84 on
   rx 2.05); the reed bed with violet beads reads; forearm bristles and the horn
   crown show. Shortcomings: 8.4 m across the claws (brief: ~7 m); the horns stood
   up mid-skull instead of raking off the crown; the eyes were small; the mottle
   hides under the reeds (only the tail shows it). Clips: `forearm_punch` and
   `barb_throw` swung the arms the wrong way and `walk` planted the foot behind
   (the `_arm` / `_leg` yaw sign was reversed: on a +X bone a +yaw moves the tip
   backward); `leaping_squash` barely whipped the reeds; `calm_soak` sank the snout
   into the floor; `collapse` rotated the knees so far the shins went through the
   floor; `death` rolled 62 deg onto its side, which buried the reeds and left three
   legs pointing straight up. `reeds_fold`, `reed_lash`, `pollen_shake`, both
   breaths, `spore_spread`, `hit_react`, `stagger`, `reeds_burnt_idle` read.
2. Legs narrowed (7.6 m), horns raked back off the rear of the skull, eyes 0.21 m,
   one more reed per row. Yaw sign flipped in `_arm` and `_leg`: `barb_throw` now
   throws both forearms forward with the bristles leading, `walk` plants ahead and
   pushes back. Squash reeds whip 65 deg forward over the head. Collapse keeps the
   shins on the ground. Death rewritten: a wide flat body never rolls over; it
   collapses, the legs fold under, it lists 18 deg and the head drops aside.
   Remaining: `forearm_punch`'s contact read as a stomp beside the head; death's
   raised-side legs stuck up.
3. Punch hammers out past the snout (arm_l socket goes from (2.6, 0.9, 2.35) to
   (0.28, 0.43, 3.66) at contact); death legs fold under (hip 38 / knee -52).
   `tail_drag`'s sweep was invisible from above: a 100 deg yaw spread toward the
   tip of a 2 m tail curls it only 0.8 m sideways; the bend now runs from the base
   (falloff 0.5) with the tail lifted 20 deg through the sweep, and the camera moved
   behind. Accepted.

## Known, accepted at this scale

- Limb joints are hard intersections (box feet, tube legs); the body loft is continuous.
- The reeds are thin double-sided blades; from straight behind the far rows thin out.
- The violet beads are the resting hint of the charge arcs; the real arcs and the
  sparks between the reeds are view FX (Lane P), driven by `u.charge` (H345).
- The mottle shows on the tail and flanks; the carapace top is under the reeds.
- The tail is short (2 m) and flat: the drag's danger shape (a half ring) does the
  work; the body sells the swing with the hips and a lift.
