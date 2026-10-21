extends RefCounted
## Lane EL (spec 3.2): Eclipse, light meeting dark. Same scaling model as Steam
## (a tier-2+ tile meeting its opposite consumes all light and dark on the
## hex; eclipse_mult_per_point x consumed), and its own effect: the monster is
## `exposed` (H57's punish window, x exposed_dmg_mult from hunters) for
## eclipse_exposed_ticks. A tier-1 contact only nets. Contained.


func _sim() -> HHSim:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	s.add_player("p1", Vector2i(0, 6), "light", "dark", "lance")
	s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	return s


func test_eclipse_rule(c: HHSelfTest.HHCheck) -> void:
	var g := HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))
	var h := Vector2i(0, 0)
	g.apply([h], "light", "p", 1)
	var r := g.apply([h], "dark", "p", 2)
	c.ok(r.eruptions.is_empty(), "light 1 + dark: only nets (tier-1 contact)")
	c.eq(g.intensity(h, "dark"), 1, "dark 2 - 1")
	g.apply([h], "fire", "p", 2)
	g.apply([h], "dark", "p", 1)
	r = g.apply([h], "light", "p", 1)
	c.eq(r.eruptions.size(), 1, "dark 2 + light: Eclipse")
	c.eq(str(r.eruptions[0].kind), "eclipse", "kind")
	c.eq(int(r.eruptions[0].consumed), 3, "consumed 2 + 1")
	c.near(float(r.eruptions[0].mult), HHTune.value("eclipse_mult_per_point") * 3.0, 1e-6, "same scaling as Steam")
	c.eq(g.intensity(h, "dark") + g.intensity(h, "light"), 0, "all light and dark consumed")
	c.eq(g.intensity(h, "fire"), 2, "fire stays")


func test_eclipse_exposes_the_monster(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var hx := Vector2i(0, -1)
	s.paint([hx], "dark", "p1", 2)
	s.step()
	var mhp := float(m.hp)
	s.paint([hx], "light", "p1", 2)
	var want := s.reaction_unit("p1") * HHTune.value("eclipse_mult_per_point") * 4.0
	c.near(mhp - float(m.hp), want, 1.0, "the monster takes consumed x the auto attack")
	c.eq(int(m.exposed), int(HHTune.value("eclipse_exposed_ticks")), "and is exposed")
	var p := s.unit("p1")
	var hp := float(p.hp)
	s.paint([p.hex], "dark", "p1", 3)
	s.step()
	s.paint([p.hex], "light", "p1", 1)
	c.near(float(p.hp), hp, 0.01, "never the caster")


func test_eclipse_contained(c: HHSelfTest.HHCheck) -> void:
	var g := HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))
	var a := Vector2i(1, 1)
	g.begin_action("x")
	g.apply([a], "dark", "p", 3)
	var r := g.apply([a], "light", "p", 3)
	c.eq(r.eruptions.size(), 1, "erupts once")
	for n in HHHex.neighbors(a):
		c.ok(g.at(n).is_empty(), "nothing spills onto the ring at %s" % n)
	g.apply([a], "dark", "p", 3)
	r = g.apply([a], "light", "p", 3)
	c.ok(r.eruptions.is_empty() and r.bursts.is_empty(), "the same hex does not react again in this action")
