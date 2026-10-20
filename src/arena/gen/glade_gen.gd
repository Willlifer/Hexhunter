class_name HHGladeGen
extends GKDef
## The Grassy Glade (kickoff Lane D: "minor elevation, some trees as
## obstacles"; Lane C: "sunlit patches for monster in the Grassy Glade").
## Spirewalker's arena (H10): it recharges on the sun cells. One seeded
## layout feeds arena(p) and build(p) (H200 pattern).
##
## Cells: "floor" (grass), "edge" (H17), "tree" (a trunk on the hex:
## impassable, holds no charge), "sun" (a sunlit patch: walkable floor with
## `sun: true`, drawn as a lighter grass disc). Elevation is a gentle seeded
## bump field scaled by `bumps`; nothing on the floor is a cliff.
##
## Roles: ROLES below in GKMaterials.ROLES shape (Request: merge); role()
## falls back to existing roles until then.

const SKIRT_M := 12.0
const HF_STEP := 1.0
const SUN_R_LO := 1.7           ## sun patch radius range (m): 2-7 hexes each
const SUN_R_HI := 2.5

const ROLES := {
	"glade_grass": { "a": "#6fa03a", "b": "#55852c", "c": "#8fbf4e", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.45, "world": true },
	"sun_grass": { "a": "#b4d65a", "b": "#9cc24a", "c": "#d4e878", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.35, "world": true },
	"canopy": { "a": "#4c8a2c", "b": "#376a20", "c": "#78b040", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.35, "world": true },
	"glade_trunk": { "a": "#5a4634", "b": "#43342a", "c": "#6e5a46", "rough": 0.95, "pat": "grain", "scale": 3.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"glade_flower": { "a": "#f0e0f8", "b": "#d8b8e8", "c": "#ffffff", "rough": 0.8, "pat": "plain", "scale": 4.0, "amt": 0.2, "world": true },
	"bush": { "a": "#3f6f2a", "b": "#2c5220", "c": "#558a36", "rough": 1.0, "pat": "grass", "scale": 2.0, "amt": 0.3, "world": true },
}
const FALLBACK := {
	"glade_grass": "meadow_grass:#6fa03a",
	"sun_grass": "meadow_grass:#b4d65a",
	"canopy": "foliage:#4c8a2c",
	"glade_trunk": "bark:#5a4634",
	"glade_flower": "sign_white:#f0e0f8",
	"bush": "hedge",
}


static func role(name: String) -> String:
	return HHGenUtil.role(FALLBACK, name)


func id() -> String:
	return "glade"


func title() -> String:
	return "Grassy Glade"


func kind() -> String:
	return "env"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pi("seed", "Seed", "Layout", 1, 1, 99999),
		pf("radius_m", "Floor radius (m)", "Layout", 25.0, 15.0, 30.0, 0.5),
		pi("tree_count", "Trees on the floor", "Obstacles", 14, 0, 40),
		pi("sun_patches", "Sunlit patches", "Cells", 7, 0, 12),
		pf("bumps", "Elevation", "Layout", 0.5, 0.0, 1.0, 0.05),
		pf("flower_density", "Flowers", "Dressing", 0.5, 0.0, 1.0, 0.05),
	]


func presets() -> Dictionary:
	return {
		"default": {},
		"sparse": { "tree_count": 6, "sun_patches": 5, "bumps": 0.3, "flower_density": 0.25 },
		"thick": { "tree_count": 28, "sun_patches": 9, "bumps": 0.7, "flower_density": 0.9 },
	}


static func _validated(p: Dictionary) -> Dictionary:
	return HHGladeGen.new().validate(p)


# ------------------------------------------------------------------ layout

static func height(L: Dictionary, x: float, z: float) -> float:
	var R: float = L.R
	var r := sqrt(x * x + z * z)
	var h := HHGenUtil.blobs_at(L.blobs, x, z)
	if r > R:
		h += (r - R) * 0.18 + sin(atan2(z, x) * 5.0 + float(L.rim_ph)) * (r - R) * 0.04
	return h


## 1 inside a sun patch, 0 outside (soft edge for the floor tint).
static func sun_mask(L: Dictionary, x: float, z: float) -> float:
	var m := 0.0
	for sp in L.sun_patches:
		var s: Dictionary = sp
		var d := Vector2(x, z).distance_to(Vector2(float(s.x), float(s.z)))
		m = maxf(m, 1.0 - smoothstep(float(s.r) - 0.5, float(s.r) + 0.9, d))
	return m


