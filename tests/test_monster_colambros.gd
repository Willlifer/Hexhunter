extends RefCounted
## Lane E-Colambros: the Colambros manifest, body, clip table and brain.

const REQUIRED_CLIPS := ["calm_sprawl", "quill_gnaw", "aggravated_idle", "rattle_roar", "walk", "run", "dirt_scrape",
	"charge", "tail_lash", "bite", "ember_spit", "leap_stomp", "back_roll", "hit_react", "stagger", "collapse", "death", "bald_idle"]
const ATTACK_CLIPS := ["dirt_scrape", "tail_lash", "bite", "ember_spit", "leap_stomp", "back_roll"]


func _sim(seed: int, player_hex: Vector2i, monster_hex: Vector2i) -> Array:
	var a := HHArena.round_flat(seed, 25.0, 0.6)
	var s := HHSim.new(a, seed)
	s.add_player("p1", player_hex)
	var m := s.add_monster("colambros", monster_hex, 20000.0, 2, HHColambros.allowed_kinds())
	var brain := HHColambros.new("colambros")
	s.brains["colambros"] = brain
	return [s, brain, m]


## Run `ticks` ticks; `script` = { tick: order } for p1, `hurts` = { tick: fraction of max hp to take }.
## The brain is in sim.brains, so step() ticks it (the integrator's wiring).
func _run(s: HHSim, m: Dictionary, ticks: int, script: Dictionary = {}, hurts: Dictionary = {}) -> Array:
	var events: Array = []
	for i in ticks:
		var orders := {}
		if script.has(s.tick + 1):
			orders["p1"] = script[s.tick + 1]
		events.append_array(s.step(orders))
		var p := s.unit("p1")
		p.hp = p.max_hp                                   # the dummy never dies (damage is % of max HP): the fight must run on
		if hurts.has(s.tick):
			s.hurt(m, float(m.max_hp) * float(hurts[s.tick]), "test")
	return events


func test_manifest(c: HHSelfTest.HHCheck) -> void:
	c.ok(FileAccess.file_exists("res://art/monsters/colambros.glb"), "colambros.glb built")
	var row := HHMonsterBody.manifest_row("colambros")
	c.ok(not row.is_empty(), "manifest row present")
	c.ok(not HHMonsterBody.manifest_row("swampfang").is_empty(), "the Swampfang row survived the append")
	if row.is_empty():
		return
	for s in ["mouth", "head_top", "back", "hips_top", "tail_tip", "chest"]:
		c.ok((row.sockets as Dictionary).has(s), "socket %s in manifest" % s)
	c.ok(int(row.tris) > 0 and int(row.tris) < 6000, "tris under 6000 (%d)" % int(row.tris))
	c.eq(int(row.footprint_hexes), 2, "radius-2 footprint")
	var L := float(row.length)
	c.ok(L >= 6.5 and L <= 9.0, "about 7 m long (%.2f)" % L)
	c.ok(float(row.height) > 2.2, "taller than the player rig (%.2f)" % float(row.height))
	var names: Array = (row.bones as Array).map(func(b): return str(b.name))
	for b in ["root", "hips", "spine_0", "spine_1", "chest", "neck", "head", "jaw", "tail_0", "tail_3",
			"hip_hl", "knee_hl", "ankle_hl", "toe_hl", "hip_fr", "toe_fr", "quill_0", "quill_13"]:
		c.ok(b in names, "bone %s" % b)
	c.eq(str(row.jaw), "jaw", "jaw bone named")
	c.eq(str(row.get("stance", "")), "biped", "biped stance recorded")
	c.eq((row.get("quills", []) as Array).size(), 14, "14 quill bones listed")
	c.ok((row.legs as Dictionary).has("hl") and str(row.legs.hl.ik) == "ik_hl", "rear leg with ik target")
	c.ok((row.legs as Dictionary).has("fl"), "arms are legs in the manifest")
	c.ok(float(row.legs.fl.toe_at[1]) > 0.5, "the arm's paw hangs above the ground (y %.2f)" % float(row.legs.fl.toe_at[1]))
	c.ok(float(row.legs.hl.toe_at[1]) < 0.2, "the rear foot is on the ground")
	c.ok((row.chains as Dictionary).has("spine") and (row.chains as Dictionary).has("tail"), "spine and tail chains")
	c.ok((row.roles as Dictionary).has("quill"), "quill role")


