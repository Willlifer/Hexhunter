extends RefCounted
## Lane E: the Rimeslithe manifest, body, clip table and brain.

const REQUIRED_CLIPS := ["calm_sit", "frost_over", "aggravated_idle", "roar", "walk", "frost_beam", "cold_slam",
	"shoulder_charge", "bite", "arm_swipe", "mist_breath", "meteor_drop", "freeze_pillar", "hit_react", "stagger", "collapse", "death"]
const ATTACK_CLIPS := ["frost_beam", "cold_slam", "shoulder_charge", "bite", "arm_swipe", "mist_breath", "meteor_drop", "freeze_pillar"]
const SOCKETS := ["mouth", "head_top", "back", "shoulder_l", "shoulder_r", "fist_l", "fist_r", "tail_tip"]


## A round arena with a shade patch (centre `shade_at`, radius 2) and optional rock cells.
func _arena(seed: int, shade_at: Vector2i = Vector2i(-9999, -9999), rocks: Array = [], lava: Array = []) -> HHArena:
	var a := HHArena.round_flat(seed, 25.0, 0.6)
	if shade_at.x != -9999:
		for h in HHHex.area(shade_at, 2):
			if a.cells.has(h) and bool(a.cells[h].walkable):
				a.cells[h].kind = "shade"
	for h in rocks:
		if a.cells.has(h):
			a.cells[h] = { "walkable": false, "kind": "rock", "depth": 0.0 }
	for h in lava:
		if a.cells.has(h):
			a.cells[h].kind = "lava"
	return a


func _sim(seed: int, player_hex: Vector2i, monster_hex: Vector2i, a: HHArena = null) -> Array:
	if a == null:
		a = _arena(seed)
	var s := HHSim.new(a, seed)
	s.add_player("p1", player_hex)
	var m := s.add_monster("rimeslithe", monster_hex, 20000.0, 2, HHRimeslithe.ALLOWED_KINDS)
	var brain := HHRimeslithe.new("rimeslithe")
	s.brains["rimeslithe"] = brain
	brain.setup(s, m)
	return [s, brain, m]


## Run `ticks` ticks through HHSim.step (the brain ticks inside it); `script` =
## { tick: order } for p1, `hurts` = { tick: fraction of max hp to take }.
func _run(s: HHSim, m: Dictionary, ticks: int, script: Dictionary = {}, hurts: Dictionary = {}) -> Array:
	var events: Array = []
	for i in ticks:
		var orders := {}
		if script.has(s.tick + 1):
			orders["p1"] = script[s.tick + 1]
		s.step(orders)
		if hurts.has(s.tick):
			s.hurt(m, float(m.max_hp) * float(hurts[s.tick]), "test")
		events.append_array(s.events)
	return events


func test_manifest(c: HHSelfTest.HHCheck) -> void:
	c.ok(FileAccess.file_exists("res://art/monsters/rimeslithe.glb"), "rimeslithe.glb built")
	var row := HHMonsterBody.manifest_row("rimeslithe")
	c.ok(not row.is_empty(), "manifest row present")
	c.ok(not HHMonsterBody.manifest_row("swampfang").is_empty(), "the swampfang row survived the append")
	if row.is_empty():
		return
	for s in SOCKETS:
		c.ok((row.sockets as Dictionary).has(s), "socket %s in manifest" % s)
	c.ok(int(row.tris) > 0 and int(row.tris) < 7000, "tris under 7000 (%d)" % int(row.tris))
	c.eq(int(row.footprint_hexes), 2, "radius-2 footprint")
	var L := float(row.length)
	c.ok(L >= 8.5 and L <= 10.5, "8.5-10.5 m long (%.2f)" % L)
	c.ok(float(row.height) > 3.4, "3.5 m at the shoulder with crystals above (%.2f)" % float(row.height))
	var names: Array = (row.bones as Array).map(func(b): return str(b.name))
	for b in ["root", "hips", "spine_0", "spine_1", "chest", "neck", "head", "jaw", "tail_0", "tail_3",
			"hip_fl", "knee_fl", "ankle_fl", "toe_fl", "hip_fr", "toe_fr", "hip_hl", "toe_hl", "hip_hr", "toe_hr"]:
		c.ok(b in names, "bone %s" % b)
	c.eq(str(row.jaw), "jaw", "jaw bone named")
	c.ok((row.arms as Array).has("fl") and (row.arms as Array).has("fr"), "arms listed")
	c.ok((row.crystals as Dictionary).has("shoulder_l") and (row.crystals as Dictionary).has("back_0"), "crystal clusters listed")
	c.ok((row.chains as Dictionary).has("spine") and (row.chains as Dictionary).has("neck") and (row.chains as Dictionary).has("tail"), "spine, neck and tail chains")
	var fl: Array = row.legs.fl.hip_at
	c.ok(float(fl[1]) > 2.2, "the shoulder joint sits high (%.2f m)" % float(fl[1]))
	var toe: Array = row.legs.fl.toe_at
	c.ok(float(toe[2]) > 3.5, "the knuckles rest far ahead of the hips (%.2f m)" % float(toe[2]))


