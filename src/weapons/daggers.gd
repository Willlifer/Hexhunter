class_name HHDaggers
## Dual daggers: two sword-sized karambits, one per hand (kickoff §6, Lane A).
##   Q Flourish    spin: damage + the element on a radius-2 area round you. 3 s.
##   W Exchange    throw the daggers up, attune to the backup element. 1 s (HHTune exchange_cd).
##   E Daggerleap  leap to the cursor hex (15 ticks), spinning, a trail of the element on every
##                 hex crossed; a small spinning strike where you land. 6 s.
##   R Knifedance  for 6 s you take 25% more damage while every second you lay the active, then
##                 the backup element on your hex and its ring, alternating. 15 s.
## Basics: fast (16 ticks, 5 of wind-up, 45), reach 1; the sim lays the element where they land (H27).
## Numbers live in TUNE (Lane A owns no HHTune keys; the integrator may lift them into HHTune,
## see DECISIONS-lane-A.md). Ticks are 30 Hz. Damage is HHSim.strike (HHFormulas.hit).

const TUNE := {
	# basics
	"reach": 1,                 # melee: adjacent to the footprint
	"basic_dmg": 45.0,          # half a lance blow, twice as often
	"basic_ticks": 16,          # 0.53 s between basics
	"basic_windup": 5,          # a flick, not a plant (H34 still: a hit breaks it)
	# Q Flourish
	"q_cd": 90,                 # 3 s
	"q_windup": 6,              # the spin gathers for 0.2 s
	"q_radius": 2,              # "large aoe": 19 hexes
	"q_dmg": 120.0,
	"q_steps": 1,               # element laid on the area
	"q_stagger": 0.2,
	# E Daggerleap
	"e_cd": 180,                # 6 s
	"e_range": 6,               # hexes; the aim clamps along the line
	"e_air_ticks": 15,          # half a second in the air
	"e_trail_steps": 1,         # element on every hex of the line crossed
	"e_land_dmg": 90.0,         # the spinning landing, radius e_land_radius
	"e_land_radius": 1,
	"e_land_stagger": 0.25,
	# R Knifedance
	"r_cd": 450,                # 15 s
	"r_ticks": 180,             # 6 s of dancing
	"r_every": 30,              # one pulse a second: active, backup, active...
	"r_vuln_pct": 25.0,         # you take 25% more damage (resist -25 on every element)
	"r_radius": 1,              # own hex + ring
	"r_steps": 1,
}


static func basic() -> Dictionary:
	return { "damage": float(TUNE.basic_dmg), "ticks": int(TUNE.basic_ticks), "reach": int(TUNE.reach), "windup": int(TUNE.basic_windup) }


static func skills() -> Dictionary:
	return {
		"q": { "name": "Flourish", "cooldown": int(TUNE.q_cd), "text": "Spin: damage and your element on a wide area round you." },
		"w": { "name": "Elemental Exchange", "cooldown": int(HHTune.value("exchange_cd")), "text": "Throw the daggers up; attune to your backup element." },
		"e": { "name": "Daggerleap", "cooldown": int(TUNE.e_cd), "text": "Leap to the cursor, spinning; a trail of your element behind you." },
		"r": { "name": "Knifedance", "cooldown": int(TUNE.r_cd), "text": "6 s: take 25% more damage; every second lay your active, then backup element round you." },
	}


static func cast(sim: HHSim, u: Dictionary, key: String, aim: Vector2i) -> bool:
	match key:
		"q":
			sim.begin_windup(u, "flourish", int(TUNE.q_windup), {}, Callable(HHDaggers, "_flourish"))
			return true
		"w":
			var a: String = u.element
			u.element = u.backup
			u.backup = a
			sim._emit({ "type": "swap", "id": u.id, "element": u.element })
			return true
		"e":
			var to := leap_target(sim, u, aim, int(TUNE.e_range))
			if to == u.hex:
				return false
			u["daggerleap_from"] = u.hex
			sim.begin_leap(u, to, int(TUNE.e_air_ticks), Callable(HHDaggers, "_daggerleap_land"))
			return true
		"r":
			if u.has("knifedance_until") and int(u.knifedance_until) > sim.tick:
				return false
			_knifedance_start(sim, u)
			return true
	return false


## Nothing blocks with a dagger in each hand: no counter.
static func counter(_sim: HHSim, _u: Dictionary, _attacker: Dictionary) -> void:
	pass


