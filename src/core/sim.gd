class_name HHSim
extends RefCounted
## The fight as pure state on a fixed 30 Hz tick (H7, H8): units on a hex
## underlay, the charge grid, telegraphs, statuses, events. No nodes. Same
## seed + same orders = same fight (state_hash proves it), so co-op is
## lockstep wiring later and replays are free. HHFight draws it and feeds it
## orders; monster brains (Lane E) are objects in `brains` ticked here.
##
## A unit: { id, kind: "player" | "monster", hex: Vector2i, pos: Vector3 (the
##   glide, world), prev: Vector2i, progress: 0..1 along the current step,
##   path: Array[Vector2i], facing: float (rad), hp, max_hp, element, backup,
##   reach: int (hexes), size: int (footprint radius, monsters), run: bool,
##   target: id | "", stagger: ticks, statuses: { name: { ticks } },
##   cooldowns: { q, w, e, r, basic } ticks, crossed: Vector2i,
##   weapon: "lance" | ..., attacking: bool (auto-attack intent),
##   guard: ticks of Guard left, leap: {} | { to, ticks, total, on_land },
##   allowed_kinds: [] (walkable rule) | [kinds] (monsters: where they may step),
##   untargetable: bool (a dive, a vault), resist: { element: pct } }
##
## Orders per unit per tick (all optional):
##   { move: Vector2i, stop: true, target: id ("" clears), attack: true
##     (target + auto-attack, H25), run: bool, swap: true (W),
##     cast: { skill: "q" | "e" | "r", aim: Vector2i },
##     paint: { element, hex, steps } (sandbox only, H20) }

const TICK := 1.0 / 30.0

var rng := RandomNumberGenerator.new()
var seed := 1
var tick := 0
var arena: HHArena
var charge: HHCharge
var units := {}
var order: Array = []          # unit ids in insertion order (deterministic iteration)
var brains := {}               # unit id -> Object with tick(sim, u)
var telegraphs: Array = []     # { id, owner, hexes, left, total, payload }
var events: Array = []         # this tick's events
var over := ""                 # "" | "win" | "dead"
var sandbox := false           # H20: paint orders allowed
var _next_tg := 1


func _init(p_arena: HHArena, p_seed: int = 1) -> void:
	arena = p_arena
	seed = p_seed
	rng.seed = p_seed
	charge = HHCharge.new(arena)


# ------------------------------------------------------------------ setup

func add_player(id: String, hex: Vector2i, element: String = "fire", backup: String = "water", weapon: String = "lance") -> Dictionary:
	var u := _unit(id, "player", hex)
	u.max_hp = HHTune.value("player_hp")
	u.hp = u.max_hp
	u.element = element
	u.backup = backup
	u.weapon = weapon
	u.reach = HHWeapons.reach(weapon)
	return u


## A monster: a footprint and HP; Lane E's brain and body give it life.
func add_monster(id: String, hex: Vector2i, hp: float = 20000.0, size: int = 2, allowed_kinds: Array = []) -> Dictionary:
	var u := _unit(id, "monster", hex)
	u.max_hp = hp
	u.hp = hp
	u.size = size
	u.reach = size + 1
	u.allowed_kinds = allowed_kinds
	return u


