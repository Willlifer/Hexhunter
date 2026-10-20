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
##   b.bind(sim, "swampfang")           # optional: the body reads its unit each frame
##   b.set_state(sim.unit(id))          # or the fight feeds the unit dictionary itself
##
## REACTIVE STATE (L-12): set_state(u) reads the brain's view-facing fields
## (`smoulder`, `cold`, `charge`, `reeds_burnt`) and update() drives the
## role materials: Colambros' quills glow when smouldering, Rimeslithe's
## crystals tint and brighten with the cold meter, Spirewalker's arc beads
## and reed tips glow violet by charge with crackling arcs over the bed
## (gone while the reeds are burnt), Swampfang's eyes and frill flash violet
## through a darkness telegraph (`cue("darkness")`, or seen in the bound
## sim's telegraphs). `glow` is the current 0..1 intensity for tests and HUD.
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

# reactive state (L-12)
var sim: HHSim = null              ## bound sim (optional; update() reads unit_id from it)
var unit_id := ""
var state := {}                    ## the last unit dictionary fed to set_state
var glow := 0.0                    ## current readable intensity 0..1 (smoulder / cold / charge / cue)
var state_name := ""               ## "smouldering" | "cold" | "charged" | "reeds_burnt" | "darkness" | ""
var _role_mats := {}               # role -> StandardMaterial3D shared by that role's surfaces
var _state_t := 0.0                # seconds, for pulses
var _cue := 0.0                    # seconds left on a one-shot cue (Swampfang's darkness)
var _cue_name := ""
var _beads: Array = []             # Spirewalker: [{ pos: Vector3 (mesh space), bone: int }] per arc bead
var _bead_xform := Transform3D.IDENTITY
var _arcs: MeshInstance3D = null   # Spirewalker's crackle ribbons
var _arc_t := 0.0
var _arc_rng := RandomNumberGenerator.new()


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
		mi.set_surface_override_material(i, role_material(role))


## This body's material for a role (one per role, shared by every surface of
## that role, so a state change edits one material).
func role_material(role: String) -> StandardMaterial3D:
	if not _role_mats.has(role):
		_role_mats[role] = material_for(role)
	return _role_mats[role]


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
	if skeleton == null:
		return
	if sim != null and unit_id != "":
		set_state(sim.unit(unit_id))
	_drive_state(delta)
	if clip == "":
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


# ------------------------------------------------------------------ reactive state (L-12)

const SMOULDER_COLOR := Color(1.0, 0.32, 0.06)       ## quill ember (HHLook fire glow, warmer)
const COLD_COLOR := Color(0.42, 0.85, 1.0)           ## crystal cold (saturated cyan; white-out at 30 m otherwise)
const CHARGE_COLOR := Color(0.72, 0.42, 1.0)         ## arc violet
const DARK_COLOR := Color(0.42, 0.12, 0.95)          ## Swampfang's darkness call (eyes, frill): deep violet, not pink
const ARC_EVERY := 0.07                              ## seconds between arc re-rolls
const CUE_SECONDS := 1.5                             ## the darkness telegraph window (45 ticks)


## Bind to the sim: update() then reads sim.unit(id) itself every frame
## (the fight may call set_state directly instead).
func bind(p_sim: HHSim, p_id: String) -> void:
	sim = p_sim
	unit_id = p_id


## Feed the unit dictionary (a no-op until called). The brain's view-facing
## fields: smoulder (bool), cold (0..1), charge (0..1), reeds_burnt (bool).
func set_state(u: Dictionary) -> void:
	if u.is_empty():
		return
	state = u
	if sim != null and unit_id != "":
		for tg in sim.telegraphs:
			if str(tg.get("owner", "")) == unit_id and str((tg.get("payload", {}) as Dictionary).get("name", "")) == "darkness":
				cue("darkness", float(tg.get("left", 0)) / 30.0)


## A one-shot visual cue by name for `seconds` (Swampfang: "darkness").
func cue(cue_name: String, seconds: float = CUE_SECONDS) -> void:
	_cue_name = cue_name
	_cue = maxf(_cue, seconds)


