extends RefCounted
## Lane E: the Swampfang manifest, body, clip table and brain.

const REQUIRED_CLIPS := ["calm_float", "aggravated_idle", "frill_roar", "walk", "hit_react", "stagger", "collapse",
	"death", "dark_spray", "water_jet", "thrash_splash", "death_roll_spin", "dive", "swim", "surface_lunge", "bite_back_miss"]
const ATTACK_CLIPS := ["dark_spray", "water_jet", "thrash_splash", "death_roll_spin", "surface_lunge"]


func _sim(seed: int, player_hex: Vector2i, monster_hex: Vector2i) -> Array:
	var a := HHArena.round_flat(seed, 25.0, 0.6)
	var s := HHSim.new(a, seed)
	s.add_player("p1", player_hex)
	var m := s.add_monster("swampfang", monster_hex, 20000.0, 2)
	var brain := HHSwampfang.new("swampfang")
	return [s, brain, m]


## Run `ticks` ticks; `script` = { tick: order } for p1, `hurts` = { tick: fraction of max hp to take }.
func _run(s: HHSim, brain: HHSwampfang, m: Dictionary, ticks: int, script: Dictionary = {}, hurts: Dictionary = {}) -> Array:
	var events: Array = []
	for i in ticks:
		var orders := {}
		if script.has(s.tick + 1):
			orders["p1"] = script[s.tick + 1]
		s.step(orders)
		if hurts.has(s.tick):
			s.hurt(m, float(m.max_hp) * float(hurts[s.tick]), "test")
		brain.tick(s, m)
		events.append_array(s.events)      # step() returns sim.events; the brain's emits land there too
	return events


func test_manifest(c: HHSelfTest.HHCheck) -> void:
	c.ok(FileAccess.file_exists("res://art/monsters/swampfang.glb"), "swampfang.glb built")
	var row := HHMonsterBody.manifest_row("swampfang")
	c.ok(not row.is_empty(), "manifest row present")
	if row.is_empty():
		return
	for s in ["mouth", "frill", "back", "tail_tip"]:
		c.ok((row.sockets as Dictionary).has(s), "socket %s in manifest" % s)
	c.ok(int(row.tris) > 0 and int(row.tris) < 6000, "tris under 6000 (%d)" % int(row.tris))
	c.eq(int(row.footprint_hexes), 2, "radius-2 footprint")
	var L := float(row.length)
	c.ok(L >= 7.0 and L <= 10.0, "7-10 m long (%.2f)" % L)
	c.ok(float(row.height) > 2.2, "taller than the player rig (%.2f)" % float(row.height))
	var names: Array = (row.bones as Array).map(func(b): return str(b.name))
	for b in ["root", "hips", "spine_0", "chest", "neck", "head", "jaw", "tail_0", "tail_3", "frill_l", "frill_r",
			"hip_fl", "knee_fl", "ankle_fl", "toe_fl", "hip_hr", "toe_hr"]:
		c.ok(b in names, "bone %s" % b)
	c.eq(str(row.jaw), "jaw", "jaw bone named")
	c.ok((row.legs as Dictionary).has("fl") and str(row.legs.fl.ik) == "ik_fl", "leg fl with ik target")
	c.ok((row.chains as Dictionary).has("spine") and (row.chains as Dictionary).has("tail"), "spine and tail chains")


func test_body_loads_and_poses(c: HHSelfTest.HHCheck) -> void:
	var b := HHMonsterBody.new()
	var ok := b.build("swampfang")
	c.ok(ok, "body builds from the glb")
	if not ok:
		b.free()
		return
	c.ok(b.skeleton != null and b.skeleton.get_bone_count() >= 20, "skeleton with bones (%d)" % (b.skeleton.get_bone_count() if b.skeleton else 0))
	c.ok(b.triangle_count() > 0 and b.triangle_count() < 6000, "mesh tris under budget (%d)" % b.triangle_count())
	for s in ["mouth", "frill", "back", "tail_tip", "ik_fl", "ik_hr"]:
		c.ok(b.socket(s) != null, "socket node %s" % s)
	c.ok(b.has_bone("jaw") and b.has_bone("frill_l") and b.has_bone("tail_3"), "named bones found")
	var rest := b.socket_pos("mouth")
	c.ok(rest.z > 3.0 and rest.y > 0.8, "mouth socket forward and up at rest (%s)" % rest)
	c.ok(b.socket_pos("tail_tip").z < -3.0, "tail tip behind")
	for clip in REQUIRED_CLIPS:
		var key := float(HHSwampfangClips.CLIPS[clip].key)
		c.ok(b.pose_at(clip, key), "pose_at %s" % clip)
	b.pose_at("frill_roar", 0.95)
	var roar := b.socket_pos("mouth")
	c.ok(roar.distance_to(rest) > 0.2, "frill_roar moves the mouth (%.2f m)" % roar.distance_to(rest))
	b.pose_at("dive", 1.8)
	c.ok(b.bone_pos("hips").y < rest.y - 1.0, "dive sinks the body")
	b.play("aggravated_idle")
	b.play("dark_spray", false)
	for i in 80:
		b.update(1.0 / 30.0)
	c.eq(b.clip, "aggravated_idle", "a one-shot returns to the loop it cut")
	b.free()


