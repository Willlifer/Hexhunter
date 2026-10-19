extends RefCounted
## HHFormulas, HHPhases, HHTune, HHTileFX mapping, the GK kit.


func test_formulas(c: HHSelfTest.HHCheck) -> void:
	var d := HHFormulas.tile_damage(1000.0, 10.0)
	c.near(d.value, 100.0, 1e-6, "10% of 1000")
	c.ok(d.has("formula") and d.has("values"), "calc carries its breakdown")
	c.near(HHFormulas.tile_damage(1000.0, 10.0, 50.0).value, 50.0, 1e-6, "resist halves")
	c.near(HHFormulas.tile_damage(1000.0, 10.0, 99.0).value, 25.0, 1e-6, "resist capped at 75")
	c.near(HHFormulas.tile_damage(1000.0, 0.0).value, 0.0, 1e-6, "zero pct = zero")
	c.near(HHFormulas.hit(100.0, 1.5).value, 150.0, 1e-6, "hit = base * power")
	c.near(HHFormulas.stagger_ticks(0.5).value, roundf(HHTune.value("stagger_max_ticks") * 0.5), 1e-6, "stagger scales")
	c.eq(HHFormulas.ELEMENTS.size(), 7, "seven elements (H2)")
	for el in HHFormulas.ELEMENTS:
		if el != "ice":
			c.eq(HHFormulas.OPPOSITE[HHFormulas.OPPOSITE[el]], el, "opposite is symmetric: %s" % el)


func test_phases(c: HHSelfTest.HHCheck) -> void:
	var script := { "rules": { "speed": 1.0 }, "phases": [
		{ "id": "aggravated", "trigger": { "hp_below": 0.75 }, "rules": { "speed": 1.2 } },
		{ "id": "enrage", "trigger": { "hp_below": 0.25, "after": "aggravated", "delay_ticks": 10 }, "rules": { "speed": 1.5 } },
	] }
	var st := HHPhases.start(script)
	c.eq(HHPhases.check(st, 1.0, 0).size(), 0, "nothing at full hp")
	c.near(float(HHPhases.rule(st, "speed")), 1.0, 1e-6, "base rule")
	c.eq(HHPhases.check(st, 0.7, 5), ["aggravated"], "first phase fires")
	c.near(float(HHPhases.rule(st, "speed")), 1.2, 1e-6, "phase rules merge")
	c.eq(HHPhases.check(st, 0.2, 6).size(), 0, "enrage is pending")
	c.eq(HHPhases.countdown(st, "enrage", 6), 10, "countdown")
	c.eq(HHPhases.check(st, 0.2, 16), ["enrage"], "fires after the delay")
	c.ok(HHPhases.fired(st, "enrage"), "fired")
	c.eq(HHPhases.check(st, 0.1, 30).size(), 0, "fires once")


func test_tune(c: HHSelfTest.HHCheck) -> void:
	HHTune.reset()
	var w := HHTune.value("walk_ticks")
	HHTune.set_value("walk_ticks", w + 5.0)
	c.near(HHTune.value("walk_ticks"), w + 5.0, 1e-6, "override reads back")
	HHTune.reset()
	c.near(HHTune.value("walk_ticks"), w, 1e-6, "reset restores the default")
	c.eq(HHTune.list("water_slow").size(), 4, "lists read")


func test_tile_fx_layers(c: HHSelfTest.HHCheck) -> void:
	var L := HHTileFX.layers({})
	c.eq(L.mark, "", "empty entry: nothing")
	L = HHTileFX.layers({ "h": 2, "v": -1, "marker": "", "glaze": 0 })
	c.eq(L.h.el, "fire", "h>0 is fire")
	c.eq(int(L.h.tier), 2, "tier")
	c.eq(L.v.el, "dark", "v<0 is dark")
	L = HHTileFX.layers({ "h": -1, "v": 0, "marker": "", "glaze": 10 })
	c.eq(L.mark, "glaze", "glaze mark")
	c.ok(L.crack, "almost gone: cracked")
	L = HHTileFX.layers({ "h": 0, "v": 0, "marker": "fuse", "glaze": 0 })
	c.eq(L.mark, "fuse", "marker wins")
	c.ok(L.h.is_empty(), "no face under a marker")
	c.ok(HHTileFX.hex_mesh().get_surface_count() == 1, "hex mesh builds")


func test_kit_mesh(c: HHSelfTest.HHCheck) -> void:
	var g := GKMesh.new()
	g.box("grass", Vector3.ZERO, Vector3.ONE)
	c.eq(g.triangle_count(), 12, "a box is 12 triangles")
	g.sphere("stone_grey", Vector3.ZERO, 1.0, 8)
	var m := g.commit()
	c.eq(m.get_surface_count(), 2, "one surface per role")
	c.eq(m.surface_get_name(0), "grass", "surfaces sorted by role")
	c.ok(GKMaterials.has("grass") and GKMaterials.has("stone_grey") and GKMaterials.has("hedge"), "floor roles exist")
	var a := HHArena.round_flat(1, 6.0, 0.3)
	c.ok(not a.hf.is_empty(), "arena carries a heightfield")
