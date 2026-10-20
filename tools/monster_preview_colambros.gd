extends SceneTree
## Review renders of Colambros (a copy of tools/monster_preview.gd pointed at
## colambros, with its own clip shot list): a turntable (three angles) and
## every clip at its key moment, saved as PNGs, then quit. Needs a window:
##   godot --path . --script res://tools/monster_preview_colambros.gd [-- --out design/art/monsters]
## Writes <out>/colambros_<view|clip>.png. The player rig's height (2.2 m)
## stands beside the monster as a scale bar; the ground carries a 1 m hex grid.

const VIEWS := [
	{ "name": "view_front34", "yaw": 35.0, "pitch": 18.0 },
	{ "name": "view_side", "yaw": 90.0, "pitch": 10.0 },
	{ "name": "view_back34", "yaw": 150.0, "pitch": 24.0 },
]
const CLIP_SHOTS := [
	{ "clip": "calm_sprawl", "yaw": 50.0, "pitch": 24.0 },
	{ "clip": "quill_gnaw", "yaw": 120.0, "pitch": 30.0 },
	{ "clip": "aggravated_idle", "yaw": 35.0, "pitch": 18.0 },
	{ "clip": "rattle_roar", "yaw": 40.0, "pitch": 14.0 },
	{ "clip": "walk", "yaw": 80.0, "pitch": 12.0 },
	{ "clip": "run", "yaw": 80.0, "pitch": 12.0 },
	{ "clip": "dirt_scrape", "yaw": 60.0, "pitch": 14.0 },
	{ "clip": "charge", "yaw": 70.0, "pitch": 10.0 },
	{ "clip": "tail_lash", "yaw": 20.0, "pitch": 55.0 },
	{ "clip": "bite", "yaw": 60.0, "pitch": 14.0 },
	{ "clip": "ember_spit", "yaw": 60.0, "pitch": 14.0 },
	{ "clip": "leap_stomp", "yaw": 50.0, "pitch": 18.0 },
	{ "clip": "back_roll", "yaw": 40.0, "pitch": 35.0 },
	{ "clip": "hit_react", "yaw": 35.0, "pitch": 18.0 },
	{ "clip": "stagger", "yaw": 60.0, "pitch": 14.0 },
	{ "clip": "collapse", "yaw": 60.0, "pitch": 18.0 },
	{ "clip": "death", "yaw": 40.0, "pitch": 30.0 },
	{ "clip": "bald_idle", "yaw": 35.0, "pitch": 18.0 },
]

var monster_id := "colambros"
var out_dir := "design/art/monsters"
var body: HHMonsterBody
var cam: Camera3D
var world: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--monster")
	if i >= 0 and i + 1 < args.size():
		monster_id = args[i + 1]
	i = args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	root.size = Vector2i(1280, 800)
	_build.call_deferred()


func _build() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.9)
	sm.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sm.ground_bottom_color = Color(0.25, 0.3, 0.25)
	sm.ground_horizon_color = Color(0.6, 0.65, 0.6)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.8, 0.85, 1.0)
	world.add_child(fill)
	# ground with a 1 m hex grid
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.52, 0.36)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	world.add_child(_hex_grid(9))
	# the scale bar: the player rig's capsule
	var p := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = HHLook.RIG_HEIGHT
	p.mesh = cm
	p.position = Vector3(3.6, HHLook.RIG_HEIGHT * 0.5, 2.6)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.92, 0.92, 0.9)
	p.material_override = pmat
	world.add_child(p)
	body = HHMonsterBody.new()
	world.add_child(body)
	if not body.build(monster_id):
		print("monster_preview: no body for ", monster_id)
		quit(1)
		return
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.1
	cam.far = 300.0
	world.add_child(cam)
	cam.make_current()
	_shoot_all()


func _hex_grid(r: int) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.2, 0.26, 0.18)
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	for h in HHHex.area(Vector2i.ZERO, r):
		var w := HHHex.to_world(h, 1.0)
		var cs := HHHex.corners(Vector3(w.x, 0.02, w.y), 1.0)
		for i in 6:
			im.surface_add_vertex(cs[i])
			im.surface_add_vertex(cs[(i + 1) % 6])
	im.surface_end()
	mi.mesh = im
	return mi


func _aim(yaw_deg: float, pitch_deg: float, dist: float = 15.0, lift: float = 1.3) -> void:
	var target := Vector3(0.0, lift, 0.0)
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func _shoot_all() -> void:
	var abs := ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs)
	for v in VIEWS:
		body.pose_at("aggravated_idle", 0.8)
		_aim(float(v.yaw), float(v.pitch))
		await _save(abs.path_join("%s_%s.png" % [monster_id, v.name]))
	for s in CLIP_SHOTS:
		var clip := str(s.clip)
		var key := float(HHMonsterBody.clips(monster_id).get(clip, {}).get("key", 0.0))
		body.pose_at(clip, key)
		_aim(float(s.yaw), float(s.pitch), float(s.get("dist", 15.0)))
		await _save(abs.path_join("%s_%s.png" % [monster_id, clip]))
	print("monster_preview: done -> ", abs)
	quit(0)


func _save(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("monster_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
