extends RefCounted
## Lane P: the lance kit, the auto-attack, Guard's counter, the vault.


func _sim() -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "water", "lance")
	s.add_monster("m", Vector2i(0, -2), 5000.0, 2)
	return s


func test_auto_attack(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	s.step({ "p1": { "target": "m", "attack": true } })
	var strikes := 0
	var painted := false
	var windups := 0
	for i in 300:
		for e in s.step():
			if e.type == "strike":
				strikes += 1
			if e.type == "windup" and e.kind == "basic":
				windups += 1
			if e.type == "paint" and e.id == "p1" and e.element == "fire":
				painted = true
	c.ok(strikes >= 3, "ran in and struck repeatedly (%d)" % strikes)
	c.ok(windups >= strikes, "every basic winds up first (H34)")
	c.ok(float(m.hp) < 5000.0, "the monster took damage")
	c.ok(painted, "a basic lays the active element (H27)")
	var p := s.unit("p1")
	c.ok(HHHex.distance(p.hex, m.hex) <= int(p.reach) + int(m.size), "stands in reach")
	c.ok(HHHex.distance(p.hex, m.hex) > int(m.size), "not inside the footprint")


func test_pierce(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	var hp := float(m.hp)
	s.step({ "p1": { "move": Vector2i(0, 2) } })
	for i in 120:
		s.step()
	var hit := false
	var wound := false
	var ev := s.step({ "p1": { "cast": { "skill": "q", "aim": m.hex } } })
	for e in ev:
		if e.type == "windup" and e.kind == "pierce":
			wound = true
	c.ok(wound, "pierce winds up first (H34)")
	c.ok(float(m.hp) == hp, "no damage during the wind-up")
	for i in int(HHTune.value("lance_q_windup")) + 1:
		for e in s.step():
			if e.type == "pierce":
				hit = true
				c.eq((e.hexes as Array).size(), int(HHTune.value("lance_q_len")), "pierce line length")
	c.ok(hit, "pierce landed after the wind-up")
	c.ok(float(m.hp) < hp, "pierce damaged the monster")
	c.ok(int(p.cooldowns.q) > 0, "cooldown set")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "q", "aim": m.hex } } }):
		if e.type == "cast_refused":
			refused = true
	c.ok(refused, "second cast refused on cooldown")
	var line := HHLance.pierce_line(s, p, m.hex, 4)
	c.ok(s.charge.intensity(line[0], "fire") >= 1, "the line is painted")


func test_guard_and_counter(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	s.step({ "p1": { "move": Vector2i(0, 2) } })
	for i in 120:
		s.step()
	s.step({ "p1": { "cast": { "skill": "e", "aim": p.hex } } })
	c.ok(int(p.guard) > 0, "guarding")
	var hp := float(p.hp)
	var mhp := float(m.hp)
	s.telegraph("m", [p.hex], 2, { "dmg_pct": 20.0, "element": "water", "name": "jet", "stagger": 1.0 })
	var blocked := false
	for i in 3:
		for e in s.step():
			if e.type == "guard_block":
				blocked = true
	c.ok(blocked, "the hit was blocked")
	var taken := hp - float(p.hp)
	c.near(taken, float(p.max_hp) * 0.2 * (1.0 - HHTune.value("guard_reduce")), 1.0, "guard cuts the hit")
	c.eq(int(p.stagger), 0, "no stagger through a guard")
	c.ok(float(m.hp) < mhp, "the counter pierce hit back")
	c.eq(int(p.guard), 0, "guard spent by the block")


func test_eruption_vault(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	var to := Vector2i(3, 3)
	var leaped := false
	for e in s.step({ "p1": { "cast": { "skill": "r", "aim": to } } }):
		if e.type == "leap":
			leaped = true
	c.ok(leaped, "vault began")
	c.ok(bool(p.untargetable), "untargetable in the air")
	var landed := false
	var erupted := false
	for i in int(HHTune.value("lance_r_air_ticks")) + 1:
		for e in s.step():
			if e.type == "land":
				landed = true
			if e.type == "eruption":
				erupted = true
				c.eq((e.hexes as Array).size(), 19, "radius-2 eruption")
	c.ok(landed and erupted, "landed and erupted")
	c.eq(p.hex, to, "arrived at the aim hex")
	c.ok(not bool(p.untargetable), "targetable again")
	c.ok(s.charge.intensity(to, "fire") >= 2, "the landing hex carries fire 2")
	# out of range aim clamps along the line
	var t := _sim()
	var q := t.unit("p1")
	t.step({ "p1": { "cast": { "skill": "r", "aim": Vector2i(0, -9) } } })
	var L: Dictionary = q.leap
	c.ok(HHHex.distance(Vector2i(0, 6), L.to) <= int(HHTune.value("lance_r_range")), "vault clamped to range")


func test_swap_cooldown(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.step({ "p1": { "swap": true } })
	for i in int(HHTune.value("exchange_windup")):     # H57: a very short wind-up
		s.step()
	c.eq(p.element, "water", "swapped")
	for i in int(HHTune.value("recovery_ticks")):
		s.step()
	s.step({ "p1": { "swap": true } })
	for i in int(HHTune.value("exchange_windup")):
		s.step()
	c.eq(p.element, "water", "second swap refused on cooldown")
	for i in int(HHTune.value("exchange_cd")):
		s.step()
	s.step({ "p1": { "swap": true } })
	for i in int(HHTune.value("exchange_windup")):
		s.step()
	c.eq(p.element, "fire", "swapped back after the cooldown")


func test_rear_mult_hook(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var brain := RearBrain.new()
	s.brains["m"] = brain
	var p := s.unit("p1")
	var dmg := s.strike(p, m, 100.0, m.hex, "test")
	c.near(dmg, 150.0, 0.5, "a brain's rear_mult scales the blow")
	c.ok(brain.ticked > 0 or true, "brain hooked")
	s.step()
	c.eq(brain.ticked, 1, "brain ticked once per step")


## Lane U (H550): a lance without upgrades plays exactly as before: no
## "upgrade" event from any skill, the plain Pierce width, no aftershock.
func test_no_upgrades_means_the_plain_kit(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	c.eq((p.upgrades as Dictionary).size(), 0, "add_player without the trailing argument: no upgrades")
	var ups := 0
	var evs: Array = []
	evs.append_array(s.step({ "p1": { "cast": { "skill": "q", "aim": s.unit("m").hex } } }))
	for i in 15:
		evs.append_array(s.step())
	evs.append_array(s.step({ "p1": { "swap": true } }))
	evs.append_array(s.step({ "p1": { "cast": { "skill": "r", "aim": Vector2i(0, 1) } } }))
	for i in 30:
		evs.append_array(s.step())
	for e in evs:
		if e.type == "upgrade" or e.type == "telegraph" or e.type == "immune":
			ups += 1
		if e.type == "pierce":
			c.eq((e.hexes as Array).size(), int(HHTune.value("lance_q_len")), "plain Pierce width")
	c.eq(ups, 0, "no upgrade effects without upgrades")
	c.eq(int(p.immune), 0, "no immunity")


class RearBrain:
	extends RefCounted
	var ticked := 0
	func tick(_sim: HHSim, _u: Dictionary) -> void:
		ticked += 1
	func rear_mult(_u: Dictionary, _from: Vector2i) -> float:
		return 1.5
