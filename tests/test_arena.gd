extends RefCounted
## HHArena: the underlay, the heightfield and pathing.


func test_round_shape(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 17.5, 0.0)
	c.ok(a.cells.size() > 300, "a 35 m floor has hundreds of hexes (%d)" % a.cells.size())
	c.ok(a.walkable_count() < a.cells.size(), "an edge band is unwalkable")
	c.ok(a.walkable(Vector2i(0, 0)), "centre walkable")
	var far := Vector2i(11, 0)
	c.ok(not a.walkable(far) or not a.exists(far), "far out is edge or absent")
	for h in a.cells:
		var d := HHHex.to_world(h, HHArena.HEX).length()
		c.ok(d <= a.radius_m + 1e-6, "every cell inside the radius")
	c.ok(a.exists(a.spawns.player[0]) and a.walkable(a.spawns.player[0]), "player spawn walkable")
	c.ok(a.walkable(a.spawns.monster), "monster spawn walkable")


func test_heightfield_flat_and_bowl(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 17.5, 0.0)
	c.near(a.height_at(0.0, 0.0), 0.0, 1e-6, "flat centre")
	c.near(a.height_at(5.0, -3.0), 0.0, 1e-6, "flat floor")
	c.ok(a.height_at(26.0, 0.0) > 3.0, "the skirt rises into a wall")
	var b := HHArena.round_flat(7, 17.5, 0.6)
	var any := false
	for h in b.cells:
		if absf(b.hex_height(h)) > 0.05:
			any = true
	c.ok(any, "bumps make relief")
	c.ok(b.walkable_count() > 200, "relief leaves most of the floor walkable (%d)" % b.walkable_count())
	var w := b.world(Vector2i(2, 3))
	c.near(w.y, b.hex_height(Vector2i(2, 3)), 1e-6, "world() carries the height")
	c.eq(b.from_world(w), Vector2i(2, 3), "from_world inverts world")


func test_path(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 17.5, 0.0)
	var from := Vector2i(0, 0)
	var to := Vector2i(5, 3)
	var p := a.path(from, to)
	c.eq(p.size(), HHHex.distance(from, to), "shortest path on open ground")
	c.eq(p[-1], to, "ends at the goal")
	c.ok(a.path(from, from).is_empty(), "no path to self")
	c.ok(a.path(from, Vector2i(50, 50)).is_empty(), "no path off the arena")
	var edge := Vector2i(0, 11)
	var nw := a.nearest_walkable(from, edge)
	c.ok(a.walkable(nw), "nearest walkable is walkable")
	c.ok(HHHex.distance(nw, edge) <= 3, "and near the edge click")
	# a wall of blocked hexes forces a detour
	var blocked := {}
	for r in range(-3, 4):
		blocked[Vector2i(2, r)] = true
	var det := a.path(from, Vector2i(4, 0), blocked)
	c.ok(det.size() > 4, "detour is longer (%d)" % det.size())
	for h in det:
		c.ok(not blocked.has(h), "detour avoids the wall")


func test_path_to_reach(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 17.5, 0.0)
	var from := Vector2i(-5, 0)
	var target := Vector2i(4, 0)
	var p := a.path_to_reach(from, target, 2)
	c.ok(not p.is_empty(), "walks toward the target")
	c.eq(HHHex.distance(p[-1], target), 2, "stops at reach")
	c.ok(a.path_to_reach(Vector2i(3, 0), target, 2).is_empty(), "already in reach: no path")


func test_cliffs(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 17.5, 0.0)
	# raise a ridge in the heightfield and check the step rule
	var cols: int = a.hf.cols
	var data: PackedFloat32Array = a.hf.data
	for j in a.hf.rows:
		for i in cols:
			var x: float = float(a.hf.origin[0]) + i * float(a.hf.step)
			if x > 2.0 and x < 5.0:
				data[j * cols + i] = 4.0
	a.hf.data = data
	var p := a.path(Vector2i(0, 0), Vector2i(5, 0))
	c.ok(p.is_empty(), "a 4 m ridge is a cliff: no path across")
	HHTune.set_value("max_step_m", 10.0)
	c.ok(not a.path(Vector2i(0, 0), Vector2i(5, 0)).is_empty(), "raising max_step_m opens it")
	HHTune.reset()


func test_roundtrip_json(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(3, 12.0, 0.4)
	var d := a.to_dict()
	var s := JSON.stringify(d)
	var back := HHArena.from_dict(JSON.parse_string(s))
	c.eq(back.cells.size(), a.cells.size(), "cells survive JSON")
	c.eq(back.walkable_count(), a.walkable_count(), "walkable survives JSON")
	c.near(back.height_at(3.3, -2.1), a.height_at(3.3, -2.1), 1e-4, "heightfield survives JSON")
	c.eq(back.spawns.monster, a.spawns.monster, "spawns survive JSON")
