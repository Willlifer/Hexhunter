# Colambros: review renders

`tools/monster_preview_colambros.gd` (windowed) writes `colambros_view_<front34|side|back34>.png`
in `aggravated_idle` and `colambros_<clip>.png` for every clip at its `key` time
(HHColambrosClips.CLIPS). `-- --only a,b` renders just those shots; `-- --gauntlet <png>`
renders only the gauntlet angle. Rebuild: `blender -b --factory-startup --python
tools/blender/build_monster_colambros.py`, then `godot --headless --path . --import`,
then `godot --path . --script res://tools/monster_preview_colambros.gd`.

Reference: `design/kickoff/ref/monster_colambros.png` (a brute wyvern standing tall on
its hind legs, small arms held up, heavy tail behind, ringed horns). The kickoff text
wins where they disagree (rust / ash / bone palette, the quill ridge, kangaroo legs).
Scale bar in every shot: the player rig's 2.2 m capsule; the ground carries the 1 m
hex grid.

Model v3 (H650): 2250 triangles, 8.1 m nose to tail tip, hips 1.95 m, skull ~3.9 m,
5.0 m to the horn tips. The rest pose is the biped stance: the torso rises ~35 deg
from the hips to the shoulders, an S-neck carries a big hyena skull, the tail sweeps
down and rests its tip on the ground (the kangaroo's third support). Rear legs are
digitigrade (`shapes_ma.digi_leg`: thigh mass, calf, high hock, three splayed toes);
the arms are small and held off the ground in front of the chest. `run` and `charge`
are the only clips on all fours (`_quad`): the torso pitches level, the arms paw the
ground. That contrast is the read between the charge and the ember spit (H651).

## Visual pass 3.5 gauntlet (Lane MA)

Comparison images (reference left, render right, `tools/gauntlet_compare_ma.gd`):
`design/visual_pass/MA/colambros_round<0-3>.png`. Gauntlet angle: the reference's
rear three-quarter from the monster's right (camera yaw -118, pitch 8), `aggravated_idle`.

0. Baseline (the model as Lane E left it). Differences, in the brief's order:
   (1) silhouette: a horizontal four-legged lizard; the reference is a tall upright
   biped; (2) posture: front limbs as long as the rear ones and planted, the body level;
   (3) signature features: no horns, small head, thin shins, no tail support;
   (4) palette: right per the text (rust / ash / bone); (5) surface: fine.
1. Rebuilt the skeleton as a brute-wyvern biped: hips raised to 1.95 m, the torso
   pitched up to the shoulders (3.45 m), S-neck, skull 0.6 m wide at 3.9 m, two
   swept ringed horns (bone and horn bands, `shapes_ma.horn`), digitigrade rear legs
   with a thigh mass, arms shortened to 1.1 m and held at the chest, tail down to the
   ground. `_quad` retuned for the new stance (pitch 36, drop 0.45, the arms reach the
   ground). Looked: the biped reads at once, the arms read as small. Wrong now: a
   haunch mass and the thigh mass made two separate lumps in `run`; the lower legs were
   thin and hidden under the thigh; the jaw was a white box (belly role).
2. Haunch masses removed, one bigger thigh mass; shins/hocks thicker (0.40 / 0.26);
   jaw in the hide colour; quills darken earlier (mid band 62% toward the char tip);
   gauntlet camera brought in. Looked: legs read as kangaroo legs. Wrong: the head
   still small against the reference; the tail a straight cone; the horns thin.
3. Skull/brow mass bigger, horns longer and thicker (0.22 m root, five rings), tail
   curved so its last two metres lie along the ground; a rump mass closes the open seam
   where the spine and tail lofts meet over the hips (seen as a pale sliver in side
   view). Looked: accepted for this pass. Remaining differences: the reference's head
   turns over its shoulder (ours faces forward), its tail ends in a club (the text has
   none), its spikes are small and dark (ours are the text's long bone quills).

Spine lofts are closed now and every role mesh's islands get their normals voted
outward (`shapes_ma.install_normal_fix`): an open belly strip had come out with its
normals inward on Rimeslithe and read as a bright bar.

## Clips (H651)

Rendered every clip at its key time and looked at all 18 plus the three views.
Biped: `aggravated_idle`, `walk`, `rattle_roar` (rears less than before: the upright
stance was already tall), `dirt_scrape` (stands, only a 5 deg lean, the left foot
rakes back), `bite`, `ember_spit` (upright, head whips level, mouth at 2.7 m),
`tail_lash`, `leap_stomp`, `hit_react`, `stagger`, `bald_idle`. All fours: `run`,
`charge` (lower, jaws open, quills flat). Lying: `calm_sprawl` / `quill_gnaw` /
`collapse` (`SPRAWL_PITCH` 32 lays the torso down first), `death` (on its side),
`back_roll` (`_pitch_then_roll`: lies level, THEN rolls 180 about its long axis; it
used to roll the upright torso through the floor).

Gameplay camera (30 m, 44 deg, caldera): `design/visual_pass/MA/fight_colambros/`
shot_05 (standing up, horns and pale chest facing the camera) and shot_07 (after a
charge, the upright stance with the tail on the ground).

## Known, accepted at this scale

- Limb joints are hard intersections; knee and hock knobs hide most of them.
- Quills are opaque spikes; the smoulder glow is the body's `quill` role material.
- The bald window flattens the quills along the spine rather than removing them.

## Earlier rounds (Lane E, model v2)

Three rounds fixed floating feet, an under-floor back_roll, tail_lash tucking under
the body and a gnaw that could not reach the flank; they accepted a stance that still
stood on four legs. Superseded by the pass above.
