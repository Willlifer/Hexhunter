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
## `done` fires after HHTune load_warm_frames rendered frames; the node frees itself.

signal done()

const DIR := "res://shaders"
const LAYOUTS := [[false, false], [true, true], [false, true]]   # MultiMesh use_colors, use_custom_data (fx_particles, telegraph_fx)

var _frames := 0
var _lights: Array[Light3D] = []
var _centre := Vector3.ZERO


## Start warming (the caller puts this node in front of the camera), with
## the temporary lights over `centre`.
func begin(centre: Vector3) -> void:
	_centre = centre
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	var i := 0
	for path in shader_paths():
		var sh := load(path) as Shader
		if sh == null or sh.get_mode() != Shader.MODE_SPATIAL:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.position = Vector3(float(i % 12) * 0.03 - 0.18, float(i / 12) * 0.03, 0)
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
		i += 1
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


func _process(_delta: float) -> void:
	if _frames == 0:
		for l in _lights:
			l.global_position = _centre + Vector3(0, 6, 0)
	_frames += 1
	if _frames >= int(HHTune.value("load_warm_frames")):
		set_process(false)
		done.emit()
		queue_free()


## Every .gdshader under res://shaders (an exported build lists the source
## files as they are; .remap entries point at the same paths).
static func shader_paths() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".gdshader"):
			var p := DIR.path_join(name)
			if not p in out:
				out.append(p)
	return out
