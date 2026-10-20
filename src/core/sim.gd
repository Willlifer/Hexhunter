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
##   allowed_kinds, untargetable, resist }
##
## Orders per unit per tick (all optional):
##   { move: Vector2i, move_pos: Vector3 (the exact point), stop: true,
##     target: id, attack: true (right-click on the monster, H32), run: bool,
##     swap: true, cast: { skill, aim: Vector2i }, potion: true (T, H40),
##     paint: {...} (sandbox) }

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
var hooks := {}                # unit id -> Object with tick(sim, u): a weapon's per-tick work (Knifedance), H42
var telegraphs: Array = []
var events: Array = []
var over := ""
var sandbox := false
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
	u.run = true
	u.potions = int(HHTune.value("potion_count"))
	u.cooldowns["t"] = 0
	return u


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
		"goal_pos": NO_POS, "pos": arena.stand(hex), "facing": 0.0, "hp": 1.0, "max_hp": 1.0,
		"element": "", "backup": "", "reach": 1, "size": 0, "run": false, "target": "", "attacking": false,
		"stagger": 0, "statuses": {}, "cooldowns": { "q": 0, "w": 0, "e": 0, "r": 0, "basic": 0 },
		"crossed": hex, "weapon": "", "guard": 0, "leap": {}, "windup": {}, "allowed_kinds": [],
		"untargetable": false, "resist": {}, "potions": 0, "regen": {},
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


## Walls for `me`: living monsters' footprints (not its own) plus, for a
## monster, the cells outside its allowed kinds.
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
	for id in brains.keys():
		var u: Dictionary = units.get(id, {})
		if not u.is_empty() and alive(u):
			brains[id].tick(self, u)
	for id in hooks.keys():
		var u: Dictionary = units.get(id, {})
		if not u.is_empty() and alive(u):
			hooks[id].tick(self, u)
	for id in order:
		var u: Dictionary = units[id]
		if alive(u):
			_windup(u)
			if u.kind == "player":
				_walk_free(u)
			else:
				_walk_hex(u)
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


## Committed to an action (wind-up, vault, stagger, paralysis): no new moves.
func held(u: Dictionary) -> bool:
	return int(u.stagger) > 0 or _paralysed(u) or not (u.leap as Dictionary).is_empty() or not (u.windup as Dictionary).is_empty()


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
	if o.has("move") and not held(u):
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
	if o.get("swap", false) and u.kind == "player" and not held(u):
		HHWeapons.cast(self, u, "w", u.hex)
	if o.has("cast") and u.kind == "player" and not held(u):
		var cst: Dictionary = o.cast
		HHWeapons.cast(self, u, str(cst.get("skill", "")), cst.get("aim", u.hex))
	if o.get("potion", false) and u.kind == "player" and not held(u):
		if int(u.potions) > 0 and int(u.cooldowns.get("t", 0)) <= 0:
			u.cooldowns["t"] = int(HHTune.value("potion_cd"))
			_stop(u)
			begin_windup(u, "potion", int(HHTune.value("potion_windup")), {}, Callable(self, "_potion_land"))
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
	if int(u.stagger) > 0:
		u.stagger = int(u.stagger) - 1
		return
	if _paralysed(u) or not (u.windup as Dictionary).is_empty():
		return
	var blocked := blocked_for(u)
	# walk into range of the target
	if u.target != "" and (u.path as Array).is_empty() and (u.goal_pos as Vector3) == NO_POS:
		var t := unit(u.target)
		if t.is_empty() or not alive(t):
			u.target = ""
			u.attacking = false
		elif targetable(t) and HHHex.distance(u.hex, t.hex) > int(u.reach) + int(t.size):
			u.path = arena.path_to_reach(u.hex, t.hex, int(u.reach) + int(t.size), blocked)
	var path: Array = u.path
	var goal: Vector3 = u.goal_pos
	if path.is_empty() and goal == NO_POS:
		if u.target != "" and units.has(u.target):
			_face_pos(u, unit(u.target).pos)
		return
	# string-pull: skip waypoints while the straight run to a later one is clear
	while path.size() >= 2 and clear_line(u.hex, path[1], blocked):
		path.pop_front()
	if path.size() == 1 and goal != NO_POS and clear_line(u.hex, arena.from_world(goal), blocked):
		path.pop_front()
	var target: Vector3
	if path.is_empty():
		target = goal
	else:
		target = arena.stand(path[0])
		if path.size() == 1 and goal != NO_POS and arena.from_world(goal) == path[0]:
			target = goal
	var mps := HHTune.value("run_mps") if u.run else HHTune.value("walk_mps")
	var step := mps * charge.move_mult(u.hex, u.id) * TICK
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
	var ticks := float(u.get("walk_ticks", HHTune.value("monster_walk_ticks")))
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


