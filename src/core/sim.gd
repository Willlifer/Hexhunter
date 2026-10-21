class_name HHSim
extends RefCounted
## The fight as pure state on a fixed 30 Hz tick (H7, H8). No nodes. Same
## seed + same orders = same fight (state_hash proves it). HHFight draws it
## and feeds it orders; monster brains (Lane E) are objects in `brains`.
##
## Movement (H31): PLAYERS move freely on a continuous world position. The
## hex underlay routes them around obstacles (a BFS path of waypoints that is
## string-pulled so straight runs stay straight) and decides what hits them:
## `u.hex` is always the hex under `u.pos`. Attacks originate from and land
## on hexes. MONSTERS keep the hex-to-hex glide (slow, heavy, readable).
## Players run by default (H37); `run: false` is the walk.
##
## A unit: { id, kind, hex, pos: Vector3, prev, progress (monsters), path:
##   Array[Vector2i] (waypoints), goal_pos: Vector3 (players: the exact point
##   clicked, NO_POS = none), facing, hp, max_hp, element, backup, reach, size,
##   run, target, attacking, stagger, statuses, cooldowns { q w e r basic },
##   crossed, weapon, guard, leap, windup { left, total, kind, data },
##   allowed_kinds, untargetable, resist, upgrades (skill -> [ids], H550),
##   immune (ticks that hurt() skips, H552),
##   co-op (H53, Lane S): downed (bool: a hunter at 0 HP with an ally up; hp
##   stays 0 so every alive() check skips it), revive (float ticks of revive
##   progress), revive_by (id of the ally reviving, "" = none), hurt_tick (last
##   tick hurt() landed), aggro_id / aggro_tick (monsters: the hunter that hit
##   it last and when), party_scale (monsters: the HP factor applied),
##   H56 (Lane W, hunters only): charging ({} or { skill, ticks, level, aim }:
##   a held Q), dash ({} or { from, to: Vector3, ticks, total }), dash_charges,
##   dash_recharge (ticks to the next charge), dash_recover (ticks before the
##   next dash), dash_iframes (ticks of dodge left), heal_zone ({} or { hex,
##   radius, left, total, pct_per_s }: the hunter's thrown potion on the
##   ground), potion_hex (where the last potion landed) }
##
## Co-op (H53): up to 4 hunters. add_player fans hunters 2..4 out round the
## spawn; monster HP scales with the party (scale_for_party); a hunter at 0 HP
## with another standing is downed, not dead, and an ally next to it for
## revive_ticks brings it back; `over` is "dead" only when no hunter stands.
## Brains pick their prey with monster_target(). Hunters never hurt each other
## (party_friendly_fire 0): H33's "your own element" covers the whole party.
##
## Orders per unit per tick (all optional):
##   { move: Vector2i, move_pos: Vector3 (the exact point), stop: true,
##     target: id, attack: true (right-click on the monster, H32), run: bool,
##     swap: true, cast: { skill, aim: Vector2i }, potion: true | { aim: Vector2i }
##     (T: a throw at aim, H40/H56; true = at your feet), paint: {...} (sandbox),
##     H56 charged Q: charge: { skill: "q", aim } (key down), charge_aim: Vector2i
##     (aim updates while held), release: { skill: "q", aim } (key up; a charge
##     and a release in one tick is a tap), dash: Vector3 (Shift: toward that
##     world point; on the hunter = the way it was moving) }
## A `cast` of q is still an instant level-1 shot (tests, old bots).

const TICK := 1.0 / 30.0
const NO_POS := Vector3(INF, INF, INF)

var rng := RandomNumberGenerator.new()
var seed := 1
var tick := 0
var arena: HHArena
var charge: HHCharge
var units := {}
var order: Array = []
var brains := {}
var env: HHEnv = null           # H51: swells, vents, rockfalls, sunbreaks and gusts
var hooks := {}                # unit id -> Object with tick(sim, u): a weapon's per-tick work (Knifedance), H42
var projectiles: Array = []    # generic moving hexes, stepped per tick (H553): see launch()
var telegraphs: Array = []
var events: Array = []
var over := ""
var sandbox := false
var _next_tg := 1

## Difficulty tiers (Lane D, H240-H242). Every fight behaviour that existed on
## 2026-10-21 IS the EASY tier and runs on every tier; new behaviour (enrage,
## element pulse, purge, avoidance, set-pieces) is added behind
## `tier_at_least("normal")`, never by changing what EASY does. Today nothing
## is gated yet, so NORMAL and HARD play exactly like EASY (test_difficulty
## proves the hashes match). HARD is defined so later lanes can gate on it; it
## is not offered in the lobby until something differs. Set it once, before
## the first step(), from the launch cfg's "difficulty"; it is in state_hash
## and in every co-op snapshot.
const TIERS := ["easy", "normal", "hard"]
var difficulty := "easy"


func _init(p_arena: HHArena, p_seed: int = 1, p_difficulty: String = "easy") -> void:
	arena = p_arena
	seed = p_seed
	difficulty = clean_tier(p_difficulty)
	rng.seed = p_seed
	charge = HHCharge.new(arena)
	charge.author_rows(arena.authored_rows())            # H43: the biome's permanent charge
	env = HHEnv.new(self)                                # H51: the arena's own recurring events


# ------------------------------------------------------------------ difficulty (H240)

## A known tier id, else "easy" (unknown / empty / old cfgs play as today).
static func clean_tier(t: Variant) -> String:
	var s := str(t).strip_edges().to_lower()
	return s if s in TIERS else "easy"


## 0 easy, 1 normal, 2 hard.
static func tier_rank(t: String) -> int:
	return maxi(0, TIERS.find(clean_tier(t)))


## The gate for every behaviour above EASY: `if sim.tier_at_least("normal"):`.
## A misspelt tier is an error and gates nothing on (false), never everything.
func tier_at_least(t: String) -> bool:
	var want := TIERS.find(t)
	if want < 0:
		push_error("HHSim.tier_at_least: unknown tier '%s' (one of %s)" % [t, TIERS])
		return false
	return tier_rank(difficulty) >= want


func set_difficulty(t: Variant) -> void:
	difficulty = clean_tier(t)


# ------------------------------------------------------------------ setup

## A hunter. The first one stands on `hex`; later ones (H53) fan out from it
## to a free, safe hex (party_spawn), so every arena's single spawn seats four.
## Every hunter faces the monster's spawn. Monster HP rescales (scale_for_party).
func add_player(id: String, hex: Vector2i, element: String = "fire", backup: String = "water", weapon: String = "lance", upgrades: Dictionary = {}) -> Dictionary:
	var at := party_spawn(hex)
	var u := _unit(id, "player", at)
	_face_pos(u, arena.stand(arena.spawns.get("monster", at)))
	var ups := {}                                        # H550: skill -> Array of upgrade ids, copied
	for k in upgrades:
		ups[str(k)] = Array(upgrades[k]).duplicate()
	u.upgrades = ups
	u.max_hp = HHTune.value("player_hp")
	u.hp = u.max_hp
	u.element = element
	u.backup = backup
	u.weapon = weapon
	u.reach = HHWeapons.reach(weapon)
	u.run = true
	u.potions = int(HHTune.value("potion_count"))
	u.cooldowns["t"] = 0
	u.charging = {}                                      # H56: the held Q
	u.dash = {}
	u.dash_charges = int(HHTune.value("dash_charges"))
	u.dash_recharge = 0
	u.dash_recover = 0
	u.dash_iframes = 0
	u.heal_zone = {}
	u.recovery = 0                                       # H57: rooted ticks after an action
	u.flinch = 0                                         # H58: held after a landed monster hit
	u.combo = {}                                         # H57: { step, until, target } (lance, daggers)
	u.queued = {}                                        # H57: a buffered press { o, until }
	scale_for_party()
	return u


func add_monster(id: String, hex: Vector2i, hp: float = 20000.0, size: int = 2, allowed_kinds: Array = []) -> Dictionary:
	var u := _unit(id, "monster", hex)
	u.max_hp = hp
	u.hp = hp
	u.size = size
	u.reach = size + 1
	u.allowed_kinds = allowed_kinds
	u.party_scale = 1.0
	u.exposed = 0                                        # H57: ticks left of a punish window (replicates)
	scale_for_party()
	return u


# ------------------------------------------------------------------ party (H53)

## Monster HP factor for the current party: 1 + party_hp_mult per extra hunter.
func party_factor() -> float:
	return 1.0 + HHTune.value("party_hp_mult") * float(maxi(0, players().size() - 1))


## Rescale every monster's max HP (and HP, proportionally) to the party.
## Called by add_player and add_monster, so callers never need to; idempotent:
## a monster remembers the factor it carries (party_scale) and only the change
## is applied, so solo (factor 1) never touches HP and a test that set HP by
## hand keeps it.
func scale_for_party() -> void:
	var f := party_factor()
	for m in monsters():
		var cur := float(m.get("party_scale", 1.0))
		if absf(f - cur) < 1e-6:
			continue
		m.max_hp = float(m.max_hp) * f / cur
		m.hp = float(m.hp) * f / cur
		m.party_scale = f
		_emit({ "type": "party_scale", "id": m.id, "factor": f, "max_hp": m.max_hp })


## Where a new hunter stands: `want` when no hunter is within party_spawn_min
## of it, else the best safe hex round it: walkable plain ground (floor, pad,
## sun; never water, lava, rock, vents, shade), no charge on it, clear of the
## monster's spawn, reachable from `want` by a short path, party_spawn_min+
## from every hunter. Preference: party_spawn_min..max from its NEAREST hunter
## (the party stands 2-3 apart), then closest to `want`, then abreast of
## `want` (same distance to the monster spawn), then hex order. A thin spawn
## (the pond's shore) strings the party along it rather than into the water.
## Deterministic; never consumes the RNG.
func party_spawn(want: Vector2i) -> Vector2i:
	var others := players()
	var min_d := int(HHTune.value("party_spawn_min"))
	if others.all(func(o): return HHHex.distance(o.hex, want) >= min_d):
		return want
	var max_d := int(HHTune.value("party_spawn_max"))
	var mon: Vector2i = arena.spawns.get("monster", want)
	var mon_d := HHHex.distance(want, mon)
	var blocked := {}
	for m in monsters():
		for h in footprint(m):
			blocked[h] = true
	var best := want
	var best_key := []
	for r in range(1, max_d * 2 + 3):
		for h in arena.ring(want, r):
			if not _spawn_ok(h, blocked, mon):
				continue
			var near := 1 << 30
			for o in others:
				near = mini(near, HHHex.distance(o.hex, h))
			if near < min_d:
				continue
			var p := arena.path(want, h, blocked)
			if p.is_empty() or p.size() > r + 3:
				continue
			var band := 0 if near <= max_d else 1
			var key := [band, r, absi(HHHex.distance(h, mon) - mon_d), h.y, h.x]
			if best_key.is_empty() or _key_less(key, best_key):
				best_key = key
				best = h
	return best


const SPAWN_KINDS := ["floor", "pad", "sun"]


func _spawn_ok(h: Vector2i, blocked: Dictionary, mon: Vector2i) -> bool:
	return arena.walkable(h) and arena.kind(h) in SPAWN_KINDS and not blocked.has(h) \
		and charge.at(h).is_empty() and HHHex.distance(h, mon) > 4


static func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Hunters standing (alive and not downed).
func standing_players() -> Array:
	return players().filter(func(p): return alive(p) and not bool(p.get("downed", false)))


