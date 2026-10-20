extends RefCounted
## Lane E: the Spirewalker manifest, body, clip table and brain.

const REQUIRED_CLIPS := ["calm_soak", "aggravated_idle", "walk", "reeds_fold", "leaping_squash", "forearm_punch", "bite",
	"barb_throw", "reed_lash", "tail_drag", "pollen_shake", "thunder_breath", "dark_breath", "spore_spread",
	"hit_react", "stagger", "collapse", "death", "reeds_burnt_idle"]
const ATTACK_CLIPS := ["leaping_squash", "forearm_punch", "bite", "barb_throw", "reed_lash", "tail_drag", "pollen_shake",
	"thunder_breath", "dark_breath", "spore_spread"]


func _sim(seed: int, player_hex: Vector2i, monster_hex: Vector2i) -> Array:
	var a := HHArena.round_flat(seed, 25.0, 0.6)
	var s := HHSim.new(a, seed)
	s.add_player("p1", player_hex)
	var brain := HHSpirewalker.new("spirewalker")
	var m := s.add_monster("spirewalker", monster_hex, 20000.0, 2, brain.allowed_kinds())
	return [s, brain, m]


## Run `ticks` ticks; `script` = { tick: order } for p1, `hurts` = { tick: fraction of max hp to take }.
func _run(s: HHSim, brain: HHSpirewalker, m: Dictionary, ticks: int, script: Dictionary = {}, hurts: Dictionary = {}) -> Array:
	var events: Array = []
	for i in ticks:
		var orders := {}
		if script.has(s.tick + 1):
			orders["p1"] = script[s.tick + 1]
		s.step(orders)
		if hurts.has(s.tick):
			s.hurt(m, float(m.max_hp) * float(hurts[s.tick]), "test")
		brain.tick(s, m)
		events.append_array(s.events)
	return events


func test_manifest(c: HHSelfTest.HHCheck) -> void:
	c.ok(FileAccess.file_exists("res://art/monsters/spirewalker.glb"), "spirewalker.glb built")
	var row := HHMonsterBody.manifest_row("spirewalker")
	c.ok(not row.is_empty(), "manifest row present")
	c.ok(not HHMonsterBody.manifest_row("swampfang").is_empty(), "the swampfang row survived the append")
	if row.is_empty():
		return
	for s in ["mouth", "back", "reeds", "tail_tip", "arm_l", "arm_r"]:
		c.ok((row.sockets as Dictionary).has(s), "socket %s in manifest" % s)
	c.ok(int(row.tris) > 0 and int(row.tris) < 7000, "tris under 7000 (%d)" % int(row.tris))
	c.eq(int(row.footprint_hexes), 2, "radius-2 footprint")
	var W := float(row.width)
	c.ok(W >= 6.0 and W <= 9.0, "6-9 m across (%.2f)" % W)
	c.ok(float(row.height) > 2.2, "reeds rise past the player rig (%.2f)" % float(row.height))
	c.ok(float(row.height) < 4.5, "but not a tower (%.2f)" % float(row.height))
	var names: Array = (row.bones as Array).map(func(b): return str(b.name))
	for b in ["root", "hips", "spine_0", "spine_1", "chest", "neck", "head", "jaw", "tail_0", "tail_2",
			"reed_0", "reed_1", "reed_2", "hip_fl", "knee_fl", "ankle_fl", "toe_fl", "hip_ml", "hip_mr", "hip_hl", "toe_hr"]:
		c.ok(b in names, "bone %s" % b)
	c.eq((row.legs as Dictionary).size(), 6, "six legs")
	c.eq(str(row.jaw), "jaw", "jaw bone named")
	c.eq(Array(row.reeds), ["reed_0", "reed_1", "reed_2"], "reed row bones listed")
	c.ok((row.chains as Dictionary).has("spine") and (row.chains as Dictionary).has("tail"), "spine and tail chains")


