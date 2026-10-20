# Spirewalker: review renders

`tools/monster_preview_spirewalker.gd` (windowed) writes `spirewalker_view_<front34|side|back34>.png`
in `aggravated_idle` and `spirewalker_<clip>.png` for every clip at its `key` time
(HHSpirewalkerClips.CLIPS). Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_spirewalker.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview_spirewalker.gd`.

Reference: `design/kickoff/ref/monster_spirewalker.png` (a flat, broad, plant-backed
lizard). Scale bar in every shot: the player rig's 2.2 m capsule; the ground carries
the 1 m hex grid.

Rig v2 (Phase 3.5): 5802 tris, 7.5 m across, 7.8 m nose to tail, the back at 2.1 m, the
mound at 2.6 m, the tallest reeds at 4.2 m; radius-2 footprint; 58 bones (adds the
four whip vines `vine_<k>_0..4`). Roles hide / belly / mound / frond / reed / bristle /
arc / mouth / teeth / eye / claw; the vines are `reed`, so the charge glow and the
burnt state reach them like the reeds. Built by `build_monster_spirewalker.py` with
`monster_rig/ext_spirewalker.py` (mound, reed bed, fronds, vine thorns, bristles,
horns; the head reuses `ext_swampfang`'s skull and jaw builders) on
`monster_rig/shapes_mb.py`.

## Phase 3.5 gauntlet (Lane MB)

`godot --path . --script res://tools/monster_preview_spirewalker.gd -- --gauntlet N`
renders the reference's pose and camera (`aggravated_idle`, from its front-left, 8 deg
up) and writes `design/visual_pass/MB/spirewalker_round<N>.png` (reference left,
render right) plus the three turntable views. Text wins over the image: six limbs,
copper reeds, mustard and ochre; the reference supplies the squat toad body, the head,
the planted legs and the plant mass on a mound with fronds and trailing whips.

0. Baseline (`spirewalker_round0.png`). Five biggest differences: (1) silhouette and
   proportions: a spider (long thin legs lifting the body, knees above the back) where
   the reference is a low heavy toad hugging the ground; (2) posture: up on stilts,
   not planted; (3) signature features: a thin brush of reeds straight off the back,
   no mound, no fronds, no whip vines, a flat narrow head without the wide grin and
   brow; (4) palette: one pale yellow everywhere, no darker back; (5) surface: smooth
   tubes, small dark claws.
1. Rebuilt body (`spirewalker_round1.png`). A broad low toad body (belly at 0.45 m), a
   wide flat skull with a heavy brow, a deep grinning jaw with eight teeth a side and a
   red mouth; six short thick limbs with the elbows jutting out level and broad paws
   with long pale claws; a dark-ochre mound on the back; a denser reed bed (7 rows of
   up to 10) rooted on the mound and tallest in the middle (a spire); eight fronds
   round the mound's base; four thorned whip vines on bones. Look: the toad reads; the
   vines were thick rods and the flank pair hung to the ground (read as extra legs
   from behind); the fronds were small and pale.
2. Vines thinned (7.5 to 3 cm) and re-pathed up and back with a curled tip, clear of
   the ground; fronds longer and wider, olive. Look: fronds now read as a leaf skirt,
   but stuck out flat like plates; the hide read too bright; the forearm bristles
   formed a cage of slats; the eyes hid under the brow.
3. Fronds droop over the flanks; hide dustier (0.75, 0.58, 0.22) with more ochre
   mottle; bristles in two directions, shorter; eyes larger and further out. Look: the
   comparison now matches the reference's read: squat body, grin, planted claws, plant
   mass with a leaf skirt and trailing whips. Remaining: the reed bed is a spire of
   blades, not a trunk with a flower (text wins: a reed bed).
4. Clip pass, no geometry change (`spirewalker_round4.png`, the final comparison).
   The vines were static in every clip: a vine layer now runs after every clip pose:
   `reed_lash` coils them back and whips them up and over the back toward the head at
   1.2 s (contact), `leaping_squash` folds them with the reeds and whips them on the
   slam, `pollen_shake` shakes them, `reeds_fold` lays them flat, `reeds_burnt_idle`,
   `collapse` and `death` droop them, idles sway them. Every clip re-rendered at its
   key time and looked at.

Verdict: closer, yes. The spider is gone: a squat, planted toad-crab with a plant
mound, a grin and whip vines; six limbs and the copper reeds kept from the text.

## Phase 2 rounds (Lane E)

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
