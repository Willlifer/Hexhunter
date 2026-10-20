class_name HHLance
## The lance (kickoff §6 skills; H5: the Phase 1 weapon).
##   Q Pierce     stab forward: a line of hexes toward the cursor, element laid on it, damage to anyone in it. 3 s.
##                H56: hold to charge (rooted, braced: lance_charge_guard); levels in q_shape.
##   W Exchange   plant the spear, attune to the backup element. 1 s.
##   E Guard      block for 2 s; a hit taken while guarding answers with a stronger Pierce at the attacker. 8 s.
##   R Eruption   vault to the cursor hex; on landing a radius-2 eruption of the element. 15 s.
## All numbers: HHTune lance_*. Upgrade numbers (H550) in TUNE below, read as HHTune "lance_up_*".
##   pierce_wide     Q is three hexes wide (the two parallel rays beside the line).
##   guard_stagger   E's counter also staggers (lance_up_e_stagger).
##   eruption_twice  R posts a second eruption on the same ground, a player telegraph lance_up_r_echo_ticks later.

static var _registered := false


## Upgrade numbers, F1-editable as "lance_up_<key>".
const TUNE := {
	# Q Pierce charged (H56, Lane W H95x): hold to charge, the lance roots and braces (HHTune lance_charge_guard)
	"q_l2_len": 6,            # level 2 (held 1.5 s): a longer stab ...
	"q_l2_steps": 2,          # ... at strength 2
	"q_l2_mult": 1.8,         # ... x lance_q_dmg
	"q_l2_stagger": 0.45,
	"q_l3_len": 6,            # level 3 (3 s, fires itself): a 3-wide lunge this long
	"q_l3_centre_steps": 3,   # ... the centre line at strength 3
	"q_l3_side_steps": 2,     # ... the two side lines at strength 2
	"q_l3_mult": 3.5,         # ... x lance_q_dmg ("big damage")
	"q_l3_stagger": 0.9,      # ... heavy stagger
	"q_l3_windup": 16,        # the full lunge winds up longer than the stab (lance_q_windup)
	# basic string (H57): hit 1 is the plain basic (lance_basic_windup, HHTune recovery_ticks)
	"combo2_windup": 14,      # hit 2: the sweeping slash
	"combo2_recovery": 12,
	"combo2_mult": 1.35,      # x lance_basic_dmg
	"combo2_steps": 1,
	"combo2_stagger": 0.15,
	"combo3_windup": 18,      # hit 3: the spinning slam, the finisher
	"combo3_recovery": 17,    # ~0.57 s: the longest commit
	"combo3_mult": 2.0,
	"combo3_steps": 2,        # strength 2 ...
	"combo3_splash": 1,       # ... on the blow's hex and its ring
	"combo3_stagger": 0.5,
	"up_q_width": 3,         # pierce_wide: hexes across (1 = the plain line, 3 = line plus both sides; +2 on the level-3 lunge)
	"up_e_stagger": 1.0,      # guard_stagger: the counter's stagger strength (0..1 of stagger_max_ticks)
	"up_r_echo_ticks": 30,    # eruption_twice: the aftershock lands this many ticks after the first
	"up_r_echo_pct": 1.5,     # eruption_twice: aftershock damage, pct of the victim's max HP
}


static func _t(key: String) -> float:
	if not _registered:
		_registered = true
		HHTune.register("lance", TUNE)
	return HHTune.value("lance_" + key)


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


## pierce_wide: the line plus the parallel rays on both sides (width 3).
static func widen(sim: HHSim, u: Dictionary, line: Array, width: int) -> Array:
	if width < 3 or line.is_empty():
		return line
	var di := HHHex.direction_index(u.hex, line[0])
	if di < 0:
		return line
	var out: Array = line.duplicate()
	for side in [1, 5]:
		var off: Vector3i = HHHex.CUBE_DIRS[(di + side) % 6]
		for h in line:
			var n := HHHex.to_offset(HHHex.to_cube(h) + off)
			if sim.arena.exists(n) and not n in out:
				out.append(n)
	return out


## H57: hit 2 / 3 of the basic string (HHWeapons.combo_hit).
static func combo(step: int) -> Dictionary:
	var k := "combo%d_" % clampi(step, 2, 3)
	return { "windup": int(_t(k + "windup")), "recovery": int(_t(k + "recovery")), "mult": float(_t(k + "mult")),
		"steps": int(_t(k + "steps")), "stagger": float(_t(k + "stagger")), "splash": int(_t("combo3_splash")) if step >= 3 else 0 }


