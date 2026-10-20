extends RefCounted
## Lane W (H57, H58): commit feel. Recovery after every action, the dash and
## the movement skills as the only escapes, the lance / daggers basic strings
## (never the bow), the facing lock, the monster's exposed window, W's short
## wind-up, the potion's root, the input buffer, and monster hits that land
## interrupting the hunter (and the things that do not).


class StubBrain:
	extends RefCounted
	var busy_until := 0
	func tick(_sim: HHSim, _u: Dictionary) -> void:
		pass


func _sim(weapon: String, at: Vector2i = Vector2i(0, 2)) -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", at, "fire", "water", weapon)
	s.add_monster("m", Vector2i(0, -2), 50000.0, 2)
	return s


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e): return e.type == type)


func _steps(s: HHSim, n: int, first: Dictionary = {}) -> Array:
	var out: Array = []
	out.append_array(s.step(first))
	for i in n - 1:
		out.append_array(s.step())
	return out


func _rec() -> int:
	return int(HHTune.value("recovery_ticks"))


# ------------------------------------------------------------------ recovery

func test_recovery_after_every_action(c: HHSelfTest.HHCheck) -> void:
	var cases := [
		["lance", { "cast": { "skill": "q", "aim": Vector2i(0, -2) } }, int(HHTune.value("lance_q_windup")), "Q"],
		["lance", { "cast": { "skill": "e", "aim": Vector2i(0, 2) } }, 0, "E (instant Guard)"],
		["bow", { "cast": { "skill": "e", "aim": Vector2i(0, -1) } }, 0, "E (Arcing Shot)"],
		["lance", { "swap": true }, int(HHTune.value("exchange_windup")), "W"],
		["lance", { "potion": { "aim": Vector2i(2, 2) } }, int(HHTune.value("potion_windup")), "the potion throw"],
		["daggers", { "cast": { "skill": "r", "aim": Vector2i(0, 2) } }, 0, "R (Knifedance)"],
	]
	for cs in cases:
		var s := _sim(str(cs[0]), Vector2i(0, 4))
		var p := s.unit("p1")
		var ev := _steps(s, int(cs[2]) + 1, { "p1": cs[1] })
		c.ok(not _of(ev, "recovery").is_empty(), "%s: a recovery follows" % cs[3])
		c.ok(int(p.recovery) > 0, "%s: recovering" % cs[3])
		var at: Vector3 = p.pos
		s.step({ "p1": { "move": Vector2i(6, 4), "move_pos": s.arena.stand(Vector2i(6, 4)) } })
		c.ok((p.pos as Vector3).distance_to(at) < 0.01, "%s: rooted during the recovery" % cs[3])
	# basics (H59): a bow basic recovers basic_recovery_bow_ticks, a vault landing recovery_ticks
	var s := _sim("bow", Vector2i(0, 4))
	var p := s.unit("p1")
	var ev := _steps(s, 60, { "p1": { "target": "m", "attack": true } })
	c.ok(_of(ev, "recovery").any(func(e): return int(e.ticks) == int(HHTune.value("basic_recovery_bow_ticks"))), "a bow basic recovers 0.2 s (H59)")
	var d := _sim("daggers", Vector2i(0, 4))
	var evd := _steps(d, 60, { "p1": { "target": "m", "attack": true } })
	c.ok(_of(evd, "recovery").any(func(e): return int(e.ticks) == int(HHTune.value("basic_recovery_melee_ticks"))), "string hit 1 recovers 0.15 s (H59)")
	var t := _sim("lance", Vector2i(0, 6))
	var ev2 := _steps(t, int(HHTune.value("lance_r_air_ticks")) + 1, { "p1": { "cast": { "skill": "r", "aim": Vector2i(3, 5) } } })
	c.ok(not _of(ev2, "land").is_empty() and not _of(ev2, "recovery").is_empty(), "a vault's landing recovers")