func test_body_loads_and_poses(c: HHSelfTest.HHCheck) -> void:
	var b := HHMonsterBody.new()
	var ok := b.build("rimeslithe")
	c.ok(ok, "body builds from the glb")
	if not ok:
		b.free()
		return
	c.ok(b.skeleton != null and b.skeleton.get_bone_count() >= 24, "skeleton with bones (%d)" % (b.skeleton.get_bone_count() if b.skeleton else 0))
	c.ok(b.triangle_count() > 0 and b.triangle_count() < 7000, "mesh tris under budget (%d)" % b.triangle_count())
	c.ok(b.meshes.any(func(mi): return str(mi.name) == "body_crystal"), "a crystal mesh of its own (H303)")
	for s in SOCKETS + ["ik_fl", "ik_hr"]:
		c.ok(b.socket(s) != null, "socket node %s" % s)
	var rest := b.socket_pos("mouth")
	c.ok(rest.z > 3.5 and rest.y > 1.2, "mouth socket forward and up at rest (%s)" % rest)
	var fist := b.socket_pos("fist_l")
	c.ok(fist.y < 0.6 and fist.z > 3.5 and fist.x > 1.5, "left fist on the floor, far forward and out (%s)" % fist)
	c.ok(b.socket_pos("tail_tip").z < -3.0, "tail tip behind")
	for clip in REQUIRED_CLIPS:
		var key := float(HHRimeslitheClips.CLIPS[clip].key)
		c.ok(b.pose_at(clip, key), "pose_at %s" % clip)
	b.pose_at("roar", 1.1)
	c.ok(b.socket_pos("mouth").distance_to(rest) > 0.5, "roar moves the mouth")
	c.ok(b.socket_pos("fist_l").y > fist.y + 0.4, "roar lifts the fists off the floor")
	b.pose_at("cold_slam", 1.2)
	var l := b.socket_pos("fist_l")
	var r := b.socket_pos("fist_r")
	c.ok(l.y < 0.7 and r.y < 0.7, "cold_slam tell: both fists planted (%.2f, %.2f)" % [l.y, r.y])
	c.ok(absf(l.x - r.x) > absf(fist.x) * 2.0 + 0.2, "cold_slam tell: fists planted wider than the stance")
	b.pose_at("cold_slam", 0.5)
	c.ok(b.socket_pos("fist_l").y > 0.8, "cold_slam raises the fists first")
	b.pose_at("collapse", 1.8)
	c.ok(b.bone_pos("hips").y < 1.0, "collapse drops the body")
	b.pose_at("calm_sit", 2.0)
	c.ok(b.bone_pos("toe_hl").y > -0.1 and b.socket_pos("fist_l").y > -0.1, "sitting keeps toes and knuckles at the floor")
	b.play("aggravated_idle")
	b.play("cold_slam", false)
	for i in 100:
		b.update(1.0 / 30.0)
	c.eq(b.clip, "aggravated_idle", "a one-shot returns to the loop it cut")
	b.free()


