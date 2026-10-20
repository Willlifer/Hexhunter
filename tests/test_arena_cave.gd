extends RefCounted
## HHCaveGen: the Cave generator (Lane C/D). Determinism, terraces and ramps
## keep the floor connected, pillars carry hp, rocks and pillars are
## impassable, shade cells are authored cold, spawns, JSON, roles.


func _default() -> Dictionary:
	return HHCaveGen.new().preset("default")


func test_determinism(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a1 := HHCaveGen.arena(p)
	var a2 := HHCaveGen.arena(p)
	c.eq(JSON.stringify(HHGenUtil.export_dict(a1, "cave", 1, p)), JSON.stringify(HHGenUtil.export_dict(a2, "cave", 1, p)), "same params twice: same cells, heightfield, extras, authored")
	var g := HHCaveGen.new()
	c.eq(g.build(p).triangle_count(), g.build(p).triangle_count(), "same params twice: same triangle count")
	var p2 := p.duplicate()
	p2.seed = 7
	c.ok(JSON.stringify(HHCaveGen.arena(p2).to_dict()) != JSON.stringify(a1.to_dict()), "another seed: another cave")
	c.eq(a1.id, "cave", "id")
	c.near(a1.radius_m, 25.0, 1e-6, "H23 radius")


func test_kinds(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHCaveGen.arena(p)
	var n := a.cells.size()
	c.ok(n > 600 and n < 900, "a 50 m floor is about 750 hexes (%d)" % n)
	var pillars := HHGenUtil.cells_of_kind(a, "pillar")
	var rocks := HHGenUtil.cells_of_kind(a, "rock")
	var shade := HHGenUtil.cells_of_kind(a, "shade")
	var edge := HHGenUtil.cells_of_kind(a, "edge")
	c.eq(pillars.size(), int(p.pillar_count), "pillar_count pillars")
	c.eq(rocks.size(), int(p.rock_count), "rock_count rocks")
	c.ok(shade.size() >= int(p.shade_count) and shade.size() <= int(p.shade_count) * 5, "shade clusters (%d cells for %d corners)" % [shade.size(), int(p.shade_count)])
	c.ok(edge.size() > 60, "an edge band (H17) (%d)" % edge.size())
	for h in pillars:
		var cell: Dictionary = a.cells[h]
		c.ok(not a.walkable(h), "pillar impassable")
		c.ok(cell.has("hp") and float(cell.hp) > 0.0, "pillar carries hp")
		c.eq(str(cell.get("kind_after", "")), "floor", "pillar becomes floor when broken")
	for h in rocks:
		c.ok(not a.walkable(h), "rock impassable")
	for h in shade:
		c.ok(a.walkable(h), "shade walkable")
	for h in edge:
		c.ok(not a.walkable(h), "edge unwalkable")
	var none := HHCaveGen.arena({ "pillar_count": 0, "rock_count": 0, "shade_count": 0 })
	c.eq(HHGenUtil.cells_of_kind(none, "pillar").size() + HHGenUtil.cells_of_kind(none, "rock").size() + HHGenUtil.cells_of_kind(none, "shade").size(), 0, "zero sliders: no obstacle or shade cells")


func test_terraces_and_ramps(c: HHSelfTest.HHCheck) -> void:
	var a := HHCaveGen.arena(_default())
	var levels := {}
	for key in a.cells:
		if a.walkable(key):
			levels[int(round(a.hex_height(key) / HHCaveGen.RAMP_M))] = true
	c.ok(levels.size() >= 3, "plenty of elevation change: %d distinct terrace heights" % levels.size())
	var cliffs := 0
	var steps := 0
	for key in a.cells:
		var h: Vector2i = key
		if not a.walkable(h):
			continue
		for n in a.neighbors(h):
			if not a.walkable(n):
				continue
			var d := absf(a.hex_height(n) - a.hex_height(h))
			if d > HHTune.value("max_step_m"):
				cliffs += 1
			elif d > 0.3:
				steps += 1
	c.ok(cliffs > 20, "terrace edges are cliffs (%d blocked neighbour pairs)" % cliffs)
	c.ok(steps > 10, "ramps exist: %d walkable steps between terraces" % steps)
	for seed in [1, 2, 3, 11, 42]:
		var s := HHCaveGen.arena({ "seed": seed })
		var frac := HHGenUtil.reach_fraction(s, s.spawns.player[0])
		c.ok(frac >= 0.8, "seed %d: the player reaches >= 80%% of the walkable floor (%.2f)" % [seed, frac])
	var flat := HHCaveGen.arena({ "terraces": 1 })
	c.ok(HHGenUtil.reach_fraction(flat, flat.spawns.player[0]) >= 0.9, "one terrace: nearly all reachable")
	var maze := HHCaveGen.arena(HHCaveGen.new().preset("maze"))
	c.ok(HHGenUtil.reach_fraction(maze, maze.spawns.player[0]) >= 0.8, "maze preset still connected")


func test_spawns_and_path(c: HHSelfTest.HHCheck) -> void:
	for seed in [1, 2, 3, 11, 42]:
		var a := HHCaveGen.arena({ "seed": seed })
		var ps: Vector2i = a.spawns.player[0]
		var ms: Vector2i = a.spawns.monster
		c.ok(a.walkable(ps), "seed %d: player spawn walkable" % seed)
		c.ok(a.walkable(ms), "seed %d: monster spawn walkable" % seed)
		c.ok(HHHex.distance(ps, ms) >= 10, "seed %d: spawns at least 10 hexes apart (%d)" % [seed, HHHex.distance(ps, ms)])
		c.ok(not a.path(ps, ms).is_empty(), "seed %d: a path from player to monster" % seed)


func test_authored(c: HHSelfTest.HHCheck) -> void:
	var a := HHCaveGen.arena(_default())
	var rows := HHGenUtil.authored(a)
	var shade := HHGenUtil.cells_of_kind(a, "shade")
	c.eq(rows.size(), shade.size(), "one authored row per shade cell")
	for rd in rows:
		var r: Dictionary = rd
		var h := Vector2i(int(r.q), int(r.r))
		c.eq(a.kind(h), "shade", "authored row sits on a shade cell")
		c.eq(int(r.h), -1, "shade is water 1")
		c.ok(bool(r.glaze), "shade is glazed")
		c.ok(not HHGenUtil.NO_CHARGE.has(a.kind(h)), "authored cells can hold charge")


func test_json_roundtrip(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHCaveGen.arena(p)
	var d := HHCaveGen.export_dict(p)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back := HHGenUtil.from_dict(parsed)
	c.eq(back.cells.size(), a.cells.size(), "cells survive")
	c.eq(back.walkable_count(), a.walkable_count(), "walkable survives")
	var kinds_ok := true
	var hp_ok := true
	for key in a.cells:
		var h: Vector2i = key
		if back.kind(h) != a.kind(h):
			kinds_ok = false
		if a.kind(h) == "pillar" and absf(float((back.cells[h] as Dictionary).get("hp", -1.0)) - HHCaveGen.PILLAR_HP) > 1e-6:
			hp_ok = false
	c.ok(kinds_ok, "kinds survive JSON")
	c.ok(hp_ok, "pillar hp survives through the extras block")
	c.eq(back.spawns.monster, a.spawns.monster, "spawns survive")
	c.near(back.height_at(3.3, -2.1), a.height_at(3.3, -2.1), 1e-4, "heightfield survives")
	c.eq(HHGenUtil.authored(back).size(), HHGenUtil.authored(a).size(), "authored rows survive")
	c.eq(str((parsed.gen as Dictionary).id), "cave", "gen block names the generator")
	var again := HHCaveGen.arena((parsed.gen as Dictionary).params)
	c.eq(JSON.stringify(again.to_dict()), JSON.stringify(a.to_dict()), "rebuilt from the gen block: identical")


func test_roles_and_asset(c: HHSelfTest.HHCheck) -> void:
	var asset := HHCaveGen.new().build(_default())
	var seen := {}
	for part in asset.parts:
		var m: ArrayMesh = part.mesh
		for i in m.get_surface_count():
			var r := m.surface_get_name(i)
			var base := r.substr(0, r.find(":")) if r.find(":") >= 0 else r
			seen[r] = true
			c.ok(GKMaterials.has(r) or HHCaveGen.ROLES.has(base), "role '%s' exists in GKMaterials or HHCaveGen.ROLES" % r)
	c.ok(seen.size() >= 4, "several roles in use (%d)" % seen.size())
	for k in HHCaveGen.ROLES:
		var e: Dictionary = HHCaveGen.ROLES[k]
		c.ok(e.has("a") and e.has("rough") and e.has("pat"), "ROLES['%s'] has the GKMaterials entry shape" % k)
		c.ok(HHCaveGen.FALLBACK.has(k), "ROLES['%s'] has a fallback until merged" % k)
	c.eq(asset.kind, "env", "env asset")
	c.ok(asset.markers.has("spawn_player") and asset.markers.has("spawn_monster") and asset.markers.has("ref_cam"), "markers present")
	c.ok(asset.markers.has("torch_0"), "torch markers present")
	c.ok((asset.lights.get("points", {}) as Dictionary).has("torch"), "torch point-light spec in lights")
	c.ok(float(asset.lights.sun_energy) < 0.6, "noticeably dark: sun energy %.2f" % float(asset.lights.sun_energy))
	c.ok(asset.warnings.is_empty(), "no build warnings: %s" % [asset.warnings])
	for name in ["default", "open", "maze"]:
		var g := HHCaveGen.new()
		var tris := g.build(g.preset(name)).triangle_count()
		c.ok(tris < 80000, "preset %s under 80k tris (%d)" % [name, tris])
