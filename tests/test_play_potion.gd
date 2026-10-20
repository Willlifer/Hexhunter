extends RefCounted
## H40 / H56: potions are a thrown heal zone, and the ground fights the heal.


func _sim() -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "light", "lance")
	return s


func _throw(s: HHSim, id: String, aim: Variant) -> Array:
	var out: Array = []
	out.append_array(s.step({ id: { "potion": { "aim": aim } if aim is Vector2i else true } }))
	for i in int(HHTune.value("potion_windup")) + 1:
		out.append_array(s.step())
	return out


func test_potion_zone_heals_over_time(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.hurt(p, 2000.0, "test")
	c.eq(int(p.potions), int(HHTune.value("potion_count")), "starts with potions")
	s.step({ "p1": { "potion": { "aim": p.hex } } })
	c.ok(not (p.windup as Dictionary).is_empty(), "throwing is a wind-up")
	c.eq(str(p.windup.kind), "potion", "...the potion wind-up")
	for i in int(HHTune.value("potion_windup")) + 1:
		s.step()
	c.eq(int(p.potions), int(HHTune.value("potion_count")) - 1, "one potion spent")
	var z: Dictionary = p.heal_zone
	c.ok(not z.is_empty(), "a heal zone on the ground")
	c.eq(int(z.radius), int(HHTune.value("potion_radius")), "zone radius potion_radius")
	c.eq(s.arena.area(z.hex, int(z.radius)).size(), 37, "radius 3 = 37 hexes")
	var hp := float(p.hp)
	for i in int(HHTune.value("potion_seconds") * 30.0) + 30:
		s.step()
	c.near(float(p.hp) - hp, float(p.max_hp) * HHTune.value("potion_heal_pct") / 100.0, 2.0, "standing in it the whole time heals potion_heal_pct (what a drink did)")
	c.ok((p.heal_zone as Dictionary).is_empty(), "zone ended")
	var refused := false
	for e in s.step({ "p1": { "potion": true } }):
		if e.type == "cast_refused" and e.skill == "t":
			refused = true
	c.ok(refused, "second potion refused on cooldown")


func test_potion_thrown_at_the_cursor(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var evs := _throw(s, "p1", Vector2i(4, 6))
	var pot := evs.filter(func(e): return e.type == "potion")
	c.eq(pot.size(), 1, "the potion landed")
	c.eq(pot[0].hex, Vector2i(4, 6), "where the cursor was")
	c.eq((p.heal_zone as Dictionary).hex, Vector2i(4, 6), "the zone sits there")
	c.eq(p.hex, Vector2i(0, 6), "the thrower stayed put")
	var t := _sim()
	var q := t.unit("p1")
	_throw(t, "p1", Vector2i(0, -14))
	var at: Vector2i = (q.heal_zone as Dictionary).hex
	c.eq(HHHex.distance(q.hex, at), int(HHTune.value("potion_range")), "a far throw clamps to potion_range along the line")


func test_zone_heals_hunters_inside_only(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	var p1 := s.add_player("p1", Vector2i(0, 6), "fire", "water", "bow")
	var p2 := s.add_player("p2", Vector2i(3, 6), "fire", "water", "lance")
	var p3 := s.add_player("p3", Vector2i(-8, 6), "fire", "water", "daggers")
	for p in [p1, p2, p3]:
		s.hurt(p, 1500.0, "test")
	c.ok(HHHex.distance(p2.hex, Vector2i(2, 6)) <= 3 and HHHex.distance(p3.hex, Vector2i(2, 6)) > 3, "setup: p2 inside, p3 outside")
	var before := [float(p1.hp), float(p2.hp), float(p3.hp)]
	_throw(s, "p1", Vector2i(2, 6))
	for i in 90:
		s.step()
	c.ok(float(p1.hp) > before[0], "the thrower inside heals")
	c.ok(float(p2.hp) > before[1], "an ally inside heals")
	c.near(float(p3.hp), before[2], 0.01, "a hunter outside the zone does not")
	c.ok(s.in_heal_zone(p2) and not s.in_heal_zone(p3), "in_heal_zone agrees")


func test_dark_starves_light_feeds(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.paint([p.hex], "dark", "env", 3)
	c.near(s.heal_mult(p), 0.1, 1e-6, "dark 3 under you: healing at 10%")
	s.paint([p.hex], "light", "env", 3)
	c.near(s.heal_mult(p), 1.0, 1e-6, "light cancels the dark (same axis)")
	s.paint([p.hex], "light", "env", 2)
	c.near(s.heal_mult(p), 1.0 + 2.0 * HHTune.value("light_heal_bonus"), 1e-6, "light 2 under you feeds the heal")


func test_zone_heal_fought_by_the_ground(c: HHSelfTest.HHCheck) -> void:
	var gains := {}
	for case in ["plain", "dark", "light"]:
		var s := _sim()
		var p := s.unit("p1")
		s.hurt(p, 2500.0, "test")
		if case == "dark":
			s.charge.author(p.hex, 0, -2, "")                # permanent dark 2 under the hunter (no drain; never decays mid-test)
		elif case == "light":
			s.charge.author(p.hex, 0, 2, "")
		var hp := float(p.hp)
		_throw(s, "p1", Vector2i(0, 4))
		for i in 95:
			s.step()
		gains[case] = float(p.hp) - hp
	c.ok(float(gains.plain) > 0.0, "the zone heals (%d)" % int(gains.plain))
	c.ok(float(gains.dark) < float(gains.plain) * 0.5, "dark under the hunter cuts it (%d vs %d)" % [int(gains.dark), int(gains.plain)])
	c.ok(float(gains.light) > float(gains.plain) * 1.2, "light under the hunter boosts it (%d vs %d)" % [int(gains.light), int(gains.plain)])


func test_swampfang_answers_a_potion(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.add_monster("swampfang", Vector2i(0, -2), 20000.0, 2)
	var brain := HHSwampfang.new("swampfang")
	s.brains["swampfang"] = brain
	s.hurt(s.unit("swampfang"), 10.0, "test")             # aggravate it
	for i in 5:
		s.step()
	s.hurt(p, 1000.0, "test")
	var zone := Vector2i(5, 8)
	s.step({ "p1": { "potion": { "aim": zone } } })
	var dark: Array = []
	for i in int(HHTune.value("potion_windup")) + 6:
		for e in s.step():
			if e.type == "telegraph" and str(e.name) == "darkness":
				dark = e.hexes
	c.ok(not dark.is_empty(), "the monster calls down darkness after a potion")
	c.ok(zone in dark, "...over the zone the potion made")
	c.ok(dark.size() > 0 and HHHex.distance(dark[0], zone) <= 6, "...centred on the zone, not the thrower")
