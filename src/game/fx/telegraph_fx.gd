class_name HHTelegraphFx
extends Node3D
## Lane FX (H700-H712): the wind-up effect of one telegraphed attack, drawn
## besides its danger hexes. It BUILDS over the countdown (`p` 0..1) and
## COMMITS at contact (a burst, then the ground fades). HHFxLayer owns a pool
## of these and feeds them; one effect serves every telegraph of one attack
## (same owner, name and start tick: the charge's lane segments, the barbs).
##
## Two layers (recipe()):
##   generic   by element, so every attack has something:
##             ""      dust and a ground crack line
##             fire    heat glow spreading, embers rising, smoke late
##             ice     wind whipping up (spiralling white streaks, snow motes)
##                     that crystallises in the last third: frost over the
##                     ground from the source, ice shards growing out of it
##             water   ripples and rising droplets
##             thunder crackling arcs that get denser, sparks
##             wind    streaks spiralling in
##             dark    a pool creeping in from the hex rims, low smoke
##             light   motes converging, rings closing on each hex
##   special   keyed by telegraph name (SPECIAL) for the signature moves; a
##             special can keep or drop the generic particles / ground.
## Effects key off telegraph names, elements and socket / bone NAMES on the
## body (mouth, fist_l, toe_hl ...), never mesh shapes; a missing socket
## falls back to a point estimated from the footprint.

const TICK := 1.0 / 30.0
const COMMIT_S := 0.75            ## seconds of landing flash + ground fade after contact
const GROUND_LIFT := 0.082        ## above the danger tint (0.07), under the outline (0.09)
const GROUND_CAP := 220           ## ground hexes drawn per effect (bigger areas are subsampled)
const SHARD_CAP := 40
const SHIMMER_CAP := 12

## Ground shader modes (shaders/fx_ground.gdshader).
const GROUND_MODE := { "": 0, "fire": 1, "ice": 2, "water": 3, "thunder": 4, "wind": 5, "dark": 6, "light": 7, "shadow": 8, "lane": 9, "lane_fire": 9 }

## Per-attack specials by telegraph name (payload.name, else payload.clip).
## Every name the four brains emit is listed here or falls to its element.
const SPECIAL := {
	# Colambros
	"ember_spit": "breath_fire", "charge": "charge_lane", "leap_stomp": "landing_shadow",
	# Swampfang (its telegraphs carry the clip as the name)
	"dark_spray": "swamp_spit", "water_jet": "swamp_spit", "swim": "surface_ripple",
	"surface_lunge": "surface_ripple", "death_roll_spin": "vortex",
	# Rimeslithe
	"cold_slam": "fist_frost", "frost_beam": "beam_charge", "meteor_drop": "meteor",
	"mist_breath": "ice_breath", "shoulder_charge": "charge_lane",
	# Spirewalker
	"leaping_squash": "landing_shadow", "pollen_shake": "pollen_haze", "pollen_spores": "spore_drift",
	"reed_lash": "reed_sparks", "thunder_breath": "mouth_crackle", "dark_breath": "mouth_smoke",
	# the arena itself (H51, owner "env")
	"env_swell": "env_swell", "env_vent": "env_vent", "env_rockfall": "env_rockfall",
}
## Attacks that only need their element's generic layer (listed so the test
## can prove coverage; anything unlisted also falls back to its element).
const GENERIC_ONLY := ["bite", "tail_lash", "back_roll", "quill_scatter", "charge_vent", "thrash_splash",
	"darkness", "frost_beam_light", "mist_wide", "freeze_pillar", "arm_swipe", "forearm_punch",
	"tail_drag", "barb_throw", "spore_spread", "pollen_paralysis", "arcing shot", "bomblet", "aftershock",
	"env_sunbreak", "env_gust"]
## What a special keeps of the generic layer: [particles, ground].
const KEEP := {
	"breath_fire": [false, true], "charge_lane": [false, false], "landing_shadow": [true, true],
	"swamp_spit": [true, true], "surface_ripple": [false, false], "vortex": [false, false],
	"fist_frost": [true, true], "beam_charge": [true, true], "meteor": [true, true], "ice_breath": [true, true],
	"pollen_haze": [false, true], "spore_drift": [false, false], "reed_sparks": [true, true],
	"mouth_crackle": [true, true], "mouth_smoke": [true, true],
	"env_swell": [false, false], "env_vent": [false, true], "env_rockfall": [false, false],
}

const COL := {
	"": Color(0.72, 0.62, 0.48), "fire": Color(1.0, 0.45, 0.12), "ice": Color(0.75, 0.93, 1.0),
	"water": Color(0.35, 0.65, 1.0), "thunder": Color(0.75, 0.5, 1.0), "wind": Color(0.6, 1.0, 0.65),
	"dark": Color(0.5, 0.2, 0.85), "light": Color(1.0, 0.85, 0.35),
}
const DUST := Color(0.66, 0.56, 0.42)
const SMOKE := Color(0.22, 0.2, 0.2)
const EMBER := Color(1.0, 0.55, 0.15)
const EMBER_END := Color(0.85, 0.12, 0.02)
const DUST_KICK := Color(0.84, 0.74, 0.58)      ## the charge's kicked dust: pale, so it reads on dark rock

var layer: Node                   ## HHFxLayer (sim, arena, bodies)
var key := ""
var tg_name := ""
var element := ""
var special := ""
var owner_id := ""
var payload := {}
var members := {}                 ## telegraph id -> Array of hexes (still live)
var hexes: Array = []
var pts: Array = []               ## world points of the hexes (ground surface)
var ctr := Vector3.ZERO
var start_tick := 0
var total := 1                    ## the shortest member's window (the wind-up)
var p := 0.0                      ## build 0..1
var committed := false
var commit_t := 0.0
var age := 0.0
var live := false                 ## in use (false = parked in the pool)
var keep_particles := true
var keep_ground := true

var add: HHFxParticles
var mix: HHFxParticles
var light: OmniLight3D
var rng := RandomNumberGenerator.new()
var _acc := {}
var _ground: Array = []           # [{ hex, mis: [MeshInstance3D], end_at: float (-1 live) }]
var _ground_pool: Array = []
var _modes: Array = []            # ground modes drawn, bottom first
var _shards: MultiMeshInstance3D
var _shard_data: Array = []       # [{ pos, basis, size, delay }]
var _meteor := false
var _shimmer: MultiMeshInstance3D
var _shimmer_pts: Array = []
var _kick := 0.0
var _whirls: Array = []           # ice: standing whirl centres
var _origin := Vector3.ZERO       # ground origin of spreading patterns
var _reach := 3.0
var _dir := Vector3.FORWARD

static var _ground_mats := {}
static var _shard_mesh: ArrayMesh
static var _shard_mat: StandardMaterial3D
static var _shimmer_mat: ShaderMaterial
static var _quad: QuadMesh


# ------------------------------------------------------------------ registry

## The effect a telegraph payload gets: { name, element, special } (special
## "" = the generic element layer only).
static func recipe(pl: Dictionary) -> Dictionary:
	var nm := str(pl.get("name", pl.get("clip", "")))
	var sp := str(SPECIAL.get(nm, ""))
	if bool(pl.get("ripple", false)):
		sp = "surface_ripple"
	return { "name": nm, "element": str(pl.get("element", "")), "special": sp }


## True when a name has an effect (a special, or listed as generic-only).
static func covers(name: String) -> bool:
	return SPECIAL.has(name) or name in GENERIC_ONLY


# ------------------------------------------------------------------ build

func _init() -> void:
	add = HHFxParticles.new(220, true)
	add.name = "add"
	add_child(add)
	mix = HHFxParticles.new(320, false)
	mix.name = "mix"
	add_child(mix)
	light = OmniLight3D.new()
	light.shadow_enabled = false
	light.visible = false
	light.omni_attenuation = 1.4
	add_child(light)
	_shards = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _shard_mesh_get()
	mm.instance_count = SHARD_CAP + 1
	mm.visible_instance_count = 0
	_shards.multimesh = mm
	_shards.material_override = _shard_mat_get()
	_shards.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 80, 400))
	add_child(_shards)
	_shimmer = MultiMeshInstance3D.new()
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_custom_data = true
	sm.mesh = _quad_get()
	sm.instance_count = SHIMMER_CAP
	sm.visible_instance_count = 0
	_shimmer.multimesh = sm
	_shimmer.material_override = _shimmer_mat_get()
	_shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shimmer.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 80, 400))
	add_child(_shimmer)
	visible = false


## Take a parked effect for a new attack.
func begin(p_layer: Node, p_key: String, tg: Dictionary, p_start: int) -> void:
	layer = p_layer
	key = p_key
	payload = tg.payload
	var r := recipe(payload)
	tg_name = r.name
	element = r.element
	special = r.special
	owner_id = str(tg.owner)
	start_tick = p_start
	total = int(tg.total)
	members = {}
	hexes = []
	pts = []
	p = 0.0
	committed = false
	commit_t = 0.0
	age = 0.0
	live = true
	visible = true
	_acc = {}
	_kick = 0.0
	_meteor = false
	_whirls = []
	_shard_data = []
	_shimmer_pts = []
	_shards.multimesh.visible_instance_count = 0
	_shimmer.multimesh.visible_instance_count = 0
	add.clear()
	mix.clear()
	light.visible = false
	rng.seed = hash(key)
	var keep: Array = KEEP.get(special, [true, true])
	keep_particles = bool(keep[0])
	keep_ground = bool(keep[1])
	add_member(tg)
	_frame()


