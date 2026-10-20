extends RefCounted
## Lane A: the bow kit (HHBow): reach-7 basics, Energized shot, Arcing shot's telegraph, Arrowstorm.


func _sim() -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 6), "fire", "water", "bow")
	s.add_monster("m", Vector2i(0, -2), 5000.0, 2)
	return s


func test_basics_reach_7(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	c.eq(int(p.reach), 7, "reach 7 from the weapon")
	c.eq(HHHex.distance(p.hex, m.hex), 8, "starts 8 hexes from the monster's centre (6 from its footprint)")
	s.step({ "p1": { "target": "m", "attack": true } })
	var strikes := 0
	var windups := 0
	var painted_target := false
	for i in 150:
		for e in s.step():
			if e.type == "strike" and e.cause == "basic":
				strikes += 1
				c.near(float(e.amount), float(HHBow.TUNE.basic_dmg), 0.5, "an arrow does basic_dmg")
			if e.type == "windup" and e.kind == "basic":
				windups += 1
				c.eq(int(e.ticks), int(HHBow.TUNE.basic_windup), "the draw")
			if e.type == "paint" and e.id == "p1" and e.element == "fire" and HHHex.distance(e.hexes[0], m.hex) <= int(m.size):
				painted_target = true
	c.ok(strikes >= 4, "shot repeatedly without walking in (%d)" % strikes)
	c.ok(windups >= strikes, "every arrow is drawn first")
	c.eq(p.hex, Vector2i(0, 6), "never moved: already in reach")
	c.ok(float(m.hp) < 5000.0, "the monster took damage")
	c.ok(painted_target, "a basic lays the element on the target's hex (H27)")


func test_energized_shot_stops_at_first_monster(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	var hp := float(m.hp)
	var wound := false
	for e in s.step({ "p1": { "cast": { "skill": "q", "aim": m.hex } } }):
		if e.type == "windup" and e.kind == "energized":
			wound = true
	c.ok(wound, "energized shot winds up")
	c.near(float(m.hp), hp, 0.1, "no damage yet")
	var shot: Dictionary = {}
	for i in int(HHBow.TUNE.q_windup) + 1:
		for e in s.step():
			if e.type == "energized_shot":
				shot = e
	c.ok(not shot.is_empty(), "the arrow flew")
	c.eq(str(shot.get("hit", "")), "m", "hit the monster")
	var hexes: Array = shot.get("hexes", [])
	c.ok(hexes.size() < int(HHBow.TUNE.q_range), "stopped at the monster (%d hexes)" % hexes.size())
	c.ok(hexes.size() >= 5, "flew the distance to the footprint")
	c.ok(HHHex.distance(hexes[-1], m.hex) <= int(m.size), "the last hex is on the footprint")
	for h in hexes:
		c.ok(s.charge.intensity(h, "fire") >= 1, "hex %s on the way is painted" % h)
	c.ok(float(m.hp) < hp, "the monster took damage")
	c.ok(int(p.cooldowns.q) > 0, "cooldown set")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "q", "aim": m.hex } } }):
		if e.type == "cast_refused":
			refused = true
	c.ok(refused, "refused on cooldown")
	# a shot into empty ground flies the full range and paints it all
	var t := _sim()
	var q := t.unit("p1")
	t.step({ "p1": { "cast": { "skill": "q", "aim": Vector2i(5, 6) } } })
	var miss: Dictionary = {}
	for i in int(HHBow.TUNE.q_windup) + 1:
		for e in t.step():
			if e.type == "energized_shot":
				miss = e
	c.eq((miss.get("hexes", []) as Array).size(), int(HHBow.TUNE.q_range), "a miss flies 10 hexes")
	c.eq(str(miss.get("hit", "x")), "", "nothing hit")
	c.ok(not t.held(q), "free after the shot")


func test_arcing_shot_is_a_telegraph(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	var hp := float(m.hp)
	var aim := Vector2i(0, 0)                        # on the footprint's edge
	var tg: Dictionary = {}
	for e in s.step({ "p1": { "cast": { "skill": "e", "aim": aim } } }):
		if e.type == "telegraph":
			tg = e
	c.ok(not tg.is_empty(), "a telegraph was posted")
	c.eq(str(tg.get("owner", "")), "p1", "owned by the archer")
	c.eq(str(tg.get("name", "")), "arcing shot", "named")
	c.eq((tg.get("hexes", []) as Array).size(), 7, "radius-1 burst")
	c.eq(int(tg.get("ticks", 0)), int(HHBow.TUNE.e_ticks), "lands after e_ticks")
	c.ok(not s.held(p), "the archer is free while it flies")
	c.near(float(m.hp), hp, 0.1, "nothing yet")
	var ended: Dictionary = {}
	for i in int(HHBow.TUNE.e_ticks):
		for e in s.step():
			if e.type == "telegraph_end":
				ended = e
	c.ok(not ended.is_empty(), "it landed")
	c.ok("m" in (ended.get("hit", []) as Array), "the monster was in the burst")
	c.ok(not "p1" in (ended.get("hit", []) as Array), "the archer is spared (owner)")
	c.near(float(m.hp), hp - float(m.max_hp) * float(HHBow.TUNE.e_dmg_pct) / 100.0, 1.0, "e_dmg_pct of max HP")
	c.ok(s.charge.intensity(aim, "fire") >= 2, "two steps of element on the burst")
	c.ok(int(p.cooldowns.e) > 0, "cooldown set")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "e", "aim": aim } } }):
		if e.type == "cast_refused":
			refused = true
	c.ok(refused, "refused on cooldown")
	# out of range: the lob lands short, along the line
	var t := _sim()
	var far_tg: Dictionary = {}
	for e in t.step({ "p1": { "cast": { "skill": "e", "aim": Vector2i(0, -14) } } }):
		if e.type == "telegraph":
			far_tg = e
	var centre := HHBow.clamp_along(t, t.unit("p1"), Vector2i(0, -14), int(HHBow.TUNE.e_range))
	c.eq(HHHex.distance(Vector2i(0, 6), centre), int(HHBow.TUNE.e_range), "clamped to e_range")
	c.ok(centre in (far_tg.get("hexes", []) as Array), "the burst is centred on the clamped hex")


