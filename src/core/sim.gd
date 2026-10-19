class_name HHSim
extends RefCounted
## The fight as pure state on a fixed 30 Hz tick (H7, H8): units on a hex
## underlay, the charge grid, statuses, events. No nodes. Same seed + same
## orders = same fight (state_hash proves it), so co-op is lockstep wiring
## later and replays are free. HHFight draws it and feeds it orders.
##
## A unit: { id, kind: "player" | "monster", hex: Vector2i, pos: Vector3 (the
##   glide, world), prev: Vector2i, progress: 0..1 along the current step,
##   path: Array[Vector2i], facing: float (rad), hp, max_hp, element, backup,
##   reach: int (hexes), size: int (footprint radius, monsters), run: bool,
##   target: id | "", stagger: ticks, statuses: { name: { ticks, pct } },
##   cooldowns: { q, w, e, r } ticks, crossed: Vector2i (last hex charged on entry) }
##
## Orders per unit per tick (all optional):
##   { move: Vector2i (hex clicked), stop: true, target: id ("" clears),
##     run: bool, swap: true (W: active <-> backup element),
##     paint: { element, hex, steps } (the sandbox; Lane P replaces it with casts) }

const TICK := 1.0 / 30.0

var rng := RandomNumberGenerator.new()
var seed := 1
var tick := 0
var arena: HHArena
var charge: HHCharge
var units := {}
var order: Array = []          # unit ids in insertion order (deterministic iteration)
var events: Array = []         # this tick's events
var over := ""                 # "" | "win" | "dead"


func _init(p_arena: HHArena, p_seed: int = 1) -> void:
	arena = p_arena
	seed = p_seed
	rng.seed = p_seed
	charge = HHCharge.new(arena)


# ------------------------------------------------------------------ setup

func add_player(id: String, hex: Vector2i, element: String = "fire", backup: String = "water") -> Dictionary:
	var u := _unit(id, "player", hex)
	u.max_hp = HHTune.value("player_hp")
	u.hp = u.max_hp
	u.element = element
	u.backup = backup
	u.reach = 2
	return u


## A monster stub: a footprint and HP. Lane E gives it a brain and a body.
func add_monster(id: String, hex: Vector2i, hp: float = 20000.0, size: int = 2) -> Dictionary:
	var u := _unit(id, "monster", hex)
	u.max_hp = hp
	u.hp = hp
	u.size = size
	u.reach = size + 1
	return u


