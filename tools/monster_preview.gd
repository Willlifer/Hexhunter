extends SceneTree
## Review renders of a monster: a turntable (three angles) and its clips at
## their key moments, saved as PNGs, then quit. Needs a window (not headless):
##   godot --path . --script res://tools/monster_preview.gd [-- --monster swampfang --out design/art/monsters]
## Writes <out>/<id>_<view|clip>.png. The player rig's height (2.2 m) stands
## beside the monster as a scale bar; the ground carries a 1 m hex grid.

const VIEWS := [
	{ "name": "view_front34", "yaw": 35.0, "pitch": 18.0 },
	{ "name": "view_side", "yaw": 90.0, "pitch": 10.0 },
	{ "name": "view_back34", "yaw": 150.0, "pitch": 24.0 },
]
const CLIP_SHOTS := [
	{ "clip": "frill_roar", "yaw": 40.0, "pitch": 14.0 },
	{ "clip": "walk", "yaw": 70.0, "pitch": 14.0 },
	{ "clip": "dark_spray", "yaw": 45.0, "pitch": 16.0 },
	{ "clip": "death_roll_spin", "yaw": 30.0, "pitch": 28.0 },
	{ "clip": "dive", "yaw": 80.0, "pitch": 18.0 },
	{ "clip": "bite_back_miss", "yaw": 150.0, "pitch": 30.0 },
	{ "clip": "calm_float", "yaw": 50.0, "pitch": 22.0 },
	{ "clip": "thrash_splash", "yaw": 20.0, "pitch": 60.0 },
	{ "clip": "water_jet", "yaw": 60.0, "pitch": 14.0 },
	{ "clip": "surface_lunge", "yaw": 45.0, "pitch": 14.0 },
	{ "clip": "swim", "yaw": 30.0, "pitch": 55.0 },
	{ "clip": "aggravated_idle", "yaw": 35.0, "pitch": 18.0 },
	{ "clip": "hit_react", "yaw": 35.0, "pitch": 18.0 },
	{ "clip": "stagger", "yaw": 60.0, "pitch": 14.0 },
	{ "clip": "collapse", "yaw": 60.0, "pitch": 18.0 },
	{ "clip": "death", "yaw": 40.0, "pitch": 30.0 },
]

var monster_id := "swampfang"
var out_dir := "design/art/monsters"
var body: HHMonsterBody
var cam: Camera3D
var world: Node3D
var scale_bar: Node3D
var gauntlet := -1                 ## --gauntlet N: the Lane MB comparison round N only
var water := false                 ## --water: the pond stand-in shots only (Lane MB)
var only_clips: PackedStringArray = []   ## --clips a,b: just these clip shots (no views)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--monster")
	if i >= 0 and i + 1 < args.size():
		monster_id = args[i + 1]
	i = args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--gauntlet")
	if i >= 0 and i + 1 < args.size():
		gauntlet = int(args[i + 1])
	i = args.find("--clips")
	if i >= 0 and i + 1 < args.size():
		only_clips = args[i + 1].split(",")
	water = "--water" in args
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
	scale_bar = p
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
	if gauntlet >= 0:
		await _shoot_gauntlet()
		return
	if water:
		await _shoot_water()
		return
	for v in (VIEWS if only_clips.is_empty() else []):
		body.pose_at("aggravated_idle", 0.8)
		_aim(float(v.yaw), float(v.pitch))
		await _save(abs.path_join("%s_%s.png" % [monster_id, v.name]))
	for s in CLIP_SHOTS:
		var clip := str(s.clip)
		if not only_clips.is_empty() and not (clip in only_clips):
			continue
		var key := float(HHMonsterBody.clips(monster_id).get(clip, {}).get("key", 0.0))
		body.pose_at(clip, key)
		_aim(float(s.yaw), float(s.pitch), float(s.get("dist", 15.0)))
		await _save(abs.path_join("%s_%s.png" % [monster_id, clip]))
	print("monster_preview: done -> ", abs)
	quit(0)


## Lane MB gauntlet (design/visual_pass/BRIEF.md): the reference's pose and
## camera, no scale bar, saved as <id>_round<N>_render.png, then the
## comparison (reference left, render right) as <id>_round<N>.png in
## design/visual_pass/MB, plus the three turntable views for the round.
const GAUNTLET := { "clip": "dark_spray", "t": 1.3, "yaw": 70.0, "pitch": 8.0, "dist": 12.5, "lift": 1.7, "crop": [0.04, 0.12, 0.96, 0.88] }
const GAUNTLET_REF := "res://design/kickoff/ref/monster_swampfang.png"


func _shoot_gauntlet() -> void:
	var dir := ProjectSettings.globalize_path("res://design/visual_pass/MB").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	scale_bar.visible = false
	body.pose_at(str(GAUNTLET.clip), float(GAUNTLET.t))
	_aim(float(GAUNTLET.yaw), float(GAUNTLET.pitch), float(GAUNTLET.dist), float(GAUNTLET.lift))
	var ren := dir.path_join("%s_round%d_render.png" % [monster_id, gauntlet])
	await _save(ren)
	var cmp := load("res://tools/gauntlet_compare_mb.gd")
	var c: Array = GAUNTLET.crop
	var err: Error = cmp.compose(ProjectSettings.globalize_path(GAUNTLET_REF), ren,
		dir.path_join("%s_round%d.png" % [monster_id, gauntlet]), 600, Rect2(c[0], c[1], c[2] - c[0], c[3] - c[1]))
	print("monster_preview: gauntlet round %d (%s)" % [gauntlet, "ok" if err == OK else error_string(err)])
	scale_bar.visible = true
	for v in VIEWS:
		body.pose_at("aggravated_idle", 0.8)
		_aim(float(v.yaw), float(v.pitch))
		await _save(dir.path_join("%s_round%d_%s.png" % [monster_id, gauntlet, v.name]))
	quit(0)


## Lane MB: a pond stand-in (the floor dropped 3 m under a flat water
## plane at y = 0, the pond arena's surface height) for the submerged clips,
## at the gameplay camera (30 m, 44 deg, FOV 40) and in close-up.
const WATER_SHOTS := [
	{ "clip": "calm_float", "yaw": 35.0 }, { "clip": "swim", "yaw": 35.0 },
	{ "clip": "dive", "yaw": 80.0 }, { "clip": "surface_lunge", "yaw": 45.0 },
]


func _shoot_water() -> void:
	var dir := ProjectSettings.globalize_path("res://design/visual_pass/MB").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	for n in world.get_children():
		if n is MeshInstance3D and n != scale_bar:
			(n as Node3D).position.y -= 3.0
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	w.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.26, 0.42, 0.52, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.6
	w.material_override = m
	world.add_child(w)
	scale_bar.position.y = HHLook.RIG_HEIGHT * 0.5 - 0.6
	for s in WATER_SHOTS:
		var clip := str(s.clip)
		body.pose_at(clip, float(HHMonsterBody.clips(monster_id)[clip].key))
		cam.fov = 40.0
		_aim(float(s.yaw), 44.0, 30.0, 0.0)
		await _save(dir.path_join("%s_water_%s_far.png" % [monster_id, clip]))
		cam.fov = 38.0
		_aim(float(s.yaw), 24.0, 14.0, 0.5)
		await _save(dir.path_join("%s_water_%s_near.png" % [monster_id, clip]))
	quit(0)


func _save(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("monster_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