## Another telegraph of the same attack (the charge's next lane segment).
func add_member(tg: Dictionary) -> void:
	var id := int(tg.id)
	if members.has(id):
		return
	members[id] = (tg.hexes as Array).duplicate()
	total = mini(total, int(tg.total))
	var arena: HHArena = layer.arena
	for h in tg.hexes:
		if arena == null or not arena.exists(h) or h in hexes:
			continue
		hexes.append(h)
		pts.append(arena.surface(h))
	ctr = Vector3.ZERO
	for q in pts:
		ctr += q
	if not pts.is_empty():
		ctr /= float(pts.size())
	_frame()
	_build_ground()
	if element == "ice" and keep_particles:
		_build_shards()
	if special == "breath_fire":
		_build_shimmer()


## A member resolved: its hexes' ground commits, a small burst there.
func end_member(id: int) -> void:
	if not members.has(id):
		return
	var hs: Array = members[id]
	members.erase(id)
	for g in _ground:
		if g.end_at < 0.0 and g.hex in hs:
			g.end_at = age
	if not committed:
		commit()
	elif special == "charge_lane":
		_lane_pass(hs)


func parked() -> bool:
	return not live


func release() -> void:
	live = false
	visible = false
	add.clear()
	mix.clear()
	light.visible = false
	for g in _ground:
		for mi in g.mis:
			(mi as MeshInstance3D).visible = false
		_ground_pool.append(g)
	_ground = []
	_shards.multimesh.visible_instance_count = 0
	_shimmer.multimesh.visible_instance_count = 0
	members = {}


## Done once every member resolved, the commit faded and the sprites died.
func finished() -> bool:
	return committed and members.is_empty() and commit_t >= COMMIT_S and add.n == 0 and mix.n == 0


# ------------------------------------------------------------------ frame

func _owner() -> Dictionary:
	var sim: HHSim = layer.sim
	return sim.unit(owner_id) if sim != null else {}


func _owner_pos() -> Vector3:
	var u := _owner()
	return u.pos if not u.is_empty() else ctr


func _facing() -> float:
	var u := _owner()
	return float(u.get("facing", 0.0)) if not u.is_empty() else 0.0


func _fwd() -> Vector3:
	var f := _facing()
	return Vector3(sin(f), 0.0, cos(f))


## A socket of the owner's body in world space: the body's posed socket when
## it has one by that name, else `fallback` (model space: +Z forward, +X left).
func sock(socket_name: String, fallback: Vector3) -> Vector3:
	var local := fallback
	var body: Node = layer.body_of(owner_id) if layer != null else null
	if body != null and body.has_method("socket") and body.call("socket", socket_name) != null:
		local = body.call("socket_pos", socket_name)
	elif body != null and body.has_method("has_bone") and bool(body.call("has_bone", socket_name)):
		local = body.call("bone_pos", socket_name)
	return Transform3D(Basis(Vector3.UP, _facing()), _owner_pos()) * local


func _size() -> int:
	var u := _owner()
	return int(u.get("size", 2)) if not u.is_empty() else 2


## Origin, reach and direction of the spreading patterns, per frame (the
## owner may turn or move during the wind-up).
func _frame() -> void:
	var o := _owner_pos()
	_dir = _fwd()
	match special:
		"surface_ripple", "meteor", "landing_shadow", "pollen_haze", "env_swell", "env_vent", "env_rockfall":
			_origin = ctr
		"breath_fire":
			_origin = o
			var best := 1e9
			for q in pts:
				var dd := Vector2(q.x - o.x, q.z - o.z).length()
				if dd < best:
					best = dd
					_origin = q
		"fist_frost":
			_origin = (sock("fist_l", Vector3(1.6, 0.3, 3.5)) + sock("fist_r", Vector3(-1.6, 0.3, 3.5))) * 0.5
		_:
			_origin = o if not _owner().is_empty() else ctr
			if str(_owner().get("kind", "")) == "player":
				_origin = ctr                           # the hunter's own shapes spread from their centre
	var far := 0.5
	for q in pts:
		far = maxf(far, Vector2(q.x - _origin.x, q.z - _origin.z).length())
	_reach = far + 0.8
	if special == "charge_lane" and not pts.is_empty():
		var d := ctr - o
		d.y = 0.0
		if d.length() > 0.1:
			_dir = d.normalized()


## Advance one frame. `p_sim` is the build from the sim's ticks (0..1).
func update(p_sim: float, delta: float) -> void:
	age += delta
	if not committed:
		p = clampf(p + delta / maxf(1.0, float(total)) / TICK, p_sim, minf(1.0, p_sim + 1.0 / maxf(1.0, float(total))))
	else:
		commit_t += delta
	_frame()
	var k := p if not committed else 1.0
	if not committed:
		if keep_particles:
			_generic(k, delta)
		_special(k, delta)
	else:
		_after(delta)
	_push_ground()
	_push_shards()
	_push_shimmer()
	add.step(delta)
	mix.step(delta)


func _rate(chan: String, per_s: float, delta: float) -> int:
	var a := float(_acc.get(chan, 0.0)) + per_s * delta
	var n := int(floor(a))
	_acc[chan] = a - n
	return n


func _pick() -> Vector3:
	if pts.is_empty():
		return ctr
	return pts[rng.randi() % pts.size()]


func _jit(r: float) -> Vector3:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * r
	return Vector3(cos(a) * d, 0.0, sin(a) * d)


func _area() -> float:
	return clampf(pow(float(maxi(1, pts.size())), 0.6), 1.0, 14.0)


func _set_light(at: Vector3, col: Color, energy: float, rng_m: float) -> void:
	light.visible = energy > 0.02
	light.position = at
	light.light_color = col
	light.light_energy = energy
	light.omni_range = rng_m


# ------------------------------------------------------------------ generic layer

func _generic(k: float, dt: float) -> void:
	var A := _area()
	var col: Color = COL.get(element, COL[""])
	match element:
		"fire":
			for i in _rate("ember", (8.0 + 34.0 * k) * A, dt):
				var q := _pick() + _jit(0.75)
				add.spawn({ "pos": q + Vector3(0, 0.1, 0), "vel": Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(1.2, 2.6) * (0.6 + k), rng.randf_range(-0.3, 0.3)),
					"life": rng.randf_range(0.6, 1.2), "size": 0.09 + 0.05 * k, "size_end": 0.04, "color": Color(1.0, 0.75, 0.3, 1.0), "color_end": Color(EMBER_END, 0.0),
					"shape": HHFxParticles.STREAK, "streak": 0.05, "drag": 0.4 })
			if k > 0.45:
				for i in _rate("smoke", 3.0 * A * k, dt):
					mix.spawn({ "pos": _pick() + _jit(0.6) + Vector3(0, 0.3, 0), "vel": Vector3(0, rng.randf_range(0.6, 1.1), 0), "life": 1.6,
						"size": 0.4, "size_end": 1.1, "color": Color(SMOKE, 0.35), "color_end": Color(SMOKE, 0.0), "shape": HHFxParticles.PUFF })
			_set_light(ctr + Vector3(0, 1.2, 0), Color(1.0, 0.5, 0.2), 0.6 + 2.6 * k, 4.0 + sqrt(float(pts.size())))
		"ice":
			_gen_ice(k, dt, A)
		"water":
			for i in _rate("drop", (6.0 + 26.0 * k) * A, dt):
				add.spawn({ "pos": _pick() + _jit(0.7) + Vector3(0, 0.05, 0), "vel": Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(1.6, 3.0) * (0.5 + k), rng.randf_range(-0.2, 0.2)),
					"life": 0.8, "size": 0.07, "size_end": 0.05, "color": Color(0.6, 0.85, 1.0, 0.9), "grav": 5.0, "shape": HHFxParticles.FLAKE })
		"thunder":
			for i in _rate("spark", (5.0 + 40.0 * k * k) * A, dt):
				var q := _pick() + _jit(0.8) + Vector3(0, rng.randf_range(0.05, 0.4 + 0.8 * k), 0)
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
				add.spawn({ "pos": q, "vel": d * rng.randf_range(4.0, 9.0), "life": rng.randf_range(0.06, 0.14), "size": 0.06 + 0.06 * k,
					"color": Color(0.9, 0.8, 1.0, 1.0), "color_end": Color(col, 0.6), "shape": HHFxParticles.STREAK, "streak": 0.05 })
			if rng.randf() < 0.25 + 0.5 * k:
				_set_light(_pick() + Vector3(0, 1.0, 0), Color(0.75, 0.55, 1.0), rng.randf_range(1.0, 3.0) * k, 5.0)
			else:
				light.visible = false
		"wind":
			for i in _rate("gust", (6.0 + 30.0 * k) * A, dt):
				var c := _pick()
				add.spawn_swirl({ "centre": c, "radius": rng.randf_range(1.2, 2.6), "angle": rng.randf() * TAU, "spin": rng.randf_range(3.5, 6.0) * (0.6 + k),
					"pull": rng.randf_range(0.8, 1.6), "rise": 0.3, "y": c.y + rng.randf_range(0.1, 0.9), "life": 0.8,
					"size": 0.06, "color": Color(0.75, 1.0, 0.8, 0.8), "shape": HHFxParticles.STREAK, "streak": 0.06 })
		"dark":
			for i in _rate("murk", (2.0 + 8.0 * k) * A, dt):
				var q := _pick() + _jit(1.0)
				mix.spawn({ "pos": q + Vector3(0, 0.15, 0), "vel": Vector3(rng.randf_range(-0.2, 0.2), 0.15, rng.randf_range(-0.2, 0.2)), "life": 1.6,
					"size": 0.35, "size_end": 0.9, "color": Color(0.1, 0.03, 0.16, 0.55), "color_end": Color(0.05, 0.0, 0.1, 0.0), "shape": HHFxParticles.PUFF })
			for i in _rate("wisp", (2.0 + 10.0 * k) * A, dt):
				add.spawn({ "pos": _pick() + _jit(0.8) + Vector3(0, 0.1, 0), "vel": Vector3(0, rng.randf_range(0.4, 1.0), 0), "life": 1.0,
					"size": 0.07, "color": Color(0.7, 0.4, 1.0, 0.9), "shape": HHFxParticles.FLAKE })
		"light":
			for i in _rate("mote", (5.0 + 26.0 * k) * A, dt):
				var c := _pick()
				add.spawn_swirl({ "centre": c, "radius": rng.randf_range(1.4, 2.8), "angle": rng.randf() * TAU, "spin": 1.2, "pull": 2.2 + 2.0 * k,
					"rise": -0.2, "y": c.y + rng.randf_range(0.6, 1.8), "life": 1.0, "size": 0.09, "size_end": 0.05,
					"color": Color(1.0, 0.9, 0.5, 0.95), "shape": HHFxParticles.FLAKE })
			_set_light(ctr + Vector3(0, 1.5, 0), Color(1.0, 0.85, 0.45), 2.2 * k, 4.0 + sqrt(float(pts.size())))
		_:
			for i in _rate("dust", (2.0 + 9.0 * k) * A, dt):
				var q := _pick() + _jit(0.7)
				mix.spawn({ "pos": q + Vector3(0, 0.1, 0), "vel": Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.2, 0.6), rng.randf_range(-0.4, 0.4)), "life": 1.2,
					"size": 0.25, "size_end": 0.7, "color": Color(DUST, 0.45), "color_end": Color(DUST, 0.0), "shape": HHFxParticles.PUFF, "drag": 0.8 })
			if k > 0.6:
				for i in _rate("grit", 10.0 * A * k, dt):
					mix.spawn({ "pos": _pick() + _jit(0.8), "vel": Vector3(0, rng.randf_range(1.0, 2.0), 0), "life": 0.5, "size": 0.05,
						"color": Color(0.25, 0.2, 0.15, 0.9), "grav": 9.0, "shape": HHFxParticles.FLAKE })


