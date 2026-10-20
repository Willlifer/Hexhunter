extends SceneTree
## Gauntlet comparison image (Lane MB, design/visual_pass/BRIEF.md): the
## reference on the left, the render on the right, both scaled to the same
## height, one PNG. Runs headless:
##   godot --headless --path . --script res://tools/gauntlet_compare_mb.gd -- --ref <png> --render <png> --out <png> [--height 600] [--crop x0,y0,x1,y1]
## `--crop` (fractions 0..1 of the render) trims the render to the monster
## before scaling. The preview tools call compose() directly.

const GAP := 12
const BG := Color(0.12, 0.12, 0.13)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ref := _arg(args, "--ref", "")
	var ren := _arg(args, "--render", "")
	var out := _arg(args, "--out", "")
	var h := int(_arg(args, "--height", "600"))
	var crop := Rect2(0, 0, 1, 1)
	var c := _arg(args, "--crop", "")
	if c != "":
		var p := c.split(",")
		crop = Rect2(float(p[0]), float(p[1]), float(p[2]) - float(p[0]), float(p[3]) - float(p[1]))
	if ref == "" or ren == "" or out == "":
		print("gauntlet_compare_mb: need --ref --render --out")
		quit(1)
		return
	var err := compose(_abs(ref), _abs(ren), _abs(out), h, crop)
	print("gauntlet_compare_mb: %s (%s)" % [out, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)


static func _arg(args: PackedStringArray, flag: String, def: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


static func _abs(p: String) -> String:
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


## Reference left, render right (cropped by `crop`, fractions), same height.
static func compose(ref_path: String, render_path: String, out_path: String, height: int = 600, crop: Rect2 = Rect2(0, 0, 1, 1)) -> Error:
	var a := Image.load_from_file(ref_path)
	var b := Image.load_from_file(render_path)
	if a == null or b == null or a.is_empty() or b.is_empty():
		return ERR_FILE_NOT_FOUND
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	if crop != Rect2(0, 0, 1, 1):
		var r := Rect2i(int(crop.position.x * b.get_width()), int(crop.position.y * b.get_height()),
			int(crop.size.x * b.get_width()), int(crop.size.y * b.get_height()))
		b = b.get_region(r)
	a.resize(int(round(a.get_width() * float(height) / a.get_height())), height, Image.INTERPOLATE_LANCZOS)
	b.resize(int(round(b.get_width() * float(height) / b.get_height())), height, Image.INTERPOLATE_LANCZOS)
	var w := a.get_width() + GAP + b.get_width()
	var img := Image.create(w, height, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	img.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	img.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width() + GAP, 0))
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	return img.save_png(out_path)
