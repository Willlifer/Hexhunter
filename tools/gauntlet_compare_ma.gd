extends SceneTree
## Gauntlet comparison (design/visual_pass/BRIEF.md, Lane MA): the reference
## image on the LEFT, the render on the RIGHT, both scaled to the same height,
## one PNG. Headless is fine (pure Image work):
##   godot --headless --path . --script res://tools/gauntlet_compare_ma.gd -- \
##       --ref design/kickoff/ref/monster_colambros.png \
##       --render design/visual_pass/MA/colambros_r1_render.png \
##       --out design/visual_pass/MA/colambros_round1.png [--height 720] [--crop x,y,w,h]
## --crop cuts a region (pixels of the source) out of the reference first,
## for a sheet that shows more than one creature.

const GAP := 12


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ref_path := _arg(args, "--ref", "")
	var ren_path := _arg(args, "--render", "")
	var out_path := _arg(args, "--out", "")
	var h := int(_arg(args, "--height", "720"))
	if ref_path == "" or ren_path == "" or out_path == "":
		print("gauntlet_compare_ma: need --ref, --render and --out")
		quit(1)
		return
	var ref := _load(ref_path)
	var ren := _load(ren_path)
	if ref == null or ren == null:
		quit(1)
		return
	var crop := _arg(args, "--crop", "")
	if crop != "":
		var p := crop.split(",")
		ref = ref.get_region(Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
	ref = _fit(ref, h)
	ren = _fit(ren, h)
	var out := Image.create(ref.get_width() + GAP + ren.get_width(), h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.1, 0.1, 0.1))
	out.blit_rect(ref, Rect2i(Vector2i.ZERO, ref.get_size()), Vector2i.ZERO)
	out.blit_rect(ren, Rect2i(Vector2i.ZERO, ren.get_size()), Vector2i(ref.get_width() + GAP, 0))
	var abs := _abs(out_path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var err := out.save_png(abs)
	print("gauntlet_compare_ma: %s (%s)" % [abs, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)


func _arg(args: PackedStringArray, flag: String, def: String) -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


func _abs(p: String) -> String:
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _load(p: String) -> Image:
	var img := Image.load_from_file(_abs(p))
	if img == null or img.is_empty():
		print("gauntlet_compare_ma: cannot load ", p)
		return null
	img.convert(Image.FORMAT_RGB8)
	return img


func _fit(img: Image, h: int) -> Image:
	var w := maxi(1, int(round(float(img.get_width()) * float(h) / float(img.get_height()))))
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return img