func _drive_state(delta: float) -> void:
	_state_t += delta
	if _cue > 0.0:
		_cue -= delta
		if _cue <= 0.0:
			_cue_name = ""
	match id:
		"colambros": _drive_smoulder()
		"rimeslithe": _drive_cold()
		"spirewalker": _drive_charge(delta)
		"swampfang": _drive_darkness()
		_:
			glow = 0.0
			state_name = ""


func _drive_smoulder() -> void:
	var on := bool(state.get("smoulder", false))
	var pulse := 0.72 + 0.28 * sin(_state_t * 7.5)          # a slow breathing ember
	glow = pulse if on else 0.0
	state_name = "smouldering" if on else ""
	_emit("quill", SMOULDER_COLOR, 4.5 * glow, Color(1.0, 0.5, 0.25) if on else Color.WHITE, glow)
	_emit("eye", SMOULDER_COLOR, 2.5 * glow, Color.WHITE, 0.0)


func _drive_cold() -> void:
	var cold := clampf(float(state.get("cold", 0.0)), 0.0, 1.0)
	glow = cold
	state_name = "cold" if cold > 0.5 else ""
	# the crystals: smoky grey -> pale cyan, and brighter with the meter;
	# a shimmer above 0.7 (the weak-point band, H335)
	var shimmer := 1.0 + (0.18 * sin(_state_t * 9.0) if cold > 0.7 else 0.0)
	_emit("crystal", COLD_COLOR, 1.9 * cold * cold * shimmer, Color(0.6, 0.95, 1.2), cold)
	_emit("eye", COLD_COLOR, 2.0 * cold, Color.WHITE, 0.0)


func _drive_charge(delta: float) -> void:
	var charge := clampf(float(state.get("charge", 0.0)), 0.0, 1.0)
	var burnt := bool(state.get("reeds_burnt", false))
	var charged := charge > 0.6 and not burnt
	glow = 0.0 if burnt else charge
	state_name = "reeds_burnt" if burnt else ("charged" if charged else "")
	var flicker := 1.0 + (0.3 * sin(_state_t * 23.0) * sin(_state_t * 5.3) if charged else 0.0)
	var live := 0.0 if burnt else 1.0
	_emit("arc", CHARGE_COLOR, (1.2 + 3.0 * charge) * flicker * live, Color(0.3, 0.26, 0.24) if burnt else Color.WHITE, 1.0 if burnt else 0.0)
	# the reed tips take the violet with the charge; cut reeds go to charcoal
	_emit("reed", CHARGE_COLOR, 1.6 * charge * flicker * live, Color(0.3, 0.26, 0.24) if burnt else Color.WHITE, 1.0 if burnt else 0.0)
	if _arcs == null:
		_build_arcs()
	if _arcs == null:
		return
	_arcs.visible = charged
	if charged:
		_arc_t -= delta
		if _arc_t <= 0.0:
			_arc_t = ARC_EVERY
			_draw_arcs(charge)


func _drive_darkness() -> void:
	var on := _cue > 0.0 and _cue_name == "darkness"
	var pulse := 0.6 + 0.4 * sin(_state_t * 14.0)
	glow = pulse if on else 0.0
	state_name = "darkness" if on else ""
	_emit("eye", DARK_COLOR, 4.0 * glow, Color.WHITE, 0.0)
	_emit("frill", DARK_COLOR, 2.2 * glow, Color(0.75, 0.45, 1.0) if on else Color.WHITE, glow)


## Drive one role's material: emission (colour x energy) and an albedo tint
## (lerped from white by `tint_w`). Energy 0 switches emission off.
func _emit(role: String, color: Color, energy: float, tint: Color, tint_w: float) -> void:
	if not _role_mats.has(role):
		return
	var m: StandardMaterial3D = _role_mats[role]
	m.emission_enabled = energy > 0.001
	m.emission = color
	m.emission_energy_multiplier = maxf(0.0, energy)
	m.albedo_color = Color.WHITE.lerp(tint, clampf(tint_w, 0.0, 1.0))


