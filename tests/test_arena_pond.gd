extends RefCounted
## HHPondGen: the Shallow Lilypad Pond generator (Lane C). Determinism,
## the water rules, pads as cover, spawns, pathing, JSON, material roles.


func _default() -> Dictionary:
	return HHPondGen.new().preset("default")


func test_determinism(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a1 := HHPondGen.arena(p)
	var a2 := HHPondGen.arena(p)
	c.eq(JSON.stringify(a1.to_dict()), JSON.stringify(a2.to_dict()), "same params twice: same cell dict and heightfield")
	var g := HHPondGen.new()
	c.eq(g.build(p).triangle_count(), g.build(p).triangle_count(), "same params twice: same triangle count")
	var p2 := p.duplicate()
	p2.seed = 7
	c.ok(JSON.stringify(HHPondGen.arena(p2).to_dict()) != JSON.stringify(a1.to_dict()), "another seed: another pond")
	c.ok(g.build(p).triangle_count() > 2000, "the asset has real geometry (%d tris)" % g.build(p).triangle_count())


func test_walkable_band(c: HHSelfTest.HHCheck) -> void:
	var a := HHPondGen.arena(_default())
	var n := a.cells.size()
	var w := a.walkable_count()
	c.ok(n > 600 and n < 900, "a 50 m floor is about 750 hexes (%d)" % n)
	c.ok(w > n * 0.6 and w < n * 0.95, "most of the pond is walkable, not all (%d / %d)" % [w, n])
	c.eq(a.id, "pond", "id")
	c.near(a.radius_m, 25.0, 1e-6, "H23 radius")
	var edge := 0
	for key in a.cells:
		var h: Vector2i = key
		if a.kind(h) == "edge":
			edge += 1
			c.ok(not a.walkable(h), "edge hexes unwalkable (H17)")
	c.ok(edge > 60, "an edge band exists (%d)" % edge)


func test_water_rules(c: HHSelfTest.HHCheck) -> void:
	var a := HHPondGen.arena(_default())
	var water := 0
	var deep := 0
	var shore := 0
	for key in a.cells:
		var h: Vector2i = key
		var k := a.kind(h)
		if k == "water":
			water += 1
			c.ok(a.depth(h) > 0.0, "water carries depth")
			if a.depth(h) > HHPondGen.DEEP_M:
				deep += 1
				c.ok(not a.walkable(h), "deep water is unwalkable")
			else:
				c.ok(a.walkable(h), "shallow water is wadeable")
			c.ok(a.hex_height(h) < 0.0, "the bed is below the surface")
		elif k == "floor":
			shore += 1
			c.near(a.depth(h), 0.0, 1e-6, "shore is dry")
	c.ok(water > 300, "a lake (%d water hexes)" % water)
	c.ok(deep > 10 and deep < water / 4, "deep pools exist and are small (%d of %d)" % [deep, water])
	c.ok(shore > 60, "a shore (%d floor hexes)" % shore)
	c.near(a.depth(Vector2i(0, 0)), -a.hex_height(Vector2i(0, 0)), 1e-5, "depth = water level - bed at the centre")
	var dry := HHPondGen.arena({ "water_depth": 0.0 })
	var any_deep := false
	for key in dry.cells:
		if dry.kind(key) == "water" and not dry.walkable(key):
			any_deep = true
	c.ok(not any_deep, "water_depth 0: no deep water")


func test_pads(c: HHSelfTest.HHCheck) -> void:
	var a := HHPondGen.arena(_default())
	var pads := 0
	var cover := 0
	for key in a.cells:
		var h: Vector2i = key
		if a.kind(h) == "pad":
			pads += 1
			c.ok(a.walkable(h), "pads are walkable")
			var cell: Dictionary = a.cells[h]
			c.ok(cell.has("cover"), "pads carry a cover flag")
			if bool(cell.get("cover", false)):
				cover += 1
	c.ok(pads >= 20, "the default preset lays big pads (%d)" % pads)
	c.ok(cover >= 1 and cover <= pads, "a pad or two to hide behind (%d cover of %d)" % [cover, pads])
	c.eq(HHPondGen.cover_hexes(a).size(), cover, "cover_hexes lists them")
	var none := HHPondGen.arena({ "lilypad_count": 0 })
	var np := 0
	for key in none.cells:
		if none.kind(key) == "pad":
			np += 1
	c.eq(np, 0, "lilypad_count 0: no pad hexes")


func test_spawns_and_path(c: HHSelfTest.HHCheck) -> void:
	for seed in [1, 2, 3, 11, 42]:
		var a := HHPondGen.arena({ "seed": seed })
		var ps: Vector2i = a.spawns.player[0]
		var ms: Vector2i = a.spawns.monster
		c.ok(a.walkable(ps), "seed %d: player spawn walkable" % seed)
		c.ok(a.walkable(ms), "seed %d: monster spawn walkable" % seed)
		c.ok(HHHex.distance(ps, ms) >= 10, "seed %d: spawns at least 10 hexes apart (%d)" % [seed, HHHex.distance(ps, ms)])
		c.ok(not a.path(ps, ms).is_empty(), "seed %d: a path from player to monster" % seed)
		c.ok(a.depth(ms) <= HHPondGen.DEEP_M, "seed %d: the monster spawns on the pool rim, not in it" % seed)


func test_json_roundtrip(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHPondGen.arena(p)
	var d := HHPondGen.export_dict(p)
	var s := JSON.stringify(d)
	var parsed: Dictionary = JSON.parse_string(s)
	var back := HHArena.from_dict(parsed)
	c.eq(back.cells.size(), a.cells.size(), "cells survive")
	c.eq(back.walkable_count(), a.walkable_count(), "walkable survives")
	var kinds_ok := true
	var depths_ok := true
	for key in a.cells:
		var h: Vector2i = key
		if back.kind(h) != a.kind(h):
			kinds_ok = false
		if absf(back.depth(h) - a.depth(h)) > 1e-4:
			depths_ok = false
	c.ok(kinds_ok, "kinds survive JSON")
	c.ok(depths_ok, "depths survive JSON")
	c.eq(back.spawns.monster, a.spawns.monster, "spawns survive")
	c.near(back.height_at(3.3, -2.1), a.height_at(3.3, -2.1), 1e-4, "heightfield survives")
	c.eq(str((parsed.gen as Dictionary).id), "pond", "gen block names the generator")
	c.eq(int((parsed.gen as Dictionary).params.seed), int(p.seed), "gen block carries the params")
	c.eq((parsed.cover as Array).size(), HHPondGen.cover_hexes(a).size(), "cover list exported")
	var again := HHPondGen.arena((parsed.gen as Dictionary).params)
	c.eq(JSON.stringify(again.to_dict()), JSON.stringify(a.to_dict()), "rebuilt from the gen block: identical")


func test_roles_exist(c: HHSelfTest.HHCheck) -> void:
	var asset := HHPondGen.new().build(_default())
	var seen := {}
	for part in asset.parts:
		var m: ArrayMesh = part.mesh
		for i in m.get_surface_count():
			var r := m.surface_get_name(i)
			var base := r.substr(0, r.find(":")) if r.find(":") >= 0 else r
			seen[r] = true
			c.ok(GKMaterials.has(r) or HHPondGen.ROLES.has(base), "role '%s' exists in GKMaterials or HHPondGen.ROLES" % r)
	c.ok(seen.size() >= 5, "several roles in use (%d)" % seen.size())
	for k in HHPondGen.ROLES:
		var e: Dictionary = HHPondGen.ROLES[k]
		c.ok(e.has("a") and e.has("rough") and e.has("pat"), "ROLES['%s'] has the GKMaterials entry shape" % k)
		c.ok(HHPondGen.FALLBACK.has(k), "ROLES['%s'] has a fallback until merged" % k)
	c.eq(asset.kind, "env", "env asset")
	c.ok(asset.markers.has("spawn_player") and asset.markers.has("spawn_monster") and asset.markers.has("ref_cam"), "markers present")
	c.ok(not asset.lights.is_empty(), "lights present")
	c.ok(asset.warnings.is_empty(), "no build warnings: %s" % [asset.warnings])
	for name in ["default", "sparse", "dense"]:
		var g := HHPondGen.new()
		var pr := g.preset(name)
		c.ok(g.build(pr).triangle_count() < 120000, "preset %s within a tris budget" % name)
