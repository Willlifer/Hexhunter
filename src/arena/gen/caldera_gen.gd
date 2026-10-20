class_name HHCalderaGen
extends GKDef
## The Volcanic Caldera (H12: a snow-rimmed volcanic bowl, ash and snow on
## the rim, heat vents and lava pools on the floor; Lane C: "heat vents/lava
## pools for monster in the Caldera"). Colambros's arena (H10). One seeded
## layout feeds arena(p) and build(p) (H200 pattern).
##
## Cells: "floor" (basalt), "edge" (H17), "vent" (heat vent: walkable,
## authored fire 1 that re-forms), "lava" (pool: impassable, authored fire 3
## permanent), "rock" (volcanic boulder, impassable, no charge). The rim
## rises beyond the floor to RIM_M at the skirt's reach; `snowline` is the
## fraction of that rise above which it is snow (ash below, basalt lower).
##
## Roles: ROLES below in GKMaterials.ROLES shape (Request: merge); role()
## falls back to existing roles until then.

const SKIRT_M := 14.0
const HF_STEP := 0.5
const RIM_M := 16.0
const LAVA_SINK := 0.14          ## the lava surface sits this far below the floor

const ROLES := {
	"basalt": { "a": "#2b2927", "b": "#201e1c", "c": "#3a3734", "rough": 0.95, "pat": "asphalt", "scale": 0.5, "amt": 0.35, "world": true },
	"ash": { "a": "#7d7873", "b": "#67625e", "c": "#938e88", "rough": 1.0, "pat": "stipple", "scale": 1.0, "amt": 0.35, "world": true },
	"snow": { "a": "#eef2f5", "b": "#d8e0e8", "c": "#ffffff", "rough": 0.7, "pat": "speckle", "scale": 1.5, "amt": 0.15, "world": true },
	"lava": { "a": "#ff6a1a", "b": "#ff3a08", "c": "#ffd060", "rough": 0.4, "pat": "stipple", "scale": 0.8, "amt": 0.5, "world": true },
	"lava_crust": { "a": "#3a2a24", "b": "#2a1c18", "c": "#5a3a2c", "rough": 0.95, "pat": "blocks", "scale": 0.4, "amt": 0.4, "world": true },
	"vent_rim": { "a": "#4a3f3a", "b": "#372f2b", "c": "#6a5a50", "rough": 0.95, "pat": "stipple", "scale": 1.2, "amt": 0.4, "world": true },
	"scoria": { "a": "#3b3330", "b": "#2b2522", "c": "#4d4440", "rough": 0.98, "pat": "blocks", "scale": 0.35, "amt": 0.45, "world": true },
}
const FALLBACK := {
	"basalt": "pond_bed:#2b2927",
	"ash": "pond_bed:#7d7873",
	"snow": "plaster_white:#eef2f5",
	"lava": "orange_tip:#ff6a1a",
	"lava_crust": "pond_bed:#3a2a24",
	"vent_rim": "pond_bed:#4a3f3a",
	"scoria": "pond_bed:#3b3330",
}


static func role(name: String) -> String:
	return HHGenUtil.role(FALLBACK, name)


func id() -> String:
	return "caldera"


func title() -> String:
	return "Volcanic Caldera"


func kind() -> String:
	return "env"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pi("seed", "Seed", "Layout", 1, 1, 99999),
		pf("radius_m", "Floor radius (m)", "Layout", 25.0, 15.0, 30.0, 0.5),
		pi("vents", "Heat vents", "Cells", 8, 0, 16),
		pi("lava_pools", "Lava pools", "Cells", 3, 0, 6),
		pi("rocks", "Rocks", "Obstacles", 14, 0, 40),
		pf("snowline", "Snowline (rim fraction)", "Look", 0.45, 0.0, 1.0, 0.05),
	]


func presets() -> Dictionary:
	return {
		"default": {},
		"calm": { "vents": 6, "lava_pools": 2, "rocks": 10, "snowline": 0.35 },
		"furnace": { "vents": 12, "lava_pools": 4, "rocks": 18, "snowline": 0.65 },
	}


static func _validated(p: Dictionary) -> Dictionary:
	return HHCalderaGen.new().validate(p)


# ------------------------------------------------------------------ layout

## 0 on the floor, 1 at the top of the rim.
static func rim_u(L: Dictionary, r: float) -> float:
	var R: float = L.R
	if r <= R:
		return 0.0
	return clampf((r - R) / SKIRT_M, 0.0, 1.0)


static func height(L: Dictionary, x: float, z: float) -> float:
	var R: float = L.R
	var r := sqrt(x * x + z * z)
	var h := HHGenUtil.blobs_at(L.blobs, x, z) - 0.5 * (1.0 - clampf(r / R, 0.0, 1.0))
	if r > R:
		var u := rim_u(L, r)
		h += pow(u, 1.6) * RIM_M + sin(atan2(z, x) * 7.0 + float(L.rim_ph)) * u * 2.2 + sin(atan2(z, x) * 17.0) * u * 0.6
	return h