func test_clip_table(c: HHSelfTest.HHCheck) -> void:
	var clips := HHMonsterBody.clips("rimeslithe")
	var listed := HHMonsterBody.clip_list("rimeslithe")
	for name in REQUIRED_CLIPS:
		c.ok(clips.has(name), "clip %s present" % name)
		c.ok(name in listed, "clip %s listed" % name)
		if not clips.has(name):
			continue
		var e: Dictionary = clips[name]
		c.ok(float(e.duration) > 0.0, "%s duration > 0" % name)
		c.ok(str(e.note) != "", "%s has a note" % name)
		var ct := int(e.contact_tick)
		c.ok(ct == -1 or float(ct) * HHSim.TICK < float(e.duration), "%s contact tick within duration" % name)
	for name in ATTACK_CLIPS:
		var ct := int(clips[name].contact_tick)
		c.ok(ct >= 24 and ct <= 48, "%s contact tick 24-48 (%d)" % [name, ct])
		var window := int(round(float(ct) * float(HHRimeslithe.TUNE.windup_mult)))
		c.ok(window >= int(HHRimeslithe.TUNE.telegraph_min_ticks) and window <= int(HHRimeslithe.TUNE.telegraph_max_ticks), "%s x2 windup inside the window (%d)" % [name, window])
	c.eq(int(clips.meteor_drop.contact_tick) * 2, 90, "meteor drop telegraphs for 3 s")
	c.eq(HHRimeslitheClips.clip_list().size(), clips.size(), "clip_list matches CLIPS")
	c.eq(clips.size(), REQUIRED_CLIPS.size(), "exactly the kickoff clip list")


func test_phases_script(c: HHSelfTest.HHCheck) -> void:
	var st := HHPhases.start(HHRimeslithe.phases())
	c.eq(HHPhases.check(st, 1.0, 1).size(), 0, "calm at full hp")
	c.eq(HHPhases.check(st, 0.9, 2), ["aggravated"], "aggravated on first damage")
	c.eq(HHPhases.check(st, 0.4, 3).size(), 0, "nothing between")
	c.eq(HHPhases.check(st, 0.2, 4), ["enraged"], "enraged below 0.25")
	c.ok(float(HHPhases.rule(st, "gap_mult")) < 1.0, "enrage shortens the gap")
	c.ok(float(HHPhases.rule(st, "meteor_chance")) > float(HHRimeslithe.TUNE.meteor_chance), "enrage throws more meteors")
	c.ok(HHRimeslithe.TUNE.has("windup_mult") and float(HHRimeslithe.TUNE.windup_mult) >= 2.0, "the heaviest windup (x2)")
	c.eq(HHRimeslithe.new().allowed_kinds(), HHRimeslithe.ALLOWED_KINDS, "allowed_kinds()")
	c.ok(not "lava" in HHRimeslithe.ALLOWED_KINDS and not "rock" in HHRimeslithe.ALLOWED_KINDS, "never lava or rock")


