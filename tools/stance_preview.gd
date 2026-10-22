extends SceneTree
## Lane ST (H490-H499): the weapon stances' review renders. Builds the real
## HHPlayerBody per weapon in a fixed lit scene (ink on) and writes, per weapon:
##   <out>/<w>_stance.png        the idle at its key: front 3/4 | side | back 3/4 | the gameplay camera
##   <out>/<w>_breath.png        the idle loop at 0, 1/4, 1/2, 3/4 of its cycle, side by side (the breathing / weight shift)
##   <out>/<w>_into_attack.png   the idle played, then the first attack started through the real cross-fade (update())
##   <ref_out>/<tag>_<w>_gauntlet.png  (with --ref-dir) the reference image LEFT, the front 3/4 and side RIGHT
## The references are third-party art kept out of git: pass their folder with --ref-dir
## and keep --ref-out in a git-ignored folder (default design/art/shots/stances).
## Needs a window (not headless):
##   godot --path . --script res://tools/stance_preview.gd -- [--tag r1] [--out design/art/stances] [--ref-dir <folder>] [--weapons lance,daggers,bow]

const SHEET_H := 900
const REFS := { "lance": ["OIP.webp", "OIP (1).webp"], "daggers": ["OIP (2).webp"], "bow": ["OIP (3).webp"] }
const FIRST_ATTACK := { "lance": "combo_stab", "daggers": "combo_whirl", "bow": "strike" }

var out_dir := "design/art/stances"
var ref_out := "design/art/shots/stances"
var ref_dir := ""
var tag := "r0"
var weapons: PackedStringArray = ["lance", "daggers", "bow"]
var vp: SubViewport
var cam: Camera3D
var world: Node3D
var env: Environment
var body: HHPlayerBody


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for pair in [["--out", "out_dir"], ["--ref-out", "ref_out"], ["--ref-dir", "ref_dir"], ["--tag", "tag"]]:
		var i := args.find(pair[0])
		if i >= 0 and i + 1 < args.size():
			set(pair[1], args[i + 1])
	var j := args.find("--weapons")
	if j >= 0 and j + 1 < args.size():
		weapons = args[j + 1].split(",")
	root.size = Vector2i(640, 480)
	_build.call_deferred()


func _build() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(600, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	root.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.40, 0.42, 0.44)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.56)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.94, 0.86)
	key.shadow_enabled = true
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.8, 0.88, 1.0)
	world.add_child(rim)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.36, 0.30)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	body = HHPlayerBody.new()
	world.add_child(body)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 300.0
	world.add_child(cam)
	cam.current = true
	HHTune.set_value("ink_on", 1.0)
	await _shoot_all()


func _abs(dir: String, name: String) -> String:
	var d := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(d)
	return d.path_join(name)


func _shoot_all() -> void:
	for w in weapons:
		if not body.build(w):
			print("stance_preview: no body for ", w)
			continue
		body.set_suit_color(HHPlayerBody.suit_color_for("p1"))
		HHInk.sync(body.inks)
		var key := float(HHPlayerBody.clips(w).idle.key)
		body.pose_at("idle", key)
		var views: Array = []
		for yaw in [35.0, -90.0, 150.0]:
			_look(Vector3(0.0, 0.95, -0.3), yaw * (-1.0 if w == "lance" and absf(yaw) < 60.0 else 1.0), 1.3, 6.4, 34.0)
			views.append(await _grab())
		var game := await _game_view()
		_sheet(views + [game], _abs(out_dir, "%s_stance.png" % w))
		# the loop: four moments, front 3/4
		var d := body.duration("idle")
		var loop_tiles: Array = []
		for k in 4:
			body.pose_at("idle", d * float(k) / 4.0)
			_look(Vector3(0.0, 0.95, -0.3), -35.0 if w == "lance" else 35.0, 1.3, 6.4, 34.0)
			loop_tiles.append(_crop_centre(await _grab(), 0.8))
		_sheet(loop_tiles, _abs(out_dir, "%s_breath.png" % w))
		await _into_attack(w)
		if ref_dir != "":
			var tiles: Array = []
			for f in REFS.get(w, []):
				var im := Image.load_from_file(ref_dir.path_join(str(f)))
				if im != null and not im.is_empty():
					tiles.append(im)
			if not tiles.is_empty():
				_sheet(tiles + [views[0], views[1]], _abs(ref_out, "%s_%s_gauntlet.png" % [tag, w]))
	print("stance_preview: done -> ", _abs(out_dir, ""))
	quit(0)


## The gameplay camera (high, behind-right, far): how the stance reads in play.
func _game_view() -> Image:
	cam.fov = 40.0
	var pivot := Vector3(0.0, 1.1, 0.0)
	var yaw := deg_to_rad(200.0)
	var pitch := deg_to_rad(48.0)
	cam.position = pivot + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 9.0
	cam.look_at(pivot, Vector3.UP)
	return await _grab()


## The idle running, then the first attack through the body's own cross-fade:
## seven frames from the side the weapon is on.
func _into_attack(w: String) -> void:
	var atk := str(FIRST_ATTACK[w])
	body.clip = ""
	body.play("idle")
	for k in 30:
		body.update(1.0 / 30.0)
	body.play(atk, false)
	var tiles: Array = []
	var marks := [0.0, 0.05, 0.1, 0.17, 0.27, float(body.contact_time(atk)), float(body.contact_time(atk)) + 0.12]
	var t := 0.0
	for m in marks:
		while t < float(m) - 1e-4:
			body.update(1.0 / 60.0)
			t += 1.0 / 60.0
		_look(Vector3(0.0, 1.0, 0.3), -60.0, 1.3, 6.0, 36.0)
		tiles.append(_crop_centre(await _grab(), 0.85))
	_sheet(tiles, _abs(out_dir, "%s_into_attack.png" % w), 600)
	body.play("idle")
	for k in 60:                                   # let the swing ribbon die before the next weapon's frames
		body.update(1.0 / 30.0)


func _look(target: Vector3, yaw_deg: float, height: float, dist: float, fov: float) -> void:
	var y := deg_to_rad(yaw_deg)
	cam.fov = fov
	cam.position = Vector3(target.x + sin(y) * dist, height, target.z + cos(y) * dist)
	cam.look_at(target, Vector3.UP)


func _grab() -> Image:
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


func _crop_centre(img: Image, frac_w: float) -> Image:
	var w := int(img.get_width() * frac_w)
	var x0 := (img.get_width() - w) / 2
	return img.get_region(Rect2i(x0, 0, w, img.get_height()))


func _sheet(tiles: Array, path: String, h: int = SHEET_H) -> void:
	var scaled: Array[Image] = []
	var width := 0
	for t in tiles:
		var im: Image = (t as Image).duplicate()
		im.convert(Image.FORMAT_RGB8)
		im.resize(int(im.get_width() * float(h) / im.get_height()), h, Image.INTERPOLATE_LANCZOS)
		scaled.append(im)
		width += im.get_width() + 8
	var out := Image.create(width - 8, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.08, 0.08, 0.09))
	var x := 0
	for im in scaled:
		out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, 0))
		x += im.get_width() + 8
	var err := out.save_png(path)
	print("stance_preview: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
