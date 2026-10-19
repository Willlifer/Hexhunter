extends Node
## Entry point. User args (after `--`):
##   --self-test                run every tests/test_*.gd and exit (0 = green);
##                              report at user://self_test_report.json
##   --seed N                   the sim's seed (default 1)
##   --arena <id>               round (default) or a file under arenas/<id>.json
##   --fight <monster>          put a monster stub in the arena (Lane E fills it)
##   --autoplay                 scripted sandbox run, then quit (the smoke test)
##   --shot <dir> [--count n] [--every s]   save n rendered frames to <dir>, then quit
##   --tune key=value           override one HHTune number this run (repeatable)
##   --cam dist,pitch           start the camera at this distance (m) and pitch (deg)
## With no args (a double-clicked exe) it opens the sandbox with the Swampfang stub, wide view.

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
	if args.is_empty():                                             # double-clicked: the fight sandbox, wide view
		args = PackedStringArray(["--fight", "swampfang", "--cam", "30,42"])
	var seed := int(_arg(args, "--seed", "1"))
	var arena := _load_arena(_arg(args, "--arena", "round"), seed)
	var fight := HHFight.new()
	fight.name = "Fight"
	fight.autoplay = "--autoplay" in args or "--shot" in args
	if "--shot" in args:
		fight.autoplay_seconds = maxf(fight.autoplay_seconds, float(_arg(args, "--count", "6")) * float(_arg(args, "--every", "1.5")) + 1.0)
	add_child(fight)
	fight.setup(arena, seed, _arg(args, "--fight", ""))
	if "--cam" in args:                                          # "dist,pitch_deg" for review renders
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


func _load_arena(id: String, seed: int) -> HHArena:
	var path := "res://arenas/%s.json" % id
	if id != "round" and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return HHArena.from_dict(parsed)
		push_warning("boot: arena '%s' failed to parse, using round" % id)
	return HHArena.round_flat(seed)


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
