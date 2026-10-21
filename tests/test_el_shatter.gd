extends RefCounted
## Lane EL (spec 2.2, H261 DECIDE-B, H264 DECIDE-E): Ice crystallises a charged
## tile into an Elemental Crystal; it shatters on a monster crushing it, a
## hunter's weapon hit, or overcharge. Shatter = shatter_mult_per_point x
## stored charge + shatter_mult_per_ice x ice, heavy stagger, fragments splash
## tier 1 of the stored element onto the ring (contained). Crystals wall
## hunters (the pathfinder routes round them) and never form on a hunter: it
## is pushed to the nearest open hex.


func _grid() -> HHCharge:
	return HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))


func test_glaze_kept_crystal_forms(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var e := Vector2i(4, 0)
	g.apply([e], "ice", "p")
	c.eq(g.marker(e), "stasis", "ice on EMPTY ground keeps its tier-1 behaviour (the stasis glaze)")
	var r := g.apply([e], "fire", "p", 2)
	c.eq(g.crystal(e), 1, "an element landing on armed ice crystallises: ice 1")
	c.eq(g.intensity(e, "fire"), 2, "carrying fire 2")
	var h := Vector2i(0, 0)
	g.apply([h], "fire", "p", 2)
	r = g.apply([h], "ice", "p", 1)
	c.ok(h in r.crystals, "ice on a charged tile forms a crystal")
	c.eq(g.crystal(h), 1, "ice 1")
	c.eq(g.intensity(h, "fire"), 2, "a fire 2 crystal")
	var before := int(g.at(h).timer)
	for i in 20:
		g.tick()
	c.eq(int(g.at(h).timer), before, "decay paused inside the crystal")
	for i in int(HHTune.value("crystal_ticks")):
		g.tick()
	c.eq(g.crystal(h), 0, "it thaws after crystal_ticks")
	c.eq(g.intensity(h, "fire"), 2, "back to plain fire 2")


func test_feed_and_overcharge(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	g.apply([h], "fire", "p", 2)
	g.apply([h], "ice", "p", 1)
	var r := g.apply([h], "fire", "p", 1)
	c.ok(r.shatters.is_empty(), "its own axis feeds it")
	c.eq(g.intensity(h, "fire"), 3, "fire 3 crystal")
	r = g.apply([h], "ice", "p", 2)
	c.eq(g.crystal(h), 3, "ice feeds it to 3")
	r = g.apply([h], "fire", "p", 1)
	c.eq(r.shatters.size(), 1, "charge past the cap shatters it (DECIDE-E)")
	var want := HHTune.value("shatter_mult_per_point") * 3.0 + HHTune.value("shatter_mult_per_ice") * 3.0
	c.near(float(r.shatters[0].mult), want, 1e-6, "mult = per_point x 3 + per_ice x 3")
	c.ok(g.crystal(h) == 0 and g.intensity(h, "fire") == 0, "the hex is cleared")
	for n in HHHex.neighbors(h):
		c.eq(g.intensity(n, "fire"), 1, "fragments splash fire 1 at %s" % n)
	var k := Vector2i(-4, 0)
	g.apply([k], "water", "p", 1)
	g.apply([k], "ice", "p", 3)
	r = g.apply([k], "ice", "p", 1)
	c.eq(r.shatters.size(), 1, "ice past ice 3 shatters it too")
	var j := Vector2i(4, 4)
	g.apply([j], "light", "p", 2)
	g.apply([j], "ice", "p", 1)
	r = g.apply([j], "wind", "p")
	c.ok(r.shatters.is_empty() and g.crystal(j) == 1, "wind does nothing to a crystal")
	r = g.apply([j], "fire", "p", 1)
	c.eq(r.shatters.size(), 1, "a foreign element breaks it")


func test_fragments_are_contained(c: HHSelfTest.HHCheck) -> void:
	var g := _grid()
	var h := Vector2i(0, 0)
	var ring := HHHex.neighbors(h)
	g.apply([ring[0]], "fire", "p", 1)
	g.apply([ring[0]], "ice", "p", 1)            # a neighbouring crystal
	g.apply([ring[1]], "fire", "p", 3)            # fire 3 next door
	g.apply([ring[2]], "water", "p", 2)           # water 2 next door
	g.apply([h], "fire", "p", 3)
	g.apply([h], "ice", "p", 1)
	var r := g.apply([h], "thunder", "p")
	c.eq(r.shatters.size(), 1, "thunder on a crystal shatters it, once")
	c.ok(r.detonations.is_empty(), "a crystal shatters, it does not also detonate")
	c.eq(g.crystal(ring[0]), 1, "the neighbouring crystal survives the splash")
	c.ok(r.bursts.is_empty(), "the splash on fire 3 does not Overheat it")
	c.ok(r.eruptions.is_empty(), "the splash on water 2 does not Steam it")
	c.eq(g.intensity(ring[2], "water"), 1, "it nets")


func _duel() -> HHSim:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	s.add_player("p1", Vector2i(0, 2), "ice", "fire", "lance")
	s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	return s


func test_weapon_hit_shatters_player_triggered(c: HHSelfTest.HHCheck) -> void:
	var s := _duel()
	var m := s.unit("m")
	var p := s.unit("p1")
	var hx := s.nearest_hex_of(m, p.hex)
	s.paint([hx], "fire", "p1", 3)
	s.step()
	s.paint([hx], "ice", "p1", 1)
	c.ok(s.crystal_at(hx), "a crystal under the monster's edge")
	s.step()
	var mhp := float(m.hp)
	var php := float(p.hp)
	var blow := s.strike(p, m, 100.0, hx, "basic")
	var mult := HHTune.value("shatter_mult_per_point") * 3.0 + HHTune.value("shatter_mult_per_ice") * 1.0
	c.near(mhp - float(m.hp), blow + s.reaction_unit("p1") * mult, 1.5, "the blow + Shatter at the hunter's full rate")
	c.ok(not s.crystal_at(hx), "shattered")
	c.ok(int(m.stagger) > 0, "heavy stagger")
	c.near(float(p.hp), php, 0.01, "the hunter is never hurt by its own Shatter")


func test_crush_is_monster_triggered(c: HHSelfTest.HHCheck) -> void:
	var s := _duel()
	var m := s.unit("m")
	var p := s.unit("p1")
	var ahead := Vector2i(0, 1)                  # the hex the hull's leading edge reaches when the monster steps to (0, -1)
	s.paint([ahead], "fire", "p1", 2)
	s.step()
	s.paint([ahead], "ice", "p1", 1)
	c.ok(s.crystal_at(ahead), "a crystal in the monster's way")
	p.hp = 10.0
	var mhp := float(m.hp)
	s.monster_move(m, Vector2i(0, -1))
	var crushed := false
	var hp_after := -1.0
	for i in 40:
		for e in s.step():
			if e.type == "shatter":
				crushed = true
				hp_after = float(p.hp)
	c.ok(crushed, "the monster walking onto it crushes it")
	var mult := HHTune.value("shatter_mult_per_point") * 2.0 + HHTune.value("shatter_mult_per_ice") * 1.0
	var want := s.reaction_unit("p1") * mult * HHTune.value("monster_reaction_frac")
	c.near(mhp - float(m.hp), want, 1.5, "monster-triggered: the monster takes monster_reaction_frac of the player-cast damage")
	c.ok(hp_after >= 1.0 and hp_after < 10.0, "a hunter caught in it is hurt but never killed (DECIDE-C): %.1f HP" % hp_after)


func test_crystal_walls_hunters_and_pushes(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 4), "ice", "fire", "lance")
	var wall: Array = []
	for q in range(-3, 4):
		wall.append(Vector2i(q, 2))
	s.paint(wall, "fire", "p1", 1)
	s.step()
	s.paint(wall, "ice", "p1", 1)
	for h in wall:
		c.ok(s.crystal_at(h), "crystal at %s" % h)
	var b := s.blocked_for(p)
	c.ok(wall.all(func(h): return b.has(h)), "crystals are walls for a hunter")
	var path := s.arena.path(p.hex, Vector2i(0, 0), b)
	c.ok(not path.is_empty(), "there is a way round")
	c.ok(path.all(func(h): return not s.crystal_at(h)), "and the path never enters a crystal")
	s.step({ "p1": { "move": Vector2i(0, 0), "move_pos": s.arena.stand(Vector2i(0, 0)) } })
	var entered := false
	for i in 150:
		s.step()
		if s.crystal_at(p.hex):
			entered = true
	c.ok(not entered, "walking never steps into a crystal")
	c.eq(p.hex, Vector2i(0, 0), "arrived round the wall")
	# a crystal forming under a hunter: formed, and the hunter pushed off
	s.paint([p.hex], "water", "p1", 1)
	s.step()
	var under: Vector2i = p.hex
	s.paint([under], "ice", "p1", 1)
	var pushed := {}
	for e in s.step():
		if e.type == "push_out" and str(e.get("by", "")) == "crystal":
			pushed = e
	c.ok(s.crystal_at(under), "the crystal formed")
	c.ok(not pushed.is_empty(), "the hunter was pushed (push_out by crystal)")
	c.ok(p.hex != under and not s.crystal_at(p.hex) and s.arena.walkable(p.hex), "onto an open hex")
	c.eq(HHHex.distance(p.hex, under), 1, "the nearest one")


func test_first_crystal_on_a_line(c: HHSelfTest.HHCheck) -> void:
	var s := _duel()
	var line: Array = [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]
	s.paint([line[2]], "dark", "p1", 1)
	s.step()
	s.paint([line[2]], "ice", "p1", 1)
	c.eq(s.first_crystal(line), 2, "a sweep beam stops at index 2")
	c.eq(s.first_crystal([Vector2i(0, 5)]), -1, "none")
