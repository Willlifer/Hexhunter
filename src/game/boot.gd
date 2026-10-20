extends Node
## Entry point. User args (after `--`):
##   --self-test                run every tests/test_*.gd and exit (0 = green);
##                              report at user://self_test_report.json
##   --seed N                   the sim's seed (default 1)
##   --arena <id>               round (default) or arenas/<id>.json (rebuilt through
##                              its generator when the file carries a "gen" block)
##   --fight <monster>          put a monster in the arena (Lane E's brain and body
##                              when src/monster/<monster>.gd exists, else the stub)
##   --weapon <id>              lance (default) | daggers | bow
##   --element <el> --backup <el>   the hunter's element pair (default fire / water)
##   --sandbox                  H20: left-click paints, keys 1-7 pick the element
##   --autoplay [--seconds s]   scripted run, then quit (the smoke test)
##   --shot <dir> [--count n] [--every s]   save n rendered frames to <dir>, then quit
##   --shot-lobby <dir>         the same, of the lobby
##   --cam dist,pitch           start the camera at this distance (m) and pitch (deg)
##   --tune key=value           override one HHTune number this run (repeatable)
##   --bench                    Lane C's arena bench (src/arena/bench/bench.gd)
## With no args (a double-clicked exe) it opens the lobby (H47). Any fight flag
## starts that fight directly; when it ends (or on Esc) the lobby opens with
## the same cfg (H48). Both run under HHShell.

const REPORT_PATH := "user://self_test_report.json"
const FIGHT_FLAGS := ["--arena", "--fight", "--weapon", "--seed", "--cam", "--sandbox", "--autoplay", "--shot", "--element", "--backup"]


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
	var saved := HHTunePanel.load_saved()                          # the F1 panel's keepers
	if saved > 0:
		print("boot: %d tune value(s) from %s" % [saved, HHTunePanel.PATH])
	for i in args.size():
		if args[i] == "--tune" and i + 1 < args.size():            # a flag still beats the file
			var kv := args[i + 1].split("=")
			if kv.size() == 2:
				HHTune.set_value(kv[0], float(kv[1]))
	var shell := HHShell.new()
	shell.name = "Shell"
	add_child(shell)
	if "--shot-lobby" in args:
		shell.go_lobby(HHShell.default_cfg())
		_capture(args, "--shot-lobby")
		return
	var direct := false
	for f in FIGHT_FLAGS:
		if f in args:
			direct = true
	if not direct:                                                  # double-clicked: the lobby (H47)
		shell.go_lobby({})
		return
	var cfg := HHShell.default_cfg()
	cfg.arena = _arg(args, "--arena", "round")
	cfg.monster = _arg(args, "--fight", "")
	cfg.weapon = _arg(args, "--weapon", "lance")
	cfg.element = _arg(args, "--element", "fire")
	cfg.backup = _arg(args, "--backup", "water")
	cfg.seed = int(_arg(args, "--seed", "1"))
	cfg.cam = _arg(args, "--cam", "18,48") if "--cam" in args else ""
	cfg.sandbox = "--sandbox" in args
	cfg.autoplay = "--autoplay" in args or "--shot" in args
	var seconds := 14.0
	if "--seconds" in args:
		seconds = float(_arg(args, "--seconds", "14"))
	if "--shot" in args:
		seconds = maxf(seconds, float(_arg(args, "--count", "6")) * float(_arg(args, "--every", "1.5")) + 1.0)
	cfg.autoplay_seconds = seconds
	shell.play(cfg)
	if "--shot" in args:
		_capture(args, "--shot")


func _capture(args: PackedStringArray, flag: String) -> void:
	var cap := HHCapture.new()
	cap.out_dir = _arg(args, flag, "design/art/shots")
	cap.every = float(_arg(args, "--every", "1.5"))
	cap.count = int(_arg(args, "--count", "6"))
	add_child(cap)


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
