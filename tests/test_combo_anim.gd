extends RefCounted
## H60 (Lane X): the dedicated string clips. Every hit has its own clip,
## timed to the sim (contact = the hit's wind-up, the clip done before the
## next hit can start), hits chain through ready loops without a pop, the
## feet hold their plants, the string ends in the guard, the swing trail
## draws only on the swing, and the lance's brace holds through a charge.

const STRINGS := ["lance", "daggers"]
const POP_M := 0.03                    # a seam may move a joint this far (m)


func _body(weapon: String) -> HHPlayerBody:
	var b := HHPlayerBody.new()
	if not b.build(weapon):
		b.free()
		return null
	return b


func _clip_set(w: String) -> GDScript:
	return HHPlayerBody.clip_set(w)


## Joint positions that show a pop: the root of the figure, the head, both wrists, both ankles, the weapon.
func _snap(b: HHPlayerBody) -> Array:
	return [b.bone_pos("hips"), b.bone_pos("head"), b.bone_pos("hand_l"), b.bone_pos("hand_r"),
		b.bone_pos("foot_l"), b.bone_pos("foot_r"), b.socket_pos("weapon_r")]


func _gap(a: Array, c: Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, (a[i] as Vector3).distance_to(c[i]))
	return m


func test_every_hit_has_a_dedicated_clip(c: HHSelfTest.HHCheck) -> void:
	for w in STRINGS:
		var clips := HHPlayerBody.clips(w)
		var combo: Dictionary = _clip_set(w).get("COMBO_CLIPS")
		var ready: Dictionary = _clip_set(w).get("READY_CLIPS")
		var seen := {}
		for step in [1, 2, 3]:
			var name := str(combo.get(step, ""))
			c.ok(clips.has(name), "%s hit %d -> %s in CLIPS" % [w, step, name])
			c.ok(not seen.has(name), "%s hit %d has its own clip" % [w, step])
			seen[name] = true
			c.ok(not name in ["strike", "sweep", "spin", "slam", "jump_attack"], "%s hit %d is not a reused clip (%s)" % [w, step, name])
		for step in [1, 2]:
			c.ok(clips.has(str(ready.get(step, ""))) and bool(clips[str(ready[step])].loop), "%s ready loop %d" % [w, step])
		var b := _body(w)
		if b == null:
			c.ok(false, "body %s" % w)
			continue
		for name in seen.keys() + ready.values():
			var okp := true
			for u in [0.0, 0.3, 0.6, 1.0]:
				okp = b.pose_at(name, b.duration(name) * u) and okp
			c.ok(okp, "%s/%s has a pose function" % [w, name])
		b.free()


func test_hits_are_timed_to_the_sim(c: HHSelfTest.HHCheck) -> void:
	for w in STRINGS:
		var clips := HHPlayerBody.clips(w)
		var combo: Dictionary = _clip_set(w).get("COMBO_CLIPS")
		var cadence := int(HHWeapons.basic_ticks(w))
		for step in [1, 2, 3]:
			var row: Dictionary = clips[str(combo[step])]
			var hit := HHWeapons.combo_hit(w, step)
			c.eq(int(row.contact_tick), int(hit.windup), "%s hit %d contact tick = its wind-up" % [w, step])
			c.eq(int(row.get("recovery", -1)), int(hit.recovery), "%s hit %d recovery = the sim's" % [w, step])
			c.ok(bool(row.get("timed", false)), "%s hit %d plays through the recovery at full rate" % [w, step])
			# the next wind-up can start at the basic cooldown, or when the recovery ends
			var next := maxi(cadence, int(hit.windup) + int(hit.recovery))
			c.ok(float(row.duration) <= float(next) * HHSim.TICK + 0.001, "%s hit %d done (%.2f s) before the next can start (%d ticks)" % [w, step, float(row.duration), next])
			var tr: Variant = row.get("trail")
			c.ok(tr is Array and float(tr[0]) < float(row.contact_tick) * HHSim.TICK and float(tr[1]) > float(row.contact_tick) * HHSim.TICK, "%s hit %d trail spans the contact" % [w, step])
		# the finisher's trail is the strongest
		c.ok(float(clips[str(combo[3])].trail[2]) > float(clips[str(combo[1])].trail[2]), "%s finisher trail strongest" % w)


