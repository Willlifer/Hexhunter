class_name HHBow
## The winged recurve bow (kickoff §6, Lane A). Held in the left hand; the arrow is art/weapons/arrow.glb.
##   Q Energized shot  an arrow along the line to the cursor, up to 10 hexes: lays the element on every
##                     hex it passes and hits the first monster in its way. 3 s.
##   W Exchange        flip the quiver, attune to the backup element. 1 s (HHTune exchange_cd).
##   E Arcing shot     a lobbed elemental bomb: a radius-1 player telegraph on the cursor hex that
##                     lands after 24 ticks (the monster can see it coming), damage + 2 steps. 6 s.
##   R Arrowstorm      shoot up and jump very high (60 ticks, untargetable); on landing a radius-3
##                     downfall of arrows and element. 20 s. (Air control: see Request H104.)
## Basics: ranged, reach 7, 8 ticks of wind-up, 55 every 30 ticks; the sim lays the element on the
## target's hex (H27). Numbers live in TUNE; ticks are 30 Hz; damage is HHSim.strike / HHFormulas.

static var _registered := false


## H107: every number reads through HHTune under the "bow_" prefix (the F1
## panel edits them live); TUNE holds the defaults.
static func _t(key: String) -> float:
	if not _registered:
		_registered = true
		HHTune.register("bow", TUNE)
	return HHTune.value("bow_" + key)


const TUNE := {
	# basics
	"reach": 7,                 # hexes to the target's footprint
	"basic_dmg": 55.0,
	"basic_ticks": 30,          # one arrow a second
	"basic_windup": 8,          # the draw
	# Q Energized shot
	"q_cd": 90,                 # 3 s
	"q_windup": 8,
	"q_range": 10,              # hexes of flight
	"q_dmg": 130.0,
	"q_steps": 1,               # element on every hex passed
	"q_stagger": 0.15,
	# E Arcing shot
	"e_cd": 180,                # 6 s
	"e_range": 9,               # how far the lob reaches; the aim clamps along the line
	"e_radius": 1,              # the burst: 7 hexes
	"e_ticks": 24,              # flight time: the telegraph the monster sees
	"e_dmg_pct": 1.0,           # percent of the victim's max HP (HHFormulas.tile_damage)
	"e_steps": 2,
	"e_stagger": 0.2,
	# R Arrowstorm
	"r_cd": 600,                # 20 s
	"r_range": 4,               # you may drift this far while up (aim hex); 0 = straight up
	"r_air_ticks": 60,          # 2 s in the air, untargetable
	"r_radius": 3,              # the downfall: 37 hexes
	"r_dmg": 240.0,
	"r_steps": 2,
	"r_stagger": 0.5,
}


static func basic() -> Dictionary:
	return { "damage": float(_t("basic_dmg")), "ticks": int(_t("basic_ticks")), "reach": int(_t("reach")), "windup": int(_t("basic_windup")) }


static func skills() -> Dictionary:
	return {
		"q": { "name": "Energized Shot", "cooldown": int(_t("q_cd")), "text": "An arrow along the line to the cursor; lays your element as it flies, hits the first monster." },
		"w": { "name": "Elemental Exchange", "cooldown": int(HHTune.value("exchange_cd")), "text": "Flip the quiver; attune to your backup element." },
		"e": { "name": "Arcing Shot", "cooldown": int(_t("e_cd")), "text": "Lob an elemental bomb at the cursor; it bursts where it lands." },
		"r": { "name": "Arrowstorm", "cooldown": int(_t("r_cd")), "text": "Shoot up and leap high, untargetable; a storm of arrows and element where you land." },
	}


