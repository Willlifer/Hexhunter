extends RefCounted
## Lane W (H56, H950-): charged Q on every weapon (three levels, strengths,
## damage, upgrades), the lance's brace and root, the slowed draw, auto
## release, cooldown on release, the dash, and snapshots carrying it all.
## A flat round arena; the stub monster (size 2) at (0, -2) covers rows -4..0.

const MHP := 50000.0


func _sim(weapon: String, at: Vector2i, upgrades: Dictionary = {}, monster: bool = true) -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", at, "fire", "water", weapon, upgrades)
	if monster:
		s.add_monster("m", Vector2i(0, -2), MHP, 2)
	return s


## Hold Q for `ticks` ticks (the charge order's tick counts as the first),
## release, and run until the wind-up lands. Every event on the way.
func _charged(s: HHSim, ticks: int, aim: Vector2i, release: bool = true) -> Array:
	var out: Array = []
	out.append_array(s.step({ "p1": { "charge": { "skill": "q", "aim": aim } } }))
	for i in ticks - 1:
		out.append_array(s.step())
	if release:
		out.append_array(s.step({ "p1": { "release": { "skill": "q", "aim": aim } } }))
	for i in 20:
		out.append_array(s.step())
	return out


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e): return e.type == type)


func _l2() -> int:
	return int(roundf(HHTune.value("charge_l2_s") * 30.0))


func _l3() -> int:
	return int(roundf(HHTune.value("charge_l3_s") * 30.0))


## Every hex of `shape` carries `el` at exactly its strength.
func _painted(c: HHSelfTest.HHCheck, s: HHSim, shape: Dictionary, el: String, what: String) -> void:
	var bad := 0
	for h in shape:
		if s.charge.intensity(h, el) != int(shape[h]):
			bad += 1
	c.eq(bad, 0, "%s: every hex painted at its strength (%d hexes)" % [what, shape.size()])


func _counts(shape: Dictionary) -> Dictionary:
	var out := {}
	for h in shape:
		out[int(shape[h])] = int(out.get(int(shape[h]), 0)) + 1
	return out


# ------------------------------------------------------------------ levels and flow

func test_levels_by_time(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHSim.charge_level(1), 1, "a tap is level 1")
	c.eq(HHSim.charge_level(_l2() - 1), 1, "just short of charge_l2_s: still 1")
	c.eq(HHSim.charge_level(_l2()), 2, "charge_l2_s: level 2")
	c.eq(HHSim.charge_level(_l3()), 3, "charge_l3_s: level 3")


func test_charge_flow_cooldown_on_release(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(0, 6))
	var p := s.unit("p1")
	var ev := s.step({ "p1": { "charge": { "skill": "q", "aim": Vector2i(5, 6) } } })
	c.eq(_of(ev, "charge_start").size(), 1, "charge_start event")
	c.ok(s.charging(p), "charging")
	c.eq(int(p.cooldowns.q), 0, "no cooldown while holding")
	var lv: Array = []
	for i in _l2() + 5:
		lv.append_array(_of(s.step(), "charge_level"))
	c.eq(lv.size(), 1, "one charge_level event so far")
	c.eq(int(lv[0].level), 2, "...level 2")
	var refused := false
	for e in s.step({ "p1": { "cast": { "skill": "e", "aim": Vector2i(3, 3) } } }):
		if e.type == "cast" and e.skill == "e":
			refused = false
	c.ok(int(p.cooldowns.e) == 0, "other casts are refused while charging")
	var rel := s.step({ "p1": { "release": { "skill": "q", "aim": Vector2i(5, 6) } } })
	var r := _of(rel, "charge_release")
	c.eq(r.size(), 1, "charge_release event")
	c.eq(int(r[0].level), 2, "released at level 2")
	c.ok(not s.charging(p), "no longer charging")
	c.eq(str(p.windup.get("kind", "")), "energized", "a wind-up still plays after release (commit)")
	c.eq(int(p.cooldowns.q), int(HHBow.TUNE.q_cd) - 1, "cooldown starts on release (one tick run)")
	c.ok(_of(rel, "cast").size() == 1 and int(_of(rel, "cast")[0].level) == 2, "the cast event carries the level")