## The author's example, made the showcase: wind whips up first (white
## streaks spiralling round the area, snow motes drifting in it), then in the
## last third it turns to ice: the streaks slow and fall as glitter, frost
## spreads over the ground (fx_ground mode 2) and shards grow out of it.
func _gen_ice(k: float, dt: float, A: float) -> void:
	var wind := 1.0 - smoothstep(0.6, 0.85, k)
	var frost := smoothstep(0.55, 1.0, k)
	var spin := 3.5 + 6.5 * k
	if _whirls.is_empty():
		# a few standing whirls (one per ~10 hexes, at most 4): the streaks
		# wind round these, so the spiral reads as wind rather than noise
		var n := clampi(pts.size() / 10 + 1, 1, 4)
		var pool: Array = pts.duplicate()
		pool.shuffle()
		for j in mini(n, pool.size()):
			_whirls.append(pool[j])
	for i in _rate("whip", (16.0 + 60.0 * k) * A * (0.2 + 0.8 * wind), dt):
		var tall := rng.randf() < 0.6 and not _whirls.is_empty()
		var c: Vector3 = _whirls[rng.randi() % _whirls.size()] if tall else _pick()
		var r := rng.randf_range(0.8, 2.2) if tall else rng.randf_range(1.0, 2.4)
		mix.spawn_swirl({ "centre": c, "radius": r, "angle": rng.randf() * TAU, "spin": spin * rng.randf_range(0.85, 1.2),
			"pull": r * rng.randf_range(0.35, 0.6), "rise": rng.randf_range(1.2, 2.4) if tall else rng.randf_range(0.5, 1.2),
			"y": c.y + rng.randf_range(0.05, 0.6), "life": rng.randf_range(0.9, 1.3), "size": 0.1 + 0.05 * k, "size_end": 0.05,
			"color": Color(0.96, 0.99, 1.0, 0.95), "color_end": Color(0.82, 0.94, 1.0, 0.0), "shape": HHFxParticles.STREAK, "streak": 0.11 })
	# the snow devils: mist puffs wound round each whirl, climbing, a volume
	# the streaks wrap; they thin out as the frost takes over
	for i in _rate("devil", (10.0 + 26.0 * k) * float(_whirls.size()) * wind, dt):
		var c: Vector3 = _whirls[rng.randi() % _whirls.size()]
		var r := rng.randf_range(0.5, 1.6)
		mix.spawn_swirl({ "centre": c, "radius": r, "angle": rng.randf() * TAU, "spin": spin * 0.9, "pull": r * 0.25,
			"rise": rng.randf_range(1.0, 2.0), "y": c.y + rng.randf_range(0.0, 0.4), "life": 1.2, "size": 0.35, "size_end": 0.9,
			"color": Color(0.9, 0.96, 1.0, 0.32 + 0.2 * k), "color_end": Color(0.9, 0.96, 1.0, 0.0), "shape": HHFxParticles.PUFF })
	for i in _rate("snow", (8.0 + 26.0 * k) * A, dt):
		var c := _pick()
		mix.spawn_swirl({ "centre": c, "radius": rng.randf_range(0.4, 2.0), "angle": rng.randf() * TAU, "spin": spin * 0.6,
			"pull": 0.3, "rise": rng.randf_range(0.3, 1.0) * wind - 0.5 * frost, "y": c.y + rng.randf_range(0.2, 1.8),
			"life": 1.5, "size": 0.1, "color": Color(1.0, 1.0, 1.0, 1.0), "shape": HHFxParticles.FLAKE })
	if frost > 0.0:
		for i in _rate("glint", 26.0 * A * frost, dt):
			add.spawn({ "pos": _pick() + _jit(0.8) + Vector3(0, rng.randf_range(0.6, 2.0), 0), "vel": Vector3(0, -rng.randf_range(0.6, 1.4), 0),
				"life": 0.9, "size": 0.08, "size_end": 0.03, "color": Color(0.7, 0.95, 1.0, 1.0), "shape": HHFxParticles.SPARK })
	_set_light(ctr + Vector3(0, 1.5, 0), Color(0.6, 0.9, 1.0), 2.4 * frost, 4.0 + sqrt(float(pts.size())))


# ------------------------------------------------------------------ specials

func _special(k: float, dt: float) -> void:
	match special:
		"breath_fire": _sp_breath_fire(k, dt)
		"charge_lane": _sp_charge(k, dt)
		"landing_shadow": pass
		"swamp_spit": _sp_swamp_spit(k, dt)
		"surface_ripple": _sp_surface(k, dt)
		"vortex": _sp_vortex(k, dt)
		"fist_frost": _sp_fist_frost(k, dt)
		"beam_charge": _sp_beam(k, dt)
		"meteor": _sp_meteor(k, dt)
		"ice_breath": _sp_ice_breath(k, dt)
		"pollen_haze": _sp_pollen(k, dt)
		"spore_drift": _sp_spores(k, dt)
		"reed_sparks": _sp_reed_sparks(k, dt)
		"mouth_crackle": _sp_mouth_crackle(k, dt)
		"mouth_smoke": _sp_mouth_smoke(k, dt)
		"env_swell": _sp_swell(k, dt)
		"env_vent": _sp_vent(k, dt)
		"env_rockfall": _sp_rockfall(k, dt)


func _body_glow(role: String, col: Color, energy: float) -> void:
	var body: Node = layer.body_of(owner_id) if layer != null else null
	if body != null and body.has_method("fx_glow"):
		body.call("fx_glow", role, col, energy)


