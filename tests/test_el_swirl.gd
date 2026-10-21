extends RefCounted
## Lane EL (spec 2.1): Wind's Swirl. Wind on empty ground still arms a gale
## marker. Wind landing on charged ground pulls every plain charge within the
## pull radius (2 for a small or line cast, 3 for a wide area) of the cast's
## centre inward: sums per element, capped at 3, laid on the centre (or the
## nearest free hex of its ring); pulled hexes clear. A condensed tier 3 fires
## that element's tier-3 burst once, immediately, without its ring splash.
## With no reaction the condensed charge spreads tier 1 one ring outward.
## Contained: no pulling from a hex a reaction produced or used this action,
## a Swirl centre is not swirled again in the same action, crystals stay put.


func _grid() -> HHCharge:
	return HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))


func test_wind_on_empty_arms_gale(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	var r := g.apply([h], "wind", "p")
	c.eq(g.marker(h), "gale", "wind on empty ground arms a gale")
	c.ok(r.swirl.is_empty(), "no Swirl on empty ground")
	r = g.apply([h], "dark", "p", 2)
	c.eq(r.gales.size(), 1, "an element on the gale marker spreads to the ring (kept)")


func test_swirl_condenses(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var centre := Vector2i(0, 0)
	g.apply([Vector2i(1, 0)], "fire", "p", 1)
	g.apply([Vector2i(-1, 0)], "light", "p", 1)
	g.apply([Vector2i(0, 2)], "fire", "p", 1)          # distance 2: pulled
	g.apply([Vector2i(3, 0)], "fire", "p", 2)          # distance 3: out of a small cast's reach
	var r := g.apply([centre, Vector2i(1, 0)], "wind", "p")
	c.ok(not r.swirl.is_empty(), "wind on charged ground Swirls")
	c.eq(int(r.swirl.radius), 2, "a small cast pulls radius 2")
	var land: Vector2i = r.swirl.landing
	c.eq(g.intensity(land, "fire"), 2, "fire 1 + fire 1 condensed")
	c.eq(g.intensity(land, "light"), 1, "light 1 condensed beside it")
	c.eq(land, centre, "laid on the centre")
	c.ok(g.at(Vector2i(0, 2)).is_empty(), "pulled hexes clear (past the spread ring)")
	c.eq(g.intensity(Vector2i(3, 0), "fire"), 2, "out of reach: untouched")
	c.ok(r.bursts.is_empty(), "below 3: no burst")
	var copies: Array = r.swirl.copies
	c.ok(not copies.is_empty(), "no reaction: the condensed charge spreads one ring outward")
	for n in copies:
		c.eq(HHHex.distance(n, land), 1, "a copy on the ring at %s" % n)


func test_swirl_tier3_fires_once_without_spreading(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var centre := Vector2i(0, 0)
	for h in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		g.apply([h], "fire", "p", 1)
	var r := g.apply([Vector2i(1, 0)], "wind", "p")       # the wind has to land on charge
	c.eq(r.bursts.size(), 1, "fire summed to 4, capped at 3: Overheat fires once")
	c.eq(str(r.bursts[0].kind), "overheat", "Overheat")
	c.ok(bool(r.bursts[0].get("swirl", false)), "marked as Swirl's")
	c.ok((r.bursts[0].painted as Array).is_empty(), "Swirl's reaction does not spread (no ring paint)")
	var land: Vector2i = r.swirl.landing
	c.eq(g.intensity(land, "fire"), 2, "vented to 2")
	for n in HHHex.neighbors(land):
		c.eq(g.intensity(n, "fire"), 0, "ring bare at %s" % n)


func test_swirl_wide_area_radius_3(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	g.apply([Vector2i(3, 0)], "water", "p", 1)
	var area := HHHex.area(Vector2i(0, 0), 2)
	var r := g.apply(area, "wind", "p")
	c.ok(r.swirl.is_empty(), "nothing charged under the cast: no Swirl, gale markers")
	var g2 := _grid()
	g2.apply([Vector2i(3, 0)], "water", "p", 1)
	g2.apply([Vector2i(1, 0)], "water", "p", 1)
	r = g2.apply(area, "wind", "p")
	c.eq(int(r.swirl.radius), 3, "a wide area pulls radius 3")
	c.ok(g2.at(Vector2i(3, 0)).is_empty(), "the water 3 hexes out was pulled")
	c.eq(g2.intensity(r.swirl.landing, "water"), 2, "condensed")


func test_swirl_meets_opposites(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	g.apply([Vector2i(1, 0)], "fire", "p", 2)
	g.apply([Vector2i(-1, 0)], "water", "p", 1)
	var r := g.apply([Vector2i(1, 0)], "wind", "p")
	c.eq(r.eruptions.size(), 1, "fire 2 meets water 1 in the vortex: Steam")
	c.eq(int(r.eruptions[0].consumed), 3, "consumed 3")
	c.ok(r.bursts.is_empty(), "one reaction at the centre, no more")


func test_swirl_containment(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	g.begin_action("a")
	var h := Vector2i(0, 0)
	g.apply([h], "fire", "p", 3)
	var r := g.apply([h], "fire", "p", 1)             # Overheat: the ring is reaction output this action
	c.eq(r.bursts.size(), 1, "Overheat")
	var ring := HHHex.neighbors(h)
	r = g.apply([ring[0]], "wind", "p")
	c.ok(r.swirl.is_empty() or (r.swirl.pulled as Array).is_empty(), "Swirl cannot pull what a reaction produced or used this action")
	c.eq(g.intensity(ring[3], "fire"), 2, "the ring stays where Overheat laid it")
	g.begin_action("b")
	r = g.apply([ring[0]], "wind", "p")
	c.ok(not (r.swirl.pulled as Array).is_empty(), "next action: it can")
	var centre: Vector2i = r.swirl.centre
	r = g.apply([centre], "wind", "p")
	c.ok(r.swirl.is_empty(), "a Swirl centre is not swirled again in the same action")
	# crystals stay put
	var g2 := _grid()
	g2.apply([Vector2i(1, 0)], "fire", "p", 2)
	g2.apply([Vector2i(1, 0)], "ice", "p", 1)
	g2.apply([Vector2i(-1, 0)], "dark", "p", 1)
	r = g2.apply([Vector2i(0, 0), Vector2i(-1, 0)], "wind", "p")
	c.eq(g2.crystal(Vector2i(1, 0)), 1, "a crystal is not pulled")
	c.eq(g2.intensity(Vector2i(1, 0), "fire"), 2, "nor emptied")


func test_swirl_damage_rule(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 6), "wind", "fire", "lance")
	var m := s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	for h in [Vector2i(0, -1), Vector2i(1, -2), Vector2i(-1, -2)]:
		s.paint([h], "fire", "p1", 1)
	s.step()
	var mhp := float(m.hp)
	var r := s.paint([Vector2i(0, -1)], "wind", "p1")
	c.eq(r.bursts.size(), 1, "condensed to fire 3 under the monster: Overheat")
	c.near(mhp - float(m.hp), s.reaction_unit("p1") * HHTune.value("overheat_aa_mult"), 1.0, "the monster takes it at the hunter's rate")
	c.near(float(p.hp), float(p.max_hp), 0.01, "the hunter is untouched")