static func layout(q: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(q.seed)
	var R: float = q.radius_m
	var L := { "R": R }
	L["blobs"] = HHGenUtil.make_blobs(rng, 7, R, 4.5, 9.0, float(q.bumps) * 0.55)
	L["rim_ph"] = rng.randf_range(0.0, TAU)
	var a := HHArena.new()
	a.id = "glade"
	a.seed = int(q.seed)
	a.radius_m = R
	a.skirt_m = SKIRT_M
	a._lay_cells()
	var p_hint := Vector2(0.0, R * 0.72)
	var m_hint := Vector2(0.0, -R * 0.7)
	var avoid: Array = [HHHex.from_world(p_hint, HHArena.HEX), HHHex.from_world(m_hint, HHArena.HEX)]
	var floor_hexes := HHGenUtil.cells_of_kind(a, "floor")
	# trees on the floor: spaced so every gap is walkable
	var trees := HHGenUtil.pick_spaced(rng, floor_hexes, int(q.tree_count), 3, avoid, 4)
	var tree_look: Array = []
	for h in trees:
		var c: Dictionary = a.cells[h]
		c.kind = "tree"
		c.walkable = false
		tree_look.append({ "h": rng.randf_range(4.2, 6.5), "r": rng.randf_range(0.2, 0.32), "w": rng.randf_range(2.2, 3.2),
			"lean": rng.randf_range(-0.08, 0.08), "ph": rng.randf_range(0.0, TAU), "tint": rng.randf_range(0.85, 1.15) })
	L["tree_look"] = tree_look
	# sun patches: discs between the trees
	var taken: Array = avoid.duplicate()
	taken.append_array(trees)
	var open: Array[Vector2i] = []
	for h in floor_hexes:
		if str((a.cells[h] as Dictionary).kind) == "floor" and HHHex.to_world(h, HHArena.HEX).length() < R - 4.0:
			open.append(h)
	var centres := HHGenUtil.pick_spaced(rng, open, int(q.sun_patches), 6, taken, 3)
	var patches: Array = []
	for h in centres:
		var w := HHHex.to_world(h, HHArena.HEX)
		patches.append({ "x": w.x + rng.randf_range(-0.4, 0.4), "z": w.y + rng.randf_range(-0.4, 0.4), "r": rng.randf_range(SUN_R_LO, SUN_R_HI) })
	L["sun_patches"] = patches
	var sun_cells: Array = []
	for h in floor_hexes:
		var c: Dictionary = a.cells[h]
		if str(c.kind) != "floor":
			continue
		var w := HHHex.to_world(h, HHArena.HEX)
		for sp in patches:
			var s: Dictionary = sp
			if Vector2(w.x, w.y).distance_to(Vector2(float(s.x), float(s.z))) <= float(s.r):
				c.kind = "sun"
				c["sun"] = true
				sun_cells.append(h)
				break
	L["sun_cells"] = sun_cells
	# dressing: gold flowers inside the sun patches, mixed flowers, grass tufts, bushes, the forest ring
	var flowers: Array = []
	for sp in patches:
		var s: Dictionary = sp
		for i in 7:
			var ang := rng.randf_range(0.0, TAU)
			var rr := sqrt(rng.randf()) * float(s.r) * 0.85
			flowers.append({ "x": float(s.x) + cos(ang) * rr, "z": float(s.z) + sin(ang) * rr, "h": rng.randf_range(0.3, 0.5), "hue": 0.55 })
	for i in int(round(float(q.flower_density) * 260.0)):
		var ang := rng.randf_range(0.0, TAU)
		var rr := sqrt(rng.randf()) * (R + 5.0)
		flowers.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "h": rng.randf_range(0.2, 0.45), "hue": rng.randf() })
	L["flowers"] = flowers
	var tufts: Array = []
	for i in 560:
		var ang := rng.randf_range(0.0, TAU)
		var rr := sqrt(rng.randf()) * (R + 6.0)
		tufts.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "h": rng.randf_range(0.35, 0.8), "tint": rng.randf_range(0.8, 1.15) })
	L["tufts"] = tufts
	var bushes: Array = []
	for i in 26:
		var ang := rng.randf_range(0.0, TAU)
		var rr := R + rng.randf_range(-1.2, 7.0)
		bushes.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "r": rng.randf_range(0.6, 1.3), "tint": rng.randf_range(0.8, 1.1) })
	L["bushes"] = bushes
	var forest: Array = []
	for i in 70:
		var ang := TAU * float(i) / 70.0 + rng.randf_range(-0.05, 0.05)
		var rr := R + rng.randf_range(2.5, 10.5)
		forest.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "h": rng.randf_range(6.0, 10.0), "r": rng.randf_range(0.25, 0.4), "w": rng.randf_range(2.6, 4.0),
			"ph": rng.randf_range(0.0, TAU), "tint": rng.randf_range(0.75, 1.05) })
	L["forest"] = forest
	# heightfield, spawns, authored (none: sun is a cell flag, not a charge)
	HHGenUtil.fill_hf(a, func(x: float, z: float) -> float: return height(L, x, z), HF_STEP)
	HHGenUtil.pick_spawns(a, p_hint, m_hint, 10)
	a.spawns["authored"] = []
	L["arena"] = a
	return L


