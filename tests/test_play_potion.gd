extends RefCounted
## H40: potions, and the ground fighting the heal.


func _sim() -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "light", "lance")
	return s


func test_potion_heals_over_time(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.hurt(p, 2000.0, "test")
	c.eq(int(p.potions), int(HHTune.value("potion_count")), "starts with potions")
	s.step({ "p1": { "potion": true } })
	c.ok(not (p.windup as Dictionary).is_empty(), "drinking is a wind-up")
	for i in int(HHTune.value("potion_windup")) + 1:
		s.step()
	c.eq(int(p.potions), int(HHTune.value("potion_count")) - 1, "one potion spent")
	c.ok(not (p.regen as Dictionary).is_empty(), "regen running")
	var hp := float(p.hp)
	for i in int(HHTune.value("potion_seconds") * 30.0) + 30:
		s.step()
	c.near(float(p.hp) - hp, float(p.max_hp) * HHTune.value("potion_heal_pct") / 100.0, 2.0, "healed potion_heal_pct over its seconds")
	c.ok((p.regen as Dictionary).is_empty(), "regen ended")
	var refused := false
	for e in s.step({ "p1": { "potion": true } }):
		if e.type == "cast_refused" and e.skill == "t":
			refused = true
	c.ok(refused, "second potion refused on cooldown")


func test_dark_starves_light_feeds(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.paint([p.hex], "dark", "env", 3)
	c.near(s.heal_mult(p), 0.1, 1e-6, "dark 3 under you: healing at 10%")
	s.paint([p.hex], "light", "env", 3)
	c.near(s.heal_mult(p), 1.0, 1e-6, "light cancels the dark (same axis)")
	s.paint([p.hex], "light", "env", 2)
	c.near(s.heal_mult(p), 1.0 + 2.0 * HHTune.value("light_heal_bonus"), 1e-6, "light 2 under you feeds the heal")


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
	s.step({ "p1": { "potion": true } })
	var dark := false
	for i in int(HHTune.value("potion_windup")) + 6:
		for e in s.step():
			if e.type == "telegraph" and str(e.name) == "darkness":
				dark = true
	c.ok(dark, "the monster calls down darkness after a potion")
