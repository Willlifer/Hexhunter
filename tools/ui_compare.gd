extends SceneTree
## Gauntlet comparison image for the HUD (Lane UI, BRIEF.md step 1): the
## reference on the left, a real fight frame on the right at the same height,
## and under them both action bars cropped and blown up to one height.
##   godot --headless --path . --script res://tools/ui_compare.gd -- --shot <frame.png> --out <out.png>
##     [--ref design/kickoff/ref/ui_hud.jpg] [--bar x,y,w,h]   (the frame's bar crop; default: the bottom centre)
## Image ops only, so it runs headless.

const ROW_H := 450
const BAR_H := 200
const GAP := 12
const REF_BAR := Rect2i(196, 286, 258, 55)      # the reference's skill bar and orb
const BG := Color(0.08, 0.08, 0.09)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var ref_path := _arg(args, "--ref", "res://design/kickoff/ref/ui_hud.jpg")
	var shot_path := _arg(args, "--shot", "")
	var out_path := _arg(args, "--out", "design/visual_pass/UI/hud_compare.png")
	var ref := _load(ref_path)
	var shot := _load(shot_path)
	if ref == null or shot == null:
		print("ui_compare: could not load %s or %s" % [ref_path, shot_path])
		quit(1)
		return
	var bar := Rect2i(int(shot.get_width() * 0.5) - 470, shot.get_height() - 150, 940, 150)
	var b := _arg(args, "--bar", "")
	if b != "":
		var v := b.split(",")
		bar = Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
	var top_l := _scaled(ref, ROW_H)
	var top_r := _scaled(shot, ROW_H)
	var bot_l := _scaled(ref.get_region(REF_BAR), BAR_H)
	var bot_r := _scaled(shot.get_region(bar), BAR_H)
	var w := maxi(top_l.get_width() + GAP + top_r.get_width(), bot_l.get_width() + GAP + bot_r.get_width())
	var out := Image.create(w, ROW_H + GAP + BAR_H, false, Image.FORMAT_RGBA8)
	out.fill(BG)
	out.blit_rect(top_l, Rect2i(Vector2i.ZERO, top_l.get_size()), Vector2i(0, 0))
	out.blit_rect(top_r, Rect2i(Vector2i.ZERO, top_r.get_size()), Vector2i(top_l.get_width() + GAP, 0))
	out.blit_rect(bot_l, Rect2i(Vector2i.ZERO, bot_l.get_size()), Vector2i(0, ROW_H + GAP))
	out.blit_rect(bot_r, Rect2i(Vector2i.ZERO, bot_r.get_size()), Vector2i(bot_l.get_width() + GAP, ROW_H + GAP))
	var abs := out_path if out_path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var err := out.save_png(abs)
	print("ui_compare: %s (%s)" % [abs, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)


func _load(path: String) -> Image:
	if path == "":
		return null
	var p := path if path.begins_with("res://") or path.is_absolute_path() else "res://" + path
	var img := Image.load_from_file(ProjectSettings.globalize_path(p) if p.begins_with("res://") else p)
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _scaled(img: Image, h: int) -> Image:
	var out := img.duplicate() as Image
	var w := int(round(float(img.get_width()) * float(h) / float(img.get_height())))
	out.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return out


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback
