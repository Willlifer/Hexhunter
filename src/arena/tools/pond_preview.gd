extends SceneTree
## Review renders of the pond (needs a window, not headless):
##   godot --path . --script res://src/arena/tools/pond_preview.gd
## Builds each preset, lights it from asset.lights, puts the camera at the
## ref_cam marker, waits for frames, saves design/art/arenas/pond_<preset>.png,
## plus pond_default_hexes.png with the logical underlay drawn over it.

const OUT := "res://design/art/arenas/"
const SHOTS: Array = [
	{ "preset": "default", "file": "pond_default.png", "overlay": false },
	{ "preset": "sparse", "file": "pond_sparse.png", "overlay": false },
	{ "preset": "dense", "file": "pond_dense.png", "overlay": false },
	{ "preset": "default", "file": "pond_default_hexes.png", "overlay": true },
	{ "preset": "default", "file": "pond_default_low.png", "overlay": false, "cam": "low" },
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g := HHPondGen.new()
	var world := Node3D.new()
	root.add_child(world)
	var failed := 0
	for sd in SHOTS:
		var shot: Dictionary = sd
		for c in world.get_children():
			world.remove_child(c)
			c.free()
		var p := g.preset(str(shot.preset))
		var t0 := Time.get_ticks_msec()
		var both := HHPondGen.build_both(p)
		var asset: GKAsset = both.asset
		var arena: HHArena = both.arena
		var ms := Time.get_ticks_msec() - t0
		world.add_child(asset.instantiate(false))
		world.add_child(HHArenaStage.sun(asset.lights))
		world.add_child(HHArenaStage.sky(asset.lights))
		if bool(shot.overlay):
			world.add_child(HHArenaStage.overlay(arena))
		var cam := Camera3D.new()
		cam.fov = 45.0
		cam.far = 400.0
		cam.transform = asset.marker("ref_cam")
		world.add_child(cam)
		if str(shot.get("cam", "")) == "low":
			var ps := asset.marker("spawn_player").origin
			cam.look_at_from_position(ps + Vector3(2.0, 2.2, 5.0), Vector3(0.0, 0.2, -4.0), Vector3.UP)
		cam.make_current()
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		print("preview: %s tris=%d build=%dms warnings=%s pads=%s cover=%s walkable=%s/%s" % [shot.file, asset.triangle_count(), ms,
			asset.warnings, asset.meta.get("pads"), asset.meta.get("cover"), asset.meta.get("walkable"), asset.meta.get("cells")])
		if not HHArenaStage.save_frame(root, OUT + str(shot.file)):
			failed += 1
	quit(0 if failed == 0 else 1)
