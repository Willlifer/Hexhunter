extends SceneTree
## Lane ENV gauntlet renders (H751): the reference photo on the left, the
## arena from a matching camera on the right, one PNG at the same height.
## Needs a window (not headless):
##   godot --path . --script res://tools/arena_compare.gd -- --arena pond --round 1
##   ... -- --arena all --round 2 [--out design/visual_pass/ENV] [--cam x,y,z,tx,ty,tz] [--fov 55] [--solo]
## Writes <out>/<arena>_round<N>.png (with --solo also <arena>_round<N>_render.png).
## The scene is lit exactly as the fight lights it (HHArenaStage sun + sky),
## plus the point lights the bench adds; the fight-side extras that live in
## the asset itself (glow quads, emissive roles) show in both.

const H := 640                       ## output height (px)
## Per arena: a camera placed like the photographer's. pond and glade stand
## on the shore / in the meadow at eye height, the cave stands low on the
## floor looking along it, the caldera is an aerial oblique over the rim.
const CAMS := {
	"pond": { "pos": [-3.0, 4.2, 22.5], "at": [1.0, -1.0, 2.0], "fov": 55.0 },
	"cave": { "pos": [-6.0, 2.6, 20.5], "at": [-14.0, 2.0, 2.0], "fov": 62.0 },
	"glade": { "pos": [2.0, 1.8, 19.0], "at": [0.0, 2.2, 0.0], "fov": 58.0 },
	"caldera": { "pos": [0.0, 52.0, 78.0], "at": [0.0, 0.0, -6.0], "fov": 50.0 },
}

var out_dir := "design/visual_pass/ENV"
var ids: PackedStringArray = []
var round_n := 1
var cam_override: Array = []
var fov_override := 0.0
var solo := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var arena := "all"
	for i in args.size():
		var v := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--arena": arena = v
			"--round": round_n = int(v)
			"--out": out_dir = v
			"--fov": fov_override = float(v)
			"--solo": solo = true
			"--cam":
				for s in v.split(","):
					cam_override.append(float(s))
	ids = HHArenaGens.ids() if arena == "all" else PackedStringArray([arena])
	_run.call_deferred()


func _run() -> void:
	var failed := 0
	for id in ids:
		if not await _one(id):
			failed += 1
	quit(0 if failed == 0 else 1)


func _one(id: String) -> bool:
	var ref_path := ProjectSettings.globalize_path("res://design/kickoff/ref/arena_%s.jpg" % id)
	var ref := Image.load_from_file(ref_path)
	if ref == null:
		push_error("arena_compare: no reference %s" % ref_path)
		return false
	var w := int(round(float(ref.get_width()) / float(ref.get_height()) * H))
	root.size = Vector2i(w, H)
	var world := Node3D.new()
	root.add_child(world)
	var p: Dictionary = (_params(id))
	var t0 := Time.get_ticks_msec()
	var both := HHArenaGens.build_both(id, p)
	var asset: GKAsset = both.asset
	world.add_child(asset.instantiate(false))
	world.add_child(HHArenaStage.sun(asset.lights))
	world.add_child(HHArenaStage.sky(asset.lights))
	for l in HHArenaStage.point_lights(asset):
		world.add_child(l)
	var cam := Camera3D.new()
	var spec: Dictionary = CAMS[id]
	cam.fov = fov_override if fov_override > 0.0 else float(spec.fov)
	cam.far = 600.0
	cam.near = 0.1
	world.add_child(cam)
	var cp: Array = spec.pos
	var ca: Array = spec.at
	if cam_override.size() == 6:
		cp = cam_override.slice(0, 3)
		ca = cam_override.slice(3, 6)
	cam.look_at_from_position(Vector3(cp[0], cp[1], cp[2]), Vector3(ca[0], ca[1], ca[2]), Vector3.UP)
	cam.make_current()
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	shot.convert(Image.FORMAT_RGB8)
	print("compare %s: tris=%d parts=%d build=%dms" % [id, asset.triangle_count(), asset.parts.size(), Time.get_ticks_msec() - t0])
	ref.convert(Image.FORMAT_RGB8)
	ref.resize(w, H, Image.INTERPOLATE_BILINEAR)
	var out := Image.create(w * 2 + 8, H, false, Image.FORMAT_RGB8)
	out.fill(Color(0.08, 0.08, 0.08))
	out.blit_rect(ref, Rect2i(0, 0, w, H), Vector2i.ZERO)
	out.blit_rect(shot, Rect2i(0, 0, w, H), Vector2i(w + 8, 0))
	var base := out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_dir)
	base = base.simplify_path()
	DirAccess.make_dir_recursive_absolute(base)
	var path := base.path_join("%s_round%d.png" % [id, round_n])
	var err := out.save_png(path)
	print("render: %s (%s)" % [path, "ok" if err == OK else error_string(err)])
	if solo:
		shot.save_png(base.path_join("%s_round%d_render.png" % [id, round_n]))
	world.queue_free()
	await process_frame
	return err == OK


## The committed arena's params (the default preset as shipped).
func _params(id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://arenas/%s.json" % id))
	if parsed is Dictionary and (parsed as Dictionary).has("gen"):
		return ((parsed as Dictionary).gen as Dictionary).params
	return HHArenaGens.make(id).preset("default")
