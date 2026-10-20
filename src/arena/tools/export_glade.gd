extends SceneTree
## Writes arenas/glade.json (the default preset's HHArena plus `gen`, `extras`
## and `authored` blocks, HHGenUtil.export_dict):
##   godot --headless --path . --script res://src/arena/tools/export_glade.gd
## Env PRESET=sparse|thick picks another preset (default: "default").


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g := HHGladeGen.new()
	var preset := OS.get_environment("PRESET")
	var p := g.preset(preset)
	var ok := HHGladeGen.export_json(p, "res://arenas/glade.json")
	var a := HHGladeGen.arena(p)
	print("export_glade: preset '%s' -> arenas/glade.json: %s (%d cells, %d walkable, %d authored, spawns %s / %s)" % [
		preset if preset != "" else "default", "ok" if ok else "FAILED", a.cells.size(), a.walkable_count(), HHGenUtil.authored(a).size(), a.spawns.player[0], a.spawns.monster])
	quit(0 if ok else 1)