## The nearest walkable hex to `aim` within `range` of u along the line (lance R's rule).
static func leap_target(sim: HHSim, u: Dictionary, aim: Vector2i, range: int) -> Vector2i:
	var blocked := sim.blocked_for(u)
	var to := sim.arena.nearest_walkable(u.hex, aim, blocked)
	if HHHex.distance(u.hex, to) > range:
		var best: Vector2i = u.hex
		for h in HHHex.line(u.hex, to):
			if HHHex.distance(u.hex, h) <= range and sim.arena.walkable(h) and not blocked.has(h):
				best = h
		to = best
	return to


static func _flourish(sim: HHSim, u: Dictionary, _data: Dictionary) -> void:
	var area := sim.arena.area(u.hex, int(TUNE.q_radius))
	for t in sim.units_in(area, u.id):
		sim.strike(u, t, float(TUNE.q_dmg), sim.nearest_hex_of(t, u.hex), "flourish", float(TUNE.q_stagger))
	sim.paint(area, u.element, u.id, int(TUNE.q_steps))
	sim._emit({ "type": "flourish", "id": u.id, "hex": u.hex, "hexes": area, "element": u.element })


static func _daggerleap_land(sim: HHSim, u: Dictionary) -> void:
	var from: Vector2i = u.get("daggerleap_from", u.hex)
	u.erase("daggerleap_from")
	var trail: Array = []
	for h in HHHex.line(from, u.hex):
		if sim.arena.exists(h):
			trail.append(h)
	sim.paint(trail, u.element, u.id, int(TUNE.e_trail_steps))
	var land := sim.arena.area(u.hex, int(TUNE.e_land_radius))
	for t in sim.units_in(land, u.id):
		sim.strike(u, t, float(TUNE.e_land_dmg), sim.nearest_hex_of(t, u.hex), "daggerleap", float(TUNE.e_land_stagger))
	sim._emit({ "type": "daggerleap", "id": u.id, "from": from, "hex": u.hex, "hexes": trail, "element": u.element })


# ------------------------------------------------------------------ Knifedance

## Knifedance runs on the sim's per-tick brain hook (sim.brains[u.id]): the
## only per-tick callback the sim offers a weapon today. See the Request in
## DECISIONS-lane-A.md (H103) for a proper weapon tick.
static func _knifedance_start(sim: HHSim, u: Dictionary) -> void:
	var saved: Dictionary = (u.resist as Dictionary).duplicate()
	u["knifedance_resist_saved"] = saved
	var vuln := -float(TUNE.r_vuln_pct)
	for el in HHFormulas.ELEMENTS:
		u.resist[el] = float(saved.get(el, 0.0)) + vuln
	u["knifedance_until"] = sim.tick + int(TUNE.r_ticks)
	u["knifedance_next"] = sim.tick + 1                       # first pulse on the next tick
	u["knifedance_pulse"] = 0
	sim.brains[u.id] = KnifedanceTicker.new()
	sim._emit({ "type": "knifedance", "id": u.id, "phase": "start", "ticks": int(TUNE.r_ticks) })


static func _knifedance_pulse(sim: HHSim, u: Dictionary) -> void:
	var n := int(u.knifedance_pulse)
	var el: String = u.element if n % 2 == 0 else u.backup
	var area := sim.arena.area(u.hex, int(TUNE.r_radius))
	sim.paint(area, el, u.id, int(TUNE.r_steps))
	u.knifedance_pulse = n + 1
	u.knifedance_next = sim.tick + int(TUNE.r_every)
	sim._emit({ "type": "knifedance", "id": u.id, "phase": "pulse", "element": el, "hexes": area })


static func _knifedance_end(sim: HHSim, u: Dictionary) -> void:
	var saved: Dictionary = u.get("knifedance_resist_saved", {})
	u.resist = saved.duplicate()
	u.erase("knifedance_resist_saved")
	u.erase("knifedance_until")
	u.erase("knifedance_next")
	u.erase("knifedance_pulse")
	if sim.brains.get(u.id) is KnifedanceTicker:
		sim.brains.erase(u.id)
	sim._emit({ "type": "knifedance", "id": u.id, "phase": "end" })


class KnifedanceTicker:
	extends RefCounted
	func tick(sim: HHSim, u: Dictionary) -> void:
		if not u.has("knifedance_until"):
			sim.brains.erase(u.id)
			return
		if not sim.alive(u) or sim.tick >= int(u.knifedance_until):
			HHDaggers._knifedance_end(sim, u)
			return
		if sim.tick >= int(u.knifedance_next):
			HHDaggers._knifedance_pulse(sim, u)
