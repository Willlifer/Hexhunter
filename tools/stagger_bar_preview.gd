extends "res://tools/feel_preview.gd"
## Lane SB (H513) review renders: the stagger bar on the monster plate and the
## topple on the body, through the real fight (feel_preview's harness: the
## pond, Swampfang held still). Needs a window (not headless):
##   godot --path . --script res://tools/stagger_bar_preview.gd [-- --out design/stagger_bar]
## Writes sb_filling.png (a water lance stringing basics, the bar part full),
## sb_topple.png (the frame it topples: the flash), sb_down.png (held in the
## slump, TOPPLED, the bar draining) and sb_up.png (standing again, empty).


func _initialize() -> void:
	super._initialize()
	if not "--out" in OS.get_cmdline_user_args():
		out_dir = "design/stagger_bar"


## The frame as feel_preview saves it, plus <key>_plate.png: the monster
## plate at full resolution, x2 (the bar is thin; the review needs to read it).
func _shot(f: HHFight, key: String) -> void:
	await _drawn()
	var img := root.get_viewport().get_texture().get_image()
	var w := img.get_width()
	var plate := img.get_region(Rect2i(int(w * 0.5) - 330, 0, 660, 96))
	plate.resize(1320, 192, Image.INTERPOLATE_LANCZOS)
	plate.save_png(_abs(out_dir).path_join(key + "_plate.png"))
	img.resize(SAVE.x, SAVE.y, Image.INTERPOLATE_LANCZOS)
	img.save_png(_abs(out_dir).path_join(key + ".png"))
	print("stagger_bar_preview: ", key)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	var f := _fight("lance")
	await process_frame
	if f.debug != null:
		f.debug.visible = false
	_place(f, 2)
	var sim := f.sim
	var m := sim.unit("swampfang")
	var p := sim.unit("p1")
	p.element = "water"
	await _settle(f)
	# string water basics until the bar is a good way up
	var orders := { "p1": { "target": "swampfang", "attack": true } }
	m.sbar = float(m.sbar_need) * 0.55
	for k in 140:
		_tick(f, orders if k == 0 else {})
		_frame(f, 22.0)
		await _drawn()
	await _shot(f, "sb_filling")
	# the hunter steps back from the string (the spray settles), then one fill tops it up: it topples
	p.attacking = false
	p.target = ""
	for k in 70:
		_tick(f)
		_frame(f, 22.0)
		await _drawn()
	m.sbar = float(m.sbar_need) - 0.01
	var shot_topple := false
	var down_at := -1
	for k in 400:
		if k == 1:
			sim.sbar_feed(m, 1.0, "basic")
		_tick(f)
		_frame(f, 22.0)
		await _drawn()
		if int(m.get("toppled", 0)) > 0 and not shot_topple:
			shot_topple = true
			down_at = k
			await _shot(f, "sb_topple")
		if down_at >= 0 and k == down_at + 50:
			await _shot(f, "sb_down")
		if down_at >= 0 and int(m.toppled) == 0 and k > down_at + 20:
			for j in 20:
				_tick(f)
				_frame(f, 22.0)
				await _drawn()
			await _shot(f, "sb_up")
			break
	print("stagger_bar_preview: done -> ", _abs(out_dir))
	quit(0)