func test_w_and_potion_wind_up(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(0, 4))
	var p := s.unit("p1")
	var ev := s.step({ "p1": { "swap": true } })
	c.ok(_of(ev, "windup").any(func(e): return e.kind == "exchange" and int(e.ticks) == int(HHTune.value("exchange_windup"))), "W winds up exchange_windup ticks")
	c.eq(p.element, "fire", "not yet swapped")
	_steps(s, int(HHTune.value("exchange_windup")))
	c.eq(p.element, "water", "swapped after the wind-up")
	var t := _sim("bow", Vector2i(0, 4))
	var q := t.unit("p1")
	t.step({ "p1": { "move": Vector2i(8, 4), "move_pos": t.arena.stand(Vector2i(8, 4)) } })
	t.step()
	t.step({ "p1": { "potion": { "aim": Vector2i(3, 4) } } })
	var at: Vector3 = q.pos
	_steps(t, 5)
	c.ok((q.pos as Vector3).distance_to(at) < 0.01, "the potion throw roots")


func test_input_buffer(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(0, 4))
	var p := s.unit("p1")
	_steps(s, int(HHBow.TUNE.q_windup) + 1, { "p1": { "cast": { "skill": "q", "aim": Vector2i(5, 4) } } })
	c.ok(int(p.recovery) > 0, "recovering")
	s.step({ "p1": { "cast": { "skill": "e", "aim": Vector2i(0, -1) } } })
	c.eq(int(p.cooldowns.e), 0, "E pressed during the recovery waits")
	var ev := _steps(s, _rec() + 2)
	c.ok(_of(ev, "cast").any(func(e): return e.skill == "e"), "...and fires when the recovery ends")


# ------------------------------------------------------------------ escapes

func test_dash_escapes_wind_up_and_recovery(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(0, 2))
	var p := s.unit("p1")
	var m := s.unit("m")
	var hp := float(m.hp)
	s.step({ "p1": { "cast": { "skill": "q", "aim": m.hex } } })
	c.eq(str(p.windup.get("kind", "")), "pierce", "winding up Pierce")
	var ev := s.step({ "p1": { "dash": (p.pos as Vector3) + Vector3(4, 0, 2) } })
	c.eq(_of(ev, "dash").size(), 1, "the dash goes during a wind-up")
	c.ok(_of(ev, "windup_broken").any(func(e): return e.kind == "pierce" and e.why == "dash"), "...and breaks it")
	_steps(s, 30)
	c.ok(_of(s.events, "pierce").is_empty() and float(m.hp) == hp, "the Pierce never happens")
	# recovery
	var t := _sim("bow", Vector2i(0, 4))
	var q := t.unit("p1")
	_steps(t, int(HHBow.TUNE.q_windup) + 1, { "p1": { "cast": { "skill": "q", "aim": Vector2i(5, 4) } } })
	c.ok(int(q.recovery) > 0, "recovering")
	var ev2 := t.step({ "p1": { "dash": (q.pos as Vector3) + Vector3(-4, 0, 0) } })
	c.eq(_of(ev2, "dash").size(), 1, "the dash goes during a recovery")
	c.eq(int(q.recovery), 0, "...and ends it")


func test_movement_skills_escape(c: HHSelfTest.HHCheck) -> void:
	for row in [["lance", "r"], ["daggers", "e"], ["bow", "r"]]:
		var s := _sim(str(row[0]), Vector2i(0, 6))
		var p := s.unit("p1")
		s.step({ "p1": { "cast": { "skill": "q", "aim": Vector2i(0, 0) } } })
		c.ok(not (p.windup as Dictionary).is_empty(), "%s: winding up Q" % row[0])
		var ev := s.step({ "p1": { "cast": { "skill": row[1], "aim": Vector2i(4, 6) } } })
		c.ok(not _of(ev, "leap").is_empty(), "%s %s: the movement skill goes during a wind-up" % [row[0], row[1]])
		c.ok(not _of(ev, "windup_broken").is_empty(), "%s: ...breaking it" % row[0])


func test_nothing_else_escapes(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(0, 6))
	var p := s.unit("p1")
	s.step({ "p1": { "cast": { "skill": "q", "aim": Vector2i(0, 0) } } })
	var at: Vector3 = p.pos
	var ev: Array = []
	ev.append_array(s.step({ "p1": { "cast": { "skill": "e", "aim": p.hex } } }))
	ev.append_array(s.step({ "p1": { "move": Vector2i(6, 6), "move_pos": s.arena.stand(Vector2i(6, 6)) } }))
	ev.append_array(s.step({ "p1": { "swap": true } }))
	ev.append_array(s.step({ "p1": { "potion": true } }))
	c.ok(_of(ev, "windup_broken").is_empty(), "E, a move, W and the potion do not break a wind-up")
	c.ok((p.pos as Vector3).distance_to(at) < 0.01, "no movement")
	c.ok(int(p.guard) == 0, "no Guard")
	var ev2 := _steps(s, 12)
	c.eq(_of(ev2, "pierce").size(), 1, "the Pierce lands as committed")


