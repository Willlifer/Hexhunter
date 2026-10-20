extends SceneTree
## Review renders of the caldera (needs a window, not headless):
##   godot --path . --script res://src/arena/tools/caldera_preview.gd
## Each preset from the ref_cam marker, the default with the hex overlay,
## and a low shot from the player spawn; PNGs go to design/art/arenas/.

const SHOTS: Array = [
	{ "preset": "default", "file": "caldera_default.png", "overlay": false },
	{ "preset": "calm", "file": "caldera_calm.png", "overlay": false },
	{ "preset": "furnace", "file": "caldera_furnace.png", "overlay": false },
	{ "preset": "default", "file": "caldera_default_hexes.png", "overlay": true },
	{ "preset": "default", "file": "caldera_default_low.png", "overlay": false, "cam": "low" },
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = await HHPreviewRun.run(self, "caldera", SHOTS)
	quit(0 if failed == 0 else 1)