func test_weak_points(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(3, Vector2i(0, 4), Vector2i(0, 0))
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	s.step({})
	c.near(HHRimeslithe.rear_mult(m, Vector2i(0, 4)), 1.0, 1e-6, "no heat, no cold: 1.0")
	m.cold = 0.9
	c.near(HHRimeslithe.rear_mult(m, Vector2i(0, 4)), 1.5, 1e-6, "crystals bright: 1.5")
	m.cold = 0.0
	s.charge.author(Vector2i(1, 0), 2, 0)                        # fire under the footprint
	c.near(HHRimeslithe.rear_mult(m, Vector2i(0, 4)), 1.5, 1e-6, "standing on fire: 1.5")
	var p := s.unit("p1")
	var dmg := s.strike(p, m, 100.0, Vector2i(0, 2), "test")
	c.near(dmg, 150.0, 1e-3, "strike() folds the multiplier through the brain (%.0f)" % dmg)
	s.charge.clear(Vector2i(1, 0))
	c.near(HHRimeslithe.rear_mult(m, Vector2i(0, 4)), 1.0, 1e-6, "fire gone: 1.0")
	# hits while high drain the cold
	m.cold = 0.9
	s.step({})
	s.hurt(m, 10.0, "test")
	s.step({})
	c.near(float(m.cold), 0.9 - float(HHRimeslithe.TUNE.cold_drain_hit), 0.01, "a hit while high drains cold (%.2f)" % float(m.cold))
	m.cold = 0.5
	s.hurt(m, 10.0, "test")
	s.step({})
	c.ok(float(m.cold) > 0.49, "a hit while low does not drain (%.2f)" % float(m.cold))
	c.ok(brain.rolls >= 0, "brain alive")


func test_calm_seeks_shade(c: HHSelfTest.HHCheck) -> void:
	var a := _arena(5, Vector2i(-6, -6))
	var r := _sim(5, Vector2i(0, 16), Vector2i(0, -2), a)
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	var ev := _run(s, m, 900)
	c.eq(brain.state, "calm", "stays calm with the player 16 hexes away")
	c.ok(brain.attacks.is_empty(), "no attacks while calm")
	c.ok(brain.goals.any(func(g): return str(a.kind(g)) == "shade"), "walked toward the shade")
	c.eq(str(a.kind(m.hex)), "shade", "sits in the shade")
	c.ok(float(m.cold) > 0.5, "cold rose in the shade (%.2f)" % float(m.cold))
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "walk"), "walked")
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "frost_over"), "frosted over")
	_run(s, m, 400)
	c.near(float(m.cold), 1.0, 1e-6, "cold caps at 1")
	c.eq(brain.anim, "calm_sit", "sits once fully charged")