## Colambros' fire breath (ember_spit): the mouth glows orange and swells,
## leaks smoke and embers, a heat-shimmer cone grows along the hexes, the
## ground scorch spreads from it; late, a low tongue of embers licks out
## along the cone. Read at 30 m: an orange light at HEAD height, smoke above.
func _sp_breath_fire(k: float, dt: float) -> void:
	var m := sock("mouth", Vector3(0, 2.7, 4.3))
	var pulse := 0.85 + 0.15 * sin(age * (8.0 + 14.0 * k))
	add.pin(0, m, (0.8 + 2.2 * k) * pulse, Color(1.0, 0.42, 0.08, 0.6 + 0.4 * k), HHFxParticles.DOT)
	add.pin(1, m, (0.35 + 0.9 * k) * pulse, Color(1.0, 0.88, 0.5, 0.95), HHFxParticles.DOT)
	add.pin(2, m + Vector3(0, 0.1, 0), (1.4 + 2.4 * k) * pulse, Color(1.0, 0.3, 0.05, 0.18 + 0.2 * k), HHFxParticles.DOT)
	_set_light(m + _fwd() * 0.6, Color(1.0, 0.45, 0.12), (1.5 + 7.0 * k) * pulse, 7.0)
	_body_glow("teeth", Color(1.0, 0.4, 0.1), 3.0 * k)
	_body_glow("eye", Color(1.0, 0.5, 0.1), 3.0 * k)
	for i in _rate("smoke", 9.0 + 22.0 * k, dt):
		mix.spawn({ "pos": m + _jit(0.25) + Vector3(0, 0.2, 0), "vel": Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(1.4, 2.4), rng.randf_range(-0.3, 0.3)) + _fwd() * 0.3, "life": rng.randf_range(1.3, 1.9),
			"size": 0.4, "size_end": 1.9, "color": Color(0.1, 0.08, 0.08, 0.8), "color_end": Color(0.28, 0.26, 0.25, 0.0), "shape": HHFxParticles.PUFF, "drag": 0.5 })
	for i in _rate("leak", 10.0 + 40.0 * k, dt):
		add.spawn({ "pos": m + _jit(0.15), "vel": _fwd() * rng.randf_range(0.5, 1.5) + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.4, 0.8), rng.randf_range(-0.6, 0.6)),
			"life": rng.randf_range(0.5, 1.0), "size": 0.08, "size_end": 0.04, "color": Color(1.0, 0.8, 0.35, 1.0), "color_end": Color(EMBER_END, 0.0),
			"grav": 1.5, "shape": HHFxParticles.STREAK, "streak": 0.05 })
	if k > 0.45:
		# the tongue: embers racing low along the cone
		for i in _rate("tongue", 40.0 * (k - 0.45) * _area(), dt):
			var to := _pick() + Vector3(0, 0.25, 0)
			var from := m.lerp(to, rng.randf_range(0.0, 0.3))
			var v := (to - from)
			add.spawn({ "pos": from, "vel": v / 0.6, "life": 0.6, "size": 0.12, "size_end": 0.05, "color": Color(1.0, 0.6, 0.15, 0.9),
				"color_end": Color(EMBER_END, 0.0), "shape": HHFxParticles.STREAK, "streak": 0.07 })


## The charge (Colambros, Rimeslithe's shoulder charge): dust kicked BACK off
## the rear feet in two-beat scrapes, grit hopping along the lane (the ground
## rumbling), chevrons racing down the lane (fx_ground lane mode); smouldering
## (fire payload) adds ember streaks running the lane. Read at 30 m: tan
## clouds at FOOT height behind it, arrows on the ground ahead.
func _sp_charge(k: float, dt: float) -> void:
	var fire := element == "fire"
	var back := -_dir
	var side := Vector3(_dir.z, 0, -_dir.x)
	var s := float(_size())
	var feet := [sock("toe_hl", Vector3(0.7, 0.1, -0.2 - 0.4 * s)), sock("toe_hr", Vector3(-0.7, 0.1, -0.2 - 0.4 * s))]
	_kick -= dt
	if _kick <= 0.0:
		_kick = lerpf(0.42, 0.24, k)
		var foot: Vector3 = feet[int(age / 0.3) % 2]
		var n := int(6 + 8 * k)
		for i in n:
			var v := back * rng.randf_range(2.0, 5.0) + side * rng.randf_range(-3.5, 3.5) + Vector3(0, rng.randf_range(2.5, 5.5), 0)
			mix.spawn({ "pos": foot + Vector3(0, 0.3, 0), "vel": v, "life": rng.randf_range(1.2, 1.8), "size": 0.45, "size_end": 1.5 + 0.6 * k,
				"color": Color(DUST_KICK, 0.9), "color_end": Color(DUST_KICK.lightened(0.1), 0.0), "shape": HHFxParticles.PUFF, "grav": 1.0, "drag": 1.6 })
		for i in n:
			mix.spawn({ "pos": foot + Vector3(0, 0.2, 0), "vel": back * rng.randf_range(3.0, 6.0) + side * rng.randf_range(-1.0, 1.0) + Vector3(0, rng.randf_range(2.0, 4.0), 0),
				"life": 0.7, "size": 0.07, "color": Color(0.2, 0.15, 0.1, 1.0), "grav": 12.0, "shape": HHFxParticles.FLAKE })
	for i in _rate("skirt", 6.0 + 14.0 * k, dt):
		var foot2: Vector3 = feet[rng.randi() % 2]
		var out := side * (1.0 if rng.randf() < 0.5 else -1.0)
		mix.spawn({ "pos": foot2 + out * rng.randf_range(0.5, 1.5) + Vector3(0, 0.2, 0), "vel": out * rng.randf_range(0.8, 2.0) + Vector3(0, 0.5, 0) + _dir * 0.8,
			"life": 1.2, "size": 0.5, "size_end": 1.3 + 0.6 * k, "color": Color(DUST_KICK, 0.5 + 0.3 * k), "color_end": Color(DUST_KICK, 0.0),
			"shape": HHFxParticles.PUFF, "drag": 1.2 })
	for i in _rate("rumble", (8.0 + 30.0 * k) * _area() * 0.5, dt):
		mix.spawn({ "pos": _pick() + _jit(0.6) + Vector3(0, 0.05, 0), "vel": Vector3(0, rng.randf_range(0.8, 1.6), 0), "life": 0.35, "size": 0.06,
			"color": Color(0.25, 0.2, 0.15, 0.9), "grav": 10.0, "shape": HHFxParticles.FLAKE })
		if rng.randf() < 0.3:
			mix.spawn({ "pos": _pick() + _jit(0.5) + Vector3(0, 0.1, 0), "vel": _dir * 1.5 + Vector3(0, 0.3, 0), "life": 0.9, "size": 0.2, "size_end": 0.6,
				"color": Color(0.66, 0.56, 0.42, 0.35 * k), "color_end": Color(0.66, 0.56, 0.42, 0.0), "shape": HHFxParticles.PUFF, "drag": 1.0 })
	if fire:
		for i in _rate("lane_ember", 30.0 * k * _area() * 0.5, dt):
			var q := _pick() + _jit(0.5) + Vector3(0, rng.randf_range(0.1, 0.5), 0)
			add.spawn({ "pos": q, "vel": _dir * rng.randf_range(6.0, 10.0) + Vector3(0, 0.4, 0), "life": 0.45, "size": 0.1, "size_end": 0.05,
				"color": Color(1.0, 0.7, 0.25, 1.0), "color_end": Color(EMBER_END, 0.0), "shape": HHFxParticles.STREAK, "streak": 0.06 })


## A lane segment the charging body just passed: dust thrown out sideways.
func _lane_pass(hs: Array) -> void:
	var side := Vector3(_dir.z, 0, -_dir.x)
	var arena: HHArena = layer.arena
	var n := 0
	for h in hs:
		if n >= 6 or arena == null or not arena.exists(h):
			continue
		n += 1
		var q := arena.surface(h)
		for i in 2:
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			mix.spawn({ "pos": q + Vector3(0, 0.2, 0), "vel": side * sgn * rng.randf_range(2.0, 4.0) + Vector3(0, rng.randf_range(1.0, 2.0), 0) - _dir,
				"life": 1.0, "size": 0.4, "size_end": 1.4, "color": Color(0.62, 0.5, 0.36, 0.7), "color_end": Color(0.7, 0.6, 0.48, 0.0),
				"shape": HHFxParticles.PUFF, "drag": 2.0, "grav": 1.0 })
		if element == "fire":
			add.spawn({ "pos": q + Vector3(0, 0.3, 0), "vel": Vector3(0, 2.0, 0), "life": 0.5, "size": 0.5, "size_end": 0.9,
				"color": Color(1.0, 0.55, 0.15, 0.8), "color_end": Color(0.9, 0.2, 0.05, 0.0), "shape": HHFxParticles.DOT })


## Swampfang's dark spray / water jet: the frill flares and the mouth glows
## (violet for dark, blue for water) and drips before it fires.
func _sp_swamp_spit(k: float, dt: float) -> void:
	var water := element == "water"
	var col := Color(0.35, 0.7, 1.0) if water else Color(0.55, 0.2, 1.0)
	var m := sock("mouth", Vector3(0, 1.3, 4.6))
	var pulse := 0.8 + 0.2 * sin(age * (6.0 + 16.0 * k))
	add.pin(0, m, (0.4 + 1.2 * k) * pulse, Color(col, 0.5 + 0.4 * k), HHFxParticles.DOT)
	add.pin(1, m, (0.2 + 0.5 * k) * pulse, Color(0.85, 0.95, 1.0, 0.8) if water else Color(0.9, 0.7, 1.0, 0.8), HHFxParticles.DOT)
	_body_glow("frill", col, (0.5 + 3.5 * k) * pulse)
	_body_glow("eye", col, 3.0 * k)
	var fr := sock("frill", Vector3(0, 1.95, 3.0))
	add.pin(2, fr, (0.6 + 1.4 * k) * pulse, Color(col, 0.25 + 0.3 * k), HHFxParticles.RING)
	_set_light(m, col, 1.0 + 4.0 * k, 6.0)
	for i in _rate("drip", 6.0 + 24.0 * k, dt):
		var c := Color(0.6, 0.85, 1.0, 0.9) if water else Color(0.6, 0.3, 1.0, 0.9)
		add.spawn({ "pos": m + _jit(0.25), "vel": Vector3(0, rng.randf_range(-0.5, 0.3), 0) + _fwd() * 0.3, "life": 0.7, "size": 0.08,
			"color": c, "grav": 6.0, "shape": HHFxParticles.FLAKE })