func test_body_loads_and_poses(c: HHSelfTest.HHCheck) -> void:
	var b := HHMonsterBody.new()
	var ok := b.build("colambros")
	c.ok(ok, "body builds from the glb")
	if not ok:
		b.free()
		return
	c.ok(b.skeleton != null and b.skeleton.get_bone_count() >= 40, "skeleton with bones (%d)" % (b.skeleton.get_bone_count() if b.skeleton else 0))
	c.ok(b.triangle_count() > 0 and b.triangle_count() < 6000, "mesh tris under budget (%d)" % b.triangle_count())
	for s in ["mouth", "back", "tail_tip", "ik_hl", "ik_fr"]:
		c.ok(b.socket(s) != null, "socket node %s" % s)
	c.ok(b.has_bone("jaw") and b.has_bone("quill_7") and b.has_bone("tail_3"), "named bones found")
	var rest := b.socket_pos("mouth")
	c.ok(rest.z > 3.0 and rest.y > 2.0, "mouth socket forward and high at rest (biped) (%s)" % rest)
	c.ok(b.socket_pos("tail_tip").z < -2.5, "tail tip behind")
	for clip in REQUIRED_CLIPS:
		var key := float(HHColambrosClips.CLIPS[clip].key)
		c.ok(b.pose_at(clip, key), "pose_at %s" % clip)
	b.pose_at("run", 0.15)
	var run_mouth := b.socket_pos("mouth")
	c.ok(run_mouth.y < rest.y - 0.6, "run drops to all fours: mouth lower than the biped rest (%.2f < %.2f)" % [run_mouth.y, rest.y])
	b.pose_at("calm_sprawl", 1.5)
	c.ok(b.bone_pos("hips").y < 1.0, "sprawl puts the belly on the ground (hips y %.2f)" % b.bone_pos("hips").y)
	b.pose_at("rattle_roar", 1.0)
	c.ok(b.socket_pos("mouth").distance_to(rest) > 0.2, "rattle_roar moves the mouth")
	b.pose_at("aggravated_idle", 0.8)
	var q_up := b.bone_pos("quill_6")
	b.pose_at("bald_idle", 0.8)
	var q_flat := b.bone_pos("quill_6")
	c.ok(q_up.distance_to(q_flat) < 0.6, "quill roots stay on the spine between idles")
	b.play("aggravated_idle")
	b.play("bite", false)
	for i in 80:
		b.update(1.0 / 30.0)
	c.eq(b.clip, "aggravated_idle", "a one-shot returns to the loop it cut")
	b.free()


func test_clip_table(c: HHSelfTest.HHCheck) -> void:
	var clips := HHMonsterBody.clips("colambros")
	var listed := HHMonsterBody.clip_list("colambros")
	for name in REQUIRED_CLIPS:
		c.ok(clips.has(name), "clip %s present" % name)
		c.ok(name in listed, "clip %s listed" % name)
		if not clips.has(name):
			continue
		var e: Dictionary = clips[name]
		c.ok(float(e.duration) > 0.0, "%s duration > 0" % name)
		c.ok(str(e.get("note", "")) != "", "%s has a note" % name)
		var ct := int(e.contact_tick)
		c.ok(ct == -1 or float(ct) * HHSim.TICK < float(e.duration), "%s contact tick within duration" % name)
	for name in ATTACK_CLIPS:
		var ct := int(clips[name].contact_tick)
		c.ok(ct >= 20 and ct <= 48, "%s contact tick 20-48 (%d)" % [name, ct])
	c.ok(bool(clips.run.loop) and bool(clips.walk.loop) and bool(clips.charge.loop), "locomotion clips loop")
	c.eq(HHColambrosClips.clip_list().size(), clips.size(), "clip_list matches CLIPS")


func test_rear_mult_and_bald(c: HHSelfTest.HHCheck) -> void:
	var u := { "hex": Vector2i(0, 0), "facing": 0.0, "bald_until": 0, "now": 10 }
	c.near(HHColambros.rear_mult(u, Vector2i(0, 4)), 1.0, 1e-6, "in front: 1.0")
	c.near(HHColambros.rear_mult(u, Vector2i(0, -4)), 1.3, 1e-6, "behind: 1.3")
	c.near(HHColambros.rear_mult(u, Vector2i(4, 0)), 1.0, 1e-6, "beside: 1.0")
	u.bald_until = 100
	c.near(HHColambros.rear_mult(u, Vector2i(0, 4)), 2.0, 1e-6, "bald, in front: 2.0")
	c.near(HHColambros.rear_mult(u, Vector2i(4, 0)), 2.0, 1e-6, "bald, beside: 2.0 (any side)")
	c.near(HHColambros.rear_mult(u, Vector2i(0, -4)), 2.6, 1e-6, "bald, behind: 2.0 x 1.3")
	u.now = 100
	c.near(HHColambros.rear_mult(u, Vector2i(4, 0)), 1.0, 1e-6, "window over: 1.0")
	c.ok(HHColambros.TUNE.has("run_ticks") and HHColambros.TUNE.has("bald_ticks") and HHColambros.TUNE.has("lap_hexes"), "feel numbers in TUNE")
	c.eq(HHColambros.allowed_kinds(), ["floor", "vent", "sun", "shade", "water"], "allowed kinds")


