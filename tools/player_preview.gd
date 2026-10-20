extends SceneTree
## Review renders of the player rig (Lane B): the rig with each weapon at
## idle, the key frame of six clips per weapon, and an 8-frame run strip,
## saved as PNGs, then quit. Needs a window (not headless):
##   godot --path . --script res://tools/player_preview.gd [-- --out design/art/player --weapons lance,daggers,bow --all]
## Writes <out>/<weapon>_<clip>.png and <out>/<weapon>_run_strip.png. The
## ground carries a 1 m hex grid; a 2.2 m pole stands beside the figure.

const SHOTS := {
	"lance": [
		{ "clip": "wield_idle", "yaw": 35.0, "pitch": 12.0 },
		{ "clip": "strike", "yaw": 60.0, "pitch": 10.0 },
		{ "clip": "plant", "yaw": 60.0, "pitch": 10.0 },
		{ "clip": "slam", "yaw": 35.0, "pitch": 16.0 },
		{ "clip": "guard", "yaw": 20.0, "pitch": 12.0 },
		{ "clip": "sweep", "yaw": 20.0, "pitch": 62.0, "dist": 7.0 },
	],
	"daggers": [
		{ "clip": "wield_idle", "yaw": 35.0, "pitch": 12.0 },
		{ "clip": "strike", "yaw": -35.0, "pitch": 26.0 },
		{ "clip": "dive", "yaw": 70.0, "pitch": 10.0 },
		{ "clip": "flourish", "yaw": 30.0, "pitch": 30.0 },
		{ "clip": "spin", "yaw": 40.0, "pitch": 14.0 },
		{ "clip": "jump_attack", "yaw": 40.0, "pitch": 14.0 },
	],
	"bow": [
		{ "clip": "wield_idle", "yaw": 35.0, "pitch": 12.0 },
		{ "clip": "strike", "yaw": 55.0, "pitch": 10.0 },
		{ "clip": "kneel_shot", "yaw": 55.0, "pitch": 10.0 },
		{ "clip": "draw", "yaw": 90.0, "pitch": 8.0 },
		{ "clip": "lob", "yaw": 60.0, "pitch": 12.0 },
		{ "clip": "volley", "yaw": 45.0, "pitch": 14.0 },
	],
}

var out_dir := "design/art/player"
var weapons: PackedStringArray = ["lance", "daggers", "bow"]
var all_clips := false
var body: HHPlayerBody
var cam: Camera3D
var world: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--weapons")
	if i >= 0 and i + 1 < args.size():
		weapons = args[i + 1].split(",")
	all_clips = args.has("--all")
	root.size = Vector2i(1100, 800)
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
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.52, 0.36)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	world.add_child(_hex_grid(5))
	# the 2.2 m scale pole
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = HHLook.RIG_HEIGHT
	pole.mesh = cm
	pole.position = Vector3(1.6, HHLook.RIG_HEIGHT * 0.5, -0.6)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.92, 0.92, 0.9)
	pole.material_override = pmat
	world.add_child(pole)
	body = HHPlayerBody.new()
	world.add_child(body)
	cam = Camera3D.new()
	cam.fov = 36.0
	cam.near = 0.1
	cam.far = 200.0
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


func _aim(yaw_deg: float, pitch_deg: float, dist: float = 6.2, lift: float = 1.05) -> void:
	var target := Vector3(0.0, lift, 0.0)
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func _shoot_all() -> void:
	var abs := ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(abs)
	for w in weapons:
		if not body.build(w):
			print("player_preview: no body for ", w)
			continue
		body.pose_at("idle", 1.0)
		_aim(35.0, 12.0)
		await _save(abs.path_join("%s_idle.png" % w))
		var shots: Array = SHOTS.get(w, [])
		if all_clips:
			shots = []
			for cname in HHPlayerBody.clips(w):
				shots.append({ "clip": cname, "yaw": 45.0, "pitch": 12.0 })
		for s in shots:
			var clip := str(s.clip)
			var key := float(HHPlayerBody.clips(w).get(clip, {}).get("key", 0.0))
			body.pose_at(clip, key)
			_aim(float(s.yaw), float(s.pitch), float(s.get("dist", 6.2)))
			await _save(abs.path_join("%s_%s.png" % [w, clip]))
		await _run_strip(abs.path_join("%s_run_strip.png" % w))
	print("player_preview: done -> ", abs)
	quit(0)


## Eight frames of the run cycle from the side, stitched into one strip.
func _run_strip(path: String) -> void:
	var d := body.duration("run")
	var tiles: Array[Image] = []
	for k in 8:
		body.pose_at("run", d * float(k) / 8.0)
		_aim(90.0, 6.0, 5.6, 1.0)
		tiles.append(await _grab())
	var w := tiles[0].get_width()
	var h := tiles[0].get_height()
	var crop_w := int(w * 0.42)
	var x0 := (w - crop_w) / 2
	var strip := Image.create(crop_w * 8, h, false, tiles[0].get_format())
	for k in 8:
		strip.blit_rect(tiles[k], Rect2i(x0, 0, crop_w, h), Vector2i(crop_w * k, 0))
	var err := strip.save_png(path)
	print("player_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])


func _grab() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func _save(path: String) -> void:
	var img := await _grab()
	var err := img.save_png(path)
	print("player_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
