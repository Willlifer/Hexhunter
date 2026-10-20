extends RefCounted
## Lane U: one test per upgrade in HHUpgrades.TABLE, plus determinism with
## upgrades slotted. A flat round arena, the player at (0, 6), a stub monster
## (size 2) at (0, -2): its footprint reaches row 0.


func _sim(weapon: String, upgrades: Dictionary, element: String = "fire", backup: String = "water") -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 6), element, backup, weapon, upgrades)
	s.add_monster("m", Vector2i(0, -2), 5000.0, 2)
	return s


func _run(s: HHSim, ticks: int, orders: Dictionary = {}) -> Array:
	var out: Array = []
	out.append_array(s.step(orders))
	for i in ticks:
		out.append_array(s.step())
	return out


func _events(evs: Array, type: String, key: String = "", val: Variant = null) -> Array:
	return evs.filter(func(e): return e.type == type and (key == "" or e.get(key) == val))


# ------------------------------------------------------------------ W (any)

func test_exchange_immune(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", { "w": ["exchange_immune"] })
	var p := s.unit("p1")
	var evs := _run(s, int(HHTune.value("exchange_windup")) - 1, { "p1": { "swap": true } })   # H57: W winds up briefly
	c.eq(p.element, "water", "swapped")
	c.eq(int(p.immune), int(HHTune.value("upgrade_exchange_immune_ticks")) - 1, "immunity ticks set at the swap (one tick elapsed)")
	c.ok(not _events(evs, "upgrade", "upgrade", "exchange_immune").is_empty(), "upgrade event")
	var hp := float(p.hp)
	s.hurt(p, 500.0, "test", 1.0)
	c.near(float(p.hp), hp, 0.01, "a hit while immune does nothing")
	c.eq(int(p.stagger), 0, "...no stagger either")
	c.ok(not _events(s.events, "immune").is_empty(), "immune event emitted")
	s.telegraph("m", [p.hex], 2, { "dmg_pct": 20.0, "name": "jet" })
	_run(s, 2)
	c.near(float(p.hp), hp, 0.01, "a telegraph landing inside the second is shrugged off")
	_run(s, int(HHTune.value("upgrade_exchange_immune_ticks")))
	c.eq(int(p.immune), 0, "immunity over after 1 s")
	s.hurt(p, 100.0, "test")
	c.near(float(p.hp), hp - 100.0, 0.01, "hits land again")
	# without the upgrade a swap grants nothing
	var t := _sim("lance", {})
	t.step({ "p1": { "swap": true } })
	c.eq(int(t.unit("p1").immune), 0, "plain Exchange: no immunity")


func test_exchange_burst(c: HHSelfTest.HHCheck) -> void:
	for weapon in ["lance", "daggers", "bow"]:
		var s := _sim(weapon, { "w": ["exchange_burst"] })
		var p := s.unit("p1")
		var evs := _run(s, int(HHTune.value("exchange_windup")) - 1, { "p1": { "swap": true } })   # H57: W winds up briefly
		var up := _events(evs, "upgrade", "upgrade", "exchange_burst")
		c.eq(up.size(), 1, "%s: the nova fired" % weapon)
		var r := int(HHTune.value("upgrade_exchange_burst_radius"))
		c.eq((up[0].hexes as Array).size(), s.arena.area(p.hex, r).size(), "%s: radius %d round the hunter" % [weapon, r])
		c.eq(str(up[0].element), "water", "%s: the NEW element" % weapon)
		c.ok(s.charge.intensity(p.hex, "water") >= 1, "%s: water under the hunter" % weapon)
		c.ok(s.charge.intensity(Vector2i(0, 6 + r), "water") >= 1, "%s: ...out to the ring at %d" % [weapon, r])
		c.eq(s.charge.intensity(Vector2i(0, 6 + r + 1), "water"), 0, "%s: not beyond" % weapon)
	var t := _sim("lance", {})
	t.step({ "p1": { "swap": true } })
	c.eq(t.charge.intensity(Vector2i(0, 6), "water"), 0, "plain Exchange paints nothing")


# ------------------------------------------------------------------ bow

func test_energized_double(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", { "q": ["energized_double"] })
	var evs := _run(s, int(HHBow.TUNE.q_windup) + 1, { "p1": { "cast": { "skill": "q", "aim": Vector2i(5, 6) } } })
	var shot := _events(evs, "energized_shot")
	c.eq(shot.size(), 1, "the shot flew")
	var hexes: Array = shot[0].hexes
	c.eq(hexes.size(), int(HHBow.TUNE.q_range), "full line on a miss")
	for h in hexes:
		c.eq(s.charge.intensity(h, "fire"), 2, "hex %s carries fire 2" % h)
	var t := _sim("bow", {})
	_run(t, int(HHBow.TUNE.q_windup) + 1, { "p1": { "cast": { "skill": "q", "aim": Vector2i(5, 6) } } })
	c.eq(t.charge.intensity(hexes[0], "fire"), 1, "plain shot: fire 1")


func test_arcing_twice(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", { "e": ["arcing_twice"] })
	var m := s.unit("m")
	var aim := Vector2i(0, 1)
	var evs := _run(s, 0, { "p1": { "cast": { "skill": "e", "aim": aim } } })
	var tgs := _events(evs, "telegraph")
	c.eq(tgs.size(), 7, "the burst plus six bomblets are posted at once")
	var bomblets := tgs.filter(func(e): return e.name == "bomblet")
	c.eq(bomblets.size(), 6, "six bomblets")
	var dist := int(HHBow.TUNE.up_e_echo_dist)
	for b in bomblets:
		c.eq(int(b.ticks), int(HHBow.TUNE.e_ticks) + int(HHBow.TUNE.up_e_echo_ticks), "a bomblet lands after the burst")
		c.eq((b.hexes as Array).size(), s.arena.area(aim, int(HHBow.TUNE.up_e_echo_radius)).size(), "a bomblet is a small area")
	var corners := HHBow.cluster_hexes(s, aim, dist)
	c.eq(corners.size(), 6, "six corners at distance %d" % dist)
	# the first burst lands, the monster in it takes the burst; the bomblets have not landed yet
	var hp := float(m.hp)
	var land1 := _run(s, int(HHBow.TUNE.e_ticks) - 1)
	c.eq(_events(land1, "telegraph_end", "name", "arcing shot").size(), 1, "the burst landed")
	c.eq(_events(land1, "telegraph_end", "name", "bomblet").size(), 0, "no bomblet yet")
	c.ok(float(m.hp) < hp, "the monster took the burst")
	var hp2 := float(m.hp)
	var land2 := _run(s, int(HHBow.TUNE.up_e_echo_ticks))
	c.eq(_events(land2, "telegraph_end", "name", "bomblet").size(), 6, "six bomblets landed later")
	c.ok(float(m.hp) < hp2, "the monster (its footprint touches the cluster) took bomblet damage")
	for h in corners:
		c.ok(s.charge.intensity(h, "fire") >= 1, "corner %s painted" % h)
	c.ok(s.charge.intensity(aim, "fire") >= 2, "the centre keeps the first burst's two steps")


func test_arrowstorm_glaze(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", { "r": ["arrowstorm_glaze"] })
	var p := s.unit("p1")
	var evs := _run(s, int(HHBow.TUNE.r_air_ticks) + 1, { "p1": { "cast": { "skill": "r", "aim": p.hex } } })
	c.eq(_events(evs, "arrowstorm").size(), 1, "the storm fell")
	c.eq(_events(evs, "upgrade", "upgrade", "arrowstorm_glaze").size(), 1, "then froze over")
	c.ok(s.charge.intensity(p.hex, "fire") >= 2, "fire 2 under the archer")
	c.ok(s.charge.is_glazed(p.hex), "...glazed in place")
	c.ok(s.charge.is_glazed(Vector2i(0, 9)), "...out to the ring at 3")
	var t := _sim("bow", {})
	_run(t, int(HHBow.TUNE.r_air_ticks) + 1, { "p1": { "cast": { "skill": "r", "aim": Vector2i(0, 6) } } })
	c.ok(not t.charge.is_glazed(Vector2i(0, 6)), "a plain storm is not glazed")


# ------------------------------------------------------------------ daggers

func test_daggerleap_homing(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("daggers", { "e": ["daggerleap_homing"] })
	var p := s.unit("p1")
	var m := s.unit("m")
	var to := Vector2i(0, 3)
	s.step({ "p1": { "cast": { "skill": "e", "aim": to } } })
	p.element = "thunder"                                 # swapped mid-air by force: the knives keep the CAST element
	var evs := _run(s, int(HHDaggers.TUNE.e_air_ticks))
	var up := _events(evs, "upgrade", "upgrade", "daggerleap_homing")
	c.eq(up.size(), 1, "knives released on landing")
	c.eq(str(up[0].target), "m", "homing on the monster within range")
	c.eq(str(up[0].element), "fire", "with the element you cast with")
	c.eq(_events(evs, "projectile", "phase", "launch").size(), int(HHDaggers.TUNE.up_e_homing_count), "three projectiles")
	c.eq(s.projectiles.size(), 3, "three in flight")
	var hp := float(m.hp)
	var flight := _run(s, int(HHDaggers.TUNE.up_e_homing_every) * (int(HHDaggers.TUNE.up_e_homing_max) + 1))
	var hits := _events(flight, "projectile", "phase", "hit")
	c.eq(hits.size(), 3, "all three knives found the monster")
	c.eq(s.projectiles.size(), 0, "none left")
	var starts := {}
	for h in hits:
		var trail: Array = h.trail
		c.ok(trail.size() >= 2, "a knife flew at least two hexes (%d)" % trail.size())
		c.ok(HHHex.distance(trail[-1], m.hex) <= int(m.size), "a knife ended on the footprint")
		starts[trail[0]] = true
		for x in trail:
			if HHHex.distance(x, m.hex) > int(m.size):
				c.ok(s.charge.intensity(x, "fire") >= 1, "trail hex %s painted fire" % x)
	c.eq(starts.size(), 3, "fanned: three different first hexes")
	c.near(float(m.hp), hp - 3.0 * float(HHDaggers.TUNE.up_e_homing_dmg), 1.0, "three knives of up_e_homing_dmg")
	c.eq(_events(flight, "strike", "cause", "hunting knife").size(), 3, "three strikes")
	# no monster in range: the knives fly straight on along the leap and drop
	var t := _sim("daggers", { "e": ["daggerleap_homing"] })
	t.unit("m").hex = Vector2i(0, -20)
	t.unit("m").pos = t.arena.stand(Vector2i(0, -20))
	t.step({ "p1": { "cast": { "skill": "e", "aim": Vector2i(0, 3) } } })      # leap inward: room for 10 hexes of flight
	var evs2 := _run(t, int(HHDaggers.TUNE.e_air_ticks))
	var up2 := _events(evs2, "upgrade", "upgrade", "daggerleap_homing")
	c.eq(up2.size(), 1, "knives still released")
	c.eq(str(up2[0].target), "", "no target in 6 hexes")
	var fl2 := _run(t, int(HHDaggers.TUNE.up_e_homing_every) * (int(HHDaggers.TUNE.up_e_homing_max) + 1))
	var ends := _events(fl2, "projectile", "phase", "end")
	c.eq(ends.size(), 3, "they ran out and dropped")
	for e in ends:
		var trail: Array = e.trail
		c.eq(trail.size(), int(HHDaggers.TUNE.up_e_homing_max), "a straight knife flies up_e_homing_max hexes")
		for x in trail:
			c.ok(t.charge.intensity(x, "fire") >= 1, "straight trail hex %s painted" % x)
		c.ok(HHHex.distance(trail[-1], Vector2i(0, 3)) == int(HHDaggers.TUNE.up_e_homing_max), "...in a straight line from the landing")
	var u := _sim("daggers", {})
	_run(u, int(HHDaggers.TUNE.e_air_ticks), { "p1": { "cast": { "skill": "e", "aim": to } } })
	c.eq(u.projectiles.size(), 0, "a plain Daggerleap launches nothing")


func test_flourish_twin(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("daggers", { "q": ["flourish_twin"] })
	var p := s.unit("p1")
	var evs := _run(s, int(HHDaggers.TUNE.q_windup) + 1, { "p1": { "cast": { "skill": "q", "aim": p.hex } } })
	c.eq(_events(evs, "flourish").size(), 1, "flourished")
	var up := _events(evs, "upgrade", "upgrade", "flourish_twin")
	c.eq(up.size(), 1, "the twin ring fired")
	var r := int(HHDaggers.TUNE.q_radius)
	c.eq((up[0].hexes as Array).size(), s.arena.ring(p.hex, r + 1).size(), "the ring just beyond the Flourish")
	c.eq(str(up[0].element), "water", "the backup element")
	c.ok(s.charge.intensity(Vector2i(0, 6 + r), "fire") >= 1, "fire at the Flourish's edge")
	c.ok(s.charge.intensity(Vector2i(0, 6 + r + 1), "water") >= 1, "water on the ring beyond")
	c.eq(s.charge.intensity(Vector2i(0, 6 + r + 1), "fire"), 0, "...and no fire there")


func test_knifedance_long(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("daggers", { "r": ["knifedance_long"] })
	var p := s.unit("p1")
	var start := _events(s.step({ "p1": { "cast": { "skill": "r", "aim": p.hex } } }), "knifedance", "phase", "start")
	c.eq(start.size(), 1, "started")
	c.eq(int(start[0].ticks), int(HHDaggers.TUNE.up_r_long_ticks), "9 s of dancing")
	var evs := _run(s, int(HHDaggers.TUNE.up_r_long_ticks) + 2)
	c.eq(_events(evs, "knifedance", "phase", "pulse").size(), 9, "nine pulses")
	c.eq(_events(evs, "knifedance", "phase", "end").size(), 1, "then it ended")
	c.ok(not s.hooks.has("p1"), "unhooked")


# ------------------------------------------------------------------ lance

func test_pierce_wide(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", { "q": ["pierce_wide"] })
	var p := s.unit("p1")
	var m := s.unit("m")
	var evs := _run(s, int(HHTune.value("lance_q_windup")) + 1, { "p1": { "cast": { "skill": "q", "aim": m.hex } } })
	var pierce := _events(evs, "pierce")
	c.eq(pierce.size(), 1, "pierced")
	var hexes: Array = pierce[0].hexes
	var len := int(HHTune.value("lance_q_len"))
	c.eq(hexes.size(), len * 3, "triple width: %d hexes" % (len * 3))
	var line := HHLance.pierce_line(s, p, m.hex, len)
	for h in line:
		c.ok(h in hexes, "line hex %s kept" % h)
		var sides := 0
		for n in HHHex.neighbors(h):
			if n in hexes and not n in line:
				sides += 1
		c.ok(sides >= 2, "line hex %s has hexes on both sides (%d)" % [h, sides])
	for h in hexes:
		c.ok(s.charge.intensity(h, "fire") >= 1, "wide hex %s painted" % h)
	c.ok(not p.hex in hexes, "the hunter's own hex is not in it")
	var t := _sim("lance", {})
	var plain := _events(_run(t, int(HHTune.value("lance_q_windup")) + 1, { "p1": { "cast": { "skill": "q", "aim": m.hex } } }), "pierce")
	c.eq((plain[0].hexes as Array).size(), len, "plain Pierce is one hex wide")


func test_guard_stagger(c: HHSelfTest.HHCheck) -> void:
	var plain_st := _guard_block(c, _sim("lance", {}))
	var up_st := _guard_block(c, _sim("lance", { "e": ["guard_stagger"] }))
	c.ok(up_st > plain_st, "the counter staggers harder with the upgrade (%d > %d)" % [up_st, plain_st])
	var want := int(roundf(HHTune.value("stagger_max_ticks") * float(HHLance.TUNE.up_e_stagger)) * HHTune.value("monster_stagger_mult"))
	c.eq(up_st, want, "monster stagger of up_e_stagger x monster_stagger_mult")


func _guard_block(c: HHSelfTest.HHCheck, s: HHSim) -> int:
	var p := s.unit("p1")
	var m := s.unit("m")
	s.step({ "p1": { "move": Vector2i(0, 2) } })
	_run(s, 120)
	s.step({ "p1": { "cast": { "skill": "e", "aim": p.hex } } })
	s.telegraph("m", [p.hex], 2, { "dmg_pct": 20.0, "element": "water", "name": "jet", "stagger": 1.0 })
	var evs := _run(s, 2)
	c.eq(_events(evs, "guard_block").size(), 1, "the hit was blocked")
	var st := _events(evs, "stagger", "id", "m")
	return int(st[0].ticks) if not st.is_empty() else 0


func test_eruption_twice(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", { "r": ["eruption_twice"] })
	var m := s.unit("m")
	var to := Vector2i(0, 1)                               # lands next to the footprint
	var evs := _run(s, int(HHTune.value("lance_r_air_ticks")), { "p1": { "cast": { "skill": "r", "aim": to } } })
	c.eq(_events(evs, "eruption").size(), 1, "erupted")
	var up := _events(evs, "upgrade", "upgrade", "eruption_twice")
	c.eq(up.size(), 1, "an aftershock was posted")
	var tg := _events(evs, "telegraph", "name", "aftershock")
	c.eq(tg.size(), 1, "...as a telegraph the monster can read")
	c.eq((tg[0].hexes as Array).size(), 19, "on the same radius-2 ground")
	c.eq(int(tg[0].ticks), int(HHLance.TUNE.up_r_echo_ticks), "landing up_r_echo_ticks later")
	var hp := float(m.hp)
	var later := _run(s, int(HHLance.TUNE.up_r_echo_ticks))
	c.eq(_events(later, "telegraph_end", "name", "aftershock").size(), 1, "the aftershock landed")
	c.near(float(m.hp), hp - float(m.max_hp) * float(HHLance.TUNE.up_r_echo_pct) / 100.0, 1.0, "up_r_echo_pct of max HP")
	c.eq(s.charge.intensity(to, "fire"), 3, "fire stacked to 3 under the second eruption")
	var t := _sim("lance", {})
	var plain := _run(t, int(HHTune.value("lance_r_air_ticks")), { "p1": { "cast": { "skill": "r", "aim": to } } })
	c.eq(_events(plain, "telegraph").size(), 0, "a plain Eruption posts nothing")


# ------------------------------------------------------------------ potion (any)

func test_potion_cleanse(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", { "t": ["potion_cleanse"] })
	var p := s.unit("p1")
	for st in ["burn", "poison", "slow"]:
		s.apply_status(p, st, 600)
	c.eq((p.statuses as Dictionary).size(), 3, "three statuses on")
	var evs := _run(s, int(HHTune.value("potion_windup")) + 1, { "p1": { "potion": true } })
	c.eq(_events(evs, "potion").size(), 1, "drank")
	var up := _events(evs, "upgrade", "upgrade", "potion_cleanse")
	c.eq(up.size(), 1, "cleansed")
	c.eq((up[0].cleared as Array).size(), 3, "three cleared")
	c.eq((p.statuses as Dictionary).size(), 0, "no statuses left")
	c.ok(not (p.heal_zone as Dictionary).is_empty(), "the heal zone still runs (H56)")
	var t := _sim("lance", {})
	var q := t.unit("p1")
	t.apply_status(q, "burn", 600)
	_run(t, int(HHTune.value("potion_windup")) + 1, { "p1": { "potion": true } })
	c.ok((q.statuses as Dictionary).has("burn"), "a plain potion leaves the burn")


# ------------------------------------------------------------------ determinism

func test_determinism_with_upgrades(c: HHSelfTest.HHCheck) -> void:
	var ups := { "w": ["exchange_burst", "exchange_immune"], "e": ["daggerleap_homing"], "q": ["flourish_twin"], "r": ["knifedance_long"] }
	var orders := { 1: { "p1": { "cast": { "skill": "e", "aim": Vector2i(0, 3) } } }, 20: { "p1": { "swap": true } },
		40: { "p1": { "cast": { "skill": "q", "aim": Vector2i(0, 3) } } }, 60: { "p1": { "cast": { "skill": "r", "aim": Vector2i(0, 3) } } } }
	var a := _sim("daggers", ups)
	var b := _sim("daggers", ups)
	var d := _sim("daggers", {})
	var mid_a := 0
	var mid_b := 0
	for i in 150:
		a.step(orders.get(i, {}))
		b.step(orders.get(i, {}))
		d.step(orders.get(i, {}))
		if i == 25:                                       # knives in flight, immunity ticking
			mid_a = a.state_hash()
			mid_b = b.state_hash()
	c.eq(mid_a, mid_b, "same upgrades + orders = same hash mid-flight")
	c.eq(a.state_hash(), b.state_hash(), "same upgrades + orders = same hash at the end")
	c.ok(a.state_hash() != d.state_hash(), "without the upgrades the fight differs")