## Where Swampfang will surface: the water bulges and rings run out from the
## spot, bubbles rise and pop, faster as it nears (the kickoff's ripples).
func _sp_surface(k: float, dt: float) -> void:
	add.pin(0, ctr + Vector3(0, 0.15, 0), 0.6 + 1.6 * k, Color(0.75, 0.9, 1.0, 0.18 + 0.3 * k), HHFxParticles.DOT)
	add.pin(1, ctr + Vector3(0, 0.12, 0), 0.8 + 1.8 * fmod(age * (0.8 + 1.5 * k), 1.0), Color(0.8, 0.95, 1.0, 0.5 * (1.0 - fmod(age * (0.8 + 1.5 * k), 1.0))), HHFxParticles.RING)
	for i in _rate("bubble", 6.0 + 34.0 * k, dt):
		add.spawn({ "pos": ctr + _jit(0.6 + 1.0 * k) + Vector3(0, 0.05, 0), "vel": Vector3(0, rng.randf_range(0.5, 1.2), 0), "life": rng.randf_range(0.3, 0.6),
			"size": rng.randf_range(0.07, 0.16), "color": Color(0.85, 0.95, 1.0, 0.85), "shape": HHFxParticles.RING })
	if element == "dark":
		_body_glow("frill", Color(0.55, 0.2, 1.0), 2.0 * k)


## Swampfang's death roll: a water vortex round its body, streaks whipping
## round faster and faster, spray flung off the rim.
func _sp_vortex(k: float, dt: float) -> void:
	var o := _owner_pos()
	var inner := float(_size()) + 0.5
	for i in _rate("vortex", 30.0 + 90.0 * k, dt):
		var r := rng.randf_range(inner, _reach)
		var c := o + Vector3(0, 0.05, 0)
		var sys := add if rng.randf() < 0.5 else mix
		sys.spawn_swirl({ "centre": c, "radius": r, "angle": rng.randf() * TAU, "spin": (2.5 + 7.0 * k) * (inner + 1.0) / r * 1.6,
			"pull": 0.3, "rise": rng.randf_range(0.2, 0.9), "y": c.y + rng.randf_range(0.05, 0.6), "life": rng.randf_range(0.5, 0.9),
			"size": 0.08, "color": Color(0.7, 0.9, 1.0, 0.85) if sys == add else Color(0.92, 0.97, 1.0, 0.8), "shape": HHFxParticles.STREAK, "streak": 0.07 })
	if k > 0.5:
		for i in _rate("fling", 30.0 * k, dt):
			var a := rng.randf() * TAU
			var d := Vector3(cos(a), 0, sin(a))
			add.spawn({ "pos": o + d * inner + Vector3(0, 0.5, 0), "vel": d * rng.randf_range(3.0, 6.0) + Vector3(0, rng.randf_range(1.5, 3.0), 0), "life": 0.7,
				"size": 0.08, "color": Color(0.7, 0.9, 1.0, 0.9), "grav": 8.0, "shape": HHFxParticles.FLAKE })


## Rimeslithe's cold slam: the fists planted, frost spreading from the
## knuckles (the ground's frost phase runs the whole countdown here), cold
## mist rolling off them, the knuckles glowing.
func _sp_fist_frost(k: float, dt: float) -> void:
	var fl := sock("fist_l", Vector3(2.1, 0.35, 4.35))
	var fr := sock("fist_r", Vector3(-2.1, 0.35, 4.35))
	var pulse := 0.85 + 0.15 * sin(age * (5.0 + 10.0 * k))
	add.pin(0, fl, (0.4 + 1.1 * k) * pulse, Color(0.6, 0.92, 1.0, 0.45 + 0.4 * k), HHFxParticles.DOT)
	add.pin(1, fr, (0.4 + 1.1 * k) * pulse, Color(0.6, 0.92, 1.0, 0.45 + 0.4 * k), HHFxParticles.DOT)
	_set_light((fl + fr) * 0.5 + Vector3(0, 0.6, 0), Color(0.55, 0.88, 1.0), 1.5 + 4.0 * k, 7.0)
	for fi in 2:
		var f: Vector3 = fl if fi == 0 else fr
		for i in _rate("mist%d" % fi, 8.0 + 18.0 * k, dt):
			var out := (f - _owner_pos())
			out.y = 0.0
			out = out.normalized()
			mix.spawn({ "pos": f + _jit(0.3), "vel": out * rng.randf_range(0.8, 2.0) + Vector3(rng.randf_range(-0.5, 0.5), 0.1, rng.randf_range(-0.5, 0.5)),
				"life": 1.4, "size": 0.3, "size_end": 1.1, "color": Color(0.88, 0.96, 1.0, 0.5), "color_end": Color(0.9, 0.97, 1.0, 0.0), "shape": HHFxParticles.PUFF, "drag": 1.0 })


## Rimeslithe's frost beam: charging light at the mouth, motes drawn into it,
## a ring closing on it over and over, faster toward the shot.
func _sp_beam(k: float, dt: float) -> void:
	var m := sock("mouth", Vector3(0, 1.7, 5.3))
	var pulse := 0.8 + 0.2 * sin(age * (8.0 + 20.0 * k))
	add.pin(0, m, (0.4 + 2.0 * k) * pulse, Color(0.6, 0.92, 1.0, 0.5 + 0.45 * k), HHFxParticles.DOT)
	add.pin(1, m, (0.2 + 0.8 * k) * pulse, Color(1.0, 1.0, 1.0, 0.95), HHFxParticles.SPARK)
	var cyc := fmod(age * (0.8 + 2.5 * k), 1.0)
	add.pin(2, m, 2.6 * (1.0 - cyc) + 0.2, Color(0.7, 0.95, 1.0, 0.7 * cyc), HHFxParticles.RING)
	_set_light(m, Color(0.6, 0.9, 1.0), 1.5 + 6.0 * k, 8.0)
	_body_glow("eye", Color(0.5, 0.9, 1.0), 4.0 * k)
	for i in _rate("draw", 14.0 + 50.0 * k, dt):
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.5, 3.0)
		add.spawn_swirl({ "centre": m - Vector3(0, 0.0, 0), "radius": r, "angle": a, "spin": 1.5, "pull": r / 0.6, "rise": 0.0,
			"y": m.y + rng.randf_range(-1.2, 1.2), "life": 0.6, "size": 0.08, "size_end": 0.04, "color": Color(0.85, 0.97, 1.0, 1.0),
			"shape": HHFxParticles.STREAK, "streak": 0.04 })


## Rimeslithe's meteor: its shadow grows on the ground (fx_ground shadow
## under the frost) and in the last quarter the ice chunk falls into it.
func _sp_meteor(k: float, _dt: float) -> void:
	_meteor = true
	if k > 0.5:
		_set_light(ctr + Vector3(0, 3.0, 0), Color(0.6, 0.9, 1.0), 3.0 * k, 6.0)


## The pond's swell (H51, "the water map should pulse water every 15 s or
## so"): the water rises in a dome where it comes up, rings run out from it,
## and a crest of spray rolls out to the rim of the disk as it nears.
func _sp_swell(k: float, dt: float) -> void:
	var pulse := 0.9 + 0.1 * sin(age * 6.0)
	add.pin(0, ctr + Vector3(0, 0.1 + 0.5 * k, 0), (0.8 + 2.4 * k) * pulse, Color(0.6, 0.85, 1.0, 0.15 + 0.3 * k), HHFxParticles.DOT)
	mix.pin(0, ctr + Vector3(0, 0.15 + 0.35 * k, 0), 0.6 + 2.2 * k, Color(0.82, 0.93, 1.0, 0.2 + 0.25 * k), HHFxParticles.PUFF)
	var crest := _reach * (0.15 + 0.75 * k)
	for i in _rate("crest", (20.0 + 60.0 * k) * (0.5 + k), dt):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var base := ctr + d * crest
		add.spawn({ "pos": base + Vector3(0, 0.15, 0), "vel": d * 1.2 + Vector3(0, rng.randf_range(1.2, 2.4) * (0.5 + k), 0), "life": 0.5,
			"size": 0.09, "color": Color(0.78, 0.94, 1.0, 0.95), "grav": 9.0, "shape": HHFxParticles.FLAKE })
		if rng.randf() < 0.35:
			mix.spawn({ "pos": base + Vector3(0, 0.2, 0), "vel": d * 1.5 + Vector3(0, 0.4, 0), "life": 0.7, "size": 0.35, "size_end": 0.8,
				"color": Color(0.9, 0.97, 1.0, 0.55), "color_end": Color(0.9, 0.97, 1.0, 0.0), "shape": HHFxParticles.PUFF, "drag": 1.0 })
	for i in _rate("bubble", 10.0 + 30.0 * k, dt):
		add.spawn({ "pos": ctr + _jit(_reach * 0.5) + Vector3(0, 0.05, 0), "vel": Vector3(0, rng.randf_range(0.5, 1.2), 0), "life": 0.4,
			"size": rng.randf_range(0.08, 0.16), "color": Color(0.85, 0.95, 1.0, 0.85), "shape": HHFxParticles.RING })


