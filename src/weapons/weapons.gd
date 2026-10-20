class_name HHWeapons
## The weapon registry and the cast dispatcher. A weapon is a script with
## static funcs: `basic() -> { damage, ticks, reach }`, `skills() -> { q, w,
## e, r: { name, cooldown, text } }`, `cast(sim, u, key, aim) -> bool`,
## `counter(sim, u, attacker)`. Numbers live in HHTune under `<weapon>_*`.
## Lane A/B add daggers and bow here in Phase 2. Lane U (H550): the shared
## Elemental Exchange and potion answers live here so the "any"-weapon
## upgrades (HHUpgrades) have one home; their numbers are TUNE under
## HHTune "upgrade_*".

const WEAPONS := { "lance": "res://src/weapons/lance.gd", "daggers": "res://src/weapons/daggers.gd", "bow": "res://src/weapons/bow.gd" }

static var _cache := {}
static var _registered := false


## Numbers of the weapon-agnostic upgrades (HHUpgrades weapon "any"), read
## through HHTune as "upgrade_<key>" so the F1 panel edits them.
const TUNE := {
	"exchange_immune_ticks": 30,   # exchange_immune: 1 s of immunity after Elemental Exchange
	"exchange_burst_radius": 3,    # exchange_burst: the nova's radius round the hunter (37 hexes)
	"exchange_burst_steps": 1,     # exchange_burst: steps of the new element laid by the nova
}


static func _t(key: String) -> float:
	if not _registered:
		_registered = true
		HHTune.register("upgrade", TUNE)
	return HHTune.value("upgrade_" + key)


static func script(weapon: String) -> GDScript:
	if _cache.has(weapon):
		return _cache[weapon]
	var path: String = WEAPONS.get(weapon, "")
	var s: GDScript = load(path) if path != "" and ResourceLoader.exists(path) else null
	_cache[weapon] = s
	return s


static func reach(weapon: String) -> int:
	var s := script(weapon)
	return int(s.basic().reach) if s != null else 1


static func basic_damage(weapon: String) -> float:
	var s := script(weapon)
	return float(s.basic().damage) if s != null else 10.0


static func basic_windup(weapon: String) -> int:
	var s := script(weapon)
	return int(s.basic().get("windup", 0)) if s != null else 0


static func basic_ticks(weapon: String) -> int:
	var s := script(weapon)
	return int(s.basic().ticks) if s != null else 30


static func skills(weapon: String) -> Dictionary:
	var s := script(weapon)
	return s.skills() if s != null else {}


## Fire skill `key` ("q" | "w" | "e" | "r") for `u` aimed at `aim`. Cooldown
## and hold checks happen here; the weapon resolves the shape. False = refused.
## `level` (H56): the charged Q's level 1..3 (a `cast` of q is level 1; the
## sim's release passes the level held). Other skills ignore it.
static func cast(sim: HHSim, u: Dictionary, key: String, aim: Vector2i, level: int = 1) -> bool:
	var s := script(str(u.weapon))
	if s == null or not key in ["q", "w", "e", "r"]:
		return false
	if int(u.cooldowns[key]) > 0:
		sim._emit({ "type": "cast_refused", "id": u.id, "skill": key, "why": "cooldown" })
		return false
	var ok := false
	if key == "w":                                       # H57: Exchange gets a very short wind-up (every weapon)
		sim.begin_windup(u, "exchange", int(HHTune.value("exchange_windup")), {}, Callable(HHWeapons, "_exchange_land"))
		ok = true
	else:
		ok = s.cast(sim, u, key, aim, clampi(level, 1, 3))
	if ok:
		var sk: Dictionary = s.skills()[key]
		u.cooldowns[key] = int(sk.cooldown)
		sim._emit({ "type": "cast", "id": u.id, "skill": key, "name": str(sk.name), "aim": aim, "element": u.element, "level": clampi(level, 1, 3) })
		if (u.windup as Dictionary).is_empty() and (u.leap as Dictionary).is_empty():
			sim.begin_recovery(u, int(HHTune.value("recovery_ticks")))   # H57: an instant skill (Guard, Arcing Shot, Knifedance) recovers now
	return ok


static func _exchange_land(sim: HHSim, u: Dictionary, _data: Dictionary) -> void:
	exchange(sim, u)


## H57: the movement skills that may break a wind-up or recovery (escapes):
## Eruption's vault, Daggerleap, Arrowstorm.
const ESCAPES := { "lance": "r", "daggers": "e", "bow": "r" }


static func is_escape(weapon: String, key: String) -> bool:
	return key != "" and str(ESCAPES.get(weapon, "")) == key


## H57: lance and daggers string their basics (combo()); the bow never does.
static func has_combo(weapon: String) -> bool:
	var s := script(weapon)
	return s != null and s.has_method("combo")


## One hit of a basic string: { windup, recovery, mult, steps, stagger, splash }.
## Hit 1 (and every bow basic) is the plain basic with its own short recovery (H59).
static func combo_hit(weapon: String, step: int) -> Dictionary:
	var s := script(weapon)
	var rec := int(HHTune.value("basic_recovery_bow_ticks" if weapon == "bow" else "basic_recovery_melee_ticks"))   # H59
	var base := { "windup": basic_windup(weapon), "recovery": rec, "mult": 1.0, "steps": 1,
		"stagger": HHTune.value("basic_stagger"), "splash": 0 }
	if s != null and s.has_method("combo") and step >= 2:
		base.merge(s.combo(step), true)
	return base


