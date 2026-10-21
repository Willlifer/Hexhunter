extends RefCounted
## Lane M (H400-H389), spec 10: "one suite for the Purge trigger and its
## containment". The dot_pain_meter (7.3) fires a Purge only past its line,
## only on NORMAL+, and the Purge's detonations / splashes set nothing else off
## in the same action. The monster here is a stub brain (an aggravated
## monster that never moves or attacks) so the ground under it stays put; the
## stub's `id` picks the real monster's purge profile.

class Stub extends RefCounted:
	var id := ""
	var state := "aggravated"
	var mode := "idle"
	var busy_until := 0
	var next_attack_at := 0
	var anim := ""
	var ticks := 0

	func _init(p_id: String) -> void:
		id = p_id

	func tick(_sim: HHSim, _u: Dictionary) -> void:
		ticks += 1


const ISOLATE := { "tier_avoid_frac": 99.0, "tier_sp_first_s": 9999.0, "tier_pulse_every_s": 9999.0 }


func _isolate(on: bool) -> void:
	for k in ISOLATE:
		HHTune.set_value(k, ISOLATE[k] if on else HHTune.default_of(k))


func _sim(kind: String, tier: String) -> Array:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1, tier)
	s.add_player("p1", Vector2i(0, 9))
	var m := s.add_monster(kind, Vector2i(0, -2), 20000.0, 2, ["floor"])
	var brain := Stub.new(kind)
	s.brains[kind] = brain
	return [s, brain, m]


## Run until `pred` or `limit` ticks; returns the events of every tick.
func _until(s: HHSim, limit: int, pred: Callable) -> Array:
	var all: Array = []
	for i in limit:
		all.append(s.step({}))
		if pred.call():
			break
	return all


func _count(ev: Array, type: String) -> int:
	return ev.filter(func(e): return str(e.type) == type).size()


func _tier_events(ev: Array, what: String) -> Array:
	return ev.filter(func(e): return str(e.type) == "tier" and str(e.what) == what)


func test_meter_triggers_purge_only_past_the_line(c: HHSelfTest.HHCheck) -> void:
	_isolate(true)
	# fire 3 under the monster: 3.6 %/s of a third of its HP = 1.2 %/s of max HP -> past 3 % in ~3 s
	var r := _sim("spirewalker", "normal")
	var s: HHSim = r[0]
	var m: Dictionary = r[2]
	s.paint([m.hex], "fire", "p1", 3)
	var peak := 0.0
	var fired_at := -1
	for i in 240:
		var ev := s.step({})
		peak = maxf(peak, float((m.get("tier", {}) as Dictionary).get("meter", 0.0)))
		var pe := _tier_events(ev, "purge")
		if not pe.is_empty():
			fired_at = s.tick
			peak = maxf(peak, float(pe[0].get("meter", 0.0)))
			break
	c.ok(fired_at > 0, "fire 3 under it: a Purge fires (tick %d)" % fired_at)
	c.ok(peak >= HHTierBrain.t("pain_pct"), "the meter passed the line first (peak %.2f %% >= %.1f %%)" % [peak, HHTierBrain.t("pain_pct")])
	c.ok(fired_at >= 60 and fired_at <= 150, "after ~3 s of fire 3, not at once (tick %d)" % fired_at)
	c.eq(float(m.tier.meter), 0.0, "the meter resets when it purges")
	# below the line: fire 1 under it peaks at ~1.6 % in 4 s
	var r2 := _sim("spirewalker", "normal")
	var s2: HHSim = r2[0]
	var m2: Dictionary = r2[2]
	s2.paint([m2.hex], "fire", "p1", 1)
	var peak2 := 0.0
	var any := false
	for i in 300:
		var ev := s2.step({})
		peak2 = maxf(peak2, float((m2.get("tier", {}) as Dictionary).get("meter", 0.0)))
		any = any or not _tier_events(ev, "purge").is_empty()
	c.ok(not any, "fire 1 under it: no Purge in 10 s (meter peak %.2f %%)" % peak2)
	c.ok(peak2 > 0.5 and peak2 < HHTierBrain.t("pain_pct"), "the meter counts it, under the line")
	# EASY: the same burn, nothing
	var r3 := _sim("spirewalker", "easy")
	var s3: HHSim = r3[0]
	var m3: Dictionary = r3[2]
	s3.paint([m3.hex], "fire", "p1", 3)
	var ev3 := _until(s3, 240, func(): return false)
	var tiers := 0
	for ev in ev3:
		tiers += _count(ev, "tier")
	c.eq(tiers, 0, "EASY: no tier events at all")
	c.ok(not m3.has("tier"), "EASY: the unit never carries tier state")
	c.ok(float(m3.hp) < float(m3.max_hp), "EASY: it just keeps burning")
	_isolate(false)