func _unit(id: String, kind: String, hex: Vector2i) -> Dictionary:
	var u := {
		"id": id, "kind": kind, "hex": hex, "prev": hex, "progress": 0.0, "path": [] as Array[Vector2i],
		"pos": arena.stand(hex), "facing": 0.0, "hp": 1.0, "max_hp": 1.0, "element": "", "backup": "",
		"reach": 1, "size": 0, "run": false, "target": "", "stagger": 0, "statuses": {},
		"cooldowns": { "q": 0, "w": 0, "e": 0, "r": 0, "basic": 0 }, "crossed": hex,
		"weapon": "", "attacking": false, "guard": 0, "leap": {}, "allowed_kinds": [],
		"untargetable": false, "resist": {},
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


## Hexes a monster's body covers: walls for everyone else.
func footprint(u: Dictionary) -> Array:
	if int(u.size) <= 0:
		return [u.hex]
	return HHHex.area(u.hex, int(u.size))


## Walls for `me` this tick: living monsters' footprints (not its own), plus
## for a monster the cells outside its allowed kinds.
func blocked_for(me: Dictionary) -> Dictionary:
	var b := {}
	for id in order:
		var o: Dictionary = units[id]
		if o.id == me.id or not alive(o) or o.kind != "monster":
			continue
		for h in footprint(o):
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


## The footprint hex of `t` nearest to `from` (where a blow lands).
func nearest_hex_of(t: Dictionary, from: Vector2i) -> Vector2i:
	var best: Vector2i = t.hex
	var bd := HHHex.distance(from, best)
	for h in footprint(t):
		var d := HHHex.distance(from, h)
		if d < bd:
			bd = d
			best = h
	return best


# ------------------------------------------------------------------ the tick

## One tick: orders, brains, movement, telegraphs, attacks, ground, charge
## decay, statuses. Returns the events it raised.
func step(orders: Dictionary = {}) -> Array:
	events = []
	if over != "":
		return events
	tick += 1
	for id in order:
		var u: Dictionary = units[id]
		if alive(u) and orders.has(id):
			_orders(u, orders[id])
	for id in brains.keys():
		var u: Dictionary = units.get(id, {})
		if not u.is_empty() and alive(u):
			brains[id].tick(self, u)
	for id in order:
		var u: Dictionary = units[id]
		if alive(u):
			_walk(u)
	_telegraphs()
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
	for id in order:
		var u: Dictionary = units[id]
		for k in u.cooldowns:
			if int(u.cooldowns[k]) > 0:
				u.cooldowns[k] = int(u.cooldowns[k]) - 1
		if int(u.guard) > 0:
			u.guard = int(u.guard) - 1
	charge.tick()
	_check_over()
	return events


func _emit(e: Dictionary) -> void:
	e["tick"] = tick
	events.append(e)


func _orders(u: Dictionary, o: Dictionary) -> void:
	var held := int(u.stagger) > 0 or _paralysed(u) or not (u.leap as Dictionary).is_empty()
	if o.get("stop", false):
		u.path = [] as Array[Vector2i]
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
		u.attacking = true                                   # H25: left-click = auto-attack
		u.path = [] as Array[Vector2i]
	if o.has("move") and not held:
		var goal: Vector2i = o.move
		var blocked := blocked_for(u)
		var dest := arena.nearest_walkable(u.hex, goal, blocked)
		u.target = ""
		u.attacking = false
		_set_path(u, arena.path(u.hex, dest, blocked))
		_emit({ "type": "move", "id": u.id, "to": dest })
	if o.get("swap", false) and u.kind == "player":
		HHWeapons.cast(self, u, "w", u.hex)
	if o.has("cast") and u.kind == "player" and not held:
		var cst: Dictionary = o.cast
		HHWeapons.cast(self, u, str(cst.get("skill", "")), cst.get("aim", u.hex))
	if o.has("paint") and sandbox:
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


## CONTRACT for brains: walk a monster toward `goal` over its allowed kinds.
## Returns false when no path exists.
func monster_move(u: Dictionary, goal: Vector2i) -> bool:
	var blocked := blocked_for(u)
	var dest := arena.nearest_walkable(u.hex, goal, blocked)
	var p := arena.path(u.hex, dest, blocked)
	if p.is_empty():
		u.path = [] as Array[Vector2i]
		return false
	_set_path(u, p)
	return true


func _walk(u: Dictionary) -> void:
	if not (u.leap as Dictionary).is_empty():
		_leap(u)
		return
	if int(u.stagger) > 0:
		u.stagger = int(u.stagger) - 1
		return
	if _paralysed(u):
		return
	# walk into range of the target (OSRS style)
	if u.target != "" and (u.path as Array).is_empty():
		var t := unit(u.target)
		if t.is_empty() or not targetable(t):
			if t.is_empty() or not alive(t):
				u.target = ""
				u.attacking = false
		elif HHHex.distance(u.hex, t.hex) > int(u.reach) + int(t.size):
			var p := arena.path_to_reach(u.hex, t.hex, int(u.reach) + int(t.size), blocked_for(u))
			if not p.is_empty():
				u.path = p
				u.progress = 0.0
	if (u.path as Array).is_empty():
		u.pos = arena.stand(u.hex)
		u.progress = 0.0
		if u.target != "" and units.has(u.target):
			_face(u, unit(u.target).hex)
		return
	var next: Vector2i = u.path[0]
	var ticks := HHTune.value("run_ticks") if u.run else HHTune.value("walk_ticks")
	if u.kind == "monster":
		ticks = HHTune.value("monster_walk_ticks")
	u.progress = float(u.progress) + charge.move_mult(u.hex) / ticks
	if float(u.progress) >= 1.0 - 1e-6:          # float accumulation must not cost a tick
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
	var a := arena.stand(u.hex)
	var b := arena.stand(toward)
	var d := b - a
	if d.length_squared() > 1e-6:
		u.facing = atan2(d.x, d.z)


## A vault (lance R): the unit flies to `to` over `total` ticks, untargetable,
## then `on_land` (a Callable taking the sim and the unit) fires.
func begin_leap(u: Dictionary, to: Vector2i, total: int, on_land: Callable) -> void:
	u.path = [] as Array[Vector2i]
	u.progress = 0.0
	u.leap = { "from": u.hex, "to": to, "ticks": 0, "total": maxi(1, total), "on_land": on_land }
	u.untargetable = true
	_face(u, to)
	_emit({ "type": "leap", "id": u.id, "to": to, "ticks": total })


func _leap(u: Dictionary) -> void:
	var L: Dictionary = u.leap
	L.ticks = int(L.ticks) + 1
	var t := float(L.ticks) / float(L.total)
	var a := arena.stand(L.from)
	var b := arena.stand(L.to)
	u.pos = a.lerp(b, t) + Vector3(0, HHTune.value("leap_height_m") * 4.0 * t * (1.0 - t), 0)
	if int(L.ticks) >= int(L.total):
		u.hex = L.to
		u.prev = L.from
		u.pos = b
		u.leap = {}
		u.untargetable = false
		u.crossed = L.to
		_emit({ "type": "land", "id": u.id, "hex": u.hex })
		if (L.on_land as Callable).is_valid():
			(L.on_land as Callable).call(self, u)


## Entering a hex: crossing fire burns once.
func _enter(u: Dictionary, hex: Vector2i) -> void:
	var pct := charge.crossing_pct(hex)
	if pct > 0.0 and u.crossed != hex:
		hurt(u, HHFormulas.tile_damage(u.max_hp, pct, resist_of(u, "fire")).value, "fire_cross")
	u.crossed = hex


func _ground(u: Dictionary) -> void:
	var s := charge.standing(u.hex)
	if float(s.fire) > 0.0:
		hurt(u, HHFormulas.tile_damage(u.max_hp, float(s.fire), resist_of(u, "fire")).value, "fire")
	if float(s.drain) > 0.0:
		hurt(u, HHFormulas.tile_damage(u.max_hp, float(s.drain), resist_of(u, "dark")).value, "dark")
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


func resist_of(u: Dictionary, element: String) -> float:
	return float((u.resist as Dictionary).get(element, 0.0))


# ------------------------------------------------------------------ attacks

## H25: the auto-attack. In reach of a targetable target with the basic
## cooldown down: a weapon blow that also lays one step of the active element
## on the hex it lands on (H27).
func _auto_attack(u: Dictionary) -> void:
	if not bool(u.attacking) or u.target == "" or int(u.stagger) > 0 or _paralysed(u) or not (u.leap as Dictionary).is_empty():
		return
	var t := unit(u.target)
	if t.is_empty() or not targetable(t):
		return
	if HHHex.distance(u.hex, t.hex) > int(u.reach) + int(t.size) or not (u.path as Array).is_empty():
		return
	if int(u.cooldowns.basic) > 0:
		return
	u.cooldowns.basic = int(HHWeapons.basic_ticks(u.weapon))
	var hex := nearest_hex_of(t, u.hex)
	_face(u, hex)
	strike(u, t, HHWeapons.basic_damage(u.weapon), hex, "basic")
	paint([hex], u.element, u.id, 1)


## One blow from `u` on `t` landing on `hex`: rear multiplier (a brain may
## expose rear_mult), resistance, then hurt.
func strike(u: Dictionary, t: Dictionary, base: float, hex: Vector2i, cause: String, stagger: float = 0.0) -> float:
	var mult := 1.0
	var brain: Variant = brains.get(t.id)
	if brain != null and brain.has_method("rear_mult"):
		mult = float(brain.rear_mult(t, u.hex))
	var dmg: float = HHFormulas.hit(base, mult, resist_of(t, u.element)).value
	hurt(t, dmg, cause, stagger)
	_emit({ "type": "strike", "id": u.id, "target": t.id, "hex": hex, "amount": dmg, "cause": cause, "rear": mult > 1.0 })
	return dmg


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


# ------------------------------------------------------------------ telegraphs

## CONTRACT for brains: a danger shape. The view draws `hexes` for `ticks`;
## then the payload lands on every unit in them (not the owner):
##   { dmg_pct, element, paint_steps, status, status_ticks, stagger 0..1,
##     clip, name, self_hit }
## Returns the telegraph id.
func telegraph(owner: String, hexes: Array, ticks: int, payload: Dictionary = {}) -> int:
	var id := _next_tg
	_next_tg += 1
	telegraphs.append({ "id": id, "owner": owner, "hexes": hexes.duplicate(), "left": maxi(1, ticks), "total": maxi(1, ticks), "payload": payload.duplicate() })
	_emit({ "type": "telegraph", "id": id, "owner": owner, "hexes": hexes.duplicate(), "ticks": ticks, "name": str(payload.get("name", "")) })
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
	for u in units_in(tg.hexes, "" if bool(p.get("self_hit", false)) else str(tg.owner)):
		var pct := float(p.get("dmg_pct", 0.0))
		var el := str(p.get("element", ""))
		if pct > 0.0:
			var dmg: float = HHFormulas.tile_damage(u.max_hp, pct, resist_of(u, el) if el != "" else 0.0).value
			if int(u.guard) > 0:
				dmg *= 1.0 - HHTune.value("guard_reduce")
				_guard_counter(u, owner)
				hurt(u, dmg, str(p.get("name", "telegraph")), 0.0)
			else:
				hurt(u, dmg, str(p.get("name", "telegraph")), float(p.get("stagger", 0.0)))
		if str(p.get("status", "")) != "" and int(u.guard) <= 0:
			apply_status(u, str(p.status), int(p.get("status_ticks", 90)))
		hit.append(u.id)
	if str(p.get("element", "")) != "" and int(p.get("paint_steps", 0)) > 0:
		paint(tg.hexes, str(p.element), str(tg.owner), int(p.paint_steps))
	_emit({ "type": "telegraph_end", "id": tg.id, "owner": tg.owner, "hexes": tg.hexes, "hit": hit, "name": str(p.get("name", "")) })


## Lance E: a blocked hit answers with a stronger Pierce toward the attacker.
func _guard_counter(u: Dictionary, attacker: Dictionary) -> void:
	if attacker.is_empty() or not alive(attacker):
		return
	u.guard = 0
	_emit({ "type": "guard_block", "id": u.id, "from": attacker.id })
	HHWeapons.counter(self, u, attacker)


# ------------------------------------------------------------------ ground

## Lay `element` on `hexes` as `caster` and resolve what the ground did.
func paint(hexes: Array, element: String, caster: String, steps: int = 1, fresh: bool = true) -> Dictionary:
	var r := charge.apply(hexes, element, caster, steps, fresh)
	_emit({ "type": "paint", "id": caster, "element": element, "hexes": hexes.duplicate(), "changed": r.changed.duplicate() })
	for d in r.detonations:
		_blast(d.hex, float(d.pct), HHFormulas.detonation_ring_pct(float(d.pct)).value, "detonate", d.mix)
	for o in r.overheat:
		_emit({ "type": "overheat", "hex": o.hex, "ring": o.ring })
		for u in units_in(o.ring):
			hurt(u, HHFormulas.tile_damage(u.max_hp, float(o.pct), resist_of(u, "fire")).value, "overheat")
	for o in r.overfreeze:
		_emit({ "type": "overfreeze", "hex": o.hex, "ring": o.ring })
		for u in units_in([o.hex] + o.ring):
			hurt(u, HHFormulas.tile_damage(u.max_hp, float(o.pct), resist_of(u, "ice")).value, "overfreeze")
			apply_status(u, "slow", int(HHTune.value("overfreeze_slow_ticks")))
	for g in r.gales:
		_emit({ "type": "gale", "hex": g.origin, "copies": g.copies })
	for h in r.doused:
		_emit({ "type": "douse", "hex": h })
	return r


func _blast(hex: Vector2i, pct: float, ring_pct: float, cause: String, mix: Dictionary) -> void:
	_emit({ "type": "detonate", "hex": hex, "pct": pct, "mix": mix })
	var hit := {}
	for u in unit_at(hex):
		if not targetable(u):
			continue
		hit[u.id] = true
		hurt(u, HHFormulas.tile_damage(u.max_hp, pct, resist_of(u, "thunder")).value, cause, HHTune.value("detonate_stagger"))
	for n in arena.ring(hex, 1):
		for u in unit_at(n):
			if not hit.has(u.id) and targetable(u):
				hit[u.id] = true
				hurt(u, HHFormulas.tile_damage(u.max_hp, ring_pct, resist_of(u, "thunder")).value, cause)


func hurt(u: Dictionary, amount: float, cause: String, stagger: float = 0.0) -> void:
	if not alive(u) or amount <= 0.0:
		return
	u.hp = maxf(0.0, float(u.hp) - amount)
	if stagger > 0.0:
		var st := int(HHFormulas.stagger_ticks(stagger).value)
		if u.kind == "monster":
			st = int(float(st) * HHTune.value("monster_stagger_mult"))
		if st > int(u.stagger):
			u.stagger = st
			u.path = [] as Array[Vector2i]
			_emit({ "type": "stagger", "id": u.id, "ticks": st })
	_emit({ "type": "hurt", "id": u.id, "amount": amount, "cause": cause, "hp": u.hp })
	if float(u.hp) <= 0.0:
		u.path = [] as Array[Vector2i]
		u.leap = {}
		u.untargetable = false
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
		parts.append("%s:%s:%d:%.3f:%s:%d:%d" % [id, u.hex, int(u.hp), float(u.progress), u.element, int(u.stagger), int(u.guard)])
	var keys := charge.entries.keys()
	keys.sort()
	for h in keys:
		var e: Dictionary = charge.entries[h]
		parts.append("%s:%d:%d:%s:%d:%d" % [h, int(e.h), int(e.v), e.marker, int(e.glaze), int(e.timer)])
	for tg in telegraphs:
		parts.append("tg%d:%d" % [int(tg.id), int(tg.left)])
	return hash("|".join(parts))
