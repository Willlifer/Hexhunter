# Element pass: the sim, before and after (Lane EL, H360-H375)

**What was run.** `tools/element_sim.gd` (extends Lane D's `difficulty_baseline.gd`): the same seeded solo bot (attack, cast r / q / e on cooldown, step out of a telegraph about to land, drink under 40%) plus one habit, so it uses BOTH elements: it lays its active element for 3 landed basics, swaps (W), cashes in with the backup for 3, and so on. All 21 element pairs (the axis element active: fire/thunder lays fire and detonates with thunder) x the four monsters on their biomes x lance / bow / daggers x EASY and NORMAL x seeds 1-4, 240 s cap: 2016 fights per run. Deterministic; reproduce with

```
godot --headless --path . --script res://tools/element_sim.gd -- --pairs fire/water,... --monsters swampfang --seeds 4 --json out.json
godot --headless --path . --script res://tools/element_sim.gd -- --merge after.json,... --before before.json,... --md design/elements/sim.md
```

**Runs.**
- BEFORE: `dev` at 455e2ef (the old rules: Douse, Glaze, Gale, Overfreeze, Fuse x3/point).
- AFTER-1: this lane's rules, Thunder unchanged.
- AFTER-2: + Thunder `det_mult_per_point` 3.0 -> 2.5.
- FINAL (the tables below): + `det_mult_per_water` 1.0 -> 0.5, on this lane MERGED with dev at 3ca3285. That dev also brought Lane P's push-out damage and leap splash (H271-H279), which hurt the bot (it stands where monsters land): FINAL's win rates are not purely this lane's doing. AFTER-1 / AFTER-2 are pre-merge.

**How to read it.** A simple bot, not a person: the numbers compare pairs and cash-ins for the same player. NORMAL equals EASY fight for fight (nothing is gated on a tier, H368). "Cash-in share" = the share of the damage the monster took that came from each reaction (the reaction event's strongest cause); weapon blows and ground damage make up the rest. BEFORE's "shatter" column is the old Overfreeze.

## The Thunder retune (spec 2.4)

Median fight length (s) and Detonate's share of the damage, thunder pairs against the other operators' pairs with the same axis partner:

| Partner | thunder: BEFORE / AFTER-1 / AFTER-2 / FINAL | Detonate share B / 1 / 2 / F | ice: B / 1 / 2 / F | wind: B / 1 / 2 / F |
|---|---|---|---|---|
| fire | 32.2 / 31.9 / 34.4 / 34.3 | 59 / 56 / 51 / 49 % | 54.3 / 36.3 / 36.8 / 38.5 | 43.4 / 47.9 / 47.9 / 48.1 |
| water | 34.4 / 31.9 / 32.4 / 33.5 | 73 / 66 / 63 / 59 % | 30.0 / 39.2 / 39.2 / 40.9 | 91.3 / 50.4 / 50.4 / 51.0 |
| light | 42.9 / 42.3 / 46.4 / 48.0 | 69 / 60 / 56 / 57 % | 195.6 / 52.6 / 52.6 / 51.8 | 240 (0 wins) / 60.3 / 60.3 / 58.9 |
| dark | 36.5 / 33.9 / 36.3 / 36.0 | 68 / 59 / 55 / 54 % | 81.8 / 35.9 / 35.9 / 41.6 | 72.7 / 46.0 / 46.0 / 47.4 |

Read: before, a thunder pair was the only fast way to play (every non-thunder operator pair but water/ice was 1.5-6x slower, light/wind never won). After, Shatter's share in ice pairs (48-54%) matches Detonate's in thunder pairs (49-59%), every axis pair has its own tier-3 or eruption payoff, and fire/dark, water/dark, fire/water are as fast as the thunder pairs. Thunder pairs are still the quickest by 5-20% on fire / water / dark (water/thunder most), and the wind pairs are the slowest operator (the bot never aims a Swirl; it fires it with basics on the hull's edge). Further Thunder cuts are the author's call after play (L-47).

BEFORE: 2016 fights: 21 pairs x colambros/rimeslithe/spirewalker/swampfang x lance/bow/daggers x tiers easy/normal, seeds 1-4, 240 s cap (timeout = not a win).

AFTER: 2016 fights: 21 pairs x colambros/rimeslithe/spirewalker/swampfang x lance/bow/daggers x tiers easy/normal, seeds 1-4, 240 s cap (timeout = not a win).

Cells: win rate (wins/fights) | median fight length | median length of the wins.

### Per tier

| Tier | Before | After |
|---|---|---|
| easy | 77% (774/1008) | 63.3 s | 54.5 s | 93% (935/1008) | 46.2 s | 46.3 s |
| normal | 77% (774/1008) | 63.3 s | 54.5 s | 93% (935/1008) | 46.2 s | 46.3 s |

### Per tier and monster

| Monster | Tier | Before | After |
|---|---|---|---|
| colambros | easy | 73% (184/252) | 57.2 s | 49.6 s | 82% (207/252) | 47.2 s | 49.0 s |
| colambros | normal | 73% (184/252) | 57.2 s | 49.6 s | 82% (207/252) | 47.2 s | 49.0 s |
| rimeslithe | easy | 86% (216/252) | 65.2 s | 52.1 s | 98% (246/252) | 41.9 s | 40.6 s |
| rimeslithe | normal | 86% (216/252) | 65.2 s | 52.1 s | 98% (246/252) | 41.9 s | 40.6 s |
| spirewalker | easy | 75% (190/252) | 74.7 s | 55.5 s | 94% (236/252) | 41.7 s | 41.5 s |
| spirewalker | normal | 75% (190/252) | 74.7 s | 55.5 s | 94% (236/252) | 41.7 s | 41.5 s |
| swampfang | easy | 73% (184/252) | 69.8 s | 56.0 s | 98% (246/252) | 50.5 s | 50.5 s |
| swampfang | normal | 73% (184/252) | 69.8 s | 56.0 s | 98% (246/252) | 50.5 s | 50.5 s |

### Per element pair (all monsters, weapons, tiers)

| Pair | Before | After | Cash-in share before | Cash-in share after |
|---|---|---|---|---|
| fire/water | 88% (84/96) | 66.0 s | 64.0 s | 96% (92/96) | 39.1 s | 39.3 s | overheat 21% | detonate 3%, shatter 3%, overheat 11%, geyser 8%, flux 1%, steam 35% |
| fire/light | 81% (78/96) | 65.8 s | 61.7 s | 96% (92/96) | 53.4 s | 53.4 s | overheat 35% | detonate 1%, shatter 5%, overheat 25%, glint 18%, flux 1%, steam 1%, eclipse 4% |
| fire/dark | 94% (90/96) | 45.0 s | 45.1 s | 100% (96/96) | 36.5 s | 36.5 s | overheat 35% | detonate 2%, shatter 5%, overheat 24%, flux 24%, steam 1% |
| fire/thunder | 100% (96/96) | 32.2 s | 32.2 s | 92% (88/96) | 34.3 s | 34.3 s | detonate 59%, overheat 7% | detonate 49%, shatter 2%, overheat 11%, flux 1%, steam 1% |
| fire/ice | 92% (88/96) | 54.3 s | 54.0 s | 94% (90/96) | 38.5 s | 39.0 s | shatter 5%, overheat 24% | detonate 1%, shatter 48%, overheat 10%, flux 1%, steam 1% |
| fire/wind | 96% (92/96) | 43.4 s | 43.4 s | 96% (92/96) | 48.1 s | 48.3 s | overheat 34% | detonate 2%, shatter 3%, swirl 29%, overheat 17%, flux 1%, steam 2% |
| water/light | 25% (24/96) | 240.0 s | 130.6 s | 77% (74/96) | 78.6 s | 67.8 s | - | detonate 2%, shatter 9%, overheat 1%, geyser 25%, glint 24%, flux 1%, steam 3%, eclipse 3% |
| water/dark | 63% (60/96) | 78.9 s | 92.2 s | 92% (88/96) | 38.1 s | 38.0 s | - | detonate 3%, shatter 5%, geyser 26%, flux 27%, steam 1% |
| water/thunder | 100% (96/96) | 34.4 s | 34.4 s | 94% (90/96) | 33.5 s | 33.5 s | detonate 73% | detonate 59%, shatter 2%, geyser 9% |
| water/ice | 100% (96/96) | 30.0 s | 30.0 s | 96% (92/96) | 40.9 s | 40.9 s | shatter 73% | detonate 1%, shatter 53%, geyser 12%, flux 1% |
| water/wind | 69% (66/96) | 91.3 s | 97.8 s | 92% (88/96) | 51.0 s | 51.2 s | - | detonate 2%, shatter 3%, swirl 30%, geyser 19%, flux 1%, steam 1% |
| light/dark | 52% (50/96) | 149.6 s | 142.1 s | 92% (88/96) | 47.0 s | 46.6 s | - | detonate 2%, shatter 3%, geyser 1%, glint 9%, flux 11%, eclipse 39% |
| light/thunder | 100% (96/96) | 42.9 s | 42.9 s | 96% (92/96) | 48.0 s | 49.5 s | detonate 69% | detonate 57%, shatter 2%, glint 8%, flux 1%, eclipse 2% |
| light/ice | 31% (30/96) | 195.6 s | 153.0 s | 98% (94/96) | 51.8 s | 52.2 s | shatter 12% | detonate 1%, shatter 54%, glint 11%, flux 1%, eclipse 2% |
| light/wind | 0% (0/96) | 240.0 s | - | 94% (90/96) | 58.9 s | 59.3 s | overheat 1% | detonate 2%, shatter 4%, swirl 30%, geyser 1%, glint 16%, flux 1%, eclipse 3% |
| dark/thunder | 100% (96/96) | 36.5 s | 36.5 s | 96% (92/96) | 36.0 s | 36.0 s | detonate 68% | detonate 54%, shatter 2%, flux 13% |
| dark/ice | 79% (76/96) | 81.8 s | 84.4 s | 92% (88/96) | 41.6 s | 41.6 s | shatter 10% | detonate 1%, shatter 53%, flux 12% |
| dark/wind | 69% (66/96) | 72.7 s | 82.0 s | 96% (92/96) | 47.4 s | 47.8 s | - | detonate 2%, shatter 4%, swirl 31%, flux 21% |
| thunder/ice | 98% (94/96) | 59.4 s | 59.3 s | 88% (84/96) | 66.5 s | 68.3 s | detonate 37%, shatter 6% | detonate 19%, shatter 18%, flux 1% |
| thunder/wind | 96% (92/96) | 63.9 s | 63.9 s | 88% (84/96) | 68.4 s | 69.8 s | detonate 38% | detonate 22%, shatter 1%, swirl 10%, flux 1% |
| ice/wind | 81% (78/96) | 83.5 s | 82.1 s | 88% (84/96) | 73.1 s | 75.8 s | shatter 15% | shatter 22%, swirl 10%, flux 2% |

### Damage share by column, every fight

| Column | Before | After |
|---|---|---|
| weapon | 63% | 36% |
| ground | 10% | 4% |
| detonate | 14% | 12% |
| shatter | 5% | 14% |
| swirl | - | 6% |
| overheat | 7% | 5% |
| geyser | - | 6% |
| glint | - | 7% |
| flux | - | 5% |
| steam | - | 2% |
| eclipse | - | 3% |