## The caldera's vents (H51): the ground rumbles (grit hopping), steam hisses
## up thicker and thicker, the scorch glows; then it erupts.
func _sp_vent(k: float, dt: float) -> void:
	for i in _rate("steam", 6.0 + 30.0 * k, dt):
		mix.spawn({ "pos": ctr + _jit(0.5) + Vector3(0, 0.2, 0), "vel": Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(1.5, 3.0) * (0.6 + k), rng.randf_range(-0.3, 0.3)),
			"life": rng.randf_range(1.0, 1.6), "size": 0.3, "size_end": 1.4 + k, "color": Color(0.92, 0.9, 0.88, 0.5 + 0.3 * k), "color_end": Color(0.8, 0.78, 0.76, 0.0),
			"shape": HHFxParticles.PUFF, "drag": 0.6 })
	for i in _rate("grit", (10.0 + 40.0 * k) * _area() * 0.5, dt):
		mix.spawn({ "pos": _pick() + _jit(0.7) + Vector3(0, 0.05, 0), "vel": Vector3(0, rng.randf_range(0.8, 2.0) * (0.5 + k), 0), "life": 0.35, "size": 0.07,
			"color": Color(0.2, 0.15, 0.12, 0.95), "grav": 10.0, "shape": HHFxParticles.FLAKE })
	if k > 0.5:
		for i in _rate("spit", 20.0 * (k - 0.5), dt):
			add.spawn({ "pos": ctr + _jit(0.3) + Vector3(0, 0.3, 0), "vel": Vector3(rng.randf_range(-1, 1), rng.randf_range(3, 6), rng.randf_range(-1, 1)), "life": 0.6,
				"size": 0.1, "color": Color(1.0, 0.75, 0.3, 1.0), "color_end": Color(EMBER_END, 0.0), "grav": 9.0, "shape": HHFxParticles.STREAK, "streak": 0.05 })
	_set_light(ctr + Vector3(0, 0.8, 0), Color(1.0, 0.45, 0.15), 0.5 + 3.0 * k * (0.85 + 0.15 * sin(age * 30.0)), 5.0)


## The cave's rockfall (H51): grit and dust sift down from the ceiling over
## the spot, its shadow grows, and in the last fifth the rock drops into it.
func _sp_rockfall(k: float, dt: float) -> void:
	var top := ctr + Vector3(0, 9.0, 0)
	for i in _rate("sift", 8.0 + 30.0 * k, dt):
		mix.spawn({ "pos": top + _jit(1.4), "vel": Vector3(0, -rng.randf_range(6.0, 9.0), 0), "life": 1.1, "size": 0.06,
			"color": Color(0.3, 0.27, 0.24, 1.0), "grav": 4.0, "shape": HHFxParticles.FLAKE, "streak": 0.02 })
	for i in _rate("dust", 3.0 + 10.0 * k, dt):
		mix.spawn({ "pos": top + _jit(1.2) - Vector3(0, rng.randf_range(0.0, 3.0), 0), "vel": Vector3(0, -rng.randf_range(1.5, 3.0), 0), "life": 1.6,
			"size": 0.4, "size_end": 1.2, "color": Color(0.68, 0.62, 0.55, 0.45), "color_end": Color(0.68, 0.62, 0.55, 0.0), "shape": HHFxParticles.PUFF })
	var fall := clampf((k - 0.78) / 0.22, 0.0, 1.0)
	if fall > 0.0:
		mix.pin(0, ctr + Vector3(0, lerpf(10.0, 0.6, fall * fall), 0), 1.1, Color(0.22, 0.2, 0.19, 1.0), HHFxParticles.SHARD)
		mix.pin(1, ctr + Vector3(0, lerpf(10.0, 0.6, fall * fall) + 0.2, 0), 0.8, Color(0.36, 0.33, 0.3, 1.0), HHFxParticles.SHARD)


## Rimeslithe's mist breath: cold mist leaks from the mouth before it blows.
func _sp_ice_breath(k: float, dt: float) -> void:
	var m := sock("mouth", Vector3(0, 1.7, 5.3))
	add.pin(0, m, 0.3 + 1.0 * k, Color(0.7, 0.95, 1.0, 0.4 + 0.4 * k), HHFxParticles.DOT)
	for i in _rate("breath", 6.0 + 20.0 * k, dt):
		mix.spawn({ "pos": m + _jit(0.2), "vel": _fwd() * rng.randf_range(0.4, 1.4) + Vector3(0, -0.2, 0), "life": 1.4, "size": 0.3, "size_end": 1.2,
			"color": Color(0.9, 0.97, 1.0, 0.55), "color_end": Color(0.9, 0.97, 1.0, 0.0), "shape": HHFxParticles.PUFF, "drag": 0.6 })


## Spirewalker's pollen shake: a yellow-green haze thickening over the cloud,
## violet sparks running along the reeds.
func _sp_pollen(k: float, dt: float) -> void:
	for i in _rate("haze", (3.0 + 18.0 * k) * _area(), dt):
		var q := _pick() + _jit(0.8) + Vector3(0, rng.randf_range(0.3, 2.2), 0)
		mix.spawn({ "pos": q, "vel": Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.05, 0.2), rng.randf_range(-0.3, 0.3)), "life": rng.randf_range(1.6, 2.4),
			"size": 0.9, "size_end": 2.2, "color": Color(0.9, 0.86, 0.3, 0.16 + 0.4 * k), "color_end": Color(0.75, 0.8, 0.35, 0.0), "shape": HHFxParticles.PUFF })
	for i in _rate("pollen", (4.0 + 16.0 * k) * _area(), dt):
		add.spawn({ "pos": _pick() + _jit(0.9) + Vector3(0, rng.randf_range(0.2, 2.0), 0), "vel": Vector3(rng.randf_range(-0.2, 0.2), 0.2, rng.randf_range(-0.2, 0.2)),
			"life": 1.4, "size": 0.06, "color": Color(1.0, 0.95, 0.4, 0.9), "shape": HHFxParticles.FLAKE })
	_reed_sparks(k, dt)


func _sp_spores(k: float, dt: float) -> void:
	for i in _rate("spore", (2.0 + 6.0 * k) * _area(), dt):
		mix.spawn({ "pos": _pick() + _jit(0.8) + Vector3(0, rng.randf_range(0.2, 1.4), 0), "vel": Vector3(0, rng.randf_range(0.1, 0.4), 0), "life": 1.6,
			"size": 0.08, "color": Color(0.45, 0.7, 0.25, 0.9), "shape": HHFxParticles.FLAKE })


func _sp_reed_sparks(k: float, dt: float) -> void:
	_reed_sparks(k, dt)


func _reed_sparks(k: float, dt: float) -> void:
	var r := sock("reeds", Vector3(0, 3.0, -0.1))
	for i in _rate("reed", 10.0 + 40.0 * k, dt):
		var q := r + Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.9, 0.6), rng.randf_range(-1.6, 1.6))
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		add.spawn({ "pos": q, "vel": d * rng.randf_range(2.0, 5.0), "life": 0.12, "size": 0.07, "color": Color(0.85, 0.6, 1.0, 1.0),
			"shape": HHFxParticles.STREAK, "streak": 0.06 })


func _sp_mouth_crackle(k: float, dt: float) -> void:
	var m := sock("mouth", Vector3(0, 0.6, 4.2))
	add.pin(0, m, (0.3 + 1.0 * k) * (0.7 + 0.3 * rng.randf()), Color(0.7, 0.5, 1.0, 0.6 + 0.3 * k), HHFxParticles.DOT)
	for i in _rate("crackle", 20.0 + 50.0 * k, dt):
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		add.spawn({ "pos": m, "vel": d * rng.randf_range(3.0, 7.0), "life": 0.1, "size": 0.06, "color": Color(0.9, 0.8, 1.0, 1.0), "shape": HHFxParticles.STREAK, "streak": 0.05 })
	_reed_sparks(k * 0.6, dt)


func _sp_mouth_smoke(k: float, dt: float) -> void:
	var m := sock("mouth", Vector3(0, 0.6, 4.2))
	add.pin(0, m, 0.3 + 0.9 * k, Color(0.55, 0.25, 1.0, 0.45 + 0.4 * k), HHFxParticles.DOT)
	for i in _rate("dsmoke", 5.0 + 16.0 * k, dt):
		mix.spawn({ "pos": m + _jit(0.2), "vel": Vector3(0, rng.randf_range(0.2, 0.6), 0) + _fwd() * 0.4, "life": 1.4, "size": 0.3, "size_end": 1.0,
			"color": Color(0.12, 0.04, 0.2, 0.65), "color_end": Color(0.1, 0.02, 0.15, 0.0), "shape": HHFxParticles.PUFF })


# ------------------------------------------------------------------ commit

