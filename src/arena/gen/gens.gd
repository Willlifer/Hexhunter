class_name HHArenaGens
extends RefCounted
## The biome generators by id (Lane C/D): one place for the bench, the
## tools and boot to dispatch on. Each generator is a GKDef for the look
## and a static `arena(p)` for the underlay (H200 pattern).


static func defs() -> Array:
	return [HHPondGen, HHCaveGen, HHGladeGen, HHCalderaGen]


static func ids() -> PackedStringArray:
	return PackedStringArray(["pond", "cave", "glade", "caldera"])


static func make(id: String) -> GKDef:
	match id:
		"pond": return HHPondGen.new()
		"cave": return HHCaveGen.new()
		"glade": return HHGladeGen.new()
		"caldera": return HHCalderaGen.new()
	return null


static func arena(id: String, p: Dictionary) -> HHArena:
	match id:
		"pond": return HHPondGen.arena(p)
		"cave": return HHCaveGen.arena(p)
		"glade": return HHGladeGen.arena(p)
		"caldera": return HHCalderaGen.arena(p)
	return null


static func build_both(id: String, p: Dictionary) -> Dictionary:
	match id:
		"pond": return HHPondGen.build_both(p)
		"cave": return HHCaveGen.build_both(p)
		"glade": return HHGladeGen.build_both(p)
		"caldera": return HHCalderaGen.build_both(p)
	return {}


static func export_json(id: String, p: Dictionary, path: String = "") -> bool:
	var out := path if path != "" else "res://arenas/%s.json" % id
	match id:
		"pond": return HHPondGen.export_json(p, out)
		"cave": return HHCaveGen.export_json(p, out)
		"glade": return HHGladeGen.export_json(p, out)
		"caldera": return HHCalderaGen.export_json(p, out)
	return false


## The generator's own material roles (merged into GKMaterials on request).
static func roles(id: String) -> Dictionary:
	match id:
		"pond": return HHPondGen.ROLES
		"cave": return HHCaveGen.ROLES
		"glade": return HHGladeGen.ROLES
		"caldera": return HHCalderaGen.ROLES
	return {}