func test_discharge_roar_is_contained(c: HHSelfTest.HHCheck) -> void:
	_isolate(true)
	var r := _sim("spirewalker", "normal")
	var s: HHSim = r[0]
	var m: Dictionary = r[2]
	var p := s.unit("p1")
	var radius := int(m.size) + HHTierBrain.ti("purge_radius")
	s.paint([m.hex], "fire", "p1", 3)
	# inside the radius: a hunter's charged setup (fire 2 on three hexes, dark 1 on the rim)
	var inner := [m.hex + Vector2i(4, 0), m.hex + Vector2i(-4, 0), m.hex + Vector2i(0, 4)]
	for h in inner:
		s.paint([h], "fire", "p1", 2)
	var rim: Vector2i = m.hex + Vector2i(0, -5)
	s.paint([rim], "dark", "p1", 1)
	# outside, touching the rim hex: must survive (no chain)
	var outside: Vector2i = rim + Vector2i(0, -1)
	s.paint([outside], "fire", "p1", 2)
	# an armed fuse on empty ground inside: not charged, so not part of the roar, stays armed
	var fuse: Vector2i = m.hex + Vector2i(-2, 3)
	s.paint([fuse], "thunder", "p1", 1)
	# the hunter stands on a charged hex inside, nearly dead: DECIDE-C (never kills)
	p.hex = inner[2]
	p.pos = s.arena.stand(p.hex)
	p.crossed = p.hex
	p.hp = 40.0
	c.eq(HHHex.distance(rim, m.hex), radius, "the rim hex is on the edge of the purge radius")
	c.eq(s.charge.marker(fuse), "fuse", "the fuse is armed")
	var started := -1
	var done_ev: Array = []
	for i in 300:
		var ev := s.step({})
		if started < 0 and not _tier_events(ev, "purge").is_empty():
			started = s.tick
			var tg: Array = s.telegraphs.filter(func(t): return str((t.payload as Dictionary).get("name", "")) == "tier_discharge_roar")
			c.eq(tg.size(), 1, "the roar is telegraphed")
			if tg.size() == 1:
				var want: Array = HHTierBrain.purge_hexes(s, m).filter(func(h): return s.charge.charged(h))
				var got: Array = (tg[0].hexes as Array).duplicate()
				got.sort()
				c.eq(got, want, "the telegraph shows exactly the charged hexes in reach")
				c.eq(int(tg[0].left), HHTierBrain.ti("purge_windup_ticks") - 1, "a 1 s tell (one tick already counted down)")
		if not _tier_events(ev, "purge_done").is_empty():
			done_ev = ev
			break
	c.ok(started > 0 and not done_ev.is_empty(), "the roar started and landed")
	var dets := _count(done_ev, "detonate")
	c.eq(dets, 5, "one detonation per charged hex in reach (centre, three fire 2, the dark rim)")
	c.eq(_count(done_ev, "overheat") + _count(done_ev, "overfreeze") + _count(done_ev, "gale"), 0, "nothing else went off in the same action")
	c.ok(done_ev.filter(func(e): return str(e.type) == "detonate").all(func(e): return str(e.get("trigger", "")) == str(m.id)), "every blast is the roar's own (EL's react_at, the monster the trigger)")
	for h in inner + [rim]:
		c.ok(not s.charge.charged(h), "inside %s: cashed out" % [h])
	c.eq(s.charge.intensity(outside, "fire"), 2, "outside, touching a blast: untouched (no chain)")
	c.eq(s.charge.marker(fuse), "fuse", "the empty fuse inside is still armed (the roar fires charge, not markers)")
	c.ok(float(p.hp) >= 1.0 and float(p.hp) < 40.0, "the hunter on a blast took damage but lives (hp %.1f, 3.3 / DECIDE-C)" % float(p.hp))
	c.ok(not bool(p.get("downed", false)) and s.over == "", "nobody went down")
	c.ok(float(m.hp) < float(m.max_hp), "the hunter's own setup hurt the monster (3.3: monster_reaction_frac)")
	# then the reposition: a leap to a clean corner
	var T: Dictionary = m.tier
	c.eq(str((T.act as Dictionary).get("kind", "")), "move", "it repositions after the purge")
	c.eq(str((T.act as Dictionary).get("style", "")), "leap", "Spirewalker leaps")
	var goal: Vector2i = (T.act as Dictionary).get("goal", Vector2i.ZERO)
	_until(s, 90, func(): return (T.act as Dictionary).is_empty())
	c.ok((T.act as Dictionary).is_empty(), "the move ended")
	c.eq(m.hex, goal, "it landed on its corner")
	c.ok(HHHex.distance(m.hex, Vector2i(0, -2)) >= HHTierBrain.ti("reposition_min"), "far from where it purged")
	var dirt := 0
	for h in HHHex.area(m.hex, int(m.size) + 1):
		if s.charge.charged(h):
			dirt += 1
	c.eq(dirt, 0, "clean ground under the corner")
	_isolate(false)