# ------------------------------------------------------------------ arena

static func arena(p: Dictionary) -> HHArena:
	return layout(_validated(p)).arena


static func build_both(p: Dictionary) -> Dictionary:
	var g := HHGladeGen.new()
	return { "arena": arena(p), "asset": g.build(p) }


static func export_dict(p: Dictionary) -> Dictionary:
	var q := _validated(p)
	return HHGenUtil.export_dict(arena(q), "glade", 1, q)


static func export_json(p: Dictionary, path: String = "res://arenas/glade.json") -> bool:
	return HHGenUtil.write_json(export_dict(p), path)


# ------------------------------------------------------------------ asset

func _build(q: Dictionary) -> GKAsset:
	var asset := GKAsset.new()
	var L := layout(q)
	var a: HHArena = L.arena
	var R: float = q.radius_m
	# -- floor: meadow grass, lighter inside the sun patches, darker under the forest
	var g := GKMesh.new()
	var grass := role("glade_grass")
	var sunny := role("sun_grass")
	HHGenUtil.hf_quads(g, a, func(cx: float, cz: float) -> Array:
		var r := sqrt(cx * cx + cz * cz)
		var m := sun_mask(L, cx, cz)
		if m > 0.7:
			return [sunny, Color(1.05, 1.05, 0.95)]
		var tint := Color.WHITE.lerp(Color(0.5, 0.58, 0.42), clampf((r - R - 2.0) / 7.0, 0.0, 1.0))
		return [grass, tint.lerp(Color(1.4, 1.36, 0.92), m / 0.7)])
	var floor_mesh := g.commit()
	asset.add_part("floor", floor_mesh)
	asset.add_trimesh_collider(floor_mesh)
	# -- trees: trunks on their hex, round canopies
	var tg := GKMesh.new()
	var trunk := role("glade_trunk")
	var leaf := role("canopy")
	var trees := HHGenUtil.cells_of_kind(a, "tree")
	for i in trees.size():
		var c := a.world(trees[i])
		_tree(tg, trunk, leaf, c, L.tree_look[i])
	for fd in L.forest:
		var f: Dictionary = fd
		var x := float(f.x)
		var z := float(f.z)
		_tree(tg, trunk, leaf, Vector3(x, a.height_at(x, z) - 0.3, z), f)
	tg.tint = Color.WHITE
	asset.add_part("trees", tg.commit())
	# -- bushes
	var bg := GKMesh.new()
	var bush := role("bush")
	for bd in L.bushes:
		var b: Dictionary = bd
		var x := float(b.x)
		var z := float(b.z)
		var rad := float(b.r)
		var ti := float(b.tint)
		bg.tint = Color(ti, ti, ti * 0.95)
		var c := Vector3(x, a.height_at(x, z) + rad * 0.45, z)
		bg.sphere(bush, c, rad, 7, Vector3(1.0, 0.75, 0.9))
		bg.sphere(bush, c + Vector3(rad * 0.5, 0.1, rad * 0.2), rad * 0.7, 6, Vector3(1.0, 0.8, 1.0))
	bg.tint = Color.WHITE
	asset.add_part("bushes", bg.commit())
	# -- flowers and grass tufts
	var fg := GKMesh.new()
	var petal := role("glade_flower")
	var stem := "hedge"
	for fd in L.flowers:
		var f: Dictionary = fd
		var x := float(f.x)
		var z := float(f.z)
		var y := a.height_at(x, z)
		var top := Vector3(x, y + float(f.h), z)
		fg.tint = Color.WHITE
		fg.tube(stem, [Vector3(x, y, z), top], [0.018, 0.012], 4, false)
		var hue: float = f.hue
		var brole := petal if hue < 0.4 else ("foliage_gold" if hue < 0.7 else ("sign_red:#d04a7a" if hue < 0.85 else "sign_blue:#6a7ad8"))
		fg.sphere(brole, top, 0.075, 5, Vector3(1.0, 0.6, 1.0))
	for td in L.tufts:
		var t: Dictionary = td
		var x := float(t.x)
		var z := float(t.z)
		var y := a.height_at(x, z) - 0.02
		var h := float(t.h)
		var ti := float(t.tint)
		fg.tint = Color(ti, ti, ti * 0.9)
		for b in 3:
			var ba := TAU * float(b) / 3.0 + h
			var bx := x + cos(ba) * 0.12
			var bz := z + sin(ba) * 0.12
			fg.tube(stem, [Vector3(bx, y, bz), Vector3(bx + cos(ba) * 0.1, y + h * (0.7 + 0.3 * float(b) / 2.0), bz + sin(ba) * 0.1)], [0.11, 0.0], 4, false)
	fg.tint = Color.WHITE
	asset.add_part("flowers", fg.commit())
	# -- markers and a bright sunny day
	HHGenUtil.markers(asset, a, R * 0.95, R + 15.0)
	asset.lights = { "sun_dir_deg": [-52.0, 28.0], "sun_energy": 1.7, "sun_color": "#fff6dc",
		"sky_top": "#3f86e0", "sky_horizon": "#d8e8f6", "ground_horizon": "#8fae6a", "ground_bottom": "#3e5230", "ambient": 1.0 }
	asset.meta = { "trees": trees.size(), "sun_patches": (L.sun_patches as Array).size(), "sun_cells": (L.sun_cells as Array).size(),
		"walkable": a.walkable_count(), "cells": a.cells.size(), "reach": HHGenUtil.reach_fraction(a, a.spawns.player[0]) }
	if a.path(a.spawns.player[0], a.spawns.monster).is_empty():
		asset.warnings.append("no path from the player spawn to the monster spawn")
	return asset


