extends RefCounted
## HHSim: the 30 Hz tick, movement, ground damage, determinism.


func _sim(seed: int = 1) -> HHSim:
	var a := HHArena.round_flat(seed, 17.5, 0.0)
	var s := HHSim.new(a, seed)
	s.sandbox = true
	s.add_player("p1", Vector2i(0, 4))
	return s


func test_run_arrives(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var goal := Vector2i(4, 0)
	var exact := s.arena.stand(goal) + Vector3(0.3, 0.0, -0.2)
	s.step({ "p1": { "move": goal, "move_pos": exact } })
	var p := s.unit("p1")
	var dist_m := (s.arena.stand(Vector2i(0, 4)) as Vector3).distance_to(exact)
	var ticks := int(ceil(dist_m / (HHTune.value("run_mps") * HHSim.TICK)))
	var arrived := -1
	for i in ticks + 5:
		for e in s.step():
			if e.type == "arrive":
				arrived = e.tick
	c.eq(p.hex, goal, "arrived at the goal hex")
	c.ok(arrived > 0 and arrived <= ticks + 2, "arrival within distance / run_mps (%d <= %d)" % [arrived, ticks])
	c.near((p.pos as Vector3).distance_to(exact), 0.0, 1e-3, "pos is the exact point clicked (H31)")


func test_free_glide_is_straight(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var start: Vector3 = s.unit("p1").pos
	var goal := s.arena.stand(Vector2i(4, 4))
	s.step({ "p1": { "move": Vector2i(4, 4), "move_pos": goal } })
	for i in 12:
		s.step()
	var pos: Vector3 = s.unit("p1").pos
	c.ok(pos.distance_to(start) > 1.0, "moving")
	var seg := goal - start
	var t := (pos - start).dot(seg) / seg.length_squared()
	var off := (pos - (start + seg * t)).length()
	c.ok(off < 0.05, "straight line on open ground (off by %.3f)" % off)
	c.ok(s.unit("p1").hex == s.arena.from_world(pos), "hex follows the position")


func test_stop_and_run(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	s.step({ "p1": { "move": Vector2i(6, 4), "run": true } })
	for i in 3:
		s.step()
	s.step({ "p1": { "stop": true } })
	var p := s.unit("p1")
	c.ok((p.path as Array).is_empty() and (p.goal_pos as Vector3) == HHSim.NO_POS, "stop clears the route")
	var r := _sim()
	r.step({ "p1": { "move": Vector2i(6, 4), "run": true } })
	var w := _sim()
	w.step({ "p1": { "move": Vector2i(6, 4), "run": false } })
	for i in 20:
		r.step()
		w.step()
	var start := r.arena.stand(Vector2i(0, 4))
	c.ok((r.unit("p1").pos as Vector3).distance_to(start) > (w.unit("p1").pos as Vector3).distance_to(start), "running is faster than walking (Shift, H37)")
	c.ok(bool(_sim().unit("p1").run), "players run by default")


func test_ground_fire_burns(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.paint([p.hex], "fire", "env", 3)
	var every := int(HHTune.value("ground_tick_every"))
	var own := _sim()
	var q := own.unit("p1")
	own.paint([q.hex], "fire", "p1", 3)
	for i in every:
		own.step()
	c.near(float(q.hp), float(q.max_hp), 0.5, "your own fire never hurts you (H33)")
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
	s.step({ "p1": { "move": next, "move_pos": s.arena.stand(next) } })
	var burned := false
	for i in 20:
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
	s.step({ "p1": { "move": Vector2i(4, 4), "move_pos": s.arena.stand(Vector2i(4, 4)) } })
	s.hurt(p, 10.0, "test", 1.0)
	var hex: Vector2i = p.hex
	for i in int(HHTune.value("stagger_max_ticks")) - 1:
		s.step()
	c.eq(p.hex, hex, "held in place while staggered")
	c.ok((p.path as Array).is_empty() and (p.goal_pos as Vector3) == HHSim.NO_POS, "a stagger interrupts the run")
	for i in 3:
		s.step()                                   # the hold runs out
	s.step({ "p1": { "move": Vector2i(4, 4), "move_pos": s.arena.stand(Vector2i(4, 4)) } })
	for i in 20:
		s.step()
	c.ok(p.hex != hex, "moves again after a new order")


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
	var orders := { 3: { "p1": { "move": Vector2i(5, 2), "move_pos": a.arena.stand(Vector2i(5, 2)) } }, 20: { "p1": { "paint": { "element": "fire", "hex": Vector2i(1, 2), "steps": 3 } } },
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
