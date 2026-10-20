extends SceneTree
## Review renders of the weapons (Lane A): each weapon at three angles with
## its manifest markers drawn (tip red, trail_base blue, second_hand green,
## string ends yellow), plus a "gauntlet" sheet of every weapon side by side
## with the 2.2 m player capsule for scale. Needs a window (not headless):
##   godot --path . --script res://tools/weapon_preview.gd [-- --out design/art/weapons --only karambit,bow]
## Writes <out>/<id>_<view>.png and <out>/gauntlet.png, then quits.

const MANIFEST := "res://art/weapons/weapons.json"
const VIEWS := [
	{ "name": "front34", "yaw": 35.0, "pitch": 14.0 },
	{ "name": "side", "yaw": 90.0, "pitch": 4.0 },
	{ "name": "back34", "yaw": 215.0, "pitch": 20.0 },
]
## The gauntlet sheet: id, x position; the off-hand karambit beside the right one
const SHEET := [
	{ "id": "lance", "x": -2.6 },
	{ "id": "karambit", "x": -1.0 },
	{ "id": "karambit_l", "x": -0.1 },
	{ "id": "bow", "x": 1.4 },
	{ "id": "arrow", "x": 2.5 },
]

var out_dir := "design/art/weapons"
var only: PackedStringArray = []
var cam: Camera3D
var world: Node3D
var stage: Node3D
var manifest := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
	root.size = Vector2i(1280, 800)
	_build.call_deferred()


func _build() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		print("weapon_preview: no manifest at ", MANIFEST)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	manifest = (parsed as Dictionary).get("weapons", {}) if parsed is Dictionary else {}
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.42, 0.62)
	sm.sky_horizon_color = Color(0.62, 0.66, 0.74)
	sm.ground_bottom_color = Color(0.22, 0.24, 0.24)
	sm.ground_horizon_color = Color(0.50, 0.52, 0.52)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, 30.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -150.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.85, 0.88, 1.0)
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.44, 0.40)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	world.add_child(_hex_grid(6))
	stage = Node3D.new()
	world.add_child(stage)
	cam = Camera3D.new()
	cam.fov = 32.0
	cam.near = 0.05
	cam.far = 200.0
	world.add_child(cam)
	cam.make_current()
	_shoot_all()


func _hex_grid(r: int) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.24, 0.27, 0.24)
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	for h in HHHex.area(Vector2i.ZERO, r):
		var w := HHHex.to_world(h, 1.0)
		var cs := HHHex.corners(Vector3(w.x, 0.01, w.y), 1.0)
		for i in 6:
			im.surface_add_vertex(cs[i])
			im.surface_add_vertex(cs[(i + 1) % 6])
	im.surface_end()
	mi.mesh = im
	return mi


## A role material (HHMonsterBody.material_for's pattern): vertex COLOR as albedo.
static func material_for(role: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	match role:
		"steel":
			m.roughness = 0.35
			m.metallic = 0.55
			m.metallic_specular = 0.6
		"gem":
			m.roughness = 0.18
			m.metallic = 0.2
		"feather":
			m.roughness = 0.8
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"string":
			m.roughness = 0.9
		_:
			m.roughness = 0.85
	m.resource_name = "hh_" + role
	return m


static func surface_role(mesh: Mesh, i: int) -> String:
	var mat := mesh.surface_get_material(i)
	var n := mat.resource_name if mat else ""
	if n == "" and mesh is ArrayMesh:
		n = (mesh as ArrayMesh).surface_get_name(i)
	return n


## Instance a weapon glb and dress its surfaces by role. Null when missing.
static func instance(id: String) -> Node3D:
	var path := "res://art/weapons/%s.glb" % id
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	var n := scene.instantiate() as Node3D
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, material_for(surface_role(m.mesh, i)))
	return n


static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _marker(p: Vector3, color: Color, r: float = 0.03) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = p
	return mi


func _markers(id: String, parent: Node3D) -> void:
	var row: Dictionary = manifest.get(id, {})
	if row.is_empty():
		return
	parent.add_child(_marker(Vector3.ZERO, Color(1, 1, 1), 0.025))
	parent.add_child(_marker(v3(row.tip), Color(1, 0.15, 0.15)))
	parent.add_child(_marker(v3(row.trail_base), Color(0.2, 0.4, 1.0)))
	var sh: Variant = row.get("second_hand")
	if sh is Dictionary:
		parent.add_child(_marker(v3((sh as Dictionary).point), Color(0.2, 1.0, 0.3)))
	if row.has("string"):
		for p in row.string:
			parent.add_child(_marker(v3(p), Color(1.0, 0.9, 0.2), 0.024))


func _aim(target: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> void:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func _clear_stage() -> void:
	for c in stage.get_children():
		stage.remove_child(c)
		c.queue_free()


func _shoot_all() -> void:
	var abs := ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs)
	var ids: Array = manifest.keys()
	for id in ids:
		if not only.is_empty() and not id in only:
			continue
		var row: Dictionary = manifest[id]
		var lo := v3(row.aabb.min)
		var hi := v3(row.aabb.max)
		var centre := (lo + hi) * 0.5
		var extent := (hi - lo).length()
		_clear_stage()
		var w := instance(id)
		if w == null:
			print("weapon_preview: missing ", id)
			continue
		# stand it upright on the ground, grip origin above the floor
		var holder := Node3D.new()
		holder.position = Vector3(0, -lo.y + 0.05, 0)
		stage.add_child(holder)
		holder.add_child(w)
		_markers(id, holder)
		for v in VIEWS:
			_aim(centre + holder.position, float(v.yaw), float(v.pitch), extent * 1.55 + 0.6)
			await _save(abs.path_join("%s_%s.png" % [id, v.name]))
	# the gauntlet sheet
	_clear_stage()
	for s in SHEET:
		var id := str(s.id)
		var base_id := id.trim_suffix("_l")
		var w := instance(id)
		if w == null or not manifest.has(base_id):
			continue
		var lo := v3(manifest[base_id].aabb.min)
		var holder := Node3D.new()
		holder.position = Vector3(float(s.x), -lo.y + 0.02, 0.0)
		holder.rotation_degrees = Vector3(0.0, 90.0, 0.0)     # profile to the camera (blades and wings lie in the (f, u) plane)
		stage.add_child(holder)
		holder.add_child(w)
	var p := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = HHLook.RIG_HEIGHT
	p.mesh = cm
	p.position = Vector3(3.6, HHLook.RIG_HEIGHT * 0.5, 0.0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.92, 0.92, 0.9)
	p.material_override = pmat
	stage.add_child(p)
	_aim(Vector3(0.5, 1.3, 0.0), 12.0, 8.0, 10.5)
	await _save(abs.path_join("gauntlet.png"))
	print("weapon_preview: done -> ", abs)
	quit(0)


func _save(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("weapon_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
