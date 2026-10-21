class_name HHReactionFx
extends Node3D
## Lane EL (spec sections 2-3): the element cash-ins on the ground. View only,
## never writes the sim. Two halves:
##   crystals   continuous from state: every HHCharge entry holding a crystal
##              draws a hex prism. The ice shell's height is its ice level
##              (1-3); the core inside is tinted by the element it stores and
##              stands as tall as that element's tier, so "fire 2, ice 1"
##              reads as a short ice prism with a two-thirds red core
##   one-shots  from sim events: shatter (shards + ring), swirl (an inward
##              vortex over the pull radius), overheat / geyser / glint / flux
##              (the tier-3 bursts), steam (a rising plume), eclipse (a dark
##              and a gold ring collapsing), a crystal forming (a frost flake
##              puff). Rings, flashes, sparks and numbers go through the
##              fx layer's HHSkillFx (`skill`) so the look is one language.
## Everything is sprites on two HHFxParticles systems and pooled prisms:
## cheap, and it runs on the Compatibility renderer (web).

const LIFT := 0.04
const SHELL_H := [0.0, 0.7, 1.05, 1.4]        # prism height by ice level
const CORE_H := [0.0, 0.3, 0.55, 0.85]         # core height by stored tier
const ICE := Color(0.75, 0.95, 1.0)
const STEAM := Color(0.93, 0.95, 0.97)

var arena: HHArena
var skill: HHSkillFx                            # the fx layer's: ring(), flash(), burst(), number()
var enabled := true
var add: HHFxParticles
var mix: HHFxParticles
var rng := RandomNumberGenerator.new()
var _prisms := {}                               # hex -> { shell, core, key }
var _pool: Array = []
var _shell_mats := {}
var _core_mats := {}
static var _shell_mesh: CylinderMesh
static var _core_mesh: CylinderMesh


func setup(a: HHArena) -> void:
	arena = a
	rng.seed = 3601
	add = HHFxParticles.new(240, true)
	add.name = "Add"
	add_child(add)
	mix = HHFxParticles.new(140, false)
	mix.name = "Mix"
	add_child(mix)


## The element a crystal shows: its stronger axis (fire / water first on a tie), or "" (bare ice).
static func crystal_element(e: Dictionary) -> String:
	var h := int(e.get("h", 0))
	var v := int(e.get("v", 0))
	if h == 0 and v == 0:
		return ""
	if absi(h) >= absi(v):
		return "fire" if h > 0 else "water"
	return "light" if v > 0 else "dark"


## Per frame: prisms for the live crystals, particles advance.
func sync(sim: HHSim, delta: float) -> void:
	if not enabled or sim == null:
		return
	var live := {}
	for hex in sim.charge.entries:
		var e: Dictionary = sim.charge.entries[hex]
		var ice := int(e.get("crystal", 0))
		if ice <= 0:
			continue
		live[hex] = true
		var el := crystal_element(e)
		var tier := maxi(absi(int(e.get("h", 0))), absi(int(e.get("v", 0))))
		var key := "%s|%d|%d" % [el, ice, tier]
		var p: Dictionary = _prisms.get(hex, {})
		if p.is_empty():
			p = _acquire()
			_prisms[hex] = p
			p.key = ""
			p.grow = 0.0
		if str(p.key) != key:
			p.key = key
			_dress(p, hex, el, clampi(ice, 1, 3), clampi(tier, 0, 3))
		if float(p.grow) < 1.0:
			p.grow = minf(1.0, float(p.grow) + delta * 6.0)
			_place(p, 0.35 + 0.65 * (1.0 - pow(1.0 - float(p.grow), 3.0)))
	for hex in _prisms.keys():
		if live.has(hex):
			continue
		var p: Dictionary = _prisms[hex]
		_prisms.erase(hex)
		(p.shell as Node3D).visible = false
		(p.core as Node3D).visible = false
		_pool.append(p)
	add.step(delta)
	mix.step(delta)


func crystal_count() -> int:
	return _prisms.size()


