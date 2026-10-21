extends RefCounted
## Lane EL (spec 2.3): Geyser, water's tier-3 reaction. Fresh water on water 3
## erupts: burst = Overheat's (geyser_aa_mult, parity by default), a massive
## stagger on the monster, water 1 splashed onto the ring, the centre vents to
## 2. Contained as Overheat: the splash never reacts.


func _grid() -> HHCharge:
	return HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))


func test_geyser_rule(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	g.apply([h], "water", "p", 3)
	var r := g.apply([h], "water", "p", 1)
	c.eq(r.bursts.size(), 1, "fresh water on water 3 erupts")
	c.eq(str(r.bursts[0].kind), "geyser", "a Geyser")
	c.near(float(r.bursts[0].mult), HHTune.value("overheat_aa_mult"), 1e-6, "burst = Overheat's (parity)")
	c.eq(g.intensity(h, "water"), 2, "the centre vents to 2")
	for n in HHHex.neighbors(h):
		c.eq(g.intensity(n, "water"), 1, "water 1 splashed at %s" % n)
	r = g.apply([h], "water", "p", 1)
	c.ok(r.bursts.is_empty(), "water 2 -> 3: no burst until the next cast")
	r = g.apply([h], "water", "p", 1)
	c.eq(r.bursts.size(), 1, "the next cast on 3 erupts again")
	r = g.apply([Vector2i(4, 0)], "water", "p", 3)
	c.ok(r.bursts.is_empty(), "laying water 3 on bare ground is not a burst")


func test_geyser_splash_is_contained(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	var ring := HHHex.neighbors(h)
	g.apply([h], "water", "p", 3)
	g.apply([ring[0]], "water", "p", 3)
	g.apply([ring[1]], "fire", "p", 2)
	var r := g.apply([h], "water", "p", 1)
	c.eq(r.bursts.size(), 1, "one burst only: the splash on a water-3 neighbour does not erupt it")
	c.ok(r.eruptions.is_empty(), "the splash on fire 2 does not Steam")
	c.eq(g.intensity(ring[0], "water"), 3, "water 3 neighbour stays capped")
	c.eq(g.intensity(ring[1], "fire"), 1, "fire 2 neighbour nets to fire 1")


func test_geyser_damage_and_stagger(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 6), "water", "fire", "lance")
	var m := s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	var hx := Vector2i(1, -2)
	s.paint([hx], "water", "p1", 3)
	s.step()
	var mhp := float(m.hp)
	var r := s.paint([hx], "water", "p1", 1)
	c.eq(r.bursts.size(), 1, "erupted")
	var staggered := 0
	var want := s.reaction_unit("p1") * HHTune.value("geyser_aa_mult")
	c.near(mhp - float(m.hp), want, 1.0, "Geyser: the caster's auto attack x geyser_aa_mult on the monster")
	staggered = int(m.stagger)
	var st := int(float(HHFormulas.stagger_ticks(HHTune.value("geyser_stagger")).value) * HHTune.value("monster_stagger_mult"))
	c.eq(staggered, st, "a massive stagger on the monster")
	# under the caster: nothing
	s.step()
	s.paint([p.hex], "water", "p1", 3)
	s.step()
	var php := float(p.hp)
	s.paint([p.hex], "water", "p1", 1)
	c.near(float(p.hp), php, 0.01, "the caster's own Geyser never hurts it")
