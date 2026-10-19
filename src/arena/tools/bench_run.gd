extends SceneTree
## Opens the arena bench windowed (until the integrator wires `--bench`):
##   godot --path . --script res://src/arena/tools/bench_run.gd
## With BENCH_SHOT=<png path> it also saves one frame after a few seconds
## (with the hex overlay on) and quits: the windowed check for the tool.


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
	quit(0 if ok else 1)