## Snow cover 0..1 at a point: the rim above the snowline, drifts on the
## floor's outer band.
static func snow_at(L: Dictionary, x: float, z: float) -> float:
	var R: float = L.R
	var r := sqrt(x * x + z * z)
	var line: float = L.snowline
	var u := rim_u(L, r)
	var s := smoothstep(line - 0.12, line + 0.08, u + 0.06 * sin(atan2(z, x) * 11.0))
	var drift := smoothstep(0.25, 0.6, HHGenUtil.blobs_at(L.snow_blobs, x, z)) * clampf((r / R - 0.45) / 0.55, 0.0, 1.0) * clampf((0.8 - line) / 0.3, 0.0, 1.0)
	return maxf(s, drift)


static func layout(q: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(q.seed)
	var R: float = q.radius_m
	var L := { "R": R, "snowline": float(q.snowline) }
	L["blobs"] = HHGenUtil.make_blobs(rng, 7, R, 4.0, 8.0, 0.3)
	L["rim_ph"] = rng.randf_range(0.0, TAU)
	var sb := HHGenUtil.make_blobs(rng, 9, R + 2.0, 2.5, 5.0, 1.0)
	for b in sb:
		(b as Dictionary).a = absf(float((b as Dictionary).a)) * 1.6
	L["snow_blobs"] = sb
	var a := HHArena.new()
	a.id = "caldera"
	a.seed = int(q.seed)
	a.radius_m = R
	a.skirt_m = SKIRT_M
	a._lay_cells()
	var p_hint := Vector2(0.0, R * 0.72)
	var m_hint := Vector2(0.0, -R * 0.7)
	var avoid: Array = [HHHex.from_world(p_hint, HHArena.HEX), HHHex.from_world(m_hint, HHArena.HEX)]
	var floor_hexes := HHGenUtil.cells_of_kind(a, "floor")
	# vents
	var vents := HHGenUtil.pick_spaced(rng, floor_hexes, int(q.vents), 3, avoid, 4)
	var taken: Array = avoid.duplicate()
	taken.append_array(vents)
	# lava pools: a centre and a hex radius of 1 or 2
	var inner: Array[Vector2i] = []
	for h in floor_hexes:
		if HHHex.to_world(h, HHArena.HEX).length() < R - 5.0:
			inner.append(h)
	var centres := HHGenUtil.pick_spaced(rng, inner, int(q.lava_pools), 8, taken, 6)
	var pools: Array = []
	for c in centres:
		var rad := 1 if rng.randf() < 0.5 else 2
		var cells: Array = []
		for h in HHHex.area(c, rad):
			if a.cells.has(h) and str((a.cells[h] as Dictionary).kind) == "floor":
				var skip := false
				if rad == 2 and HHHex.distance(h, c) == 2 and rng.randf() < 0.3:
					skip = true
				if not skip:
					cells.append(h)
		pools.append({ "c": c, "rad": rad, "cells": cells })
	L["pools"] = pools
	for pd in pools:
		taken.append((pd as Dictionary).c)
		for h in (pd as Dictionary).cells:
			var c: Dictionary = a.cells[h]
			c.kind = "lava"
			c.walkable = false
	for h in vents:
		(a.cells[h] as Dictionary).kind = "vent"
	# rocks: boulders on their own hex
	var rocks := HHGenUtil.pick_spaced(rng, floor_hexes, int(q.rocks), 2, taken, 3)
	var rock_look: Array = []
	for h in rocks:
		var c: Dictionary = a.cells[h]
		if str(c.kind) != "floor":
			continue
		c.kind = "rock"
		c.walkable = false
		rock_look.append({ "h": h, "r": rng.randf_range(0.75, 1.0), "sq": rng.randf_range(0.6, 0.9), "rot": rng.randf_range(0.0, TAU), "tint": rng.randf_range(0.8, 1.15) })
	L["rock_look"] = rock_look
	var vent_look: Array = []
	for h in vents:
		vent_look.append({ "h": h, "r": rng.randf_range(0.5, 0.7), "ph": rng.randf_range(0.0, TAU) })
	L["vent_look"] = vent_look
	# dressing: scoria stones on the floor, rim boulders
	var stones: Array = []
	for i in 80:
		var ang := rng.randf_range(0.0, TAU)
		var rr := sqrt(rng.randf()) * (R + 4.0)
		stones.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "r": rng.randf_range(0.12, 0.32), "tint": rng.randf_range(0.7, 1.1) })
	L["stones"] = stones
	var crags: Array = []
	for i in 30:
		var ang := TAU * float(i) / 30.0 + rng.randf_range(-0.08, 0.08)
		var rr := R + rng.randf_range(3.0, 11.0)
		crags.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "r": rng.randf_range(1.2, 2.6), "sq": rng.randf_range(0.7, 1.4), "rot": rng.randf_range(0.0, TAU) })
	L["crags"] = crags
	# heightfield, spawns, authored charge
	HHGenUtil.fill_hf(a, func(x: float, z: float) -> float: return height(L, x, z), HF_STEP)
	HHGenUtil.pick_spawns(a, p_hint, m_hint, 10)
	var authored: Array = []
	for h in vents:
		authored.append(HHGenUtil.author_row(h, 1, 0, "", false))
	for pd in pools:
		for h in (pd as Dictionary).cells:
			authored.append(HHGenUtil.author_row(h, 3, 0, "", false))
	a.spawns["authored"] = authored
	L["arena"] = a
	return L


