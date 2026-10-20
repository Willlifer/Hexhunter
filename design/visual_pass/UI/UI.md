# Lane UI: visual pass gauntlet log (Phase 3.5)

Reference: `design/kickoff/ref/ui_hud.jpg` (the only UI reference). The HUD is
graded against it directly; the lobby, results and ambush card against its
visual language (plate framing, ornament, icon style, fonts, value contrast),
per the coordinator's scope change.

Every comparison image: reference left, our frame right at the same height;
the bottom row blows up the reference's skill bar and the matching region of
ours. Built by `tools/ui_compare.gd`. Frames: the HUD from real fights
(`--arena pond --fight swampfang --shot <dir> --cam 30,44 --autoplay`, windowed);
the other screens from `tools/ui_screens.gd` (fixed frames, scratch files only);
HUD states the autoplay never reaches from `tools/ui_hud_preview.gd`
(`hud_states.png`: statuses, monster states, low HP, no potions, every weapon).

Differences are listed in the brief's order: silhouette/proportions,
posture/layout, signature features, palette/value contrast, surface detail.

## HUD

### Round 1: `hud_round1.png` (the Phase 3 HUD)
1. Silhouette: ours is a flat grey rectangle with the orb at the far left; the
   reference centres a big red orb between two runs of square icons.
2. Layout: skill names under every box and "fire / water" text clutter the bar;
   the reference carries no text but key numbers.
3. Signature: the reference's skills are painted icons; ours are four identical
   dark-red boxes with a letter. No cooldown sweep (ours fills vertically).
4. Value: our boxes are mid-dark red on a mid-grey plate, low contrast; the
   reference is near-black under saturated icons.
5. Surface: no bevel, no frame, no ornament; the orb is a flat disc.

### Round 2: `hud_round2.png` (the rebuild)
Changed: orb centred between Q W E R and the elements + potion; one dark plate
with a gold trim and diamond studs; a glyph icon per skill (11 skill glyphs,
7 element, status glyphs) on an element-tinted gradient with a bevel; radial
cooldown sweep with a bright hand; glass orb with a liquid fill, meniscus and
highlight; reserved stamina arc over the orb (H19); serif face; monster plate
with a portrait socket, ghost bar, quarter ticks, a state socket.
Still wrong:
1. Silhouette: the orb is small next to the reference's (1.6x a slot against ~2.3x).
2. The cooldown hand on R escaped the slot (a clip that subtracted instead of
   intersected): a diagonal line across the plate.
3. Icons read as flat white stamps on one colour; the reference icons have depth.
4. The empty monster-state socket is a black hole beside the bar.
5. The stamina arc is invisible.

### Round 3: `hud_round3.png`
Changed: orb radius 48 -> 54 and raised 5 px so it crowns the plate; the sweep
hand intersects the slot; a lit radial core behind each glyph; the empty state
socket holds a dim gold star; the stamina arc has gold rails and studs.
Still wrong:
1. The reference's icons are multi-hued paintings; ours stay one hue per bar
   (the active element). Deliberate: W recolours the whole bar, which reads the
   swap at a glance; logged H806.
2. The state label beside the monster socket was small and hard to read on grass.
3. Status icons (28 px) were cramped; their seconds collided.
4. The fight's debug text (top left) is not the HUD's and still clutters (fight.gd; Request R-UI2).
5. The bar is wider than the reference's relative to the screen (5 + 5 icons
   there, 4 + 3 here at a larger size). Kept: the kickoff wants Q W E R readable.

### Round 4: `hud_round4.png` + `hud_states.png`
Changed: state label in serif caps with a heavier outline; status icons 30 px
with the seconds in serif. The states sheet shows every status glyph, three
monster states, 18% HP liquid, an empty potion slot dimmed, Guard's gold glow,
VICTORY's banner (in the full frame). Grade: close in language (dark plate,
centred red orb, framed square icons, key letters, no clutter); short of the
reference's painted icon art, which code-drawn glyphs will not reach.

## Lobby