func _acquire() -> Dictionary:
	if not _pool.is_empty():
		return _pool.pop_back()
	if _shell_mesh == null:
		_shell_mesh = CylinderMesh.new()
		_shell_mesh.radial_segments = 6
		_shell_mesh.rings = 1
		_shell_mesh.top_radius = 0.5
		_shell_mesh.bottom_radius = 0.66
		_shell_mesh.height = 1.0
		_core_mesh = CylinderMesh.new()
		_core_mesh.radial_segments = 6
		_core_mesh.rings = 1
		_core_mesh.top_radius = 0.22
		_core_mesh.bottom_radius = 0.34
		_core_mesh.height = 1.0
	var shell := MeshInstance3D.new()
	shell.mesh = _shell_mesh
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	var core := MeshInstance3D.new()
	core.mesh = _core_mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	return { "shell": shell, "core": core, "key": "", "grow": 0.0 }


## Size, colour and place one prism (the mesh is 1 m tall, centred: scaled and lifted).
func _dress(p: Dictionary, hex: Vector2i, el: String, ice: int, tier: int) -> void:
	var sh: MeshInstance3D = p.shell
	var co: MeshInstance3D = p.core
	p.base = arena.surface(hex) + Vector3(0, LIFT, 0)
	p.hs = float(SHELL_H[ice])
	p.hc = float(CORE_H[tier]) if el != "" else 0.0
	sh.visible = true
	sh.material_override = _shell_mat(el)
	co.visible = float(p.hc) > 0.0
	if co.visible:
		co.material_override = _core_mat(el)
	_place(p, 1.0)


## The prism at grow `s` (0..1 of its height): flats turned to the hex's
## flats (pointy-top grid), standing on the ground.
func _place(p: Dictionary, s: float) -> void:
	var rot := Basis(Vector3.UP, deg_to_rad(30.0))
	var base: Vector3 = p.base
	var hs := float(p.hs) * s
	var hc := float(p.hc) * s
	(p.shell as Node3D).transform = Transform3D(rot.scaled(Vector3(1.0, maxf(hs, 0.01), 1.0)), base + Vector3(0, hs * 0.5, 0))
	(p.core as Node3D).transform = Transform3D(rot.scaled(Vector3(1.0, maxf(hc, 0.01), 1.0)), base + Vector3(0, hc * 0.5, 0))


func _shell_mat(el: String) -> StandardMaterial3D:
	if _shell_mats.has(el):
		return _shell_mats[el]
	var m := StandardMaterial3D.new()
	var tint := ICE.lerp(HHLook.element_color(el), 0.35) if el != "" else ICE
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.62)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.12
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = ICE.lerp(HHLook.glow_color(el), 0.25) if el != "" else ICE
	m.emission_energy_multiplier = 0.35
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_shell_mats[el] = m
	return m


func _core_mat(el: String) -> StandardMaterial3D:
	if _core_mats.has(el):
		return _core_mats[el]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var g := HHLook.glow_color(el)
	if el == "dark":
		g = Color(0.42, 0.22, 0.7)                     # dark's glow is near black: lift it so the core reads inside the ice
	m.albedo_color = g
	_core_mats[el] = m
	return m


# ------------------------------------------------------------------ one-shots

func on_event(e: Dictionary, sim: HHSim) -> void:
	if not enabled or sim == null:
		return
	var t := str(e.get("type", ""))
	if not t in ["crystal", "shatter", "swirl", "overheat", "geyser", "glint", "flux", "steam", "eclipse"]:
		return
	if not e.has("hex") or not sim.arena.exists(e.hex):
		return
	var at := sim.arena.surface(e.hex)
	match t:
		"crystal":
			_puff(at, ICE, 8, HHFxParticles.FLAKE, 1.4)
		"shatter":
			_shatter(at, e)
		"swirl":
			_swirl(sim, e)
		"overheat":
			_column(at, HHLook.glow_color("fire"), 14, 8.0, HHFxParticles.STREAK)
			_ring(at, HHLook.glow_color("fire"), 1.9, 0.4)
		"geyser":
			_geyser(at)
		"glint":
			_glint(at)
		"flux":
			_flux(at)
		"steam":
			_steam(at, int(e.get("consumed", 3)))
		"eclipse":
			_eclipse(at)