## Two different hunters, with friendly fire off (party_friendly_fire 0):
## they never hurt, slow or blast each other (H33 extended to the party).
func allies(a_id: String, b_id: String) -> bool:
	if a_id == b_id or a_id == "" or b_id == "" or HHTune.value("party_friendly_fire") > 0.5:
		return false
	return str(unit(a_id).get("kind", "")) == "player" and str(unit(b_id).get("kind", "")) == "player"


## The ground under `u` counts as its own when it or an ally painted it.
func _ground_owner(u: Dictionary, hex: Vector2i) -> String:
	var src := str(charge.at(hex).get("source", ""))
	return src if allies(src, u.id) else str(u.id)


## H53 aggro: the hunter a monster goes for. The nearest standing hunter (hex
## distance), where the one that hit `m` last (aggro_id) counts as
## aggro_hit_bonus_hexes closer for aggro_memory_ticks after that hit. Ties go
## to the earlier hunter in `order`. Solo it is exactly the old nearest-alive
## pick. {} when nobody stands.
func monster_target(m: Dictionary) -> Dictionary:
	var held := unit(str(m.get("commit_id", "")))       # H54: hold a target a while (it flipped 9-35 times a fight)
	if not held.is_empty() and alive(held) and not bool(held.get("downed", false)) and tick < int(m.get("commit_until", -1)):
		return held
	var picked := _monster_target_pick(m)
	if not picked.is_empty() and str(picked.id) != str(m.get("commit_id", "")):
		m["commit_id"] = str(picked.id)
		m["commit_until"] = tick + int(HHTune.value("aggro_commit_ticks"))
	return picked


func _monster_target_pick(m: Dictionary) -> Dictionary:
	var hot := str(m.get("aggro_id", ""))
	if hot != "" and tick - int(m.get("aggro_tick", -1)) > int(HHTune.value("aggro_memory_ticks")):
		hot = ""
	var bonus := HHTune.value("aggro_hit_bonus_hexes")
	var best := {}
	var best_s := INF
	for p in players():
		if not alive(p) or bool(p.get("downed", false)):
			continue
		var s := float(HHHex.distance(m.hex, p.hex))
		if p.id == hot:
			s -= bonus
		if s < best_s:
			best_s = s
			best = p
	return best


func _unit(id: String, kind: String, hex: Vector2i) -> Dictionary:
	var u := {
		"id": id, "kind": kind, "hex": hex, "prev": hex, "progress": 0.0, "path": [] as Array[Vector2i],
		"goal_pos": NO_POS, "pos": arena.stand(hex), "facing": 0.0, "hp": 1.0, "max_hp": 1.0,
		"element": "", "backup": "", "reach": 1, "size": 0, "run": false, "target": "", "attacking": false,
		"stagger": 0, "statuses": {}, "cooldowns": { "q": 0, "w": 0, "e": 0, "r": 0, "basic": 0 },
		"crossed": hex, "weapon": "", "guard": 0, "leap": {}, "windup": {}, "allowed_kinds": [],
		"untargetable": false, "resist": {}, "potions": 0, "regen": {}, "upgrades": {}, "immune": 0,
		"downed": false, "revive": 0.0, "revive_by": "", "hurt_tick": -1, "aggro_id": "", "aggro_tick": -1,
	}
	units[id] = u
	order.append(id)
	return u


func unit(id: String) -> Dictionary:
	return units.get(id, {})


func players() -> Array:
	return order.map(func(i): return units[i]).filter(func(u): return u.kind == "player")


func monsters() -> Array:
	return order.map(func(i): return units[i]).filter(func(u): return u.kind == "monster")


func alive(u: Dictionary) -> bool:
	return float(u.hp) > 0.0


func targetable(u: Dictionary) -> bool:
	return alive(u) and not bool(u.untargetable)


func footprint(u: Dictionary) -> Array:
	if int(u.size) <= 0:
		return [u.hex]
	return HHHex.area(u.hex, int(u.size))


## Walls for `me`: living monsters' hulls (not its own) plus, for a
## monster, the cells outside its allowed kinds. H250: a monster's walls are
## the other hulls grown by its own size (its centre may not stand where its
## hull would overlap another's); a hunter standing inside a hull (a moving
## monster glided onto it) is not walled by that hull, so it can walk out.
func blocked_for(me: Dictionary) -> Dictionary:
	var b := {}
	var grow := int(me.size) if str(me.kind) == "monster" else 0
	for id in order:
		var o: Dictionary = units[id]
		if o.id == me.id or not alive(o) or o.kind != "monster":
			continue
		if grow == 0 and in_hull(o, me.hex):
			continue
		for h in HHHex.area(o.hex, int(o.size) + grow):
			b[h] = true
	var allowed: Array = me.allowed_kinds
	if not allowed.is_empty():
		for h in arena.cells:
			if not arena.kind(h) in allowed:
				b[h] = true
	return b


func unit_at(hex: Vector2i) -> Array:
	var out: Array = []
	for id in order:
		var u: Dictionary = units[id]
		if not alive(u):
			continue
		if u.hex == hex or (int(u.size) > 0 and HHHex.distance(u.hex, hex) <= int(u.size)):
			out.append(u)
	return out


func nearest_hex_of(t: Dictionary, from: Vector2i) -> Vector2i:
	var best: Vector2i = t.hex
	var bd := HHHex.distance(from, best)
	for h in footprint(t):
		var d := HHHex.distance(from, h)
		if d < bd:
			bd = d
			best = h
	return best


## Every targetable unit standing in `hexes` (footprints count), except `skip`.
func units_in(hexes: Array, skip: String = "") -> Array:
	var seen := {}
	var out: Array = []
	for h in hexes:
		for u in unit_at(h):
			if u.id == skip or seen.has(u.id) or not targetable(u):
				continue
			seen[u.id] = true
			out.append(u)
	return out


# ------------------------------------------------------------------ the hull (H250-H259, Lane H)
## A monster's hull is its footprint: every hex within `size` of its hex (the
## radius-2 monsters hold 19 hexes; a size-1 monster would hold 7). Hunters
## never step into a hull (blocked_for). The Attack Ring is the ring of hexes
## bordering it (size + 1: 18 hexes round a radius-2 hull, 12 round a radius-1). A weapon hits from any hex
## outside the hull within its reach of the hull's edge (daggers 1 = the
## Attack Ring, lance 2, bow 7: HHWeapons.reach). A monster that is moving
## may glide over a hunter (H338); once it stands still (arrived, stopped,
## landed from a leap, surfaced) any hunter inside its hull is slid at once to
## the nearest free Attack Ring hex (_push_out): not a hit, no damage, no
## stagger, no interrupt. All of it is deterministic: no RNG, fixed tie-breaks.

const NO_HEX := Vector2i(-9999, -9999)


func in_hull(m: Dictionary, hex: Vector2i) -> bool:
	return HHHex.distance(m.hex, hex) <= int(m.size)


## Standing still: no glide under way and not in the air.
func stationary(m: Dictionary) -> bool:
	return (m.path as Array).is_empty() and (m.leap as Dictionary).is_empty()


## H251: the hull holds its hexes (push-out acts): a living, surfaced monster
## standing still. A submerged Swampfang (untargetable) or a monster mid-glide
## or mid-leap does not push; it pushes the tick it stops.
func occupying(m: Dictionary) -> bool:
	return str(m.kind) == "monster" and alive(m) and not bool(m.untargetable) and stationary(m)


func attack_ring(m: Dictionary) -> Array[Vector2i]:
	return arena.ring(m.hex, int(m.size) + 1)


## Every hex inside a living monster's hull (except `skip`'s).
func hull_hexes(skip: String = "") -> Dictionary:
	var out := {}
	for id in order:
		var o: Dictionary = units[id]
		if o.kind != "monster" or not alive(o) or o.id == skip:
			continue
		for h in HHHex.area(o.hex, int(o.size)):
			out[h] = true
	return out


## H252: `u` can hit `t` from `h`: outside the hull, within the weapon's reach
## of the hull's edge.
func in_attack_range(u: Dictionary, t: Dictionary, h: Vector2i = NO_HEX) -> bool:
	var d := HHHex.distance(u.hex if h == NO_HEX else h, t.hex)
	return d > int(t.size) and d <= int(t.size) + int(u.reach)


## H252: where `u` goes to hit `t`, and the path there: { hex, path }. The
## pathfinder never aims at the monster's centre. It takes the hex in range
## (in_attack_range) fewest steps away, a spot another hunter stands on or is
## heading to costing attack_spot_claimed_steps more (the party spreads round
## the ring), then the nearest to the hunter's exact position, then hex order.
## Already in range: { hex: u.hex, path: [] }. Nothing reachable: hex NO_HEX.
func attack_spot(u: Dictionary, t: Dictionary) -> Dictionary:
	var empty: Array[Vector2i] = []
	if in_attack_range(u, t):
		return { "hex": u.hex, "path": empty }
	var blocked := blocked_for(u)
	var claimed := {}
	for p in players():
		if p.id == u.id or not (alive(p) or bool(p.get("downed", false))):
			continue
		claimed[p.hex] = true
		if str(p.target) == str(t.id) and not (p.path as Array).is_empty():
			claimed[(p.path as Array)[-1]] = true
	var cost := int(HHTune.value("attack_spot_claimed_steps"))
	var start: Vector2i = u.hex
	var prev := { start: start }
	var depth := { start: 0 }
	var queue: Array[Vector2i] = [start]
	var qi := 0
	var limit := 1 << 30
	var best := NO_HEX
	var best_key := []
	var at: Vector3 = u.pos
	while qi < queue.size():
		var h := queue[qi]
		qi += 1
		var d: int = depth[h]
		if d > limit:
			break
		if h != start and in_attack_range(u, t, h):
			var s := arena.stand(h)
			var key := [d + (cost if claimed.has(h) else 0), Vector2(s.x - at.x, s.z - at.z).length_squared(), h.y, h.x]
			if best_key.is_empty() or _key_less(key, best_key):
				best_key = key
				best = h
			if limit == 1 << 30:
				limit = d + cost
		for n in arena.walk_neighbors(h, blocked):
			if not prev.has(n):
				prev[n] = h
				depth[n] = d + 1
				queue.append(n)
	if best == NO_HEX:
		return { "hex": NO_HEX, "path": empty }
	var out: Array[Vector2i] = []
	var cur := best
	while cur != start:
		out.push_front(cur)
		cur = prev[cur]
	return { "hex": best, "path": out }


## H253: where a hunter inside `m`'s hull is slid to: the Attack Ring hex
## nearest its exact position that is walkable, outside every hull, and not
## held by another hunter (nor taken by a push this tick) when one such
## exists; else the nearest shared one; else the next ring out.
func push_spot(m: Dictionary, p: Dictionary, taken: Dictionary = {}) -> Vector2i:
	var walls := hull_hexes()
	var held := {}
	for q in players():
		if q.id != p.id and (alive(q) or bool(q.get("downed", false))):
			held[q.hex] = true
	var at: Vector3 = p.pos
	for r in range(int(m.size) + 1, int(m.size) + 2 + int(HHTune.value("push_out_max_rings"))):
		var best := NO_HEX
		var best_key := []
		for h in arena.ring(m.hex, r):
			if not arena.walkable(h) or walls.has(h):
				continue
			var s := arena.stand(h)
			var key := [1 if (taken.has(h) or held.has(h)) else 0, Vector2(s.x - at.x, s.z - at.z).length_squared(), h.y, h.x]
			if best_key.is_empty() or _key_less(key, best_key):
				best_key = key
				best = h
		if best != NO_HEX:
			return best
	return NO_HEX


