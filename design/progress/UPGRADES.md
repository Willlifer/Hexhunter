# Upgrades (boss drops)

Source of truth: `src/progress/upgrades.gd` (`HHUpgrades.TABLE`). This page is the readable copy for the lobby, HUD and hunt-loop lanes (H550, H551). Every skill has three slots; an upgrade sits in the slot of the skill it modifies. "any" upgrades fit every weapon. Numbers are F1-editable under the prefixes shown.

| Weapon | Skill | Id | Name | One line | Drops from | Numbers |
|---|---|---|---|---|---|---|
| any | W | `exchange_immune` | Exchange Ward | Elemental Exchange grants 1 s of immunity. | Swampfang, Colambros | `upgrade_exchange_immune_ticks` 30 |
| any | W | `exchange_burst` | Exchange Nova | Elemental Exchange explodes your new element in a radius of 3 around you. | Colambros, Spirewalker | `upgrade_exchange_burst_radius` 3, `_steps` 1 |
| any | T | `potion_cleanse` | Clean Draught | A potion also clears burn, poison, slow and paralysis. | Swampfang, Spirewalker | none |
| lance | Q | `pierce_wide` | Broad Pierce | Pierce is three hexes wide (also widens Guard's counter). | Rimeslithe, Spirewalker | `lance_up_q_width` 3 |
| lance | E | `guard_stagger` | Staggering Guard | Guard's counter also staggers the monster hard. | Swampfang | `lance_up_e_stagger` 1.0 |
| lance | R | `eruption_twice` | Aftershock | Eruption lands twice: a second eruption on the same ground 1 s later (a telegraph). | Rimeslithe, Swampfang | `lance_up_r_echo_ticks` 30, `_pct` 1.5 |
| daggers | Q | `flourish_twin` | Twin Flourish | Flourish also lays your backup element on the ring just beyond its edge. | Swampfang, Spirewalker | `daggers_up_q_twin_steps` 1 |
| daggers | E | `daggerleap_homing` | Hunting Knives | Daggerleap's landing releases three fast knives that home on a monster within 6 hexes, painting the element you cast with as they fly. | Colambros | `daggers_up_e_homing_count` 3, `_range` 6, `_every` 2, `_max` 10, `_dmg` 60, `_stagger` 0.1, `_steps` 1 |
| daggers | R | `knifedance_long` | Long Dance | Knifedance lasts 9 s. | Rimeslithe, Colambros | `daggers_up_r_long_ticks` 270 |
| bow | Q | `energized_double` | Overcharged Shot | Energized Shot lays your element twice along its whole line. | Colambros, Spirewalker | `bow_up_q_double_steps` 2 |
| bow | E | `arcing_twice` | Cluster Shot | Arcing Shot bursts twice: six bomblets land in a wider ring half a second after the first burst. | Swampfang, Rimeslithe | `bow_up_e_echo_dist` 3, `_radius` 1, `_ticks` 15, `_pct` 0.5, `_steps` 1 |
| bow | R | `arrowstorm_glaze` | Frozen Storm | Arrowstorm's downfall freezes over: its element is glazed in place. | Rimeslithe | `bow_up_r_glaze_steps` 1 |

Per monster: Swampfang drops 6 (ward, cleanse, guard, aftershock, twin, cluster); Colambros 5 (ward, nova, knives, long dance, overcharged); Rimeslithe 5 (broad, aftershock, long dance, cluster, frozen); Spirewalker 5 (nova, cleanse, broad, twin, overcharged).

## How the pieces fit

- **Table and slots:** `HHUpgrades.slot(upgrades, skill, id, weapon)` enforces max 3 per skill and weapon fit; `for_weapon(weapon)` lists candidates; `check()` is empty when every row is well formed (tested).
- **Into the fight:** `sim.add_player(id, hex, element, backup, weapon, upgrades)` where `upgrades = { q: [], w: [], e: [], r: [], t: [] }` (the launch cfg's `upgrades`, from `HHSave.upgrades_for(weapon)`). The weapon script reads `HHUpgrades.has(u, id)` at the point of effect and emits an `upgrade { id, upgrade, ... }` event the view can flash.
- **Drops:** `HHDrops.roll(monster, sim.rng, weapon, save.owned)` -> 1-2 ids (35% two), weighted 3 / 2 / 1 for your weapon / any / other, never a duplicate; deterministic per seed.
- **Save:** `HHSave.load_or_new()` -> `own(id)`, `slot(weapon, skill, id)`, `unslot`, `record_hunt(monster, arena, weapon, result, seconds)`, `save()`. File `user://hunter.json`; `HHSave.path` is static for tests.

## How a projectile upgrade works (Hunting Knives)

The sim has a generic `projectiles` array (H553). A projectile is a hex that moves: `sim.launch({ owner, from, target, dir, spread, element, steps, every, max_hexes, dmg, stagger, cause })`.

1. On Daggerleap's landing the weapon finds the nearest targetable monster whose footprint is within `daggers_up_e_homing_range`, then launches `count` projectiles from the landing hex with `spread` -1 / 0 / +1 (the first step turns one hex direction each way, so three distinct lanes). The element is the one the hunter had **when the leap was cast** (`u.daggerleap_element`), not the current one.
2. Every `every` ticks (2 = 15 hexes a second) `_projectiles()` moves each one step: toward the target's nearest footprint hex when there is a live target, else straight on along `dir`. The hex it enters is painted `element` x `steps` through `sim.paint` (so reactions, pillar damage and H33 self-immunity all apply as usual).
3. Entering a hex occupied by a targetable unit of another kind strikes it (`sim.strike`, so rear multipliers and resistances apply) and ends the projectile. Off the arena or after `max_hexes` it ends. Events: `projectile { phase: launch | step | hit | end, hex, trail }`.
4. The view (Lane V) draws `sim.projectiles` each frame (`hex`, `element`, `owner`) and reacts to the events; nothing else is needed on the scene side.

Monsters and future weapons can launch the same thing (a spit, a rolling boulder) with the same spec.
