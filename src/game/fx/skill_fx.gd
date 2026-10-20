class_name HHSkillFx
extends Node3D
## Lane FX (H706): the hunter's wind-ups and impacts. Continuous from state
## (the player unit's `windup { left, total, kind }`): the element builds at
## the weapon hand (a glow, motes drawn in, a light). One-shots from sim
## events: strike (a burst + a short flash at the blow, small enough to stay
## camera-friendly), cast (a flash at the hand), pierce / energized_shot /
## daggerleap (streaks down the line), eruption / arrowstorm (the big ring
## burst), flourish / knifedance pulses / upgrade echoes (smaller rings).

const RING_S := 0.55              ## big ring life (s)
const FLASH := { "basic": 0.55, "pierce": 1.0, "energized": 1.0, "flourish": 0.9 }

var layer: Node                   ## HHFxLayer
var add: HHFxParticles
var mix: HHFxParticles
var light: OmniLight3D
var rng := RandomNumberGenerator.new()
var rings: Array = []             # [{ mi, t, life, size }]
var _ring_pool: Array = []
var _acc := 0.0
var numbers: Array = []           # [{ label, t, life, from }] floating damage numbers
var _num_pool: Array = []
const NUMBER_S := 1.1

static var _ring_mat: ShaderMaterial
static var _plane: PlaneMesh


func _init() -> void:
	add = HHFxParticles.new(260, true)
	add_child(add)
	mix = HHFxParticles.new(80, false)
	add_child(mix)
	light = OmniLight3D.new()
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	rng.seed = 77


static func element_col(el: String) -> Color:
	return HHTelegraphFx.COL.get(el, Color(1.0, 0.95, 0.8))


## The weapon hand of the player in world space.
func hand(u: Dictionary) -> Vector3:
	var body: Node = layer.player_body if layer != null else null
	var local := Vector3(-0.35, 1.25, 0.35)
	if body != null and body.has_method("socket_pos"):
		var sname := "offhand_l" if str(u.get("weapon", "")) == "bow" else "weapon_r"
		if body.has_method("socket") and body.call("socket", sname) != null:
			local = body.call("socket_pos", sname)
	return Transform3D(Basis(Vector3.UP, float(u.get("facing", 0.0))), u.pos) * local


func update(sim: HHSim, player_id: String, delta: float) -> void:
	var u := sim.unit(player_id)
	add.pin(0, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	add.pin(1, Vector3.ZERO, 0.0, Color.TRANSPARENT)
	light.visible = false
	if not u.is_empty() and sim.alive(u):
		var w: Dictionary = u.get("windup", {})
		var kind := str(w.get("kind", ""))
		if not w.is_empty() and kind != "potion":
			var k := 1.0 - float(w.left) / maxf(1.0, float(w.total))
			var scale := float(FLASH.get(kind, 0.8))
			var col := element_col(str(u.element))
			var h := hand(u)
			var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.03)
			add.pin(0, h, (0.15 + 0.55 * k) * scale * pulse, Color(col, 0.5 + 0.45 * k), HHFxParticles.DOT)
			add.pin(1, h, (0.08 + 0.22 * k) * scale, Color(1, 1, 1, 0.9), HHFxParticles.SPARK)
			light.visible = true
			light.position = h
			light.light_color = col
			light.light_energy = (0.6 + 2.4 * k) * scale
			light.omni_range = 3.5
			_acc += (14.0 + 40.0 * k) * scale * delta
			while _acc >= 1.0:
				_acc -= 1.0
				var r := rng.randf_range(0.6, 1.2) * scale
				add.spawn_swirl({ "centre": h, "radius": r, "angle": rng.randf() * TAU, "spin": 5.0, "pull": r / 0.3, "rise": 0.0,
					"y": h.y + rng.randf_range(-0.4, 0.4), "life": 0.3, "size": 0.05, "color": Color(col.lerp(Color.WHITE, 0.4), 1.0),
					"shape": HHFxParticles.STREAK, "streak": 0.03 })
	_step_rings(delta)
	_step_numbers(delta)
	add.step(delta)
	mix.step(delta)