## A committed action: `ticks` of wind-up, then `on_done.call(sim, u, data)`.
## The unit cannot move or start another action meanwhile (H34).
func begin_windup(u: Dictionary, kind: String, ticks: int, data: Dictionary, on_done: Callable) -> void:
	u.windup = { "left": maxi(1, ticks), "total": maxi(1, ticks), "kind": kind, "data": data, "on_done": on_done }
	_emit({ "type": "windup", "id": u.id, "kind": kind, "ticks": ticks })


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


func _enter(u: Dictionary, hex: Vector2i) -> void:
	var pct := charge.crossing_pct(hex)
	if pct > 0.0 and u.crossed != hex and not charge.owned_by(hex, u.id):
		hurt(u, HHFormulas.tile_damage(u.max_hp, pct, resist_of(u, "fire")).value, "fire_cross")
	u.crossed = hex


func _ground(u: Dictionary) -> void:
	var s := charge.standing(u.hex)
	var mine: bool = str(s.source) == u.id                 # H33: your own element never hurts you
	if float(s.fire) > 0.0 and not mine:
		hurt(u, HHFormulas.tile_damage(u.max_hp, float(s.fire), resist_of(u, "fire")).value, "fire")
	if float(s.drain) > 0.0 and not mine:
		hurt(u, HHFormulas.tile_damage(u.max_hp, float(s.drain), resist_of(u, "dark")).value, "dark")
	if float(s.heal) > 0.0:
		heal(u, HHFormulas.tile_damage(u.max_hp, float(s.heal)).value, "light")


## H40: the potion lands: a heal over potion_seconds that the ground can
## fight (dark under you cuts it, light under you feeds it).
func _potion_land(_sim: HHSim, u: Dictionary, _data: Dictionary) -> void:
	u.potions = int(u.potions) - 1
	var secs := HHTune.value("potion_seconds")
	u.regen = { "ticks": int(secs * 30.0), "pct_per_s": HHTune.value("potion_heal_pct") / maxf(secs, 1.0) }
	u["potion_tick"] = tick                              # brains read this (they tick before wind-ups land)
	_emit({ "type": "potion", "id": u.id, "left": u.potions })


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
			"burn": hurt(u, HHFormulas.tile_damage(u.max_hp, HHTune.value("burn_pct_per_s")).value, "burn")
			"poison": hurt(u, HHFormulas.tile_damage(u.max_hp, HHTune.value("poison_pct_per_s")).value, "poison")
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
	if HHHex.distance(u.hex, t.hex) > int(u.reach) + int(t.size) or not (u.path as Array).is_empty():
		return
	if int(u.cooldowns.basic) > 0:
		return
	u.cooldowns.basic = int(HHWeapons.basic_ticks(u.weapon))
	_face_pos(u, t.pos)
	begin_windup(u, "basic", int(HHWeapons.basic_windup(u.weapon)), { "target": t.id }, Callable(self, "_basic_land"))


func _basic_land(_sim: HHSim, u: Dictionary, data: Dictionary) -> void:
	var t := unit(str(data.target))
	if t.is_empty() or not targetable(t):
		return
	if HHHex.distance(u.hex, t.hex) > int(u.reach) + int(t.size) + 1:
		_emit({ "type": "miss", "id": u.id, "target": t.id })
		return
	var hex := nearest_hex_of(t, u.hex)
	strike(u, t, HHWeapons.basic_damage(u.weapon), hex, "basic", HHTune.value("basic_stagger"))
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
		var pct := float(p.get("dmg_pct", 0.0))
		var el := str(p.get("element", ""))
		if pct > 0.0:
			var dmg: float = HHFormulas.tile_damage(u.max_hp, pct, resist_of(u, el) if el != "" else 0.0).value
			if int(u.guard) > 0:
				dmg *= 1.0 - HHTune.value("guard_reduce")
				_guard_counter(u, owner)
				hurt(u, dmg, cause, 0.0)
			else:
				hurt(u, dmg, cause, float(p.get("stagger", 0.0)))
		if str(p.get("status", "")) != "" and int(u.guard) <= 0:
			apply_status(u, str(p.status), int(p.get("status_ticks", 90)))
		hit.append(u.id)
	if str(p.get("element", "")) != "" and int(p.get("paint_steps", 0)) > 0:
		paint(tg.hexes, str(p.element), str(tg.owner), int(p.paint_steps))
	_emit({ "type": "telegraph_end", "id": tg.id, "owner": tg.owner, "hexes": tg.hexes, "hit": hit, "name": cause })


