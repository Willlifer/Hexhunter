extends RefCounted
## Lane IC (H470-H479): the author's playtest note on ice. "If you couldn't
## shatter it you could end up stuck in place." A hunter must never be held by
## crystals: they pass through them (H470). The monster still crushes them and
## a sweep beam still stops at them (cover), and the shatter read the
## view and HUD use agrees with the sim's own rule (H471).


func _ring_of_crystals(s: HHSim, centre: Vector2i, el: String = "fire") -> Array:
	var ring: Array = s.arena.ring(centre, 1)
	s.paint(ring, el, "p1", 1)
	s.step()
	s.paint(ring, "ice", "p1", 1)
	return ring


## The trap, reproduced: six crystals round a hunter (an ice cast on its own
## charged ground). Before H470 every crystal was a wall for hunters and the
## walk never left the hex.
func test_boxed_in_hunter_walks_out(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 0), "ice", "fire", "lance")
	var ring := _ring_of_crystals(s, p.hex)
	c.ok(ring.all(func(h): return s.crystal_at(h)), "six crystals round the hunter")
	var goal := Vector2i(0, 6)
	s.step({ "p1": { "move": goal, "move_pos": s.arena.stand(goal) } })
	for i in 200:
		s.step()
	c.eq(p.hex, goal, "the boxed-in hunter walks out")
	c.ok(ring.all(func(h): return s.crystal_at(h)), "walking through never breaks a crystal")


## The same box but the crystal also formed under the hunter (the old push-out
## case): nothing slides the hunter, it stands in the frost and walks out.
func test_crystal_underfoot_holds_nobody(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 0), "ice", "fire", "lance")
	var area: Array = s.arena.area(p.hex, 2)
	s.paint(area, "water", "p1", 1)
	s.step()
	s.paint(area, "ice", "p1", 1)
	var pushed := false
	for e in s.step():
		if str(e.type) == "push_out":
			pushed = true
	c.ok(s.crystal_at(Vector2i(0, 0)), "a crystal under the hunter")
	c.ok(not pushed, "no push: a crystal never moves a hunter")
	c.eq(p.hex, Vector2i(0, 0), "the hunter stands where it was")
	c.ok(s.blocked_for(p).is_empty(), "no crystal is a wall for a hunter")
	var goal := Vector2i(-5, 0)
	s.step({ "p1": { "move": goal, "move_pos": s.arena.stand(goal) } })
	for i in 200:
		s.step()
	c.eq(p.hex, goal, "it walks straight out")


## The walk-into-reach (a basic's approach) must not fail because every
## reach hex is a crystal: the hunter steps into one and strikes, and that
## strike shatters it (H365's weapon hit) at the hunter's full rate.
func test_reach_through_a_crystal_field(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 6), "ice", "fire", "lance")
	var m := s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	var field: Array = []
	for h in s.arena.area(m.hex, 4):
		if HHHex.distance(h, m.hex) > 2:
			field.append(h)
	s.paint(field, "fire", "p1", 1)
	s.step()
	s.paint(field, "ice", "p1", 1)
	c.ok(field.all(func(h): return s.crystal_at(h)), "a crystal moat round the monster")
	var hp := float(m.hp)
	for i in 240:
		s.step({ "p1": { "target": "m", "attack": true } } if i == 0 else {})
	c.ok(float(m.hp) < hp, "the hunter crossed the moat and hit the monster")


