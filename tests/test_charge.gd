extends RefCounted
## HHCharge: the element reactions, as rules.


func _grid() -> HHCharge:
	return HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))


func test_axis_and_decay(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	g.apply([h], "fire", "p", 2)
	c.eq(g.intensity(h, "fire"), 2, "fire 2 laid")
	g.apply([h], "fire", "p", 3)
	c.eq(g.intensity(h, "fire"), 3, "fire caps at 3")
	g.apply([h], "light", "p", 1)
	c.eq(g.intensity(h, "light"), 1, "light sits beside fire")
	var step := int(HHTune.value("charge_step_ticks"))
	for i in step:
		g.tick()
	c.eq(g.intensity(h, "fire"), 2, "one decay step after step_ticks")
	c.eq(g.intensity(h, "light"), 1, "lesser axis waits")
	for i in step * 6:
		g.tick()
	c.ok(g.at(h).is_empty(), "charge decays away")


func test_douse(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(1, 0)
	g.apply([h], "fire", "p", 3)
	var r := g.apply([h], "water", "p", 1)
	c.ok(h in r.doused, "fire met water: doused")
	c.ok(g.at(h).is_empty(), "nothing lingers")
	g.apply([h], "water", "p", 2)
	g.apply([h], "dark", "p", 1)
	r = g.apply([h], "fire", "p", 1)
	c.ok(h in r.doused, "water met fire: doused")
	c.eq(g.intensity(h, "dark"), 1, "dark stays after a douse")
	c.eq(g.intensity(h, "water"), 0, "water gone")


func test_fuse(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 1)
	var r := g.apply([h], "thunder", "p")
	c.eq(g.marker(h), "fuse", "thunder on empty ground arms a fuse")
	c.ok(r.detonations.is_empty(), "no blast on empty ground")
	r = g.apply([h], "fire", "p", 2)
	c.eq(r.detonations.size(), 1, "fire on a fuse detonates")
	c.near(float(r.detonations[0].pct), 5.0 + 4.0 * 2, 1e-6, "5 + 4/point")
	c.ok(g.at(h).is_empty(), "blown hex is bare")
	g.apply([h], "water", "p", 2)
	g.apply([h], "light", "p", 1)
	r = g.apply([h], "thunder", "p")
	c.eq(r.detonations.size(), 1, "thunder on charge detonates")
	c.near(float(r.detonations[0].pct), 5.0 + 4.0 * 3 + 2.0 * 2, 1e-6, "+2 per water point")
	var mix: Dictionary = r.detonations[0].mix
	c.eq(int(mix.get("water", 0)), 2, "mix carries water")
	c.eq(int(mix.get("light", 0)), 1, "mix carries light")


func test_glaze_and_shatter(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(2, 2)
	g.apply([h], "ice", "p")
	c.eq(g.marker(h), "stasis", "ice on empty ground arms stasis")
	g.apply([h], "water", "p", 2)
	c.ok(g.is_glazed(h), "water on a stasis marker arrives glazed")
	c.eq(g.intensity(h, "water"), 2, "the water is under the glaze")
	c.near(g.move_mult(h), 1.0, 1e-6, "glazed water walks at full speed")
	var before: int = g.at(h).timer
	for i in 10:
		g.tick()
	c.eq(int(g.at(h).timer), int(before), "decay paused under glaze")
	var r := g.apply([h], "light", "p")
	c.eq(g.intensity(h, "light"), 0, "light washes off a glaze")
	r = g.apply([h], "thunder", "p")
	c.eq(r.detonations.size(), 1, "thunder shatters a glazed hex")
	c.near(float(r.detonations[0].pct), (5.0 + 4.0 * 2 + 2.0 * 2) * 1.5, 1e-6, "x1.5 shatter")
	g.apply([h], "water", "p", 1)
	g.apply([h], "ice", "p")
	c.ok(g.is_glazed(h), "ice on charge glazes")
	g.apply([h], "fire", "p", 1)
	c.ok(not g.is_glazed(h), "fire melts the glaze")
	c.eq(g.intensity(h, "water"), 1, "and is spent (water stays)")


func test_gale(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	g.apply([h], "wind", "p")
	c.eq(g.marker(h), "gale", "wind on empty ground arms a gale")
	var r := g.apply([h], "dark", "p", 2)
	c.eq(r.gales.size(), 1, "dark on a gale marker fires it")
	c.eq((r.gales[0].copies as Array).size(), 6, "six copies")
	for n in HHHex.neighbors(h):
		c.eq(g.intensity(n, "dark"), 2, "copy carries dark 2 at %s" % n)
	c.eq(g.intensity(h, "dark"), 2, "origin keeps its charge")
	var gale_ticks := int(HHTune.value("charge_gale_ticks"))
	for i in gale_ticks:
		g.tick()
	c.eq(g.intensity(HHHex.neighbors(h)[0], "dark"), 1, "copies fade a step after gale_ticks")
	# wind on existing charge copies it too
	var k := Vector2i(3, 0)
	g.apply([k], "fire", "p", 1)
	r = g.apply([k], "wind", "p")
	c.eq(r.gales.size(), 1, "wind on charge gales")


func test_overheat(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	g.apply([h], "fire", "p", 3)
	var r := g.apply([h], "fire", "p", 1)
	c.eq(r.overheat.size(), 1, "fresh fire on fire 3 erupts")
	c.eq((r.overheat[0].ring as Array).size(), 6, "the whole ring")
	for n in HHHex.neighbors(h):
		c.eq(g.intensity(n, "fire"), 2, "ring gets +2 fire at %s" % n)
	c.eq(g.intensity(h, "fire"), 2, "centre vents to 2")
	r = g.apply([h], "fire", "p", 1)
	c.ok(r.overheat.is_empty(), "fire 3 again, no eruption until recast")
	r = g.apply([h], "fire", "p", 1)
	c.eq(r.overheat.size(), 1, "recast on 3 erupts again")
	# propagated ring never erupts
	var n0 := HHHex.neighbors(h)[0]
	c.ok(g.intensity(n0, "fire") <= 3, "ring capped")


func test_overfreeze(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(1, 1)
	g.apply([h], "water", "p", 2)
	g.apply([h], "ice", "p")
	c.ok(g.is_glazed(h), "glazed water")
	var r := g.apply([h], "ice", "p")
	c.eq(r.overfreeze.size(), 1, "fresh ice on glazed water overfreezes")
	c.near(float(r.overfreeze[0].pct), 12.0, 1e-6, "12% burst")
	c.eq((r.overfreeze[0].ring as Array).size(), 6, "ring glazes")
	for n in HHHex.neighbors(h):
		c.ok(g.is_glazed(n), "sheet at %s" % n)
		c.eq(g.intensity(n, "water"), 1, "thin water sheet at %s" % n)
	r = g.apply([HHHex.neighbors(h)[0]], "ice", "p")
	c.eq(r.overfreeze.size(), 1, "a sheet is glazed water: it can overfreeze too (fresh ice)")


func test_authored_permanent(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(-2, 0)
	g.author(h, -3, 0)
	for i in 1000:
		g.tick()
	c.eq(g.intensity(h, "water"), 3, "authored water never decays")
	g.apply([h], "ice", "p")
	c.ok(g.is_glazed(h), "it can still be glazed")
	c.ok(not bool(g.at(h).permanent), "and is ordinary charge from then on")


func test_propagated_rules(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 2)
	g.apply([h], "thunder", "p")
	var r := g.apply([h], "fire", "p", 1, false)
	c.ok(r.detonations.is_empty(), "spread never fires a marker")
	c.eq(g.marker(h), "fuse", "fuse still armed")
	var k := Vector2i(2, 0)
	g.apply([k], "water", "p", 1)
	g.apply([k], "ice", "p")
	r = g.apply([k], "fire", "p", 1, false)
	c.ok(g.is_glazed(k), "spread skips glazed hexes")
