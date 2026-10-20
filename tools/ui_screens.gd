extends SceneTree
## Fixed review frames of Lane UI's screens for the gauntlet rounds: the
## lobby (sample run history, one element socket hovered, a result in the
## ticker), the results screen (a win with real drops after its reveal, and
## a loss) and the ambush title card at a settled frame. Never touches the
## player's files: the save, the last pick and the run history point at
## scratch files for the run. Needs a window:
##   godot --path . --script res://tools/ui_screens.gd -- --out <dir> [--screens lobby,results_win,results_fallen,ambush] [--monster swampfang]
## Writes <dir>/<screen>.png, then quits.

const SAMPLE_RUNS := [
	{ "monster": "colambros", "arena": "caldera", "weapon": "daggers", "element": "water", "backup": "ice", "seed": 12, "result": "win", "seconds": 184.0, "hunt": true },
	{ "monster": "colambros", "arena": "caldera", "weapon": "daggers", "element": "fire", "backup": "wind", "seed": 11, "result": "fallen", "seconds": 97.3, "hunt": false },
	{ "monster": "rimeslithe", "arena": "cave", "weapon": "bow", "element": "fire", "backup": "thunder", "seed": 4, "result": "win", "seconds": 241.0, "hunt": false },
	{ "monster": "spirewalker", "arena": "glade", "weapon": "lance", "element": "fire", "backup": "water", "seed": 3, "result": "abort", "seconds": 31.0, "hunt": false },
	{ "monster": "swampfang", "arena": "pond", "weapon": "lance", "element": "thunder", "backup": "dark", "seed": 1, "result": "win", "seconds": 132.0, "hunt": false },
]
const SCRATCH := ["user://ui_screens_hunter.json", "user://ui_screens_last.json", "user://ui_screens_runs.json"]

var out_dir := "design/visual_pass/UI/raw"
var screens: PackedStringArray = ["lobby", "results_win", "results_fallen", "ambush"]
var monster := "swampfang"
var shell: HHHuntShellStub


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--screens")
	if i >= 0 and i + 1 < args.size():
		screens = args[i + 1].split(",")
	i = args.find("--monster")
	if i >= 0 and i + 1 < args.size():
		monster = args[i + 1]
	HHSave.path = SCRATCH[0]
	HHLobbyState.last_path = SCRATCH[1]
	HHLobbyState.runs_path = SCRATCH[2]
	root.size = Vector2i(1600, 900)
	shell = HHHuntShellStub.new()
	shell.name = "Shell"
	root.add_child(shell)
	_run.call_deferred()


func _run() -> void:
	for p in SCRATCH:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for i in range(SAMPLE_RUNS.size() - 1, -1, -1):
		HHLobbyState.record_run(SAMPLE_RUNS[i])
	for s in screens:
		match s:
			"lobby":
				var lobby := HHLobby.new()
				lobby.can_replay = true
				lobby.result_text = "VICTORY in 184 s"
				shell.show_screen(lobby, { "monster": "colambros", "arena": "caldera", "weapon": "daggers", "element": "water", "backup": "ice", "seed": 12 })
				lobby.state.element_phase = 1
				lobby._refresh()
				var d: HHLobbyDisc = lobby._discs["thunder"]
				d.hover = true
				d.queue_redraw()
				await _frames(6)
				await _save("lobby.png")
			"results_win", "results_fallen":
				var won := s == "results_win"
				var r := HHResults.new()
				r.record_run = false
				r.inject(HHHuntFlow.script_named("HHDrops"), null)
				shell.show_screen(r, { "cfg": { "monster": monster, "arena": HHRegistry.biome_of(monster), "seed": 1, "weapon": "lance", "element": "fire", "backup": "water" },
					"fight": { "result": "win" if won else "fallen", "ticks": 2460, "hp": 1240.0 if won else 0.0, "monster_hp": 0.0 if won else 7400.0 } })
				await _frames(150)                                 # past the reveal
				await _save("%s.png" % s)
			"ambush":
				var am := HHAmbush.new()
				shell.show_screen(am, { "monster": monster, "arena": HHRegistry.biome_of(monster), "seed": 1, "weapon": "lance" })
				am.paused = true
				am.scrub(HHHuntKit.t("ambush_name_at") + 0.8)
				await _frames(12)
				await _save("ambush.png")
	for p in SCRATCH:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var abs := out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(abs)
	var img := root.get_viewport().get_texture().get_image()
	var path := abs.simplify_path().path_join(name)
	print("ui_screens: %s (%s)" % [path, error_string(img.save_png(path))])
