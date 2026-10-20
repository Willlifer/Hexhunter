extends SceneTree
## Review renders of the cave (needs a window, not headless):
##   godot --path . --script res://src/arena/tools/cave_preview.gd
## Each preset from the ref_cam marker, the default with the hex overlay,
## and a low shot from the player spawn; PNGs go to design/art/arenas/.

const SHOTS: Array = [
	{ "preset": "default", "file": "cave_default.png", "overlay": false },
	{ "preset": "open", "file": "cave_open.png", "overlay": false },
	{ "preset": "maze", "file": "cave_maze.png", "overlay": false },
	{ "preset": "default", "file": "cave_default_hexes.png", "overlay": true },
	{ "preset": "default", "file": "cave_default_low.png", "overlay": false, "cam": "low" },
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = await HHPreviewRun.run(self, "cave", SHOTS)
	quit(0 if failed == 0 else 1)