func on_event(e: Dictionary, sim: HHSim, player_id: String) -> void:
	var t := str(e.type)
	var u := sim.unit(str(e.get("id", "")))
	var el := str(e.get("element", u.get("element", "") if not u.is_empty() else ""))
	var col := element_col(el)
	match t:
		"strike":
			var tgt := sim.unit(str(e.target))
			var at: Vector3 = sim.arena.surface(e.hex) + Vector3(0, 1.3, 0)
			if not tgt.is_empty() and not u.is_empty():
				var tp: Vector3 = tgt.pos
				var up: Vector3 = u.pos
				at = tp.lerp(up, 0.35) + Vector3(0, 1.4, 0)
			var mine := str(e.id) == player_id
			var c := element_col(str(u.get("element", ""))) if mine else Color(1.0, 0.9, 0.8)
			burst(at, c, 10 + int(clampf(float(e.amount) / 20.0, 0.0, 14.0)), 1.0)
			flash(at, c, 0.9 + 0.6 * clampf(float(e.amount) / 200.0, 0.0, 1.0))
		"cast":
			if str(e.id) == player_id and not u.is_empty():
				flash(hand(u), col, 0.6)
		"pierce", "energized_shot", "daggerleap":
			var hs: Array = e.get("hexes", [])
			var from: Vector3 = u.pos + Vector3(0, 1.2, 0) if not u.is_empty() else Vector3.ZERO
			for i in hs.size():
				var h: Vector2i = hs[i]
				if not sim.arena.exists(h):
					continue
				var q := sim.arena.surface(h) + Vector3(0, 0.8, 0)
				var d := (q - from)
				d.y = 0.0
				d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
				add.spawn({ "pos": q, "vel": d * 14.0, "life": 0.2 + 0.02 * i, "size": 0.14, "size_end": 0.05, "color": Color(col.lerp(Color.WHITE, 0.3), 1.0),
					"shape": HHFxParticles.STREAK, "streak": 0.05 })
				if i % 2 == 0:
					burst(q, col, 3, 0.6)
		"eruption", "arrowstorm":
			var centre: Vector3 = sim.arena.surface(e.hex) if e.has("hex") else (u.pos if not u.is_empty() else Vector3.ZERO)
			var radius := _radius(sim, e.get("hexes", []), centre)
			big_ring(centre, col, radius, t == "arrowstorm", sim, e.get("hexes", []))
		"flourish":
			var centre: Vector3 = sim.arena.surface(e.hex) if e.has("hex") else u.pos
			ring(centre, col, _radius(sim, e.get("hexes", []), centre), 0.4)
			burst(centre + Vector3(0, 1.0, 0), col, 12, 1.0)
		"knifedance":
			if str(e.get("phase", "")) == "pulse" and not u.is_empty():
				ring(u.pos, col, _radius(sim, e.get("hexes", []), u.pos), 0.3)
		"reaction":
			# H50: once per unit per cast, after the blasts: the big hit on the body
			if u.is_empty():
				return
			var big := str(u.get("kind", "")) == "monster"
			var h := 3.2 if big else 1.6
			var at2: Vector3 = (u.pos as Vector3) + Vector3(0, h, 0)
			var c3 := Color(1.0, 0.8, 0.35)
			var blasts := int(e.get("blasts", 1))
			ring(u.pos, c3, (float(u.get("size", 0)) + 1.5) * 1.3, 0.45)
			burst(at2, c3, 18 + 4 * mini(blasts, 6), 1.6)
			flash(at2, c3, 2.0 if big else 1.2)
			var txt := "%d" % int(round(float(e.amount)))
			if blasts > 1:
				txt += "  x%d" % blasts
			number(at2 + Vector3(0, 0.8, 0), txt, Color(1.0, 0.86, 0.3) if big else Color(1.0, 0.45, 0.35), 1.0 if big else 0.75)
		"detonate":
			if e.has("hex") and sim.arena.exists(e.hex):
				var q2 := sim.arena.surface(e.hex) + Vector3(0, 0.6, 0)
				burst(q2, Color(1.0, 0.9, 0.6), 6, 0.7)
				var mult := float(e.get("mult", e.get("pct", 0.0)))
				if mult > 0.0:
					number(q2 + Vector3(0, 0.4, 0), "x%.1f" % mult, Color(1.0, 0.95, 0.75), 0.45)
		"upgrade":
			var hs2: Array = e.get("hexes", [])
			if not hs2.is_empty():
				var c2 := Vector3.ZERO
				var n := 0
				for h in hs2:
					if sim.arena.exists(h):
						c2 += sim.arena.surface(h)
						n += 1
				if n > 0:
					c2 /= float(n)
					ring(c2, col, _radius(sim, hs2, c2), 0.35)


