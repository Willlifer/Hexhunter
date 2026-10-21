extends RefCounted
## Lane EL (spec 3.1, H260 DECIDE-A): fire meeting water. A tier-1 tile is
## evaporated (water 1 under fire) or doused (fire 1 under water): plain
## netting, no reaction. A tile at tier 2+ meeting its opposite erupts as
## Steam: all fire and water on the hex is consumed, damage = consumed x
## steam_mult_per_point x the caster's auto attack (3.3). Contained: once per
## hex per action, nothing it does reacts again.


func _grid() -> HHCharge:
	return HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))


func _sim() -> HHSim:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "water", "lance")
	s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	return s


func test_tier1_evaporates_and_douses(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(1, 0)
	g.apply([h], "water", "p", 1)
	var r := g.apply([h], "fire", "p", 2)
	c.ok(r.eruptions.is_empty(), "water 1 + fire 2: no eruption (DECIDE-A)")
	c.eq(g.intensity(h, "fire"), 1, "the fire evaporates the water and keeps the rest")
	c.ok(h in r.doused, "a douse puff for the view")
	var k := Vector2i(2, 0)
	g.apply([k], "fire", "p", 1)
	r = g.apply([k], "water", "p", 1)
	c.ok(r.eruptions.is_empty(), "fire 1 + water 1: no eruption")
	c.ok(g.at(k).is_empty(), "doused: both gone, nothing lingers")
	g.apply([k], "fire", "p", 1)
	r = g.apply([k], "water", "p", 3)
	c.ok(r.eruptions.is_empty(), "fire 1 under a big water is still only doused (the tile is tier 1)")
	c.eq(g.intensity(k, "water"), 2, "water 3 less the step that doused the fire")


func test_steam_threshold_and_formula(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	g.apply([h], "water", "p", 2)
	g.apply([h], "dark", "p", 1)
	var r := g.apply([h], "fire", "p", 1)
	c.eq(r.eruptions.size(), 1, "water 2 + fire: Steam")
	c.eq(str(r.eruptions[0].kind), "steam", "kind")
	c.eq(int(r.eruptions[0].consumed), 3, "consumed: 2 water + 1 fire")
	c.near(float(r.eruptions[0].mult), HHTune.value("steam_mult_per_point") * 3.0, 1e-6, "mult = steam_mult_per_point x consumed")
	c.eq(g.intensity(h, "water") + g.intensity(h, "fire"), 0, "all fire and water consumed")
	c.eq(g.intensity(h, "dark"), 1, "the other axis stays")
	var k := Vector2i(3, 0)
	g.apply([k], "fire", "p", 3)
	r = g.apply([k], "water", "p", 3)
	c.eq(int(r.eruptions[0].consumed), 6, "fire 3 + water 3 consumes 6")
	c.ok(g.at(k).is_empty(), "bare after")
	var j := Vector2i(-3, 0)
	g.apply([j], "water", "p", 3)
	r = g.apply([j], "fire", "p", 2, false)
	c.ok(r.eruptions.is_empty(), "spread (not a cast) never erupts")
	c.eq(g.intensity(j, "water"), 1, "it nets instead")


func test_steam_hurts_the_monster_not_the_caster(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var p := s.unit("p1")
	var hx := Vector2i(0, -2)
	s.paint([hx], "water", "p1", 2)
	var mhp := float(m.hp)
	s.paint([hx], "fire", "p1", 1)
	var want := s.reaction_unit("p1") * HHTune.value("steam_mult_per_point") * 3.0
	c.near(mhp - float(m.hp), want, 1.0, "player-cast Steam: the caster's auto attack x 3 on the monster")
	s.paint([p.hex], "water", "p1", 3)
	var php := float(p.hp)
	var r := s.paint([p.hex], "fire", "p1", 1)
	c.eq(r.eruptions.size(), 1, "Steam under the caster")
	c.near(float(p.hp), php, 0.01, "never hurts the caster (3.3)")


func test_steam_is_contained(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var a := Vector2i(0, 0)
	g.begin_action("t1:p")
	g.apply([a], "water", "p", 2)
	var r := g.apply([a], "fire", "p", 1)
	c.eq(r.eruptions.size(), 1, "first contact erupts")
	g.apply([a], "water", "p", 2)
	r = g.apply([a], "fire", "p", 1)
	c.ok(r.eruptions.is_empty(), "the same hex cannot erupt twice in one action")
	c.eq(g.intensity(a, "water"), 1, "it only nets")
	g.begin_action("t2:p")
	g.apply([a], "water", "p", 1)
	r = g.apply([a], "fire", "p", 1)
	c.eq(r.eruptions.size(), 1, "a new action erupts again")
	# one paint over a line of water-2 hexes: each hex erupts once, the monster takes one chain
	var s := _sim()
	var m := s.unit("m")
	var line: Array = [Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2)]
	s.step()
	s.paint(line, "water", "p1", 2)
	s.step()
	var mhp := float(m.hp)
	var rr := s.paint(line, "fire", "p1", 1)
	c.eq(rr.eruptions.size(), 3, "three hexes, three eruptions, no more")
	var one := s.reaction_unit("p1") * HHTune.value("steam_mult_per_point") * 3.0
	c.near(mhp - float(m.hp), one * (1.0 + 2.0 * HHTune.value("reaction_chain_frac")), 1.0,
		"each blast reaches the body once: strongest in full + 15% of each other one")
