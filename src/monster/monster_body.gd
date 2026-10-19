class_name HHMonsterBody
extends Node3D
## A monster's body at run time: instances art/monsters/<id>.glb (built by
## tools/blender/build_monster_<id>.py with monster_rig/rigkit.py, never
## hand-edited), finds its Skeleton3D, exposes bone and socket lookup, and
## plays procedural clips: GDScript pose functions of time (one script per
## monster, HHSwampfangClips for Swampfang) that bend bones about model axes.
##
##   var b := HHMonsterBody.new()
##   add_child(b)
##   b.build("swampfang")
##   b.play("aggravated_idle")          # loops
##   b.play("frill_roar", false)        # one-shot, then back to the loop it interrupted
##   b.update(delta)                    # every frame
##
## Model space (manifest "space"): origin on the ground under the hips, +Y up,
## +Z forward (the fight sets rotation.y = unit.facing), +X the monster's left.
##
## POSE API for clip functions (all offsets from the rest pose, accumulate):
##   rot(bone, Vector3(pitch, yaw, roll) in degrees)  rotation about the model
##       axes X, Y, Z (right-hand rule) applied at the bone's head, in the
##       frame its parents leave it in. A forward bone (head, neck, spine)
##       drops its tip with +pitch and lifts it with -pitch; a backward bone
##       (tail) lifts its tip with +pitch. +yaw swings any tip to the left.
##   move(bone, Vector3 offset in model metres)         translation, same frame
##   Clips call these from `pose(clip, t, body)`; the body samples, cross-
##   fades the outgoing clip for FADE seconds, and writes the skeleton.
##
## Clip tables: `clips(id)` is the CLIPS dictionary of that monster's set
## ({ clip: { duration (s), contact_tick (30 Hz tick when damage lands, -1
## none), loop, key (preview time) } }); `clip_list(id)` its names.

const MANIFEST_PATH := "res://art/monsters/monsters.json"
const GLB_DIR := "res://art/monsters/"
const FADE := 0.18                 ## cross-fade between clips (s)
const CLIP_SET_DIR := "res://src/monster/"      ## <id>_clips.gd holds a monster's clip set
const ROUGHNESS := { "hide": 0.85, "belly": 0.8, "frill": 0.7, "teeth": 0.35, "eye": 0.15, "claw": 0.45 }

static var _manifest := {}

var id := ""
var row := {}                      ## this monster's manifest row
var model: Node3D
var skeleton: Skeleton3D
var body: MeshInstance3D            ## the hide mesh (one MeshInstance3D per role: body_<role>)
var meshes: Array[MeshInstance3D] = []
var clip := ""                     ## the clip playing on top
var time := 0.0
var loop := true
var speed := 1.0
var finished_clip := ""            ## set when a one-shot ran out this frame (consumers may read and clear)

var _set: GDScript
var _bones := {}                   # name -> index
var _rest := {}                    # index -> Basis (global rest, model space)
var _sockets := {}                 # name -> Node3D
var _sample := {}                  # index -> [Quaternion, Vector3]
var _prev_clip := ""
var _prev_time := 0.0
var _prev_loop := true
var _fade := 0.0                   # seconds left in the cross-fade
var _resume := ""                  # loop to go back to after a one-shot


# ------------------------------------------------------------------ manifest

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var txt := FileAccess.get_file_as_string(MANIFEST_PATH)
		var parsed: Variant = JSON.parse_string(txt) if txt != "" else null
		_manifest = parsed if parsed is Dictionary else {}
	return _manifest


static func manifest_row(monster_id: String) -> Dictionary:
	var m: Dictionary = manifest().get("monsters", {})
	return m.get(monster_id, {})


## The clip-set script of a monster (null when it has none).
static func clip_set(monster_id: String) -> GDScript:
	var path := CLIP_SET_DIR + monster_id + "_clips.gd"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func clips(monster_id: String) -> Dictionary:
	var s := clip_set(monster_id)
	if s == null:
		return {}
	var c: Variant = s.get("CLIPS")
	return c if c is Dictionary else {}


static func clip_list(monster_id: String = "swampfang") -> PackedStringArray:
	var out := PackedStringArray(clips(monster_id).keys())
	return out


# ------------------------------------------------------------------ build