func test_dash_cancels_a_held_charge_without_a_shot(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(0, 4))
	var p := s.unit("p1")
	_steps(s, 30, { "p1": { "charge": { "skill": "q", "aim": Vector2i(0, -2) } } })
	var ev := _steps(s, 20, { "p1": { "dash": (p.pos as Vector3) + Vector3(4, 0, 0) } })
	c.ok(_of(ev, "energized_shot").is_empty() and _of(ev, "charge_release").is_empty(), "no shot")
	c.ok(_of(ev, "charge_cancel").any(func(e): return e.why == "dash"), "charge_cancel { why: dash }")


# ------------------------------------------------------------------ strings

func _string(s: HHSim, ticks: int) -> Array:
	return _steps(s, ticks, { "p1": { "target": "m", "attack": true } })


func test_lance_and_daggers_strings(c: HHSelfTest.HHCheck) -> void:
	for weapon in ["lance", "daggers"]:
		var s := _sim(weapon, Vector2i(0, 2) if weapon == "lance" else Vector2i(0, 1))
		var ev := _string(s, 240)
		var strikes := _of(ev, "strike").filter(func(e): return e.cause == "basic")
		var steps: Array = strikes.map(func(e): return int(e.combo))
		c.ok(steps.size() >= 6 and steps.slice(0, 6) == [1, 2, 3, 1, 2, 3], "%s: hits string 1-2-3-1-2-3 (%s)" % [weapon, steps])
		var base := HHWeapons.basic_damage(weapon)
		for e in strikes.slice(0, 3):
			c.near(float(e.amount), roundf(base * float(HHWeapons.combo_hit(weapon, int(e.combo)).mult)), 0.5, "%s hit %d damage" % [weapon, int(e.combo)])
		c.ok(bool(strikes[2].get("heavy", false)), "%s: hit 3 is a heavy finisher" % weapon)
		var h1 := HHWeapons.combo_hit(weapon, 1)
		var h2 := HHWeapons.combo_hit(weapon, 2)
		var h3 := HHWeapons.combo_hit(weapon, 3)
		c.ok(int(h3.windup) > int(h2.windup) and int(h2.windup) > int(h1.windup), "%s: wind-ups grow" % weapon)
		c.ok(int(h3.recovery) > int(h2.recovery) and int(h2.recovery) > int(h1.recovery), "%s: recoveries grow" % weapon)
		c.ok(int(h3.recovery) >= 15 and int(h3.recovery) <= 18, "%s: the finisher recovers ~0.5-0.6 s (%d)" % [weapon, int(h3.recovery)])
		c.ok(int(h3.steps) > int(h1.steps) and float(h3.stagger) > float(h1.stagger), "%s: the finisher lays more element and staggers" % weapon)
		c.ok(_of(ev, "combo").size() >= 6, "%s: combo events" % weapon)


func test_strings_reset(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(0, 2))
	var p := s.unit("p1")
	var ev := _string(s, 60)
	c.ok(_of(ev, "strike").any(func(e): return int(e.get("combo", 0)) == 2), "two hits in")
	s.step({ "p1": { "move": Vector2i(0, 3), "move_pos": s.arena.stand(Vector2i(0, 3)) } })
	c.ok((p.combo as Dictionary).is_empty(), "a move order resets the string")
	var ev2 := _string(s, 80)
	var first := _of(ev2, "combo")
	c.ok(not first.is_empty() and int(first[0].step) == 1, "the next basic starts at hit 1")
	# waiting too long
	var t := _sim("lance", Vector2i(0, 2))
	var q := t.unit("p1")
	_string(t, 14)                                      # hit 1 lands at tick 12
	t.step({ "p1": { "stop": true } })
	_steps(t, int(HHTune.value("combo_window_ticks")) + _rec() + 30)
	var ev3 := _string(t, 20)
	var k := _of(ev3, "combo")
	c.ok(not k.is_empty() and int(k[0].step) == 1, "after the window the string starts over")
	# dashing
	var u := _sim("daggers", Vector2i(0, 1))
	var r := u.unit("p1")
	_string(u, 20)
	u.step({ "p1": { "dash": (r.pos as Vector3) + Vector3(4, 0, 2) } })
	c.ok((r.combo as Dictionary).is_empty(), "a dash resets the string")