func _ring(at: Vector3, col: Color, radius: float, life: float) -> void:
	if skill != null:
		skill.ring(at, col, radius, life)


func _flash(at: Vector3, col: Color, size: float) -> void:
	if skill != null:
		skill.flash(at, col, size)


func _puff(at: Vector3, col: Color, n: int, shape: int, scale: float) -> void:
	for i in n:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		add.spawn({ "pos": at + Vector3(0, 0.4, 0), "vel": d * rng.randf_range(1.5, 3.0) * scale, "life": rng.randf_range(0.35, 0.6),
			"size": 0.14 * scale, "size_end": 0.04, "color": Color(col, 1.0), "color_end": Color(col, 0.0), "drag": 3.0, "shape": shape })


## Shards fly out of the hex (ice white and the stored element), a ring
## sweeps the neighbours the fragments splash, a flash at the core.
func _shatter(at: Vector3, e: Dictionary) -> void:
	var mix_el: Dictionary = e.get("mix", {})
	var el := ""
	var best := 0
	for k in ["fire", "water", "light", "dark"]:
		if int(mix_el.get(k, 0)) > best:
			best = int(mix_el[k])
			el = k
	var col := HHLook.glow_color(el) if el != "" else ICE
	if el == "dark":
		col = Color(0.5, 0.3, 0.8)
	for i in 26:
		var a := TAU * float(i) / 26.0 + rng.randf() * 0.2
		var d := Vector3(cos(a), rng.randf_range(0.3, 1.1), sin(a)).normalized()
		add.spawn({ "pos": at + Vector3(0, 0.6, 0), "vel": d * rng.randf_range(5.0, 9.0), "life": rng.randf_range(0.35, 0.6),
			"size": 0.22, "size_end": 0.08, "color": Color(ICE if i % 2 == 0 else col, 1.0), "color_end": Color(ICE, 0.0),
			"grav": 9.0, "drag": 1.5, "shape": HHFxParticles.SHARD })
	_flash(at + Vector3(0, 0.8, 0), ICE, 1.8)
	_ring(at, ICE, 1.9, 0.35)
	_ring(at, col, 1.3, 0.3)


## The vortex: streaks orbit in from the pull radius to the centre, tinted by
## the charge it carries; the landing hex flashes.
func _swirl(sim: HHSim, e: Dictionary) -> void:
	var centre := sim.arena.surface(e.hex)
	var radius := float(e.get("radius", 2)) * 1.6 + 0.6
	var wind := HHLook.glow_color("wind")
	for i in 40:
		var a := TAU * float(i) / 40.0
		add.spawn_swirl({ "centre": centre, "radius": radius * rng.randf_range(0.75, 1.05), "angle": a, "spin": 4.5, "pull": radius / 0.55,
			"rise": 0.6, "y": 0.25 + rng.randf() * 0.4, "life": 0.55, "size": 0.12, "size_end": 0.05,
			"color": Color(wind.lerp(Color.WHITE, 0.35), 0.95), "color_end": Color(wind, 0.0), "shape": HHFxParticles.STREAK, "streak": 0.05 })
	for h in e.get("pulled", []):
		if not sim.arena.exists(h):
			continue
		var q := sim.arena.surface(h)
		var el := str((e.get("pulled_el", {}) as Dictionary).get(h, ""))
		var c := HHLook.glow_color(el) if el != "" else wind
		var d := centre - q
		add.spawn({ "pos": q + Vector3(0, 0.3, 0), "vel": d / 0.45 + Vector3(0, 0.6, 0), "life": 0.45, "size": 0.2, "size_end": 0.1,
			"color": Color(c, 1.0), "color_end": Color(c, 0.2), "shape": HHFxParticles.DOT })
	var land := sim.arena.surface(e.get("landing", e.hex)) if sim.arena.exists(e.get("landing", e.hex)) else centre
	_ring(centre, wind, radius, 0.5)
	_flash(land + Vector3(0, 0.6, 0), wind, 1.2)