### Round 1: `lobby_round1.png` (Phase 3 lobby)
1. Layout: tiles are flat colour + name; nothing shows what a pick looks like (L-19).
2. The element strip never says which slot the next click sets.
3. No frames, no ornament: flat rounded cards on a flat background.
4. The card is a loose stack of default grey buttons; no run history.
5. The default sans everywhere; the reference language is a heavy display face.

### Round 2: `lobby_round2.png`
Changed: thumbnails on every tile (`tools/ui_thumbs.gd`: arena overviews,
monsters posed at their aggravated idle, weapons on the diagonal), name on a
dark strip in the serif face, gold rim + SELECTED badge; element sockets with
glyphs, gold ring for active, silver for backup, a dashed hover ring and
"SET ACTIVE / SET BACKUP" tag, a "next click sets ..." line; the card as a plate
with gold rules, FIGHT in the orb's red, Replay/New seed side by side, LAST RUNS
(portrait, verdict + clock, weapon, element dots, seed); a warm dark backdrop
with a gold rule under the title.
Still wrong:
1. Upgrade check boxes rendered as bordered buttons (the theme's Button box leaked into CheckBox).
2. Caldera's thumbnail is mostly white snow rim, the arena's brown floor squeezed.
3. Arena overviews too far out to read the ground.
4. Tile names overlap monster feet a little.
5. The two hint lines at the bottom are dim and small.

### Round 3: `lobby_round3.png`
Changed: CheckBoxes get empty styleboxes (rows, not buttons); arena thumbnail
distance 84 -> 74 m. Remaining: caldera still reads as a snow blob (the arena
lane's content; rerun `tools/ui_thumbs.gd` after their merge); 4 and 5 kept.

## Results

### Round 1: `results_round1.png`
1. A plain rounded box, no ornament; nothing ties it to the HUD.
2. No monster portrait.
3. Stats are loose numbers; drop cards are text boxes with "[W]".
4. Value: flat grey; the default sans.
5. No reveal: everything appears at once.

### Round 2: `results_round2.png`
Changed: the HUD plate with gold trims; a portrait medallion crowning it; the
verdict in the serif face, slammed in (scale 1.8 -> 1); four framed stat tiles;
DROPS/NO SPOILS rule; drop cards with the skill's HUD icon in the cast element,
the letter, the name and blurb, dealt one by one with a flash.
Still wrong:
1. The card flash never fully faded (the curve ended at 0.6): the card stayed grey.
2. The card was too tall; empty space under the blurb.
3. The medallion cropped the monster's head.
4. FALLEN's empty drop row is a large dead area.
5. The upgrade card's top accent is the element colour only (no skill hue).

### Round 3: `results_round3.png`
Changed: flash peaks at 75% of the deal and is gone at the end; card 200x168 ->
210x140; medallion zoom 0.95 -> 0.72 (the whole monster). 4 and 5 kept.

## Ambush title card

### Round 1: `ambush_round1.png`
1. The name floats over the scene with no plate.
2. Sans face with a thin outline; nothing shared with the HUD.
3. The subtitle sits on busy lilypads, low contrast.
4. No ornament.
5. The letterbox is the only framing.

### Round 2: `ambush_round2.png`
Changed: a dark band across the lower third with gold rules fading to the
edges, wiped open from the centre as the name slams in; the name in the serif
face, warm gold, heavy outline; the subtitle in serif. Still wrong:
1. A middle gold rule ran through the subtitle.
2. The band (alpha 0.78) let the water's blue through: lower value contrast than the reference's dark strip.

### Round 3: `ambush_round3.png`
Changed: middle rule removed, the stud moved to the top rule's centre; band
alpha 0.88. Reads as the HUD's language. The slam timing is unchanged.

## Tools
- `tools/ui_thumbs.gd`: regenerate `art/ui/thumbs/*.png` from the current glbs and arenas (windowed).
- `tools/ui_compare.gd`: the comparison image (headless).
- `tools/ui_screens.gd`: fixed frames of the lobby, results and ambush card (windowed, scratch files).
- `tools/ui_hud_preview.gd`: the HUD in states the autoplay does not reach (windowed).