func test_bow_has_no_string(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(0, 4))
	var p := s.unit("p1")
	var ev := _string(s, 300)
	var strikes := _of(ev, "strike").filter(func(e): return e.cause == "basic")
	c.ok(strikes.size() >= 5, "the bow fires basics (%d)" % strikes.size())
	c.ok(_of(ev, "combo").is_empty(), "no combo events")
	c.ok(strikes.all(func(e): return int(e.get("combo", 1)) == 1 and absf(float(e.amount) - float(HHBow.TUNE.basic_dmg)) < 0.5), "every arrow is a plain hit")
	c.ok((p.combo as Dictionary).is_empty(), "no string on the unit")
	c.ok(not HHWeapons.has_combo("bow") and HHWeapons.has_combo("lance") and HHWeapons.has_combo("daggers"), "has_combo: lance and daggers only")


# ------------------------------------------------------------------ facing

func test_facing_lock(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(0, 6))
	var p := s.unit("p1")
	s.step({ "p1": { "cast": { "skill": "q", "aim": Vector2i(0, 0) } } })
	var f := float(p.facing)
	s.step({ "p1": { "target": "m" } })
	s.unit("m").pos = s.arena.stand(Vector2i(6, 6))
	_steps(s, 5)
	c.near(float(p.facing), f, 1e-4, "no turning during a wind-up")
	_steps(s, 6)
	c.ok(int(p.recovery) > 0, "recovering")
	var before := float(p.facing)
	s.step()
	var turned := absf(wrapf(float(p.facing) - before, -PI, PI))
	c.ok(turned > 0.0, "turns during the recovery")
	c.ok(turned <= deg_to_rad(HHTune.value("recovery_turn_dps")) / 30.0 + 1e-4, "...at most recovery_turn_dps (%.3f rad a tick)" % turned)


# ------------------------------------------------------------------ exposed

func test_exposed_window(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(8, 8))
	var m := s.unit("m")
	var brain := StubBrain.new()
	s.brains["m"] = brain
	brain.busy_until = s.tick + 40
	var big: Array = s.arena.area(Vector2i(0, 4), 2)
	s.telegraph("m", big, 10, { "dmg_pct": 5.0, "name": "slam" })
	var ev := _steps(s, 10)
	c.ok(not _of(ev, "exposed").is_empty(), "a big attack resolving exposes the monster")
	c.ok(int(m.exposed) > 0 and int(m.exposed) <= 30, "for the rest of its own recovery (%d ticks), no more" % int(m.exposed))
	var p := s.unit("p1")
	var hp := float(m.hp)
	s.strike(p, m, 100.0, m.hex, "test")
	c.near(hp - float(m.hp), 100.0 * HHTune.value("exposed_dmg_mult"), 0.5, "exposed: +25% from a hunter")
	_steps(s, 40)
	c.eq(int(m.exposed), 0, "the window closes")
	hp = float(m.hp)
	s.strike(p, m, 100.0, m.hex, "test")
	c.near(hp - float(m.hp), 100.0, 0.5, "...and damage is back to normal")
	brain.busy_until = s.tick + 40
	s.telegraph("m", [Vector2i(0, 4)], 2, { "dmg_pct": 5.0, "name": "jab" })
	_steps(s, 3)
	c.eq(int(m.exposed), 0, "a small attack exposes nothing")


# ------------------------------------------------------------------ interrupts (H58)

func test_monster_hit_interrupts_a_wind_up(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(0, 6))
	var p := s.unit("p1")
	s.step({ "p1": { "cast": { "skill": "q", "aim": Vector2i(0, 0) } } })
	s.telegraph("m", [p.hex], 2, { "dmg_pct": 3.0, "name": "jab" })
	var ev := _steps(s, 20)
	var it := _of(ev, "interrupted")
	c.eq(it.size(), 1, "interrupted")
	c.ok(it.size() == 1 and str(it[0].what).contains("pierce") and str(it[0].skill) == "q", "...the Pierce wind-up, q box (%s)" % [it])
	c.ok(_of(ev, "pierce").is_empty(), "the Pierce never lands")
	c.ok(int(p.flinch) == 0 and _of(ev, "recovery").is_empty(), "a flinch, not a recovery")