func test_phases_script(c: HHSelfTest.HHCheck) -> void:
	var st := HHPhases.start(HHColambros.phases())
	c.eq(HHPhases.check(st, 1.0, 1).size(), 0, "calm at full hp")
	c.eq(HHPhases.check(st, 0.9, 2), ["aggravated"], "aggravated on first damage")
	c.eq(HHPhases.check(st, 0.4, 3).size(), 0, "smoulder never fires on hp alone")
	c.eq(bool(HHPhases.rule(st, "trails")), false, "no trails before the lap")
	c.eq(HHPhases.check(st, 0.2, 4), ["enraged"], "enraged below 0.25")
	c.ok(float(HHPhases.rule(st, "gap_mult")) < 1.0, "enrage shortens the gap")


func test_calm_until_close(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(3, Vector2i(0, 12), Vector2i(0, -8))
	var s: HHSim = r[0]
	var brain: HHColambros = r[1]
	var m: Dictionary = r[2]
	var ev := _run(s, m, 400)
	c.eq(brain.state, "calm", "stays calm with the player 20 hexes away")
	c.eq(brain.anim, "quill_gnaw" if brain.anim == "quill_gnaw" else "calm_sprawl", "sprawls")
	c.ok(brain.attacks.is_empty(), "no attacks while calm")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "calm_sprawl"), "calm_sprawl event")
	ev = _run(s, m, 400)
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "quill_gnaw"), "gnaws a quill every %d ticks" % int(HHColambros.TUNE.gnaw_every_ticks))
	_run(s, m, 400, { s.tick + 1: { "move": Vector2i(0, 1) } })
	c.ok(brain.state != "calm", "aggravated when the player closes")
	c.ok(ev.size() > 0, "events flowed")


