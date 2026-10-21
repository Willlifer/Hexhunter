extends RefCounted
## Steam: fire meeting water (spec 3.1; H420, the author: "1 water into 1 fire
## should be as strong as a 1 fire 1 thunder eruption. 3 water into 3 fire
## should be as strong as a 3 dark+3 fire thunder eruption. Damage should scale
## based on total water+fire."). EVERY fresh fire / water contact erupts, tier
## 1 included (supersedes DECIDE-A's evaporate / douse): all fire and water on
## the hex is consumed, damage = HHFormulas.steam_mult(T = consumed, 2..6) x
## the caster's auto attack (3.3). Steam has its own keys (H423): it never
## reads thunder's. Contained: once per hex per action, nothing it does reacts
## again; spread (fresh = false) still only nets.


func _grid() -> HHCharge:
	return HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))


func _sim() -> HHSim:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "water", "lance")
	s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	return s


func test_every_contact_erupts(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(1, 0)
	g.apply([h], "water", "p", 1)
	var r := g.apply([h], "fire", "p", 1)
	c.eq(r.eruptions.size(), 1, "water 1 + fire 1: Steam (H420, no more evaporate)")
	c.eq(int(r.eruptions[0].consumed), 2, "T = 2")
	c.ok(r.doused.is_empty(), "no douse puff")
	c.ok(g.at(h).is_empty(), "both consumed")
	var k := Vector2i(2, 0)
	g.apply([k], "fire", "p", 1)
	r = g.apply([k], "water", "p", 3)
	c.eq(r.eruptions.size(), 1, "fire 1 under a big water: Steam")
	c.eq(int(r.eruptions[0].consumed), 4, "T = 1 + 3")
	c.ok(g.at(k).is_empty(), "all the water arriving is consumed too")
	var j := Vector2i(-3, 0)
	g.apply([j], "water", "p", 3)
	r = g.apply([j], "fire", "p", 2, false)
	c.ok(r.eruptions.is_empty(), "spread (not a cast) never erupts")
	c.eq(g.intensity(j, "water"), 1, "it nets instead")


func test_steam_curve(c: HHSelfTest.HHCheck) -> void:
	var want := { 2: 2.5, 3: 6.375, 4: 10.25, 5: 14.125, 6: 18.0 }
	for t in want:
		c.near(float(HHFormulas.steam_mult(t).value), float(want[t]), 1e-6, "steam(T = %d)" % t)
	# the author's anchors, as a VALUE check against today's thunder (the code never reads det_mult_*)
	c.near(float(HHFormulas.steam_mult(2).value), float(HHFormulas.fuse_mult(1, 1, 0).value), 1e-6, "water 1 into fire 1 = thunder on fire 1")
	c.near(float(HHFormulas.steam_mult(6).value), float(HHFormulas.fuse_mult(6, 2, 0).value), 1e-6, "water 3 into fire 3 = thunder on dark 3 + fire 3")
	# its own keys: retuning thunder moves nothing here, retuning Steam moves only Steam
	HHTune.set_value("det_mult_per_point", 9.0)
	c.near(float(HHFormulas.steam_mult(4).value), 10.25, 1e-6, "a thunder retune leaves Steam alone")
	HHTune.set_value("det_mult_per_point", HHTune.default_of("det_mult_per_point"))
	HHTune.set_value("steam_mult_max", 26.0)
	c.near(float(HHFormulas.steam_mult(6).value), 26.0, 1e-6, "steam_mult_max is T = 6")
	c.near(float(HHFormulas.fuse_mult(6, 2, 0).value), 18.0, 1e-6, "... and does not move thunder")
	HHTune.set_value("steam_mult_max", HHTune.default_of("steam_mult_max"))
	var g := _grid()
	var h := Vector2i(0, 0)
	g.apply([h], "water", "p", 2)
	g.apply([h], "dark", "p", 1)
	var r := g.apply([h], "fire", "p", 1)
	c.eq(str(r.eruptions[0].kind), "steam", "kind")
	c.eq(int(r.eruptions[0].consumed), 3, "consumed: 2 water + 1 fire")
	c.near(float(r.eruptions[0].mult), 6.375, 1e-6, "mult = steam_mult(3)")
	c.eq(g.intensity(h, "water") + g.intensity(h, "fire"), 0, "all fire and water consumed")
	c.eq(g.intensity(h, "dark"), 1, "the other axis stays")


func test_steam_hurts_the_monster_not_the_caster(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var p := s.unit("p1")
	var hx := Vector2i(0, -2)
	s.paint([hx], "water", "p1", 1)
	var mhp := float(m.hp)
	s.paint([hx], "fire", "p1", 1)
	var want := s.reaction_unit("p1") * float(HHFormulas.steam_mult(2).value)
	c.near(mhp - float(m.hp), want, 1.0, "player-cast Steam on a tier-1 contact: the caster's auto attack x 2.5 on the monster")
	s.paint([p.hex], "water", "p1", 3)
	var php := float(p.hp)
	var r := s.paint([p.hex], "fire", "p1", 1)
	c.eq(r.eruptions.size(), 1, "Steam under the caster")
	c.near(float(p.hp), php, 0.01, "never hurts the caster (3.3)")


func test_steam_ring_mirrors_thunder(c: HHSelfTest.HHCheck) -> void:
	c.near(HHTune.value("steam_ring_frac"), HHTune.value("detonate_ring_frac"), 1e-6, "the ring takes the same share as a detonation's (today's value)")
	var s := _sim()
	var m := s.unit("m")
	var ring_hex := Vector2i(0, -5)                       # one step outside the radius-2 hull
	c.eq(HHHex.distance(ring_hex, m.hex), 3, "next to the hull, not under it")
	s.paint([ring_hex], "water", "p1", 3)
	var mhp := float(m.hp)
	s.paint([ring_hex], "fire", "p1", 3)
	var want := s.reaction_unit("p1") * 18.0 * HHTune.value("steam_ring_frac")
	c.near(mhp - float(m.hp), want, 1.0, "a hull on the ring takes steam_ring_frac of x18")


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
	var one := s.reaction_unit("p1") * float(HHFormulas.steam_mult(3).value)
	c.near(mhp - float(m.hp), one * (1.0 + 2.0 * HHTune.value("reaction_chain_frac")), 1.0,
		"each blast reaches the body once: strongest in full + 15% of each other one")
