extends RefCounted
## HHGladeGen: the Grassy Glade generator (Lane C/D). Determinism, trees as
## obstacles, sun patches as flagged cells, minor elevation, spawns, JSON,
## roles.


func _default() -> Dictionary:
	return HHGladeGen.new().preset("default")


func test_determinism(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a1 := HHGladeGen.arena(p)
	var a2 := HHGladeGen.arena(p)
	c.eq(JSON.stringify(HHGenUtil.export_dict(a1, "glade", 1, p)), JSON.stringify(HHGenUtil.export_dict(a2, "glade", 1, p)), "same params twice: same cells, heightfield, extras")
	var g := HHGladeGen.new()
	c.eq(g.build(p).triangle_count(), g.build(p).triangle_count(), "same params twice: same triangle count")
	var p2 := p.duplicate()
	p2.seed = 7
	c.ok(JSON.stringify(HHGladeGen.arena(p2).to_dict()) != JSON.stringify(a1.to_dict()), "another seed: another glade")
	c.eq(a1.id, "glade", "id")
	c.near(a1.radius_m, 25.0, 1e-6, "H23 radius")


func test_kinds(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHGladeGen.arena(p)
	var n := a.cells.size()
	c.ok(n > 600 and n < 900, "a 50 m floor is about 750 hexes (%d)" % n)
	var trees := HHGenUtil.cells_of_kind(a, "tree")
	var sun := HHGenUtil.cells_of_kind(a, "sun")
	c.eq(trees.size(), int(p.tree_count), "tree_count trees")
	c.ok(sun.size() >= int(p.sun_patches) * 2 and sun.size() <= int(p.sun_patches) * 9, "sun patches are a few hexes each (%d cells for %d patches)" % [sun.size(), int(p.sun_patches)])
	for h in trees:
		c.ok(not a.walkable(h), "tree impassable")
		c.ok(HHGenUtil.NO_CHARGE.has(a.kind(h)), "tree holds no charge")
	for h in sun:
		var cell: Dictionary = a.cells[h]
		c.ok(a.walkable(h), "sun walkable")
		c.ok(bool(cell.get("sun", false)), "sun cell carries sun: true")
	var reach := HHGenUtil.reach_fraction(a, a.spawns.player[0])
	c.ok(reach >= 0.95, "trees never cut the glade (%.2f reachable)" % reach)
	var lo := INF
	var hi := -INF
	for key in a.cells:
		if a.walkable(key):
			lo = minf(lo, a.hex_height(key))
			hi = maxf(hi, a.hex_height(key))
	c.ok(hi - lo > 0.15 and hi - lo < 2.0, "minor elevation (%.2f m range)" % (hi - lo))
	var none := HHGladeGen.arena({ "tree_count": 0, "sun_patches": 0 })
	c.eq(HHGenUtil.cells_of_kind(none, "tree").size() + HHGenUtil.cells_of_kind(none, "sun").size(), 0, "zero sliders: no tree or sun cells")
	for seed in [2, 3, 11]:
		var s := HHGladeGen.arena({ "seed": seed, "sun_patches": 9, "tree_count": 28 })
		c.eq(HHGenUtil.cells_of_kind(s, "tree").size(), 28, "seed %d: 28 trees placed" % seed)
		c.ok(HHGenUtil.cells_of_kind(s, "sun").size() >= 18, "seed %d: nine patches laid" % seed)


func test_spawns_and_path(c: HHSelfTest.HHCheck) -> void:
	for seed in [1, 2, 3, 11, 42]:
		var a := HHGladeGen.arena({ "seed": seed })
		var ps: Vector2i = a.spawns.player[0]
		var ms: Vector2i = a.spawns.monster
		c.ok(a.walkable(ps), "seed %d: player spawn walkable" % seed)
		c.ok(a.walkable(ms), "seed %d: monster spawn walkable" % seed)
		c.ok(HHHex.distance(ps, ms) >= 10, "seed %d: spawns at least 10 hexes apart (%d)" % [seed, HHHex.distance(ps, ms)])
		c.ok(not a.path(ps, ms).is_empty(), "seed %d: a path from player to monster" % seed)
		c.ok(HHGenUtil.reach_fraction(a, ps) >= 0.8, "seed %d: >= 80%% reachable" % seed)


func test_json_roundtrip(c: HHSelfTest.HHCheck) -> void:
	var p := _default()
	var a := HHGladeGen.arena(p)
	var d := HHGladeGen.export_dict(p)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back := HHGenUtil.from_dict(parsed)
	c.eq(back.cells.size(), a.cells.size(), "cells survive")
	c.eq(back.walkable_count(), a.walkable_count(), "walkable survives")
	var kinds_ok := true
	var sun_ok := true
	for key in a.cells:
		var h: Vector2i = key
		if back.kind(h) != a.kind(h):
			kinds_ok = false
		if a.kind(h) == "sun" and not bool((back.cells[h] as Dictionary).get("sun", false)):
			sun_ok = false
	c.ok(kinds_ok, "kinds survive JSON")
	c.ok(sun_ok, "sun flag survives through the extras block")
	c.eq(back.spawns.monster, a.spawns.monster, "spawns survive")
	c.near(back.height_at(3.3, -2.1), a.height_at(3.3, -2.1), 1e-4, "heightfield survives")
	c.eq(str((parsed.gen as Dictionary).id), "glade", "gen block names the generator")
	c.eq((parsed.authored as Array).size(), 0, "the glade authors no charge")
	var again := HHGladeGen.arena((parsed.gen as Dictionary).params)
	c.eq(JSON.stringify(again.to_dict()), JSON.stringify(a.to_dict()), "rebuilt from the gen block: identical")


func test_roles_and_asset(c: HHSelfTest.HHCheck) -> void:
	var asset := HHGladeGen.new().build(_default())
	var seen := {}
	for part in asset.parts:
		var m: ArrayMesh = part.mesh
		for i in m.get_surface_count():
			var r := m.surface_get_name(i)
			var base := r.substr(0, r.find(":")) if r.find(":") >= 0 else r
			seen[r] = true
			c.ok(GKMaterials.has(r) or HHGladeGen.ROLES.has(base), "role '%s' exists in GKMaterials or HHGladeGen.ROLES" % r)
	c.ok(seen.size() >= 4, "several roles in use (%d)" % seen.size())
	for k in HHGladeGen.ROLES:
		var e: Dictionary = HHGladeGen.ROLES[k]
		c.ok(e.has("a") and e.has("rough") and e.has("pat"), "ROLES['%s'] has the GKMaterials entry shape" % k)
		c.ok(HHGladeGen.FALLBACK.has(k), "ROLES['%s'] has a fallback until merged" % k)
	c.eq(asset.kind, "env", "env asset")
	c.ok(asset.markers.has("spawn_player") and asset.markers.has("spawn_monster") and asset.markers.has("ref_cam"), "markers present")
	c.ok(float(asset.lights.sun_energy) >= 1.4, "a bright sunny look: sun energy %.2f" % float(asset.lights.sun_energy))
	c.ok(asset.warnings.is_empty(), "no build warnings: %s" % [asset.warnings])
	for name in ["default", "sparse", "thick"]:
		var g := HHGladeGen.new()
		var tris := g.build(g.preset(name)).triangle_count()
		c.ok(tris < 80000, "preset %s under 80k tris (%d)" % [name, tris])
