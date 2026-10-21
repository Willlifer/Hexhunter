# Easy calibration: the face-tank test (H267, H422)

Lane Q, 2026-10-21. The author (H267): "I would like the numbers adjusted so that a bot solely auto attacking a boss and not avoiding any area of effects (intentionally going into them even) will die. That's the 'easy mode' test I would like performed to define damage values from monsters in easy mode. Mechanics can stay the same."

## The bots

- **Face-tank** (`tools/difficulty_baseline.gd --bot facetank`): only ever gives the attack order on the monster (auto attacks; no Q/W/E/R, no dash, no potion, no element swap), never walks away, and when a monster telegraph is shown within two steps and it is not already standing in one, it walks INTO it. Solo, EASY, each monster on its home arena, lance / bow / daggers, element pairs fire/water and thunder/ice (an operator pair), seeds 1-10: 240 fights per table.
- **Dodging** (the existing baseline bot, `--bot dodge`, coop_bot's `_decide`): attacks, casts R/Q/E on cooldown, steps out of a telegraph about to land, drinks under 40 %. Same matrix, EASY and NORMAL: 480 fights per table.
- 300 s cap per fight. Both "before" tables are on this lane's tree after the merge and after H420 Steam / H425 Eclipse, before any damage change.

## What changed (numbers only)

Per-attack percents in each monster's `TUNE` (percent of the hunter's max HP), each multiplied by one factor per monster and rounded to 0.5 (H422). Push-out damage (`push_land_pct`, `push_self_pct`), ground DOTs, statuses, the NORMAL tier layer's own attacks (`tier_fk_dmg_pct`, `tier_sw_dmg_pct`, `tier_quench_dmg_pct`) and every mechanic are unchanged; NORMAL inherits the new numbers.

| Monster | Factor | Attacks (old -> new % max HP) |
|---|---|---|
| swampfang | x1.5 | spray 12 -> 18, jet 10 -> 15, thrash 15 -> 22.5, roll 30 -> 45, lunge 22 -> 33 |
| colambros | x1.25 | charge 24 -> 30, bite 14 -> 17.5, lash 18 -> 22.5, spit 10 -> 12.5, roll 22 -> 27.5 |
| rimeslithe | x2 | beam 12 -> 24, slam 18 -> 36, charge 20 -> 40, bite 16 -> 32, swipe 14 -> 28, mist 8 -> 16, mist_wide 5 -> 10, meteor 25 -> 50, pillar 15 -> 30 |
| spirewalker | x1.5 | punch 14 -> 21, bite 18 -> 27, barb 8 -> 12, lash 12 -> 18, tail 15 -> 22.5, pollen 4 -> 6, thunder 10 -> 15, dark 10 -> 15, spore 5 -> 7.5 |

Chosen from probes that scaled every monster telegraph's damage uniformly in the harness (`--dmg-scale`, 10 seeds each): the smallest factor per monster at which the face-tank died in every (or all but a pathological few) runs. Spirewalker died in 97 % at x1.0 and 98 % at x1.25, so it gets x1.5 for a clean 100 %.

## Face-tank: before and after (EASY)

| Monster | Weapon | Pair | Before | After |
|---|---|---|---|---|
| swampfang | lance | fire/water | 10/10 dead (100%), monster left 33% | 10/10 dead (100%), monster left 35% |
| swampfang | lance | thunder/ice | 10/10 dead (100%), monster left 42% | 10/10 dead (100%), monster left 66% |
| swampfang | bow | fire/water | 10/10 dead (100%), monster left 47% | 10/10 dead (100%), monster left 54% |
| swampfang | bow | thunder/ice | 10/10 dead (100%), monster left 76% | 10/10 dead (100%), monster left 81% |
| swampfang | daggers | fire/water | 5/10 dead (50%), monster left 2% | 10/10 dead (100%), monster left 21% |
| swampfang | daggers | thunder/ice | 10/10 dead (100%), monster left 75% | 10/10 dead (100%), monster left 81% |
| colambros | lance | fire/water | 10/10 dead (100%), monster left 64% | 10/10 dead (100%), monster left 72% |
| colambros | lance | thunder/ice | 10/10 dead (100%), monster left 80% | 10/10 dead (100%), monster left 82% |
| colambros | bow | fire/water | 10/10 dead (100%), monster left 65% | 10/10 dead (100%), monster left 71% |
| colambros | bow | thunder/ice | 10/10 dead (100%), monster left 74% | 10/10 dead (100%), monster left 79% |
| colambros | daggers | fire/water | 8/10 dead (80%), monster left 29% | 10/10 dead (100%), monster left 37% |
| colambros | daggers | thunder/ice | 10/10 dead (100%), monster left 75% | 10/10 dead (100%), monster left 79% |
| rimeslithe | lance | fire/water | 2/10 dead (20%), monster left 0% | 8/10 dead (80%), monster left 48% |
| rimeslithe | lance | thunder/ice | 10/10 dead (100%), monster left 34% | 10/10 dead (100%), monster left 77% |
| rimeslithe | bow | fire/water | 3/10 dead (30%), monster left 0% | 10/10 dead (100%), monster left 69% |
| rimeslithe | bow | thunder/ice | 10/10 dead (100%), monster left 61% | 10/10 dead (100%), monster left 87% |
| rimeslithe | daggers | fire/water | 1/10 dead (10%), monster left 0% | 10/10 dead (100%), monster left 15% |
| rimeslithe | daggers | thunder/ice | 10/10 dead (100%), monster left 58% | 10/10 dead (100%), monster left 79% |
| spirewalker | lance | fire/water | 9/10 dead (90%), monster left 36% | 10/10 dead (100%), monster left 51% |
| spirewalker | lance | thunder/ice | 10/10 dead (100%), monster left 71% | 10/10 dead (100%), monster left 77% |
| spirewalker | bow | fire/water | 10/10 dead (100%), monster left 75% | 10/10 dead (100%), monster left 80% |
| spirewalker | bow | thunder/ice | 10/10 dead (100%), monster left 89% | 10/10 dead (100%), monster left 91% |
| spirewalker | daggers | fire/water | 9/10 dead (90%), monster left 22% | 10/10 dead (100%), monster left 34% |
| spirewalker | daggers | thunder/ice | 10/10 dead (100%), monster left 82% | 10/10 dead (100%), monster left 83% |