## Contact: the burst. Generic by element, plus the special's own.
func commit() -> void:
	if committed:
		return
	committed = true
	commit_t = 0.0
	p = 1.0
	add.pin(0, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	add.pin(1, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	add.pin(2, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	add.pin(3, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	mix.pin(0, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	mix.pin(1, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	if keep_particles or special in ["surface_ripple", "vortex", "env_swell", "env_vent", "env_rockfall"]:
		_burst("water" if special in ["vortex", "surface_ripple", "env_swell"] else ("" if special == "env_rockfall" else element))
	match special:
		"breath_fire":
			var m := sock("mouth", Vector3(0, 2.7, 4.3))
			var n := 0
			for q in pts:
				if n > 24:
					break
				n += 1
				var to: Vector3 = q + Vector3(0, 0.4, 0)
				add.spawn({ "pos": m, "vel": (to - m) / 0.25, "life": 0.25, "size": 0.35, "size_end": 0.6, "color": Color(1.0, 0.75, 0.3, 1.0),
					"color_end": Color(1.0, 0.35, 0.05, 0.6), "shape": HHFxParticles.STREAK, "streak": 0.03 })
			_burst("fire")
		"charge_lane":
			pass
		"env_swell":
			# the wave breaks: spray thrown up and out from the crest ring
			for i in 48:
				var a := TAU * float(i) / 48.0
				var d := Vector3(cos(a), 0, sin(a))
				add.spawn({ "pos": ctr + d * _reach * 0.7 + Vector3(0, 0.4, 0), "vel": d * rng.randf_range(2.0, 4.0) + Vector3(0, rng.randf_range(3.0, 6.0), 0),
					"life": 0.8, "size": 0.12, "color": Color(0.75, 0.92, 1.0, 1.0), "grav": 12.0, "shape": HHFxParticles.FLAKE })
			add.spawn({ "pos": ctr + Vector3(0, 0.3, 0), "life": 0.4, "size": 1.0, "size_end": _reach * 1.4, "color": Color(0.8, 0.95, 1.0, 0.9), "color_end": Color(0.5, 0.8, 1.0, 0.0), "shape": HHFxParticles.RING })
		"env_vent":
			# the eruption: a column of fire and embers straight up
			for i in 26:
				add.spawn({ "pos": ctr + _jit(0.5) + Vector3(0, 0.3, 0), "vel": Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(7.0, 13.0), rng.randf_range(-1.2, 1.2)),
					"life": rng.randf_range(0.6, 1.0), "size": 0.14, "size_end": 0.06, "color": Color(1.0, 0.8, 0.35, 1.0), "color_end": Color(EMBER_END, 0.0),
					"grav": 9.0, "shape": HHFxParticles.STREAK, "streak": 0.05 })
			for i in 8:
				add.spawn({ "pos": ctr + Vector3(0, 0.6 + 0.6 * i, 0), "vel": Vector3(0, 3.0, 0), "life": 0.5, "size": 1.1 - 0.08 * i, "size_end": 1.5,
					"color": Color(1.0, 0.6, 0.15, 0.8), "color_end": Color(0.9, 0.2, 0.05, 0.0), "shape": HHFxParticles.PUFF })
		"env_rockfall":
			for i in 14:
				mix.spawn({ "pos": ctr + _jit(1.0) + Vector3(0, 0.3, 0), "vel": Vector3(rng.randf_range(-3, 3), rng.randf_range(1.5, 3.5), rng.randf_range(-3, 3)),
					"life": 0.8, "size": 0.12, "color": Color(0.25, 0.22, 0.2, 1.0), "grav": 14.0, "shape": HHFxParticles.SHARD })
		"meteor":
			for i in 40:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.4, 1.4), rng.randf_range(-1, 1)).normalized()
				add.spawn({ "pos": ctr + Vector3(0, 0.6, 0), "vel": d * rng.randf_range(5.0, 11.0), "life": 0.8, "size": 0.2, "size_end": 0.1,
					"color": Color(0.8, 0.97, 1.0, 1.0), "grav": 14.0, "shape": HHFxParticles.SHARD, "streak": 0.03 })
			add.spawn({ "pos": ctr + Vector3(0, 0.4, 0), "life": 0.35, "size": 1.0, "size_end": _reach * 1.3, "color": Color(0.85, 0.97, 1.0, 0.9), "color_end": Color(0.6, 0.9, 1.0, 0.0), "shape": HHFxParticles.RING })
		"beam_charge":
			var m := sock("mouth", Vector3(0, 1.7, 5.3))
			var far := m
			for q in pts:
				if (q as Vector3).distance_to(m) > far.distance_to(m):
					far = q
			for i in 12:
				var t := float(i) / 11.0
				add.spawn({ "pos": m.lerp(far + Vector3(0, 0.6, 0), t), "vel": (far - m).normalized() * 0.5, "life": 0.35, "size": 0.7, "size_end": 0.2,
					"color": Color(0.85, 0.97, 1.0, 1.0), "shape": HHFxParticles.DOT })
	light.visible = false


## The element's landing burst over the hexes (a cheap capped sample).
func _burst(el: String) -> void:
	var col: Color = COL.get(el, COL[""])
	var n := mini(pts.size(), 18)
	var picks: Array = pts.duplicate()
	picks.shuffle()
	for j in n:
		var q: Vector3 = picks[j]
		match el:
			"fire":
				add.spawn({ "pos": q + Vector3(0, 0.4, 0), "vel": Vector3(0, rng.randf_range(1.5, 3.0), 0), "life": 0.5, "size": 0.6, "size_end": 1.1,
					"color": Color(1.0, 0.65, 0.2, 0.85), "color_end": Color(0.9, 0.2, 0.05, 0.0), "shape": HHFxParticles.PUFF })
				for i in 3:
					add.spawn({ "pos": q + Vector3(0, 0.3, 0), "vel": Vector3(rng.randf_range(-2, 2), rng.randf_range(3, 6), rng.randf_range(-2, 2)), "life": 0.7,
						"size": 0.08, "color": Color(1.0, 0.8, 0.4, 1.0), "color_end": Color(EMBER_END, 0.0), "grav": 6.0, "shape": HHFxParticles.STREAK, "streak": 0.05 })
			"ice":
				for i in 3:
					add.spawn({ "pos": q + Vector3(0, 0.3, 0), "vel": Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(2.5, 5.5), rng.randf_range(-2.5, 2.5)), "life": 0.6,
						"size": 0.14, "size_end": 0.06, "color": Color(0.8, 0.97, 1.0, 1.0), "grav": 12.0, "shape": HHFxParticles.SHARD, "streak": 0.03 })
				mix.spawn({ "pos": q + Vector3(0, 0.3, 0), "vel": Vector3(0, 0.6, 0), "life": 0.9, "size": 0.5, "size_end": 1.3,
					"color": Color(0.92, 0.97, 1.0, 0.6), "color_end": Color(0.92, 0.97, 1.0, 0.0), "shape": HHFxParticles.PUFF })
			"water":
				for i in 4:
					add.spawn({ "pos": q + Vector3(0, 0.1, 0), "vel": Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(3, 5.5), rng.randf_range(-1.5, 1.5)), "life": 0.7,
						"size": 0.09, "color": Color(0.7, 0.9, 1.0, 0.95), "grav": 12.0, "shape": HHFxParticles.FLAKE })
			"thunder":
				add.spawn({ "pos": q + Vector3(0, 0.6, 0), "life": 0.16, "size": 0.9, "size_end": 1.4, "color": Color(0.85, 0.7, 1.0, 0.9), "shape": HHFxParticles.SPARK })
			"dark":
				mix.spawn({ "pos": q + Vector3(0, 0.3, 0), "vel": Vector3(0, 0.8, 0), "life": 0.9, "size": 0.5, "size_end": 1.2,
					"color": Color(0.12, 0.03, 0.2, 0.75), "color_end": Color(0.1, 0.0, 0.15, 0.0), "shape": HHFxParticles.PUFF })
			"light":
				add.spawn({ "pos": q + Vector3(0, 1.0, 0), "vel": Vector3(0, 3.0, 0), "life": 0.4, "size": 0.35, "color": Color(1.0, 0.95, 0.7, 0.9),
					"shape": HHFxParticles.STREAK, "streak": 0.12 })
			"wind":
				var d := (q - ctr)
				d.y = 0.0
				add.spawn({ "pos": q + Vector3(0, 0.3, 0), "vel": d.normalized() * 6.0 + Vector3(0, 0.5, 0), "life": 0.35, "size": 0.08,
					"color": Color(0.8, 1.0, 0.85, 0.9), "shape": HHFxParticles.STREAK, "streak": 0.06 })
			_:
				mix.spawn({ "pos": q + Vector3(0, 0.25, 0), "vel": Vector3(rng.randf_range(-0.8, 0.8), 0.9, rng.randf_range(-0.8, 0.8)), "life": 0.9, "size": 0.45, "size_end": 1.3,
					"color": Color(DUST, 0.7), "color_end": Color(DUST, 0.0), "shape": HHFxParticles.PUFF, "drag": 1.2 })
				for i in 2:
					mix.spawn({ "pos": q + Vector3(0, 0.1, 0), "vel": Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(2, 4), rng.randf_range(-1.5, 1.5)), "life": 0.6,
						"size": 0.07, "color": Color(0.22, 0.18, 0.13, 1.0), "grav": 12.0, "shape": HHFxParticles.FLAKE })
	if el in ["thunder", "light", "fire"]:
		add.spawn({ "pos": ctr + Vector3(0, 0.8, 0), "life": 0.14, "size": 1.2, "size_end": 2.2, "color": Color(col.lerp(Color.WHITE, 0.5), 0.7), "shape": HHFxParticles.DOT })


