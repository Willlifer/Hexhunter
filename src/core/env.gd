class_name HHEnv
extends RefCounted
## H51: the arena acts on its own. Every biome has one recurring event that is
## telegraphed like a monster attack (owner "env", so it hits hunters AND
## monsters: bait the monster into it) and lays its element on the ground, so
## it feeds the reaction grid: the pond's swells douse fire and carry thunder,
## the caldera's vents light fire, the cave drops dark rockfalls, the glade
## alternates healing sunbreaks with gusts of wind.
##
## Node-free and seeded (its own RNG from the sim seed, so brains' rolls do not
## shift). Numbers live in HHTune under env_*; env_on = 0 switches it off.

const OWNER := "env"

var _sim_ref: WeakRef = null     # the sim owns this object; a strong ref back would be a leak cycle
var sim: HHSim:
	get:
		return _sim_ref.get_ref() as HHSim if _sim_ref != null else null
var rng := RandomNumberGenerator.new()
var next_tick := 0
var count := 0                    ## pulses fired so far (glade alternates on this)
var by_kind := {}                 ## kind -> Array[Vector2i]


func _init(p_sim: HHSim) -> void:
	_sim_ref = weakref(p_sim)
	rng.seed = int(p_sim.seed) * 7919 + 101
	for h in p_sim.arena.cells:
		var k := p_sim.arena.kind(h)
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(h)
	for k in by_kind:
		(by_kind[k] as Array).sort()
	next_tick = _period_for(str(p_sim.arena.id))


func biome() -> String:
	return str(sim.arena.id)


func active() -> bool:
	return HHTune.value("env_on") > 0.5 and biome() in ["pond", "cave", "glade", "caldera"]


func _period() -> int:
	return _period_for(biome())


static func _period_for(b: String) -> int:
	if not b in ["pond", "cave", "glade", "caldera"]:
		return 1 << 30
	return int(HHTune.value("env_%s_every" % b) * 30.0)


func tick() -> void:
	if not active() or sim.tick < next_tick:
		return
	next_tick = sim.tick + _period()
	count += 1
	match biome():
		"pond": _pond()
		"caldera": _caldera()
		"cave": _cave()
		"glade": _glade()


func _pick(kind: String) -> Vector2i:
	var list: Array = by_kind.get(kind, [])
	if list.is_empty():
		return Vector2i(0, 0)
	return list[rng.randi_range(0, list.size() - 1)]


func _inside(hexes: Array) -> Array:
	var out: Array = []
	for h in hexes:
		if sim.arena.exists(h) and sim.charge.can_hold(h) and sim.arena.kind(h) != "edge":
			out.append(h)
	return out


func _tg(name: String, hexes: Array, warn_s: float, element: String, steps: int, dmg_pct: float, stagger: float = 0.0, status: String = "", status_ticks: int = 0) -> void:
	if hexes.is_empty():
		return
	sim.telegraph(OWNER, hexes, int(warn_s * 30.0), {
		"name": name, "element": element, "paint_steps": steps, "dmg_pct": dmg_pct,
		"stagger": stagger, "status": status, "status_ticks": status_ticks, "env": true })


## Pond: a swell rolls up from the deep water and floods a wide disk.
func _pond() -> void:
	var c := _pick("water")
	var r := int(HHTune.value("env_pond_radius"))
	_tg("env_swell", _inside(sim.arena.area(c, r)), HHTune.value("env_warn_s"), "water", 1,
		HHTune.value("env_pond_dmg_pct"), 0.15)


## Caldera: a few vents erupt, each lighting a ring of fire.
func _caldera() -> void:
	var vents: Array = (by_kind.get("vent", []) as Array).duplicate()
	var n := mini(int(HHTune.value("env_caldera_vents")), vents.size())
	for i in n:
		var v: Vector2i = vents.pop_at(rng.randi_range(0, vents.size() - 1))
		_tg("env_vent", _inside(sim.arena.area(v, 2)), HHTune.value("env_warn_s"), "fire", 2,
			HHTune.value("env_caldera_dmg_pct"), 0.2, "burn", 60)


## Cave: rocks shake loose from the ceiling over a few spots; dust and shadow linger.
func _cave() -> void:
	for i in int(HHTune.value("env_cave_rocks")):
		var c := _pick("floor")
		_tg("env_rockfall", _inside(sim.arena.area(c, 1)), HHTune.value("env_warn_s"), "dark", 1,
			HHTune.value("env_cave_dmg_pct"), 0.35)


## Glade: a sunbreak (light: heals whoever stands in it) or a gust of wind across the clearing.
func _glade() -> void:
	if count % 2 == 1:
		var c := _pick("sun") if not (by_kind.get("sun", []) as Array).is_empty() else _pick("floor")
		_tg("env_sunbreak", _inside(sim.arena.area(c, 2)), HHTune.value("env_warn_s"), "light", 2, 0.0)
	else:
		var a := _pick("floor")
		var b := _pick("floor")
		var line: Array = HHHex.line(a, b)
		_tg("env_gust", _inside(line), HHTune.value("env_warn_s"), "wind", 1, 0.0, 0.1)
