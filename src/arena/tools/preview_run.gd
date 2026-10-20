class_name HHPreviewRun
extends RefCounted
## Shared by the <id>_preview.gd tools: build each shot's preset, light it
## from asset.lights (sun, sky, fog, point lights from torch_* / glow_*
## markers), camera at the ref_cam marker (or a low shot from the player
## spawn), wait for frames, save the PNG. Windowed only.
##
## shot: { preset, file, overlay: bool, cam: "" | "low" }


static func run(tree: SceneTree, id: String, shots: Array, out_dir: String = "res://design/art/arenas/") -> int:
	var def := HHArenaGens.make(id)
	var world := Node3D.new()
	tree.root.add_child(world)
	var failed := 0
	for sd in shots:
		var shot: Dictionary = sd
		for c in world.get_children():
			world.remove_child(c)
			c.free()
		var p := def.preset(str(shot.preset))
		var t0 := Time.get_ticks_msec()
		var both := HHArenaGens.build_both(id, p)
		var asset: GKAsset = both.asset
		var arena: HHArena = both.arena
		var ms := Time.get_ticks_msec() - t0
		world.add_child(asset.instantiate(false))
		world.add_child(HHArenaStage.sun(asset.lights))
		world.add_child(HHArenaStage.sky(asset.lights))
		for l in HHArenaStage.point_lights(asset):
			world.add_child(l)
		if bool(shot.get("overlay", false)):
			world.add_child(HHArenaStage.overlay(arena, float(asset.meta.get("water_level", -1000.0))))
		var cam := Camera3D.new()
		cam.fov = 45.0
		cam.far = 400.0
		cam.transform = asset.marker("ref_cam")
		world.add_child(cam)
		if str(shot.get("cam", "")) == "low":
			var ps := asset.marker("spawn_player").origin
			var ms_ := asset.marker("spawn_monster").origin
			var back := (ps - ms_).normalized()
			cam.look_at_from_position(ps + back * 5.0 + Vector3(0, 2.4, 0), ms_.lerp(ps, 0.6) + Vector3(0, 0.5, 0), Vector3.UP)
		cam.make_current()
		for i in 4:
			await tree.process_frame
		await RenderingServer.frame_post_draw
		print("preview: %s tris=%d build=%dms warnings=%s meta=%s" % [shot.file, asset.triangle_count(), ms, asset.warnings, asset.meta])
		if not HHArenaStage.save_frame(tree.root, out_dir + str(shot.file)):
			failed += 1
	return failed