## H253: every hunter (standing or downed, not in the air) inside a still
## hull slides out. Monsters in `order`, then hunters in `order`; two hunters
## never get the same hex when the ring has room.
func _push_out() -> void:
	var taken := {}
	for mid in order:
		var m: Dictionary = units[mid]
		if not occupying(m):
			continue
		for pid in order:
			var p: Dictionary = units[pid]
			if p.kind != "player" or not (alive(p) or bool(p.get("downed", false))):
				continue
			if not (p.leap as Dictionary).is_empty() or not in_hull(m, p.hex):
				continue
			var to := push_spot(m, p, taken)
			if to == NO_HEX:
				continue
			taken[to] = true
			_shove(p, m, to)


## H250: stepping a monster's hex to `next` would make its hull touch another
## monster's (where it stands, or the hex it is gliding into). Paths are
## planned round the other hulls; this catches two monsters walking at each
## other. One monster alone never clashes.
func _hull_clash(u: Dictionary, next: Vector2i) -> bool:
	for id in order:
		var o: Dictionary = units[id]
		if o.id == u.id or o.kind != "monster" or not alive(o):
			continue
		var reach := int(o.size) + int(u.size)
		if HHHex.distance(next, o.hex) <= reach:
			return true
		if not (o.path as Array).is_empty() and HHHex.distance(next, (o.path as Array)[0]) <= reach:
			return true
	return false


## Slide `p` to `to`: position and hex at once (the view eases it), no
## crossing burn, a dash under way ends, a walk re-routes from the new spot.
func _shove(p: Dictionary, m: Dictionary, to: Vector2i) -> void:
	var from_hex: Vector2i = p.hex
	var from_pos: Vector3 = p.pos
	p.prev = from_hex
	p.hex = to
	p.pos = arena.stand(to)
	p.crossed = to
	if not (p.get("dash", {}) as Dictionary).is_empty():
		p.dash = {}
		p.dash_recover = int(HHTune.value("dash_recover_ticks"))
		_emit({ "type": "dash_end", "id": p.id, "hex": to })
	var path: Array = p.path
	if str(p.target) != "" and bool(p.attacking):
		p.path = [] as Array[Vector2i]                  # the approach is re-planned from here (attack_spot)
		p.goal_pos = NO_POS
	elif not path.is_empty() or (p.goal_pos as Vector3) != NO_POS:
		var dest: Vector2i = path[-1] if not path.is_empty() else arena.from_world(p.goal_pos)
		var blocked := blocked_for(p)
		var goal := arena.nearest_walkable(to, dest, blocked)
		p.path = arena.path(to, goal, blocked)
		if goal != dest or (p.path as Array).is_empty():
			p.goal_pos = NO_POS
	_emit({ "type": "push_out", "id": p.id, "by": m.id, "from": from_hex, "to": to, "from_pos": from_pos, "to_pos": p.pos })


## A hunter's walk ran into a hull (a monster stepped into its way): route
## round it to the same destination instead of stopping. From the hunter's
## own hex centre, hex centre to hex centre for a moment (a centre-to-centre
## step never clips a third hex). False when there is no way round.
func _reroute(u: Dictionary, blocked: Dictionary) -> bool:
	var path: Array = u.path
	var dest: Vector2i
	if not path.is_empty():
		dest = path[-1]
	elif (u.goal_pos as Vector3) != NO_POS:
		dest = arena.from_world(u.goal_pos)
	else:
		return false
	var goal := arena.nearest_walkable(u.hex, dest, blocked)
	var np := arena.path(u.hex, goal, blocked)
	if np.is_empty():
		return false
	if goal != dest:
		u.goal_pos = NO_POS
	np.push_front(u.hex)
	u.path = np
	u.unpull_until = tick + 15
	return true


# ------------------------------------------------------------------ the tick

func step(orders: Dictionary = {}) -> Array:
	events = []
	if over != "":
		return events
	tick += 1
	for id in order:
		var u: Dictionary = units[id]
		if alive(u) and orders.has(id):
			_orders(u, orders[id])
	for id in order:
		var u: Dictionary = units[id]
		if alive(u) and u.kind == "player":
			_charge_tick(u)
			_queued_tick(u)
	for id in brains.keys():
		var u: Dictionary = units.get(id, {})
		if not u.is_empty() and alive(u):
			if difficulty == "easy":
				brains[id].tick(self, u)
			else:
				HHTierBrain.tick(self, brains[id], u)    # Lane M (H360): spec 7 and 8, NORMAL and up only
	for id in hooks.keys():
		var u: Dictionary = units.get(id, {})
		if not u.is_empty() and alive(u):
			hooks[id].tick(self, u)
	_projectiles()
	if env != null:
		env.tick()
	for id in order:
		var u: Dictionary = units[id]
		if alive(u):
			_windup(u)
			if u.kind == "player":
				_walk_free(u)
			else:
				_walk_hex(u)
	_telegraphs()
	_push_out()                                          # H253: after the landing's own damage, before anyone acts on the new spot
	for id in order:
		var u: Dictionary = units[id]
		if alive(u) and u.kind == "player":
			_auto_attack(u)
	if tick % int(HHTune.value("ground_tick_every")) == 0:
		for id in order:
			var u: Dictionary = units[id]
			if alive(u):
				_ground(u)
				_statuses(u)
		_heal_zones()
	for id in order:
		var u: Dictionary = units[id]
		for k in u.cooldowns:
			if int(u.cooldowns[k]) > 0:
				u.cooldowns[k] = int(u.cooldowns[k]) - 1
		if int(u.guard) > 0:
			u.guard = int(u.guard) - 1
		if int(u.immune) > 0:
			u.immune = int(u.immune) - 1
		if u.kind == "player":
			_dash_timers(u)
			if int(u.get("recovery", 0)) > 0:
				u.recovery = int(u.recovery) - 1
			if int(u.get("flinch", 0)) > 0:
				u.flinch = int(u.flinch) - 1
		elif int(u.get("exposed", 0)) > 0:
			u.exposed = int(u.exposed) - 1
			if int(u.exposed) == 0:
				_emit({ "type": "exposed_end", "id": u.id })
	charge.tick()
	if tick % int(HHTune.value("authored_reform_every")) == 0:
		charge.author_rows(arena.authored_rows(), true)  # H44: vents, lava and shade re-form
	_revives()
	_check_over()
	return events


func _emit(e: Dictionary) -> void:
	e["tick"] = tick
	events.append(e)


## Committed to an action (wind-up, vault, stagger, paralysis): no new moves.
func held(u: Dictionary) -> bool:
	return int(u.stagger) > 0 or _paralysed(u) or not (u.leap as Dictionary).is_empty() or not (u.windup as Dictionary).is_empty() \
		or not (u.get("dash", {}) as Dictionary).is_empty() or int(u.get("recovery", 0)) > 0 or int(u.get("flinch", 0)) > 0


## H57: held only by a commit an escape may break: a wind-up, a recovery or a
## held charge (not a stagger, a flinch, paralysis, a leap or a dash).
func escapable(u: Dictionary) -> bool:
	if int(u.stagger) > 0 or _paralysed(u) or not (u.leap as Dictionary).is_empty() \
			or not (u.get("dash", {}) as Dictionary).is_empty() or int(u.get("flinch", 0)) > 0:
		return false
	return not (u.windup as Dictionary).is_empty() or int(u.get("recovery", 0)) > 0 or charging(u)


## H57: an escape (the dash, a movement skill) breaks the commit: the wind-up
## does not happen, the recovery ends, a held charge is lost (spent). The
## combo string resets.
func break_commit(u: Dictionary, why: String) -> void:
	var w: Dictionary = u.windup
	if not w.is_empty():
		u.windup = {}
		_emit({ "type": "windup_broken", "id": u.id, "kind": str(w.kind), "why": why })
	u.recovery = 0
	if charging(u):
		cancel_charge(u, "dash")
	_combo_reset(u, why)


func _combo_reset(u: Dictionary, why: String) -> void:
	if not (u.get("combo", {}) as Dictionary).is_empty():
		u.combo = {}
		_emit({ "type": "combo_reset", "id": u.id, "why": why })


## H57: a buffered press fires once nothing holds the hunter; dropped when stale.
func _queued_tick(u: Dictionary) -> void:
	var q: Dictionary = u.get("queued", {})
	if q.is_empty():
		return
	if tick > int(q.until):
		u.queued = {}
		return
	if held(u) or charging(u):
		return
	u.queued = {}
	_orders(u, q.o)


## H58: a monster attack landed on a hunter: the wind-up, a held charge (no
## shot, no cooldown spent), the combo string and the recovery are cancelled,
## and a short flinch holds it (a stagger still wins when longer).
func _interrupt(u: Dictionary, cause: String) -> void:
	var what: Array = []
	var w: Dictionary = u.windup
	if not w.is_empty():
		u.windup = {}
		what.append(str(w.kind))
		_emit({ "type": "windup_broken", "id": u.id, "kind": str(w.kind), "why": "interrupted" })
	var skill := interrupted_skill(w)
	if charging(u):
		what.append("charge")
		skill = str(u.charging.skill)
		cancel_charge(u, "interrupted")
	if not (u.get("combo", {}) as Dictionary).is_empty():
		what.append("combo")
		_combo_reset(u, "interrupted")
	if int(u.get("recovery", 0)) > 0:
		what.append("recovery")
		u.recovery = 0
	u.queued = {}
	u.flinch = maxi(int(u.get("flinch", 0)), int(HHTune.value("flinch_ticks")))
	_stop(u)
	_emit({ "type": "interrupted", "id": u.id, "what": ",".join(PackedStringArray(what)), "skill": skill, "cause": cause })


## The skill box a cancelled wind-up belongs to (the HUD flashes it).
static func interrupted_skill(w: Dictionary) -> String:
	match str(w.get("kind", "")):
		"pierce", "energized", "flourish": return "q"
		"exchange": return "w"
		"potion": return "t"
		"basic": return "basic"
	return ""


## H56: a hunter holding a charged Q.
func charging(u: Dictionary) -> bool:
	return not (u.get("charging", {}) as Dictionary).is_empty()


## H56: the lance roots while it charges (move orders are ignored: commitment).
func rooted(u: Dictionary) -> bool:
	return charging(u) and str(u.get("weapon", "")) == "lance"


