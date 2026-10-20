extends RefCounted
## Lane A: the dual daggers kit (HHDaggers): fast basics, Flourish, Daggerleap's trail, Knifedance.


func _sim() -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "water", "daggers")
	s.add_monster("m", Vector2i(0, -2), 20000.0, 2)   # H50: fire basics set off overheats now; this suite measures cadence
	return s


func test_basics_fast(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	c.eq(int(p.reach), int(HHDaggers.TUNE.reach), "reach 1 from the weapon")
	s.step({ "p1": { "target": "m", "attack": true } })
	var strikes := 0
	var windups := 0
	var painted := false
	for i in 300:
		for e in s.step():
			if e.type == "strike" and e.cause == "basic":
				strikes += 1
				c.near(float(e.amount), float(HHDaggers.TUNE.basic_dmg), 0.5, "a basic does basic_dmg")
			if e.type == "windup" and e.kind == "basic":
				windups += 1
				c.eq(int(e.ticks), int(HHDaggers.TUNE.basic_windup), "short wind-up")
			if e.type == "paint" and e.id == "p1" and e.element == "fire":
				painted = true
	c.ok(strikes >= 8, "fast basics: many strikes in 10 s (%d)" % strikes)
	c.ok(windups >= strikes, "every basic winds up first")
	c.ok(float(m.hp) < 20000.0, "the monster took damage")
	c.ok(painted, "a basic lays the element (H27)")
	c.ok(HHHex.distance(p.hex, m.hex) <= int(p.reach) + int(m.size), "stands in reach")


func test_flourish(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	s.step({ "p1": { "move": Vector2i(0, 1) } })
	for i in 90:
		s.step()
	c.eq(p.hex, Vector2i(0, 1), "walked up to the monster")
	var hp := float(m.hp)
	var wound := false
	for e in s.step({ "p1": { "cast": { "skill": "q", "aim": m.hex } } }):
		if e.type == "windup" and e.kind == "flourish":
			wound = true
	c.ok(wound, "flourish winds up (H34)")
	c.ok(s.held(p), "committed during the wind-up")
	c.near(float(m.hp), hp, 0.1, "no damage during the wind-up")
	var fired := false
	for i in int(HHDaggers.TUNE.q_windup) + 1:
		for e in s.step():
			if e.type == "flourish":
				fired = true
				c.eq((e.hexes as Array).size(), 7, "a tap (level 1, H56): radius-1 area")
	c.ok(fired, "flourish landed")
	c.ok(float(m.hp) < hp, "the monster in the area took damage")
	c.ok(s.charge.intensity(p.hex, "fire") >= 1, "the area carries the element")
	c.ok(s.charge.intensity(Vector2i(0, 2), "fire") >= 1, "...out to the ring at 1")
	c.ok(int(p.cooldowns.q) > 0 and int(p.cooldowns.q) <= int(HHDaggers.TUNE.q_cd) - int(HHDaggers.TUNE.q_windup), "cooldown set at cast, counting since")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "q", "aim": m.hex } } }):
		if e.type == "cast_refused":
			refused = true
	c.ok(refused, "refused on cooldown")


func test_daggerleap_trail(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var from: Vector2i = p.hex
	var to := Vector2i(3, 3)
	var leaped := false
	for e in s.step({ "p1": { "cast": { "skill": "e", "aim": to } } }):
		if e.type == "leap":
			leaped = true
			c.eq(int(e.ticks), int(HHDaggers.TUNE.e_air_ticks), "15 ticks in the air")
	c.ok(leaped, "daggerleap began")
	c.ok(bool(p.untargetable), "untargetable while leaping")
	var landed := false
	var trail: Array = []
	for i in int(HHDaggers.TUNE.e_air_ticks) + 1:
		for e in s.step():
			if e.type == "land":
				landed = true
			if e.type == "daggerleap":
				trail = e.hexes
	c.ok(landed, "landed")
	c.eq(p.hex, to, "at the aim hex")
	c.ok(not bool(p.untargetable), "targetable again")
	var line := HHHex.line(from, to)
	c.eq(trail.size(), line.size(), "the trail is the line from start to landing")
	for h in line:
		c.ok(s.charge.intensity(h, "fire") >= 1, "trail hex %s painted" % h)
	c.ok(int(p.cooldowns.e) > 0, "cooldown set")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "e", "aim": from } } }):
		if e.type == "cast_refused":
			refused = true
	c.ok(refused, "refused on cooldown")
	# out of range: clamped along the line
	var t := _sim()
	var q := t.unit("p1")
	t.step({ "p1": { "cast": { "skill": "e", "aim": Vector2i(0, -12) } } })
	var L: Dictionary = q.leap
	c.ok(not L.is_empty() and HHHex.distance(Vector2i(0, 6), L.to) <= int(HHDaggers.TUNE.e_range), "leap clamped to range")


