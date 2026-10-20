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
## statuses that hurt or hold the hunter.
static func potion_landed(sim: HHSim, u: Dictionary) -> void:
	if HHUpgrades.has(u, "potion_cleanse"):
		var cleared: Array = []
		for name in ["burn", "poison", "slow", "paralysis"]:
			if (u.statuses as Dictionary).has(name):
				(u.statuses as Dictionary).erase(name)
				cleared.append(name)
				sim._emit({ "type": "status_end", "id": u.id, "status": name })
		sim._emit({ "type": "upgrade", "id": u.id, "upgrade": "potion_cleanse", "cleared": cleared })