func _unit(id: String, kind: String, hex: Vector2i) -> Dictionary:
	var u := {
		"id": id, "kind": kind, "hex": hex, "prev": hex, "progress": 0.0, "path": [] as Array[Vector2i],
		"pos": arena.world(hex), "facing": 0.0, "hp": 1.0, "max_hp": 1.0, "element": "", "backup": "",
		"reach": 1, "size": 0, "run": false, "target": "", "stagger": 0, "statuses": {},
		"cooldowns": { "q": 0, "w": 0, "e": 0, "r": 0 }, "crossed": hex,
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


## Hexes a monster's body covers: walls for everyone else.
func footprint(u: Dictionary) -> Array:
	if int(u.size) <= 0:
		return [u.hex]
	return HHHex.area(u.hex, int(u.size))


func blocked_for(me: Dictionary) -> Dictionary:
	var b := {}
	for id in order:
		var o: Dictionary = units[id]
		if o.id == me.id or not alive(o) or o.kind != "monster":
			continue
		for h in footprint(o):
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


# ------------------------------------------------------------------ the tick

## One tick: orders, movement, ground, charge decay, statuses. Returns the
## events it raised.
func step(orders: Dictionary = {}) -> Array:
	events = []
	if over != "":
		return events
	tick += 1
	for id in order:
		var u: Dictionary = units[id]
		if not alive(u):
			continue
		if orders.has(id):
			_orders(u, orders[id])
	for id in order:
		var u: Dictionary = units[id]
		if alive(u):
			_walk(u)
	if tick % int(HHTune.value("ground_tick_every")) == 0:
		for id in order:
			var u: Dictionary = units[id]
			if alive(u):
				_ground(u)
				_statuses(u)
	for id in order:
		var u: Dictionary = units[id]
		for k in u.cooldowns:
			if int(u.cooldowns[k]) > 0:
				u.cooldowns[k] = int(u.cooldowns[k]) - 1
	charge.tick()
	_check_over()
	return events


func _emit(e: Dictionary) -> void:
	e["tick"] = tick
	events.append(e)


func _orders(u: Dictionary, o: Dictionary) -> void:
	if o.get("stop", false):
		u.path = [] as Array[Vector2i]
		u.target = ""
	if o.has("run"):
		u.run = bool(o.run)
	if o.has("target"):
		var t := str(o.target)
		u.target = t if units.has(t) else ""
	if o.has("move") and int(u.stagger) <= 0 and not _paralysed(u):
		var goal: Vector2i = o.move
		var blocked := blocked_for(u)
		var dest := arena.nearest_walkable(u.hex, goal, blocked)
		u.target = ""
		_set_path(u, arena.path(u.hex, dest, blocked))
		_emit({ "type": "move", "id": u.id, "to": dest })
	if o.get("swap", false) and u.kind == "player" and int(u.cooldowns.w) <= 0:
		var a: String = u.element
		u.element = u.backup
		u.backup = a
		_emit({ "type": "swap", "id": u.id, "element": u.element })
	if o.has("paint"):
		var p: Dictionary = o.paint
		paint([p.hex], str(p.element), u.id, int(p.get("steps", 1)))


func _set_path(u: Dictionary, p: Array[Vector2i]) -> void:
	# keep the glide continuous: if mid-step, finish the current step first
	if int(u.progress * 1000.0) > 0 and not (u.path as Array).is_empty():
		var first: Vector2i = u.path[0]
		var np: Array[Vector2i] = [first]
		np.append_array(arena.path(first, p[-1] if not p.is_empty() else first, blocked_for(u)))
		u.path = np
	else:
		u.path = p
		u.progress = 0.0


func _paralysed(u: Dictionary) -> bool:
	return u.statuses.has("paralysis") or u.statuses.has("freeze")


func _walk(u: Dictionary) -> void:
	if int(u.stagger) > 0:
		u.stagger = int(u.stagger) - 1
		return
	if _paralysed(u):
		return
	# walk into range of the target (OSRS style)
	if u.target != "" and (u.path as Array).is_empty():
		var t := unit(u.target)
		if t.is_empty() or not alive(t):
			u.target = ""
		elif HHHex.distance(u.hex, t.hex) > int(u.reach) + int(t.size):
			var p := arena.path_to_reach(u.hex, t.hex, int(u.reach) + int(t.size), blocked_for(u))
			if not p.is_empty():
				u.path = p
				u.progress = 0.0
	if (u.path as Array).is_empty():
		u.pos = arena.world(u.hex)
		u.progress = 0.0
		return
	var next: Vector2i = u.path[0]
	var ticks := HHTune.value("run_ticks") if u.run else HHTune.value("walk_ticks")
	u.progress = float(u.progress) + charge.move_mult(u.hex) / ticks
	if float(u.progress) >= 1.0 - 1e-6:          # float accumulation must not cost a tick
		u.progress = 0.0
		u.prev = u.hex
		u.hex = next
		(u.path as Array).pop_front()
		_enter(u, next)
		if (u.path as Array).is_empty():
			u.pos = arena.world(u.hex)
			_emit({ "type": "arrive", "id": u.id, "hex": u.hex })
			return
		next = u.path[0]
	var a := arena.world(u.hex)
	var b := arena.world(next)
	u.pos = a.lerp(b, float(u.progress))
	var d := b - a
	if d.length_squared() > 1e-6:
		u.facing = atan2(d.x, d.z)


## Entering a hex: crossing fire burns once.
func _enter(u: Dictionary, hex: Vector2i) -> void:
	var pct := charge.crossing_pct(hex)
	if pct > 0.0 and u.crossed != hex:
		hurt(u, HHFormulas.tile_damage(u.max_hp, pct).value, "fire_cross")
	u.crossed = hex


func _ground(u: Dictionary) -> void:
	var s := charge.standing(u.hex)
	if float(s.fire) > 0.0:
		hurt(u, HHFormulas.tile_damage(u.max_hp, float(s.fire)).value, "fire")
	if float(s.drain) > 0.0:
		hurt(u, HHFormulas.tile_damage(u.max_hp, float(s.drain)).value, "dark")
	if float(s.heal) > 0.0:
		heal(u, HHFormulas.tile_damage(u.max_hp, float(s.heal)).value, "light")


func _statuses(u: Dictionary) -> void:
	for name in u.statuses.keys():
		var st: Dictionary = u.statuses[name]
		match name:
			"burn": hurt(u, HHFormulas.tile_damage(u.max_hp, HHTune.value("burn_pct_per_s")).value, "burn")
			"poison": hurt(u, HHFormulas.tile_damage(u.max_hp, HHTune.value("poison_pct_per_s")).value, "poison")
		st.ticks = int(st.ticks) - int(HHTune.value("ground_tick_every"))
		if int(st.ticks) <= 0:
			u.statuses.erase(name)
			_emit({ "type": "status_end", "id": u.id, "status": name })


# ------------------------------------------------------------------ actions

## Lay `element` on `hexes` as `caster` and resolve what the ground did.
func paint(hexes: Array, element: String, caster: String, steps: int = 1, fresh: bool = true) -> Dictionary:
	var r := charge.apply(hexes, element, caster, steps, fresh)
	_emit({ "type": "paint", "id": caster, "element": element, "hexes": hexes.duplicate(), "changed": r.changed.duplicate() })
	for d in r.detonations:
		_blast(d.hex, float(d.pct), HHFormulas.detonation_ring_pct(float(d.pct)).value, "detonate", d.mix)
	for o in r.overheat:
		_emit({ "type": "overheat", "hex": o.hex, "ring": o.ring })
		for n in o.ring:
			for u in unit_at(n):
				hurt(u, HHFormulas.tile_damage(u.max_hp, float(o.pct)).value, "overheat")
	for o in r.overfreeze:
		_emit({ "type": "overfreeze", "hex": o.hex, "ring": o.ring })
		var hit := {}
		for n in [o.hex] + o.ring:
			for u in unit_at(n):
				if not hit.has(u.id):
					hit[u.id] = true
					hurt(u, HHFormulas.tile_damage(u.max_hp, float(o.pct)).value, "overfreeze")
	for g in r.gales:
		_emit({ "type": "gale", "hex": g.origin, "copies": g.copies })
	for h in r.doused:
		_emit({ "type": "douse", "hex": h })
	return r


func _blast(hex: Vector2i, pct: float, ring_pct: float, cause: String, mix: Dictionary) -> void:
	_emit({ "type": "detonate", "hex": hex, "pct": pct, "mix": mix })
	var hit := {}
	for u in unit_at(hex):
		hit[u.id] = true
		hurt(u, HHFormulas.tile_damage(u.max_hp, pct).value, cause)
	for n in arena.ring(hex, 1):
		for u in unit_at(n):
			if not hit.has(u.id):
				hit[u.id] = true
				hurt(u, HHFormulas.tile_damage(u.max_hp, ring_pct).value, cause)


func hurt(u: Dictionary, amount: float, cause: String, stagger: float = 0.0) -> void:
	if not alive(u) or amount <= 0.0:
		return
	u.hp = maxf(0.0, float(u.hp) - amount)
	if stagger > 0.0:
		u.stagger = maxi(int(u.stagger), int(HHFormulas.stagger_ticks(stagger).value))
	_emit({ "type": "hurt", "id": u.id, "amount": amount, "cause": cause, "hp": u.hp })
	if float(u.hp) <= 0.0:
		u.path = [] as Array[Vector2i]
		_emit({ "type": "death", "id": u.id, "cause": cause })


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

## A hash of everything that matters: equal for equal seeds and orders.
func state_hash() -> int:
	var parts := PackedStringArray()
	parts.append(str(tick))
	for id in order:
		var u: Dictionary = units[id]
		parts.append("%s:%s:%d:%.3f:%s:%d" % [id, u.hex, int(u.hp), float(u.progress), u.element, int(u.stagger)])
	var keys := charge.entries.keys()
	keys.sort()
	for h in keys:
		var e: Dictionary = charge.entries[h]
		parts.append("%s:%d:%d:%s:%d:%d" % [h, int(e.h), int(e.v), e.marker, int(e.glaze), int(e.timer)])
	return hash("|".join(parts))
