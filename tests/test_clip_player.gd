extends RefCounted
## Lane B: the player rig, the weapon clip sets and HHPlayerBody's event map.

const WEAPONS := ["lance", "daggers", "bow"]
const BONES := ["root", "hips", "spine", "chest", "neck", "head",
	"shoulder_l", "upper_arm_l", "forearm_l", "hand_l", "shoulder_r", "upper_arm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
const SOCKETS := ["weapon_r", "offhand_l", "back", "chest", "hair", "hat"]
const SHARED := ["idle", "wield_idle", "walk", "run", "strike", "sweep", "spin", "jump", "jump_attack", "swap", "stagger", "hit_react", "death"]
const SPECIALS := {
	"lance": ["plant", "slam", "guard"],
	"daggers": ["dive", "flourish"],
	"bow": ["kneel_shot", "draw", "lob", "arrowstorm_leap", "volley"],
}
const CONTACTS := { "lance": 12, "daggers": 5, "bow": 8 }


func _body(weapon: String) -> HHPlayerBody:
	var b := HHPlayerBody.new()
	if not b.build(weapon):
		b.free()
		return null
	return b


func test_rig_loads(c: HHSelfTest.HHCheck) -> void:
	c.ok(FileAccess.file_exists("res://art/characters/base_rig.glb"), "base_rig.glb built")
	var j := HHPlayerBody.rig_json()
	c.ok(not j.is_empty(), "rig.json present")
	c.near(float(j.get("height", 0.0)), 2.2, 0.01, "rig height 2.2")
	var names: Array = (j.get("bones", []) as Array).map(func(b): return str(b.name))
	for bn in BONES:
		c.ok(bn in names, "rig.json bone %s" % bn)
	for s in SOCKETS:
		c.ok((j.get("sockets", {}) as Dictionary).has("socket_" + s), "rig.json socket_%s" % s)
	var b := _body("lance")
	c.ok(b != null, "body builds for lance")
	if b == null:
		return
	c.ok(b.skeleton != null and b.skeleton.get_bone_count() == 20, "20 deform bones (%d)" % (b.skeleton.get_bone_count() if b.skeleton else 0))
	for bn in BONES:
		c.ok(b.has_bone(bn), "bone %s" % bn)
	for s in SOCKETS:
		c.ok(b.socket(s) != null, "socket %s" % s)
	c.ok(b.triangle_count() > 0 and b.triangle_count() < 4000, "rig tris under 4000 (%d)" % b.triangle_count())
	c.ok(b.meshes.size() == 5, "one mesh per colour role (%d)" % b.meshes.size())
	var top := b.bone_pos("head")
	c.ok(top.y > 1.7 and top.y < 2.0, "head pivot at 1.84 (%s)" % top)
	var wr := b.socket_pos("weapon_r")
	c.ok(wr.x < 0.0 and wr.y > 0.8 and wr.y < 1.3, "weapon socket in the right hand at rest (%s)" % wr)
	b.free()


func test_clip_tables(c: HHSelfTest.HHCheck) -> void:
	for w in WEAPONS:
		var clips := HHPlayerBody.clips(w)
		c.ok(not clips.is_empty(), "%s has a clip table" % w)
		var want: Array = SHARED.duplicate()
		want.append_array(SPECIALS[w])
		for name in want:
			c.ok(clips.has(name), "%s clip %s" % [w, name])
			if not clips.has(name):
				continue
			var row: Dictionary = clips[name]
			var d := float(row.get("duration", 0.0))
			c.ok(d > 0.0, "%s/%s duration > 0" % [w, name])
			var ct := int(row.get("contact_tick", -1))
			c.ok(ct == -1 or (ct > 0 and float(ct) * HHSim.TICK < d), "%s/%s contact tick %d inside %.2f s" % [w, name, ct, d])
			c.ok(row.has("loop") and row.has("note"), "%s/%s loop + note" % [w, name])
			var key := float(row.get("key", 0.0))
			c.ok(key >= 0.0 and key <= d, "%s/%s key inside" % [w, name])
		c.eq(int(clips.strike.contact_tick), int(CONTACTS[w]), "%s basic contact tick" % w)
		c.ok(bool(clips.run.loop) and float(clips.run.get("stride", 0.0)) > 3.0, "%s run loops with a 3.46 m stride" % w)
		c.ok(bool(clips.idle.loop) and bool(clips.wield_idle.loop), "%s idles loop" % w)
		for k in ["q", "w", "e", "r"]:
			var sc := HHPlayerBody.skill_clip(w, k)
			c.ok(sc != "" and clips.has(sc), "%s skill %s -> %s" % [w, k, sc])
	c.eq(int(HHPlayerBody.clips("lance").plant.contact_tick), 10, "lance plant contact 10 (Pierce)")
	c.ok(bool(HHPlayerBody.clips("lance").guard.loop), "lance guard loops")
	c.ok(bool(HHPlayerBody.clips("bow").draw.loop), "bow draw loops")


func test_every_clip_poses(c: HHSelfTest.HHCheck) -> void:
	for w in WEAPONS:
		var b := _body(w)
		c.ok(b != null, "body builds for %s" % w)
		if b == null:
			continue
		c.ok(b.weapon_main != null, "%s weapon attached" % w)
		var clips := HHPlayerBody.clips(w)
		for name in clips:
			var d := float(clips[name].duration)
			var okp := true
			for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
				okp = b.pose_at(name, d * u) and okp
			c.ok(okp, "%s/%s poses" % [w, name])
			# the pose stays sane: the head above the hips and nothing NaN
			var h := b.bone_pos("head")
			c.ok(is_finite(h.x) and is_finite(h.y) and is_finite(h.z), "%s/%s finite" % [w, name])
			if name != "death" and name != "dive":
				c.ok(h.y > b.bone_pos("hips").y - 0.3, "%s/%s head above hips" % [w, name])
		# feet planted in the loops: both ankles near the ground somewhere in the cycle
		for loopname in ["idle", "wield_idle"]:
			b.pose_at(loopname, 0.3)
			c.ok(b.bone_pos("foot_l").y < 0.2 and b.bone_pos("foot_r").y < 0.2, "%s/%s feet on the ground" % [w, loopname])
		# the strike moves the weapon hand forward at contact
		b.pose_at("wield_idle", 0.0)
		var rest := b.socket_pos("weapon_r") if w != "bow" else b.socket_pos("offhand_l")
		b.pose_at("strike", b.contact_time("strike"))
		var hit := b.socket_pos("weapon_r") if w != "bow" else b.socket_pos("offhand_l")
		c.ok(hit.distance_to(rest) > 0.15, "%s strike contact moves the weapon hand (%.2f m)" % [w, hit.distance_to(rest)])
		# run cycle: the stance foot travels back while the other is lifted
		var d := b.duration("run")
		b.pose_at("run", 0.05 * d)
		var fl0 := b.bone_pos("foot_l")
		b.pose_at("run", 0.2 * d)
		var fl1 := b.bone_pos("foot_l")
		c.ok(fl1.z < fl0.z - 0.2, "%s run: left foot travels back in stance (%.2f -> %.2f)" % [w, fl0.z, fl1.z])
		c.ok(fl0.y < 0.25, "%s run: left foot on the ground at contact (%.2f)" % [w, fl0.y])
		b.pose_at("run", 0.65 * d)
		c.ok(b.bone_pos("foot_l").y > 0.25, "%s run: left foot lifted mid-swing (%.2f)" % [w, b.bone_pos("foot_l").y])
		b.free()


func test_bow_nocks_the_arrow(c: HHSelfTest.HHCheck) -> void:
	var b := _body("bow")
	if b == null:
		c.ok(false, "bow body")
		return
	c.ok(b.arrow != null, "arrow instanced")
	b.pose_at("wield_idle", 0.5)
	c.ok(b.arrow != null and not b.arrow.visible, "no arrow at idle")
	b.pose_at("draw", 0.5)
	c.ok(b.arrow != null and b.arrow.visible, "arrow nocked in the draw")
	var hr := b.socket_pos("weapon_r")
	var hl := b.socket_pos("offhand_l")
	c.ok(hr.z < hl.z, "draw: the string hand behind the bow hand")
	c.ok(hr.distance_to(hl) > 0.3, "draw: a real pull (%.2f m)" % hr.distance_to(hl))
	b.free()


func test_event_map(c: HHSelfTest.HHCheck) -> void:
	var arena := HHArena.round_flat(1, 20.0, 0.0)
	var sim := HHSim.new(arena, 1)
	var u := sim.add_player("p1", Vector2i(10, 10))
	var mon := sim.add_monster("m", Vector2i(13, 10), 1000.0, 1)
	for w in WEAPONS:
		var b := _body(w)
		if b == null:
			c.ok(false, "body for %s" % w)
			continue
		b.bind(sim, "p1")
		b.update(0.016)
		c.eq(b.clip, "idle", "%s starts idle" % w)
		# a target arms the stance
		u.target = "m"
		b.update(0.016)
		c.eq(b.clip, "wield_idle", "%s target -> wield_idle" % w)
		u.target = ""
		# windup basic -> strike held at contact, strike releases it
		b.on_event({ "type": "windup", "id": "p1", "kind": "basic", "ticks": int(CONTACTS[w]) }, sim)
		c.eq(b.clip, "strike", "%s windup -> strike" % w)
		for i in 40:
			b.update(HHSim.TICK)
		c.near(b.time, b.contact_time("strike"), 0.02, "%s strike holds at contact" % w)
		b.on_event({ "type": "strike", "id": "p1", "target": "m", "amount": 90.0 }, sim)
		for i in 3:
			b.update(HHSim.TICK)
		c.ok(b.time > b.contact_time("strike") + 0.03, "%s strike event releases the hold" % w)
		for i in 60:
			b.update(HHSim.TICK)
		c.eq(b.clip, "idle", "%s strike returns to the loop" % w)
		# casts
		for k in ["q", "e"]:
			b.on_event({ "type": "cast", "id": "p1", "skill": k, "name": k }, sim)
			var want := HHPlayerBody.skill_clip(w, k)
			if w == "lance" and k == "q":
				b.on_event({ "type": "windup", "id": "p1", "kind": "pierce", "ticks": 10 }, sim)
			c.eq(b.clip, want, "%s cast %s -> %s" % [w, k, want])
			if want == "guard":
				u.guard = 60
				for i in 10:
					b.update(HHSim.TICK)
				c.eq(b.clip, "guard", "%s guard holds while u.guard > 0" % w)
				u.guard = 0
				for i in 10:
					b.update(HHSim.TICK)
				c.ok(b.clip in ["idle", "wield_idle"], "%s guard ends with u.guard (%s)" % [w, b.clip])
			else:
				for i in 90:
					b.update(HHSim.TICK)
		# leap -> jump clip timed to the air, land -> the landing clip
		b.on_event({ "type": "leap", "id": "p1", "to": Vector2i(12, 10), "ticks": 26 }, sim)
		var leap_clip := HHPlayerBody.skill_clip(w, "r")
		c.eq(b.clip, leap_clip, "%s leap -> %s" % [w, leap_clip])
		c.near(b.duration(leap_clip) / b.speed, 26.0 * HHSim.TICK, 0.02, "%s leap clip spans the air time" % w)
		for i in 26:
			b.update(HHSim.TICK)
		b.on_event({ "type": "land", "id": "p1", "hex": Vector2i(12, 10) }, sim)
		var land_want := "slam" if w == "lance" else ("volley" if w == "bow" else "jump_attack")
		c.eq(b.clip, land_want, "%s land -> %s" % [w, land_want])
		for i in 60:
			b.update(HHSim.TICK)
		# stagger, hurt, swap, death
		b.on_event({ "type": "stagger", "id": "p1", "ticks": 20 }, sim)
		c.eq(b.clip, "stagger", "%s stagger" % w)
		for i in 60:
			b.update(HHSim.TICK)
		b.on_event({ "type": "hurt", "id": "p1", "amount": 10.0, "cause": "fire", "hp": 100.0 }, sim)
		c.ok(b.clip != "hit_react", "%s fire does not flinch" % w)
		b.on_event({ "type": "hurt", "id": "p1", "amount": 10.0, "cause": "bite", "hp": 100.0 }, sim)
		c.eq(b.clip, "hit_react", "%s a bite flinches" % w)
		for i in 30:
			b.update(HHSim.TICK)
		b.on_event({ "type": "swap", "id": "p1", "element": "water" }, sim)
		c.eq(b.clip, "swap", "%s swap" % w)
		for i in 40:
			b.update(HHSim.TICK)
		for e in ["move", "arrive", "blocked"]:
			b.on_event({ "type": e, "id": "p1" }, sim)
		c.eq(b.clip, "idle", "%s move events leave the loop alone" % w)
		b.on_event({ "type": "death", "id": "p1", "cause": "bite" }, sim)
		c.eq(b.clip, "death", "%s death" % w)
		for i in 90:
			b.update(HHSim.TICK)
		c.eq(b.clip, "death", "%s death holds" % w)
		b.free()
	c.ok(mon.id == "m", "monster placed")


func test_locomotion_follows_speed(c: HHSelfTest.HHCheck) -> void:
	var b := _body("lance")
	if b == null:
		c.ok(false, "body")
		return
	b.update(0.016)
	for i in 30:
		b.position += Vector3(0, 0, 8.0 * HHSim.TICK)
		b.update(HHSim.TICK)
	c.eq(b.clip, "run", "8 m/s runs")
	c.near(b.speed_mps, 8.0, 0.5, "speed read from the position delta")
	for i in 30:
		b.position += Vector3(0, 0, 5.5 * HHSim.TICK)
		b.update(HHSim.TICK)
	c.eq(b.clip, "walk", "5.5 m/s walks")
	for i in 30:
		b.update(HHSim.TICK)
	c.eq(b.clip, "idle", "standing idles")
	b.free()