func _orders(u: Dictionary, o: Dictionary) -> void:
	if o.get("stop", false):
		_stop(u)
		u.target = ""
		u.attacking = false
	if o.has("run"):
		u.run = bool(o.run)
	if o.has("target"):
		var t := str(o.target)
		u.target = t if units.has(t) else ""
		if u.target == "":
			u.attacking = false
	if o.get("attack", false) and u.target != "":
		u.attacking = true
		_stop(u)
	if o.has("move") and not (u.leap as Dictionary).is_empty() and bool((u.leap as Dictionary).get("air_control", false)):
		var L: Dictionary = u.leap                   # H42: Arrowstorm steers in the air: retarget the landing
		var want: Vector2i = o.move
		var nb := blocked_for(u)
		var dest := arena.nearest_walkable(arena.from_world(L.from), want, nb)
		if HHHex.distance(arena.from_world(L.from), dest) <= int(L.get("range", 4)):
			L.to = dest
			_emit({ "type": "leap_steer", "id": u.id, "to": dest })
	if o.has("move") and not held(u) and not rooted(u):
		var goal: Vector2i = o.move
		var blocked := blocked_for(u)
		var dest := arena.nearest_walkable(u.hex, goal, blocked)
		u.target = ""
		u.attacking = false
		var exact: Vector3 = o.get("move_pos", NO_POS)
		if dest != goal:
			exact = NO_POS
		_set_route(u, arena.path(u.hex, dest, blocked), exact)
		_emit({ "type": "move", "id": u.id, "to": dest })
	if u.kind == "player" and o.has("dash"):
		_dash_order(u, o.dash)
	if u.kind == "player" and o.has("charge"):
		_charge_order(u, o.charge)
	if u.kind == "player" and o.has("charge_aim") and charging(u) and o.charge_aim is Vector2i:
		(u.charging as Dictionary).aim = o.charge_aim
	if u.kind == "player" and o.has("release") and o.release is Dictionary:
		var rl: Dictionary = o.release
		if charging(u) and str(rl.get("skill", "q")) == str(u.charging.skill):
			_release_charge(u, rl.get("aim", (u.charging as Dictionary).get("aim", u.hex)))
	if u.kind == "player" and o.has("move") and not (u.get("combo", {}) as Dictionary).is_empty():
		_combo_reset(u, "move")                          # H57: breaking off resets the string
	var busy := held(u) or charging(u)
	if u.kind == "player" and busy and o.has("cast") and o.cast is Dictionary \
			and HHWeapons.is_escape(str(u.weapon), str(o.cast.get("skill", ""))) and escapable(u):
		break_commit(u, "escape")                        # H57: a movement skill is an escape from a commit
		busy = held(u) or charging(u)
	if u.kind == "player" and busy and escapable(u) and not charging(u):
		var q := {}                                      # H57: a press during a wind-up / recovery fires when it ends
		var w: Dictionary = u.windup
		var rem := int(u.get("recovery", 0)) + (int(w.left) + int((w.get("data", {}) as Dictionary).get("recovery", HHTune.value("recovery_ticks"))) if not w.is_empty() else 0)
		for k in ["swap", "cast", "potion"]:
			if o.has(k) and not (o[k] is bool and not o[k]):
				var key := "w" if k == "swap" else ("t" if k == "potion" else str((o[k] as Dictionary).get("skill", "")) if o[k] is Dictionary else "")
				if int((u.cooldowns as Dictionary).get(key, 0)) > rem:
					_emit({ "type": "cast_refused", "id": u.id, "skill": key, "why": "cooldown" })
				else:
					q[k] = o[k]
		if not q.is_empty() and rem <= int(HHTune.value("input_buffer_ticks")) * 3:
			u.queued = { "o": q, "until": tick + rem + int(HHTune.value("input_buffer_ticks")) }
	if o.get("swap", false) and u.kind == "player" and not busy:
		HHWeapons.cast(self, u, "w", u.hex)
	if o.has("cast") and u.kind == "player" and not busy:
		var cst: Dictionary = o.cast
		HHWeapons.cast(self, u, str(cst.get("skill", "")), cst.get("aim", u.hex))
	var pot: Variant = o.get("potion", false)
	if (pot is Dictionary or (pot is bool and pot)) and u.kind == "player" and not busy:
		if int(u.potions) > 0 and int(u.cooldowns.get("t", 0)) <= 0:
			var aim: Vector2i = (pot as Dictionary).get("aim", u.hex) if pot is Dictionary else u.hex
			var at := potion_target(u, aim)
			u.cooldowns["t"] = int(HHTune.value("potion_cd"))
			_stop(u)
			if at != u.hex:
				_face(u, at)
			begin_windup(u, "potion", int(HHTune.value("potion_windup")), { "aim": at }, Callable(self, "_potion_land"))
		else:
			_emit({ "type": "cast_refused", "id": u.id, "skill": "t", "why": "none left" if int(u.potions) <= 0 else "cooldown" })
	if o.has("paint") and sandbox:
		var p: Dictionary = o.paint
		paint([p.hex], str(p.element), u.id, int(p.get("steps", 1)))


func _stop(u: Dictionary) -> void:
	u.goal_pos = NO_POS
	if u.kind == "player":
		u.path = [] as Array[Vector2i]
	elif not (u.path as Array).is_empty() and int(float(u.progress) * 1000.0) > 0:
		var first: Vector2i = u.path[0]
		var np: Array[Vector2i] = [first]
		u.path = np                                  # a monster lands on the hex it glides to
	else:
		u.path = [] as Array[Vector2i]


func _set_route(u: Dictionary, p: Array[Vector2i], exact: Vector3 = NO_POS) -> void:
	if u.kind == "player":
		u.path = p
		u.goal_pos = exact
		return
	if int(float(u.progress) * 1000.0) > 0 and not (u.path as Array).is_empty():
		var first: Vector2i = u.path[0]
		var np: Array[Vector2i] = [first]
		np.append_array(arena.path(first, p[-1] if not p.is_empty() else first, blocked_for(u)))
		u.path = np
	else:
		u.path = p
		u.progress = 0.0


func _paralysed(u: Dictionary) -> bool:
	return u.statuses.has("paralysis") or u.statuses.has("freeze")


## CONTRACT for brains: walk a monster toward `goal` over its allowed kinds.
func monster_move(u: Dictionary, goal: Vector2i) -> bool:
	var blocked := blocked_for(u)
	var dest := arena.nearest_walkable(u.hex, goal, blocked)
	var p := arena.path(u.hex, dest, blocked)
	if p.is_empty():
		u.path = [] as Array[Vector2i]
		return false
	_set_route(u, p)
	return true


# ------------------------------------------------------------------ movement

## Can a unit run straight from hex a to hex b? Every hex on the line is
## walkable, not blocked, and no cliff step.
func clear_line(a: Vector2i, b: Vector2i, blocked: Dictionary) -> bool:
	var line := HHHex.line(a, b)
	var max_step := HHTune.value("max_step_m")
	for i in line.size():
		var h: Vector2i = line[i]
		if not arena.walkable(h) or blocked.has(h):
			return false
		if i > 0 and absf(arena.hex_height(h) - arena.hex_height(line[i - 1])) > max_step:
			return false
	return true


func _walk_free(u: Dictionary) -> void:
	if not (u.leap as Dictionary).is_empty():
		_leap(u)
		return
	if not (u.get("dash", {}) as Dictionary).is_empty():
		_dash_step(u)
		return
	if int(u.stagger) > 0:
		u.stagger = int(u.stagger) - 1
		return
	if _paralysed(u) or not (u.windup as Dictionary).is_empty() or rooted(u) or int(u.get("flinch", 0)) > 0:
		return
	if int(u.get("recovery", 0)) > 0:
		_recovery_turn(u)                                # H57: rooted; turns slowly toward the target
		return
	var blocked := blocked_for(u)
	# walk into range of the target (not while charging: only an explicit move moves a charging hunter)
	if u.target != "" and (u.path as Array).is_empty() and (u.goal_pos as Vector3) == NO_POS and not charging(u):
		var t := unit(u.target)
		if t.is_empty() or not alive(t):
			u.target = ""
			u.attacking = false
		elif targetable(t) and not in_attack_range(u, t):
			u.path = attack_spot(u, t).path                  # H252: the nearest open spot in range, never the centre
	var path: Array = u.path
	var goal: Vector3 = u.goal_pos
	if path.is_empty() and goal == NO_POS:
		if u.target != "" and units.has(u.target):
			_face_pos(u, unit(u.target).pos)
		return
	# string-pull: skip waypoints while the straight run to a later one is clear
	# (not right after a clipped corner: then follow hex centres for a moment)
	var pull := tick >= int(u.get("unpull_until", 0))
	while pull and path.size() >= 2 and clear_line(u.hex, path[1], blocked):
		path.pop_front()
	if pull and path.size() == 1 and goal != NO_POS and clear_line(u.hex, arena.from_world(goal), blocked):
		path.pop_front()
	var target: Vector3
	if path.is_empty():
		target = goal
	else:
		target = arena.stand(path[0])
		if path.size() == 1 and goal != NO_POS and arena.from_world(goal) == path[0]:
			target = goal
	var mps := HHTune.value("run_mps") if u.run else HHTune.value("walk_mps")
	if u.statuses.has("slow"):
		mps *= HHTune.value("slow_mult")
	if charging(u):
		mps *= HHTune.value("charge_move_mult")       # H56: bow and daggers slow while they charge
	var step := mps * charge.move_mult(u.hex, _ground_owner(u, u.hex)) * TICK
	var from: Vector3 = u.pos
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var dist := flat.length()
	var next: Vector3
	if dist <= step:
		next = target
	else:
		next = from + flat / dist * step
	var nh := arena.from_world(next)
	if nh != u.hex and (not arena.walkable(nh) or blocked.has(nh) or absf(arena.hex_height(nh) - arena.hex_height(u.hex)) > HHTune.value("max_step_m")):
		var centre := arena.stand(u.hex)
		var off := Vector3(centre.x - from.x, 0.0, centre.z - from.z)
		if pull and not path.is_empty() and nh != path[0] and off.length() > 1e-3:
			# H880: the string-pulled run clipped a corner hex the hex line missed
			# (it is tested centre to centre, the hunter is off-centre). Step back
			# toward this hex's centre and follow hex centres for a moment instead
			# of stopping: stopping re-paths into the same clip every tick.
			u.unpull_until = tick + 15
			u.pos = centre if off.length() <= step else from + off / off.length() * step
			return
		if hull_hexes().has(nh) and _reroute(u, blocked):
			return                                    # H254: a hull stepped into the way: go round it
		_stop(u)                                      # the edge, a cliff, the monster's body
		_emit({ "type": "blocked", "id": u.id, "hex": nh })
		return
	next.y = arena.stand(nh).y
	if dist > 1e-4:
		u.facing = atan2(flat.x, flat.z)
	u.pos = next
	if nh != u.hex:
		u.prev = u.hex
		u.hex = nh
		_enter(u, nh)
	if dist <= step:
		if not path.is_empty():
			path.pop_front()
		if path.is_empty():
			u.goal_pos = NO_POS
			_emit({ "type": "arrive", "id": u.id, "hex": u.hex })


## H57 facing lock: during a recovery the hunter turns toward its target at
## recovery_turn_dps at most (during a wind-up it does not turn at all).
func _recovery_turn(u: Dictionary) -> void:
	if u.target == "" or not units.has(u.target):
		return
	var d: Vector3 = (unit(u.target).pos as Vector3) - (u.pos as Vector3)
	if Vector2(d.x, d.z).length_squared() < 1e-6:
		return
	var want := atan2(d.x, d.z)
	var diff := wrapf(want - float(u.facing), -PI, PI)
	var lim := deg_to_rad(HHTune.value("recovery_turn_dps")) * TICK
	u.facing = wrapf(float(u.facing) + clampf(diff, -lim, lim), -PI, PI)


