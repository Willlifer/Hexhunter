# Difficulty baseline (the BEFORE numbers)

Spec section 10: win rate and median fight length per difficulty tier. Measured on 2026-10-21 on `dev` at d185a9c plus Lane D's tier switch. No behaviour is gated on a tier yet, so NORMAL is identical to EASY by construction (H240) and the two rows match fight for fight. A later Thunder retune and the NORMAL-tier lanes compare against these numbers.

Reproduce: four processes in parallel, about a minute each. The runs are deterministic, so the same table comes back.

```
godot --headless --path . --script res://tools/difficulty_baseline.gd -- --monsters swampfang --seeds 20 --cap 300 --json base_swampfang.json
(... the same for colambros, rimeslithe and spirewalker ...)
godot --headless --path . --script res://tools/difficulty_baseline.gd -- --merge base_swampfang.json,base_colambros.json,base_rimeslithe.json,base_spirewalker.json --md design/difficulty/baseline.md
```

**How to read it.** The fights are played by `tools/coop_bot.gd`'s bot, alone. It attacks, casts r, q or e on cooldown, steps out of a telegraph that is about to land, and drinks under 40% HP. It always plays fire active with water backup. It wins almost every fight in about half a minute, mostly through fire reactions: in one sample Swampfang lance fight it dealt 9.4k of the monster's 20k HP through overheat and 5.5k with basic attacks.

So this table compares tiers and monsters for the same bot. It does not say how hard a fight is for a person, and another element pair moves every number. Thunder is not in the bot's pair. A Thunder retune therefore needs its own before/after with `--pair thunder,<backup>`: for example, Swampfang with the lance, seed 1, on thunder/ice wins at 33.8 s against 41.9 s on fire/water.

Solo bot (tools/coop_bot.gd's bot via tools/difficulty_baseline.gd), each monster on its biome, element pair fire/water, seeds 1-20 per cell, 300 s cap per fight (still running then = timeout, counted as not a win). 480 fights.

Cells: win rate (wins/fights) | median fight length, all outcomes | median length of the wins.

### Per tier

| Tier | Win rate | Median length | Median win |
|---|---|---|---|
| easy | 99% (238/240) | 30.4 s | 30.4 s |
| normal | 99% (238/240) | 30.4 s | 30.4 s |

### Per tier and monster

| Monster | Tier | Win rate | Median length | Median win | Outcomes |
|---|---|---|---|---|---|
| swampfang | easy | 98% (59/60) | 49.3 s | 49.1 s | win 59, dead 1 |
| swampfang | normal | 98% (59/60) | 49.3 s | 49.1 s | win 59, dead 1 |
| colambros | easy | 100% (60/60) | 28.4 s | 28.4 s | win 60 |
| colambros | normal | 100% (60/60) | 28.4 s | 28.4 s | win 60 |
| rimeslithe | easy | 100% (60/60) | 27.7 s | 27.7 s | win 60 |
| rimeslithe | normal | 100% (60/60) | 27.7 s | 27.7 s | win 60 |
| spirewalker | easy | 98% (59/60) | 30.3 s | 30.2 s | win 59, dead 1 |
| spirewalker | normal | 98% (59/60) | 30.3 s | 30.2 s | win 59, dead 1 |

### Per tier, monster and weapon

| Monster | Weapon | Tier | Win rate | Median length | Median win | Outcomes |
|---|---|---|---|---|---|---|
| swampfang | lance | easy | 100% (20/20) | 41.9 s | 41.9 s | win 20 |
| swampfang | lance | normal | 100% (20/20) | 41.9 s | 41.9 s | win 20 |
| swampfang | bow | easy | 95% (19/20) | 61.6 s | 61.0 s | win 19, dead 1 |
| swampfang | bow | normal | 95% (19/20) | 61.6 s | 61.0 s | win 19, dead 1 |
| swampfang | daggers | easy | 100% (20/20) | 47.5 s | 47.5 s | win 20 |
| swampfang | daggers | normal | 100% (20/20) | 47.5 s | 47.5 s | win 20 |
| colambros | lance | easy | 100% (20/20) | 22.9 s | 22.9 s | win 20 |
| colambros | lance | normal | 100% (20/20) | 22.9 s | 22.9 s | win 20 |
| colambros | bow | easy | 100% (20/20) | 31.9 s | 31.9 s | win 20 |
| colambros | bow | normal | 100% (20/20) | 31.9 s | 31.9 s | win 20 |
| colambros | daggers | easy | 100% (20/20) | 29.3 s | 29.3 s | win 20 |
| colambros | daggers | normal | 100% (20/20) | 29.3 s | 29.3 s | win 20 |
| rimeslithe | lance | easy | 100% (20/20) | 24.9 s | 24.9 s | win 20 |
| rimeslithe | lance | normal | 100% (20/20) | 24.9 s | 24.9 s | win 20 |
| rimeslithe | bow | easy | 100% (20/20) | 29.6 s | 29.6 s | win 20 |
| rimeslithe | bow | normal | 100% (20/20) | 29.6 s | 29.6 s | win 20 |
| rimeslithe | daggers | easy | 100% (20/20) | 27.8 s | 27.8 s | win 20 |
| rimeslithe | daggers | normal | 100% (20/20) | 27.8 s | 27.8 s | win 20 |
| spirewalker | lance | easy | 95% (19/20) | 29.6 s | 29.6 s | win 19, dead 1 |
| spirewalker | lance | normal | 95% (19/20) | 29.6 s | 29.6 s | win 19, dead 1 |
| spirewalker | bow | easy | 100% (20/20) | 32.5 s | 32.5 s | win 20 |
| spirewalker | bow | normal | 100% (20/20) | 32.5 s | 32.5 s | win 20 |
| spirewalker | daggers | easy | 100% (20/20) | 27.8 s | 27.8 s | win 20 |
| spirewalker | daggers | normal | 100% (20/20) | 27.8 s | 27.8 s | win 20 |