static func cast(sim: HHSim, u: Dictionary, key: String, aim: Vector2i) -> bool:
	match key:
		"q":
			var path := shot_line(sim, u, aim, int(_t("q_range")))
			if path.is_empty():
				return false
			sim._face(u, path[0])
			sim.begin_windup(u, "energized", int(_t("q_windup")), { "line": path }, Callable(HHBow, "_energized_land"))
			return true
		"w":
			var a: String = u.element
			u.element = u.backup
			u.backup = a
			sim._emit({ "type": "swap", "id": u.id, "element": u.element })
			return true
		"e":
			var at := clamp_along(sim, u, aim, int(_t("e_range")))
			if not sim.arena.exists(at):
				return false
			sim._face(u, at)
			var burst := sim.arena.area(at, int(_t("e_radius")))
			sim.telegraph(u.id, burst, int(_t("e_ticks")), { "dmg_pct": float(_t("e_dmg_pct")), "element": u.element,
				"paint_steps": int(_t("e_steps")), "stagger": float(_t("e_stagger")), "name": "arcing shot" })
			return true
		"r":
			var to := leap_target(sim, u, aim, int(_t("r_range")))
			sim.begin_leap(u, to, int(_t("r_air_ticks")), Callable(HHBow, "_arrowstorm_land"), true)   # H42: steer while airborne
			return true
	return false


## The bow blocks nothing: no counter.
static func counter(_sim: HHSim, _u: Dictionary, _attacker: Dictionary) -> void:
	pass


## The flight line of a shot: from u toward `aim`, extended (or cut) to `range`
## hexes, on the arena, the caster's hex excluded. aim == u.hex shoots the facing.
static func shot_line(sim: HHSim, u: Dictionary, aim: Vector2i, range: int) -> Array:
	var toward := aim
	if toward == u.hex:
		var f := float(u.facing)
		var w := sim.arena.world(u.hex) + Vector3(sin(f), 0, cos(f)) * 3.0
		toward = sim.arena.from_world(w)
		if toward == u.hex:
			toward = HHHex.neighbors(u.hex)[0]
	var n := HHHex.distance(u.hex, toward)
	var ac := HHHex.to_cube(u.hex)
	var bc := HHHex.to_cube(toward)
	var k := float(range) / float(n)
	var far := HHHex.cube_round(ac.x + (bc.x - ac.x) * k, ac.y + (bc.y - ac.y) * k, ac.z + (bc.z - ac.z) * k)
	var out: Array = []
	for h in HHHex.line(u.hex, far).slice(1):
		if out.size() >= range:
			break
		if not sim.arena.exists(h):
			break
		out.append(h)
	return out


## The hex on the line from u to `aim`, no farther than `range`.
static func clamp_along(sim: HHSim, u: Dictionary, aim: Vector2i, range: int) -> Vector2i:
	if HHHex.distance(u.hex, aim) <= range:
		return aim
	var best: Vector2i = u.hex
	for h in HHHex.line(u.hex, aim):
		if HHHex.distance(u.hex, h) <= range and sim.arena.exists(h):
			best = h
	return best


## Where a leap may land: the nearest walkable hex to `aim` within `range` (own hex when none).
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


static func _energized_land(sim: HHSim, u: Dictionary, data: Dictionary) -> void:
	var line: Array = data.line
	var passed: Array = []
	var hit := ""
	for h in line:
		passed.append(h)
		var found := false
		for t in sim.unit_at(h):
			if t.id == u.id or not sim.targetable(t) or t.kind != "monster":
				continue
			sim.strike(u, t, float(_t("q_dmg")), h, "energized shot", float(_t("q_stagger")))
			hit = t.id
			found = true
			break
		if found:
			break
	sim.paint(passed, u.element, u.id, int(_t("q_steps")))
	sim._emit({ "type": "energized_shot", "id": u.id, "hexes": passed, "hit": hit, "element": u.element })


static func _arrowstorm_land(sim: HHSim, u: Dictionary) -> void:
	var area := sim.arena.area(u.hex, int(_t("r_radius")))
	for t in sim.units_in(area, u.id):
		sim.strike(u, t, float(_t("r_dmg")), sim.nearest_hex_of(t, u.hex), "arrowstorm", float(_t("r_stagger")))
	sim.paint(area, u.element, u.id, int(_t("r_steps")))
	sim._emit({ "type": "arrowstorm", "id": u.id, "hex": u.hex, "hexes": area, "element": u.element })