## Spirewalker: the nine arc beads (role `arc`) are small spheres in the glb;
## cluster the mesh's vertices into bead centres, each with its heaviest bone,
## so the arcs follow the reed bed's pose.
func _build_arcs() -> void:
	var bead_mi: MeshInstance3D = null
	for mi in meshes:
		if str(mi.name) == "body_arc":
			bead_mi = mi
	if bead_mi == null or bead_mi.mesh.get_surface_count() == 0:
		return
	var arrays := bead_mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: Variant = arrays[Mesh.ARRAY_BONES]
	var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
	var per := 0
	if bones is PackedInt32Array and verts.size() > 0:
		per = (bones as PackedInt32Array).size() / verts.size()
	var clusters: Array = []
	for vi in verts.size():
		var v := verts[vi]
		var found := false
		for cl in clusters:
			var centre: Vector3 = (cl.sum as Vector3) / float(cl.n)
			if centre.distance_to(v) < 0.22:
				cl.sum = (cl.sum as Vector3) + v
				cl.n = int(cl.n) + 1
				found = true
				break
		if not found:
			var bone := -1
			if per > 0:
				var best := -1.0
				for k in per:
					var w := float((weights as PackedFloat32Array)[vi * per + k])
					if w > best:
						best = w
						bone = int((bones as PackedInt32Array)[vi * per + k])
			clusters.append({ "sum": v, "n": 1, "bone": bone })
	_beads = []
	for cl in clusters:
		_beads.append({ "pos": (cl.sum as Vector3) / float(cl.n), "bone": int(cl.bone) })
	_bead_xform = bead_mi.transform
	_arcs = MeshInstance3D.new()
	_arcs.name = "arcs"
	_arcs.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arcs.material_override = m
	_arcs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arcs.visible = false
	skeleton.add_child(_arcs)


func bead_count() -> int:
	return _beads.size()


## A bead's posed position in skeleton space.
func bead_pos(i: int) -> Vector3:
	var b: Dictionary = _beads[i]
	var p: Vector3 = _bead_xform * (b.pos as Vector3)
	var bone := int(b.bone)
	if bone < 0:
		return p
	return global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse() * p


## Re-roll the crackle: ribbons between bead pairs (jittered, camera-faced
## when a camera exists) plus short sparks up off the beads.
func _draw_arcs(charge: float) -> void:
	var im: ImmediateMesh = _arcs.mesh
	im.clear_surfaces()
	if _beads.size() < 2:
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var to_cam := Vector3(0.3, 1.0, 0.3).normalized()
	if cam != null:
		to_cam = (skeleton.global_transform.affine_inverse() * cam.global_position - bead_pos(0)).normalized()
	var pts: Array[Vector3] = []
	for i in _beads.size():
		pts.append(bead_pos(i))
	var n_arcs := 3 + int(round(3.0 * charge))
	var width := 0.09 + 0.06 * charge
	var col := CHARGE_COLOR
	col.a = 0.85
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in n_arcs:
		var i := _arc_rng.randi_range(0, pts.size() - 1)
		var j := i
		var tries := 0
		while (j == i or pts[i].distance_to(pts[j]) > 2.6) and tries < 8:
			j = _arc_rng.randi_range(0, pts.size() - 1)
			tries += 1
		if j == i:
			continue
		var prev := pts[i]
		var segs := 5
		for k in range(1, segs + 1):
			var t := float(k) / float(segs)
			var p := pts[i].lerp(pts[j], t)
			if k < segs:
				p += Vector3(_arc_rng.randf_range(-1, 1), _arc_rng.randf_range(-0.6, 1.2), _arc_rng.randf_range(-1, 1)) * 0.16
			_ribbon(im, prev, p, to_cam, width, col)
			prev = p
	for s in 2 + int(round(2.0 * charge)):
		var i := _arc_rng.randi_range(0, pts.size() - 1)
		var up := Vector3(_arc_rng.randf_range(-0.4, 0.4), 1.0, _arc_rng.randf_range(-0.4, 0.4)).normalized()
		_ribbon(im, pts[i], pts[i] + up * _arc_rng.randf_range(0.25, 0.6), to_cam, width * 0.7, Color(0.95, 0.8, 1.0, 0.9))
	im.surface_end()


func _ribbon(im: ImmediateMesh, a: Vector3, b: Vector3, to_cam: Vector3, w: float, col: Color) -> void:
	var d := b - a
	if d.length_squared() < 1e-6:
		return
	var side := d.cross(to_cam).normalized() * (w * 0.5)
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		im.surface_set_color(col)
		im.surface_add_vertex(v)


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
