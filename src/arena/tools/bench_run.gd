extends SceneTree
## Opens the arena bench windowed (until the integrator wires `--bench`):
##   godot --path . --script res://src/arena/tools/bench_run.gd
## With BENCH_SHOT=<png path> it also saves one frame after a few seconds
## (with the hex overlay on) and quits: the windowed check for the tool.
## With BENCH_ALL=1 as well, it first cycles every generator in the picker
## (cave, glade, caldera) and saves bench_<id>.png beside the shot.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bench := HHBench.open(self)
	var shot := OS.get_environment("BENCH_SHOT")
	if shot == "":
		return
	for i in 12:
		await process_frame
	bench.set_overlay(true)
	var cb: CheckBox = bench._controls["__overlay"]
	cb.button_pressed = true
	# exercise the stack: a slider change, undo, redo
	bench._on_change("lilypad_count", 90)
	await create_timer(0.5).timeout
	bench.undo()
	await create_timer(0.5).timeout
	bench.redo()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	print("bench: status = ", bench._status.text)
	var ok := HHArenaStage.save_frame(root, shot)
	if OS.get_environment("BENCH_ALL") != "":
		var ds := HHBench.defs()
		for i in range(1, ds.size()):
			bench._def_pick.select(i)
			bench._pick_def(i)
			await create_timer(0.8).timeout
			await RenderingServer.frame_post_draw
			print("bench: status = ", bench._status.text)
			if not HHArenaStage.save_frame(root, shot.get_base_dir() + "/bench_%s.png" % bench.def.id()):
				ok = false
	quit(0 if ok else 1)