func test_clip_table(c: HHSelfTest.HHCheck) -> void:
	var clips := HHMonsterBody.clips("swampfang")
	var listed := HHMonsterBody.clip_list("swampfang")
	for name in REQUIRED_CLIPS:
		c.ok(clips.has(name), "clip %s present" % name)
		c.ok(name in listed, "clip %s listed" % name)
		if not clips.has(name):
			continue
		var e: Dictionary = clips[name]
		c.ok(float(e.duration) > 0.0, "%s duration > 0" % name)
		var ct := int(e.contact_tick)
		c.ok(ct == -1 or float(ct) * HHSim.TICK < float(e.duration), "%s contact tick within duration" % name)
	for name in ATTACK_CLIPS:
		var ct := int(clips[name].contact_tick)
		c.ok(ct >= 24 and ct <= 48, "%s contact tick in the 0.8-1.6 s telegraph window (%d)" % [name, ct])
	c.eq(HHSwampfangClips.clip_list().size(), clips.size(), "clip_list matches CLIPS")


func test_rear_mult(c: HHSelfTest.HHCheck) -> void:
	var u := { "hex": Vector2i(0, 0), "facing": 0.0 }      # faces +Z (rows increasing)
	c.near(HHSwampfang.rear_mult(u, Vector2i(0, 4)), 1.0, 1e-6, "in front: 1.0")
	c.near(HHSwampfang.rear_mult(u, Vector2i(0, -4)), 1.5, 1e-6, "behind: 1.5")
	c.near(HHSwampfang.rear_mult(u, Vector2i(4, 0)), 1.0, 1e-6, "beside: 1.0")
	u.facing = PI                                           # turned round
	c.near(HHSwampfang.rear_mult(u, Vector2i(0, 4)), 1.5, 1e-6, "turned: what was in front is behind")
	c.ok(HHSwampfang.is_behind(u, Vector2i(0, 4)), "is_behind agrees")
	c.ok(HHSwampfang.TUNE.has("attack_gap_ticks") and HHSwampfang.TUNE.has("rear_mult"), "feel numbers in TUNE")


func test_phases_script(c: HHSelfTest.HHCheck) -> void:
	var st := HHPhases.start(HHSwampfang.phases())
	c.eq(HHPhases.check(st, 1.0, 1).size(), 0, "calm at full hp")
	c.eq(HHPhases.check(st, 0.9, 2), ["aggravated"], "aggravated on first damage")
	c.eq(HHPhases.check(st, 0.45, 3), ["threatened"], "threatened below 0.5")
	c.ok(bool(HHPhases.rule(st, "dive")), "threatened turns the dive on")
	c.eq(HHPhases.check(st, 0.2, 4), ["enraged"], "enraged below 0.25")
	c.ok(float(HHPhases.rule(st, "gap_mult")) < 1.0, "enrage shortens the gap")


func test_calm_until_close(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(3, Vector2i(0, 10), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSwampfang = r[1]
	var m: Dictionary = r[2]
	var ev := _run(s, brain, m, 120)
	c.eq(brain.state, "calm", "stays calm with the player 14 hexes away")
	c.eq(brain.anim, "calm_float", "floats")
	c.ok(brain.attacks.is_empty(), "no attacks while calm")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "calm_float"), "monster_anim event")
	_run(s, brain, m, 400, { s.tick + 1: { "move": Vector2i(0, 2) } })
	c.ok(brain.state != "calm", "aggravated when the player closes to %d hexes" % HHHex.distance(m.hex, s.unit("p1").hex))
	c.ok(ev.size() > 0, "events flowed")


