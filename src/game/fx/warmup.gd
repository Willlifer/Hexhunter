class_name HHWarmup
extends Node3D
## Shader warm-up behind the loading screen. The browser (WebGL, the
## Compatibility renderer) compiles a shader the first time something draws
## with it, and that compile freezes the page: the first telegraph, the first
## reaction, the first light that pops in. In co-op a long freeze stalls the
## stream until the relay drops the player. So before play starts, every
## project shader draws once in front of the camera, as a plain mesh and in
## each MultiMesh layout the effects use, with an omni and a spot light over
## the whole arena (an object lit by a point light is another variant).
## `done` fires after HHTune load_warm_frames rendered frames (or `frames`
## when set); the node frees itself.
##
## H460-H462 (lane LD): the shader list is every .gdshader under res://shaders
## and res://src (the arena's gk_fade too) plus the runtime-built ones
## (HHTierFx.warm_shaders). `add_proxies(root)` also draws a tiny copy of
## each mesh + material under `root` here in front of the camera (all of them
## for the boot preload, HHPreload; only the hidden ones for a fight's own
## warm-up), so a StandardMaterial3D variant, a pooled effect that starts
## hidden, or a prop behind the camera compiles now and not on first sight.

signal done()

const DIRS := ["res://shaders", "res://src"]
const LAYOUTS := [[false, false], [true, true], [false, true]]   # MultiMesh use_colors, use_custom_data (fx_particles, telegraph_fx)
const PROXY_SIZE := 0.04         ## a proxy's longest side (m), 2 m in front of the camera
const MAX_PROXIES := 900

var frames := -1                 ## >= 0: warm this many frames instead of load_warm_frames
var proxies := 0                 ## proxies added (logs, tests)
var _frames := 0
var _lights: Array[Light3D] = []
var _centre := Vector3.ZERO
var _slot := 0
var _seen := {}


## Start warming (the caller puts this node in front of the camera), with
## the temporary lights over `centre`.
func begin(centre: Vector3) -> void:
	_centre = centre
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	for sh in shaders():
		if sh.get_mode() != Shader.MODE_SPATIAL:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.position = _next_slot()
		add_child(mi)
		for lay in LAYOUTS:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = lay[0]
			mm.use_custom_data = lay[1]
			mm.mesh = quad
			mm.instance_count = 1
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.position = mi.position
			add_child(mmi)
	var omni := OmniLight3D.new()
	omni.omni_range = 60.0
	omni.light_energy = 0.01                  # behind the loading screen anyway
	var spot := SpotLight3D.new()
	spot.spot_range = 60.0
	spot.spot_angle = 80.0
	spot.light_energy = 0.01
	spot.rotation_degrees = Vector3(-90, 0, 0)
	for l: Light3D in [omni, spot]:
		l.top_level = true
		add_child(l)
		_lights.append(l)
	var own := OmniLight3D.new()                # and one by the quads themselves
	own.omni_range = 3.0
	own.light_energy = 0.01
	add_child(own)


## Draw a tiny copy of every distinct mesh + material under `root` here
## (only the hidden ones when `hidden_only`). Returns how many were added.
func add_proxies(root: Node, hidden_only: bool) -> int:
	var before := proxies
	_walk(root, hidden_only)
	return proxies - before


func _walk(n: Node, hidden_only: bool) -> void:
	if n == self or proxies >= MAX_PROXIES:
		return
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		if not hidden_only or not g.is_visible_in_tree():
			_proxy(g)
	for ch in n.get_children():
		_walk(ch, hidden_only)


