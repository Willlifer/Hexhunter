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

### Commit feel (H56-H58, Lane W H950-H970)
- **Orders** added: `charge { skill: "q", aim }`, `charge_aim: Vector2i`, `release { skill: "q", aim }`, `dash: Vector3` (a world point), `potion: true | { aim }`. `cast` of q is an instant level-1 shot.
- **Hunter fields** (all plain data, replicated with the unit): `charging { skill, ticks, level, aim }`, `dash { from, to, ticks, total }`, `dash_charges`, `dash_recharge`, `dash_recover`, `dash_iframes`, `heal_zone { hex, radius, left, total, pct_per_s }`, `potion_hex`, `recovery`, `flinch`, `combo { step, until, target }`, `queued { o, until }`. **Monster field**: `exposed` (ticks).
- **Rules**: `held(u)` includes a dash, a recovery and a flinch; `escapable(u)` is a wind-up / recovery / charge; `break_commit(u, why)` is what the dash and the movement skills (`HHWeapons.ESCAPES`) do. `hurt(..., by, interrupt := true)`: a landed hit from a monster interrupts (`_interrupt`); guarded hits and reactions pass `interrupt = false`. `begin_recovery(u, ticks)` after every action. Basic strings: `HHWeapons.has_combo` / `combo_hit(weapon, step)`; weapons with a `combo(step)` func string their basics. Charged shapes: `HHWeapons.charge_shape(sim, u, aim, level) -> { hex: strength }` (each weapon's `q_shape`).
- **Events**: `charge_start`, `charge_level`, `charge_release`, `charge_cancel`, `dash`, `dash_end`, `dash_ready`, `dodge`, `potion { hex, radius }`, `heal_zone_end`, `recovery`, `combo { step }`, `combo_reset`, `interrupted { what, skill }`, `exposed`, `exposed_end`; `strike` may carry `combo`, `heavy`, `level`; `windup` carries `step` and `level`.
- **View**: `HHAimFx` (`src/game/fx/aim_fx.gd`, under the arena view) draws the range ring, the charge preview and pips, charge glows, heal zones, dash streaks and the exposed ring; the fight's hit-stop freezes bodies on heavy events. Review renders: `tools/feel_preview.gd` -> `design/feel/`.

## HHPhases (`phases.gd`)
`start(script) -> state`, `check(state, hp_frac, tick) -> fired ids`, `rule(state, key, def)`, `countdown`. Triggers: `hp_below`, `after`, `delay_ticks`. A monster's calm / aggravated / threatened / enraged states are a phase script plus its own brain.

## Events (from `step()`)
`move, arrive, swap, paint, detonate, overheat, overfreeze, gale, douse, hurt, heal, death, status, status_end, over`. Every event carries `tick`. The view reads events for one-shots (bursts, hit reactions); it reads state for everything continuous.

## Phase 3 contracts (H48): screens, launch config, registry, upgrades

**Screen.** Any top-level screen is a `Node` with `setup(cfg: Dictionary)` and `signal finished(result: Dictionary)`. `HHShell` (`src/game/shell.gd`, Lane L) owns the tree: `show(screen)` frees the current screen and adds the new one; it keeps `last_cfg` so "replay" and "new seed" are one call. No `change_scene`; F10 / Esc in a fight emits `finished({ result: "abort" })`.

**Launch config** (the one dictionary that starts a fight, Lane L):
```
cfg = { arena: "pond", monster: "swampfang", weapon: "lance",
        element: "fire", backup: "water", seed: 1,
        upgrades: { q: [], w: [], e: [], r: [] },     # upgrade ids slotted per skill, max 3 each
        locked: [],                                    # keys the prep screen may not change (hunt loop: arena, monster)
        cam: "30,44" }
```
`HHFight.setup_cfg(cfg)` builds the fight from it (the old `setup(arena, seed, monster, asset)` stays for tests). The fight emits `finished({ result: "win"|"fallen"|"abort", cfg, ticks, hp, monster_hp })`.

**Registry** (`src/game/registry.gd`, `HHRegistry`, Lane L): static tables `ARENAS`, `MONSTERS`, `WEAPONS`, `ELEMENTS` of rows `{ id, name, blurb, look: [tint_hex, TAG] }` plus `biome_of(monster) -> arena id`. Referenced by id; scripts load lazily by path (Gauntlet G66). `check()` verifies each id resolves to a file.

**Upgrades** (`src/progress/upgrades.gd`, `HHUpgrades`, Lane U): `TABLE: id -> { skill: "q"|"w"|"e"|"r", weapon: "lance"|"daggers"|"bow"|"any", name, blurb, drops_from: [monster ids] }`. A player unit carries `u.upgrades: Dictionary` (skill -> Array of ids), filled by `sim.add_player(..., upgrades)` (Lane U extends the signature with a trailing default argument). Weapon scripts ask `HHUpgrades.has(u, "id")`. `HHDrops.roll(monster_id, rng: RandomNumberGenerator) -> Array` of upgrade ids; `HHSave` (`user://hunter.json`): `{ owned: [ids], slotted: { weapon: { q: [], w: [], e: [], r: [] } }, hunts: [...] }` with `load_or_new()`, `save()`.

**Hunt loop** (`src/game/hunt/**`, Lane H): screens `HHWorldMap`, `HHAmbush`, `HHResults`; `HHHunt.start(shell)` runs map -> ambush -> prep (the lobby with `locked: ["arena", "monster"]`) -> fight -> results -> map. It reads `HHSave` / `HHDrops` through `ResourceLoader.exists` guards so it runs before Lane U merges.

## Reactions and the arena (H50, H51)
Reaction damage = `sim.reaction_unit(source)` x a multiplier: a player's auto attack at the lance's cadence (`HHWeapons.basic_damage * lance_basic_ticks / basic_ticks`), or `reaction_unit_other` for a monster or the arena. Detonations carry `mult` (and `pct` = the same number, for old readers). All blasts of one `paint()` are gathered per unit and landed by `_land_reactions`: strongest in full + `reaction_chain_frac` of each other; it emits `reaction { id, amount, blasts, cause }`.
`HHEnv` (`src/core/env.gd`, `sim.env`) ticks inside `step()` after projectiles. Its telegraphs have owner `"env"` and names `env_swell`, `env_vent`, `env_rockfall`, `env_sunbreak`, `env_gust`; the payload carries `env: true`.

## Phase 4 contracts (H52, H53): co-op

**Model (H52).** Host-authoritative state streaming. The host runs the only HHSim (brains, env, everything). A client never steps a sim: it holds a *mirror* HHSim (same arena, no brains) that the replicator overwrites from snapshots, so the view, HUD and bodies read it exactly as they read a local sim today. Clients send orders; the host applies each client's orders under that client's unit id on the next tick. Solo play never touches the network.

**Party config.** The launch cfg gains `players: [{ peer: int, id: "p1".."p4", name, weapon, element, backup, upgrades }]` (solo: one entry, peer 1) and `local_id` (which unit this machine controls; solo "p1"). `cfg.net = "solo" | "host" | "client"`.

**HHNet** (`src/net/net.gd`, Lane N): a Node the shell owns at `Shell/Net`. `host(port := 24631, max_peers := 3) -> Error`, `join(address, port := 24631) -> Error`, `leave()`, `is_host()`, `is_online()`, `peer_id()`, signals `peer_joined(peer)`, `peer_left(peer)`, `connected()`, `failed()`, `disconnected()`. ENetMultiplayerPeer on desktop; the transport is one function so Phase 5 can swap in WebSocketMultiplayerPeer.

**HHSession** (`src/net/session.gd`, Lane N): the party before a fight. `members: { peer: { name, weapon, element, backup, upgrades, ready } }`; `set_mine(fields)` (each peer edits its own row; RPC to host, host rebroadcasts), `host_set(cfg_fields)` (arena, monster, seed: host only), `all_ready()`, `start()` (host only: builds the launch cfg with `players` and sends it; every peer emits `start_fight(cfg)` with its own `local_id`). Signals `changed()`, `start_fight(cfg)`.

**HHSnapshot** (`src/net/snapshot.gd`, Lane N, node-free): `capture(sim) -> Dictionary` and `apply(sim, snap)`. Covers `tick`, `over`, every unit dictionary (Callables stripped: `leap.on_land`, `windup.on_done` become `null`; a mirror never resolves them), `charge.entries`, `telegraphs`, `projectiles`, `env.next_tick/count`. Full snapshot on join and every 30 ticks; deltas (changed units, changed charge hexes, telegraph adds/ends) every tick. Events the host's `step()` returned are forwarded alongside (the view, sfx and effects consume them on clients as on the host).

**HHReplicator** (`src/net/replicator.gd`, Lane N): a Node the fight adds when `cfg.net != "solo"`. Host: `collect(peer) -> orders` merged into the next `step()`, then `publish(tick, events)`. Client: `send_order(order)`, `signal snapshot_applied(events)`. The fight never calls RPCs itself.

**Sim (Lane S).** `add_player` for up to 4 hunters on `arena.spawns.player` (the arena JSON keeps one spawn; the sim fans out to the free walkable hexes around it); monster HP x `party_hp_mult` per extra hunter; co-op downed state: at 0 HP with an ally alive a hunter is `downed` (untargetable, no orders) and an ally standing adjacent for `revive_ticks` brings them back at `revive_hp_pct`; the fight is lost only when every hunter is down; solo keeps "fallen". Monsters spread pressure: a brain's target is the nearest *non-downed* hunter, with a threat bonus for the last hunter that hit it (`aggro_*` tune keys).

**Game (Lane C).** `HHFight.setup_cfg` builds every hunter in `cfg.players`, controls `cfg.local_id`, and in client mode applies replicated state instead of stepping. Other hunters get bodies, nameplates and party frames on the HUD; a downed hunter shows a revive ring. Lobby: Host / Join panel, party list, ready toggles; host-only tiles for arena/monster/seed. Hunt loop: the host's map drives the hunt; every peer sees every hunter's token; the ambush plays everywhere; prep is each peer's own lobby (arena/monster locked); results roll each peer's own drops into its own save.


### Net API as built (Lane N, H850-H863)
- **HHNet**: `host`, `join`, `leave`, `is_host`, `is_client`, `is_online`, `peer_id`, `peers()`, `poll()`, `send`, `send_encoded`, `session`, `player_name`, `accepting` / `refuse_reason`, `last_error` (a sentence), `names`, `stats` / `sent_rate`, `make_peer(server, address, port, peers)` (the transport seam); signals `peer_joined`, `peer_left`, `connected`, `failed`, `disconnected`, `message`. Each HHNet runs its own SceneMultiplayer on its own tree branch and sends raw packets, no RPCs. Joins are a versioned handshake the host can refuse; a dead join fails in 5 s; a vanished peer drops in 3-6 s.
- **HHSession**: `members`, `joined`, `fields`, `set_mine`, `host_set`, `all_ready`, `start(force := false) -> Error`, `build_cfg(peer)`, `unit_id(peer)`, `end_fight()`; signals `changed`, `start_fight(cfg)`.
- **HHSnapshot**: `capture`, `apply`, `delta`, `apply_delta`, `same`, `encode` / `decode`, `age_charge`, `clean`. Charge decay and telegraph / projectile countdowns are predicted on both ends; only real changes travel.
- **HHReplicator**: `attach(fight, sim, cfg)` (null in solo), `role`, `merge(local_orders)`, `publish(tick, events)`, `send_order(o)`, `request_full()`, `pump()`, `stats`; signals `snapshot_applied(events)`, `lost`.
- Measured: 11.7 KB/s per client compressed with four hunters; ~62 ms click-to-mirror on localhost; 0 mismatches across 1800 ticks; two real processes agree on every full snapshot.

### Online co-op through the relay (Lane R, H110-H119)
Browsers cannot listen and have no UDP; desktops behind routers need port forwarding for ENet. Online play goes through a public relay instead: `relay/relay.py` (Python, `websockets`), hosted as a Render free web service (`render.yaml`, click-steps in `relay/README.md`). Same model as LAN (H52): the relay only moves bytes.
- **HHNet**: `host_online(max_peers := 3)`, `join_online(code)`, `is_relay()`, `room`, `relay_url` (from `HHRelayConfig.url()`: the `URL` const in `src/net/relay_config.gd`, `--relay <url>` on desktop, `?relay=<url>` in a browser), signals `room_ready(code)` and `relay_status(text)`. `make_peer` builds an `HHRelayPeer` when online and always on the web (`host()` / `join(address)` there mean online, the address being the room code). Over the relay the 5 s JOIN_TIMEOUT starts at `connected_to_server`, not at `join`; `last_error` is the relay peer's sentence ("room not found: ...", "room full: ...", "host left", "could not reach the relay (...)"). A relay host that loses the relay gets `disconnected()`.
- **HHRelayPeer** (`src/net/relay_peer.gd`): a `MultiplayerPeerExtension` over one `WebSocketPeer` (or anything shaped like one: `make_socket`). The status turns CONNECTED only on the relay's `hosted` / `joined`; a joiner emits `peer_connected(1)` after that (SceneMultiplayer answers with `connected_to_server`, HHNet sends HELLO, `send_bytes` needs CONNECTED). A socket that never opens is retried every 2.5 s (each attempt cut at 12 s) for 90 s, with `status_text` "relay asleep, retrying… (N s)". The packet queue holds sender, channel and mode at its head for SceneMultiplayer. **Everything is reliable and ordered (TCP)**, whatever transfer mode is asked; CH_STREAM deltas never drop, they queue.
- **Protocol v1.** Hello (text JSON, first frame): `{"op":"host","v":1}` or `{"op":"join","v":1,"room":"KMRTX"}`. Replies: `hosted{room,id:1,max:5}` / `joined{room,id}`; the host also gets `peer_join{id}` / `peer_leave{id}` and may send `kick{id}`. Errors: `error{code,msg}` with code `not_found | full | rooms_full | busy | bad_request | version | host_left | idle | rate | slow | kicked`, then the relay closes (after 1 s, so the client reads it first). Data (binary): 5-byte header `[1=DATA][target, 0 = all but sender][sender, set by the relay][channel][mode]` + payload; joiners reach only the host, the host one peer or all. Ids are 1 (host) and 2..255. Room codes: 5 letters from `ACDEFHJKMNPRTWXY`.
- **Relay limits**: 5 per room, 256 KB frames, 200 rooms, 1000 connections, 10 s hello, 15 min idle per room, 300 frames/s (burst 900) and 256 KB/s (burst 1 MB) per connection, 512 queued frames per receiver (past it: "slow"), no compression, no payload logging. GET without Upgrade answers 200. Binds `0.0.0.0:$PORT` when PORT is set, else `127.0.0.1:8765` (`--port N`).
- **Lobby**: "Play together" has a LAN / Online switch (the web build is Online only). Online: Host online shows the ROOM code big with Copy; Join online takes the code (`HHRelayPeer.clean_code`: case and dashes forgiven). `HHLobbyCoop.host_online(name)`, `join_online(code, name)`, `online`, `room`, `share_code()`. Boot: `--host --online`, `--join-code <code>`, `--relay <url>`.
- **Tests**: `tests/test_net_relay.gd` (codec; HHNet host + client through HHRelayPeer over the in-process fake relay `tests/relay_fake.gd` with a 300-tick fight hash check; room not found / full / mid-hunt refusal / asleep-then-awake; the lobby's Online mode on the fake net). Real processes through a local relay: `tools/net_two_process.md`.
- Measured through a local relay, four hunters at Swampfang: 13.1-13.2 KB/s down per client, 33.7 KB/s up from the host (65 frames/s); two hunters 10.5 KB/s per client.