func test_body_loads_and_poses(c: HHSelfTest.HHCheck) -> void:
	var b := HHMonsterBody.new()
	var ok := b.build("spirewalker")
	c.ok(ok, "body builds from the glb")
	if not ok:
		b.free()
		return
	c.ok(b.skeleton != null and b.skeleton.get_bone_count() >= 36, "skeleton with bones (%d)" % (b.skeleton.get_bone_count() if b.skeleton else 0))
	c.ok(b.triangle_count() > 0 and b.triangle_count() < 7000, "mesh tris under budget (%d)" % b.triangle_count())
	for s in ["mouth", "back", "reeds", "tail_tip", "arm_l", "ik_fl", "ik_mr", "ik_hl"]:
		c.ok(b.socket(s) != null, "socket node %s" % s)
	c.ok(b.has_bone("reed_1") and b.has_bone("hip_ml") and b.has_bone("tail_2"), "named bones found")
	var mouth := b.socket_pos("mouth")
	c.ok(mouth.z > 3.0 and mouth.y > 0.3, "mouth socket forward and low at rest (%s)" % mouth)
	c.ok(b.socket_pos("tail_tip").z < -2.5, "tail tip behind")
	var reeds := b.socket_pos("reeds")
	c.ok(reeds.y > 2.5, "reeds socket stands high at rest (%.2f)" % reeds.y)
	c.ok(absf(b.socket_pos("arm_l").x) > 2.0 and b.socket_pos("arm_l").x > 0.0, "left arm socket out on the left")
	for clip in REQUIRED_CLIPS:
		var key := float(HHSpirewalkerClips.CLIPS[clip].key)
		c.ok(b.pose_at(clip, key), "pose_at %s" % clip)
	b.pose_at("reeds_fold", 0.8)
	var folded := b.socket_pos("reeds")
	c.ok(folded.y < reeds.y - 0.8, "reeds_fold lays the bed flat (socket y %.2f -> %.2f)" % [reeds.y, folded.y])
	b.pose_at("leaping_squash", 1.25)
	c.ok(b.bone_pos("hips").y < 1.0, "the squash lands the body low (hips y %.2f)" % b.bone_pos("hips").y)
	b.pose_at("bite", 0.9)
	c.ok(b.socket_pos("mouth").distance_to(mouth) > 0.2, "bite moves the mouth")
	b.play("aggravated_idle")
	b.play("forearm_punch", false)
	for i in 80:
		b.update(1.0 / 30.0)
	c.eq(b.clip, "aggravated_idle", "a one-shot returns to the loop it cut")
	b.free()


func test_clip_table(c: HHSelfTest.HHCheck) -> void:
	var clips := HHMonsterBody.clips("spirewalker")
	var listed := HHMonsterBody.clip_list("spirewalker")
	for name in REQUIRED_CLIPS:
		c.ok(clips.has(name), "clip %s present" % name)
		c.ok(name in listed, "clip %s listed" % name)
		if not clips.has(name):
			continue
		var e: Dictionary = clips[name]
		c.ok(float(e.duration) > 0.0, "%s duration > 0" % name)
		c.ok(e.has("loop") and e.has("key") and e.has("note"), "%s carries loop, key, note" % name)
		var ct := int(e.contact_tick)
		c.ok(ct == -1 or float(ct) * HHSim.TICK < float(e.duration), "%s contact tick within duration" % name)
	for name in ATTACK_CLIPS:
		var ct := int(clips[name].contact_tick)
		c.ok(ct >= 24 and ct <= 48, "%s contact tick in the 0.8-1.6 s band (%d)" % [name, ct])
	c.eq(HHSpirewalkerClips.clip_list().size(), clips.size(), "clip_list matches CLIPS")
	c.eq(clips.size(), REQUIRED_CLIPS.size(), "no extra clips")