func test_attacks_and_fallback_telegraph(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(5, Vector2i(0, -2), Vector2i(0, -6))      # 4 hexes from the centre: touching the footprint + 1
	var s: HHSim = r[0]
	var brain: HHSwampfang = r[1]
	var m: Dictionary = r[2]
	var ev := _run(s, brain, m, 900)
	c.ok(brain.attacks.size() >= 2, "attacks issued (%d)" % brain.attacks.size())
	var p := s.unit("p1")
	c.ok(float(p.hp) < float(p.max_hp), "the fallback telegraph landed damage (hp %d)" % int(p.hp))
	c.ok(ev.any(func(e): return e.type == "telegraph"), "telegraph events emitted")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "frill_roar"), "roared on aggravation")
	for a in brain.attacks:
		c.ok(not (a.hexes as Array).is_empty(), "%s has a danger shape" % a.clip)
		for h in a.hexes:
			c.ok(HHHex.distance(m.hex, h) > int(m.size) or a.clip == "surface_lunge", "%s never targets its own footprint" % a.clip)
		c.ok(a.ticks >= 24 and a.ticks <= 48, "%s telegraph window 24-48 ticks (%d)" % [a.clip, a.ticks])


func test_cadence(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(11, Vector2i(0, -2), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSwampfang = r[1]
	var m: Dictionary = r[2]
	_run(s, brain, m, 1500, {}, { 400: 0.3, 700: 0.3 })
	c.ok(brain.attacks.size() >= 3, "several attacks (%d)" % brain.attacks.size())
	var gap := int(HHSwampfang.TUNE.attack_gap_ticks)
	for i in range(1, brain.attacks.size()):
		var prev: Dictionary = brain.attacks[i - 1]
		var next: Dictionary = brain.attacks[i]
		var rest := int(next.tick) - (int(prev.tick) + int(prev.ticks))
		c.ok(rest >= gap, "%s -> %s: %d ticks after the previous contact (min %d)" % [prev.clip, next.clip, rest, gap])


func test_goals_fit(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(13, Vector2i(6, 9), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSwampfang = r[1]
	var m: Dictionary = r[2]
	_run(s, brain, m, 1200, { 1: { "move": Vector2i(-8, 12) }, 500: { "move": Vector2i(9, -10) } }, { 300: 0.6 })
	c.ok(brain.goals.size() >= 2, "goals chosen (%d)" % brain.goals.size())
	for g in brain.goals:
		var fits := true
		for h in HHHex.area(g, int(m.size)):
			if not s.arena.walkable(h) or not str(s.arena.kind(h)) in HHSwampfang.ALLOWED_KINDS:
				fits = false
		c.ok(fits, "goal %s is walkable for the footprint" % g)
	c.ok(s.arena.walkable(m.hex), "monster stands on a walkable hex")


func test_bite_back_miss(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(17, Vector2i(0, -9), Vector2i(0, -6))     # directly behind (facing +Z), touching
	var s: HHSim = r[0]
	var brain: HHSwampfang = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")                                 # aggravate
	var ev := _run(s, brain, m, 200)
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "bite_back_miss"), "bites backward and misses")
	c.near(HHSwampfang.rear_mult(m, Vector2i(0, -9)), 1.5, 1e-6, "the player there takes the rear multiplier")


func test_dive_swim_surface(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(19, Vector2i(0, -2), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSwampfang = r[1]
	var m: Dictionary = r[2]
	var ev := _run(s, brain, m, 100)
	ev.append_array(_run(s, brain, m, 1200, {}, { 110: 0.6 }))
	c.eq(brain.state, "threatened", "threatened below half")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "dive"), "dived")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "swim"), "swam")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "surface_lunge"), "surfaced with a lunge")
	c.ok(ev.any(func(e): return e.type == "telegraph" and bool(e.payload.get("ripple", false))), "ripples marked the surface hex")
	c.ok(brain.attacks.any(func(a): return a.clip == "surface_lunge"), "the lunge is a telegraph")
	c.eq(bool(m.untargetable), false, "targetable again after surfacing")
	c.ok(s.arena.walkable(m.hex), "surfaced on a walkable hex")


func test_deterministic(c: HHSelfTest.HHCheck) -> void:
	var hashes: Array = []
	var hexes: Array = []
	var hps: Array = []
	var counts: Array = []
	for k in 2:
		var r := _sim(23, Vector2i(2, 9), Vector2i(0, -6))
		var s: HHSim = r[0]
		var brain: HHSwampfang = r[1]
		var m: Dictionary = r[2]
		_run(s, brain, m, 600, { 1: { "move": Vector2i(0, -1) }, 250: { "move": Vector2i(6, 2), "run": true } }, { 120: 0.55 })
		hashes.append(s.state_hash())
		hexes.append(m.hex)
		hps.append(int(s.unit("p1").hp))
		counts.append(brain.attacks.size())
	c.eq(hexes[0], hexes[1], "same monster hex after 600 ticks")
	c.eq(hps[0], hps[1], "same player hp")
	c.eq(hashes[0], hashes[1], "same state hash")
	c.eq(counts[0], counts[1], "same attack count (%d)" % int(counts[0]))
	c.ok(int(counts[0]) > 0, "the fight happened")
