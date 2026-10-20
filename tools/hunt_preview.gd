extends SceneTree
## Review renders of the hunt screens (Lane H): the world map for a couple
## of seeds (one site's name shown as if hovered), the ambush at its lurk and
## at its peak frame for every monster, and the results screen. Needs a
## window (not headless):
##   godot --path . --script res://tools/hunt_preview.gd [-- --out design/hunt/shots --seeds 1,2 --monsters swampfang,colambros,rimeslithe,spirewalker]
## Writes <out>/map_seed<N>.png, <out>/ambush_<id>_lurk.png,
## <out>/ambush_<id>_peak.png, <out>/results_win.png and quits.

var out_dir := "design/hunt/shots"
var seeds: PackedStringArray = ["1", "2"]
var monsters: PackedStringArray = ["swampfang", "colambros", "rimeslithe", "spirewalker"]
var lurk_t := 0.45
var shell: HHHuntShellStub


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--seeds")
	if i >= 0 and i + 1 < args.size():
		seeds = args[i + 1].split(",")
	i = args.find("--monsters")
	if i >= 0 and i + 1 < args.size():
		monsters = args[i + 1].split(",")
	i = args.find("--lurk")
	if i >= 0 and i + 1 < args.size():
		lurk_t = float(args[i + 1])
	root.size = Vector2i(1600, 900)
	shell = HHHuntShellStub.new()
	shell.name = "Shell"
	root.add_child(shell)
	_run.call_deferred()


func _run() -> void:
	for s in seeds:
		var map := HHWorldMap.new()
		shell.show_screen(map, { "seed": int(s), "weapon": "lance" })
		map.hover_force = (map.disturbance + 1) % 4
		map.run_to(10.0, 6.0)
		await _frames(40)
		await _save("map_seed%s.png" % s)
		map.hover_force = -1
	for m in monsters:
		var arena := HHHuntFlow.biome_of(m)
		var am := HHAmbush.new()
		shell.show_screen(am, { "monster": m, "arena": arena, "seed": 1, "weapon": "lance" })
		am.paused = true
		am.scrub(lurk_t)
		print("ambush %s: hunter %s monster %s surface %s" % [m, am._hunter_pos, am._monster_pos, am.arena.surface(am.arena.spawns.monster)])
		await _frames(12)
		await _save("ambush_%s_lurk.png" % m)
		am.paused = false
		var peak := HHAmbush.peak_time()
		while am.time < peak:                              # play it live so the motes emit
			await process_frame
		am.paused = true
		await _frames(2)
		await _save("ambush_%s_peak.png" % m)
	var r := HHResults.new()
	r.inject(HHHuntFlow.script_named("HHDrops"), null)      # real drops when Lane U is in; no save written
	shell.show_screen(r, { "cfg": { "monster": "swampfang", "arena": "pond", "seed": 1, "weapon": "lance" },
		"fight": { "result": "win", "ticks": 2460, "hp": 1240.0, "monster_hp": 0.0 } })
	await _frames(6)
	await _save("results_win.png")
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var abs := out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(out_dir)
	HHArenaStage.save_frame(root, abs.simplify_path().path_join(name))