func test_hits_chain_without_a_pop(c: HHSelfTest.HHCheck) -> void:
	for w in STRINGS:
		var b := _body(w)
		if b == null:
			c.ok(false, "body %s" % w)
			continue
		var combo: Dictionary = _clip_set(w).get("COMBO_CLIPS")
		var ready: Dictionary = _clip_set(w).get("READY_CLIPS")
		for step in [1, 2]:
			var hit := str(combo[step])
			b.pose_at(hit, b.duration(hit))
			var end := _snap(b)
			b.pose_at(str(ready[step]), 0.0)
			var r := _snap(b)
			b.pose_at(str(combo[step + 1]), 0.0)
			var nxt := _snap(b)
			c.ok(_gap(end, r) < POP_M, "%s hit %d ends on its ready loop (%.3f m)" % [w, step, _gap(end, r)])
			c.ok(_gap(r, nxt) < POP_M, "%s ready %d is hit %d's first frame (%.3f m)" % [w, step, step + 1, _gap(r, nxt)])
		var fin := str(combo[3])
		b.pose_at(fin, b.duration(fin))
		var e3 := _snap(b)
		b.pose_at("wield_idle", 0.0)
		var g := _snap(b)
		c.ok(_gap(e3, g) < POP_M, "%s finisher ends in the guard: root home (%.3f m)" % [w, _gap(e3, g)])
		b.pose_at(str(combo[1]), 0.0)
		c.ok(_gap(_snap(b), g) < POP_M, "%s hit 1 starts from the guard" % w)
		b.free()


func test_contact_reaches_and_feet_hold(c: HHSelfTest.HHCheck) -> void:
	for w in STRINGS:
		var b := _body(w)
		if b == null:
			c.ok(false, "body %s" % w)
			continue
		var combo: Dictionary = _clip_set(w).get("COMBO_CLIPS")
		b.pose_at("wield_idle", 0.0)
		var hips0 := b.bone_pos("hips")
		for step in [1, 2, 3]:
			var name := str(combo[step])
			b.pose_at(name, b.contact_time(name))
			c.ok(b.bone_pos("hips").z > hips0.z + 0.15, "%s hit %d lunges at contact (root %.2f m)" % [w, step, b.bone_pos("hips").z - hips0.z])
			# a planted foot stays planted: between two frames on the ground the ankle may not skate
			var d := b.duration(name)
			var prev := {}
			var worst := 0.0
			var floated := 0.0
			var n := int(d * 60.0)
			for i in n + 1:
				b.pose_at(name, d * float(i) / float(n))
				for side in ["l", "r"]:
					var p := b.bone_pos("foot_" + side)
					if prev.has(side):
						var q: Vector3 = prev[side]
						if p.y < HHClipsShared.ANKLE_Y + 0.01 and q.y < HHClipsShared.ANKLE_Y + 0.01:
							worst = maxf(worst, Vector2(p.x - q.x, p.z - q.z).length())
					prev[side] = p
			c.ok(worst < 0.012, "%s hit %d: planted feet do not skate (%.3f m a frame)" % [w, step, worst])
			# the IK reaches its plants: the lunge never stretches a leg off the floor at rest frames
			b.pose_at(name, b.contact_time(name) + 0.05)
			floated = minf(b.bone_pos("foot_l").y, b.bone_pos("foot_r").y)
			c.ok(floated < HHClipsShared.ANKLE_Y + 0.03, "%s hit %d: a foot on the floor after contact (%.2f)" % [w, step, floated])
		b.free()


