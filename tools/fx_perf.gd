extends SceneTree
## Lane FX perf check: a real windowed fight on a biome for `--seconds`
## (default 12), vsync off, the brain left to attack the hunter, with the
## arena's point lights (R-ENV1) and every effect live; every 2 s the tool
## fires one extra big wind-up (the monster's widest attack) so four effects
## overlap. Prints average / 1 %-low frame rate, the point-light count and
## the peak sprite count.
##   godot --path . --script res://tools/fx_perf.gd -- --arena cave --fight rimeslithe

var arena := "cave"
var monster := "rimeslithe"
var seconds := 12.0
var f: HHFight
var t := 0.0
var frames: Array = []
var peak := 0
var next_big := 2.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--arena": arena = args[i + 1]
			"--fight": monster = args[i + 1]
			"--seconds": seconds = float(args[i + 1])
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	f = HHFight.new()
	f.setup_cfg({ "arena": arena, "monster": monster, "weapon": "lance", "seed": 2, "cam": "30,44" })
	root.add_child(f)
	if "--no-points" in args:
		for c in f.view.get_children():
			if c is OmniLight3D:
				c.queue_free()
	if "--no-fx" in args:
		f.view.fxl.enabled = false


func _process(delta: float) -> bool:
	t += delta
	if t > 1.0:
		frames.append(delta)
		peak = maxi(peak, f.view.fxl.sprite_count())
	if t >= next_big:
		next_big += 2.0
		var b: Object = f.sim.brains.get(monster)
		var u := f.sim.unit(monster)
		var p := f.sim.unit("p1")
		var big := { "rimeslithe": "_mist_wide", "colambros": "_back_roll", "swampfang": "_death_roll", "spirewalker": "_pollen" }
		var fn := str(big.get(monster, ""))
		if b != null and b.has_method(fn):
			if fn in ["_mist_wide", "_back_roll", "_death_roll", "_pollen"]:
				b.call(fn, f.sim, u)
			else:
				b.call(fn, f.sim, u, p)
	if t >= seconds:
		var sorted := frames.duplicate()
		sorted.sort()
		var avg := 0.0
		for d in frames:
			avg += float(d)
		avg /= maxf(1.0, float(frames.size()))
		var low: float = sorted[int(sorted.size() * 0.99)] if not sorted.is_empty() else 0.0
		var lights := f.view.find_children("*", "OmniLight3D", true, false).size()
		print("fx_perf: %s on %s: avg %.0f fps, 1%%-low %.0f fps, %d omni lights in the view, peak sprites %d, live effects %d" % [
			monster, arena, 1.0 / avg, 1.0 / maxf(low, 1e-4), lights, peak, f.view.fxl.effects.size()])
		quit(0)
	return false