func test_quench_wave_is_contained(c: HHSelfTest.HHCheck) -> void:
	_isolate(true)
	var r := _sim("swampfang", "normal")
	var s: HHSim = r[0]
	var m: Dictionary = r[2]
	s.paint([m.hex], "fire", "p1", 3)
	var fires := [m.hex + Vector2i(3, 0), m.hex + Vector2i(-3, 1), m.hex + Vector2i(1, 4)]
	for h in fires:
		s.paint([h], "fire", "p1", 1)
	var fuse: Vector2i = m.hex + Vector2i(-4, 0)
	s.paint([fuse], "thunder", "p1", 1)
	var crystal: Vector2i = m.hex + Vector2i(2, -4)
	s.paint([crystal], "water", "p1", 1)
	s.paint([crystal], "ice", "p1", 1)
	var gale: Vector2i = m.hex + Vector2i(4, -1)
	s.paint([gale], "wind", "p1", 1)
	c.ok(s.charge.is_crystal(crystal), "a crystal inside (EL: ice on charge)")
	var done_ev: Array = []
	var dived := false
	for i in 300:
		var ev := s.step({})
		if not _tier_events(ev, "purge_done").is_empty():
			done_ev = ev
			break
	c.ok(not done_ev.is_empty(), "the Quench Wave landed")
	c.eq(_count(done_ev, "detonate") + _count(done_ev, "overheat") + _count(done_ev, "geyser") + _count(done_ev, "shatter") + _count(done_ev, "gale"), 0,
		"no detonation, burst, shatter or gale in the same action")
	c.eq(_count(done_ev, "steam"), fires.size() + 1, "H420: each hunter fire in reach erupts as Steam, once")
	c.ok(done_ev.filter(func(e): return str(e.type) == "steam").all(func(e): return str(e.get("trigger", "")) == str(m.id)), "monster-triggered (3.3)")
	for h in fires + [m.hex]:
		c.eq(s.charge.intensity(h, "fire"), 0, "fire at %s cashed out" % [h])
	c.eq(s.charge.marker(fuse), "fuse", "the armed fuse did not fire (contained)")
	c.eq(s.charge.marker(gale), "gale", "the gale marker did not fire")
	c.ok(s.charge.is_crystal(crystal) and s.charge.intensity(crystal, "water") == 1, "the crystal is skipped (not shattered, not fed)")
	c.eq(s.charge.intensity(m.hex + Vector2i(0, 4), "water"), HHTierBrain.ti("quench_steps"), "empty ground in reach: water 2")
	var T: Dictionary = m.tier
	c.eq(str((T.act as Dictionary).get("style", "")), "dive", "Swampfang dives to its corner")
	for i in 240:
		s.step({})
		dived = dived or bool(m.untargetable)
		if (T.act as Dictionary).is_empty():
			break
	c.ok(dived, "submerged (untargetable) on the way")
	c.ok((T.act as Dictionary).is_empty() and not bool(m.untargetable), "surfaced at the end")
	_isolate(false)
