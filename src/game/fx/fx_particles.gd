class_name HHFxParticles
extends MultiMeshInstance3D
## Lane FX (H700): a small sprite particle system on one MultiMesh, driven
## from GDScript so motion can do what the wind-ups need (streaks spiralling
## IN to a point, motes converging, smoke rising off a moving socket), which
## GPUParticles3D cannot do cheaply. One blend mode per system: `additive`
## for glows / embers / streaks, alpha for smoke / dust / snow.
##
##   var p := HHFxParticles.new(160, true)
##   p.spawn({ pos, vel, life, size, size_end, color, color_end, shape, grav, drag, streak })
##   p.spawn_swirl({ centre, radius, angle, spin, pull, rise, ... })
##   p.pin(slot, pos, size, color, shape)      # a held sprite (mouth glow), slots < PINS
##   p.step(delta)                              # advance + write the MultiMesh
##
## Shapes: see shaders/fx_particle.gdshaderinc. Colours are given in sRGB
## and converted to linear here (the shaders take COLOR as linear).

enum { DOT, STREAK, PUFF, SHARD, FLAKE, RING, SPARK }
const PINS := 4

var cap := 0
var additive := true
var n := 0                                  ## live particles (not counting pins)

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _s0 := PackedFloat32Array()
var _s1 := PackedFloat32Array()
var _c0 := PackedColorArray()
var _c1 := PackedColorArray()
var _shape := PackedInt32Array()
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _streak := PackedFloat32Array()
var _mode := PackedInt32Array()             # 0 ballistic, 1 swirl
var _sc := PackedVector3Array()             # swirl centre
var _sr := PackedFloat32Array()             # swirl radius
var _sa := PackedFloat32Array()             # swirl angle
var _sw := PackedFloat32Array()             # swirl spin (rad/s)
var _sp := PackedFloat32Array()             # swirl pull (m/s inward)
var _sy := PackedFloat32Array()             # swirl rise (m/s)
var _pins: Array = []                       # [{ pos, size, color, shape }] or {}

static var _mats := {}
static var _quad: QuadMesh


func _init(p_cap: int = 128, p_additive: bool = true) -> void:
	cap = p_cap
	additive = p_additive
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad_mesh()
	mm.instance_count = cap + PINS
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = material(additive)
	custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 150, 400))   # world-space sprites: never cull
	# packed arrays are values: resize each one in place
	_pos.resize(cap)
	_vel.resize(cap)
	_sc.resize(cap)
	_age.resize(cap)
	_life.resize(cap)
	_s0.resize(cap)
	_s1.resize(cap)
	_grav.resize(cap)
	_drag.resize(cap)
	_streak.resize(cap)
	_sr.resize(cap)
	_sa.resize(cap)
	_sw.resize(cap)
	_sp.resize(cap)
	_sy.resize(cap)
	_c0.resize(cap)
	_c1.resize(cap)
	_shape.resize(cap)
	_mode.resize(cap)
	_pins.resize(PINS)
	for i in PINS:
		_pins[i] = {}


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad


static func material(add: bool) -> ShaderMaterial:
	var key := "add" if add else "mix"
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/fx_particle_%s.gdshader" % key)
		_mats[key] = m
	return _mats[key]


func clear() -> void:
	n = 0
	for i in PINS:
		_pins[i] = {}
	multimesh.visible_instance_count = 0


func live() -> int:
	var k := n
	for p in _pins:
		if not (p as Dictionary).is_empty():
			k += 1
	return k


func full() -> bool:
	return n >= cap


## One ballistic particle. Keys (all optional but pos):
##   pos, vel, life (s), size, size_end, color, color_end, shape, grav (m/s^2,
##   down positive), drag (per s), streak (s of velocity drawn as a streak)
func spawn(o: Dictionary) -> int:
	if n >= cap:
		return -1
	var i := n
	n += 1
	_pos[i] = o.get("pos", Vector3.ZERO)
	_vel[i] = o.get("vel", Vector3.ZERO)
	_common(i, o)
	_mode[i] = 0
	return i


