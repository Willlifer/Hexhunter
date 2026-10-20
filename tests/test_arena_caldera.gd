extends RefCounted
## HHCalderaGen: the Volcanic Caldera generator (Lane C/D). Determinism,
## vents and lava pools as cells with authored fire, rocks impassable, the
## snow rim, spawns, JSON, roles.


func _default() -> Dictionary:
	return HHCalderaGen.new().preset("default")


func test_determinism(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a1 := HHCalderaGen.arena(p)
	var a2 := HHCalderaGen.arena(p)
	c.eq(JSON.stringify(HHGenUtil.export_dict(a1, "caldera", 1, p)), JSON.stringify(HHGenUtil.export_dict(a2, "caldera", 1, p)), "same params twice: same cells, heightfield, authored")
	var g := HHCalderaGen.new()
	c.eq(g.build(p).triangle_count(), g.build(p).triangle_count(), "same params twice: same triangle count")
	var p2 := p.duplicate()
	p2.seed = 7
	c.ok(JSON.stringify(HHCalderaGen.arena(p2).to_dict()) != JSON.stringify(a1.to_dict()), "another seed: another caldera")
	c.eq(a1.id, "caldera", "id")
	c.near(a1.radius_m, 25.0, 1e-6, "H23 radius")


func test_kinds(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHCalderaGen.arena(p)
	var n := a.cells.size()
	c.ok(n > 600 and n < 900, "a 50 m floor is about 750 hexes (%d)" % n)
	var vents := HHGenUtil.cells_of_kind(a, "vent")
	var lava := HHGenUtil.cells_of_kind(a, "lava")
	var rocks := HHGenUtil.cells_of_kind(a, "rock")
	c.eq(vents.size(), int(p.vents), "vents slider = vent cells")
	c.ok(lava.size() >= int(p.lava_pools) and lava.size() <= int(p.lava_pools) * 19, "lava pools of radius 1-2 (%d cells for %d pools)" % [lava.size(), int(p.lava_pools)])
	c.ok(rocks.size() >= int(p.rocks) - 2 and rocks.size() <= int(p.rocks), "rocks placed (%d of %d)" % [rocks.size(), int(p.rocks)])
	for h in vents:
		c.ok(a.walkable(h), "vent walkable")
	for h in lava:
		c.ok(not a.walkable(h), "lava impassable")
	for h in rocks:
		c.ok(not a.walkable(h), "rock impassable")
	var reach := HHGenUtil.reach_fraction(a, a.spawns.player[0])
	c.ok(reach >= 0.9, "pools and rocks never cut the floor (%.2f reachable)" % reach)
	var none := HHCalderaGen.arena({ "vents": 0, "lava_pools": 0, "rocks": 0 })
	c.eq(HHGenUtil.cells_of_kind(none, "vent").size() + HHGenUtil.cells_of_kind(none, "lava").size() + HHGenUtil.cells_of_kind(none, "rock").size(), 0, "zero sliders: a bare bowl")
	var furnace := HHCalderaGen.arena(HHCalderaGen.new().preset("furnace"))
	c.eq(HHGenUtil.cells_of_kind(furnace, "vent").size(), 12, "furnace: 12 vents")
	c.ok(HHGenUtil.cells_of_kind(furnace, "lava").size() >= 4, "furnace: four pools")


func test_rim(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHCalderaGen.arena(p)
	var R := a.radius_m
	c.ok(a.height_at(0.0, R + a.skirt_m) - a.height_at(0.0, R - 3.0) > 8.0, "the rim rises well above the floor")
	var L := HHCalderaGen.layout(HHCalderaGen.new().validate(p))
	c.ok(HHCalderaGen.snow_at(L, 0.0, R + a.skirt_m * 0.98) > 0.9, "snow on top of the rim")
	c.ok(HHCalderaGen.snow_at(L, 0.0, R + a.skirt_m * 0.1) < 0.5, "ash, not snow, low on the rim")
	var lo := INF
	var hi := -INF
	for key in a.cells:
		if a.walkable(key):
			lo = minf(lo, a.hex_height(key))
			hi = maxf(hi, a.hex_height(key))
	c.ok(hi - lo < 2.5, "the floor is a gentle dish (%.2f m range)" % (hi - lo))


func test_spawns_and_path(c: HHSelfTest.HHCheck) -> void:
	for seed in [1, 2, 3, 11, 42]:
		var a := HHCalderaGen.arena({ "seed": seed })
		var ps: Vector2i = a.spawns.player[0]
		var ms: Vector2i = a.spawns.monster
		c.ok(a.walkable(ps), "seed %d: player spawn walkable" % seed)
		c.ok(a.walkable(ms), "seed %d: monster spawn walkable" % seed)
		c.ok(HHHex.distance(ps, ms) >= 10, "seed %d: spawns at least 10 hexes apart (%d)" % [seed, HHHex.distance(ps, ms)])
		c.ok(not a.path(ps, ms).is_empty(), "seed %d: a path from player to monster" % seed)
		c.ok(HHGenUtil.reach_fraction(a, ps) >= 0.8, "seed %d: >= 80%% reachable" % seed)


func test_authored(c: HHSelfTest.HHCheck) -> void:
	var a := HHCalderaGen.arena(_default())
	var rows := HHGenUtil.authored(a)
	var vents := HHGenUtil.cells_of_kind(a, "vent")
	var lava := HHGenUtil.cells_of_kind(a, "lava")
	c.eq(rows.size(), vents.size() + lava.size(), "one authored row per vent and lava cell")
	for rd in rows:
		var r: Dictionary = rd
		var h := Vector2i(int(r.q), int(r.r))
		var k := a.kind(h)
		c.ok(k == "vent" or k == "lava", "authored row on a vent or lava cell")
		c.eq(int(r.h), 1 if k == "vent" else 3, "vent fire 1, lava fire 3")
		c.ok(int(r.h) <= HHCharge.AXIS_MAX, "within the charge axis")
		c.ok(not HHGenUtil.NO_CHARGE.has(k), "authored cells can hold charge")


func test_json_roundtrip(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHCalderaGen.arena(p)
	var d := HHCalderaGen.export_dict(p)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back := HHGenUtil.from_dict(parsed)
	c.eq(back.cells.size(), a.cells.size(), "cells survive")
	c.eq(back.walkable_count(), a.walkable_count(), "walkable survives")
	var kinds_ok := true
	for key in a.cells:
		if back.kind(key) != a.kind(key):
			kinds_ok = false
	c.ok(kinds_ok, "kinds survive JSON")
	c.eq(back.spawns.monster, a.spawns.monster, "spawns survive")
	c.near(back.height_at(3.3, -2.1), a.height_at(3.3, -2.1), 1e-4, "heightfield survives")
	c.eq(HHGenUtil.authored(back).size(), HHGenUtil.authored(a).size(), "authored rows survive")
	c.eq(str((parsed.gen as Dictionary).id), "caldera", "gen block names the generator")
	var again := HHCalderaGen.arena((parsed.gen as Dictionary).params)
	c.eq(JSON.stringify(again.to_dict()), JSON.stringify(a.to_dict()), "rebuilt from the gen block: identical")


func test_roles_and_asset(c: HHSelfTest.HHCheck) -> void:
	var asset := HHCalderaGen.new().build(_default())
	var seen := {}
	for part in asset.parts:
		var m: ArrayMesh = part.mesh
		for i in m.get_surface_count():
			var r := m.surface_get_name(i)
			var base := r.substr(0, r.find(":")) if r.find(":") >= 0 else r
			seen[r] = true
			c.ok(GKMaterials.has(r) or HHCalderaGen.ROLES.has(base), "role '%s' exists in GKMaterials or HHCalderaGen.ROLES" % r)
	c.ok(seen.size() >= 4, "several roles in use (%d)" % seen.size())
	for k in HHCalderaGen.ROLES:
		var e: Dictionary = HHCalderaGen.ROLES[k]
		c.ok(e.has("a") and e.has("rough") and e.has("pat"), "ROLES['%s'] has the GKMaterials entry shape" % k)
		c.ok(HHCalderaGen.FALLBACK.has(k), "ROLES['%s'] has a fallback until merged" % k)
	c.eq(asset.kind, "env", "env asset")
	c.ok(asset.markers.has("spawn_player") and asset.markers.has("spawn_monster") and asset.markers.has("ref_cam"), "markers present")
	c.ok(asset.markers.has("glow_0"), "lava glow markers present")
	c.ok((asset.lights.get("points", {}) as Dictionary).has("glow"), "glow point-light spec in lights")
	c.ok(asset.lights.has("fog"), "a hazy sky")
	c.ok(asset.warnings.is_empty(), "no build warnings: %s" % [asset.warnings])
	for name in ["default", "calm", "furnace"]:
		var g := HHCalderaGen.new()
		var tris := g.build(g.preset(name)).triangle_count()
		c.ok(tris < 80000, "preset %s under 80k tris (%d)" % [name, tris])
