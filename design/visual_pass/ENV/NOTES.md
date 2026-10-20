# Lane ENV gauntlet notes (Phase 3.5 visual pass)

Arenas and the world map, toward `design/kickoff/ref/arena_*.jpg`. Every image named
here is in this folder: reference on the left, the arena on the right, rendered by
`tools/arena_compare.gd` (sun, sky and point lights exactly as the bench lights it).
`<arena>_gameplay.png` is the real fight at the 30 m / 44 deg camera with the monster in
(`--arena <id> --fight <m> --autoplay --shot ... --cam 30,44`). `map_seed1/2.png` come
from `tools/hunt_preview.gd`. The hex logic is locked by `tests/test_arena_logic_lock.gd`
(regenerated cells, heightfield, spawns, extras and authored rows equal `arenas/*.json`).

Differences are listed in the brief's order: silhouette, posture/framing, signature
features, palette/value, surface.

## Pond (ref: still blue pond with lily-pad beds, lush grass banks, dark conifers)
- round 0 (baseline, not committed): pale flat light-blue water; a picket line of cones on a bald
  green bowl; few pads, none at the banks; spiky cone tufts; sky fine.
- round 1: forest wall (conifer rows, shrubs, mossy boulders), 340 dressing pads hugging
  the banks, blade tufts (short on the walkable shore, long on the skirt), darker water.
  Left wrong: water still lavender-pale (sky reflection + fog), fog greyed the trees.
- round 2: fog cut to 0.0012, water specular 0.55, pad beds spread across the lake,
  camera raised like the photo. Left wrong: water still greyish, trees too light.
- round 3: water `#0a3570` at alpha 0.84, conifer role darker. Water now reads as water.
- round 4 (final, after the fade change): unchanged look. Verdict: CLOSER. Missing: the
  reference's mirror reflections (no SSR on the clear shader) and its foreground grass.
- gameplay: tall skirt conifers covered the hunter at spawn; fixed by `gk_fade` (H759).

## Cave (ref: amber lava tube, banded walls, torch pools, wet floor)
- round 0: grey cobble floor whose Voronoi stones read as a second hex grid; black brick
  walls; spires floating on the dark wall; no warmth at all; in the fight nearly black.
- round 1: warm `tube_rock` (banded grain) walls, plaster floor, warm ambient fill,
  emissive torches + floor light pools, sconces, an overhang lip with stalactites,
  puddles. Left wrong: lip invisible (winding), cream pillars, flat lighting.
- round 2: lip winding fixed (a tunnel mouth now), darker pillars and banding, lower ambient.
  Left wrong: wall evenly lit, halos faceted.
- round 3: walls lit at the foot and sinking to dark above, soft nested halos; boulders
  brown. round 4 (final): single halo + bloom. Verdict: CLOSER on mood and palette;
  the reference's tube is enclosed and glossy, ours is an open bowl (kickoff: "no
  ceiling is fine") and matte.
- gameplay: torch pools ring the rim, floor mid-brown so ice/fire paint reads; the lip
  and stalactites dissolve near the camera (`tube_lip`, `drip`).

## Glade (ref: bright hazy woodland, loose light-green crowns, lush deep-green meadow)
- round 0: lollipop trees in a picket ring, open sky behind, lime ground, spike tufts.
- round 1: two-row broadleaf wall, understory brambles, logs, hazy bright sky + fog.
  Left wrong: ground lime, gaps under the canopies, sandy sun patches.
- round 2: tall shrub mass under the canopies, darker grass role, blade tufts in green.
- round 3: short grass carpet on the floor (0.15-0.3 m), lower light.
- round 4: deeper ground green; in-arena trees get a looser five-lobe two-tone crown.
- round 5/6 (final): with the fade, the two nearest floor trees lose their crowns at the
  compare camera's 8-10 m (gameplay never stands that close). Verdict: CLOSER; the
  reference's tall grass everywhere is deliberately not on the floor (telegraphs first).

## Caldera (ref: aerial snow-streaked crater above a cloud deck, blue-grey sky)
- round 0: the world ended at the skirt (a floating white bowl in brown fog), tan floor.
- round 1: outer flank down to 300 m, cloud deck, charcoal floor, lava glow, steam,
  cold sky. Left wrong: all-white flank, radial checker gullies.
- round 2-3: gully field reworked twice (radial sine -> contour-stretched warped noise).
- round 4: inner rim reads like the photo (streaky snow on dark rock); flank too coarse.
- rounds 5-8: flank rebuilt as one vertex-coloured surface (smooth edges, 10k tris);
  found the "grey" darks were linear vertex colours and the white blobs were clouds
  parked on the flank. round 9: rock at 0.018 linear. round 10 (final): trimmed tris.
  Verdict: CLOSEST of the four in palette; the flank's streaks are coarse blobs, not the
  photo's fine contour streaks, and the crater floor stays dark charcoal for readability.

## World map (L-20)
Paths from the start to every site, a lake with reeds and a stream, a ruined tower, a
ring of standing stones, tree clusters, rock outcrops, hills and a forest wall past the
playable square; each site wears its arena's palette (dark pond with pad beds and
conifers, warm tube-rock cave with torches and a light pool, two-tone broadleaf glade
round a sun patch, snow-streaked dark caldera rim with lava glow and steam). The labels
and the disturbance rings were checked in `map_seed1.png` / `map_seed2.png`.