## One particle orbiting `centre` (Y up): it starts `radius` out at `angle`,
## spins at `spin` rad/s, closes in at `pull` m/s and climbs at `rise` m/s.
## Its streak follows its own motion.
func spawn_swirl(o: Dictionary) -> int:
	if n >= cap:
		return -1
	var i := n
	n += 1
	var c: Vector3 = o.get("centre", Vector3.ZERO)
	_sc[i] = c
	_sr[i] = float(o.get("radius", 2.0))
	_sa[i] = float(o.get("angle", 0.0))
	_sw[i] = float(o.get("spin", 3.0))
	_sp[i] = float(o.get("pull", 0.5))
	_sy[i] = float(o.get("rise", 0.0))
	_pos[i] = c + Vector3(cos(_sa[i]) * _sr[i], float(o.get("y", 0.2)), sin(_sa[i]) * _sr[i])
	_vel[i] = Vector3.ZERO
	_common(i, o)
	_mode[i] = 1
	return i


func _common(i: int, o: Dictionary) -> void:
	_age[i] = 0.0
	_life[i] = maxf(0.02, float(o.get("life", 1.0)))
	_s0[i] = float(o.get("size", 0.2))
	_s1[i] = float(o.get("size_end", _s0[i]))
	var c: Color = o.get("color", Color.WHITE)
	_c0[i] = c
	_c1[i] = o.get("color_end", c)
	_shape[i] = int(o.get("shape", DOT))
	_grav[i] = float(o.get("grav", 0.0))
	_drag[i] = float(o.get("drag", 0.0))
	_streak[i] = float(o.get("streak", 0.0))


## A held sprite in slot `slot` (drawn until unpinned). size <= 0 unpins.
func pin(slot: int, pos: Vector3, size: float, color: Color, shape: int = DOT) -> void:
	if slot < 0 or slot >= PINS:
		return
	_pins[slot] = {} if size <= 0.0 or color.a <= 0.002 else { "pos": pos, "size": size, "color": color, "shape": shape }


func step(delta: float) -> void:
	var i := 0
	while i < n:
		_age[i] += delta
		if _age[i] >= _life[i]:
			_kill(i)
			continue
		if _mode[i] == 0:
			var v := _vel[i]
			v.y -= _grav[i] * delta
			v *= maxf(0.0, 1.0 - _drag[i] * delta)
			_vel[i] = v
			_pos[i] += v * delta
		else:
			var prev := _pos[i]
			_sa[i] += _sw[i] * delta
			_sr[i] = maxf(0.05, _sr[i] - _sp[i] * delta)
			var c := _sc[i]
			c.y += _sy[i] * delta
			_sc[i] = c
			var y := prev.y + _sy[i] * delta
			_pos[i] = Vector3(c.x + cos(_sa[i]) * _sr[i], y, c.z + sin(_sa[i]) * _sr[i])
			_vel[i] = (_pos[i] - prev) / maxf(delta, 1e-4)
		i += 1
	_write()


func _kill(i: int) -> void:
	var last := n - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_age[i] = _age[last]
		_life[i] = _life[last]
		_s0[i] = _s0[last]
		_s1[i] = _s1[last]
		_c0[i] = _c0[last]
		_c1[i] = _c1[last]
		_shape[i] = _shape[last]
		_grav[i] = _grav[last]
		_drag[i] = _drag[last]
		_streak[i] = _streak[last]
		_mode[i] = _mode[last]
		_sc[i] = _sc[last]
		_sr[i] = _sr[last]
		_sa[i] = _sa[last]
		_sw[i] = _sw[last]
		_sp[i] = _sp[last]
		_sy[i] = _sy[last]
	n = last


func _write() -> void:
	var mm := multimesh
	var k := 0
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for p in _pins:
		var d: Dictionary = p
		if d.is_empty():
			continue
		mm.set_instance_transform(k, inv * Transform3D(Basis.from_scale(Vector3.ONE * float(d.size)), d.pos))
		mm.set_instance_color(k, (d.color as Color).srgb_to_linear())
		mm.set_instance_custom_data(k, Color(0, 0, 0, float(d.shape)))
		k += 1
	for i in n:
		var f := _age[i] / _life[i]
		var env := minf(1.0, f / 0.12) * (1.0 - smoothstep(0.6, 1.0, f))
		var s := lerpf(_s0[i], _s1[i], f)
		var c := _c0[i].lerp(_c1[i], f)
		c.a *= env
		mm.set_instance_transform(k, inv * Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.001, s)), _pos[i]))
		var lc := c.srgb_to_linear()
		lc.a = c.a
		mm.set_instance_color(k, lc)
		var st := _vel[i] * _streak[i]
		mm.set_instance_custom_data(k, Color(st.x, st.y, st.z, float(_shape[i])))
		k += 1
	mm.visible_instance_count = k