func _radius(sim: HHSim, hs: Array, centre: Vector3) -> float:
	var r := 1.5
	for h in hs:
		if sim.arena.exists(h):
			var q := sim.arena.surface(h)
			r = maxf(r, Vector2(q.x - centre.x, q.z - centre.z).length() + 0.7)
	return r


## A sparks-and-flecks burst at a point.
func burst(at: Vector3, col: Color, n: int, scale: float) -> void:
	for i in n:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		add.spawn({ "pos": at, "vel": d * rng.randf_range(3.0, 7.0) * scale, "life": rng.randf_range(0.2, 0.4), "size": 0.08 * scale, "size_end": 0.03,
			"color": Color(col.lerp(Color.WHITE, 0.45), 1.0), "color_end": Color(col, 0.0), "grav": 6.0, "drag": 2.0,
			"shape": HHFxParticles.STREAK, "streak": 0.04 })


## A short flash: brief and small (no full-screen white).
func flash(at: Vector3, col: Color, size: float) -> void:
	add.spawn({ "pos": at, "life": 0.12, "size": size * 0.6, "size_end": size, "color": Color(col.lerp(Color.WHITE, 0.6), 0.85), "color_end": Color(col, 0.0), "shape": HHFxParticles.DOT })
	add.spawn({ "pos": at, "life": 0.1, "size": size * 0.5, "color": Color(1, 1, 1, 0.9), "shape": HHFxParticles.SPARK })


## A flat ring expanding over the ground.
func ring(at: Vector3, col: Color, radius: float, life: float) -> void:
	var r: Dictionary = _ring_pool.pop_back() if not _ring_pool.is_empty() else {}
	if r.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = _plane_get()
		mi.material_override = _ring_mat_get()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		r = { "mi": mi }
	var m: MeshInstance3D = r.mi
	m.visible = true
	m.position = at + Vector3(0, 0.12, 0)
	m.scale = Vector3(radius, 1, radius)
	m.set_instance_shader_parameter("col", col.lerp(Color.WHITE, 0.2))
	m.set_instance_shader_parameter("k", 0.0)
	r.t = 0.0
	r.life = life
	rings.append(r)