func _column(at: Vector3, col: Color, n: int, speed: float, shape: int) -> void:
	for i in n:
		add.spawn({ "pos": at + Vector3(rng.randf_range(-0.35, 0.35), 0.2, rng.randf_range(-0.35, 0.35)), "vel": Vector3(rng.randf_range(-0.8, 0.8), speed * rng.randf_range(0.8, 1.2), rng.randf_range(-0.8, 0.8)),
			"life": rng.randf_range(0.45, 0.7), "size": 0.16, "size_end": 0.06, "color": Color(col.lerp(Color.WHITE, 0.3), 1.0), "color_end": Color(col, 0.0),
			"grav": 4.0, "shape": shape, "streak": 0.06 })


## Water erupts upward: a tall white-cyan column of spray (streaks and puffs
## stacked to ~4 m), droplets raining back round the ring.
func _geyser(at: Vector3) -> void:
	var col := HHLook.glow_color("water")
	var spray := Color(0.8, 0.95, 1.0)
	for i in 34:
		add.spawn({ "pos": at + Vector3(rng.randf_range(-0.3, 0.3), 0.2, rng.randf_range(-0.3, 0.3)), "vel": Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(11.0, 16.0), rng.randf_range(-0.6, 0.6)),
			"life": rng.randf_range(0.5, 0.75), "size": 0.26, "size_end": 0.1, "color": Color(spray, 1.0), "color_end": Color(col, 0.0),
			"grav": 9.0, "shape": HHFxParticles.STREAK, "streak": 0.07 })
	for i in 10:
		mix.spawn({ "pos": at + Vector3(rng.randf_range(-0.25, 0.25), 0.3 + 0.4 * i, rng.randf_range(-0.25, 0.25)), "vel": Vector3(0, rng.randf_range(2.5, 4.0), 0), "life": 0.9,
			"size": 0.55, "size_end": 1.1, "color": Color(0.88, 0.96, 1.0, 0.75), "color_end": Color(0.88, 0.96, 1.0, 0.0), "drag": 1.0, "shape": HHFxParticles.PUFF })
	for i in 22:
		var a := TAU * float(i) / 22.0
		var d := Vector3(cos(a), 0, sin(a))
		add.spawn({ "pos": at + Vector3(0, 3.8, 0), "vel": d * rng.randf_range(2.0, 3.8) + Vector3(0, 2.0, 0), "life": 0.9, "size": 0.16, "size_end": 0.08,
			"color": Color(spray, 1.0), "color_end": Color(col, 0.0), "grav": 12.0, "shape": HHFxParticles.DOT })
	_ring(at, spray, 1.9, 0.45)
	_flash(at + Vector3(0, 0.6, 0), spray, 1.6)


## Light flares: a shaft of gold streaks straight up, star sparks out, a flash.
func _glint(at: Vector3) -> void:
	var col := HHLook.glow_color("light")
	for i in 30:
		var a := TAU * float(i) / 30.0
		add.spawn({ "pos": at + Vector3(0, 1.0, 0), "vel": Vector3(cos(a), rng.randf_range(-0.2, 0.6), sin(a)) * rng.randf_range(4.0, 7.0), "life": 0.45,
			"size": 0.32, "size_end": 0.06, "color": Color(1, 1, 0.85, 1.0), "color_end": Color(col, 0.0), "drag": 2.5, "shape": HHFxParticles.SPARK })
	for i in 16:
		add.spawn({ "pos": at + Vector3(rng.randf_range(-0.3, 0.3), 0.2, rng.randf_range(-0.3, 0.3)), "vel": Vector3(0, rng.randf_range(9.0, 14.0), 0), "life": 0.45,
			"size": 0.22, "size_end": 0.08, "color": Color(1, 0.98, 0.8, 1.0), "color_end": Color(col, 0.0), "shape": HHFxParticles.STREAK, "streak": 0.08 })
	_flash(at + Vector3(0, 1.2, 0), col, 3.2)
	_ring(at, col, 1.9, 0.45)


