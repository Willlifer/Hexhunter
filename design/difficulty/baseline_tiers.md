# Difficulty baseline: EASY vs NORMAL after Lane M (H360-H379)

Measured 2026-10-21 on Lane M (dev 3ca3285 + spec sections 7 and 8 on NORMAL). Same bot, seeds, cap and commands as design/difficulty/baseline.md (Lane D, the BEFORE numbers). EASY differs from that file only by dev changes since (Lane P push-out damage, leap splash); Lane M does not touch EASY.

Solo bot (tools/coop_bot.gd's bot via tools/difficulty_baseline.gd), each monster on its biome, element pair fire/water, seeds 1-20 per cell, 300 s cap per fight (still running then = timeout, counted as not a win). 480 fights.

Cells: win rate (wins/fights) | median fight length, all outcomes | median length of the wins.

### Per tier

| Tier | Win rate | Median length | Median win |
|---|---|---|---|
| easy | 94% (226/240) | 32.8 s | 32.8 s |
| normal | 81% (194/240) | 47.1 s | 50.1 s |

### Per tier and monster

| Monster | Tier | Win rate | Median length | Median win | Outcomes |
|---|---|---|---|---|---|
| swampfang | easy | 97% (58/60) | 47.7 s | 47.5 s | win 58, dead 2 |
| swampfang | normal | 82% (49/60) | 63.9 s | 63.0 s | win 49, dead 11 |
| colambros | easy | 88% (53/60) | 32.3 s | 32.7 s | win 53, dead 7 |
| colambros | normal | 82% (49/60) | 36.6 s | 37.8 s | win 49, dead 11 |
| rimeslithe | easy | 100% (60/60) | 29.0 s | 29.0 s | win 60 |
| rimeslithe | normal | 97% (58/60) | 57.3 s | 57.3 s | win 58, dead 2 |
| spirewalker | easy | 92% (55/60) | 32.5 s | 32.4 s | win 55, dead 5 |
| spirewalker | normal | 63% (38/60) | 38.6 s | 41.2 s | win 38, dead 22 |

### Per tier, monster and weapon

| Monster | Weapon | Tier | Win rate | Median length | Median win | Outcomes |
|---|---|---|---|---|---|---|
| swampfang | lance | easy | 100% (20/20) | 42.3 s | 42.3 s | win 20 |
| swampfang | lance | normal | 80% (16/20) | 63.6 s | 63.6 s | win 16, dead 4 |
| swampfang | bow | easy | 95% (19/20) | 57.1 s | 56.8 s | win 19, dead 1 |
| swampfang | bow | normal | 75% (15/20) | 88.2 s | 88.4 s | win 15, dead 5 |
| swampfang | daggers | easy | 95% (19/20) | 46.4 s | 45.7 s | win 19, dead 1 |
| swampfang | daggers | normal | 90% (18/20) | 52.7 s | 52.7 s | win 18, dead 2 |
| colambros | lance | easy | 95% (19/20) | 28.2 s | 27.7 s | win 19, dead 1 |
| colambros | lance | normal | 80% (16/20) | 36.6 s | 37.5 s | win 16, dead 4 |
| colambros | bow | easy | 100% (20/20) | 33.9 s | 33.9 s | win 20 |
| colambros | bow | normal | 100% (20/20) | 39.8 s | 39.8 s | win 20 |
| colambros | daggers | easy | 70% (14/20) | 32.3 s | 32.4 s | win 14, dead 6 |
| colambros | daggers | normal | 65% (13/20) | 35.3 s | 36.6 s | win 13, dead 7 |
| rimeslithe | lance | easy | 100% (20/20) | 26.0 s | 26.0 s | win 20 |
| rimeslithe | lance | normal | 95% (19/20) | 58.0 s | 58.1 s | win 19, dead 1 |
| rimeslithe | bow | easy | 100% (20/20) | 30.4 s | 30.4 s | win 20 |
| rimeslithe | bow | normal | 100% (20/20) | 58.2 s | 58.2 s | win 20 |
| rimeslithe | daggers | easy | 100% (20/20) | 29.5 s | 29.5 s | win 20 |
| rimeslithe | daggers | normal | 95% (19/20) | 51.9 s | 50.5 s | win 19, dead 1 |
| spirewalker | lance | easy | 100% (20/20) | 32.0 s | 32.0 s | win 20 |
| spirewalker | lance | normal | 65% (13/20) | 43.0 s | 45.7 s | win 13, dead 7 |
| spirewalker | bow | easy | 100% (20/20) | 32.5 s | 32.5 s | win 20 |
| spirewalker | bow | normal | 90% (18/20) | 38.0 s | 38.3 s | win 18, dead 2 |
| spirewalker | daggers | easy | 75% (15/20) | 31.9 s | 30.6 s | win 15, dead 5 |
| spirewalker | daggers | normal | 35% (7/20) | 35.4 s | 37.9 s | win 7, dead 13 |