## Eruption / Arrowstorm landing: two rings, a column of streaks, sparks out
## along the ground, embers / grit over every hex of the area; arrowstorm
## first rains streaks down into it.
func big_ring(at: Vector3, col: Color, radius: float, rain: bool, sim: HHSim, hs: Array) -> void:
	ring(at, col, radius, RING_S)
	ring(at, col.lerp(Color.WHITE, 0.5), radius * 0.65, RING_S * 0.8)
	flash(at + Vector3(0, 1.2, 0), col, 2.2)
	for i in 36:
		var a := TAU * float(i) / 36.0 + rng.randf() * 0.1
		var d := Vector3(cos(a), 0, sin(a))
		add.spawn({ "pos": at + d * 0.5 + Vector3(0, 0.3, 0), "vel": d * rng.randf_range(radius * 1.6, radius * 2.4) + Vector3(0, rng.randf_range(0.5, 2.0), 0),
			"life": 0.45, "size": 0.12, "size_end": 0.05, "color": Color(col.lerp(Color.WHITE, 0.4), 1.0), "color_end": Color(col, 0.0), "drag": 2.5,
			"shape": HHFxParticles.STREAK, "streak": 0.04 })
	for i in 14:
		add.spawn({ "pos": at + _jit(radius * 0.3) + Vector3(0, 0.4, 0), "vel": Vector3(0, rng.randf_range(6.0, 11.0), 0), "life": 0.4, "size": 0.16,
			"color": Color(col.lerp(Color.WHITE, 0.5), 0.9), "shape": HHFxParticles.STREAK, "streak": 0.06 })
	var n := 0
	for h in hs:
		if n >= 30 or not sim.arena.exists(h):
			continue
		n += 1
		var q := sim.arena.surface(h)
		if rain:
			add.spawn({ "pos": q + Vector3(0, 5.0, 0), "vel": Vector3(0, -22.0, 0), "life": 0.22, "size": 0.08, "color": Color(col.lerp(Color.WHITE, 0.6), 1.0),
				"shape": HHFxParticles.STREAK, "streak": 0.04 })
		mix.spawn({ "pos": q + Vector3(0, 0.2, 0), "vel": Vector3(0, 0.8, 0), "life": 0.7, "size": 0.35, "size_end": 0.9,
			"color": Color(col.lerp(Color(0.6, 0.55, 0.5), 0.6), 0.45), "color_end": Color(0.6, 0.55, 0.5, 0.0), "shape": HHFxParticles.PUFF })


func _jit(r: float) -> Vector3:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * r
	return Vector3(cos(a) * d, 0.0, sin(a) * d)


func _step_rings(delta: float) -> void:
	var keep: Array = []
	for r in rings:
		r.t = float(r.t) + delta
		var k := clampf(float(r.t) / float(r.life), 0.0, 1.0)
		var mi: MeshInstance3D = r.mi
		mi.set_instance_shader_parameter("k", k)
		if k >= 1.0:
			mi.visible = false
			_ring_pool.append(r)
		else:
			keep.append(r)
	rings = keep


static func _plane_get() -> PlaneMesh:
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(2, 2)
	return _plane


static func _ring_mat_get() -> ShaderMaterial:
	if _ring_mat == null:
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = load("res://shaders/fx_ring.gdshader")
	return _ring_mat


## A floating number (H50 reactions, detonation multipliers): rises and fades,
## always on top, outlined so it reads on any ground.
func number(at: Vector3, text: String, col: Color, scale: float) -> void:
	var l: Label3D = _num_pool.pop_back() if not _num_pool.is_empty() else null
	if l == null:
		l = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.font_size = 64
		l.outline_size = 14
		l.outline_modulate = Color(0.05, 0.03, 0.02, 1.0)
		l.render_priority = 10
		l.outline_render_priority = 9
		add_child(l)
	l.visible = true
	l.text = text
	l.modulate = col
	l.pixel_size = 0.0006 * scale
	l.position = at
	numbers.append({ "label": l, "t": 0.0, "from": at, "scale": scale })


func _step_numbers(delta: float) -> void:
	var keep: Array = []
	for n in numbers:
		n.t = float(n.t) + delta
		var k := clampf(float(n.t) / NUMBER_S, 0.0, 1.0)
		var l: Label3D = n.label
		l.position = (n.from as Vector3) + Vector3(0, 1.4 * (1.0 - pow(1.0 - k, 2.0)), 0)
		var pop := 1.0 + 0.5 * (1.0 - clampf(float(n.t) / 0.12, 0.0, 1.0))
		l.pixel_size = 0.0006 * float(n.scale) * pop
		var c := l.modulate
		c.a = 1.0 - smoothstep(0.6, 1.0, k)
		l.modulate = c
		l.outline_modulate.a = c.a
		if k >= 1.0:
			l.visible = false
			_num_pool.append(l)
		else:
			keep.append(n)
	numbers = keep
