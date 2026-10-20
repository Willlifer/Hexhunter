extends SceneTree
## Review renders of the glade (needs a window, not headless):
##   godot --path . --script res://src/arena/tools/glade_preview.gd
## Each preset from the ref_cam marker, the default with the hex overlay,
## and a low shot from the player spawn; PNGs go to design/art/arenas/.

const SHOTS: Array = [
	{ "preset": "default", "file": "glade_default.png", "overlay": false },
	{ "preset": "sparse", "file": "glade_sparse.png", "overlay": false },
	{ "preset": "thick", "file": "glade_thick.png", "overlay": false },
	{ "preset": "default", "file": "glade_default_hexes.png", "overlay": true },
	{ "preset": "default", "file": "glade_default_low.png", "overlay": false, "cam": "low" },
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = await HHPreviewRun.run(self, "glade", SHOTS)
	quit(0 if failed == 0 else 1)
