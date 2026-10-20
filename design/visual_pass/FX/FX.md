# Lane FX: telegraph wind-ups, impacts, state effects (review)

Renders: `godot --path . --script res://tools/fx_preview.gd [-- --only <monster>] [--attack <id>]`.
Each attack is triggered through the brain's own attack function on the monster's
biome, the sim stepped one tick per frame, at the gameplay camera (30 m, 44 deg,
FOV 40, behind the hunter looking at the monster). Files:
`<monster>_<attack>_<00|50|90|contact>.png` (960x600), plus
`colambros_breath_vs_charge.png` (both at 50 %, full res) and `ice_sequence.png`
(Rimeslithe's mist breath: 0 / 50 / 90 / contact, 2x2).

Everything listed below was looked at with the image open; the per-monster
contact sheets (a row per attack) were used for the sweep.

## Colambros: breath vs charge

**Round 1.** Breath (ember_spit) at 50 % already read: an orange glow on the head,
embers. The charge did not: the preview put Colambros at its spawn by the arena
edge, where its footprint fits one hex of lane, so the "charge" was a single hex
and a faint puff hidden behind the body. Two fixes. The tool now stands the monster
in the open and picks the hunter's side with the longest charge line the brain
itself computes (13 lane telegraphs, one effect). In the effect, the kicked dust
was going straight back, behind the body, which is exactly where the camera
cannot see when the monster faces you. It now goes up 2.5-5.5 m/s and out sideways ±3.5,
in pale tan (`DUST_KICK`) so it shows on dark caldera rock, with a dust skirt at the feet
growing with the wind-up. The lane chevrons washed out on the red tint, so they were
made wider and given a dark ink edge, and the lane is scuffed darker.
The breath's scorch was not visible at 50 % because it spread from the body and the spit
areas start several metres out; it now spreads from the cone's nearest hex.

**Round 2.** Side by side the two now differ (tan cloud at the feet + white arrows vs
glow at the head), but at 30 m the breath's glow was small next to the caldera's
standing flames (L-4 cards on the vents) and its smoke barely showed. The mouth
glow was made larger (three pinned sprites: a wide red halo, the orange glow, a hot
core) and the smoke became a dark column (rate 9-31/s, size to 1.9 m, alpha 0.8).

**Round 3.** The charge dust at 90 % had grown into a cloud that swallowed the body,
and the body's own head-low scrape pose is half the tell. Dust sizes came down
(end size 1.5-2.1 m, skirt 1.3-1.9 m). Final: breath = orange head glow + black
smoke column + scorch growing in the cone; charge = pale dust round the hind legs with
the body readable inside it + ink-edged chevrons racing down the lane toward you;
smouldering charge = the same with orange chevrons and ember streaks. In the
side-by-side they separate on colour, height and shape before you look at a tile.

## The ice sequence (wind whipping up, then ice)

**Round 1.** 0 % nothing (correct), 50 % a few thin white streaks, 90 % frost spreading
and shards (good), contact white frost field + shards (good). The wind phase did not
read as wind: the streaks were scattered. Added standing whirls (one per ~10 hexes,
max 4) that 60 % of the streaks spiral round and climb, made the streaks longer and
thicker, snow motes bigger, shards bigger (0.8-1.7), the ground's wind bands stronger.

**Round 2.** The ground bands now read as wind; the air had lines but no volume.
Added snow-devil mist columns at each whirl (puffs wound round it, climbing), fading as the
frost phase takes over.

**Round 3.** Only one devil showed: the alpha sprite pool (150) was saturated by
streaks + snow + devils. Raised the effect's alpha pool to 320 (measured peak 473
sprites on this, the largest ice area). Final: 50 % white whirls rising across the cone
and at the mouth, wind bands on the ground; 90 % the frost sheet spreading from the
monster with shards growing out of it and streak arcs still whipping; contact a white
frost field bristling with shards, then they shatter and sink.

## Sweep (the other attacks)

- **Swampfang:** spray / jet light the frill and mouth (violet / blue) and drip; the
  dark pool creeps over the cone; the ripple telegraph shows a white ring and bubbles
  where it will surface, away from the body; thrash and the death roll show water
  rings round it (the vortex streaks are thin at 30 m: see observations).
- **Rimeslithe:** frost beam charges a bright ring and light at the mouth; cold slam's
  frost starts at the knuckles and covers the ring by 90 %; shoulder charge gets
  the lane; bite / swipe the dust + crack; the meteor's shadow sits under the frost
  and the chunk was falling off the top of the frame at 90 %, so it now drops from
  14 m over the last half (seen in frame afterwards).
- **Spirewalker:** the reeds stay copper when charged (L-18); pollen haze was too thin
  at 90 % and was thickened (rate x1.7, alpha to 0.56); breaths get mouth crackle /
  smoke; squash gets the landing shadow; barbs are the thunder sparks per hex. The
  glade's trees sometimes stand between the camera and the action in the preview.
- **Arena events (H51):** the swell reads as a teal disk with rings running out and
  a spray crest (good); vents steam and glow amber; rockfalls drop grit and dust
  from above with sand tiles and the shadow (shadow strengthened after the first look).
- **Reactions (H50):** a gold ring, spray and `1872  x3` over the monster, with
  `x2.4` over each detonation.
- **The hunter:** Eruption's ring burst reads at 30 m. Pierce's wind-up is short, so
  the 50 % frame already shows the line streaks rather than the hand glow.

## Honest observations

1. The tiles still carry most of the shape. The effects give each attack a
   distinct look and a sense of build-up, but a few generic ones (bite, arm swipe,
   tail drag: the dust + crack layer) are quiet at 30 m and differ from each other
   only by their shape on the ground.
2. Thin streaks (death-roll vortex, lance pierce, wind) shrink to a pixel or two at
   30 m. The volume effects (dust, smoke, mist, glows) carry; the line effects are
   decoration up close.
3. At contact the ice frost and the fire scorch cover the danger tint almost
   completely. That is fine at contact (the hit has landed), but on the largest
   ice areas the 90 % frame is already mostly pink-white, so the red reads less
   in the last fifth of the countdown.