## The string through the real sim: windup events drive the hits, the
## ready loops hold between them, and a lapsed window eases to the guard.
func test_string_plays_through_the_sim(c: HHSelfTest.HHCheck) -> void:
	for w in STRINGS:
		var arena := HHArena.round_flat(1, 20.0, 0.0)
		var sim := HHSim.new(arena, 1)
		var u := sim.add_player("p1", Vector2i(10, 10), "fire", "water", w)
		sim.add_monster("m", Vector2i(12, 10), 1.0e7, 1)
		u.target = "m"
		u.attacking = true
		var b := _body(w)
		if b == null:
			c.ok(false, "body %s" % w)
			continue
		b.bind(sim, "p1")
		var combo: Dictionary = _clip_set(w).get("COMBO_CLIPS")
		var ready: Dictionary = _clip_set(w).get("READY_CLIPS")
		var seen: Array = []
		var trail_at_contact := 0
		var trail_late := 0
		var strikes := 0
		for k in 140:
			for e in sim.step({}):
				if str(e.get("id", "")) == "p1":
					b.on_event(e, sim)
					if str(e.type) == "strike":
						strikes += 1
			b.update(HHSim.TICK)
			if seen.is_empty() or seen[-1] != b.clip:
				seen.append(b.clip)
			if b.clip in combo.values() and absf(b.time - b.contact_time(b.clip)) < 0.04:
				trail_at_contact = maxi(trail_at_contact, b.trail_points)
			if b.clip in ready.values():
				trail_late = maxi(trail_late, b.trail_points)
			if strikes >= 3 and k > 0 and (u.combo as Dictionary).is_empty() and b.clip == str(combo[3]) and b.finished_clip != "":
				break
		var want := [str(combo[1]), str(ready[1]), str(combo[2]), str(ready[2]), str(combo[3])]
		var at := 0
		for s in seen:
			if at < want.size() and s == want[at]:
				at += 1
		c.eq(at, want.size(), "%s string plays hit, ready, hit, ready, finisher (%s)" % [w, str(seen)])
		c.ok(trail_at_contact > 1, "%s swing trail drawn at contact (%d)" % [w, trail_at_contact])
		c.eq(trail_late, 0, "%s no trail in the ready loops" % w)
		b.free()
		# a window that lapses: hit 1, then stop attacking; the ready loop gives way to the guard
		var sim2 := HHSim.new(HHArena.round_flat(1, 20.0, 0.0), 1)
		var u2 := sim2.add_player("p1", Vector2i(10, 10), "fire", "water", w)
		sim2.add_monster("m", Vector2i(12, 10), 1.0e7, 1)
		u2.target = "m"
		u2.attacking = true
		var b2 := _body(w)
		b2.bind(sim2, "p1")
		var was_ready := false
		for k in 90:
			for e in sim2.step({}):
				if str(e.get("id", "")) == "p1":
					b2.on_event(e, sim2)
					if str(e.type) == "strike":
						u2.attacking = false
			b2.update(HHSim.TICK)
			was_ready = was_ready or b2.clip == str(ready[1])
		c.ok(was_ready, "%s ready loop between hits" % w)
		c.eq(b2.clip, "wield_idle", "%s lapsed string eases back to the guard" % w)
		b2.free()


## H60: the lance's charged Pierce holds the brace loop (not a held lunge),
## trembles harder with the charge, and the release lands on the pierce.
func test_lance_brace(c: HHSelfTest.HHCheck) -> void:
	var sim := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var u := sim.add_player("p1", Vector2i(0, 2), "fire", "water", "lance")
	sim.add_monster("m", Vector2i(0, -2), 1.0e7, 2)
	var b := _body("lance")
	if b == null:
		c.ok(false, "body")
		return
	b.bind(sim, "p1")
	b.update(HHSim.TICK)
	var orders := { "p1": { "charge": { "skill": "q", "aim": Vector2i(0, -2) } } }
	var held_brace := 0
	var frac := 0.0
	var pierced := false
	var plant_at_pierce := false
	for k in 140:
		var ev := sim.step(orders)
		orders = {}
		for e in ev:
			if str(e.get("id", "")) == "p1":
				b.on_event(e, sim)
				if str(e.type) == "pierce":
					pierced = true
					plant_at_pierce = b.clip == "plant" and absf(b.time - b.contact_time("plant")) < 0.05
		b.update(HHSim.TICK)
		if not (u.charging as Dictionary).is_empty():
			if b.clip == "brace":
				held_brace += 1
			frac = maxf(frac, b.charge_frac)
		if pierced:
			break
	c.ok(held_brace > 60, "the brace holds through the charge (%d ticks)" % held_brace)
	c.ok(frac > 0.9, "charge_frac rises to full (%.2f)" % frac)
	c.ok(pierced, "the full charge fires")
	c.ok(plant_at_pierce, "the release reaches the plant's contact on the pierce")
	b.free()