func _walk_hex(u: Dictionary) -> void:
	if not (u.leap as Dictionary).is_empty():
		_leap(u)
		return
	if int(u.stagger) > 0:
		u.stagger = int(u.stagger) - 1
		return
	if _paralysed(u) or not (u.windup as Dictionary).is_empty():
		return
	if (u.path as Array).is_empty():
		u.pos = arena.stand(u.hex)
		u.progress = 0.0
		if u.target != "" and units.has(u.target):
			_face_pos(u, unit(u.target).pos)
		return
	var next: Vector2i = u.path[0]
	if float(u.progress) <= 0.0 and _hull_clash(u, next):
		u.path = [] as Array[Vector2i]                    # H250: another hull is in the way: stop, the brain re-plans
		u.pos = arena.stand(u.hex)
		_emit({ "type": "blocked", "id": u.id, "hex": next })
		return
	var ticks := float(u.get("walk_ticks", HHTune.value("monster_walk_ticks")))
	if u.statuses.has("slow"):
		ticks /= HHTune.value("slow_mult")
	u.progress = float(u.progress) + charge.move_mult(u.hex, u.id) / ticks
	if float(u.progress) >= 1.0 - 1e-6:
		u.progress = 0.0
		u.prev = u.hex
		u.hex = next
		(u.path as Array).pop_front()
		_enter(u, next)
		if (u.path as Array).is_empty():
			u.pos = arena.stand(u.hex)
			_emit({ "type": "arrive", "id": u.id, "hex": u.hex })
			return
		next = u.path[0]
	var a := arena.stand(u.hex)
	var b := arena.stand(next)
	u.pos = a.lerp(b, float(u.progress))
	_face(u, next)


func _face(u: Dictionary, toward: Vector2i) -> void:
	_face_pos(u, arena.stand(toward))


func _face_pos(u: Dictionary, p: Vector3) -> void:
	var d := p - (u.pos as Vector3)
	if Vector2(d.x, d.z).length_squared() > 1e-6:
		u.facing = atan2(d.x, d.z)


## A vault (lance R): the unit flies to `to` over `total` ticks, untargetable.
func begin_leap(u: Dictionary, to: Vector2i, total: int, on_land: Callable, air_control: bool = false, steer_range: int = 4) -> void:
	_stop(u)
	u.progress = 0.0
	u.leap = { "from": u.pos, "to": to, "ticks": 0, "total": maxi(1, total), "on_land": on_land, "air_control": air_control, "range": steer_range }
	u.untargetable = true
	_face(u, to)
	_emit({ "type": "leap", "id": u.id, "to": to, "ticks": total })


func _leap(u: Dictionary) -> void:
	var L: Dictionary = u.leap
	L.ticks = int(L.ticks) + 1
	var t := float(L.ticks) / float(L.total)
	var a: Vector3 = L.from
	var b := arena.stand(L.to)
	u.pos = a.lerp(b, t) + Vector3(0, HHTune.value("leap_height_m") * 4.0 * t * (1.0 - t), 0)
	if int(L.ticks) >= int(L.total):
		u.prev = u.hex
		u.hex = L.to
		u.pos = b
		u.leap = {}
		u.untargetable = false
		u.crossed = L.to
		_emit({ "type": "land", "id": u.id, "hex": u.hex })
		if (L.on_land as Callable).is_valid():
			(L.on_land as Callable).call(self, u)
		if u.kind == "player" and alive(u) and (u.leap as Dictionary).is_empty():
			begin_recovery(u, int(HHTune.value("recovery_ticks")))   # H57: a landing is an action too


## A committed action: `ticks` of wind-up, then `on_done.call(sim, u, data)`.
## The unit cannot move or start another action meanwhile (H34).
func begin_windup(u: Dictionary, kind: String, ticks: int, data: Dictionary, on_done: Callable) -> void:
	u.windup = { "left": maxi(1, ticks), "total": maxi(1, ticks), "kind": kind, "data": data, "on_done": on_done }
	_emit({ "type": "windup", "id": u.id, "kind": kind, "ticks": ticks, "step": int(data.get("step", 0)), "level": int(data.get("level", 0)) })


func _windup(u: Dictionary) -> void:
	var w: Dictionary = u.windup
	if w.is_empty():
		return
	if int(u.stagger) > 0:
		u.windup = {}                                 # a hit breaks the wind-up
		_emit({ "type": "windup_broken", "id": u.id, "kind": str(w.kind) })
		return
	w.left = int(w.left) - 1
	if int(w.left) > 0:
		return
	u.windup = {}
	(w.on_done as Callable).call(self, u, w.data)
	if u.kind == "player" and alive(u) and (u.windup as Dictionary).is_empty() and (u.leap as Dictionary).is_empty():
		begin_recovery(u, int((w.data as Dictionary).get("recovery", HHTune.value("recovery_ticks"))))


## H57: rooted for `ticks` after an action (no movement, no other action;
## the dash and the movement skills may break it).
func begin_recovery(u: Dictionary, ticks: int) -> void:
	if ticks <= 0:
		return
	u.recovery = maxi(int(u.get("recovery", 0)), ticks)
	_emit({ "type": "recovery", "id": u.id, "ticks": u.recovery })


func _enter(u: Dictionary, hex: Vector2i) -> void:
	var pct := charge.crossing_pct(hex)
	if pct > 0.0 and u.crossed != hex and not charge.owned_by(hex, _ground_owner(u, hex)):
		hurt(u, HHFormulas.tile_damage(dot_base(u), pct, resist_of(u, "fire")).value, "fire_cross")
	u.crossed = hex


## H54: the HP that pct ground and status damage is measured against. A
## hunter: max HP. A monster: its unscaled HP (party scaling does not feed
## fire carpets) x monster_ground_mult (fire 3 under a boss was 720/s and
## outdid every weapon; reactions and blows are the monster's damage now).
func dot_base(u: Dictionary) -> float:
	if u.kind != "monster":
		return float(u.max_hp)
	return float(u.max_hp) / maxf(1.0, float(u.get("party_scale", 1.0))) * HHTune.value("monster_ground_mult")


func _ground(u: Dictionary) -> void:
	var s := charge.standing(u.hex)
	var mine: bool = str(s.source) == u.id or allies(str(s.source), u.id)   # H33: your own (or your party's) element never hurts you
	if float(s.fire) > 0.0 and not mine:
		hurt(u, HHFormulas.tile_damage(dot_base(u), float(s.fire), resist_of(u, "fire")).value, "fire")
	if float(s.drain) > 0.0 and not mine:
		hurt(u, HHFormulas.tile_damage(dot_base(u), float(s.drain), resist_of(u, "dark")).value, "dark")
	if float(s.heal) > 0.0:
		heal(u, HHFormulas.tile_damage(u.max_hp, float(s.heal)).value, "light")


## H56: where a potion thrown at `aim` lands: on the line to it, no farther
## than potion_range, on the arena.
func potion_target(u: Dictionary, aim: Vector2i) -> Vector2i:
	var reach_h := int(HHTune.value("potion_range"))
	if not arena.exists(aim):
		aim = u.hex
	if HHHex.distance(u.hex, aim) <= reach_h:
		return aim
	var best: Vector2i = u.hex
	for h in HHHex.line(u.hex, aim):
		if HHHex.distance(u.hex, h) <= reach_h and arena.exists(h):
			best = h
	return best


## H40 / H56: the thrown potion lands: a heal zone of potion_radius on the
## ground for potion_seconds. Every standing hunter inside heals
## potion_heal_pct / potion_seconds of max HP a second (a hunter in it the
## whole time heals what a drink did), and the ground under each one fights
## it (dark cuts, light feeds: heal_mult). One zone per hunter; a new throw
## replaces it.
func _potion_land(_sim: HHSim, u: Dictionary, data: Dictionary) -> void:
	u.potions = int(u.potions) - 1
	var secs := HHTune.value("potion_seconds")
	var at: Vector2i = data.get("aim", u.hex)
	var ticks := int(secs * 30.0)
	u.heal_zone = { "hex": at, "radius": int(HHTune.value("potion_radius")), "left": ticks, "total": ticks,
		"pct_per_s": HHTune.value("potion_heal_pct") / maxf(secs, 1.0) }
	u["potion_tick"] = tick                              # brains read this (they tick before wind-ups land)
	u["potion_hex"] = at                                 # ... and this: Swampfang darkens the zone, not the thrower
	_emit({ "type": "potion", "id": u.id, "left": u.potions, "hex": at, "radius": int(u.heal_zone.radius) })
	HHWeapons.potion_landed(self, u)                     # H554: the weapon layer answers a potion (upgrades)


## True when `p` stands in a live heal zone.
func in_heal_zone(p: Dictionary) -> bool:
	for q in players():
		var z: Dictionary = q.get("heal_zone", {})
		if not z.is_empty() and HHHex.distance(p.hex, z.hex) <= int(z.radius):
			return true
	return false


## Once a ground tick: every live zone heals the standing hunters inside it.
func _heal_zones() -> void:
	for owner in players():
		var z: Dictionary = owner.get("heal_zone", {})
		if z.is_empty():
			continue
		for p in standing_players():
			if HHHex.distance(p.hex, z.hex) <= int(z.radius):
				heal(p, HHFormulas.tile_damage(p.max_hp, float(z.pct_per_s)).value * heal_mult(p), "potion")
		z.left = int(z.left) - int(HHTune.value("ground_tick_every"))
		if int(z.left) <= 0:
			owner.heal_zone = {}
			_emit({ "type": "heal_zone_end", "id": owner.id, "hex": z.hex })


## Healing rate under this unit: 1 - dark_heal_cut per dark tier, + light_heal_bonus per light tier.
func heal_mult(u: Dictionary) -> float:
	var dark := charge.intensity(u.hex, "dark")
	var light := charge.intensity(u.hex, "light")
	return clampf(1.0 - HHTune.value("dark_heal_cut") * dark + HHTune.value("light_heal_bonus") * light, 0.1, 2.0)


func _statuses(u: Dictionary) -> void:
	var rg: Dictionary = u.regen
	if not rg.is_empty():
		heal(u, HHFormulas.tile_damage(u.max_hp, float(rg.pct_per_s)).value * heal_mult(u), "potion")
		rg.ticks = int(rg.ticks) - int(HHTune.value("ground_tick_every"))
		if int(rg.ticks) <= 0:
			u.regen = {}
			_emit({ "type": "regen_end", "id": u.id })
	for name in u.statuses.keys():
		var st: Dictionary = u.statuses[name]
		match name:
			"burn": hurt(u, HHFormulas.tile_damage(dot_base(u), HHTune.value("burn_pct_per_s")).value, "burn")
			"poison": hurt(u, HHFormulas.tile_damage(dot_base(u), HHTune.value("poison_pct_per_s")).value, "poison")
		st.ticks = int(st.ticks) - int(HHTune.value("ground_tick_every"))
		if int(st.ticks) <= 0:
			u.statuses.erase(name)
			_emit({ "type": "status_end", "id": u.id, "status": name })


func resist_of(u: Dictionary, element: String) -> float:
	return float((u.resist as Dictionary).get(element, 0.0))


# ------------------------------------------------------------------ attacks