## H56: the charged Pierce's footprint, { hex: strength }.
##   1 (tap)  lance_q_len hexes at strength 1
##   2        q_l2_len hexes at strength 2
##   3        a 3-wide lunge q_l3_len long: centre strength 3, sides 2
## Broad Pierce (pierce_wide) adds one more hex a side at every level (the
## level-3 lunge goes 5 wide, its outer rows at strength 1: 1-2-3-2-1).
static func q_shape(sim: HHSim, u: Dictionary, aim: Vector2i, level: int) -> Dictionary:
	var length := int(HHTune.value("lance_q_len"))
	var steps := [1]                                     # strength per layer: centre, layer 1, layer 2 ...
	match level:
		2:
			length = int(_t("q_l2_len"))
			steps = [int(_t("q_l2_steps"))]
		3:
			length = int(_t("q_l3_len"))
			steps = [int(_t("q_l3_centre_steps")), int(_t("q_l3_side_steps"))]
	if HHUpgrades.has(u, "pierce_wide"):
		for i in maxi(0, (int(_t("up_q_width")) - 1) / 2):
			steps.append(steps[-1] if steps.size() == 1 else maxi(1, int(steps[-1]) - 1))
	var line := pierce_line(sim, u, aim, length)
	var out := {}
	var layers := HHWeapons.band(sim, u, line, steps.size() - 1)
	for i in layers.size():
		for h in layers[i]:
			out[h] = int(steps[i])
	return out


static func cast(sim: HHSim, u: Dictionary, key: String, aim: Vector2i, level: int = 1) -> bool:
	match key:
		"q":
			var line := pierce_line(sim, u, aim, int(HHTune.value("lance_q_len")))
			if line.is_empty():
				return false
			sim._face(u, line[0])
			var shape := q_shape(sim, u, aim, level)
			var ticks := int(_t("q_l3_windup")) if level >= 3 else int(HHTune.value("lance_q_windup"))
			sim.begin_windup(u, "pierce", ticks, { "shape": shape, "level": level }, Callable(HHLance, "_pierce_land"))
			return true
		"w":
			HHWeapons.exchange(sim, u)
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


## Damage multiplier of a Pierce level (1 at a tap).
static func q_mult(level: int) -> float:
	match level:
		2: return float(_t("q_l2_mult"))
		3: return float(_t("q_l3_mult"))
	return 1.0


static func q_stagger(level: int) -> float:
	match level:
		2: return float(_t("q_l2_stagger"))
		3: return float(_t("q_l3_stagger"))
	return HHTune.value("lance_q_stagger")


## The charged Pierce lands: one blow on every unit in the footprint (the
## level's damage and stagger, however many of its hexes it covers), then the
## footprint is painted strength group by strength group.
static func _pierce_land(sim: HHSim, u: Dictionary, data: Dictionary) -> void:
	var level := int(data.get("level", 1))
	var shape: Dictionary = data.get("shape", {})
	var hexes: Array = shape.keys()
	for t in sim.units_in(hexes, u.id):
		sim.strike(u, t, HHTune.value("lance_q_dmg") * q_mult(level), sim.nearest_hex_of(t, u.hex), "pierce", q_stagger(level))
	HHWeapons.paint_shape(sim, u, shape)
	sim._emit({ "type": "pierce", "id": u.id, "hexes": hexes, "element": u.element, "cause": "pierce", "level": level, "shape": shape })


static func _pierce(sim: HHSim, u: Dictionary, line: Array, dmg: float, steps: int, cause: String, stagger: float = -1.0) -> void:
	var st: float = HHTune.value("lance_q_stagger") if stagger < 0.0 else stagger
	for t in sim.units_in(line, u.id):
		sim.strike(u, t, dmg, sim.nearest_hex_of(t, u.hex), cause, st)
	sim.paint(line, u.element, u.id, steps)
	sim._emit({ "type": "pierce", "id": u.id, "hexes": line, "element": u.element, "cause": cause })


static func _erupt(sim: HHSim, u: Dictionary) -> void:
	var area := sim.arena.area(u.hex, int(HHTune.value("lance_r_radius")))
	for t in sim.units_in(area, u.id):
		sim.strike(u, t, HHTune.value("lance_r_dmg"), sim.nearest_hex_of(t, u.hex), "eruption", HHTune.value("lance_r_stagger"))
	sim.paint(area, u.element, u.id, int(HHTune.value("lance_r_steps")))
	sim._emit({ "type": "eruption", "id": u.id, "hex": u.hex, "hexes": area, "element": u.element })
	if HHUpgrades.has(u, "eruption_twice"):
		# the aftershock: a player telegraph on the same ground (the monster sees it coming)
		sim.telegraph(u.id, area, int(_t("up_r_echo_ticks")), { "dmg_pct": float(_t("up_r_echo_pct")), "element": u.element,
			"paint_steps": int(HHTune.value("lance_r_steps")), "stagger": HHTune.value("lance_r_stagger"), "name": "aftershock" })
		sim._emit({ "type": "upgrade", "id": u.id, "upgrade": "eruption_twice", "hexes": area })


## Guard's answer: a longer, harder Pierce toward whoever hit the block.
static func counter(sim: HHSim, u: Dictionary, attacker: Dictionary) -> void:
	var line := pierce_line(sim, u, sim.nearest_hex_of(attacker, u.hex), int(HHTune.value("lance_q_len")) + 2)
	if line.is_empty():
		return
	sim._face(u, line[0])
	if HHUpgrades.has(u, "pierce_wide"):
		line = widen(sim, u, line, int(_t("up_q_width")))
	_pierce(sim, u, line, HHTune.value("lance_q_dmg") * HHTune.value("lance_counter_mult"), 2, "counter",
		float(_t("up_e_stagger")) if HHUpgrades.has(u, "guard_stagger") else -1.0)
