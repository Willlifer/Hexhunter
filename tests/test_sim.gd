extends RefCounted
## HHSim: the 30 Hz tick, movement, ground damage, determinism.


func _sim(seed: int = 1) -> HHSim:
	var a := HHArena.round_flat(seed, 17.5, 0.0)
	var s := HHSim.new(a, seed)
	s.add_player("p1", Vector2i(0, 4))
	return s


func test_walk_arrives(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var goal := Vector2i(4, 0)
	s.step({ "p1": { "move": goal } })
	var p := s.unit("p1")
	c.ok(not (p.path as Array).is_empty(), "a move order sets a path")
	var dist := HHHex.distance(Vector2i(0, 4), goal)
	var ticks := int(HHTune.value("walk_ticks"))
	var arrived := -1
	for i in dist * ticks + 5:
		for e in s.step():
			if e.type == "arrive":
				arrived = e.tick
	c.eq(p.hex, goal, "arrived at the goal")
	c.ok(arrived > 0 and arrived <= dist * ticks + 1, "arrival within distance * walk_ticks (%d)" % arrived)
	c.near((p.pos as Vector3).x, s.arena.world(goal).x, 1e-4, "pos snaps to the centre")


func test_glide_is_between_centres(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	s.step({ "p1": { "move": Vector2i(3, 4) } })
	for i in 7:
		s.step()
	var p := s.unit("p1")
	var a := s.arena.world(p.hex)
	var b := s.arena.world(p.path[0])
	var pos: Vector3 = p.pos
	c.ok(pos.distance_to(a) > 0.1 and pos.distance_to(b) > 0.1, "mid-step: between the two centres")
	c.near(pos.distance_to(a) + pos.distance_to(b), a.distance_to(b), 1e-4, "on the segment")


func test_stop_and_run(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	s.step({ "p1": { "move": Vector2i(6, 4), "run": true } })
	for i in 3:
		s.step()
	s.step({ "p1": { "stop": true } })
	var p := s.unit("p1")
	c.ok((p.path as Array).is_empty(), "stop clears the path")
	var r := _sim()
	r.step({ "p1": { "move": Vector2i(6, 4), "run": true } })
	var w := _sim()
	w.step({ "p1": { "move": Vector2i(6, 4) } })
	for i in 40:
		r.step()
		w.step()
	c.ok(HHHex.distance(r.unit("p1").hex, Vector2i(0, 4)) > HHHex.distance(w.unit("p1").hex, Vector2i(0, 4)), "running is faster")


func test_ground_fire_burns(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.paint([p.hex], "fire", "env", 3)
	var every := int(HHTune.value("ground_tick_every"))
	for i in every:
		s.step()
	var expect: float = HHFormulas.tile_damage(p.max_hp, HHTune.value("fire_stand_pct") * 3).value
	c.near(float(p.hp), float(p.max_hp) - expect, 0.5, "fire 3 burns fire_stand_pct * 3 per second")
	s.paint([p.hex], "water", "env", 3)
	var hp := float(p.hp)
	for i in every:
		s.step()
	c.near(float(p.hp), hp, 0.5, "doused: no burn")


func test_crossing_fire(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var next := Vector2i(1, 4)
	s.paint([next], "fire", "env", 2)
	s.step({ "p1": { "move": next } })
	var burned := false
	for i in int(HHTune.value("walk_ticks")) + 2:
		for e in s.step():
			if e.type == "hurt" and e.cause == "fire_cross":
				burned = true
	c.ok(burned, "entering a fire hex burns once")


func test_detonation_hurts(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.paint([p.hex], "fire", "env", 2)
	var hp := float(p.hp)
	s.paint([p.hex], "thunder", "env")
	c.ok(float(p.hp) < hp, "a detonation under you hurts")
	var m := s.add_monster("stub", Vector2i(0, -4), 1000.0, 2)
	var side := Vector2i(0, -1)                    # inside the monster's radius-2 footprint
	s.paint([side], "light", "env", 2)
	var mhp := float(m.hp)
	s.paint([side], "thunder", "env")
	c.ok(float(m.hp) < mhp, "a blast inside the footprint hurts the monster")


func test_swap_and_statuses(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.step({ "p1": { "swap": true } })
	c.eq(p.element, "water", "swap: backup becomes active")
	c.eq(p.backup, "fire", "and active becomes backup")
	s.apply_status(p, "burn", 60)
	var hp := float(p.hp)
	for i in 61:
		s.step()
	c.ok(float(p.hp) < hp, "burn ticks")
	c.ok(not p.statuses.has("burn"), "burn ends")
	s.apply_status(p, "paralysis", 30)
	s.step({ "p1": { "move": Vector2i(3, 4) } })
	c.ok((p.path as Array).is_empty(), "paralysed: no move")


func test_stagger_holds(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.step({ "p1": { "move": Vector2i(4, 4) } })
	s.hurt(p, 10.0, "test", 1.0)
	var hex: Vector2i = p.hex
	for i in int(HHTune.value("stagger_max_ticks")) - 1:
		s.step()
	c.eq(p.hex, hex, "held in place while staggered")
	for i in int(HHTune.value("walk_ticks")) * 2:
		s.step()
	c.ok(p.hex != hex, "moves again after")


func test_walk_into_reach(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	s.add_monster("stub", Vector2i(0, -4), 1000.0, 2)
	s.step({ "p1": { "target": "stub" } })
	for i in 400:
		s.step()
	var p := s.unit("p1")
	c.ok(HHHex.distance(p.hex, Vector2i(0, -4)) <= int(p.reach) + 2, "walked into reach")
	c.ok(HHHex.distance(p.hex, Vector2i(0, -4)) > 2, "but not into the footprint")


func test_determinism(c: HHSelfTest.HHCheck) -> void:
	var a := _sim(5)
	var b := _sim(5)
	var orders := { 3: { "p1": { "move": Vector2i(5, 2) } }, 20: { "p1": { "paint": { "element": "fire", "hex": Vector2i(1, 2), "steps": 3 } } },
		40: { "p1": { "paint": { "element": "thunder", "hex": Vector2i(1, 2) } } }, 60: { "p1": { "swap": true } } }
	for i in 120:
		a.step(orders.get(i, {}))
		b.step(orders.get(i, {}))
	c.eq(a.state_hash(), b.state_hash(), "same seed + orders = same hash")
	var d := _sim(5)
	for i in 120:
		d.step(orders.get(i, {}) if i != 3 else {})
	c.ok(d.state_hash() != a.state_hash(), "different orders = different hash")


func test_over(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.add_monster("stub", Vector2i(0, -4), 10.0, 2)
	s.hurt(m, 100.0, "test")
	s.step()
	c.eq(s.over, "win", "all monsters down = win")
	var t := _sim()
	t.hurt(t.unit("p1"), 1e9, "test")
	t.step()
	c.eq(t.over, "dead", "player down = dead")