func _proxy(g: GeometryInstance3D) -> void:
	var key := proxy_key(g)
	if key == "" or _seen.has(key):
		return
	_seen[key] = true
	var p: GeometryInstance3D = null
	var aabb := AABB()
	if g is MeshInstance3D:
		var src := g as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		for s in src.get_surface_override_material_count():
			mi.set_surface_override_material(s, src.get_surface_override_material(s))
		p = mi
		aabb = src.mesh.get_aabb()
	elif g is MultiMeshInstance3D or g is CPUParticles3D:
		var mesh: Mesh = (g as MultiMeshInstance3D).multimesh.mesh if g is MultiMeshInstance3D else (g as CPUParticles3D).mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		if g is MultiMeshInstance3D:
			mm.use_colors = (g as MultiMeshInstance3D).multimesh.use_colors
			mm.use_custom_data = (g as MultiMeshInstance3D).multimesh.use_custom_data
		else:                                   # CPUParticles3D draws through a coloured, custom-data MultiMesh
			mm.use_colors = true
			mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		p = mmi
		aabb = mesh.get_aabb()
	elif g is SpriteBase3D or g is Label3D:
		p = g.duplicate(0) as GeometryInstance3D
		p.visible = true
		aabb = g.get_aabb()
	if p == null:
		return
	p.material_override = g.material_override
	p.material_overlay = g.material_overlay
	p.cast_shadow = g.cast_shadow
	p.transparency = g.transparency
	var k := PROXY_SIZE / maxf(aabb.get_longest_axis_size(), 0.001)
	p.scale = Vector3.ONE * k
	p.position = _next_slot() - aabb.get_center() * k
	p.rotation = Vector3.ZERO
	add_child(p)
	proxies += 1


## Identity of what a proxy would draw (mesh and materials); "" for nothing
## drawable. Two nodes with the same key compile the same pipelines.
static func proxy_key(g: GeometryInstance3D) -> String:
	var mesh: Mesh = null
	var parts: Array = []
	if g is MeshInstance3D:
		mesh = (g as MeshInstance3D).mesh
		if mesh != null:
			for s in (g as MeshInstance3D).get_surface_override_material_count():
				var m := (g as MeshInstance3D).get_surface_override_material(s)
				parts.append(m.get_instance_id() if m != null else 0)
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm != null:
			mesh = mm.mesh
			parts.append("mm%d%d" % [int(mm.use_colors), int(mm.use_custom_data)])
	elif g is CPUParticles3D:
		mesh = (g as CPUParticles3D).mesh
		parts.append("cpu")
	elif g is SpriteBase3D or g is Label3D:
		return "%s:%d" % [g.get_class(), g.get_instance_id()]
	if mesh == null:
		return ""
	var mo := g.material_override
	var ov := g.material_overlay
	return "%d|%s|%d|%d" % [mesh.get_instance_id(), ",".join(parts.map(func(x): return str(x))),
		mo.get_instance_id() if mo != null else 0, ov.get_instance_id() if ov != null else 0]


## The next free spot in the grid of tiny draws (a 24-wide wall, 3 cm apart).
func _next_slot() -> Vector3:
	var i := _slot
	_slot += 1
	return Vector3(float(i % 24) * 0.03 - 0.36, float(i / 24) * 0.03 - 0.3, 0)


func _process(_delta: float) -> void:
	if _frames == 0:
		for l in _lights:
			l.global_position = _centre + Vector3(0, 6, 0)
	_frames += 1
	if _frames >= (frames if frames >= 0 else int(HHTune.value("load_warm_frames"))):
		set_process(false)
		done.emit()
		queue_free()


## Every shader to warm: the project's .gdshader files and the runtime-built ones.
static func shaders() -> Array[Shader]:
	var out: Array[Shader] = []
	var web := HHWebLook.active()
	if web:
		HHWebLook.ensure_globals()           # the *_web shaders read globals that must exist before they compile
	for path in shader_paths():
		if not web and path.get_file().get_basename().ends_with("_web"):
			continue                           # the Compatibility renderer's variants (H90): never drawn on Forward+

		var sh := load(path) as Shader
		if sh != null:
			out.append(sh)
	out.append_array(HHTierFx.warm_shaders())
	return out


## Every .gdshader under res://shaders and res://src (cached: the tree is
## walked once per run). An exported build lists them through
## ResourceLoader.list_directory, which resolves .remap entries.
static func shader_paths() -> Array[String]:
	if _paths.is_empty():
		for d in DIRS:
			for p in HHPreload.list_files(d, ["gdshader"]):
				_paths.append(p)
	return _paths


static var _paths: Array[String] = []
