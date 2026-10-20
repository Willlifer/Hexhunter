extends RefCounted
## H43-H44: authored biome charge, destructible pillars, re-forming vents.


func _arena() -> HHArena:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	a.cells[Vector2i(2, 0)] = { "walkable": false, "kind": "pillar", "depth": 0.0, "hp": 120.0, "kind_after": "floor" }
	a.cells[Vector2i(-2, 0)] = { "walkable": true, "kind": "vent", "depth": 0.0 }
	a.cells[Vector2i(0, -3)] = { "walkable": true, "kind": "shade", "depth": 0.0 }
	a.authored = [{ "q": -2, "r": 0, "h": 1, "v": 0, "marker": "" }, { "q": 0, "r": -3, "h": -1, "v": 0, "marker": "", "glaze": true }]
	return a


func test_authored_at_start_and_reform(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(_arena(), 1)
	s.add_player("p1", Vector2i(0, 6))
	c.eq(s.charge.intensity(Vector2i(-2, 0), "fire"), 1, "vent carries fire 1 at start")
	c.ok(s.charge.is_glazed(Vector2i(0, -3)), "shade is glazed water")
	s.paint([Vector2i(-2, 0)], "water", "env", 1)
	c.eq(s.charge.intensity(Vector2i(-2, 0), "fire"), 0, "doused")
	for i in int(HHTune.value("authored_reform_every")) + 1:
		s.step()
	c.eq(s.charge.intensity(Vector2i(-2, 0), "fire"), 1, "the vent re-formed")
	for i in int(HHTune.value("charge_glaze_ticks")) + 5:
		s.step()
	c.ok(s.charge.is_glazed(Vector2i(0, -3)), "authored frost never thaws")


func test_pillar_breaks(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(_arena(), 1)
	s.add_player("p1", Vector2i(0, 6))
	var h := Vector2i(2, 0)
	c.ok(not s.arena.walkable(h), "pillar blocks")
	c.ok(not s.charge.can_hold(h), "pillar holds no charge")
	var broke := false
	for i in 3:
		for e in s.paint([h], "fire", "p1", 1).changed:
			pass
		for e in s.events:
			if e.type == "cell_broken":
				broke = true
	c.ok(broke, "three casts of 60 break a 120 hp pillar")
	c.ok(s.arena.walkable(h), "it is floor now")
	c.eq(s.arena.kind(h), "floor", "kind_after applied")
	c.ok(s.charge.can_hold(h), "and holds charge")


func test_biome_json_keeps_extras(c: HHSelfTest.HHCheck) -> void:
	var a := _arena()
	var back := HHArena.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	c.eq(back.kind(Vector2i(2, 0)), "pillar", "pillar survives")
	c.near(float(back.cells[Vector2i(2, 0)].hp), 120.0, 1e-6, "hp survives")
	c.eq(back.authored.size(), 2, "authored rows survive")
