class_name HHLance
## The lance (kickoff §6 skills; H5: the Phase 1 weapon).
##   Q Pierce     stab forward: a line of hexes toward the cursor, element laid on it, damage to anyone in it. 3 s.
##   W Exchange   plant the spear, attune to the backup element. 1 s.
##   E Guard      block for 2 s; a hit taken while guarding answers with a stronger Pierce at the attacker. 8 s.
##   R Eruption   vault to the cursor hex; on landing a radius-2 eruption of the element. 15 s.
## All numbers: HHTune lance_*.


static func basic() -> Dictionary:
	return { "damage": HHTune.value("lance_basic_dmg"), "ticks": int(HHTune.value("lance_basic_ticks")), "reach": int(HHTune.value("lance_reach")), "windup": int(HHTune.value("lance_basic_windup")) }


static func skills() -> Dictionary:
	return {
		"q": { "name": "Pierce", "cooldown": int(HHTune.value("lance_q_cd")), "text": "Stab a line toward the cursor; lays your element on it." },
		"w": { "name": "Elemental Exchange", "cooldown": int(HHTune.value("exchange_cd")), "text": "Plant the spear; attune to your backup element." },
		"e": { "name": "Guard", "cooldown": int(HHTune.value("lance_e_cd")), "text": "Block for 2 s. A hit answers with a stronger Pierce." },
		"r": { "name": "Eruption", "cooldown": int(HHTune.value("lance_r_cd")), "text": "Vault to the cursor; erupt your element on landing." },
	}


## The Pierce line: `length` hexes from u toward `aim` (aim == u.hex: facing).
static func pierce_line(sim: HHSim, u: Dictionary, aim: Vector2i, length: int) -> Array:
	var toward := aim
	if toward == u.hex:
		var f := float(u.facing)
		var w := sim.arena.world(u.hex) + Vector3(sin(f), 0, cos(f)) * 3.0
		toward = sim.arena.from_world(w)
		if toward == u.hex:
			toward = HHHex.neighbors(u.hex)[0]
	var out: Array = []
	for h in HHHex.ray(u.hex, toward, length):
		if sim.arena.exists(h):
			out.append(h)
	return out


static func cast(sim: HHSim, u: Dictionary, key: String, aim: Vector2i) -> bool:
	match key:
		"q":
			var line := pierce_line(sim, u, aim, int(HHTune.value("lance_q_len")))
			if line.is_empty():
				return false
			sim._face(u, line[0])
			sim.begin_windup(u, "pierce", int(HHTune.value("lance_q_windup")), { "line": line }, Callable(HHLance, "_pierce_land"))
			return true
		"w":
			var a: String = u.element
			u.element = u.backup
			u.backup = a
			sim._emit({ "type": "swap", "id": u.id, "element": u.element })
			return true
		"e":
			u.guard = int(HHTune.value("lance_e_ticks"))
			sim._emit({ "type": "guard", "id": u.id, "ticks": u.guard })
			return true
		"r":
			var blocked := sim.blocked_for(u)
			var to := sim.arena.nearest_walkable(u.hex, aim, blocked)
			if HHHex.distance(u.hex, to) > int(HHTune.value("lance_r_range")):
				# clamp to range along the line toward the aim
				var line := HHHex.line(u.hex, to)
				var best: Vector2i = u.hex
				for h in line:
					if HHHex.distance(u.hex, h) <= int(HHTune.value("lance_r_range")) and sim.arena.walkable(h) and not blocked.has(h):
						best = h
				to = best
			if to == u.hex:
				return false
			sim.begin_leap(u, to, int(HHTune.value("lance_r_air_ticks")), Callable(HHLance, "_erupt"))
			return true
	return false


static func _pierce_land(sim: HHSim, u: Dictionary, data: Dictionary) -> void:
	_pierce(sim, u, data.line, HHTune.value("lance_q_dmg"), 1, "pierce")


static func _pierce(sim: HHSim, u: Dictionary, line: Array, dmg: float, steps: int, cause: String) -> void:
	for t in sim.units_in(line, u.id):
		sim.strike(u, t, dmg, sim.nearest_hex_of(t, u.hex), cause, HHTune.value("lance_q_stagger"))
	sim.paint(line, u.element, u.id, steps)
	sim._emit({ "type": "pierce", "id": u.id, "hexes": line, "element": u.element, "cause": cause })


static func _erupt(sim: HHSim, u: Dictionary) -> void:
	var area := sim.arena.area(u.hex, int(HHTune.value("lance_r_radius")))
	for t in sim.units_in(area, u.id):
		sim.strike(u, t, HHTune.value("lance_r_dmg"), sim.nearest_hex_of(t, u.hex), "eruption", HHTune.value("lance_r_stagger"))
	sim.paint(area, u.element, u.id, int(HHTune.value("lance_r_steps")))
	sim._emit({ "type": "eruption", "id": u.id, "hex": u.hex, "hexes": area, "element": u.element })


## Guard's answer: a longer, harder Pierce toward whoever hit the block.
static func counter(sim: HHSim, u: Dictionary, attacker: Dictionary) -> void:
	var line := pierce_line(sim, u, sim.nearest_hex_of(attacker, u.hex), int(HHTune.value("lance_q_len")) + 2)
	if line.is_empty():
		return
	sim._face(u, line[0])
	_pierce(sim, u, line, HHTune.value("lance_q_dmg") * HHTune.value("lance_counter_mult"), 2, "counter")