## The auto-attack (H25, H32): in reach of a targetable target with the basic
## cooldown down, wind up (lance_basic_windup), then strike: a blow that
## also lays one step of the active element on the hex it lands on (H27).
func _auto_attack(u: Dictionary) -> void:
	if not bool(u.attacking) or u.target == "" or held(u):
		return
	var t := unit(u.target)
	if t.is_empty() or not targetable(t):
		return
	if not in_attack_range(u, t) or not (u.path as Array).is_empty():
		return                                           # H252: from outside the hull, within reach of its edge
	if int(u.cooldowns.basic) > 0 or charging(u):
		return
	u.cooldowns.basic = int(HHWeapons.basic_ticks(u.weapon))
	_face_pos(u, t.pos)
	# H57: lance and daggers string basics on one target: hit 2 within
	# combo_window_ticks of hit 1's recovery, hit 3 after hit 2 (the finisher).
	var step := 1
	if HHWeapons.has_combo(str(u.weapon)):
		var cb: Dictionary = u.get("combo", {})
		if not cb.is_empty() and int(cb.step) in [1, 2] and tick <= int(cb.until) and str(cb.target) == str(t.id):
			step = int(cb.step) + 1
		u.combo = { "step": step, "until": -1, "target": str(t.id) }
		_emit({ "type": "combo", "id": u.id, "step": step, "target": t.id })
	var hit := HHWeapons.combo_hit(str(u.weapon), step)
	begin_windup(u, "basic", int(hit.windup), { "target": t.id, "step": step, "recovery": int(hit.recovery) }, Callable(self, "_basic_land"))


func _basic_land(_sim: HHSim, u: Dictionary, data: Dictionary) -> void:
	var step := int(data.get("step", 1))
	var hit := HHWeapons.combo_hit(str(u.weapon), step)
	if not (u.get("combo", {}) as Dictionary).is_empty():
		if step >= 3:
			u.combo = {}                                 # the string is done; the next basic starts a new one
		else:
			u.combo.until = tick + int(hit.recovery) + int(HHTune.value("combo_window_ticks"))
	var t := unit(str(data.target))
	if t.is_empty() or not targetable(t):
		return
	if HHHex.distance(u.hex, t.hex) > int(u.reach) + int(t.size) + 1:
		_emit({ "type": "miss", "id": u.id, "target": t.id })
		return
	var hex := nearest_hex_of(t, u.hex)
	strike(u, t, HHWeapons.basic_damage(u.weapon) * float(hit.mult), hex, "basic", float(hit.stagger), { "combo": step, "heavy": step >= 3 })
	var hexes: Array = [hex]
	if step >= 3 and int(hit.get("splash", 0)) > 0:
		hexes = arena.area(hex, int(hit.splash))         # the finisher lays its element round the blow
	paint(hexes, u.element, u.id, int(hit.steps))


## One blow from `u` on `t` landing on `hex`: rear multiplier (a brain may
## expose rear_mult), resistance, then hurt. `extra` rides on the strike
## event (combo step, heavy: the view's hit-stop).
func strike(u: Dictionary, t: Dictionary, base: float, hex: Vector2i, cause: String, stagger: float = 0.0, extra: Dictionary = {}) -> float:
	if allies(str(u.get("id", "")), str(t.get("id", ""))):
		return 0.0                                       # H53: a hunter's blow passes through an ally
	var mult := 1.0
	var brain: Variant = brains.get(t.id)
	if brain != null and brain.has_method("rear_mult"):
		mult = float(brain.rear_mult(t, u.hex))
	var dmg: float = HHFormulas.hit(base, mult, resist_of(t, u.element)).value
	hurt(t, dmg, cause, stagger, str(u.id))
	var ev := { "type": "strike", "id": u.id, "target": t.id, "hex": hex, "amount": dmg, "cause": cause, "rear": mult > 1.0 }
	ev.merge(extra)
	_emit(ev)
	return dmg


# ------------------------------------------------------------------ charged Q (H56)

## Levels by ticks held: 1 (a tap) below charge_l2_s, 2 from it, 3 at charge_l3_s.
static func charge_level(ticks: int) -> int:
	if ticks >= int(roundf(HHTune.value("charge_l3_s") * 30.0)):
		return 3
	if ticks >= int(roundf(HHTune.value("charge_l2_s") * 30.0)):
		return 2
	return 1


## Key down: start holding `skill` (q). Refused on cooldown, mid-action or
## already charging. A charge breaks the auto-attack's own wind-up (the skill
## wins over a flick); any other wind-up refuses it. The lance roots.
func _charge_order(u: Dictionary, c: Variant) -> void:
	if not c is Dictionary:
		return
	var skill := str((c as Dictionary).get("skill", "q"))
	if skill != "q" or charging(u):
		return
	if int(u.cooldowns.get(skill, 0)) > 0:
		_emit({ "type": "cast_refused", "id": u.id, "skill": skill, "why": "cooldown" })
		return
	var w: Dictionary = u.windup
	if not w.is_empty() and str(w.kind) == "basic" and int(u.stagger) <= 0:
		u.windup = {}
		_emit({ "type": "windup_broken", "id": u.id, "kind": "basic" })
	if held(u):
		_emit({ "type": "cast_refused", "id": u.id, "skill": skill, "why": "busy" })
		return
	var aim: Variant = (c as Dictionary).get("aim", u.hex)
	u.charging = { "skill": skill, "ticks": 0, "level": 1, "aim": aim if aim is Vector2i else u.hex }
	if str(u.weapon) == "lance":
		_stop(u)                                         # rooted: the lance plants and braces
	_emit({ "type": "charge_start", "id": u.id, "skill": skill, "weapon": str(u.weapon) })


## Each tick for a charging hunter: count, announce new levels, fire at level 3.
func _charge_tick(u: Dictionary) -> void:
	if not charging(u):
		return
	var ch: Dictionary = u.charging
	if int(u.stagger) > 0 or _paralysed(u) or not (u.leap as Dictionary).is_empty():
		cancel_charge(u, "stagger" if int(u.stagger) > 0 else "held")
		return
	ch.ticks = int(ch.ticks) + 1
	var lv := charge_level(int(ch.ticks))
	if lv > int(ch.level):
		ch.level = lv
		_emit({ "type": "charge_level", "id": u.id, "skill": str(ch.skill), "level": lv })
	if lv >= 3:
		_release_charge(u, ch.get("aim", u.hex))         # full charge fires on its own


## Key up (or full charge): fire at the level reached. The weapon winds up
## (nothing is instant) and the cooldown starts now.
func _release_charge(u: Dictionary, aim: Variant) -> void:
	var ch: Dictionary = u.charging
	u.charging = {}
	var at: Vector2i = aim if aim is Vector2i else u.hex
	var lv := maxi(int(ch.get("level", 1)), charge_level(int(ch.get("ticks", 0))))
	_emit({ "type": "charge_release", "id": u.id, "skill": str(ch.skill), "level": lv, "aim": at, "ticks": int(ch.ticks) })
	HHWeapons.cast(self, u, str(ch.skill), at, lv)


## A charge lost (a stagger, a dash). A dash spends the skill: its cooldown
## starts (the commitment was paid); a stagger does not (the hit is the cost).
func cancel_charge(u: Dictionary, why: String) -> void:
	if not charging(u):
		return
	var ch: Dictionary = u.charging
	u.charging = {}
	if why == "dash":
		var sk: Dictionary = HHWeapons.skills(str(u.weapon)).get(str(ch.skill), {})
		u.cooldowns[str(ch.skill)] = int(sk.get("cooldown", 0))
	_emit({ "type": "charge_cancel", "id": u.id, "skill": str(ch.skill), "level": int(ch.level), "why": why })


# ------------------------------------------------------------------ dash (H56)

## Shift: a short dash toward `to` (a world point). On the hunter (or no
## point) it goes the way the hunter was moving, else where it faces. It
## stops short of walls, the edge, cliffs and bodies; refused when nothing is
## left of it, mid-action, out of charges or still recovering. It cancels a
## charging Q (spending it) and dodges hits for its first dash_iframe_ticks.
func _dash_order(u: Dictionary, to: Variant) -> void:
	var blocked_by_commit := held(u) and not escapable(u)   # H57: a wind-up / recovery / charge is escapable; stagger, flinch, leaps are not
	if int(u.get("dash_charges", 0)) <= 0 or int(u.get("dash_recover", 0)) > 0 or blocked_by_commit:
		var why := "recovering" if int(u.get("dash_recover", 0)) > 0 else ("none left" if int(u.get("dash_charges", 0)) <= 0 else "busy")
		_emit({ "type": "cast_refused", "id": u.id, "skill": "dash", "why": why })
		return
	var from: Vector3 = u.pos
	var d := Vector3.ZERO
	if to is Vector3 and (to as Vector3) != NO_POS:
		d = (to as Vector3) - from
		d.y = 0.0
	if d.length() < 0.5:
		var path: Array = u.path
		var goal: Vector3 = u.goal_pos
		if not path.is_empty():
			d = arena.stand(path[0]) - from
		elif goal != NO_POS:
			d = goal - from
		else:
			d = Vector3.ZERO
		d.y = 0.0
		if d.length() < 0.05:
			d = Vector3(sin(float(u.facing)), 0.0, cos(float(u.facing)))
	d = d.normalized()
	var end := dash_end(u, d)
	if Vector2(end.x - from.x, end.z - from.z).length() < 0.3:
		_emit({ "type": "cast_refused", "id": u.id, "skill": "dash", "why": "blocked" })
		return
	break_commit(u, "dash")                              # the wind-up, recovery or held charge is lost; the string resets
	_stop(u)
	u.dash_charges = int(u.dash_charges) - 1
	if int(u.get("dash_recharge", 0)) <= 0:
		u.dash_recharge = int(roundf(HHTune.value("dash_recharge_s") * 30.0))
	var total := maxi(1, int(HHTune.value("dash_ticks")))
	u.dash = { "from": from, "to": end, "ticks": 0, "total": total }
	u.dash_iframes = int(HHTune.value("dash_iframe_ticks"))
	u.facing = atan2(d.x, d.z)
	_emit({ "type": "dash", "id": u.id, "from": from, "to": end, "ticks": total, "left": int(u.dash_charges) })


## The farthest point along `dir` (unit, flat) within dash_m the hunter can
## reach in a straight line: every hex crossed walkable, unblocked, no cliff.
func dash_end(u: Dictionary, dir: Vector3) -> Vector3:
	var from: Vector3 = u.pos
	var blocked := blocked_for(u)
	var max_step := HHTune.value("max_step_m")
	var last_hex: Vector2i = u.hex
	var best := from
	var dist := HHTune.value("dash_m")
	var n := int(ceil(dist / 0.1))
	for i in range(1, n + 1):
		var p := from + dir * minf(float(i) * 0.1, dist)
		var h := arena.from_world(p)
		if h != last_hex:
			if not arena.walkable(h) or blocked.has(h) or absf(arena.hex_height(h) - arena.hex_height(last_hex)) > max_step:
				break
			last_hex = h
		best = p
	best.y = arena.stand(arena.from_world(best)).y
	return best


func _dash_step(u: Dictionary) -> void:
	var D: Dictionary = u.dash
	D.ticks = int(D.ticks) + 1
	var t := clampf(float(D.ticks) / float(D.total), 0.0, 1.0)
	var e := 1.0 - (1.0 - t) * (1.0 - t)                # ease out: a burst, then it settles
	var a: Vector3 = D.from
	var b: Vector3 = D.to
	var p := a.lerp(b, e)
	var nh := arena.from_world(p)
	p.y = arena.stand(nh).y
	u.pos = p
	if nh != u.hex:
		u.prev = u.hex
		u.hex = nh
		_enter(u, nh)
	if int(D.ticks) >= int(D.total):
		u.dash = {}
		u.dash_recover = int(HHTune.value("dash_recover_ticks"))
		_emit({ "type": "dash_end", "id": u.id, "hex": u.hex })