func test_rear_mult_and_tune(c: HHSelfTest.HHCheck) -> void:
	var u := { "hex": Vector2i(0, 0), "facing": 0.0 }      # faces +Z
	c.near(HHSpirewalker.rear_mult(u, Vector2i(0, 4)), 1.0, 1e-6, "in front: 1.0")
	c.near(HHSpirewalker.rear_mult(u, Vector2i(0, -4)), 1.5, 1e-6, "behind (the reeds): 1.5")
	c.near(HHSpirewalker.rear_mult(u, Vector2i(4, 0)), 1.0, 1e-6, "beside: 1.0")
	u.facing = PI
	c.near(HHSpirewalker.rear_mult(u, Vector2i(0, 4)), 1.5, 1e-6, "turned: what was in front is behind")
	u.reeds_burnt = true
	c.near(HHSpirewalker.rear_mult(u, Vector2i(0, -4)), 1.5, 1e-6, "reeds cut: 1.5 from the front too")
	c.ok(HHSpirewalker.TUNE.has("attack_gap_ticks") and HHSpirewalker.TUNE.has("windup_mult") and HHSpirewalker.TUNE.has("pollen_threshold"), "feel numbers in TUNE")
	c.near(float(HHSpirewalker.TUNE.windup_mult), 1.8, 1e-6, "H38 wind-up multiplier")
	var brain := HHSpirewalker.new()
	var kinds := brain.allowed_kinds()
	c.ok("floor" in kinds and "sun" in kinds and "shade" in kinds and "vent" in kinds and "water" in kinds, "allowed kinds")
	c.ok(not "lava" in kinds and not "rock" in kinds and not "pillar" in kinds and not "tree" in kinds, "never lava, rock, pillar, tree")


func test_phases_script(c: HHSelfTest.HHCheck) -> void:
	var st := HHPhases.start(HHSpirewalker.phases())
	c.eq(HHPhases.check(st, 1.0, 1).size(), 0, "calm at full hp")
	c.eq(HHPhases.check(st, 0.9, 2), ["aggravated"], "aggravated on first damage")
	c.eq(HHPhases.check(st, 0.4, 3).size(), 0, "nothing between 0.25 and 1.0")
	c.eq(HHPhases.check(st, 0.2, 4), ["enraged"], "enraged below 0.25")
	c.ok(float(HHPhases.rule(st, "gap_mult")) < 1.0, "enrage shortens the gap")
	c.ok(float(HHPhases.rule(st, "squash_chance")) > float(HHSpirewalker.TUNE.squash_chance), "enrage squashes more")


func test_calm_until_close(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(3, Vector2i(0, 12), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	var ev := _run(s, brain, m, 120)
	c.eq(brain.state, "calm", "stays calm with the player 16 hexes away")
	c.eq(brain.anim, "calm_soak", "soaks")
	c.ok(brain.attacks.is_empty(), "no attacks while calm")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "calm_soak"), "monster_anim event")
	_run(s, brain, m, 400, { s.tick + 1: { "move": Vector2i(0, 3) } })
	c.ok(brain.state != "calm", "aggravated when the player closes to %d hexes" % HHHex.distance(m.hex, s.unit("p1").hex))
	c.ok(ev.size() > 0, "events flowed")