func test_knifedance(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	m.element = "water"
	var before := s.strike(m, p, 100.0, p.hex, "probe")
	c.near(before, 100.0, 0.5, "100 before the dance")
	var started := false
	for e in s.step({ "p1": { "cast": { "skill": "r", "aim": p.hex } } }):
		if e.type == "knifedance" and e.phase == "start":
			started = true
	c.ok(started, "knifedance started")
	for el in HHFormulas.ELEMENTS:
		c.near(s.resist_of(p, el), -float(HHDaggers.TUNE.r_vuln_pct), 0.01, "resist %s is -25" % el)
	var during := s.strike(m, p, 100.0, p.hex, "probe")
	c.near(during, 125.0, 0.5, "takes 25% more while dancing")
	c.ok(not s.held(p), "free to move while dancing")
	var pulses: Array = []
	var ended := false
	for e in s.step():
		if e.type == "knifedance" and e.phase == "pulse":
			pulses.append(str(e.element))
	c.eq(pulses, ["fire"], "the first pulse comes at once, with the active element")
	c.ok(s.charge.intensity(p.hex, "fire") >= 1, "the ground under the dancer carries it")
	c.ok(s.charge.intensity(HHHex.neighbors(p.hex)[0], "fire") >= 1, "...and the ring")
	for i in int(HHDaggers.TUNE.r_ticks) + 1:
		for e in s.step():
			if e.type == "knifedance" and e.phase == "pulse":
				pulses.append(str(e.element))
				c.eq((e.hexes as Array).size(), 7, "own hex and ring")
			if e.type == "knifedance" and e.phase == "end":
				ended = true
	c.eq(pulses.size(), 6, "six pulses in 6 s")
	c.eq(pulses, ["fire", "water", "fire", "water", "fire", "water"], "active, backup, alternating (water douses the fire: a reaction a second)")
	c.ok(ended, "the dance ended")
	for el in HHFormulas.ELEMENTS:
		c.near(s.resist_of(p, el), 0.0, 0.01, "resist %s restored" % el)
	var after := s.strike(m, p, 100.0, p.hex, "probe")
	c.near(after, 100.0, 0.5, "back to 100 after")
	c.ok(not s.brains.has("p1"), "the ticker unhooked itself")
	c.ok(int(p.cooldowns.r) > 0, "cooldown set")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "r", "aim": p.hex } } }):
		if e.type == "cast_refused":
			refused = true
	c.ok(refused, "refused on cooldown")


func test_swap(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.step({ "p1": { "swap": true } })
	c.eq(p.element, "water", "swapped")
	c.eq(p.backup, "fire", "backup is the old active")
	s.step({ "p1": { "swap": true } })
	c.eq(p.element, "water", "second swap refused on cooldown")


## Lane U (H550): daggers without upgrades play exactly as before: no
## "upgrade" event, no projectiles, a 6 s Knifedance.
func test_no_upgrades_means_the_plain_kit(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	c.eq((p.upgrades as Dictionary).size(), 0, "no upgrades by default")
	var ups := 0
	var evs: Array = []
	evs.append_array(s.step({ "p1": { "cast": { "skill": "e", "aim": Vector2i(0, 3) } } }))
	for i in int(HHDaggers.TUNE.e_air_ticks) + 1:
		evs.append_array(s.step())
	evs.append_array(s.step({ "p1": { "cast": { "skill": "q", "aim": p.hex } } }))
	for i in int(HHDaggers.TUNE.q_windup) + 1:
		evs.append_array(s.step())
	evs.append_array(s.step({ "p1": { "swap": true } }))
	evs.append_array(s.step({ "p1": { "cast": { "skill": "r", "aim": p.hex } } }))
	for e in evs:
		if e.type == "upgrade" or e.type == "projectile" or e.type == "immune":
			ups += 1
		if e.type == "knifedance" and e.phase == "start":
			c.eq(int(e.ticks), int(HHDaggers.TUNE.r_ticks), "plain Knifedance length")
	c.eq(ups, 0, "no upgrade effects without upgrades")
	c.eq(s.projectiles.size(), 0, "nothing in flight")