## Per tick: recovery and dodge windows run down; spent charges come back one
## at a time, every dash_recharge_s.
func _dash_timers(u: Dictionary) -> void:
	if int(u.get("dash_recover", 0)) > 0:
		u.dash_recover = int(u.dash_recover) - 1
	if int(u.get("dash_iframes", 0)) > 0:
		u.dash_iframes = int(u.dash_iframes) - 1
	var cap := int(HHTune.value("dash_charges"))
	if int(u.get("dash_charges", cap)) >= cap:
		u.dash_recharge = 0
		return
	u.dash_recharge = int(u.get("dash_recharge", 0)) - 1
	if int(u.dash_recharge) <= 0:
		u.dash_charges = int(u.dash_charges) + 1
		_emit({ "type": "dash_ready", "id": u.id, "charges": int(u.dash_charges) })
		u.dash_recharge = int(roundf(HHTune.value("dash_recharge_s") * 30.0)) if int(u.dash_charges) < cap else 0


# ------------------------------------------------------------------ telegraphs

func telegraph(owner: String, hexes: Array, ticks: int, payload: Dictionary = {}) -> int:
	var id := _next_tg
	_next_tg += 1
	telegraphs.append({ "id": id, "owner": owner, "hexes": hexes.duplicate(), "left": maxi(1, ticks), "total": maxi(1, ticks), "payload": payload.duplicate() })
	_emit({ "type": "telegraph", "id": id, "owner": owner, "hexes": hexes.duplicate(), "ticks": ticks,
		"name": str(payload.get("name", payload.get("clip", ""))), "payload": payload.duplicate() })
	return id


func _telegraphs() -> void:
	var keep: Array = []
	for tg in telegraphs:
		tg.left = int(tg.left) - 1
		if int(tg.left) > 0:
			keep.append(tg)
			continue
		_resolve_telegraph(tg)
	telegraphs = keep


func _resolve_telegraph(tg: Dictionary) -> void:
	var p: Dictionary = tg.payload
	var owner := unit(str(tg.owner))
	var hit: Array = []
	var cause := str(p.get("name", p.get("clip", "telegraph")))
	for u in units_in(tg.hexes, "" if bool(p.get("self_hit", false)) else str(tg.owner)):
		if allies(str(tg.owner), u.id):
			continue                                     # H53: a hunter's telegraph (arcing shot, echo) spares allies
		if int(u.get("dash_iframes", 0)) > 0:
			_emit({ "type": "dodge", "id": u.id, "amount": 0.0, "cause": cause })
			continue                                     # H56: dashed through it (no damage, no status)
		var pct := float(p.get("dmg_pct", 0.0))
		var el := str(p.get("element", ""))
		if pct > 0.0:
			var dmg: float = HHFormulas.tile_damage(u.max_hp, pct, resist_of(u, el) if el != "" else 0.0).value
			if int(u.guard) > 0:
				dmg *= 1.0 - HHTune.value("guard_reduce")
				_guard_counter(u, owner)
				hurt(u, dmg, cause, 0.0, str(tg.owner), false)          # H58: a guarded hit did not land: no interrupt
			else:
				hurt(u, dmg, cause, float(p.get("stagger", 0.0)), str(tg.owner))
		if str(p.get("status", "")) != "" and int(u.guard) <= 0:
			apply_status(u, str(p.status), int(p.get("status_ticks", 90)))
		if int(u.guard) <= 0:
			for st in p.get("statuses", []):             # a list: [{ name, ticks }] (Spirewalker's pollen)
				apply_status(u, str(st.name), int(st.get("ticks", 90)))
		hit.append(u.id)
	if str(p.get("element", "")) != "" and int(p.get("paint_steps", 0)) > 0:
		paint(tg.hexes, str(p.element), str(tg.owner), int(p.paint_steps))
	_emit({ "type": "telegraph_end", "id": tg.id, "owner": tg.owner, "hexes": tg.hexes, "hit": hit, "name": cause })
	_expose(owner, tg)


## H57: a monster that just landed a big attack is `exposed` for the rest of
## the recovery its brain already has (busy_until): hunters deal
## exposed_dmg_mult more. No idle time is added.
func _expose(m: Dictionary, tg: Dictionary) -> void:
	if m.is_empty() or str(m.get("kind", "")) != "monster" or not alive(m):
		return
	var p: Dictionary = tg.payload
	if float(p.get("dmg_pct", 0.0)) <= 0.0:
		return
	if (tg.hexes as Array).size() < int(HHTune.value("exposed_min_hexes")) and float(p.get("stagger", 0.0)) < HHTune.value("exposed_min_stagger"):
		return
	var brain: Variant = brains.get(str(m.id))
	if brain == null:
		return
	var until: Variant = brain.get("busy_until")
	if not (until is int or until is float):
		return
	var left := int(until) - tick
	if left > int(m.get("exposed", 0)):
		var was := int(m.get("exposed", 0))
		m.exposed = left
		if was <= 0:
			_emit({ "type": "exposed", "id": m.id, "ticks": left })


func _guard_counter(u: Dictionary, attacker: Dictionary) -> void:
	if attacker.is_empty() or not alive(attacker):
		return
	u.guard = 0
	_emit({ "type": "guard_block", "id": u.id, "from": attacker.id })
	HHWeapons.counter(self, u, attacker)


# ------------------------------------------------------------------ projectiles

## H553: a projectile is a hex that moves one step every `every` ticks, paints
## `element` x `steps` on each hex it enters, and strikes the first targetable
## unit of another kind (never its owner) whose footprint it enters. `target`
## (a unit id) makes it home: each step goes toward the target's nearest
## footprint hex; `spread` turns the first step by that many hex directions
## (-1 / 0 / +1 fans three shots). Without a live target it flies straight
## along `dir` (a hex direction index). It ends on a hit, off the arena, or
## after `max_hexes`. Spec keys:
##   { owner, from: Vector2i, target: id, dir: int, spread: int, element, steps,
##     every, max_hexes, dmg, stagger, cause }
func launch(spec: Dictionary) -> Dictionary:
	var owner := unit(str(spec.get("owner", "")))
	var from: Vector2i = spec.get("from", owner.get("hex", Vector2i.ZERO))
	var every := maxi(1, int(spec.get("every", 2)))
	var p := {
		"id": tick * 64 + projectiles.size() + 1, "owner": str(spec.get("owner", "")), "hex": from, "target": str(spec.get("target", "")),
		"dir": int(spec.get("dir", 0)), "spread": int(spec.get("spread", 0)), "element": str(spec.get("element", "")),
		"steps": int(spec.get("steps", 1)), "every": every, "left": every,
		"max_hexes": int(spec.get("max_hexes", 12)), "travelled": 0, "dmg": float(spec.get("dmg", 0.0)),
		"stagger": float(spec.get("stagger", 0.0)), "cause": str(spec.get("cause", "projectile")), "trail": [],
	}
	projectiles.append(p)
	_emit({ "type": "projectile", "id": p.id, "owner": p.owner, "phase": "launch", "hex": from, "target": p.target, "element": p.element })
	return p


func _projectiles() -> void:
	if projectiles.is_empty():
		return
	var keep: Array = []
	for p in projectiles:
		p.left = int(p.left) - 1
		if int(p.left) > 0:
			keep.append(p)
			continue
		p.left = int(p.every)
		var cur: Vector2i = p.hex
		var t := unit(str(p.target))
		if not t.is_empty() and targetable(t):
			var di := HHHex.direction_index(cur, nearest_hex_of(t, cur))
			if di >= 0:
				if int(p.spread) != 0:
					di = posmod(di + int(p.spread), 6)
					p.spread = 0
				p.dir = di
		var next: Vector2i = HHHex.to_offset(HHHex.to_cube(cur) + HHHex.CUBE_DIRS[int(p.dir)])
		if not arena.exists(next):
			_emit({ "type": "projectile", "id": p.id, "owner": p.owner, "phase": "end", "hex": cur, "trail": p.trail })
			continue
		p.hex = next
		p.travelled = int(p.travelled) + 1
		(p.trail as Array).append(next)
		if str(p.element) != "":
			paint([next], str(p.element), str(p.owner), int(p.steps))
		_emit({ "type": "projectile", "id": p.id, "owner": p.owner, "phase": "step", "hex": next, "element": p.element })
		var owner := unit(str(p.owner))
		var hit := false
		for v in unit_at(next):
			if v.id == str(p.owner) or not targetable(v) or str(v.kind) == str(owner.get("kind", "")):
				continue
			if not owner.is_empty() and float(p.dmg) > 0.0:
				strike(owner, v, float(p.dmg), next, str(p.cause), float(p.stagger))
			_emit({ "type": "projectile", "id": p.id, "owner": p.owner, "phase": "hit", "hex": next, "target": v.id, "trail": p.trail })
			hit = true
			break
		if hit:
			continue
		if int(p.travelled) >= int(p.max_hexes):
			_emit({ "type": "projectile", "id": p.id, "owner": p.owner, "phase": "end", "hex": next, "trail": p.trail })
			continue
		keep.append(p)
	projectiles = keep


# ------------------------------------------------------------------ ground

## A blow or blast landing on destructible cells (pillars): damage them;
## at 0 they break open (H44). Returns the hexes that broke.
func damage_cells(hexes: Array, amount: float) -> Array:
	var broke: Array = []
	for h in hexes:
		if arena.damage_cell(h, amount):
			broke.append(h)
			_emit({ "type": "cell_broken", "hex": h, "kind": arena.kind(h) })
	return broke


## Lay `element` on `hexes` as `caster` and resolve what the ground did. The
## caster is immune to its own blasts and bursts (H33).
func paint(hexes: Array, element: String, caster: String, steps: int = 1, fresh: bool = true) -> Dictionary:
	if caster != "":
		var u := unit(caster)
		if not u.is_empty():
			damage_cells(hexes, HHTune.value("pillar_paint_dmg") * float(steps))
	var r := charge.apply(hexes, element, caster, steps, fresh)
	_emit({ "type": "paint", "id": caster, "element": element, "hexes": hexes.duplicate(), "changed": r.changed.duplicate() })
	var hits := {}                                       # H50: unit id -> [{ amount, cause, stagger }] from this paint
	for d in r.detonations:
		_blast(hits, d.hex, float(d.mult), "detonate", d.mix, str(d.source))
	for o in r.overheat:
		_emit({ "type": "overheat", "hex": o.hex, "ring": o.ring })
		var unit_o := reaction_unit(str(o.source))
		for u in units_in(o.ring, str(o.source)):
			if allies(str(o.source), u.id):
				continue
			_react(hits, u, unit_o * float(o.mult) * (1.0 - resist_of(u, "fire") / 100.0), "overheat", 0.0, str(o.source))
	for o in r.overfreeze:
		_emit({ "type": "overfreeze", "hex": o.hex, "ring": o.ring })
		var unit_f := reaction_unit(str(o.source))
		for u in units_in([o.hex] + o.ring, str(o.source)):
			if allies(str(o.source), u.id):
				continue
			_react(hits, u, unit_f * float(o.mult) * (1.0 - resist_of(u, "ice") / 100.0), "overfreeze", 0.0, str(o.source))
			apply_status(u, "slow", int(HHTune.value("overfreeze_slow_ticks")))
	_land_reactions(hits)
	for g in r.gales:
		_emit({ "type": "gale", "hex": g.origin, "copies": g.copies })
	for h in r.doused:
		_emit({ "type": "douse", "hex": h })
	return r


