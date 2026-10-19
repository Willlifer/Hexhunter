extends RefCounted
## Lane P: telegraphs (the monster's danger shapes) and monster movement.


func _sim() -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "water", "lance")
	s.add_monster("m", Vector2i(0, -2), 5000.0, 2)
	return s


func test_telegraph_lands_on_time(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var id := s.telegraph("m", HHHex.area(p.hex, 1), 10, { "dmg_pct": 10.0, "element": "water", "paint_steps": 1, "name": "splash", "stagger": 0.5, "status": "poison", "status_ticks": 60 })
	c.ok(id > 0, "telegraph id")
	c.eq(s.telegraphs.size(), 1, "pending")
	var hp := float(p.hp)
	var ended_at := -1
	for i in 12:
		for e in s.step():
			if e.type == "telegraph_end":
				ended_at = e.tick
				c.ok("p1" in e.hit, "the player was in it")
	c.eq(ended_at, 10, "resolved on tick 10")
	c.near(float(p.hp), hp - float(p.max_hp) * 0.1, 0.5, "10% landed")
	c.ok(int(p.stagger) > 0, "staggered")
	c.ok(p.statuses.has("poison"), "poisoned")
	c.ok(s.charge.intensity(p.hex, "water") >= 1, "the shape was painted")
	c.ok(s.telegraphs.is_empty(), "gone")


func test_telegraph_misses_when_you_leave(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var hp := float(p.hp)
	s.telegraph("m", [p.hex], 40, { "dmg_pct": 10.0, "name": "slam" })
	s.step({ "p1": { "move": Vector2i(3, 6), "move_pos": s.arena.stand(Vector2i(3, 6)), "run": true } })
	for i in 45:
		s.step()
	c.near(float(p.hp), hp, 0.5, "walked out: no damage")


func test_owner_not_hit_unless_self_hit(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var hp := float(m.hp)
	s.telegraph("m", HHHex.area(m.hex, 2), 1, { "dmg_pct": 10.0 })
	s.step()
	c.near(float(m.hp), hp, 0.5, "owner spared")
	s.telegraph("m", HHHex.area(m.hex, 2), 1, { "dmg_pct": 10.0, "self_hit": true })
	s.step()
	c.ok(float(m.hp) < hp, "self_hit hurts the owner")


func test_untargetable_skips_blasts(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	m.untargetable = true
	var hp := float(m.hp)
	s.paint([m.hex], "fire", "env", 2)
	s.paint([m.hex], "thunder", "env")
	c.near(float(m.hp), hp, 0.5, "a submerged monster is not blasted")
	s.telegraph("p1", [m.hex], 1, { "dmg_pct": 10.0 })
	s.step()
	c.near(float(m.hp), hp, 0.5, "nor hit by a telegraph")


func test_monster_move_and_kinds(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	c.ok(s.monster_move(m, Vector2i(4, 2)), "monster paths")
	for i in 200:
		s.step()
	c.eq(m.hex, Vector2i(4, 2), "monster arrived")
	# restrict to a kind that does not exist: nowhere to go
	m.allowed_kinds = ["water"]
	c.ok(not s.monster_move(m, Vector2i(0, 0)), "no path over disallowed kinds")
	# a monster walks slower than a player
	var t := _sim()
	var mm := t.unit("m")
	t.monster_move(mm, Vector2i(0, 4))
	t.step({ "p1": { "move": Vector2i(0, 0), "move_pos": t.arena.stand(Vector2i(0, 0)) } })
	for i in 30:
		t.step()
	c.ok((mm.pos as Vector3).distance_to(t.arena.stand(Vector2i(0, -2))) < (t.unit("p1").pos as Vector3).distance_to(t.arena.stand(Vector2i(0, 6))), "monster is slower")


func test_detonation_staggers(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.paint([p.hex], "light", "env", 2)
	s.paint([p.hex], "thunder", "env")
	c.ok(int(p.stagger) > 0, "a blast underfoot staggers")


func test_hash_covers_telegraphs(c: HHSelfTest.HHCheck) -> void:
	var a := _sim()
	var b := _sim()
	a.telegraph("m", [Vector2i(0, 0)], 5, {})
	c.ok(a.state_hash() != b.state_hash(), "a pending telegraph changes the hash")