## Dark collapses inward: violet motes spiral into the hex over a dark
## smoke column, a violet ring (the monster is left vulnerable).
func _flux(at: Vector3) -> void:
	var col := Color(0.62, 0.36, 1.0)
	for i in 36:
		add.spawn_swirl({ "centre": at, "radius": 2.4, "angle": TAU * float(i) / 36.0, "spin": -5.0, "pull": 3.8, "rise": 1.6, "y": 0.2 + 0.03 * i,
			"life": 0.65, "size": 0.26, "size_end": 0.08, "color": Color(col, 1.0), "color_end": Color(0.3, 0.12, 0.5, 0.0), "shape": HHFxParticles.DOT })
	for i in 8:
		mix.spawn({ "pos": at + Vector3(rng.randf_range(-0.3, 0.3), 0.3 + 0.3 * i, rng.randf_range(-0.3, 0.3)), "vel": Vector3(0, 1.4, 0), "life": 1.0, "size": 0.7, "size_end": 1.5,
			"color": Color(0.18, 0.08, 0.3, 0.75), "color_end": Color(0.18, 0.08, 0.3, 0.0), "shape": HHFxParticles.PUFF })
	_flash(at + Vector3(0, 1.0, 0), col, 2.2)
	_ring(at, col, 1.9, 0.5)


## A white plume that rises 3-5 m and spreads; bigger with more charge
## consumed. A hot flash of orange streaks at its foot.
func _steam(at: Vector3, consumed: int) -> void:
	var n := 14 + 3 * clampi(consumed, 2, 6)
	for i in n:
		mix.spawn({ "pos": at + Vector3(rng.randf_range(-0.6, 0.6), 0.3 + rng.randf() * 0.6, rng.randf_range(-0.6, 0.6)), "vel": Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(2.4, 4.2), rng.randf_range(-0.5, 0.5)),
			"life": rng.randf_range(1.3, 2.0), "size": 0.7, "size_end": 2.4, "color": Color(STEAM, 0.8), "color_end": Color(STEAM, 0.0), "drag": 0.7, "shape": HHFxParticles.PUFF })
	for i in 14:
		add.spawn({ "pos": at + Vector3(0, 0.4, 0), "vel": Vector3(rng.randf_range(-3, 3), rng.randf_range(4, 7), rng.randf_range(-3, 3)), "life": 0.4, "size": 0.14,
			"color": Color(1, 0.75, 0.5, 1.0), "color_end": Color(1, 0.9, 0.8, 0.0), "drag": 2.0, "shape": HHFxParticles.STREAK, "streak": 0.05 })
	_ring(at, STEAM, 1.9, 0.5)


## Light meets dark: a gold ring and a violet ring, dark puffs and gold sparks.
func _eclipse(at: Vector3) -> void:
	var gold := HHLook.glow_color("light")
	var vio := Color(0.45, 0.25, 0.75)
	_ring(at, gold, 2.2, 0.5)
	_ring(at, vio, 1.5, 0.6)
	for i in 6:
		mix.spawn({ "pos": at + Vector3(0, 0.5, 0), "vel": Vector3(rng.randf_range(-1, 1), 1.0, rng.randf_range(-1, 1)), "life": 1.0, "size": 0.7, "size_end": 1.6,
			"color": Color(0.1, 0.05, 0.16, 0.65), "color_end": Color(0.1, 0.05, 0.16, 0.0), "shape": HHFxParticles.PUFF })
	for i in 18:
		var a := TAU * float(i) / 18.0
		add.spawn({ "pos": at + Vector3(cos(a) * 2.0, 0.8, sin(a) * 2.0), "vel": Vector3(-cos(a), 0.3, -sin(a)) * 4.0, "life": 0.45, "size": 0.16, "size_end": 0.05,
			"color": Color(gold, 1.0), "color_end": Color(vio, 0.0), "shape": HHFxParticles.SPARK })
	_flash(at + Vector3(0, 1.0, 0), gold.lerp(vio, 0.5), 2.0)
