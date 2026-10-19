extends Node
## Entry point. User args (after `--`):
##   --self-test                run every tests/test_*.gd and exit (0 = green);
##                              report at user://self_test_report.json
##   --seed N                   the sim's seed (default 1)
##   --arena <id>               round (default) or arenas/<id>.json (rebuilt through
##                              its generator when the file carries a "gen" block)
##   --fight <monster>          put a monster in the arena (Lane E's brain and body
##                              when src/monster/<monster>.gd exists, else the stub)
##   --sandbox                  H20: left-click paints, keys 1-7 pick the element
##   --autoplay [--seconds s]   scripted run, then quit (the smoke test)
##   --shot <dir> [--count n] [--every s]   save n rendered frames to <dir>, then quit
##   --cam dist,pitch           start the camera at this distance (m) and pitch (deg)
##   --tune key=value           override one HHTune number this run (repeatable)
##   --bench                    Lane C's arena bench (src/arena/bench/bench.gd)
## With no args (a double-clicked exe) it opens the pond fight with Swampfang, wide view.

const REPORT_PATH := "user://self_test_report.json"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--tune" and i + 1 < args.size():
			var kv := args[i + 1].split("=")
			if kv.size() == 2:
				HHTune.set_value(kv[0], float(kv[1]))
	if "--self-test" in args:
		_self_test.call_deferred()
		return
	if "--bench" in args:
		if ResourceLoader.exists("res://src/arena/bench/bench.gd"):
			var s: GDScript = load("res://src/arena/bench/bench.gd")
			s.open(get_tree())
		else:
			push_error("boot: no bench yet (src/arena/bench/bench.gd)")
			get_tree().quit(2)
		return
	if args.is_empty():                                             # double-clicked: the fight, wide view
		args = PackedStringArray(["--arena", "pond", "--fight", "swampfang", "--cam", "30,44"])
	var seed := int(_arg(args, "--seed", "1"))
	var loaded := _load_arena(_arg(args, "--arena", "round"), seed)
	var fight := HHFight.new()
	fight.name = "Fight"
	fight.sandbox = "--sandbox" in args
	fight.autoplay = "--autoplay" in args or "--shot" in args
	if "--seconds" in args:
		fight.autoplay_seconds = float(_arg(args, "--seconds", "14"))
	if "--shot" in args:
		fight.autoplay_seconds = maxf(fight.autoplay_seconds, float(_arg(args, "--count", "6")) * float(_arg(args, "--every", "1.5")) + 1.0)
	add_child(fight)
	fight.setup(loaded.arena, seed, _arg(args, "--fight", ""), loaded.asset)
	if "--cam" in args:
		var cp := _arg(args, "--cam", "18,48").split(",")
		if cp.size() == 2:
			fight.camera.dist = float(cp[0])
			fight.camera.pitch = deg_to_rad(float(cp[1]))
	if "--shot" in args:
		var cap := HHCapture.new()
		cap.out_dir = _arg(args, "--shot", "design/art/shots")
		cap.every = float(_arg(args, "--every", "1.5"))
		cap.count = int(_arg(args, "--count", "6"))
		add_child(cap)


## { arena: HHArena, asset: GKAsset | null }. A JSON with a "gen" block is
## rebuilt through src/arena/gen/<id>_gen.gd (build_both(params)) when that
## script exists, so the mesh matches the underlay; else the JSON's cells
## are used with the plain floor.
func _load_arena(id: String, seed: int) -> Dictionary:
	var path := "res://arenas/%s.json" % id
	if id != "round" and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var d: Dictionary = parsed
			if d.has("gen"):
				var gen: Dictionary = d.gen
				var gp := "res://src/arena/gen/%s_gen.gd" % str(gen.get("id", id))
				if ResourceLoader.exists(gp):
					var s: GDScript = load(gp)
					var both: Dictionary = s.build_both(gen.get("params", {}))
					return { "arena": both.arena, "asset": both.asset }
			return { "arena": HHArena.from_dict(d), "asset": null }
		push_warning("boot: arena '%s' failed to parse, using round" % id)
	return { "arena": HHArena.round_flat(seed), "asset": null }


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func _self_test() -> void:
	var report := HHSelfTest.run()
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print(HHSelfTest.summary(report))
	print("report: ", ProjectSettings.globalize_path(REPORT_PATH))
	get_tree().quit(0 if report.passed else 1)