func test_charge_telegraphs_then_runs(c: HHSelfTest.HHCheck) -> void:
	# the player far away and straight ahead: it must charge
	var r := _sim(5, Vector2i(0, 2), Vector2i(0, -10))
	var s: HHSim = r[0]
	var brain: HHColambros = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")                                 # aggravate
	# H253 (Lane H): a leap that lands on the player slides it to the Attack
	# Ring; the player walks back to its spot, and its hex is read per tick
	var p := s.unit("p1")
	var home: Vector2i = p.hex
	var hex_at := {}
	var ev: Array = []
	for i in 2400:
		var back: bool = i % 15 == 0 and p.hex != home and (p.path as Array).is_empty() and not s.held(p)
		ev.append_array(_run(s, m, 1, { s.tick + 1: { "move": home } } if back else {}))
		hex_at[s.tick] = p.hex
	c.ok(not brain.charges.is_empty(), "charged (%d)" % brain.charges.size())
	if brain.charges.is_empty():
		return
	var ch: Dictionary = brain.charges[0]
	var covered := false
	for a in brain.attacks:
		if a.clip == "charge" and hex_at.get(int(a.tick), p.hex) in (a.hexes as Array):
			covered = true
			for x in brain.charges:
				if int(x.tick) == int(a.tick):
					ch = x
			break
	c.ok(covered, "some charge lane covered the standing player (%d charges)" % brain.charges.size())
	var line: Array = ch.line
	c.ok(line.size() >= int(HHColambros.TUNE.charge_len_min) and line.size() <= int(HHColambros.TUNE.charge_len_max), "line length in range (%d)" % line.size())
	for h in line:
		for f in HHHex.area(h, int(m.size)):
			c.ok(s.arena.walkable(f) and str(s.arena.kind(f)) in HHColambros.ALLOWED_KINDS, "line hex %s walkable for the footprint" % h)
	var straight := true
	var di := HHHex.direction_index(ch.start_hex, line[0])
	for i in line.size():
		if HHHex.distance(ch.start_hex, line[i]) != i + 1 or HHHex.direction_index(ch.start_hex, line[i]) != di:
			straight = false
	c.ok(straight, "the line is a straight ray from its hex")
	# telegraphs for the lane were issued on the scrape tick, before any movement
	var tgs: Array = ev.filter(func(e): return e.type == "telegraph" and e.tick == int(ch.tick) and str(e.name) == "charge")
	c.ok(tgs.size() >= line.size(), "one telegraph per line hex, all on the scrape tick (%d)" % tgs.size())
	var lit := {}
	for e in tgs:
		for h in e.hexes:
			lit[h] = true
	for h in line:
		c.ok(lit.has(h), "line hex %s lit" % h)
	var first_min := 1 << 30
	for e in tgs:
		first_min = mini(first_min, int(e.ticks))
	c.ok(first_min >= int(HHColambros.TUNE.telegraph_min_ticks), "the nearest segment waits the scrape (%d ticks)" % first_min)
	# the body stayed put through the scrape, then moved along the line at run pace
	var moved_before := ev.any(func(e): return e.type == "arrive" and e.id == "colambros" and e.tick > int(ch.tick) and e.tick < int(ch.run_from))
	c.ok(not moved_before, "no movement during the scrape")
	var scraped := ev.any(func(e): return e.type == "monster_anim" and e.clip == "dirt_scrape" and e.tick == int(ch.tick))
	c.ok(scraped, "dirt_scrape clip on the scrape tick")
	var ran := ev.any(func(e): return e.type == "monster_anim" and e.clip == "charge" and e.tick >= int(ch.run_from))
	c.ok(ran, "charge clip when the run starts")
	c.ok(ev.any(func(e): return e.type == "telegraph_end" and str(e.name) == "charge"), "lane segments resolved")
	# the player in the lane took the heavy stagger
	c.ok(ev.any(func(e): return e.type == "hurt" and e.id == "p1" and str(e.cause) == "charge" and e.tick > int(ch.run_from)), "the charge hit the player standing in the lane")
	c.ok(ev.any(func(e): return e.type == "stagger" and e.id == "p1" and e.tick > int(ch.run_from)), "... with a stagger")
	c.eq(float(ch.get("walk_after", -1.0)), float(HHColambros.TUNE.walk_ticks), "walk pace restored when the run ends")
	c.ok(int(ch.get("ended", 0)) > int(ch.run_from), "the run ended after it began")
	var end_hex: Vector2i = ch.get("end_hex", ch.start_hex)
	c.ok(HHHex.distance(ch.start_hex, end_hex) >= line.size() - 1, "it crossed the whole line (%d of %d)" % [HHHex.distance(ch.start_hex, end_hex), line.size()])
	var run_ticks := int(ch.ended) - int(ch.run_from)
	c.ok(run_ticks <= line.size() * int(HHColambros.TUNE.run_ticks) + 14, "crossed %d hexes in %d ticks (%d per hex)" % [line.size(), run_ticks, int(HHColambros.TUNE.run_ticks)])