func test_charge_meter(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(7, Vector2i(0, 12), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	_run(s, brain, m, 150)
	var floor_charge := float(m.charge)
	c.ok(floor_charge > 0.1 and floor_charge < 0.5, "charge rises on the floor (%.3f after 150 ticks)" % floor_charge)
	c.eq(brain.charged, false, "not yet charged")
	var r2 := _sim(7, Vector2i(0, 12), Vector2i(0, -6))
	var s2: HHSim = r2[0]
	var brain2: HHSpirewalker = r2[1]
	var m2: Dictionary = r2[2]
	s2.arena.cells[m2.hex].kind = "sun"
	var ev := _run(s2, brain2, m2, 150)
	c.ok(float(m2.charge) > floor_charge * 2.5, "charges faster on a sun cell (%.3f vs %.3f)" % [float(m2.charge), floor_charge])
	c.ok(float(m2.charge) > float(HHSpirewalker.TUNE.pollen_threshold) and brain2.charged, "charged past the threshold")
	c.ok(ev.any(func(e): return e.type == "monster_state" and e.state == "charged"), "charged state event")
	_run(s2, brain2, m2, 600)
	c.near(float(m2.charge), 1.0, 1e-6, "charge caps at 1")


func test_attacks_and_shapes(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(5, Vector2i(0, -2), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	var ev := _run(s, brain, m, 900)
	c.ok(brain.attacks.size() >= 2, "attacks issued (%d)" % brain.attacks.size())
	var p := s.unit("p1")
	c.ok(float(p.hp) < float(p.max_hp), "telegraphs landed damage (hp %d)" % int(p.hp))
	c.ok(ev.any(func(e): return e.type == "telegraph"), "telegraph events emitted")
	c.ok(ev.any(func(e): return e.type == "monster_state" and e.state == "aggravated"), "aggravated state event")
	for a in brain.attacks:
		c.ok(not (a.hexes as Array).is_empty(), "%s has a danger shape" % a.clip)
		if a.clip in ["barb_throw", "reed_lash", "thunder_breath", "dark_breath", "spore_spread", "tail_drag", "pollen_shake"]:
			for h in a.hexes:
				c.ok(HHHex.distance(a.at, h) > int(m.size), "%s shape outside the footprint" % a.clip)
		c.ok(a.ticks >= int(HHSpirewalker.TUNE.telegraph_min_ticks) and a.ticks <= int(HHSpirewalker.TUNE.telegraph_max_ticks), "%s window inside TUNE (%d)" % [a.clip, a.ticks])
		var contact := int(HHSpirewalkerClips.CLIPS[a.clip].contact_tick)
		c.eq(int(a.ticks), clampi(int(round(contact * 1.8)), 40, 90), "%s window = contact x1.8 clamped" % a.clip)
	var slowed: Array = ev.filter(func(e): return e.type == "monster_anim" and float(e.get("speed", 1.0)) < 1.0)
	c.ok(not slowed.is_empty(), "attack clips play slowed to match the window")


func test_cadence(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(11, Vector2i(0, -2), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	_run(s, brain, m, 1500, {}, { 400: 0.3, 700: 0.3 })
	c.ok(brain.attacks.size() >= 3, "several attacks (%d)" % brain.attacks.size())
	var gap := int(ceil(float(HHSpirewalker.TUNE.attack_gap_ticks) * 0.75))
	for i in range(1, brain.attacks.size()):
		var prev: Dictionary = brain.attacks[i - 1]
		var next: Dictionary = brain.attacks[i]
		var rest := int(next.tick) - (int(prev.tick) + int(prev.ticks))
		c.ok(rest >= gap, "%s -> %s: %d ticks after the previous contact (min %d)" % [prev.clip, next.clip, rest, gap])


func test_squash_relocates(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(13, Vector2i(0, -1), Vector2i(0, -6))     # 5 hexes from the centre: edge distance 3
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	brain.force_attack = "leaping_squash"
	var start: Vector2i = m.hex
	var ev := _run(s, brain, m, 100)           # window ~65 ticks; the clip holds it until ~130
	var sq: Array = brain.attacks.filter(func(a): return a.clip == "leaping_squash")
	c.eq(sq.size(), 1, "one squash issued")
	if sq.is_empty():
		return
	var a: Dictionary = sq[0]
	c.ok(a.ticks >= 60, "the squash is telegraphed ~2 s (%d ticks)" % a.ticks)
	c.ok((a.hexes as Array).has(Vector2i(0, -1)), "the area is at the player's hex")
	c.eq((a.hexes as Array).size(), HHHex.area(Vector2i(0, -1), 2).size(), "radius-2 area")
	c.ok(ev.any(func(e): return e.type == "leap" and e.id == "spirewalker"), "the unit flew (leap event)")
	c.ok(ev.any(func(e): return e.type == "land" and e.id == "spirewalker"), "and landed (land event)")
	c.eq(m.hex, Vector2i(0, -1), "it stands at the landing hex after contact")
	c.ok(m.hex != start, "moved from %s" % start)
	c.eq(brain.squashes_landed, 1, "landing counted")
	c.eq(bool(m.untargetable), false, "targetable again on the ground")
	var tg_end: Array = ev.filter(func(e): return e.type == "telegraph_end" and str(e.name) == "leaping_squash")
	var land: Array = ev.filter(func(e): return e.type == "land" and e.id == "spirewalker")
	c.ok(not tg_end.is_empty() and not land.is_empty() and absi(int(tg_end[0].tick) - int(land[0].tick)) <= 1, "contact and landing on the same tick")
	c.ok(float(s.unit("p1").hp) < float(s.unit("p1").max_hp), "the standing player was squashed")


func test_squash_lands_where_it_fits(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(13, Vector2i(0, 15), Vector2i(0, 8))      # the player stands on the last walkable row
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	var p := s.unit("p1")
	c.ok(s.arena.walkable(p.hex), "player hex walkable")
	s.hurt(m, 10.0, "test")
	brain.force_attack = "leaping_squash"
	_run(s, brain, m, 150)
	var sq: Array = brain.attacks.filter(func(a): return a.clip == "leaping_squash")
	c.ok(not sq.is_empty(), "squash issued near the edge")
	for h in HHHex.area(m.hex, int(m.size)):
		c.ok(s.arena.walkable(h), "footprint hex %s walkable after landing" % h)
	c.ok(m.hex != Vector2i(0, 15) and HHHex.distance(m.hex, Vector2i(0, 15)) <= 3, "landed as near the player as fits (%d away)" % HHHex.distance(m.hex, Vector2i(0, 15)))


func test_pollen_only_when_charged(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(17, Vector2i(0, -2), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	for i in 400:
		s.step({})
		m.charge = 0.0                                          # held at zero: never charged
		brain.tick(s, m)
	c.eq(brain.pollens, 0, "no pollen without charge over %d attacks" % brain.attacks.size())
	c.ok(not brain.attacks.any(func(a): return a.clip == "pollen_shake"), "no pollen_shake clip")
	m.charge = 1.0
	var spent_ok := false
	var fired_at := -1
	for i in 900:
		s.step({})
		brain.tick(s, m)
		if brain.pollens == 1 and fired_at < 0:
			fired_at = s.tick
			spent_ok = float(m.charge) < 0.01 and not brain.charged
	c.eq(brain.pollens, 1, "pollen once when charged")
	c.ok(spent_ok, "pollen spends the charge")
	c.ok(brain.attacks.any(func(a): return a.clip == "pollen_shake"), "pollen_shake clip issued")


func test_slow_then_paralysis(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(19, Vector2i(0, -2), Vector2i(0, -6))      # 4 from the centre: inside the radius-3 cloud
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	m.charge = 1.0
	brain.force_attack = "pollen_shake"
	var ev := _run(s, brain, m, 320)
	var p := s.unit("p1")
	var slow: Array = ev.filter(func(e): return e.type == "status" and e.id == "p1" and e.status == "slow")
	var poison: Array = ev.filter(func(e): return e.type == "status" and e.id == "p1" and e.status == "poison")
	var para: Array = ev.filter(func(e): return e.type == "status" and e.id == "p1" and e.status == "paralysis")
	c.ok(brain.pollens == 1, "pollen shaken")
	c.ok(not slow.is_empty(), "the first pulse slows")
	c.ok(not poison.is_empty(), "the cloud poisons (dark)")
	c.ok(not para.is_empty(), "lingering paralyses")
	if not slow.is_empty() and not para.is_empty():
		c.ok(int(para[0].tick) > int(slow[0].tick), "slow first, paralysis later (t%d -> t%d)" % [int(slow[0].tick), int(para[0].tick)])
		c.ok(int(para[0].tick) - int(slow[0].tick) <= int(HHSpirewalker.TUNE.pollen_linger_ticks) + 4, "within the linger window")
	c.ok(ev.filter(func(e): return e.type == "telegraph" and str(e.name) == "pollen_shake").size() >= int(HHSpirewalker.TUNE.pollen_pulses), "the cloud pulsed")
	var painted := false
	for h in brain.attacks[0].hexes:
		if s.charge.intensity(h, "dark") >= 1:
			painted = true
	c.ok(painted, "the cloud painted dark 1")
	c.ok(float(p.hp) < float(p.max_hp), "and hurt")


func test_reed_weak_point(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(23, Vector2i(0, -9), Vector2i(0, -6))     # directly behind (facing +Z), touching
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	_run(s, brain, m, 2)
	m.charge = 0.3
	var ev := _run(s, brain, m, 3, {}, { s.tick + 2: 0.02 })
	c.eq(brain.reeds_burnt(s), false, "a rear hit under 0.5 charge leaves the reeds")
	m.charge = 0.8
	ev.append_array(_run(s, brain, m, 3, {}, { s.tick + 2: 0.02 }))
	c.eq(brain.reeds_burnt(s), true, "a rear hit while charged cuts the reeds")
	c.eq(bool(m.reeds_burnt), true, "u.reeds_burnt set")
	c.near(float(m.charge), 0.0, 1e-6, "charge lost")
	c.near(HHSpirewalker.rear_mult(m, Vector2i(0, 3)), 1.5, 1e-6, "takes x1.5 from the front while cut")
	c.ok(ev.any(func(e): return e.type == "monster_state" and e.state == "reeds_burnt"), "reeds_burnt state event")
	m.charge = 0.0
	ev = _run(s, brain, m, 300)
	c.eq(brain.reeds_burnt(s), true, "still cut at 10 s")
	c.ok(float(m.charge) < 1e-6, "no charge while cut")
	c.eq(brain.pollens, 0, "no pollen while cut")
	ev = _run(s, brain, m, 320)
	c.eq(brain.reeds_burnt(s), false, "regrown after 20 s")
	c.eq(bool(m.reeds_burnt), false, "u.reeds_burnt cleared")
	c.ok(ev.any(func(e): return e.type == "monster_state" and e.state == "reeds_regrown"), "regrown state event")
	c.ok(float(m.charge) > 0.0, "charging again")
	var r2 := _sim(23, Vector2i(0, -3), Vector2i(0, -6))    # in front
	var s2: HHSim = r2[0]
	var brain2: HHSpirewalker = r2[1]
	var m2: Dictionary = r2[2]
	_run(s2, brain2, m2, 2)
	m2.charge = 0.9
	_run(s2, brain2, m2, 3, {}, { s2.tick + 2: 0.02 })
	c.eq(brain2.reeds_burnt(s2), false, "a hit from the front never cuts the reeds")


func test_tail_drag_behind(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(29, Vector2i(0, -9), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	_run(s, brain, m, 200)
	var td: Array = brain.attacks.filter(func(a): return a.clip == "tail_drag")
	c.ok(not td.is_empty(), "a player behind draws the tail drag")
	if td.is_empty():
		return
	var at: Vector2i = td[0].at
	var facing := float(td[0].facing)
	var back := -Vector2(sin(facing), cos(facing))
	for h in td[0].hexes:
		var v: Vector2 = (HHHex.to_world(h, 1.0) - HHHex.to_world(at, 1.0)).normalized()
		c.ok(v.dot(back) >= cos(deg_to_rad(float(HHSpirewalker.TUNE.tail_arc_deg))) - 1e-6, "half ring hex %s is behind" % h)
		var dd := HHHex.distance(at, h)
		c.ok(dd > int(m.size) and dd <= int(m.size) + int(HHSpirewalker.TUNE.tail_ring), "half ring hex %s within reach" % h)
	var full := HHHex.area(at, 4).size() - HHHex.area(at, 2).size()
	c.ok((td[0].hexes as Array).size() < full and (td[0].hexes as Array).size() >= full / 4, "a half ring (%d of %d)" % [(td[0].hexes as Array).size(), full])


func test_barbs_leave_fuse_markers(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(31, Vector2i(0, 0), Vector2i(0, -6))      # 6 from the centre
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	brain.force_attack = "barb_throw"
	var ev := _run(s, brain, m, 140)
	var bt: Array = brain.attacks.filter(func(a): return a.clip == "barb_throw")
	c.eq(bt.size(), 1, "barbs thrown")
	if bt.is_empty():
		return
	var hexes: Array = bt[0].hexes
	c.eq(hexes.size(), 3, "three single-hex projectiles")
	c.ok(hexes.has(Vector2i(0, 0)), "one lands on the player's hex")
	var tgs: Array = ev.filter(func(e): return e.type == "telegraph" and str(e.name) == "barb_throw")
	c.eq(tgs.size(), 3, "three separate telegraphs")
	for e in tgs:
		c.eq((e.hexes as Array).size(), 1, "each a single hex")
	var fuses := 0
	for h in hexes:
		if s.charge.marker(h) == "fuse":
			fuses += 1
	c.ok(fuses >= 2, "fuse markers where they landed (%d of 3)" % fuses)
	c.ok(float(s.unit("p1").hp) < float(s.unit("p1").max_hp), "a barb hit")


func test_goals_fit(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(37, Vector2i(6, 9), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHSpirewalker = r[1]
	var m: Dictionary = r[2]
	_run(s, brain, m, 1200, { 1: { "move": Vector2i(-8, 12) }, 500: { "move": Vector2i(9, -10) } }, { 300: 0.6 })
	c.ok(brain.goals.size() >= 2, "goals chosen (%d)" % brain.goals.size())
	for g in brain.goals:
		var fits := true
		for h in HHHex.area(g, int(m.size)):
			if not s.arena.walkable(h) or not str(s.arena.kind(h)) in HHSpirewalker.ALLOWED_KINDS:
				fits = false
		c.ok(fits, "goal %s is walkable for the footprint" % g)
	c.ok(s.arena.walkable(m.hex), "monster stands on a walkable hex")
	c.ok(brain.attacks.size() >= 3, "kept attacking on the move (%d)" % brain.attacks.size())


func test_deterministic(c: HHSelfTest.HHCheck) -> void:
	var hashes: Array = []
	var hexes: Array = []
	var hps: Array = []
	var counts: Array = []
	var charges: Array = []
	for k in 2:
		var r := _sim(41, Vector2i(2, 9), Vector2i(0, -6))
		var s: HHSim = r[0]
		var brain: HHSpirewalker = r[1]
		var m: Dictionary = r[2]
		s.arena.cells[Vector2i(0, -6)].kind = "sun"
		_run(s, brain, m, 900, { 1: { "move": Vector2i(0, -1) }, 250: { "move": Vector2i(6, 2), "run": true }, 600: { "move": Vector2i(0, -10) } }, { 120: 0.55, 500: 0.25 })
		hashes.append(s.state_hash())
		hexes.append(m.hex)
		hps.append(int(s.unit("p1").hp))
		counts.append(brain.attacks.size())
		charges.append(float(m.charge))
	c.eq(hexes[0], hexes[1], "same monster hex after 900 ticks")
	c.eq(hps[0], hps[1], "same player hp")
	c.eq(hashes[0], hashes[1], "same state hash")
	c.eq(counts[0], counts[1], "same attack count (%d)" % int(counts[0]))
	c.near(charges[0], charges[1], 1e-9, "same charge")
	c.ok(int(counts[0]) > 0, "the fight happened")
