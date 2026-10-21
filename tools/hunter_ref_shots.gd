extends SceneTree
## Lane Y (H80-H85): the hunter reference gauntlet's fixed frames. Builds the
## real HHPlayerBody (and HHMonsterBody for the monster sheet) in a fixed
## lit scene, poses them deterministically, renders through a SubViewport and
## writes side-by-side sheets with the author's reference on the LEFT.
## Needs a window (not headless):
##   godot --path . --script res://tools/hunter_ref_shots.gd -- --tag r1 [--out design/art/hunter_ref] [--monsters]
## Writes <out>/<tag>_hero.png        reference | hero pose, front 3/4, ink on
##        <out>/<tag>_hero_noink.png  the same frame, ink off
##        <out>/<tag>_turn.png        reference | front | side | back (rest pose, ink on)
##        <out>/<tag>_game.png        gameplay camera mid-combo, ink on | ink off
##        <out>/<tag>_monsters.png    (--monsters) each monster: game cam on | off, close-up on | off
## The reference is design/art/hunter_ref/reference.jpg (a comic cover: kept
## under design/, which the export filter leaves out).

const REF := "res://design/art/hunter_ref/reference.jpg"
const SHEET_H := 1100
const MONSTERS := ["swampfang", "colambros", "spirewalker", "rimeslithe"]

var out_dir := "design/art/hunter_ref"
var tag := "r0"
var do_monsters := false
var vp: SubViewport
var cam: Camera3D
var world: Node3D
var env: Environment
var ground: MeshInstance3D
var body: HHPlayerBody
var monster: HHMonsterBody


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--tag")
	if i >= 0 and i + 1 < args.size():
		tag = args[i + 1]
	do_monsters = args.has("--monsters")
	root.size = Vector2i(640, 480)
	_build.call_deferred()


func _build() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(620, 1100)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	root.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.55, 0.52)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()           # warm key from the front-left, high
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	key.light_energy = 1.35
	key.light_color = Color(1.0, 0.92, 0.82)
	key.shadow_enabled = true
	world.add_child(key)
	var rim := DirectionalLight3D.new()           # cool rim from behind (the comic edge light)
	rim.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.8, 0.88, 1.0)
	world.add_child(rim)
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.26, 0.28)
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
	await _shoot_all()


func _abs(name: String) -> String:
	var d := ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(d)
	return d.path_join(name)


func _shoot_all() -> void:
	body.build("lance")
	body.set_suit_color(HHPlayerBody.suit_color_for("p1"))
	var refimg := Image.load_from_file(ProjectSettings.globalize_path(REF))
	# 1. hero pose, front 3/4, low comic angle
	env.background_color = Color(0.52, 0.30, 0.17)
	_hero_pose()
	_look(Vector3(-0.05, 1.12, 0.0), -22.0, 0.75, 4.7, 34.0)
	vp.size = Vector2i(620, 1100)
	_ink(1.0)
	var hero := await _grab()
	_sheet([refimg, hero], _abs("%s_hero.png" % tag))
	_ink(0.0)
	var hero_off := await _grab()
	_sheet([refimg, hero_off], _abs("%s_hero_noink.png" % tag))
	_ink(1.0)
	# 2. turnaround at rest (A-pose)
	env.background_color = Color(0.42, 0.40, 0.42)
	body.weapon_main.visible = false
	var turn: Array = [refimg]
	for yaw in [0.0, 90.0, 180.0]:
		body.reset_pose()
		_look(Vector3(0.0, 1.1, 0.0), yaw, 2.0, 6.6, 34.0)
		vp.size = Vector2i(520, 1100)
		turn.append(await _grab())
	body.weapon_main.visible = true
	_sheet(turn, _abs("%s_turn.png" % tag))
	# 3. gameplay camera mid-combo (the lance's spiral, hit 3, at contact), a monster in frame
	env.background_color = Color(0.36, 0.44, 0.36)
	monster = HHMonsterBody.new()
	world.add_child(monster)
	monster.build("swampfang")
	monster.position = Vector3(0.0, 0.0, 7.0)
	monster.rotation.y = PI
	monster.update(0.016)
	body.weapon_main.position = Vector3.ZERO
	var hit := "combo_spiral"
	body.pose_at(hit, body.contact_time(hit) * 0.85)
	vp.size = Vector2i(1920, 1080)
	_look_orbit(Vector3(0.0, 1.2, 2.0), deg_to_rad(200.0), deg_to_rad(48.0), 18.0, 40.0)
	var g_on := await _grab()
	_ink(0.0)
	var g_off := await _grab()
	_ink(1.0)
	var hp := cam.unproject_position(body.global_position + Vector3(0.0, 1.1, 0.0))
	_sheet([_crop_centre(g_on, 0.5), _crop_centre(g_off, 0.5), _crop_at(g_on, hp, 260), _crop_at(g_off, hp, 260)], _abs("%s_game.png" % tag), 900)
	if do_monsters:
		await _monster_sheet()
	print("hunter_ref_shots: done -> ", _abs(""))
	quit(0)


