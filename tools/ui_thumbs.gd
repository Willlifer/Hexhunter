extends SceneTree
## Lobby / results thumbnails (Lane UI, H800): renders every registry id from
## the CURRENT assets and writes art/ui/thumbs/<kind>_<id>.png (500 x 280,
## twice the lobby tile). Rerun it after any monster, weapon or arena change:
##   godot --path . --script res://tools/ui_thumbs.gd [-- --only monster]
## Needs a window (not headless).
##   arena   : the biome's GKAsset through HHArenaView, a high three-quarter overview
##   monster : HHMonsterBody posed at its aggravated idle, front three-quarter, transparent
##   weapon  : the art/weapons glb laid on the diagonal, transparent
## Transparent thumbs sit on the tile's own tint; the arena ones are opaque.

const OUT := "res://art/ui/thumbs"
const SIZE := Vector2i(500, 280)
const ARENA_DIST := 74.0          # metres: the 35 m arena and its rim fill the frame at fov 30
const DARK_MEAN := 0.22           # an arena thumb darker than this mean luminance is lifted (the cave)
const WEAPON_GLB := { "lance": "lance", "daggers": "karambit", "bow": "bow" }

var only := ""
var world: Node3D
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	root.size = SIZE
	root.transparent_bg = true
	_run.call_deferred()


func _run() -> void:
	var abs := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(abs)
	var n := 0
	if only == "" or only == "arena":
		for r in HHRegistry.ARENAS:
			await _arena(str(r.id), abs)
			n += 1
	if only == "" or only == "monster":
		for r in HHRegistry.MONSTERS:
			await _monster(str(r.id), abs)
			n += 1
	if only == "" or only == "weapon":
		for r in HHRegistry.WEAPONS:
			await _weapon(str(r.id), abs)
			n += 1
	print("ui_thumbs: %d thumbnails -> %s" % [n, abs])
	quit(0)


func _fresh_world(studio: bool) -> void:
	if world != null:
		world.queue_free()
		await process_frame
	world = Node3D.new()
	root.add_child(world)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.1
	cam.far = 600.0
	world.add_child(cam)
	cam.make_current()
	if studio:
		var we := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.62, 0.66, 0.74)
		e.ambient_light_energy = 0.7
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment = e
		world.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
		key.light_energy = 1.5
		world.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-15.0, -150.0, 0.0)
		rim.light_energy = 0.9
		rim.light_color = Color(1.0, 0.9, 0.75)
		world.add_child(rim)


func _arena(id: String, abs: String) -> void:
	root.transparent_bg = false
	await _fresh_world(false)
	var loaded := HHRegistry.load_arena(id, 1)
	var view := HHArenaView.new()
	world.add_child(view)
	view.build(loaded.arena, loaded.asset)
	if view.true_hex != null:
		view.true_hex.visible = false
	_aim(Vector3(0, 0, 0), 32.0, 52.0, ARENA_DIST)
	await _save(abs.path_join("arena_%s.png" % id), true)


func _monster(id: String, abs: String) -> void:
	root.transparent_bg = true
	await _fresh_world(true)
	var body := HHHuntKit.monster_body(id)
	world.add_child(body)
	if body.has_method("pose_at"):
		body.pose_at("aggravated_idle", 0.8)
	await process_frame
	var box := _bounds(body)
	_frame(box, 35.0, 14.0, 0.52)
	await _save(abs.path_join("monster_%s.png" % id))


func _weapon(id: String, abs: String) -> void:
	root.transparent_bg = true
	await _fresh_world(true)
	var path := "res://art/weapons/%s.glb" % str(WEAPON_GLB.get(id, id))
	if not ResourceLoader.exists(path):
		print("ui_thumbs: no glb for weapon ", id)
		return
	var ps: PackedScene = load(path)
	var w: Node3D = ps.instantiate()
	var pivot := Node3D.new()
	world.add_child(pivot)
	pivot.add_child(w)
	_colour(w)
	pivot.rotation_degrees = Vector3(-62.0, 0, 0)     # +Y (the shaft) leans across the frame seen from +X (the flat side)
	if id == "daggers":                                # the pair: a mirrored twin beside the first
		var path_l := "res://art/weapons/karambit_l.glb"
		if ResourceLoader.exists(path_l):
			var w2: Node3D = (load(path_l) as PackedScene).instantiate()
			_colour(w2)
			var p2 := Node3D.new()
			world.add_child(p2)
			p2.add_child(w2)
			p2.rotation_degrees = Vector3(62.0, 0, 0)
			p2.position = Vector3(0, 0, 0.18)
	await process_frame
	var box := _bounds(world)
	_frame(box, 90.0, 6.0, 0.62)
	await _save(abs.path_join("weapon_%s.png" % id))


## Merged world AABB of every visible mesh under `n`.
func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var b := m.global_transform * m.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


## Point the camera at the box from yaw / pitch, far enough that the box fills
## `fill` of the frame (the bounding sphere against the narrower fov).
func _frame(box: AABB, yaw: float, pitch: float, fill: float) -> void:
	var c := box.get_center()
	var rad := box.size.length() * 0.5
	var dist := rad / sin(deg_to_rad(cam.fov) * 0.5) * fill     # the bounding sphere fits the frame's height
	_aim(c, yaw, pitch, dist)


func _aim(target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	cam.position = target + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.look_at(target, Vector3.UP)


func _save(path: String, lift_dark: bool = false) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img.get_size() != SIZE:                         # the project's stretch keeps the window at 1600 x 900
		img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	if lift_dark:
		_lift(img)
	var err := img.save_png(path)
	print("ui_thumbs: %s (%s)" % [path, "ok" if err == OK else error_string(err)])


## A dark render (the cave) is lifted with a gamma curve until its mean
## luminance reads on a lobby tile; brighter ones pass untouched.
func _lift(img: Image) -> void:
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	var mean := sum / maxf(1.0, float(n))
	if mean >= DARK_MEAN or mean <= 0.001:
		return
	var g := clampf(log(DARK_MEAN) / log(mean), 0.3, 1.0)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(pow(c.r, g), pow(c.g, g), pow(c.b, g), c.a))


## The weapon glbs carry their colours as vertex COLOR (Lane A): one role
## material per surface, as tools/weapon_preview.gd does.
func _colour(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for i in m.mesh.get_surface_count():
			var role := str(m.mesh.surface_get_name(i))
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.35 if role == "steel" else 0.8
			mat.metallic = 0.55 if role == "steel" else 0.0
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.set_surface_override_material(i, mat)