func test_monster_hit_interrupts_charge_combo_recovery(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("bow", Vector2i(0, 6))
	var p := s.unit("p1")
	_steps(s, 30, { "p1": { "charge": { "skill": "q", "aim": Vector2i(0, 0) } } })
	s.telegraph("m", [p.hex], 1, { "dmg_pct": 3.0, "name": "jab" })
	var ev := _steps(s, 3)
	c.ok(not s.charging(p), "a held charge is lost")
	c.ok(_of(ev, "energized_shot").is_empty(), "...no shot")
	c.eq(int(p.cooldowns.q), 0, "...and the cooldown is not spent")
	# combo
	var t := _sim("daggers", Vector2i(0, 1))
	var q := t.unit("p1")
	_steps(t, 14, { "p1": { "target": "m", "attack": true } })
	c.ok(not (q.combo as Dictionary).is_empty(), "a string running")
	t.strike(t.unit("m"), q, 50.0, q.hex, "bite")
	c.ok((q.combo as Dictionary).is_empty(), "a monster blow resets the string")
	# recovery replaced by the flinch
	var u := _sim("bow", Vector2i(0, 6))
	var r := u.unit("p1")
	_steps(u, int(HHBow.TUNE.q_windup) + 1, { "p1": { "cast": { "skill": "q", "aim": Vector2i(5, 6) } } })
	c.ok(int(r.recovery) > 0, "recovering")
	u.strike(u.unit("m"), r, 50.0, r.hex, "bite")
	c.eq(int(r.recovery), 0, "the recovery is gone")
	c.eq(int(r.flinch), int(HHTune.value("flinch_ticks")), "a flinch of flinch_ticks instead")
	c.ok(_of(u.events, "interrupted").any(func(e): return str(e.what).contains("recovery")), "interrupted { what: recovery }")


func test_lance_charge_braced_not_interrupted(c: HHSelfTest.HHCheck) -> void:
	var s := _sim("lance", Vector2i(0, 6))
	var p := s.unit("p1")
	_steps(s, 20, { "p1": { "charge": { "skill": "q", "aim": Vector2i(0, 0) } } })
	var hp := float(p.hp)
	s.strike(s.unit("m"), p, 1000.0, p.hex, "bite")
	c.near(hp - float(p.hp), 1000.0 * (1.0 - HHTune.value("lance_charge_guard")), 0.5, "the brace cuts the hit")
	c.ok(s.charging(p), "the lance charge holds through a monster hit (H59 super armour)")
	c.eq(int(p.flinch), 0, "no flinch while braced")
	s.hurt(p, 100.0, "slam", 5.0, "m")
	c.ok(s.charging(p) and int(p.stagger) == 0, "a staggering blow does not break the brace either")


func test_what_does_not_interrupt(c: HHSelfTest.HHCheck) -> void:
	var cases := ["fire", "burn", "env", "guard", "reaction"]
	for cs in cases:
		var s := _sim("lance", Vector2i(0, 6))
		var p := s.unit("p1")
		if cs == "guard":
			s.step({ "p1": { "cast": { "skill": "e", "aim": p.hex } } })
			_steps(s, _rec() + 1)
		var ev: Array = s.step({ "p1": { "charge": { "skill": "q", "aim": Vector2i(0, 0) } } })
		match cs:
			"fire":
				s.charge.author(p.hex, 3, 0, "")
				ev.append_array(_steps(s, 31))
			"burn":
				s.apply_status(p, "burn", 90)
				ev.append_array(_steps(s, 31))
			"env":
				s.telegraph("env", [p.hex], 1, { "dmg_pct": 3.0, "name": "env_swell", "env": true })
				ev.append_array(_steps(s, 2))
			"guard":
				s.telegraph("m", [p.hex], 1, { "dmg_pct": 3.0, "name": "jab" })
				ev.append_array(_steps(s, 2))
			"reaction":
				s.paint([p.hex], "fire", "m", 2)
				s.paint([p.hex], "thunder", "m", 1)
				ev.append_array(s.events)
				ev.append_array(_steps(s, 2))
		c.ok(float(p.hp) < float(p.max_hp), "%s: it hurt" % cs)
		c.ok(_of(ev, "interrupted").is_empty(), "%s: no interrupt" % cs)
		c.ok(s.charging(p) or cs == "reaction", "%s: still charging (a reaction blast staggers, which cancels as before)" % cs)