## H56: what a charged Q at `level` aimed at `aim` would paint, for the aim
## preview: { hex: strength (element steps) }. Pure (no sim writes).
static func charge_shape(sim: HHSim, u: Dictionary, aim: Vector2i, level: int) -> Dictionary:
	var s := script(str(u.weapon))
	if s == null or not s.has_method("q_shape"):
		return {}
	return s.q_shape(sim, u, aim, clampi(level, 1, 3))


## Strength groups of a shape: { steps: [hexes] }, highest first, so a cast
## paints each strength once (a strength-3 centre is laid at 3, not 2 + 1).
static func by_strength(shape: Dictionary) -> Dictionary:
	var out := {}
	for h in shape:
		var k := int(shape[h])
		if not out.has(k):
			out[k] = []
		(out[k] as Array).append(h)
	return out


## Paint a shape (hex -> strength) as `u`, strongest group first.
static func paint_shape(sim: HHSim, u: Dictionary, shape: Dictionary, element: String = "") -> void:
	var groups := by_strength(shape)
	var ks := groups.keys()
	ks.sort()
	ks.reverse()
	for k in ks:
		sim.paint(groups[k], element if element != "" else str(u.element), u.id, int(k))


## A line widened sideways (H56; the lance's Broad Pierce rule, shared):
## layer k (1..) is the line shifted k hexes along the two cube directions
## next to the line's heading, so a straight line of n hexes gains exactly n
## hexes a side per layer. Returns [line, layer1, layer2, ...] (each layer
## deduplicated against everything before it, on the arena, never the
## caster's hex).
static func band(sim: HHSim, u: Dictionary, line: Array, layers: int) -> Array:
	var out: Array = [line.duplicate()]
	if line.is_empty() or layers <= 0:
		return out
	var di := HHHex.direction_index(u.hex, line[-1])
	if di < 0:
		return out
	var seen := { u.hex: true }
	for h in line:
		seen[h] = true
	for k in range(1, layers + 1):
		var layer: Array = []
		for side in [1, 5]:
			var off: Vector3i = HHHex.CUBE_DIRS[(di + side) % 6]
			for h in line:
				var n := HHHex.to_offset(HHHex.to_cube(h) + off * k)
				if sim.arena.exists(n) and not seen.has(n):
					seen[n] = true
					layer.append(n)
		out.append(layer)
	return out


## A world-space band for free-angle lines (the bow): every hex whose centre
## lies within `half_m` metres of the line's axis (from the caster through the
## line's last hex) and between its first and last hex along it; the line's
## own hexes and the caster's hex are left out.
static func side_band(sim: HHSim, u: Dictionary, line: Array, half_m: float) -> Array:
	if line.is_empty():
		return []
	var o := HHHex.to_world(u.hex)
	var axis := HHHex.to_world(line[-1]) - o
	var span := axis.length()
	if span < 1e-3:
		return []
	var dir := axis / span
	var t0 := (HHHex.to_world(line[0]) - o).dot(dir) - 0.9    # a half-step back: a staggered row starts beside the first hex
	var t1 := span + 0.01
	var inline := { u.hex: true }
	for h in line:
		inline[h] = true
	var out: Array = []
	for h in HHHex.fringe(line, 1):
		if inline.has(h) or not sim.arena.exists(h):
			continue
		var v := HHHex.to_world(h) - o
		var t := v.dot(dir)
		var perp := absf(v.x * dir.y - v.y * dir.x)
		if t >= t0 and t <= t1 and perp <= half_m:
			out.append(h)
	return out


static func counter(sim: HHSim, u: Dictionary, attacker: Dictionary) -> void:
	var s := script(str(u.weapon))
	if s != null:
		s.counter(sim, u, attacker)


## Elemental Exchange (W, every weapon): attune to the backup element, then
## the "any" upgrades: exchange_immune (immunity ticks, honoured by sim.hurt,
## H552) and exchange_burst (a nova of the NEW element round the hunter).
static func exchange(sim: HHSim, u: Dictionary) -> void:
	var a: String = u.element
	u.element = u.backup
	u.backup = a
	sim._emit({ "type": "swap", "id": u.id, "element": u.element })
	if HHUpgrades.has(u, "exchange_immune"):
		u.immune = maxi(int(u.immune), int(_t("exchange_immune_ticks")))
		sim._emit({ "type": "upgrade", "id": u.id, "upgrade": "exchange_immune", "ticks": u.immune })
	if HHUpgrades.has(u, "exchange_burst"):
		var area := sim.arena.area(u.hex, int(_t("exchange_burst_radius")))
		sim.paint(area, u.element, u.id, int(_t("exchange_burst_steps")))
		sim._emit({ "type": "upgrade", "id": u.id, "upgrade": "exchange_burst", "hexes": area, "element": u.element })


## The sim calls this when a potion lands (H554): potion_cleanse clears the
## statuses that hurt or hold a hunter. H56: the potion is a thrown zone now,
## so it cleanses every standing hunter inside the zone as it lands.
static func potion_landed(sim: HHSim, u: Dictionary) -> void:
	if HHUpgrades.has(u, "potion_cleanse"):
		var cleared: Array = []
		var z: Dictionary = u.get("heal_zone", {})
		var who: Array = [u]
		if not z.is_empty():
			who = sim.standing_players().filter(func(p): return HHHex.distance(p.hex, z.hex) <= int(z.radius))
		for p in who:
			for name in ["burn", "poison", "slow", "paralysis"]:
				if (p.statuses as Dictionary).has(name):
					(p.statuses as Dictionary).erase(name)
					if p.id == u.id:
						cleared.append(name)
					sim._emit({ "type": "status_end", "id": p.id, "status": name })
		sim._emit({ "type": "upgrade", "id": u.id, "upgrade": "potion_cleanse", "cleared": cleared })
