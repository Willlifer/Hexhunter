extends RefCounted
## Lane EL (spec 2.5, H263 DECIDE-D): light's and dark's tier-3 reactions as a
## pair in the H50 burst model. Fresh light on light 3 = Glint, fresh dark on
## dark 3 = Flux: both burst x glint_aa_mult / flux_aa_mult (Overheat's 3x by
## default), splash their element 1 onto the ring and vent the centre to 2.
## Glint dazzles (a stagger); Flux makes the monster vulnerable (reaction
## damage it takes x flux_vuln_mult for flux_vuln_ticks; not its own blast).


func _sim() -> HHSim:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	s.add_player("p1", Vector2i(0, 6), "light", "dark", "lance")
	s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	return s


func test_pair_rule(c: HHSelfTest.HHCheck) -> void:
	var g := HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))
	var a := Vector2i(0, 0)
	var b := Vector2i(5, 0)
	g.apply([a], "light", "p", 3)
	g.apply([b], "dark", "p", 3)
	var r := g.apply([a], "light", "p", 1)
	c.eq(r.bursts.size(), 1, "light on light 3 bursts")
	c.eq(str(r.bursts[0].kind), "glint", "Glint")
	c.eq(g.intensity(a, "light"), 2, "vents to 2")
	r = g.apply([b], "dark", "p", 1)
	c.eq(str(r.bursts[0].kind), "flux", "dark on dark 3: Flux")
	c.eq(g.intensity(b, "dark"), 2, "vents to 2")
	c.near(HHFormulas.burst_mult("glint").value, HHFormulas.burst_mult("flux").value, 1e-6, "a pair: the same multiple")
	for n in HHHex.neighbors(b):
		if g.can_hold(n):
			c.eq(g.intensity(n, "dark"), 1, "dark 1 splashed at %s" % n)


func test_glint_dazzles_flux_exposes(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var hx := Vector2i(0, -2)
	s.paint([hx], "light", "p1", 3)
	s.step()
	var mhp := float(m.hp)
	s.paint([hx], "light", "p1", 1)
	var unit := s.reaction_unit("p1")
	c.near(mhp - float(m.hp), unit * HHTune.value("glint_aa_mult"), 1.0, "Glint: x glint_aa_mult")
	c.ok(int(m.stagger) > 0, "Glint dazzles (stagger)")
	m.stagger = 0
	var hy := Vector2i(1, -1)
	s.step()
	s.paint([hy], "dark", "p1", 3)
	s.step()
	mhp = float(m.hp)
	s.paint([hy], "dark", "p1", 1)
	c.near(mhp - float(m.hp), unit * HHTune.value("flux_aa_mult"), 1.0, "Flux's own blast is not boosted by the vulnerability it sets")
	c.ok((m.statuses as Dictionary).has("vulnerable"), "the monster is vulnerable")
	s.step()
	var hz := Vector2i(0, -4)                       # in the hull, clear of the Glint's and the Flux's splash
	s.paint([hz], "fire", "p1", 2)
	s.step()
	mhp = float(m.hp)
	s.paint([hz], "thunder", "p1")
	var det := unit * HHTune.value("det_aa_mult_per_point") * 2.0
	c.near(mhp - float(m.hp), det * HHTune.value("flux_vuln_mult"), 1.0, "the next reaction lands x flux_vuln_mult")
	for i in int(HHTune.value("flux_vuln_ticks")) + 31:
		s.step()
	c.ok(not (m.statuses as Dictionary).has("vulnerable"), "and it wears off")


func test_contained(c: HHSelfTest.HHCheck) -> void:
	var g := HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))
	var a := Vector2i(0, 0)
	var ring := HHHex.neighbors(a)
	g.apply([a], "light", "p", 3)
	g.apply([ring[0]], "light", "p", 3)
	g.apply([ring[1]], "dark", "p", 2)
	var r := g.apply([a], "light", "p", 1)
	c.eq(r.bursts.size(), 1, "the splash on a light-3 neighbour does not Glint it")
	c.ok(r.eruptions.is_empty(), "the splash on dark 2 does not Eclipse it")
	c.eq(g.intensity(ring[1], "dark"), 1, "it nets")
