extends SceneTree
## Writes arenas/pond.json (the default preset's HHArena plus a `gen` block
## that rebuilds it):
##   godot --headless --path . --script res://src/arena/tools/export_pond.gd [preset]
## Env PRESET=sparse|dense picks another preset (default: "default").


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g := HHPondGen.new()
	var preset := OS.get_environment("PRESET")
	var p := g.preset(preset)
	var ok := HHPondGen.export_json(p, "res://arenas/pond.json")
	var a := HHPondGen.arena(p)
	print("export_pond: preset '%s' -> arenas/pond.json: %s (%d cells, %d walkable, spawns %s / %s)" % [
		preset if preset != "" else "default", "ok" if ok else "FAILED", a.cells.size(), a.walkable_count(), a.spawns.player[0], a.spawns.monster])
	quit(0 if ok else 1)
