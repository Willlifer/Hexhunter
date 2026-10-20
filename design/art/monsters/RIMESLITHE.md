# Rimeslithe: review renders

`tools/monster_preview_rimeslithe.gd` (windowed) writes `rimeslithe_view_<front34|side|back34>.png`
in `aggravated_idle` and `rimeslithe_<clip>.png` for every clip at its `key` time
(HHRimeslitheClips.CLIPS). Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_rimeslithe.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview_rimeslithe.gd`.

Reference: `design/kickoff/ref/monster_rimeslithe.jpg` (the hunched, long-armed
quadruped with shoulder clusters). Scale bar in every shot: the player rig's 2.2 m
capsule; the ground carries the 1 m hex grid. 1872 triangles, 9.5 m nose to tail,
3.6 m at the top of the hump, 4.65 m to the crystal tips, 5.15 m across the fists.

## Rounds

1. Silhouette: the hunch and the long forearms read (forearm 2.65 m on a 1.0 m upper
   arm, knuckles 4.35 m ahead of the hips), crystals read as clusters. Shortcomings:
   the horns were flat blades seen edge-on (a black line); the crystals rendered
   bright pale already (they should be smoky grey at rest); hind legs thin for the
   mass; the hump a smooth arc. Clips: the head rested at 1.6 m, so bite, mist_breath,
   freeze_pillar, stagger and calm_sit all pushed the snout through the floor; roar
   pitched the root 22 deg about the ground origin and stood the body on its tail;
   shoulder_charge lifted the leading fist to head height; meteor_drop's key (1.0 s)
   and camera side hid the throwing arm. Root causes fixed: head carried at 2.1 m
   (neck/skull/snout stations raised 0.25 m, jaw, teeth, eyes, sockets with it),
   hump raised 0.1 m, horns rebuilt as solid pyramids (ext crystals, claw role),
   crystal palette darkened, hind radii 0.4 -> 0.5, elbows out to x 2.0; roar reworked,
   neck pitches halved in the clips, meteor key 1.45 s and camera yaw 250.
2. Head clear of the floor in every clip; horns, hind legs, smokier crystals right.
   Roar still near-vertical: measured numerically (a probe script, not kept): the
   spine bend of -26 deg over four bones lifted the head 1.3 m and shoulder -40 /
   forearm -30 put the fists at 6.3 m. calm_sit sank the hind toes 0.49 m under the
   floor (the root drop with no leg fold). The "loose foot" in collapse/death is a
   fist whose forearm is inside the lowered belly, not a detached part.
3. Probed fold angles: root -0.3 with hind hip +12 / knee -18 keeps the toe at the
   floor (y 0.10) and arm 8 / -12 / 8 keeps the knuckles there; roar now bends the
   spine -12, root -6, arms -25 / -10. Renders: roar rears on planted hind legs, jaws
   wide, fists a metre up; calm_sit folds with toes and knuckles down; cold_slam's
   planted-fists tell reads (both fists on the floor, wider than the stance; the
   test checks it); collapse belly-flat with chin down; walk stride and arm swipe
   read; the back view shows the clusters on shoulders and spine.
4. Roar's leading arm reached a little high: arms -18 / -8. Accepted: roar, death
   (on its side), stagger (sags, head low, no clipping), hit_react, freeze_pillar.

## Known, accepted at this scale

- Limb joints are hard intersections (balls at shoulder, elbow, wrist); the fist is
  a block with a knuckle ridge and curled claws.
- In collapse and death the arms sink into the belly; the fists stay visible beside
  (or, rolled, beyond) the body.
- The crystals are one flat smoky grey (vertex colour). The cold glow (smoky grey ->
  pale cyan with `u.cold`) is a material tint on the `crystal` role, a Request to the
  body's owner; nothing in the renders shows it yet.