## The reference pose: weight on the left leg, left hand on the hip, the
## right hand resting on top of the weapon held upright (its butt on the
## ground), head up and turned a touch to her left.
func _hero_pose() -> void:
	var A := HHClipsShared.ANKLE_Y
	var pose := {
		"move:hips": Vector3(0.05, -0.015, 0.0),
		"hips": Vector3(0.0, -8.0, 7.0),
		"spine": Vector3(-2.0, 4.0, -5.0),
		"chest": Vector3(-4.0, 6.0, -6.0),
		"neck": Vector3(-4.0, 8.0, 3.0),
		"head": Vector3(-9.0, 10.0, 4.0),
		"foot_l": [Vector3(0.06, A, 0.02), 0.0],
		"foot_r": [Vector3(-0.26, A, 0.16), -4.0],
		"hand_l": HHClipsShared.hand(Vector3(0.25, 1.08, 0.05), "", null, Vector3(0.8, 1.3, -0.6)),
		"hand_r": HHClipsShared.hand(Vector3(-0.40, 1.68, 0.12), "", Basis.IDENTITY, Vector3(-1.0, 1.25, -0.2)),
	}
	body.clip = ""
	body._sample = {}
	body._ik = {}
	HHClipsShared.apply(body, pose)
	var s := { "bones": body._sample, "ik": body._ik, "nock": false }
	body._sample = {}
	body._ik = {}
	body._apply(s)
	if body.weapon_main != null:
		body.weapon_main.position = Vector3(0.0, -1.08, 0.0)     # the fist near the top: the butt rests on the ground


func _look(target: Vector3, yaw_deg: float, height: float, dist: float, fov: float) -> void:
	var y := deg_to_rad(yaw_deg)
	cam.fov = fov
	cam.position = Vector3(target.x + sin(y) * dist, height, target.z + cos(y) * dist)
	cam.look_at(target, Vector3.UP)


func _look_orbit(pivot: Vector3, yaw: float, pitch: float, dist: float, fov: float) -> void:
	cam.fov = fov
	cam.position = pivot + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(pivot, Vector3.UP)


func _monster_sheet() -> void:
	body.visible = false
	var rows: Array[Image] = []
	for id in MONSTERS:
		monster.queue_free()
		await process_frame
		monster = HHMonsterBody.new()
		world.add_child(monster)
		monster.build(id)
		monster.position = Vector3.ZERO
		monster.update(0.016)
		var h := float(monster.row.get("height", 4.0))
		var tiles: Array = []
		vp.size = Vector2i(1920, 1080)
		for close in [false, true]:
			for on in [1.0, 0.0]:
				_ink(on)
				monster.update(0.016)
				if close:
					_look(Vector3(0.0, h * 0.5, 0.0), 35.0, h * 0.55, h * 1.9, 40.0)
				else:
					_look_orbit(Vector3(0.0, 1.2, 0.0), deg_to_rad(35.0), deg_to_rad(48.0), 18.0, 40.0)
				var img := await _grab()
				tiles.append(_crop_centre(img, 0.42) if not close else _crop_centre(img, 0.6))
		_ink(1.0)
		var row := _row(tiles, 420)
		rows.append(row)
	var w := 0
	var hsum := 0
	for r in rows:
		w = maxi(w, r.get_width())
		hsum += r.get_height() + 8
	var sheet := Image.create(w, hsum, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.08, 0.08, 0.09))
	var yy := 0
	for r in rows:
		sheet.blit_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(0, yy))
		yy += r.get_height() + 8
	sheet.save_png(_abs("%s_monsters.png" % tag))
	print("hunter_ref_shots: ", _abs("%s_monsters.png" % tag))
	body.visible = true


func _ink(on: float) -> void:
	HHTune.set_value("ink_on", on)
	if body != null:
		HHInk.sync(body.inks)
	if monster != null and is_instance_valid(monster):
		HHInk.sync(monster.inks, monster.ink_scale)


func _grab() -> Image:
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


## A square around a screen point (the hunter at the gameplay camera), for a zoomed look.
func _crop_at(img: Image, p: Vector2, half: int) -> Image:
	var x0 := clampi(int(p.x) - half, 0, img.get_width() - half * 2)
	var y0 := clampi(int(p.y) - half, 0, img.get_height() - half * 2)
	return img.get_region(Rect2i(x0, y0, half * 2, half * 2))


func _crop_centre(img: Image, frac_w: float) -> Image:
	var w := int(img.get_width() * frac_w)
	var x0 := (img.get_width() - w) / 2
	return img.get_region(Rect2i(x0, 0, w, img.get_height()))


func _row(tiles: Array, h: int) -> Image:
	var scaled: Array[Image] = []
	var w := 0
	for t in tiles:
		var im: Image = (t as Image).duplicate()
		im.resize(int(im.get_width() * float(h) / im.get_height()), h, Image.INTERPOLATE_LANCZOS)
		scaled.append(im)
		w += im.get_width() + 8
	var out := Image.create(w - 8, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.08, 0.08, 0.09))
	var x := 0
	for im in scaled:
		out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, 0))
		x += im.get_width() + 8
	return out


func _sheet(tiles: Array, path: String, h: int = SHEET_H) -> void:
	var conv: Array = []
	for t in tiles:
		var im: Image = (t as Image).duplicate()
		im.convert(Image.FORMAT_RGB8)
		conv.append(im)
	var img := _row(conv, h)
	var err := img.save_png(path)
	print("hunter_ref_shots: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