## A broadleaf tree: a trunk with a short fork, three round canopy lobes.
static func _tree(g: GKMesh, trunk: String, leaf: String, base: Vector3, look: Dictionary) -> void:
	var h := float(look.h)
	var rad := float(look.r)
	var w := float(look.w)
	var lean := float(look.get("lean", 0.0))
	var ph := float(look.ph)
	var ti := float(look.tint)
	g.tint = Color.WHITE
	var top := base + Vector3(lean * h, h * 0.62, 0.0)
	g.tube(trunk, [base - Vector3(0, 0.3, 0), base + Vector3(0, h * 0.3, 0), top], [rad * 1.3, rad, rad * 0.6], 7, true)
	for k in 2:
		var ang := ph + PI * float(k)
		var tip := top + Vector3(cos(ang) * w * 0.4, h * 0.2, sin(ang) * w * 0.4)
		g.tube(trunk, [top - Vector3(0, h * 0.1, 0), tip], [rad * 0.55, rad * 0.2], 5, false)
	g.tint = Color(ti, ti, ti * 0.95)
	var crown := top + Vector3(0, h * 0.18, 0)
	g.sphere(leaf, crown, w * 0.62, 8, Vector3(1.0, 0.78, 1.0))
	for k in 3:
		var ang := ph + TAU * float(k) / 3.0
		var t2 := ti * (0.92 + 0.08 * float(k))
		g.tint = Color(t2, t2, t2 * 0.95)
		g.sphere(leaf, crown + Vector3(cos(ang) * w * 0.42, h * 0.06 - 0.05 * float(k), sin(ang) * w * 0.42), w * 0.42, 7, Vector3(1.0, 0.8, 1.0))
	g.tint = Color.WHITE