func _after(_dt: float) -> void:
	if special == "charge_lane" and not members.is_empty():
		# the run: keep the lane alive (and kicking) until the body has passed
		_sp_charge(1.0, _dt)


# ------------------------------------------------------------------ ground

static func ground_material(mode_name: String) -> ShaderMaterial:
	if _ground_mats.has(mode_name):
		return _ground_mats[mode_name]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fx_ground.gdshader")
	m.set_shader_parameter("mode", int(GROUND_MODE.get(mode_name, 0)))
	var tint := Color(0.75, 0.65, 0.5)
	var tint2 := Color(1, 1, 1)
	match mode_name:
		"fire":
			tint = Color(1.0, 0.38, 0.08)
			tint2 = Color(1.0, 0.82, 0.4)
		"ice": tint = Color(0.7, 0.92, 1.0)
		"water": tint = Color(0.25, 0.45, 0.7)
		"thunder": tint = Color(0.6, 0.35, 1.0)
		"wind": tint = Color(0.5, 0.9, 0.55)
		"dark": tint = Color(0.5, 0.2, 0.9)
		"light": tint = Color(1.0, 0.82, 0.3)
		"lane":
			tint = Color(0.97, 0.9, 0.75)
			tint2 = Color(0.45, 0.35, 0.24)
		"lane_fire":
			tint = Color(1.0, 0.62, 0.2)
			tint2 = Color(0.5, 0.18, 0.05)
		"": tint = Color(0.62, 0.52, 0.38)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tint2", tint2)
	m.render_priority = 1
	_ground_mats[mode_name] = m
	return m


func _build_ground() -> void:
	_modes = []
	match special:
		"charge_lane": _modes = ["lane_fire" if element == "fire" else "lane"]
		"surface_ripple", "vortex", "env_swell": _modes = ["water"]
		"meteor", "landing_shadow": _modes = ["shadow"]
		"env_rockfall": _modes = ["shadow", ""]
	if keep_ground and not special in ["surface_ripple", "vortex", "env_swell", "env_rockfall"]:
		_modes.append(element)
	var have := {}
	for g in _ground:
		have[g.hex] = true
	var step := maxi(1, int(ceil(float(hexes.size()) / float(GROUND_CAP))))
	var arena: HHArena = layer.arena
	for i in range(0, hexes.size(), step):
		var h: Vector2i = hexes[i]
		if have.has(h):
			continue
		var g: Dictionary = _ground_pool.pop_back() if not _ground_pool.is_empty() else { "mis": [] }
		g.hex = h
		g.end_at = -1.0
		g.seed = rng.randf()
		var mis: Array = g.mis
		while mis.size() < _modes.size():
			var mi := MeshInstance3D.new()
			mi.mesh = HHTileFX.hex_mesh()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mis.append(mi)
		for j in mis.size():
			var mi: MeshInstance3D = mis[j]
			mi.visible = j < _modes.size()
			if j < _modes.size():
				mi.material_override = ground_material(str(_modes[j]))
				mi.position = arena.surface(h) + Vector3(0, GROUND_LIFT + 0.003 * j, 0)
		_ground.append(g)


func _push_ground() -> void:
	for g in _ground:
		var ck := 0.0
		if g.end_at >= 0.0:
			ck = clampf((age - float(g.end_at)) / COMMIT_S, 0.0, 1.0)
		elif committed and members.is_empty():
			ck = clampf(commit_t / COMMIT_S, 0.0, 1.0)
		var mis: Array = g.mis
		for j in mini(mis.size(), _modes.size()):
			var mi: MeshInstance3D = mis[j]
			var md := str(_modes[j])
			var gp := p
			if md == "ice" and special == "fist_frost":
				gp = 0.62 + 0.38 * p                    # frost from the knuckles the whole wind-up
			mi.set_instance_shader_parameter("progress", gp)
			mi.set_instance_shader_parameter("commit", ck)
			mi.set_instance_shader_parameter("origin", Vector4(_origin.x, _origin.z, _reach, float(g.seed)))
			mi.set_instance_shader_parameter("dir", Vector4(_dir.x, _dir.z, 0, 0))
			mi.visible = ck < 1.0


# ------------------------------------------------------------------ shards (ice)

static func _shard_mesh_get() -> ArrayMesh:
	if _shard_mesh == null:
		# a six-sided crystal: a short prism capped by a long point, base at y 0
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var r := 0.16
		var ring0: Array = []
		var ring1: Array = []
		for i in 6:
			var a := TAU * float(i) / 6.0
			ring0.append(Vector3(cos(a) * r, -0.15, sin(a) * r))
			ring1.append(Vector3(cos(a) * r * 0.9, 0.45, sin(a) * r * 0.9))
		var tip := Vector3(0.02, 1.0, 0.0)
		for i in 6:
			var j := (i + 1) % 6
			for v in [ring0[i], ring1[i], ring1[j], ring0[i], ring1[j], ring0[j], ring1[i], tip, ring1[j]]:
				st.add_vertex(v)
		st.generate_normals()
		_shard_mesh = st.commit()
	return _shard_mesh


static func _shard_mat_get() -> StandardMaterial3D:
	if _shard_mat == null:
		_shard_mat = StandardMaterial3D.new()
		_shard_mat.albedo_color = Color(0.78, 0.94, 1.0)
		_shard_mat.emission_enabled = true
		_shard_mat.emission = Color(0.45, 0.8, 1.0)
		_shard_mat.emission_energy_multiplier = 0.7
		_shard_mat.roughness = 0.15
		_shard_mat.metallic_specular = 0.9
		_shard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shard_mat


func _build_shards() -> void:
	var want := mini(SHARD_CAP, maxi(4, int(pts.size() * 1.4)))
	while _shard_data.size() < want:
		var q := _pick() + _jit(0.75)
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.55))
		var dist := Vector2(q.x - _origin.x, q.z - _origin.z).length() / maxf(_reach, 1.0)
		_shard_data.append({ "pos": q, "basis": tilt * Basis(Vector3.UP, rng.randf() * TAU), "size": rng.randf_range(0.8, 1.7),
			"delay": clampf(dist, 0.0, 1.0) * 0.7 + rng.randf() * 0.3 })


func _push_shards() -> void:
	var mm := _shards.multimesh
	if _shard_data.is_empty() and not _meteor:
		mm.visible_instance_count = 0
		return
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var k := 0
	var frost := smoothstep(0.6, 1.0, p)
	for d in _shard_data:
		var g := clampf((frost - float(d.delay) * 0.6) / 0.4, 0.0, 1.0)
		g = g * g * (3.0 - 2.0 * g)
		var s := float(d.size) * g
		var sink := 0.0
		if committed:
			var t := commit_t
			s = float(d.size) * (1.0 + 0.3 * sin(clampf(t / 0.15, 0.0, 1.0) * PI))
			if t > 0.35:
				var f := clampf((t - 0.35) / 0.4, 0.0, 1.0)
				s *= 1.0 - f
				sink = f * 0.4
		if s < 0.01:
			continue
		mm.set_instance_transform(k, inv * Transform3D((d.basis as Basis).scaled(Vector3(s, s, s)), (d.pos as Vector3) - Vector3(0, sink, 0)))
		k += 1
	if _meteor and not committed:
		var fall := clampf((p - 0.5) / 0.5, 0.0, 1.0)
		if fall > 0.0:
			var y := lerpf(14.0, 0.6, fall * fall)
			var b := Basis(Vector3(1, 0, 0.3).normalized(), age * 3.0) * Basis.from_scale(Vector3(3.2, 3.2, 3.2))
			mm.set_instance_transform(k, inv * Transform3D(b, ctr + Vector3(0, y, 0)))
			k += 1
	mm.visible_instance_count = k


# ------------------------------------------------------------------ shimmer (breath)

static func _quad_get() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad


static func _shimmer_mat_get() -> ShaderMaterial:
	if _shimmer_mat == null:
		_shimmer_mat = ShaderMaterial.new()
		_shimmer_mat.shader = load("res://shaders/fx_shimmer.gdshader")
	return _shimmer_mat


func _build_shimmer() -> void:
	var o := _owner_pos()
	var sorted: Array = pts.duplicate()
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(o) < b.distance_squared_to(o))
	_shimmer_pts = []
	var step := maxi(1, int(ceil(float(sorted.size()) / float(SHIMMER_CAP))))
	for i in range(0, sorted.size(), step):
		_shimmer_pts.append(sorted[i])


func _push_shimmer() -> void:
	var mm := _shimmer.multimesh
	if _shimmer_pts.is_empty():
		mm.visible_instance_count = 0
		return
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var k := 0
	var n := _shimmer_pts.size()
	for i in n:
		var reveal := clampf((p - float(i) / float(n) * 0.8) / 0.2, 0.0, 1.0)
		if committed:
			reveal *= 1.0 - clampf(commit_t / 0.4, 0.0, 1.0)
		if reveal <= 0.01:
			continue
		var q: Vector3 = _shimmer_pts[i]
		var h := 1.4 + 1.6 * reveal
		mm.set_instance_transform(k, inv * Transform3D(Basis.from_scale(Vector3(1.8, h, 1.0)), q + Vector3(0, 0.05, 0)))
		mm.set_instance_custom_data(k, Color(reveal * (0.5 + 0.5 * p), 0, 0, 0))
		k += 1
	mm.visible_instance_count = k
