extends RefCounted
## Lane EL (spec 3.2): Eclipse, light meeting dark (a tier-2+ tile, its own
## eclipse_min_tier, meeting its opposite consumes all light and dark on the
## hex; eclipse_aa_mult_per_point x consumed; Steam has its own curve since H420),
## and its own effect: the monster is `exposed` (H57's punish window, x
## exposed_dmg_mult from EVERY hunter) for eclipse_exposed_ticks, 5 s (H425,
## the author: "Extend vulnerable to 5s ... in a team of 4 you would want your
## eclipse to ignite before laying out big combos"). A tier-1 contact only
## nets. Contained.


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
	c.near(float(r.eruptions[0].mult), HHTune.value("eclipse_aa_mult_per_point") * 3.0, 1e-6, "same scaling as Steam")
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
	var want := s.reaction_unit("p1") * HHTune.value("eclipse_aa_mult_per_point") * 4.0
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


## H425: the Eclipse window is a party setup. Every hunter's blows and
## reactions land x exposed_dmg_mult on the exposed monster, not only the
## Eclipse caster's, for the whole 5 s.
func test_eclipse_amplifies_the_whole_party(c: HHSelfTest.HHCheck) -> void:
	c.eq(int(HHTune.value("eclipse_exposed_ticks")), 150, "5 s (H425)")
	var s := _sim()
	s.add_player("p2", Vector2i(2, 6), "fire", "water", "bow")
	var m := s.unit("m")
	var p2 := s.unit("p2")
	var k := HHTune.value("exposed_dmg_mult")
	# before: p2's blow and p2's Steam, unexposed
	var hp0 := float(m.hp)
	var plain := s.strike(p2, m, 100.0, m.hex, "basic")
	c.near(hp0 - float(m.hp), plain, 0.01, "an unexposed blow")
	var hx := Vector2i(0, -1)
	s.paint([hx], "dark", "p1", 2)
	s.step()
	s.paint([hx], "light", "p1", 2)
	c.ok(int(m.exposed) > 0, "p1's Eclipse exposed it")
	for i in 120:
		s.step()
	c.ok(int(m.exposed) > 0, "still exposed 4 s later")
	var hp1 := float(m.hp)
	s.strike(p2, m, 100.0, m.hex, "basic")
	c.near(hp1 - float(m.hp), plain * k, 1.0, "p2's blow: x exposed_dmg_mult")
	var sx := Vector2i(1, -2)
	s.paint([sx], "water", "p2", 1)
	s.step()
	var hp2 := float(m.hp)
	s.paint([sx], "fire", "p2", 1)
	c.near(hp2 - float(m.hp), s.reaction_unit("p2") * float(HHFormulas.steam_mult(2).value) * k, 1.0, "p2's Steam: x exposed_dmg_mult")
	for i in 40:
		s.step()
	c.eq(int(m.exposed), 0, "the window closes after 5 s")
