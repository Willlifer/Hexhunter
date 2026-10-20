# Rimeslithe: review renders

`tools/monster_preview_rimeslithe.gd` (windowed) writes `rimeslithe_view_<front34|side|back34>.png`
in `aggravated_idle` and `rimeslithe_<clip>.png` for every clip at its `key` time
(HHRimeslitheClips.CLIPS). `-- --only a,b` renders just those shots; `-- --gauntlet <png>`
only the gauntlet angle. Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_rimeslithe.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview_rimeslithe.gd`.

Reference: `design/kickoff/ref/monster_rimeslithe.jpg`, the lower (Reshiram-like)
creature: a long dragon head low in front, a hunched chest higher than the hips, long
forearms planted like a gorilla's, flowing crest and fin shapes from head, shoulders,
flanks and tail, a long tapering tail. The text wins on palette (dark slate hide,
smoky-grey crystals that turn pale cyan as it chills); the fins are crystal blades and
smoky plates, not feathers. Scale bar: the player rig's 2.2 m capsule; 1 m hex grid.

Model v2 (H652): 3414 triangles, 10.2 m nose to tail, the hump 4.1 m (hips 2.6 m), 5.3 m
to the shoulder-fin tips, 5.1 m across the fists. Forearms 2.3 m with a forearm mass;
rounded fists on four knuckle knobs with curled claws (no box paws); digitigrade hind
legs (`shapes_ma.digi_leg`); a brow ridge; crystal clusters of 3-8 crystals in several
sizes leaning outward on the shoulders, spine and tail root; swept blades in the
`crystal` role (`shapes_ma.plate`): a two-blade horn crest off the brow, a long fin off
each shoulder, a shorter one off each haunch, a dorsal tail fin. Because the blades are
the crystal role they take the cold glow too.

## Visual pass 3.5 gauntlet (Lane MA)

Comparison images (reference crop left, render right): `design/visual_pass/MA/rimeslithe_round<0-3>.png`.
Gauntlet angle: pure side view, head left (yaw 90, pitch 4), `aggravated_idle`.

0. Baseline. (1) silhouette: low and long, the back nearly level, shoulders barely
   above the hips; (2) posture: arms splayed like a lizard's, not planted under the
   chest; (3) signature features: box paws, a short wolf-like head, horns as flat
   spikes, no flowing crest/fin shapes; (4) palette: right per the text; (5) surface:
   crystals as a regular comb.
1. Rebuilt: hump raised to 4.1 m, neck sloping down to a 1.3 m-longer dragon skull,
   gorilla arms with forearm mass and knuckle fists, digitigrade hind legs, horns
   replaced by crest blades, shoulder fins and a tail fin. Looked: hunch and arms read.
   Wrong: a pale bar ran under the body from the jaw to the hind legs; the crest blades
   lay flat (a grey visor from the front); the jaw a pale box; crystals too bright at
   rest; the camera too far out.
2. The bar was the belly strip with inward normals (the per-role split leaves it an
   open strip, bmesh guessed wrong): `shapes_ma.install_normal_fix` votes every island
   outward from the nearest bone, and the spine lofts are capped. Jaw in the hide
   colour, belly band narrower, neck thicker, crystals smokier (0.34 grey), longer
   shoulder fins curling up at the tip, hip fins added. Looked: the body is solid and
   the flowing silhouette appears.
3. Crest blades stood up (normal tilt 0.45 -> 0.12): from the front they read as two
   swept horns instead of a visor. Accepted for this pass. Remaining differences: the
   reference's fins are wavy, many and pale; ours are four straight dark-shaded
   blades; its tail is longer (ours is held to the 10.5 m length test); its head is
   more horse-like with a long jaw line.

## Clips (H653)

Rendered all 17 clips at their key times and looked at them. The fist plant before the
cold slam reads (both fists wide on the floor at 1.2 s, 5.5 m apart); `frost_beam`
holds the head level with the jaw open; `meteor_drop` has the right fist overhead at
5.9 m; `shoulder_charge` drives the dropped left shoulder; `roar` rears with both fists
3.7 m up. The digitigrade hind legs needed a new fold (`_hind_fold`: hip / knee / hock
in a 1 : -2 : 1 ratio per metre the hips drop) in `_sit` and `_splay`, otherwise the
balls of the feet sank 0.2-0.8 m; `collapse` now keeps the chin above the floor (the
tail tip rests on it).

Gameplay camera (30 m, 44 deg, cave): `design/visual_pass/MA/fight_rimeslithe/`
shot_06 / shot_07. Cold, the crystals and blades glow pale cyan and make the silhouette;
the dark slate body is close to the cave floor's value (see Known).

## Known, accepted at this scale

- Limb joints are hard intersections (balls at shoulder, elbow, wrist, knee, hock).
- At the gameplay camera in the dark cave the slate hide has little value contrast
  with the floor; the glowing crystals carry the read. A rim light or a lighter belly
  would be the next step (not in this lane's files).
- In collapse and death the arms sink partly into the belly; the fists stay visible.

## Earlier rounds (Lane E, model v1)

Four rounds moved the head clear of the floor, rebuilt the horns, fixed roar standing
on its tail and calm_sit sinking its toes. Superseded by the pass above.