| Monster | Before | After |
|---|---|---|
| swampfang | 55/60 dead (92%), monster left 44% | 60/60 dead (100%), monster left 62% |
| colambros | 58/60 dead (97%), monster left 70% | 60/60 dead (100%), monster left 74% |
| rimeslithe | 36/60 dead (60%), monster left 22% | 58/60 dead (97%), monster left 72% |
| spirewalker | 58/60 dead (97%), monster left 72% | 60/60 dead (100%), monster left 77% |
| **all** | 207/240 dead (86%), monster left 56% | 238/240 dead (99%), monster left 72% |

Target met: the face-tank dies in 238 of 240 runs (99 %). The exceptions (pathological, reported, not forced):

- rimeslithe, lance, fire/water, seed 8: win at 33.6 s (hunter 0 % left). Fire/water is the strongest face-tank pair on the cave in every table (before: 6/30 dead); the likely cause, not traced hit by hit, is fire basics erupting as Steam on the water and frost the cave and Rimeslithe lay (H420).
- rimeslithe, lance, fire/water, seed 9: win at 34.4 s (hunter 16 % left). Fire/water is the strongest face-tank pair on the cave in every table (before: 6/30 dead); the likely cause, not traced hit by hit, is fire basics erupting as Steam on the water and frost the cave and Rimeslithe lay (H420).

## Dodging bot: before and after

Cells: win rate (wins / fights) | median fight length (all outcomes).

| Monster | Easy before | length | Easy after | length | Normal before | length | Normal after | length |
|---|---|---|---|---|---|---|---|---|
| swampfang | 95% (57/60) | 47.5 s | 85% (51/60) | 51.2 s | 95% (57/60) | 37.4 s | 93% (56/60) | 41.4 s |
| colambros | 87% (52/60) | 38.1 s | 80% (48/60) | 39.6 s | 77% (46/60) | 39.3 s | 65% (39/60) | 38.9 s |
| rimeslithe | 100% (60/60) | 42.0 s | 88% (53/60) | 42.6 s | 100% (60/60) | 32.1 s | 100% (60/60) | 32.8 s |
| spirewalker | 93% (56/60) | 39.8 s | 88% (53/60) | 36.5 s | 88% (53/60) | 41.2 s | 82% (49/60) | 39.1 s |
| **all** | 94% (225/240) | 43.1 s | 85% (205/240) | 42.6 s | 90% (216/240) | 36.8 s | 85% (204/240) | 37.7 s |

The stop rule (dodging bot's EASY win rate under ~60 %) was never close: EASY went from 94% (225/240) | 43.1 s to 85% (205/240) | 42.6 s (win rate | median length) overall, every monster stayed at 80 % or more. NORMAL Colambros is the hardest cell (65% (39/60) | 38.9 s), the bot's dodge is a step out of a telegraph within its last 1.2 s and Colambros is the fast one.

## Rerun

```
godot --headless --path . --script res://tools/difficulty_baseline.gd -- --bot facetank --tiers easy --seeds 10 --pair fire,water --json ft.json
godot --headless --path . --script res://tools/difficulty_baseline.gd -- --bot dodge --tiers easy,normal --seeds 10 --pair thunder,ice --json dg.json
godot --headless --path . --script res://tools/difficulty_baseline.gd -- --merge ft.json,dg.json --md out.md
```
`--dmg-scale X` multiplies every monster telegraph's damage in the harness only (a probe for the next calibration; the game never reads it).