func test_aggro_on_proximity_and_damage(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(7, Vector2i(0, 14), Vector2i(0, -2))
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	_run(s, m, 30)
	c.eq(brain.state, "calm", "calm at 16 hexes")
	var ev := _run(s, m, 300, { s.tick + 1: { "move": Vector2i(0, 7) } })
	c.eq(brain.state, "aggravated", "aggravated when the player closes to %d hexes" % HHHex.distance(m.hex, s.unit("p1").hex))
	c.ok(ev.any(func(e): return e.type == "monster_anim" and e.clip == "roar"), "roared on aggravation")
	c.ok(ev.any(func(e): return e.type == "monster_state" and e.state == "aggravated"), "state event")
	var r2 := _sim(8, Vector2i(0, 16), Vector2i(0, -2))
	var s2: HHSim = r2[0]
	var brain2: HHRimeslithe = r2[1]
	var m2: Dictionary = r2[2]
	_run(s2, m2, 30, {}, { 10: 0.05 })
	c.eq(brain2.state, "aggravated", "aggravated on damage")
	_run(s2, m2, 2000, {}, { 100: 0.8 })
	c.eq(brain2.state, "enraged", "enraged below 0.25")


func test_slam_telegraphs_before_damage(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(11, Vector2i(0, 3), Vector2i(0, 0))      # touching the footprint: close range
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	var p := s.unit("p1")
	var hp_at := {}
	for i in 600:
		s.step({})
		hp_at[s.tick] = float(p.hp)
		if brain.attacks.size() >= 2:
			break
	c.ok(not brain.attacks.is_empty(), "attacked")
	if brain.attacks.is_empty():
		return
	var a: Dictionary = brain.attacks[0]
	c.eq(str(a.clip), "cold_slam", "the roar flagged the first close attack: cold_slam")
	c.ok(a.hexes.has(p.hex), "the player stands in the slam ring")
	c.ok(int(a.ticks) >= 80, "the slam telegraph is long (%d ticks)" % int(a.ticks))
	var land := int(a.tick) + int(a.ticks) - 1               # issued inside step a.tick, counted down the same step
	c.near(float(hp_at.get(land - 1, -1.0)), float(p.max_hp), 1e-6, "no damage the tick before the telegraph lands")
	c.ok(float(hp_at.get(land, p.max_hp)) < float(p.max_hp), "damage on the tick it lands")
	c.ok(p.statuses.has("slow") or float(p.hp) < float(p.max_hp), "slowed by the ice")
	for h in a.hexes:
		c.ok(HHHex.distance(a.at, h) > int(m.size), "the slam never targets its own footprint")
	c.ok(s.charge.carries(a.hexes[0], "ice"), "the slam painted ice")


func test_slow_then_freeze(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(13, Vector2i(0, 3), Vector2i(0, 0))
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	var p := s.unit("p1")
	s.unit("p1").hp = 1.0e9                         # H422: x2 damage kills a hunter that never moves; this test is about the brain
	var ev := _run(s, m, 1800)
	var ice := brain.attacks.filter(func(a): return str(a.element) == "ice")
	c.ok(ice.size() >= 2, "two or more ice attacks (%d)" % ice.size())
	c.ok(ev.any(func(e): return e.type == "status" and e.id == "p1" and e.status == "slow"), "slowed first")
	c.ok(brain.freezes > 0, "then frozen (%d)" % brain.freezes)
	c.ok(ev.any(func(e): return e.type == "status" and e.id == "p1" and e.status == "freeze"), "freeze status event")
	c.ok(float(p.hp) < 1.0e9, "took damage")
	c.ok(float(m.cold) > 0.2, "cold rose with the ice attacks (%.2f)" % float(m.cold))


func test_cadence(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(17, Vector2i(0, 4), Vector2i(0, 0))
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	_run(s, m, 2400, {}, { 400: 0.3, 900: 0.3 })
	c.ok(brain.attacks.size() >= 3, "several attacks (%d)" % brain.attacks.size())
	var gap := int(HHRimeslithe.TUNE.attack_gap_ticks)
	for i in range(1, brain.attacks.size()):
		var prev: Dictionary = brain.attacks[i - 1]
		var next: Dictionary = brain.attacks[i]
		var rest := int(next.tick) - (int(prev.tick) + int(prev.ticks))
		c.ok(rest >= int(ceil(gap * 0.75)), "%s -> %s: %d ticks after the previous contact" % [prev.clip, next.clip, rest])
		c.ok(int(prev.ticks) >= int(HHRimeslithe.TUNE.telegraph_min_ticks) and int(prev.ticks) <= int(HHRimeslithe.TUNE.telegraph_max_ticks), "%s window inside TUNE (%d)" % [prev.clip, int(prev.ticks)])
	for a in brain.attacks:
		c.ok(not (a.hexes as Array).is_empty(), "%s has a danger shape" % a.name)


func test_mist_paints_ice_wide(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(19, Vector2i(0, 4), Vector2i(0, 0))
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	s.unit("p1").hp = 1.0e9                         # H422: x2 damage kills a hunter that never moves; this test is about the brain
	_run(s, m, 10, {}, { 5: 0.05 })
	c.eq(brain.state, "aggravated", "aggravated")
	_run(s, m, 900)
	var mists := brain.attacks.filter(func(a): return str(a.name) == "mist_wide")
	c.ok(mists.size() >= 1, "the arena-wide mist fired within 30 s (%d)" % mists.size())
	if mists.is_empty():
		return
	var a: Dictionary = mists[0]
	c.ok((a.hexes as Array).size() >= 100, "the mist covers a wide area (%d hexes)" % (a.hexes as Array).size())
	c.eq(int(a.ticks), int(HHRimeslithe.TUNE.mist_wide_ticks), "mist window from TUNE")
	var iced := 0
	for h in HHHex.area(Vector2i.ZERO, int(HHRimeslithe.TUNE.mist_radius)):
		if s.charge.carries(h, "ice"):
			iced += 1
	c.ok(iced >= 60, "ice on the ground across the centre (%d hexes)" % iced)
	c.ok(a.hexes.has(Vector2i(0, 4)), "the player's hex is in the mist")
	c.ok(a.hexes.all(func(h): return HHHex.distance(h, Vector2i.ZERO) <= int(HHRimeslithe.TUNE.mist_radius)), "the mist stays within its radius of the centre")


func test_beam_alternates_ice_and_light(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(23, Vector2i(0, 9), Vector2i(0, 0))
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	brain._frost_beam(s, m, s.unit("p1"))
	c.eq(s.telegraphs.size(), 2, "two telegraphs on one tick")
	var ice: Dictionary = s.telegraphs[0]
	var light: Dictionary = s.telegraphs[1]
	c.eq(str(ice.payload.element), "ice", "ice half")
	c.eq(str(light.payload.element), "light", "light half")
	c.eq(str(light.payload.status), "", "light does not slow")
	c.ok((ice.hexes as Array).size() >= 4 and (light.hexes as Array).size() >= 3, "a long line (%d + %d)" % [(ice.hexes as Array).size(), (light.hexes as Array).size()])
	for h in ice.hexes:
		c.ok(not (light.hexes as Array).has(h), "no hex in both halves")
	c.eq(int(ice.left), int(light.left), "both land together")
	_run(s, m, int(ice.total) + 2)
	c.ok(s.charge.carries(ice.hexes[0], "ice") and s.charge.carries(light.hexes[0], "light"), "ice and light on alternate hexes")


func test_freeze_pillar(c: HHSelfTest.HHCheck) -> void:
	var a := _arena(29, Vector2i(-9999, -9999), [Vector2i(2, 8), Vector2i(3, 8)])
	var r := _sim(29, Vector2i(0, 8), Vector2i(0, 0), a)
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	c.ok(brain._freeze_pillar(s, m, s.unit("p1")), "finds the rock near the player")
	c.eq(brain.attacks.size(), 1, "one telegraph")
	var at: Dictionary = brain.attacks[0]
	c.eq(str(at.clip), "freeze_pillar", "freeze_pillar clip")
	c.ok(at.hexes.has(Vector2i(0, 8)) or at.hexes.has(Vector2i(1, 8)), "the ring around the rock reaches the player's side")
	for h in at.hexes:
		c.ok(str(a.kind(h)) != "rock", "shards never land on the rock itself")
		c.ok(HHHex.distance(h, Vector2i(2, 8)) == 1 or HHHex.distance(h, Vector2i(3, 8)) == 1, "shards ring the rock")
	var r2 := _sim(31, Vector2i(0, 8), Vector2i(0, 0))
	c.ok(not (r2[1] as HHRimeslithe)._freeze_pillar(r2[0], r2[2], (r2[0] as HHSim).unit("p1")), "no rock: no pillar attack")


func test_goals_fit_and_never_lava(c: HHSelfTest.HHCheck) -> void:
	var lava: Array = []
	for h in HHHex.area(Vector2i(6, 6), 2):
		lava.append(h)
	var a := _arena(37, Vector2i(-7, 2), [Vector2i(4, -3)], lava)
	var r := _sim(37, Vector2i(8, 9), Vector2i(0, -6), a)
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	var visited := { m.hex: true }
	for i in 1500:
		var orders := {}
		if i == 1:
			orders["p1"] = { "move": Vector2i(-8, 10) }
		elif i == 600:
			orders["p1"] = { "move": Vector2i(9, -9) }
		s.step(orders)
		if i == 300:
			s.hurt(m, 0.4 * float(m.max_hp), "test")
		visited[m.hex] = true
	c.ok(brain.goals.size() >= 2, "goals chosen (%d)" % brain.goals.size())
	for g in brain.goals:
		var fits := true
		for h in HHHex.area(g, int(m.size)):
			if not s.arena.walkable(h) or not str(s.arena.kind(h)) in HHRimeslithe.ALLOWED_KINDS:
				fits = false
		c.ok(fits, "goal %s fits the footprint on allowed kinds" % g)
	for h in visited:
		for f in HHHex.area(h, int(m.size)):
			c.ok(str(s.arena.kind(f)) != "lava" and str(s.arena.kind(f)) != "rock", "never stood on lava or rock (%s)" % f)
	c.ok(s.arena.walkable(m.hex), "monster stands on a walkable hex")


func test_charge_drives_forward(c: HHSelfTest.HHCheck) -> void:
	var r := _sim(41, Vector2i(0, 7), Vector2i(0, 0))
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	var p := s.unit("p1")
	s.unit("p1").hp = 1.0e9                         # H422: x2 damage kills a hunter that never moves; this test is about the brain
	var before: Vector2i = m.hex
	brain._shoulder_charge(s, m, p)
	c.eq(brain.mode, "charge", "charging")
	c.near(float(m.walk_ticks), float(HHRimeslithe.TUNE.charge_walk_ticks), 1e-6, "charge pace")
	var a: Dictionary = brain.attacks[0]
	var last_hex: Vector2i = a.hexes[a.hexes.size() - 1]
	c.ok(HHHex.distance(last_hex, p.hex) <= 1 and (a.hexes as Array).size() <= int(HHRimeslithe.TUNE.charge_range) + 1, "a short line reaching the player (%d hexes, ends %s)" % [(a.hexes as Array).size(), last_hex])
	for h in a.hexes:
		c.ok(HHHex.distance(h, Vector2i.ZERO) > int(m.size), "the line starts past the footprint")
	c.eq(str(a.element), "", "no element")
	_run(s, m, 120)
	c.ok(m.hex != before and m.hex.y > before.y, "drove down the line (%s)" % m.hex)
	c.ok(HHHex.distance(m.hex, p.hex) > int(m.size), "stops short of the player")
	_run(s, m, 200)
	c.near(float(m.walk_ticks), float(HHRimeslithe.TUNE.walk_ticks), 1e-6, "pace restored after the charge")


func test_seeks_shade_when_cold_low(c: HHSelfTest.HHCheck) -> void:
	var a := _arena(43, Vector2i(-5, -5))
	var r := _sim(43, Vector2i(0, 9), Vector2i(0, 0), a)
	var s: HHSim = r[0]
	var brain: HHRimeslithe = r[1]
	var m: Dictionary = r[2]
	_run(s, m, 5, {}, { 2: 0.05 })
	c.eq(brain.state, "aggravated", "aggravated")
	m.cold = 0.0
	brain.next_mist_at = s.tick + 100000             # no arena mist: isolates the shade seeking
	_run(s, m, 220, { s.tick + 1: { "move": Vector2i(0, 13) } })
	c.ok(brain.goals.any(func(g): return str(a.kind(g)) == "shade"), "went for the shade with the player far and cold low")
	c.eq(str(a.kind(m.hex)), "shade", "sits in it")
	c.eq(brain.anim, "frost_over", "frosting over")
	c.ok(brain.attacks.is_empty(), "no attacks from the shade with the player far")
	var cold_then := float(m.cold)
	_run(s, m, 400)
	c.ok(float(m.cold) > cold_then, "cold charged in the shade (%.2f -> %.2f)" % [cold_then, float(m.cold)])
	c.ok(not brain.want_cold, "charged past cold_sit_until: done with the shade")
	c.ok(brain.goals.size() >= 2 or not brain.attacks.is_empty(), "comes out to fight once charged")


func test_deterministic(c: HHSelfTest.HHCheck) -> void:
	var hashes: Array = []
	var hexes: Array = []
	var hps: Array = []
	var counts: Array = []
	var colds: Array = []
	for k in 2:
		var a := _arena(47, Vector2i(-6, 4), [Vector2i(3, 6)])
		var r := _sim(47, Vector2i(2, 9), Vector2i(0, -6), a)
		var s: HHSim = r[0]
		var brain: HHRimeslithe = r[1]
		var m: Dictionary = r[2]
		_run(s, m, 900, { 1: { "move": Vector2i(0, -1) }, 250: { "move": Vector2i(6, 2), "run": true }, 500: { "move": Vector2i(-4, 7) } }, { 120: 0.55 })
		hashes.append(s.state_hash())
		hexes.append(m.hex)
		hps.append(int(s.unit("p1").hp))
		counts.append(brain.attacks.size())
		colds.append(snappedf(float(m.cold), 0.0001))
	c.eq(hexes[0], hexes[1], "same monster hex after 900 ticks")
	c.eq(hps[0], hps[1], "same player hp")
	c.eq(hashes[0], hashes[1], "same state hash")
	c.eq(counts[0], counts[1], "same attack count (%d)" % int(counts[0]))
	c.eq(colds[0], colds[1], "same cold")
	c.ok(int(counts[0]) > 0, "the fight happened")
