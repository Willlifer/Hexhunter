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
##   --difficulty easy|normal   the fight's tier (H243; default easy; "hard" is accepted, identical
##                              to normal for now); also prefills the lobby, --hunt and --host
##   --hunt [--seed N] [--weapon id]  the hunt loop: world map -> ambush -> prep -> fight -> results
##   --sandbox                  H20: left-click paints, keys 1-7 pick the element
##   --autoplay [--seconds s]   scripted run, then quit (the smoke test)
##   --shot <dir> [--count n] [--every s]   save n rendered frames to <dir>, then quit
##   --shot-lobby <dir>         the same, of the lobby
##   --cam dist,pitch           start the camera at this distance (m) and pitch (deg)
##   --tune key=value           override one HHTune number this run (repeatable)
##   --bench                    Lane C's arena bench (src/arena/bench/bench.gd)
##   --host [--name X]          co-op: open the lobby already hosting a party (H914)
##   --join <address> [--name X]   co-op: open the lobby already joined to that host
##       [--port N] on either: not the default 24631 (smoke runs stay off a real game)
##       with --autoplay [--peers n] [--seconds s]: the host starts the fight once n
##       hunters are in and ready (guests ready at once); each process's bot drives
##       its own hunter, prints its summary and quits (the two-process smoke test).
##       --arena / --fight / --weapon / --element / --backup / --seed prefill the lobby.
##   --host --online [--name X]    co-op online: host a room on the relay (H114); the code shows in the lobby
##   --join-code <code> [--name X] co-op online: join that room through the relay
##   --relay <url>              the relay for this run (default HHRelayConfig.URL; ws://127.0.0.1:8765 locally)
##   --preload / --no-preload   force the boot preload (HHPreload, H460) on or off; by default the browser
##                              runs it (preload_on_web) and the desktop skips it (preload_on_desktop)
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
	HHWebLook.apply_quality(get_viewport())                        # the browser's render scale (no-op on desktop)
	var shell := HHShell.new()
	shell.name = "Shell"
	add_child(shell)
	if HHPreload.wanted(args, OS.has_feature("web"), DisplayServer.get_name() == "headless"):   # H460: pay the first-load cost before the first screen
		var pre := HHPreload.new()
		add_child(pre)
		pre.done.connect(_start.bind(shell, args), CONNECT_ONE_SHOT)
		pre.run()
		return
	_start(shell, args)


## The first screen, from the flags (after the preload, when there is one).
func _start(shell: HHShell, args: PackedStringArray) -> void:
	if "--shot-lobby" in args:
		shell.go_lobby(HHShell.default_cfg())
		_capture(args, "--shot-lobby")
		return
	if "--host" in args or "--join" in args or "--join-code" in args:   # H914, H114: the lobby, already hosting / joined
		var lc := HHShell.default_cfg()
		for kv in [["--arena", "arena"], ["--fight", "monster"], ["--weapon", "weapon"], ["--element", "element"], ["--backup", "backup"]]:
			if kv[0] in args:
				lc[kv[1]] = _arg(args, kv[0], str(lc[kv[1]]))
		if "--seed" in args:
			lc.seed = int(_arg(args, "--seed", "1"))
		if "--cam" in args:
			lc.cam = _arg(args, "--cam", "30,44")
		if "--difficulty" in args:
			lc.difficulty = _tier(args)
		var host := "--host" in args
		shell.coop_boot = { "mode": "host" if host else "join", "address": _arg(args, "--join", ""),
			"online": "--online" in args or "--join-code" in args, "code": _arg(args, "--join-code", ""),
			"name": _arg(args, "--name", "Host" if host else "Guest"), "autoplay": "--autoplay" in args,
			"peers": int(_arg(args, "--peers", "2")), "port": int(_arg(args, "--port", str(HHParty.PORT))), "seconds": float(_arg(args, "--seconds", "30")) }
		shell.go_lobby(lc)
		return
	if "--hunt" in args:                                            # H612: straight onto the world map
		var hc := HHShell.default_cfg()
		hc.seed = int(_arg(args, "--seed", "1"))
		hc.weapon = _arg(args, "--weapon", "lance")
		hc.element = _arg(args, "--element", "fire")
		hc.backup = _arg(args, "--backup", "water")
		if "--difficulty" in args:
			hc.difficulty = _tier(args)
		shell.last_cfg = hc
		shell.hunt(hc)
		return
	var direct := false
	for f in FIGHT_FLAGS:
		if f in args:
			direct = true
	if not direct:                                                  # double-clicked: the lobby (H47)
		shell.go_lobby({ "difficulty": _tier(args) } if "--difficulty" in args else {})
		return
	var cfg := HHShell.default_cfg()
	cfg.arena = _arg(args, "--arena", "round")
	cfg.monster = _arg(args, "--fight", "")
	cfg.weapon = _arg(args, "--weapon", "lance")
	cfg.element = _arg(args, "--element", "fire")
	cfg.backup = _arg(args, "--backup", "water")
	cfg.seed = int(_arg(args, "--seed", "1"))
	cfg.difficulty = _tier(args)
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
	# Loaded by path, not by class name: the Web preset leaves tools/ out, and a
	# class-name reference made boot.gd fail to parse in the browser (Lane R, H118).
	var script: GDScript = load("res://tools/capture.gd") if ResourceLoader.exists("res://tools/capture.gd") else null
	if script == null:
		push_warning("%s: tools/capture.gd is not in this build" % flag)
		return
	var cap: Node = script.new()
	cap.set("out_dir", _arg(args, flag, "design/art/shots"))
	cap.set("every", float(_arg(args, "--every", "1.5")))
	cap.set("count", int(_arg(args, "--count", "6")))
	add_child(cap)


## --difficulty <tier>, checked: an unknown tier says so and plays easy.
func _tier(args: PackedStringArray) -> String:
	var want := _arg(args, "--difficulty", "easy").to_lower()
	if not want in HHSim.TIERS:
		push_warning("boot: unknown --difficulty '%s' (one of %s); playing easy" % [want, HHSim.TIERS])
	return HHSim.clean_tier(want)


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