## Instance the glb and wire it up. False (with an error) if missing.
func build(monster_id: String) -> bool:
	if model != null:
		return true
	id = monster_id
	row = manifest_row(id)
	_set = clip_set(id)
	var scene := load(GLB_DIR + id + ".glb") as PackedScene
	if scene == null:
		push_error("HHMonsterBody: cannot load %s%s.glb (run --import?)" % [GLB_DIR, id])
		return false
	model = scene.instantiate() as Node3D
	model.name = "model"
	add_child(model)
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		push_error("HHMonsterBody: no Skeleton3D in %s" % id)
		return false
	skeleton = sk[0]
	for i in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(i)] = i
		_rest[i] = skeleton.get_bone_global_rest(i).basis
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(mi)
		if body == null or str(mi.name) == "body_hide":
			body = mi
		_apply_materials(mi)
	for n in model.find_children("socket_*", "Node3D", true, false):
		_sockets[str(n.name).trim_prefix("socket_")] = n
	for n in model.find_children("ik_*", "Node3D", true, false):
		_sockets[str(n.name)] = n
	for s in row.get("sockets", {}):
		if not _sockets.has(s):
			push_warning("HHMonsterBody: socket %s missing from %s.glb" % [s, id])
	return true


func _apply_materials(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in mi.mesh.get_surface_count():
		var role := surface_role(mi.mesh, i)
		mi.set_surface_override_material(i, material_for(role))


## The role of a surface: its material's name (rigkit names materials by role).
static func surface_role(mesh: Mesh, i: int) -> String:
	var mat := mesh.surface_get_material(i)
	var n := mat.resource_name if mat else ""
	if n == "" and mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(i)
	return n


## A plain per-role material: vertex COLOR as albedo (the build bakes the
## palette into COLOR), roughness by role. GKMaterials-style roles can
## replace this later (the role name is the key).
static func material_for(role: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.roughness = float(ROUGHNESS.get(role, 0.8))
	m.metallic = 0.0
	if role == "frill":
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = "hh_" + role
	return m


# ------------------------------------------------------------------ lookup

func bone(bone_name: String) -> int:
	return int(_bones.get(bone_name, -1))


func bone_names() -> PackedStringArray:
	var out := PackedStringArray(_bones.keys())
	out.sort()
	return out


func has_bone(bone_name: String) -> bool:
	return _bones.has(bone_name)


## The socket node ("mouth" or "socket_mouth"; IK targets "ik_fl"). Null if unknown.
func socket(socket_name: String) -> Node3D:
	return _sockets.get(socket_name.trim_prefix("socket_"))


func socket_names() -> PackedStringArray:
	var out := PackedStringArray(_sockets.keys())
	out.sort()
	return out


## Socket position in model space, posed (works outside the tree too).
func socket_pos(socket_name: String) -> Vector3:
	var s := socket(socket_name)
	if s == null or skeleton == null:
		return Vector3.ZERO
	var att := s.get_parent() as BoneAttachment3D
	if att == null:
		return s.transform.origin
	var b := skeleton.find_bone(att.bone_name)
	if b < 0:
		return s.transform.origin
	return (skeleton.transform * global_pose(b) * s.transform).origin


## Bone head position in model space, posed.
func bone_pos(bone_name: String) -> Vector3:
	var b := bone(bone_name)
	if b < 0:
		return Vector3.ZERO
	return (skeleton.transform * global_pose(b)).origin


## A bone's global pose from the local poses (Skeleton3D only refreshes its
## own globals inside the tree; tools and tests pose headless).
func global_pose(i: int) -> Transform3D:
	var t := skeleton.get_bone_pose(i)
	var p := skeleton.get_bone_parent(i)
	while p >= 0:
		t = skeleton.get_bone_pose(p) * t
		p = skeleton.get_bone_parent(p)
	return t


func triangle_count() -> int:
	var n := 0
	for mi in meshes:
		for i in mi.mesh.get_surface_count():
			n += mi.mesh.surface_get_array_index_len(i) / 3
	return n


# ------------------------------------------------------------------ pose API

## Rotate `bone_name` by (pitch, yaw, roll) degrees about the model X, Y, Z
## axes (right-hand rule), accumulating with earlier calls this sample.
func rot(bone_name: String, euler_deg: Vector3) -> void:
	var i := bone(bone_name)
	if i < 0:
		return
	var r := Basis(Vector3.UP, deg_to_rad(euler_deg.y)) * Basis(Vector3.RIGHT, deg_to_rad(euler_deg.x)) * Basis(Vector3.BACK, deg_to_rad(euler_deg.z))
	var g: Basis = _rest[i]
	var local := g.inverse() * r * g
	var cur: Array = _sample.get(i, [Quaternion.IDENTITY, Vector3.ZERO])
	cur[0] = (cur[0] as Quaternion) * local.get_rotation_quaternion()
	_sample[i] = cur


## Translate `bone_name` by `offset` model metres (same frame as rot).
func move(bone_name: String, offset: Vector3) -> void:
	var i := bone(bone_name)
	if i < 0:
		return
	var g: Basis = _rest[i]
	var cur: Array = _sample.get(i, [Quaternion.IDENTITY, Vector3.ZERO])
	cur[1] = (cur[1] as Vector3) + g.inverse() * offset
	_sample[i] = cur


## Bend a chain of bones by a total (pitch, yaw, roll), spread along it with
## `falloff` (1 = even; > 1 puts more of the bend toward the chain's end).
func bend(chain: Array, total_deg: Vector3, falloff: float = 1.0) -> void:
	var n := chain.size()
	if n == 0:
		return
	var wsum := 0.0
	var ws: Array = []
	for k in n:
		var w := pow(float(k + 1) / float(n), falloff)
		ws.append(w)
		wsum += w
	for k in n:
		rot(str(chain[k]), total_deg * (float(ws[k]) / wsum))


# ------------------------------------------------------------------ clips

func play(clip_name: String, p_loop: bool = true, p_speed: float = 1.0) -> bool:
	if _set == null or not clips(id).has(clip_name):
		push_warning("HHMonsterBody: %s has no clip '%s'" % [id, clip_name])
		return false
	if clip_name == clip and p_loop and loop:
		return true
	if clip != "":
		_prev_clip = clip
		_prev_time = time
		_prev_loop = loop
		_fade = FADE
		if loop:
			_resume = clip                 # a one-shot returns to the loop it cut
	clip = clip_name
	time = 0.0
	loop = p_loop
	speed = p_speed
	finished_clip = ""
	return true


## Freeze on one moment of a clip (tools, renders, tests): no fade.
func pose_at(clip_name: String, t: float) -> bool:
	if _set == null or not clips(id).has(clip_name):
		return false
	clip = clip_name
	time = t
	loop = bool(clips(id)[clip_name].get("loop", false))
	_prev_clip = ""
	_fade = 0.0
	_write(_sample_clip(clip, time))
	return true


func duration(clip_name: String) -> float:
	return float(clips(id).get(clip_name, {}).get("duration", 0.0))


func update(delta: float) -> void:
	if skeleton == null or clip == "":
		return
	var d := duration(clip)
	time += delta * speed
	if loop:
		if d > 0.0:
			time = fmod(time, d)
	elif time >= d:
		time = d
		finished_clip = clip
		if _resume != "" and _resume != clip:
			play(_resume)
			_resume = ""
			time = 0.0
			d = duration(clip)
	var cur := _sample_clip(clip, time)
	if _fade > 0.0 and _prev_clip != "":
		_fade -= delta
		_prev_time += delta * speed
		var pd := duration(_prev_clip)
		if _prev_loop and pd > 0.0:
			_prev_time = fmod(_prev_time, pd)
		elif pd > 0.0:
			_prev_time = minf(_prev_time, pd)
		var w := smoothstep(0.0, 1.0, clampf(1.0 - _fade / FADE, 0.0, 1.0))
		cur = _mix(_sample_clip(_prev_clip, _prev_time), cur, w)
		if _fade <= 0.0:
			_prev_clip = ""
	_write(cur)


func _sample_clip(clip_name: String, t: float) -> Dictionary:
	_sample = {}
	_set.call("pose", clip_name, t, self)
	var out := _sample
	_sample = {}
	return out


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for i in a:
		out[i] = a[i]
	for i in b:
		if out.has(i):
			var pa: Array = out[i]
			var pb: Array = b[i]
			out[i] = [(pa[0] as Quaternion).slerp(pb[0], w), (pa[1] as Vector3).lerp(pb[1], w)]
		else:
			var pb2: Array = b[i]
			out[i] = [Quaternion.IDENTITY.slerp(pb2[0], w), (Vector3.ZERO).lerp(pb2[1], w)]
	for i in a:
		if not b.has(i):
			var pa2: Array = a[i]
			out[i] = [(pa2[0] as Quaternion).slerp(Quaternion.IDENTITY, w), (pa2[1] as Vector3).lerp(Vector3.ZERO, w)]
	return out


func _write(sample: Dictionary) -> void:
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		if sample.has(i):
			var s: Array = sample[i]
			var q: Quaternion = s[0]
			var p: Vector3 = s[1]
			skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion() * q)
			skeleton.set_bone_pose_position(i, rest.origin + rest.basis * p)
		else:
			skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_position(i, rest.origin)


func reset_pose() -> void:
	if skeleton:
		_write({})