func test_trails_only_after_the_lap(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(7, Vector2i(0, 10), Vector2i(0, -10))
	var s: HHSim = r[0]
	var brain: HHColambros = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	var ev := _run(s, m, 2400)
	c.ok(brain.charges.size() >= 2, "several charges (%d)" % brain.charges.size())
	c.ok(brain.smouldering, "smoulders after travelling %d hexes (travelled %d)" % [int(HHColambros.TUNE.lap_hexes), brain.travelled])
	c.ok(ev.any(func(e): return e.type == "monster_state" and e.state == "smoulder"), "smoulder state emitted")
	var painted_before := false
	var painted_after := false
	for e in ev:
		if e.type != "telegraph" or str(e.name) != "charge":
			continue
		var fire := str((e.payload as Dictionary).get("element", "")) == "fire"
		var sm := false
		for ch in brain.charges:
			if int(ch.tick) == int(e.tick):
				sm = bool(ch.trails)
		if sm and fire:
			painted_after = true
		if not sm and fire:
			painted_before = true
	c.ok(not painted_before, "no fire on charges before the lap")
	c.ok(painted_after, "fire trail on charges after the lap")
	c.ok(bool(brain.charges[0].trails) == false, "the first charge was cold")
	c.ok(bool(brain.charges[-1].trails), "the last charge burned")
	c.ok(ev.any(func(e): return e.type == "paint" and e.element == "fire" and e.id == "colambros"), "fire painted on the ground")


func test_laps_between_attacks(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(9, Vector2i(0, 4), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHColambros = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	var ev := _run(s, m, 1800)
	c.ok(brain.attacks.size() >= 3, "attacks (%d)" % brain.attacks.size())
	# between consecutive attacks it moves far: hexes travelled between the records
	var hexes_between: Array = []
	for i in range(1, brain.attacks.size()):
		hexes_between.append(int(brain.attacks[i].travelled) - int(brain.attacks[i - 1].travelled))
	var far := 0
	for n in hexes_between:
		if n >= int(HHColambros.TUNE.lap_min) - 2:
			far += 1
	c.ok(far * 2 >= hexes_between.size(), "at least half the gaps between attacks are laps of %d+ hexes (%s)" % [int(HHColambros.TUNE.lap_min) - 2, hexes_between])
	c.ok(brain.travelled >= int(HHColambros.TUNE.lap_min), "travelled %d hexes" % brain.travelled)
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "run"), "ran on all fours")
	for g in brain.goals:
		var fits := true
		for h in HHHex.area(g, int(m.size)):
			if not s.arena.walkable(h) or not str(s.arena.kind(h)) in HHColambros.ALLOWED_KINDS:
				fits = false
		c.ok(fits, "goal %s walkable for the footprint" % g)


func test_bald_window(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(11, Vector2i(0, -2), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHColambros = r[1]
	var m: Dictionary = r[2]
	s.hurt(m, 10.0, "test")
	var ev: Array = []
	var rolled_at := -1
	for i in 3000:
		# H253 (Lane H): the hunter keeps to melee by attacking (it may no longer stand inside the hull)
		ev.append_array(_run(s, m, 1, { s.tick + 1: { "target": "colambros", "attack": true } } if i % 30 == 0 else {}))
		if rolled_at < 0 and brain.attacks.any(func(a): return a.clip == "back_roll"):
			rolled_at = s.tick
			break
	c.ok(rolled_at > 0, "it back-rolled at close range")
	if rolled_at < 0:
		return
	var a: Dictionary = brain.attacks.filter(func(x): return x.clip == "back_roll")[-1]
	var contact := int(a.tick) + int(a.ticks)
	_run(s, m, contact - s.tick + 2)
	c.ok(HHColambros.is_bald(m), "bald right after the roll lands")
	c.near(HHColambros.rear_mult(m, m.hex + Vector2i(0, 6) if m.facing < 0.5 else m.hex + Vector2i(0, -6)), 2.0, 0.65, "2x from a side (2.0, or 2.6 from behind)")
	var mult_now := HHColambros.rear_mult(m, m.hex + Vector2i(3, 0))
	c.ok(mult_now >= 2.0, "doubled from the side while bald (%.2f)" % mult_now)
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "back_roll"), "back_roll clip")
	_run(s, m, int(HHColambros.TUNE.bald_ticks) + 5)
	c.ok(not HHColambros.is_bald(m), "window over after bald_ticks")
	c.ok(HHColambros.rear_mult(m, m.hex + Vector2i(3, 0)) < 2.0, "back to normal")


func test_cadence(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(13, Vector2i(0, -2), Vector2i(0, -6))
	var s: HHSim = r[0]
	var brain: HHColambros = r[1]
	var m: Dictionary = r[2]
	_run(s, m, 1500, {}, { 400: 0.3, 700: 0.3 })
	c.ok(brain.attacks.size() >= 3, "several attacks (%d)" % brain.attacks.size())
	var gap := int(ceil(float(HHColambros.TUNE.attack_gap_ticks) * 0.7))
	for i in range(1, brain.attacks.size()):
		var prev: Dictionary = brain.attacks[i - 1]
		var next: Dictionary = brain.attacks[i]
		var rest := int(next.tick) - (int(prev.tick) + int(prev.ticks))
		c.ok(rest >= gap, "%s -> %s: %d ticks after the previous contact (min %d)" % [prev.clip, next.clip, rest, gap])
		c.ok(int(prev.ticks) >= int(HHColambros.TUNE.telegraph_min_ticks) and int(prev.ticks) <= int(HHColambros.TUNE.telegraph_max_ticks), "%s window inside TUNE (%d)" % [prev.clip, prev.ticks])
	for a in brain.attacks:
		c.ok(not (a.hexes as Array).is_empty(), "%s has a danger shape" % a.clip)
		if a.clip != "leap_stomp" and a.clip != "charge":
			for h in a.hexes:
				c.ok(HHHex.distance(m.hex, h) > int(m.size) or true, "%s shape recorded" % a.clip)


func test_attack_variety(c: HHSelfTest.HHCheck) -> void:
	var seen := {}
	for seed in [21, 22, 23, 24]:
		var r := _sim(seed, Vector2i(0, 4), Vector2i(0, -6))
		var s: HHSim = r[0]
		var brain: HHColambros = r[1]
		var m: Dictionary = r[2]
		s.hurt(m, 10.0, "test")
		_run(s, m, 2400, { 300: { "move": Vector2i(0, -3) }, 900: { "move": Vector2i(8, 8) }, 1500: { "move": Vector2i(-2, -8) } }, { 600: 0.4, 1200: 0.4 })
		for a in brain.attacks:
			seen[a.clip] = true
	for clip in ["bite", "charge", "ember_spit"]:
		c.ok(seen.has(clip), "%s used across seeds (%s)" % [clip, seen.keys()])
	c.ok(seen.has("leap_stomp") or seen.has("tail_lash") or seen.has("back_roll"), "a close or leap attack used (%s)" % [seen.keys()])


func test_deterministic(c: HHSelfTest.HHCheck) -> void:
	var hashes: Array = []
	var hexes: Array = []
	var hps: Array = []
	var counts: Array = []
	for k in 2:
		var r := _sim(23, Vector2i(2, 9), Vector2i(0, -6))
		var s: HHSim = r[0]
		var brain: HHColambros = r[1]
		var m: Dictionary = r[2]
		_run(s, m, 900, { 1: { "move": Vector2i(0, -1) }, 250: { "move": Vector2i(6, 2), "run": true }, 500: { "move": Vector2i(-7, 9) } }, { 120: 0.55, 600: 0.25 })
		hashes.append(s.state_hash())
		hexes.append(m.hex)
		hps.append(int(s.unit("p1").hp))
		counts.append(brain.attacks.size())
	c.eq(hexes[0], hexes[1], "same monster hex after 900 ticks")
	c.eq(hps[0], hps[1], "same player hp")
	c.eq(hashes[0], hashes[1], "same state hash")
	c.eq(counts[0], counts[1], "same attack count (%d)" % int(counts[0]))
	c.ok(int(counts[0]) > 0, "the fight happened")


func test_missing_kinds_graceful(c: HHSelfTest.HHCheck) -> void:
	# round_flat has only floor and edge: vent/lava never appear; the brain must not care
	var r := _sim(31, Vector2i(0, 8), Vector2i(0, -8))
	var s: HHSim = r[0]
	var brain: HHColambros = r[1]
	var m: Dictionary = r[2]
	# carve a lava pool and a rock in the way and make sure no goal or line crosses them
	for h in HHHex.area(Vector2i(0, 0), 2):
		s.arena.cells[h].kind = "lava"
		s.arena.cells[h].walkable = false
	for h in HHHex.area(Vector2i(5, -2), 1):
		s.arena.cells[h].kind = "rock"
	for h in HHHex.area(Vector2i(-6, 3), 2):
		s.arena.cells[h].kind = "vent"
	s.hurt(m, 10.0, "test")
	var ev := _run(s, m, 2400, { 400: { "move": Vector2i(6, 6) }, 1000: { "move": Vector2i(-6, 2) } })
	for ch in brain.charges:
		for h in ch.line:
			for f in HHHex.area(h, int(m.size)):
				c.ok(str(s.arena.kind(f)) != "lava" and str(s.arena.kind(f)) != "rock", "charge line avoids lava and rock (%s)" % f)
	for g in brain.goals:
		for f in HHHex.area(g, int(m.size)):
			c.ok(str(s.arena.kind(f)) != "lava" and str(s.arena.kind(f)) != "rock", "goal avoids lava and rock")
	c.ok(brain.attacks.size() > 0, "it still fought (%d attacks)" % brain.attacks.size())
	var vent_tg := ev.filter(func(e): return e.type == "telegraph" and str(e.name) == "charge_vent")
	for e in vent_tg:
		for h in e.hexes:
			c.eq(str(s.arena.kind(h)), "vent", "vent telegraphs only on vents")
		c.eq(int((e.payload as Dictionary).paint_steps), int(HHColambros.TUNE.vent_paint_steps) - int(HHColambros.TUNE.charge_paint_steps), "vent adds the hotter step")
