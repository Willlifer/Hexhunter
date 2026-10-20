extends SceneTree
## Review renders of Rimeslithe: three turntable views in aggravated_idle and
## every clip at its key moment (HHRimeslitheClips.CLIPS), saved as PNGs,
## then quit. Needs a window (not headless):
##   godot --path . --script res://tools/monster_preview_rimeslithe.gd [-- --out design/art/monsters]
## Writes <out>/rimeslithe_<view|clip>.png. The player rig's 2.2 m capsule
## stands beside it as a scale bar; the ground carries the 1 m hex grid. The
## camera sits farther back than monster_preview.gd (this one is 9.5 m long
## and 4.6 m tall with its crystals).

const VIEWS := [
	{ "name": "view_front34", "yaw": 35.0, "pitch": 16.0 },
	{ "name": "view_side", "yaw": 90.0, "pitch": 8.0 },
	{ "name": "view_back34", "yaw": 150.0, "pitch": 22.0 },
]
## The gauntlet shot (BRIEF.md): the reference's angle, aggravated_idle.
## `-- --gauntlet <png>` renders only this; `-- --only a,b` only those clips/views.
const GAUNTLET := { "clip": "aggravated_idle", "yaw": 90.0, "pitch": 4.0, "dist": 14.0, "lift": 2.2 }
const CLIP_SHOTS := [
	{ "clip": "calm_sit", "yaw": 50.0, "pitch": 14.0 },
	{ "clip": "frost_over", "yaw": 140.0, "pitch": 22.0 },
	{ "clip": "aggravated_idle", "yaw": 35.0, "pitch": 16.0 },
	{ "clip": "roar", "yaw": 40.0, "pitch": 12.0 },
	{ "clip": "walk", "yaw": 75.0, "pitch": 10.0 },
	{ "clip": "frost_beam", "yaw": 60.0, "pitch": 12.0 },
	{ "clip": "cold_slam", "yaw": 30.0, "pitch": 18.0 },
	{ "clip": "shoulder_charge", "yaw": 50.0, "pitch": 14.0 },
	{ "clip": "bite", "yaw": 65.0, "pitch": 10.0 },
	{ "clip": "arm_swipe", "yaw": 20.0, "pitch": 30.0 },
	{ "clip": "mist_breath", "yaw": 55.0, "pitch": 12.0 },
	{ "clip": "meteor_drop", "yaw": 250.0, "pitch": 18.0 },
	{ "clip": "freeze_pillar", "yaw": 60.0, "pitch": 14.0 },
	{ "clip": "hit_react", "yaw": 35.0, "pitch": 16.0 },
	{ "clip": "stagger", "yaw": 60.0, "pitch": 12.0 },
	{ "clip": "collapse", "yaw": 60.0, "pitch": 18.0 },
	{ "clip": "death", "yaw": 40.0, "pitch": 30.0 },
]

var monster_id := "rimeslithe"
var out_dir := "design/art/monsters"
var gauntlet_path := ""
var only: PackedStringArray = []
var body: HHMonsterBody
var cam: Camera3D
var world: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--gauntlet")
	if i >= 0 and i + 1 < args.size():
		gauntlet_path = args[i + 1]
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
	root.size = Vector2i(1280, 800)
	_build.call_deferred()


func _build() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.42, 0.62)
	sm.sky_horizon_color = Color(0.7, 0.76, 0.84)
	sm.ground_bottom_color = Color(0.2, 0.22, 0.25)
	sm.ground_horizon_color = Color(0.5, 0.52, 0.56)
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
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.8, 0.88, 1.0)
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.38, 0.4)          # cave stone
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	world.add_child(_hex_grid(10))
	var p := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = HHLook.RIG_HEIGHT
	p.mesh = cm
	p.position = Vector3(4.2, HHLook.RIG_HEIGHT * 0.5, 3.2)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.92, 0.92, 0.9)
	p.material_override = pmat
	world.add_child(p)
	body = HHMonsterBody.new()
	world.add_child(body)
	if not body.build(monster_id):
		print("monster_preview_rimeslithe: no body for ", monster_id)
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
	m.albedo_color = Color(0.2, 0.22, 0.24)
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


func _aim(yaw_deg: float, pitch_deg: float, dist: float = 19.0, lift: float = 1.8) -> void:
	var target := Vector3(0.0, lift, 0.0)
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func _shoot_all() -> void:
	var abs := ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs)
	if gauntlet_path != "":
		var g := ProjectSettings.globalize_path("res://").path_join(gauntlet_path).simplify_path()
		DirAccess.make_dir_recursive_absolute(g.get_base_dir())
		var gk := float(HHMonsterBody.clips(monster_id).get(str(GAUNTLET.clip), {}).get("key", 0.0))
		body.pose_at(str(GAUNTLET.clip), gk)
		_aim(float(GAUNTLET.yaw), float(GAUNTLET.pitch), float(GAUNTLET.dist), float(GAUNTLET.lift))
		await _save(g)
		quit(0)
		return
	for v in VIEWS:
		if not only.is_empty() and not str(v.name) in only:
			continue
		body.pose_at("aggravated_idle", 0.8)
		_aim(float(v.yaw), float(v.pitch))
		await _save(abs.path_join("%s_%s.png" % [monster_id, v.name]))
	for s in CLIP_SHOTS:
		var clip := str(s.clip)
		if not only.is_empty() and not clip in only:
			continue
		var key := float(HHMonsterBody.clips(monster_id).get(clip, {}).get("key", 0.0))
		body.pose_at(clip, key)
		_aim(float(s.yaw), float(s.pitch), float(s.get("dist", 19.0)))
		await _save(abs.path_join("%s_%s.png" % [monster_id, clip]))
	print("monster_preview_rimeslithe: done -> ", abs)
	quit(0)


func _save(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("monster_preview_rimeslithe: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
