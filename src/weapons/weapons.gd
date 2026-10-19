class_name HHWeapons
## The weapon registry and the cast dispatcher. A weapon is a script with
## static funcs: `basic() -> { damage, ticks, reach }`, `skills() -> { q, w,
## e, r: { name, cooldown, text } }`, `cast(sim, u, key, aim) -> bool`,
## `counter(sim, u, attacker)`. Numbers live in HHTune under `<weapon>_*`.
## Lane A/B add daggers and bow here in Phase 2.

const WEAPONS := { "lance": "res://src/weapons/lance.gd", "daggers": "res://src/weapons/daggers.gd", "bow": "res://src/weapons/bow.gd" }

static var _cache := {}


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
static func cast(sim: HHSim, u: Dictionary, key: String, aim: Vector2i) -> bool:
	var s := script(str(u.weapon))
	if s == null or not key in ["q", "w", "e", "r"]:
		return false
	if int(u.cooldowns[key]) > 0:
		sim._emit({ "type": "cast_refused", "id": u.id, "skill": key, "why": "cooldown" })
		return false
	var ok: bool = s.cast(sim, u, key, aim)
	if ok:
		var sk: Dictionary = s.skills()[key]
		u.cooldowns[key] = int(sk.cooldown)
		sim._emit({ "type": "cast", "id": u.id, "skill": key, "name": str(sk.name), "aim": aim, "element": u.element })
	return ok


static func counter(sim: HHSim, u: Dictionary, attacker: Dictionary) -> void:
	var s := script(str(u.weapon))
	if s != null:
		s.counter(sim, u, attacker)