func _guard_counter(u: Dictionary, attacker: Dictionary) -> void:
	if attacker.is_empty() or not alive(attacker):
		return
	u.guard = 0
	_emit({ "type": "guard_block", "id": u.id, "from": attacker.id })
	HHWeapons.counter(self, u, attacker)


# ------------------------------------------------------------------ ground

## Lay `element` on `hexes` as `caster` and resolve what the ground did. The
## caster is immune to its own blasts and bursts (H33).
func paint(hexes: Array, element: String, caster: String, steps: int = 1, fresh: bool = true) -> Dictionary:
	var r := charge.apply(hexes, element, caster, steps, fresh)
	_emit({ "type": "paint", "id": caster, "element": element, "hexes": hexes.duplicate(), "changed": r.changed.duplicate() })
	for d in r.detonations:
		_blast(d.hex, float(d.pct), HHFormulas.detonation_ring_pct(float(d.pct)).value, "detonate", d.mix, str(d.source))
	for o in r.overheat:
		_emit({ "type": "overheat", "hex": o.hex, "ring": o.ring })
		for u in units_in(o.ring, str(o.source)):
			hurt(u, HHFormulas.tile_damage(u.max_hp, float(o.pct), resist_of(u, "fire")).value, "overheat")
	for o in r.overfreeze:
		_emit({ "type": "overfreeze", "hex": o.hex, "ring": o.ring })
		for u in units_in([o.hex] + o.ring, str(o.source)):
			hurt(u, HHFormulas.tile_damage(u.max_hp, float(o.pct), resist_of(u, "ice")).value, "overfreeze")
			apply_status(u, "slow", int(HHTune.value("overfreeze_slow_ticks")))
	for g in r.gales:
		_emit({ "type": "gale", "hex": g.origin, "copies": g.copies })
	for h in r.doused:
		_emit({ "type": "douse", "hex": h })
	return r


func _blast(hex: Vector2i, pct: float, ring_pct: float, cause: String, mix: Dictionary, source: String) -> void:
	_emit({ "type": "detonate", "hex": hex, "pct": pct, "mix": mix })
	var hit := {}
	for u in unit_at(hex):
		if not targetable(u) or u.id == source:
			continue
		hit[u.id] = true
		hurt(u, HHFormulas.tile_damage(u.max_hp, pct, resist_of(u, "thunder")).value, cause, HHTune.value("detonate_stagger"))
	for n in arena.ring(hex, 1):
		for u in unit_at(n):
			if not hit.has(u.id) and targetable(u) and u.id != source:
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
			_stop(u)
			_emit({ "type": "stagger", "id": u.id, "ticks": st })
	_emit({ "type": "hurt", "id": u.id, "amount": amount, "cause": cause, "hp": u.hp })
	if float(u.hp) <= 0.0:
		_stop(u)
		u.leap = {}
		u.windup = {}
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

func state_hash() -> int:
	var parts := PackedStringArray()
	parts.append(str(tick))
	for id in order:
		var u: Dictionary = units[id]
		var p: Vector3 = u.pos
		parts.append("%s:%s:%d:%.2f,%.2f:%s:%d:%d" % [id, u.hex, int(u.hp), p.x, p.z, u.element, int(u.stagger), int(u.guard)])
	var keys := charge.entries.keys()
	keys.sort()
	for h in keys:
		var e: Dictionary = charge.entries[h]
		parts.append("%s:%d:%d:%s:%d:%d" % [h, int(e.h), int(e.v), e.marker, int(e.glaze), int(e.timer)])
	for tg in telegraphs:
		parts.append("tg%d:%d" % [int(tg.id), int(tg.left)])
	return hash("|".join(parts))