func test_arrowstorm(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	var m := s.unit("m")
	var hp := float(m.hp)
	s.step({ "p1": { "move": Vector2i(0, 2) } })
	for i in 90:
		s.step()
	c.eq(p.hex, Vector2i(0, 2), "walked up")
	var leaped := false
	for e in s.step({ "p1": { "cast": { "skill": "r", "aim": p.hex } } }):
		if e.type == "leap":
			leaped = true
			c.eq(int(e.ticks), int(HHBow.TUNE.r_air_ticks), "60 ticks in the air")
	c.ok(leaped, "jumped")
	c.ok(bool(p.untargetable), "untargetable in the air")
	# a telegraph that lands while up misses
	s.telegraph("m", [p.hex], 5, { "dmg_pct": 10.0, "name": "slam" })
	var php := float(p.hp)
	var storm: Dictionary = {}
	var landed := false
	for i in int(HHBow.TUNE.r_air_ticks) + 1:
		for e in s.step():
			if e.type == "land":
				landed = true
			if e.type == "arrowstorm":
				storm = e
	c.near(float(p.hp), php, 0.1, "the slam missed the airborne archer")
	c.ok(landed, "landed")
	c.ok(not storm.is_empty(), "the storm fell")
	c.eq((storm.get("hexes", []) as Array).size(), 37, "radius-3 downfall")
	c.ok(not bool(p.untargetable), "targetable again")
	c.ok(float(m.hp) < hp, "the monster under the storm took damage")
	c.ok(s.charge.intensity(p.hex, "fire") >= 2, "two steps of element where it fell")
	c.ok(s.charge.intensity(Vector2i(0, 5), "fire") >= 2, "...out to the ring at 3")
	c.ok(int(p.cooldowns.r) > 0, "cooldown set")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "r", "aim": p.hex } } }):
		if e.type == "cast_refused":
			refused = true
	c.ok(refused, "refused on cooldown")
	# aimed: drifts to the aim hex within r_range
	var t := _sim()
	var q := t.unit("p1")
	t.step({ "p1": { "cast": { "skill": "r", "aim": Vector2i(3, 6) } } })
	var L: Dictionary = q.leap
	c.ok(not L.is_empty() and L.to == Vector2i(3, 6), "drifts to the aim hex")


func test_swap(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	s.step({ "p1": { "swap": true } })
	c.eq(p.element, "water", "swapped")
	s.step({ "p1": { "swap": true } })
	c.eq(p.element, "water", "second swap refused on cooldown")


## Lane U (H550): a bow without upgrades plays exactly as before: one
## telegraph per Arcing Shot, one step per Energized hex, no glaze.
func test_no_upgrades_means_the_plain_kit(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var p := s.unit("p1")
	c.eq((p.upgrades as Dictionary).size(), 0, "no upgrades by default")
	var ups := 0
	var tgs := 0
	var evs: Array = []
	evs.append_array(s.step({ "p1": { "cast": { "skill": "e", "aim": Vector2i(0, 1) } } }))
	evs.append_array(s.step({ "p1": { "cast": { "skill": "q", "aim": Vector2i(5, 6) } } }))
	for i in int(HHBow.TUNE.q_windup) + 1:
		evs.append_array(s.step())
	evs.append_array(s.step({ "p1": { "swap": true } }))
	for e in evs:
		if e.type == "upgrade" or e.type == "immune":
			ups += 1
		if e.type == "telegraph":
			tgs += 1
		if e.type == "energized_shot":
			c.eq(int(e.steps), int(HHBow.TUNE.q_steps), "plain Energized Shot: q_steps")
	c.eq(ups, 0, "no upgrade effects without upgrades")
	c.eq(tgs, 1, "one telegraph: the Arcing Shot alone")
	c.ok(not s.charge.is_glazed(Vector2i(5, 6)), "nothing glazed")