## Crystals stay the monster's problem and the party's cover.
func test_monster_still_crushes_and_beams_still_stop(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	s.add_player("p1", Vector2i(0, 6), "ice", "fire", "lance")
	var m := s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	var mb := s.blocked_for(m)
	var ahead := Vector2i(0, 1)
	s.paint([ahead], "fire", "p1", 2)
	s.step()
	s.paint([ahead], "ice", "p1", 1)
	c.ok(not mb.has(ahead), "a monster never paths round a crystal (it crushes it, H367)")
	c.eq(s.first_crystal([Vector2i(0, 0), ahead, Vector2i(0, 2)]), 1, "a sweep beam stops at it (cover)")
	s.monster_move(m, Vector2i(0, -1))
	var crushed := false
	for i in 40:
		for e in s.step():
			if str(e.type) == "shatter":
				crushed = true
	c.ok(crushed, "the monster's hull crushes it")


## The read the view and HUD use (H471) is the sim's own rule.
func test_crystal_response_matches_the_sim(c: HHSelfTest.HHCheck) -> void:
	for el in HHFormulas.ELEMENTS:
		for stored in [["fire", 1], ["fire", 3], ["dark", 2]]:
			for ice in [1, 3]:
				var g := HHCharge.new(HHArena.round_flat(1, 10.0, 0.0))
				var h := Vector2i(0, 0)
				g.apply([h], str(stored[0]), "p1", int(stored[1]))
				g.apply([h], "ice", "p1", ice)
				var e := g.at(h).duplicate()
				var said := HHCharge.crystal_response(e, str(el), 1)
				var r := g.apply([h], str(el), "p2", 1)
				var did := "none"
				if not (r.shatters as Array).is_empty():
					did = "shatter"
				elif g.is_crystal(h) and (g.at(h) != e):
					did = "feed"
				c.eq(str(said.kind), did, "%s on %s %d / ice %d" % [el, stored[0], stored[1], ice])
				if did == "shatter":
					c.near(float(said.mult), float((r.shatters[0] as Dictionary).mult), 0.001, "the preview multiple is the real one")


## H471: the view's read. Primed = the hunter's ACTIVE element breaks
## it (label "BREAK", cracks and pulse); the backup says "W: BREAK"; a feed
## says so; the HUD hint reads the same rule.
func test_view_read(c: HHSelfTest.HHCheck) -> void:
	HHTune.set_value("crystal_hint_hexes", 7.0)            # off by default since H473; the read itself still works
	_view_read(c)
	HHTune.set_value("crystal_hint_hexes", HHTune.default_of("crystal_hint_hexes"))


func _view_read(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 4), "ice", "fire", "lance")
	s.add_monster("m", Vector2i(0, -4), 20000.0, 2)
	var h := Vector2i(0, 2)
	s.paint([h], "fire", "p1", 2)
	s.step()
	s.paint([h], "ice", "p1", 1)
	var e: Dictionary = s.charge.at(h)
	var r := HHReactionFx.crystal_read(e, p)
	c.ok(not bool(r.primed), "ice / fire on a fire-2 crystal: both feed, not primed")
	c.eq(str(r.text), "x5", "the label is just its size")
	c.eq(str(HHHud.crystal_hint(s, p).kind), "feed", "the HUD says the active element feeds it")
	c.near(float(r.mult), 2.0 * 2.0 + 1.0, 0.001, "its size: x5 (2 per point + 1 per ice)")
	p.element = "water"
	r = HHReactionFx.crystal_read(e, p)
	c.ok(bool(r.primed), "water active: primed")
	c.ok(str(r.text).begins_with("x5") and str(r.text).contains("BREAK"), "label x5 BREAK: %s" % r.text)
	p.element = "ice"
	p.backup = "light"
	r = HHReactionFx.crystal_read(e, p)
	c.ok(str(r.text).contains("W: BREAK"), "the backup breaks it: %s" % r.text)
	var hint := HHHud.crystal_hint(s, p)
	c.eq(str(hint.kind), "swap", "HUD: swap to break")
	c.ok(str(hint.text).contains("LIGHT SHATTERS"), "HUD text: %s" % hint.text)
	p.element = "thunder"
	hint = HHHud.crystal_hint(s, p)
	c.eq(str(hint.kind), "shatter", "HUD: the active element shatters it")
	c.near(float(hint.mult), 5.0, 0.001, "at x5")
	p.hex = Vector2i(0, 12)
	c.eq(str(HHHud.crystal_hint(s, p).kind), "", "no hint for a crystal beyond crystal_hint_hexes")