# ------------------------------------------------------------------ arena

static func arena(p: Dictionary) -> HHArena:
	return layout(_validated(p)).arena


static func build_both(p: Dictionary) -> Dictionary:
	var g := HHCalderaGen.new()
	return { "arena": arena(p), "asset": g.build(p) }


static func export_dict(p: Dictionary) -> Dictionary:
	var q := _validated(p)
	return HHGenUtil.export_dict(arena(q), "caldera", 1, q)


static func export_json(p: Dictionary, path: String = "res://arenas/caldera.json") -> bool:
	return HHGenUtil.write_json(export_dict(p), path)


# ------------------------------------------------------------------ asset

func _build(q: Dictionary) -> GKAsset:
	var asset := GKAsset.new()
	var L := layout(q)
	var a: HHArena = L.arena
	var R: float = q.radius_m
	# -- ground: basalt floor, ash then snow up the rim, drifts on the outer floor
	var g := GKMesh.new()
	var basalt := role("basalt")
	var _ash := role("ash")          # the ash band is a basalt tint today; the role waits for the merge
	var snow := role("snow")
	HHGenUtil.hf_quads(g, a, func(cx: float, cz: float) -> Array:
		var r := sqrt(cx * cx + cz * cz)
		var s := snow_at(L, cx, cz)
		var u := rim_u(L, r)
		# snow where cover beats a per-quad dither: a patchy line, not a grid staircase
		var hash_v: float = sin(cx * 12.9898 + cz * 78.233) * 43758.5453
		var dither: float = hash_v - floorf(hash_v)
		if s > (0.5 + (dither - 0.5) * 0.5 if u > float(L.snowline) - 0.3 else 0.6):
			return [snow, Color.WHITE.lerp(Color(0.86, 0.9, 0.95), clampf(1.0 - s, 0.0, 1.0))]
		# ash greys the basalt up the rim as a tint, so there is no role seam
		var warm := 1.0 - clampf(r / R, 0.0, 1.0) * 0.25
		var grey := clampf(u * 3.5, 0.0, 1.0)
		return [basalt, Color(1.0, warm, warm * 0.95).lerp(Color(2.6, 2.55, 2.5), grey).lerp(Color(2.4, 2.4, 2.5), s * 2.0)])
	var ground := g.commit()
	asset.add_part("ground", ground)
	asset.add_trimesh_collider(ground)
	# -- lava pools: sunken bright hexes with a dark crust lip, glow markers
	var lg := GKMesh.new()
	var lava := role("lava")
	var crust := role("lava_crust")
	var pools: Array = L.pools
	for i in pools.size():
		var pool: Dictionary = pools[i]
		var cells: Array = pool.cells
		var centre := Vector3.ZERO
		for cd in cells:
			var h: Vector2i = cd
			var c := a.world(h)
			centre += c
			var surf := Vector3(c.x, c.y - LAVA_SINK, c.z)
			var corners := HHHex.corners(surf, HHArena.HEX * 1.0)
			var pts := PackedVector3Array()
			for k in 6:
				pts.append(corners[5 - k])
			lg.tint = Color(2.6, 1.7, 0.9)
			lg.poly(lava, pts)
			# the crust lip: a short wall from the floor down to the lava on every outside edge
			for k in 6:
				var nb := HHHex.neighbors(h)[k]
				if cells.has(nb):
					continue
				var p0 := corners[k]
				var p1 := corners[(k + 1) % 6]
				var up := Vector3(0, LAVA_SINK + 0.12, 0)
				lg.tint = Color.WHITE
				lg.quad(crust, p0 + up, p1 + up, p1, p0)
				lg.quad(crust, p0 + up, p0 + up + (p0 - surf).normalized() * 0.35, p1 + up + (p1 - surf).normalized() * 0.35, p1 + up)
		if not cells.is_empty():
			centre /= float(cells.size())
			asset.markers["glow_%d" % i] = Transform3D(Basis.IDENTITY, centre + Vector3(0, 1.2, 0))
	lg.tint = Color.WHITE
	asset.add_part("lava", lg.commit(), Transform3D.IDENTITY, false)
	# -- vents: a low cinder ring with a glowing throat
	var vg := GKMesh.new()
	var vent_rim := role("vent_rim")
	for i in (L.vent_look as Array).size():
		var v: Dictionary = L.vent_look[i]
		var c := a.world(v.h)
		var rad := float(v.r)
		vg.tint = Color.WHITE
		vg.lathe(vent_rim, c - Vector3(0, 0.05, 0), c + Vector3(0, 0.3, 0), [Vector2(0.0, rad * 1.5), Vector2(0.2, rad * 1.1), Vector2(0.35, rad * 0.55)], 8, true)
		vg.tint = Color(2.4, 1.6, 0.9)
		var pts := PackedVector3Array()
		for k in 6:
			var ang := float(v.ph) - TAU * float(k) / 6.0
			pts.append(c + Vector3(cos(ang) * rad * 0.5, 0.2, sin(ang) * rad * 0.5))
		vg.poly(lava, pts)
		asset.markers["glow_vent_%d" % i] = Transform3D(Basis.IDENTITY, c + Vector3(0, 0.8, 0))
	vg.tint = Color.WHITE
	asset.add_part("vents", vg.commit())
	# -- rocks: angular boulders on their hex, scoria scattered, crags on the rim
	var rg := GKMesh.new()
	var sc := role("scoria")
	for rd in L.rock_look:
		var rk: Dictionary = rd
		var c := a.world(rk.h)
		var rad := float(rk.r)
		var sq := float(rk.sq)
		var ti := float(rk.tint)
		rg.tint = Color(ti, ti * 0.97, ti * 0.95)
		rg.push(Transform3D(Basis(Vector3.UP, float(rk.rot)), c + Vector3(0, rad * sq * 0.5, 0)))
		rg.sphere(sc, Vector3.ZERO, rad, 5, Vector3(1.0, sq, 0.8))
		rg.sphere(sc, Vector3(rad * 0.45, rad * 0.2, -rad * 0.25), rad * 0.6, 5, Vector3(0.9, 1.1, 1.0))
		rg.pop()
	for sd in L.stones:
		var s: Dictionary = sd
		var x := float(s.x)
		var z := float(s.z)
		var ti := float(s.tint)
		rg.tint = Color(ti, ti, ti)
		rg.sphere(sc, Vector3(x, a.height_at(x, z) + float(s.r) * 0.3, z), float(s.r), 5, Vector3(1.0, 0.6, 0.8))
	for cd in L.crags:
		var cr: Dictionary = cd
		var x := float(cr.x)
		var z := float(cr.z)
		var rad := float(cr.r)
		var s := snow_at(L, x, z)
		rg.tint = Color(0.75, 0.74, 0.73).lerp(Color(1.6, 1.65, 1.7), s)
		rg.push(Transform3D(Basis(Vector3.UP, float(cr.rot)), Vector3(x, a.height_at(x, z) + rad * 0.2, z)))
		rg.sphere(sc, Vector3.ZERO, rad, 6, Vector3(1.0, float(cr.sq), 0.7))
		rg.pop()
	rg.tint = Color.WHITE
	asset.add_part("rocks", rg.commit())
	# -- markers and a hazy warm sky
	HHGenUtil.markers(asset, a, R * 1.05, R + 17.0)
	asset.lights = { "sun_dir_deg": [-38.0, -35.0], "sun_energy": 1.05, "sun_color": "#ffd6ae",
		"sky_top": "#8d8b98", "sky_horizon": "#e8c9a4", "ground_horizon": "#6a5a50", "ground_bottom": "#2c2422", "ambient": 0.55,
		"fog": { "color": "#d9bfa0", "density": 0.0012 },
		"points": { "glow": { "color": "#ff7a28", "energy": 9.0, "range": 14.0 }, "glow_vent": { "color": "#ff9040", "energy": 2.0, "range": 6.0 } } }
	var lava_cells := 0
	for pd in pools:
		lava_cells += ((pd as Dictionary).cells as Array).size()
	asset.meta = { "vents": (L.vent_look as Array).size(), "pools": pools.size(), "lava_cells": lava_cells, "rocks": (L.rock_look as Array).size(),
		"walkable": a.walkable_count(), "cells": a.cells.size(), "reach": HHGenUtil.reach_fraction(a, a.spawns.player[0]) }
	if a.path(a.spawns.player[0], a.spawns.monster).is_empty():
		asset.warnings.append("no path from the player spawn to the monster spawn")
	return asset