## H50: one reaction's "auto attack": the caster's basic damage at the lance's
## cadence (daggers hit half as hard twice as often; their reactions match the
## lance's), or reaction_unit_other when a monster or the arena set it off.
func reaction_unit(source: String) -> float:
	var u := unit(source)
	if u.is_empty() or u.kind != "player":
		return HHTune.value("reaction_unit_other")
	var w := str(u.weapon)
	return HHWeapons.basic_damage(w) * HHTune.value("lance_basic_ticks") / maxf(1.0, float(HHWeapons.basic_ticks(w)))


func _blast(hits: Dictionary, hex: Vector2i, mult: float, cause: String, mix: Dictionary, source: String) -> void:
	_emit({ "type": "detonate", "hex": hex, "mult": mult, "pct": mult, "mix": mix, "source": source })
	var unit_d := reaction_unit(source)
	var seen := {}
	for u in unit_at(hex):
		if not targetable(u) or u.id == source or allies(source, u.id):
			continue
		seen[u.id] = true
		_react(hits, u, unit_d * mult * (1.0 - resist_of(u, "thunder") / 100.0), cause, HHTune.value("detonate_stagger"), source)
	var ring_mult: float = HHFormulas.detonation_ring_pct(mult).value
	for n in arena.ring(hex, 1):
		for u in unit_at(n):
			if not seen.has(u.id) and targetable(u) and u.id != source and not allies(source, u.id):
				seen[u.id] = true
				_react(hits, u, unit_d * ring_mult * (1.0 - resist_of(u, "thunder") / 100.0), cause, 0.0, source)


func _react(hits: Dictionary, u: Dictionary, amount: float, cause: String, stagger: float, source: String = "") -> void:
	if not hits.has(u.id):
		hits[u.id] = []
	(hits[u.id] as Array).append({ "amount": amount, "cause": cause, "stagger": stagger, "source": source })


## Every unit a paint's reactions caught takes its strongest blast in full plus
## reaction_chain_frac of each other one (a big body standing on a dozen
## detonating hexes is hit by a chain, not a dozen full blasts). Emits
## `reaction` with the total for the view and the log.
func _land_reactions(hits: Dictionary) -> void:
	var ids := hits.keys()
	ids.sort()
	for id in ids:
		var u := unit(str(id))
		if u.is_empty():
			continue
		var list: Array = hits[id]
		list.sort_custom(func(x, y): return float(x.amount) > float(y.amount))
		var top: Dictionary = list[0]
		var total := float(top.amount)
		for i in range(1, list.size()):
			total += float(list[i].amount) * HHTune.value("reaction_chain_frac")
		_emit({ "type": "reaction", "id": u.id, "amount": total, "blasts": list.size(), "cause": top.cause })
		hurt(u, total, str(top.cause), float(top.stagger), str(top.get("source", "")), false)   # H58: reactions never interrupt


## `by` (optional): the unit that dealt it. A hunter's hit on a monster is
## remembered for aggro (aggro_id / aggro_tick, monster_target).
func hurt(u: Dictionary, amount: float, cause: String, stagger: float = 0.0, by: String = "", interrupt: bool = true) -> void:
	if not alive(u) or amount <= 0.0:
		return
	if int(u.immune) > 0:                                # H552: immunity ticks skip the whole hit
		_emit({ "type": "immune", "id": u.id, "amount": amount, "cause": cause })
		return
	if int(u.get("dash_iframes", 0)) > 0:               # H56: the first ticks of a dash dodge
		_emit({ "type": "dodge", "id": u.id, "amount": amount, "cause": cause })
		return
	var braced := rooted(u)                              # H59: a charging lance: super armour
	if braced:
		amount *= 1.0 - HHTune.value("lance_charge_guard")   # H56: the lance braces while it charges
	var by_kind := str(unit(by).get("kind", "")) if by != "" else ""
	if u.kind == "monster" and int(u.get("exposed", 0)) > 0 and by_kind == "player":
		amount *= HHTune.value("exposed_dmg_mult")      # H57: punished in its own recovery
	u.hurt_tick = tick
	if by != "" and u.kind == "monster" and str(unit(by).get("kind", "")) == "player":
		u.aggro_id = by
		u.aggro_tick = tick
	u.hp = maxf(0.0, float(u.hp) - amount)
	if stagger > 0.0 and not braced:
		var st := int(HHFormulas.stagger_ticks(stagger).value)
		if u.kind == "monster":
			st = int(float(st) * HHTune.value("monster_stagger_mult"))
		if st > int(u.stagger):
			u.stagger = st
			_stop(u)
			_emit({ "type": "stagger", "id": u.id, "ticks": st })
			if charging(u):
				cancel_charge(u, "stagger")
	_emit({ "type": "hurt", "id": u.id, "amount": amount, "cause": cause, "hp": u.hp })
	if interrupt and not braced and u.kind == "player" and by_kind == "monster" and float(u.hp) > 0.0:
		_interrupt(u, cause)                             # H58: a landed monster attack interrupts
	if float(u.hp) <= 0.0:
		_stop(u)
		u.leap = {}
		u.windup = {}
		u.untargetable = false
		if u.kind == "player":
			u.charging = {}
			u.dash = {}
		if u.kind == "player" and standing_players().any(func(o): return o.id != u.id):
			_down(u, cause)                              # H53: an ally stands, so this hunter can be revived
		else:
			_emit({ "type": "death", "id": u.id, "cause": cause })


# ------------------------------------------------------------------ downed and revive (H53)

## A hunter at 0 HP with an ally standing. HP stays 0, so every alive() check
## (orders, brains, hooks, targeting, ground, statuses) already skips it.
func _down(u: Dictionary, cause: String) -> void:
	u.downed = true
	u.revive = 0.0
	u.revive_by = ""
	u.target = ""
	u.attacking = false
	u.stagger = 0
	u.regen = {}
	u.charging = {}
	u.dash = {}
	var names: Array = (u.statuses as Dictionary).keys()
	names.sort()
	for name in names:
		_emit({ "type": "status_end", "id": u.id, "status": name })
	u.statuses = {}
	_emit({ "type": "downed", "id": u.id, "cause": cause })


## Each tick, after all damage: a downed hunter with an ally standing within
## 1 hex gains a tick of revive progress, unless one of those allies was hurt
## this tick (progress back to 0: "revive_interrupted"); with nobody by it the
## progress decays (revive_decay per tick). At revive_ticks it stands up with
## revive_hp_pct of max HP. Emits revive_progress every revive_event_every.
func _revives() -> void:
	for id in order:
		var d: Dictionary = units[id]
		if not bool(d.get("downed", false)):
			continue
		var helpers: Array = standing_players().filter(func(o): return o.id != d.id and HHHex.distance(o.hex, d.hex) <= 1)
		var before := float(d.revive)
		if helpers.is_empty():
			d.revive = maxf(0.0, before - HHTune.value("revive_decay"))
			d.revive_by = ""
			continue
		if helpers.any(func(o): return int(o.hurt_tick) == tick):
			d.revive = maxf(0.0, before - HHTune.value("revive_hit_setback"))   # H54: was a full reset
			d.revive_by = ""
			if before > 0.0:
				_emit({ "type": "revive_interrupted", "id": d.id, "by": str(helpers[0].id) })
			continue
		var need := HHTune.value("revive_ticks")
		d.revive = before + 1.0
		d.revive_by = str(helpers[0].id)
		var every := maxi(1, int(HHTune.value("revive_event_every")))
		if int(floor(float(d.revive))) / every > int(floor(before)) / every:
			_emit({ "type": "revive_progress", "id": d.id, "by": d.revive_by, "progress": d.revive, "total": need, "frac": minf(1.0, float(d.revive) / need) })
		if float(d.revive) >= need:
			_revive(d)


func _revive(d: Dictionary) -> void:
	var by := str(d.revive_by)
	d.downed = false
	d.revive = 0.0
	d.revive_by = ""
	d.hp = float(d.max_hp) * HHTune.value("revive_hp_pct") / 100.0
	d.crossed = d.hex                                     # standing up on burning ground is not "entering" it
	_emit({ "type": "revived", "id": d.id, "by": by, "hp": d.hp })


func heal(u: Dictionary, amount: float, cause: String) -> void:
	if not alive(u) or amount <= 0.0:
		return
	var before := float(u.hp)
	u.hp = minf(float(u.max_hp), before + amount)
	if float(u.hp) > before:
		_emit({ "type": "heal", "id": u.id, "amount": float(u.hp) - before, "cause": cause })


func apply_status(u: Dictionary, name: String, ticks: int) -> void:
	var cur: Dictionary = u.statuses.get(name, {})
	u.statuses[name] = { "ticks": maxi(int(cur.get("ticks", 0)), ticks) }
	_emit({ "type": "status", "id": u.id, "status": name, "ticks": ticks })


func _check_over() -> void:
	var ps := players()
	var ms := monsters()
	if not ps.is_empty() and ps.all(func(u): return not alive(u)):
		over = "dead"
		_emit({ "type": "over", "result": over })
	elif not ms.is_empty() and ms.all(func(u): return not alive(u)):
		over = "win"
		_emit({ "type": "over", "result": over })


# ------------------------------------------------------------------ replay checks

func state_hash() -> int:
	var parts := PackedStringArray()
	parts.append(str(tick))
	parts.append("dif:" + difficulty)                    # H240: the tier is part of the fight
	for id in order:
		var u: Dictionary = units[id]
		var p: Vector3 = u.pos
		parts.append("%s:%s:%d:%.2f,%.2f:%s:%d:%d:%d:%d:%d" % [id, u.hex, int(u.hp), p.x, p.z, u.element, int(u.stagger), int(u.guard), int(u.immune),
			1 if bool(u.get("downed", false)) else 0, int(float(u.get("revive", 0.0)) * 10.0)])
		if u.kind == "player":                           # H56: charge, dash and the heal zone
			var ch: Dictionary = u.get("charging", {})
			var z: Dictionary = u.get("heal_zone", {})
			parts.append("c%d:%d:d%d:%d:%d:z%d" % [int(ch.get("ticks", -1)), int(ch.get("level", 0)), int(u.get("dash_charges", 0)),
				int(u.get("dash_recharge", 0)), int((u.get("dash", {}) as Dictionary).get("ticks", -1)), int(z.get("left", -1))])
			parts.append("r%d:f%d:k%d" % [int(u.get("recovery", 0)), int(u.get("flinch", 0)), int((u.get("combo", {}) as Dictionary).get("step", 0))])
		else:
			parts.append("x%d" % int(u.get("exposed", 0)))   # H57
	var keys := charge.entries.keys()
	keys.sort()
	for h in keys:
		var e: Dictionary = charge.entries[h]
		parts.append("%s:%d:%d:%s:%d:%d" % [h, int(e.h), int(e.v), e.marker, int(e.glaze), int(e.timer)])
	for tg in telegraphs:
		parts.append("tg%d:%d" % [int(tg.id), int(tg.left)])
	if env != null:
		parts.append("env%d:%d" % [env.next_tick, env.count])
	for p in projectiles:
		parts.append("pr%d:%s:%d:%d" % [int(p.id), p.hex, int(p.left), int(p.travelled)])
	return hash("|".join(parts))
