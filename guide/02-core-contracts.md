# 02 Core contracts

Everything in `src/core` is node-free and seeded. A lane calls these; only the integrator (Lane P) changes them.

## HHHex (`hex.gd`)
Pointy-top odd-r. `Vector2i(col, row)`. Static: `to_cube`, `to_offset`, `distance`, `neighbors`, `area`, `ring`, `line`, `trail`, `ray`, `fringe`, `direction_index`, `step_beyond`, `to_world(h, size) -> Vector2 (x, z)`, `from_world`, `corners`. Unbounded; HHArena filters.

## HHTune (`tune.gd`)
All feel numbers. `value(key)`, `list(key)`, `set_value`, `reset`. Add a key to `DEFAULTS` with a comment; never hard-code a feel number elsewhere. The F1 panel (Lane P) edits these live.

## HHFormulas (`formulas.gd`)
`ELEMENTS` (seven, H2), `OPPOSITE`, `STATUS_ELEMENT`. Every function returns a calc `{ value, label, formula, values }`: `tile_damage(max_hp, pct, resist, mult)`, `hit(base, power, resist)`, `stagger_ticks(strength 0..1)`, `detonation_ring_pct(pct)`.

## HHArena (`arena.gd`)
The underlay over a heightfield. `cells: hex -> { walkable, kind, depth }`, `hf` (cols, rows, step, origin, data), `radius_m`, `skirt_m`, `spawns`. Queries: `exists`, `walkable`, `kind`, `depth`, `height_at(x, z)`, `hex_height`, `world(h) -> Vector3` (on the ground), `from_world`, `neighbors`, `walk_neighbors(h, blocked)` (cliff rule: `max_step_m`), `area`, `ring`, `path(from, to, blocked)`, `nearest_walkable(from, goal, blocked)`, `path_to_reach(from, target, reach, blocked)`. `to_dict` / `from_dict` for `arenas/*.json`. `round_flat(seed, radius_m, bumps)` is the Phase 0 stand-in; Lane C's generators return HHArena the same way.

Hex size is 1.0 m (H9). The floor is `radius_m`; an edge band ~1.8 m wide is `kind "edge"`, unwalkable (H17). `kind "rock"` holds no charge. `depth` is water depth for Lane C's pond rules.

## HHCharge (`charge.gd`)
The element grid. `entries: hex -> { h, v, marker, glaze, timer, source, permanent }`. `apply(hexes, element, caster, steps, fresh) -> { detonations, changed, marker_fired, gales, doused, overheat, overfreeze }`. `tick()` decays. Queries: `at`, `intensity(hex, el)`, `is_glazed`, `marker`, `charged`, `carries`, `move_mult`, `standing(hex)` (per-second pct), `crossing_pct`. `author(hex, h, v, marker)` for permanent biome state. Rules are documented at the top of the file; the tests in `test_charge.gd` are the spec.

## HHSim (`sim.gd`)
`TICK = 1/30`. `step(orders: { unit_id: order }) -> events`. Orders: `move: Vector2i`, `stop`, `target: id`, `run: bool`, `swap`, `paint: { element, hex, steps }` (sandbox). Units are dictionaries (fields listed at the top of the file). `paint()` resolves ground reactions into damage; `hurt(u, amount, cause, stagger)`, `heal`, `apply_status(u, name, ticks)`. `unit_at(hex)` respects monster footprints (`size`). `state_hash()` for replay checks. `over` is `"" | "win" | "dead"`.

Lane P adds casts (Q/E/R as orders with an aim hex) and the basic attack. Lane E adds a monster brain called from `step()` and telegraphs as hex sets with a countdown. Both go through `paint()` and `hurt()`.

## HHPhases (`phases.gd`)
`start(script) -> state`, `check(state, hp_frac, tick) -> fired ids`, `rule(state, key, def)`, `countdown`. Triggers: `hp_below`, `after`, `delay_ticks`. A monster's calm / aggravated / threatened / enraged states are a phase script plus its own brain.

## Events (from `step()`)
`move, arrive, swap, paint, detonate, overheat, overfreeze, gale, douse, hurt, heal, death, status, status_end, over`. Every event carries `tick`. The view reads events for one-shots (bursts, hit reactions); it reads state for everything continuous.