func test_auto_release_at_full(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("daggers", Vector2i(0, 6))
	var p := s.unit("p1")
	s.step({ "p1": { "charge": { "skill": "q", "aim": p.hex } } })
	var rel: Array = []
	var lv: Array = []
	for i in _l3() + 2:
		var ev := s.step()
		rel.append_array(_of(ev, "charge_release"))
		lv.append_array(_of(ev, "charge_level"))
	c.eq(rel.size(), 1, "released on its own")
	c.eq(int(rel[0].level), 3, "...at level 3")
	c.eq(int(rel[0].tick), 1 + _l3() - 1, "...on the tick it reached charge_l3_s (%d)" % int(rel[0].tick))
	c.eq(lv.map(func(e): return int(e.level)), [2, 3], "charge_level 2 then 3")
	c.ok(not s.charging(p), "the charge is spent")
	c.ok(int(p.cooldowns.q) > 0, "on cooldown")


func test_stagger_cancels(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(0, 6))
	var p := s.unit("p1")
	_charged(s, 20, Vector2i(5, 6), false)
	c.ok(s.charging(p), "charging")
	s.hurt(p, 100.0, "test", 0.5)
	c.ok(not s.charging(p), "a stagger cancels the charge")
	c.ok(not _of(s.events, "charge_cancel").is_empty() and str(_of(s.events, "charge_cancel")[0].why) == "stagger", "charge_cancel { why: stagger }")
	c.eq(int(p.cooldowns.q), 0, "a stagger costs no cooldown (the hit is the cost)")


# ------------------------------------------------------------------ lance

func test_lance_levels(c: HHSelfTest.HHCheck) -> void:
	var aim := Vector2i(9, 2)                            # due east: a clean miss
	var want := { 1: { 1: int(HHTune.value("lance_q_len")) }, 2: { 2: int(HHLance.TUNE.q_l2_len) },
		3: { 3: int(HHLance.TUNE.q_l3_len), 2: 2 * int(HHLance.TUNE.q_l3_len) } }
	for level in [1, 2, 3]:
		var s := _sim("lance", Vector2i(0, 2))
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var ev := _charged(s, ticks, aim, level < 3)
		var pierce := _of(ev, "pierce")
		c.eq(pierce.size(), 1, "L%d: pierced" % level)
		if pierce.is_empty():
			continue
		c.eq(int(pierce[0].level), level, "L%d: the event carries the level" % level)
		var shape: Dictionary = pierce[0].shape
		c.eq(_counts(shape), want[level], "L%d: hexes per strength %s" % [level, want[level]])
		_painted(c, s, shape, "fire", "L%d" % level)
		c.ok(not Vector2i(0, 2) in shape, "L%d: not on the hunter's own hex" % level)


func test_lance_damage_by_level(c: HHSelfTest.HHCheck) -> void:
	for level in [1, 2, 3]:
		var s := _sim("lance", Vector2i(0, 2))
		var m := s.unit("m")
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var ev := _charged(s, ticks, m.hex, level < 3)
		var hits := _of(ev, "strike").filter(func(e): return e.cause == "pierce")
		c.eq(hits.size(), 1, "L%d: one blow on the monster" % level)
		if hits.is_empty():
			continue
		c.near(float(hits[0].amount), roundf(HHTune.value("lance_q_dmg") * HHLance.q_mult(level)), 0.5, "L%d: lance_q_dmg x %.1f" % [level, HHLance.q_mult(level)])
	c.ok(HHLance.q_stagger(3) > HHLance.q_stagger(2) and HHLance.q_stagger(2) > HHLance.q_stagger(1), "stagger grows with the level")


func test_lance_roots_and_braces(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(0, 6))
	var p := s.unit("p1")
	_charged(s, 10, Vector2i(0, 0), false)
	var at: Vector3 = p.pos
	s.step({ "p1": { "move": Vector2i(6, 6), "move_pos": s.arena.stand(Vector2i(6, 6)) } })
	for i in 20:
		s.step()
	c.ok((p.pos as Vector3).distance_to(at) < 0.01, "a move order does nothing while the lance charges")
	c.ok(s.charging(p), "...and does not cancel it")
	var hp := float(p.hp)
	s.hurt(p, 1000.0, "test")
	c.near(hp - float(p.hp), 1000.0 * (1.0 - HHTune.value("lance_charge_guard")), 0.5, "braced: damage cut by lance_charge_guard")
	var t := _sim("lance", Vector2i(0, 6))
	var q := t.unit("p1")
	var hq := float(q.hp)
	t.hurt(q, 1000.0, "test")
	c.near(hq - float(q.hp), 1000.0, 0.5, "not charging: the full hit")


func test_broad_pierce_every_level(c: HHSelfTest.HHCheck) -> void:
	var aim := Vector2i(9, 2)
	var L1 := int(HHTune.value("lance_q_len"))
	var L3 := int(HHLance.TUNE.q_l3_len)
	var want := { 1: { 1: 3 * L1 }, 2: { 2: 3 * int(HHLance.TUNE.q_l2_len) }, 3: { 3: L3, 2: 2 * L3, 1: 2 * L3 } }
	for level in [1, 2, 3]:
		var s := _sim("lance", Vector2i(0, 2), { "q": ["pierce_wide"] })
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var pierce := _of(_charged(s, ticks, aim, level < 3), "pierce")
		if pierce.is_empty():
			c.ok(false, "L%d: pierced" % level)
			continue
		c.eq(_counts(pierce[0].shape), want[level], "Broad Pierce L%d: %s (L3 is 1-2-3-2-1)" % [level, want[level]])
		_painted(c, s, pierce[0].shape, "fire", "Broad Pierce L%d" % level)


# ------------------------------------------------------------------ bow

func test_bow_levels(c: HHSelfTest.HHCheck) -> void:
	var aim := Vector2i(5, 6)
	var R := int(HHBow.TUNE.q_range)
	for level in [1, 2, 3]:
		var s := _sim("bow", Vector2i(0, 6))
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var shot := _of(_charged(s, ticks, aim, level < 3), "energized_shot")
		c.eq(shot.size(), 1, "L%d: loosed" % level)
		if shot.is_empty():
			continue
		var shape: Dictionary = shot[0].shape
		var k := _counts(shape)
		match level:
			1: c.eq(k, { 1: R }, "L1: the 1-wide line at strength 1")
			2: c.eq(k, { 2: R }, "L2: the 1-wide line at strength 2")
			3:
				c.eq(int(k.get(3, 0)), R, "L3: the centre line at strength 3")
				c.ok(int(k.get(2, 0)) >= 2 * (R - 1) and int(k.get(2, 0)) <= 2 * R + 2, "L3: side lines at strength 2 (%d hexes)" % int(k.get(2, 0)))
				c.ok(k.size() == 2, "L3: only strengths 3 and 2")
		_painted(c, s, shape, "fire", "bow L%d" % level)


func test_bow_damage_and_pierce(c: HHSelfTest.HHCheck) -> void:
	for level in [1, 2, 3]:
		var s := _sim("bow", Vector2i(0, 6))
		var m := s.unit("m")
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var ev := _charged(s, ticks, m.hex, level < 3)
		var hits := _of(ev, "strike").filter(func(e): return e.cause == "energized shot")
		c.eq(hits.size(), 1, "L%d: one hit" % level)
		if not hits.is_empty():
			c.near(float(hits[0].amount), roundf(float(HHBow.TUNE.q_dmg) * HHBow.q_mult(level)), 0.5, "L%d: q_dmg x %.1f" % [level, HHBow.q_mult(level)])
		var shot: Array = _of(ev, "energized_shot")
		if level < 3:
			c.ok((shot[0].hexes as Array).size() < int(HHBow.TUNE.q_range), "L%d: the arrow stops in the monster" % level)
		else:
			c.eq(_counts(shot[0].shape).get(3, 0), int(HHBow.TUNE.q_range), "L3: the band flies the whole range through it")


func test_overcharged_every_level(c: HHSelfTest.HHCheck) -> void:
	var aim := Vector2i(5, 6)
	var want := { 1: [2], 2: [3], 3: [3] }
	for level in [1, 2, 3]:
		var s := _sim("bow", Vector2i(0, 6), { "q": ["energized_double"] })
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var shot := _of(_charged(s, ticks, aim, level < 3), "energized_shot")
		var ks: Array = _counts(shot[0].shape).keys()
		ks.sort()
		c.eq(ks[-1], want[level][0], "Overcharged L%d: the line at %d (+1, capped at 3)" % [level, want[level][0]])
		_painted(c, s, shot[0].shape, "fire", "Overcharged L%d" % level)


# ------------------------------------------------------------------ daggers

func test_daggers_levels(c: HHSelfTest.HHCheck) -> void:
	var want := { 1: { 1: 7 }, 2: { 1: 19 }, 3: { 3: 7, 2: 12 } }
	for level in [1, 2, 3]:
		var s := _sim("daggers", Vector2i(0, 8), {}, false)
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var fl := _of(_charged(s, ticks, Vector2i(0, 8), level < 3), "flourish")
		c.eq(fl.size(), 1, "L%d: flourished" % level)
		if fl.is_empty():
			continue
		c.eq(_counts(fl[0].shape), want[level], "L%d: %s" % [level, want[level]])
		_painted(c, s, fl[0].shape, "fire", "daggers L%d" % level)


func test_daggers_damage_by_level(c: HHSelfTest.HHCheck) -> void:
	for level in [1, 2, 3]:
		var s := _sim("daggers", Vector2i(0, 1))
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var hits := _of(_charged(s, ticks, Vector2i(0, 1), level < 3), "strike").filter(func(e): return e.cause == "flourish")
		c.eq(hits.size(), 1, "L%d: one blow" % level)
		if not hits.is_empty():
			c.near(float(hits[0].amount), roundf(float(HHDaggers.TUNE.q_dmg) * HHDaggers.q_mult(level)), 0.5, "L%d: q_dmg x %.1f" % [level, HHDaggers.q_mult(level)])


func test_twin_flourish_every_level(c: HHSelfTest.HHCheck) -> void:
	for level in [1, 2, 3]:
		var s := _sim("daggers", Vector2i(0, 8), { "q": ["flourish_twin"] }, false)
		var ticks := 1 if level == 1 else (_l2() if level == 2 else _l3())
		var ev := _charged(s, ticks, Vector2i(0, 8), level < 3)
		var up := ev.filter(func(e): return e.type == "upgrade" and e.upgrade == "flourish_twin")
		var r := HHDaggers.q_radius(level)
		c.eq((up[0].hexes as Array).size(), s.arena.ring(Vector2i(0, 8), r + 1).size(), "Twin L%d: the backup ring just beyond radius %d" % [level, r])
		c.ok(s.charge.intensity(Vector2i(0, 8 + r + 1), "water") >= 1, "Twin L%d: water on it" % level)


# ------------------------------------------------------------------ slowed while charging

func test_bow_and_daggers_slowed_while_charging(c: HHSelfTest.HHCheck) -> void:
	for weapon in ["bow", "daggers"]:
		var dists: Array = []
		for charge in [false, true]:
			var s := _sim(weapon, Vector2i(-8, 8), {}, false)
			var p := s.unit("p1")
			if charge:
				s.step({ "p1": { "charge": { "skill": "q", "aim": Vector2i(8, 8) } } })
			var from: Vector3 = p.pos
			s.step({ "p1": { "move": Vector2i(8, 8), "move_pos": s.arena.stand(Vector2i(8, 8)) } })
			for i in 29:
				s.step()
			dists.append((p.pos as Vector3).distance_to(from))
		c.near(float(dists[0]), HHTune.value("run_mps"), 0.3, "%s: a second of running covers run_mps (%.2f)" % [weapon, float(dists[0])])
		c.near(float(dists[1]) / float(dists[0]), HHTune.value("charge_move_mult"), 0.05, "%s: charging moves at charge_move_mult" % weapon)


# ------------------------------------------------------------------ dash

func test_dash_charges_recharge_recovery(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(-6, 8), {}, false)
	var p := s.unit("p1")
	c.eq(int(p.dash_charges), int(HHTune.value("dash_charges")), "starts with dash_charges")
	var from: Vector3 = p.pos
	var ev := s.step({ "p1": { "dash": from + Vector3(10, 0, 0) } })
	c.eq(_of(ev, "dash").size(), 1, "dashed")
	c.eq(int(p.dash_charges), 1, "one charge spent")
	c.ok(s.held(p), "committed during the dash")
	for i in int(HHTune.value("dash_ticks")):
		s.step()
	c.near((p.pos as Vector3).distance_to(from), HHTune.value("dash_m"), 0.05, "covered dash_m")
	c.ok(absf((p.pos as Vector3).z - from.z) < 0.05, "...toward the point")
	var r := s.step({ "p1": { "dash": (p.pos as Vector3) + Vector3(10, 0, 0) } })
	c.ok(_of(r, "cast_refused").any(func(e): return e.skill == "dash" and e.why == "recovering"), "no instant chain: recovering")
	for i in int(HHTune.value("dash_recover_ticks")):
		s.step()
	c.eq(_of(s.step({ "p1": { "dash": (p.pos as Vector3) + Vector3(0, 0, -10) } }), "dash").size(), 1, "second dash after the recovery")
	c.eq(int(p.dash_charges), 0, "both spent")
	for i in int(HHTune.value("dash_ticks")) + int(HHTune.value("dash_recover_ticks")):
		s.step()
	c.ok(_of(s.step({ "p1": { "dash": (p.pos as Vector3) + Vector3(10, 0, 0) } }), "cast_refused").any(func(e): return e.why == "none left"), "a third is refused: none left")
	var full := int(roundf(HHTune.value("dash_recharge_s") * 30.0))
	var ready: Array = []
	for i in full * 2 + 5:
		ready.append_array(_of(s.step(), "dash_ready"))
	c.eq(ready.size(), 2, "both came back")
	c.ok(ready.size() == 2 and int(ready[1].tick) - int(ready[0].tick) == full, "one at a time, dash_recharge_s apart")
	c.eq(int(p.dash_charges), 2, "full again")


func test_dash_dodges_and_cancels_a_charge(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(-6, 8))
	var p := s.unit("p1")
	_charged(s, 30, Vector2i(0, 0), false)
	c.ok(s.charging(p), "charging the lance")
	var ev := s.step({ "p1": { "dash": (p.pos as Vector3) + Vector3(-5, 0, 0) } })
	c.eq(_of(ev, "dash").size(), 1, "a dash goes through the charge")
	c.ok(not s.charging(p), "...cancelling it")
	c.ok(_of(ev, "charge_cancel").any(func(e): return e.why == "dash"), "charge_cancel { why: dash }")
	c.eq(int(p.cooldowns.q), int(HHTune.value("lance_q_cd")) - 1, "a dashed-out charge spends the Pierce (cooldown)")
	var hp := float(p.hp)
	s.hurt(p, 500.0, "test", 1.0)
	c.near(float(p.hp), hp, 0.01, "the dash's first ticks dodge a hit")
	c.ok(not _of(s.events, "dodge").is_empty(), "dodge event")
	s.telegraph("m", [p.hex], 1, { "dmg_pct": 20.0, "name": "jet", "status": "slow", "status_ticks": 60 })
	s.step()
	c.near(float(p.hp), hp, 0.01, "a telegraph landing in the window is dodged too")
	c.ok(not (p.statuses as Dictionary).has("slow"), "...status included")
	for i in 10:
		s.step()
	s.hurt(p, 100.0, "test")
	c.near(float(p.hp), hp - 100.0, 0.01, "after the window hits land")


func test_dash_stops_at_walls_and_follows_movement(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("daggers", Vector2i(0, 2))
	var p := s.unit("p1")
	var from: Vector3 = p.pos
	s.step({ "p1": { "dash": from + Vector3(0, 0, -10) } })            # straight at the monster's body
	for i in int(HHTune.value("dash_ticks")):
		s.step()
	c.ok(not p.hex in s.footprint(s.unit("m")), "never into the monster's footprint")
	c.ok((p.pos as Vector3).distance_to(from) < HHTune.value("dash_m") - 0.5, "stopped short of it")
	var t := _sim("bow", Vector2i(-6, 8), {}, false)
	var q := t.unit("p1")
	t.step({ "p1": { "move": Vector2i(-6, 0), "move_pos": t.arena.stand(Vector2i(-6, 0)) } })
	t.step()
	var at: Vector3 = q.pos
	t.step({ "p1": { "dash": at } })                                    # the cursor on the hunter: the way it was going
	for i in int(HHTune.value("dash_ticks")):
		t.step()
	c.ok((q.pos as Vector3).z < at.z - 2.5, "a dash with the cursor on the hunter goes the way it was moving")


# ------------------------------------------------------------------ snapshots

func test_snapshot_round_trip_charge_dash_zone(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var b := HHArena.round_flat(1, 25.0, 0.0)
	var host := HHSim.new(a, 1)
	var mirror := HHSim.new(b, 1)
	for s in [host, mirror]:
		s.add_player("p1", Vector2i(0, 6), "fire", "water", "bow")
		s.add_player("p2", Vector2i(4, 6), "ice", "water", "lance")
		s.add_monster("m", Vector2i(0, -2), MHP, 2)
	host.step({ "p1": { "charge": { "skill": "q", "aim": Vector2i(0, 0) }, "potion": true }, "p2": { "dash": host.unit("p2").pos + Vector3(3, 0, 0) } })
	host.step({ "p1": { "potion": { "aim": Vector2i(2, 6) } } })
	for i in 3:
		host.step()
	var snap: Dictionary = HHSnapshot.decode(HHSnapshot.encode(HHSnapshot.capture(host)))
	HHSnapshot.apply(mirror, snap)
	c.ok(not (mirror.unit("p1").charging as Dictionary).is_empty(), "charging travels")
	c.ok(not (mirror.unit("p2").dash as Dictionary).is_empty(), "the dash travels")
	c.ok(mirror.unit("p2").dash.to is Vector3, "...with its Vector3 ends")
	c.eq(mirror.state_hash(), host.state_hash(), "hash agrees mid-charge, mid-dash")
	var prev := HHSnapshot.capture(host)
	var zone_seen := false
	var bad := 0
	host.step({ "p1": { "release": { "skill": "q", "aim": Vector2i(0, 0) } } })
	for i in 120:
		if i == 10:
			host.step({ "p2": { "potion": { "aim": Vector2i(4, 4) } } })
		else:
			host.step()
		var cur := HHSnapshot.capture(host)
		if not HHSnapshot.apply_delta(mirror, HHSnapshot.decode(HHSnapshot.encode(HHSnapshot.delta(prev, cur)))) or mirror.state_hash() != host.state_hash():
			bad += 1
		zone_seen = zone_seen or not (mirror.unit("p2").heal_zone as Dictionary).is_empty()
		prev = cur
	c.eq(bad, 0, "every delta through the release, the zone and the recharge agrees")
	c.ok(zone_seen, "the heal zone travels in deltas")
	c.ok(HHSnapshot.same(HHSnapshot.capture(mirror), HHSnapshot.capture(host)), "same state at the end")


func test_orders_survive_the_wire(c: HHSelfTest.HHCheck) -> void:
	var o := HHReplicator.clean_order({ "charge": { "skill": "q", "aim": Vector2i(1, 2) }, "charge_aim": Vector2i(3, 4),
		"release": { "skill": "q", "aim": Vector2i(5, 6) }, "dash": Vector3(1, 0, 2), "potion": { "aim": Vector2i(7, 8) } }, false)
	c.eq(o.get("charge"), { "skill": "q", "aim": Vector2i(1, 2) }, "charge kept")
	c.eq(o.get("charge_aim"), Vector2i(3, 4), "charge_aim kept")
	c.eq(o.get("release"), { "skill": "q", "aim": Vector2i(5, 6) }, "release kept")
	c.eq(o.get("dash"), Vector3(1, 0, 2), "dash kept")
	c.eq(o.get("potion"), { "aim": Vector2i(7, 8) }, "a potion throw kept")
	var bad := HHReplicator.clean_order({ "charge": { "skill": "r", "aim": Vector2i(1, 2) }, "dash": "x", "potion": { "aim": 3 } }, false)
	c.ok(bad.is_empty(), "malformed ones dropped (%s)" % [bad])
