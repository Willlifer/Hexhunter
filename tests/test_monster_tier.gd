extends RefCounted
## Lane M (H360-H389): spec sections 7 and 8, NORMAL and up. Each mechanic
## works on NORMAL and does nothing on EASY; the tier layer is deterministic
## and reaches a co-op mirror with the unit. (The Purge trigger and its
## containment have their own suite, test_monster_purge.)

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


const BIOMES := { "pond": "swampfang", "caldera": "colambros", "cave": "rimeslithe", "glade": "spirewalker" }
const QUIET := { "tier_avoid_frac": 99.0, "tier_sp_first_s": 9999.0, "tier_pulse_every_s": 9999.0, "tier_pain_pct": 9999.0 }


func _quiet(on: bool, keep: Array = []) -> void:
	for k in QUIET:
		if k in keep:
			continue
		HHTune.set_value(k, QUIET[k] if on else HHTune.default_of(k))


## A stub-brained monster on flat ground (the director alone moves it).
func _stub(kind: String, tier: String, mhex := Vector2i(0, -2), phex := Vector2i(0, 9)) -> Array:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1, tier)
	s.add_player("p1", phex)
	var m := s.add_monster(kind, mhex, 20000.0, 2, ["floor"])
	var brain := Stub.new(kind)
	s.brains[kind] = brain
	return [s, brain, m]


## A real fight as HHFight builds it.
func _real(arena_id: String, monster: String, seed: int, tier: String) -> HHSim:
	var a := HHNetBench.load_arena(arena_id, seed)
	var sim := HHSim.new(a, seed, tier)
	sim.sandbox = true
	HHNetBench._hunters(sim, HHNetBench.party(1))
	var brain: Object = (load("res://src/monster/%s.gd" % monster) as GDScript).new()
	var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
	var u := sim.add_monster(monster, a.spawns.monster, HHTune.value("monster_hp"), 2, allowed)
	sim.brains[monster] = brain
	if brain.has_method("setup"):
		brain.setup(sim, u)
	return sim


func _steps(s: HHSim, n: int, keep_alive: bool = true) -> Array:
	var all: Array = []
	for i in n:
		all.append_array(s.step({}))
		if keep_alive:
			var p := s.unit("p1")
			if not p.is_empty() and float(p.hp) > 0.0:
				p.hp = p.max_hp
	return all


func _tiers(ev: Array, what: String = "") -> Array:
	return ev.filter(func(e): return str(e.type) == "tier" and (what == "" or str(e.what) == what))


# ------------------------------------------------------------------ the hook and EASY

func test_windup_hook_is_identity_without_tier(c: HHSelfTest.HHCheck) -> void:
	for w in [24, 40, 63, 90]:
		c.eq(HHTierBrain.windup({}, w), w, "no tier: %d stays %d" % [w, w])
		c.eq(HHTierBrain.windup({ "tier": { "windup": 1.0 } }, w), w, "calm tier: unchanged")
	c.eq(HHTierBrain.windup({ "tier": { "windup": 0.7 } }, 90), 63, "full enrage: 90 -> 63")
	c.eq(HHTierBrain.windup({ "tier": { "windup": 0.7 } }, 30), 24, "never under the 24-tick floor")
	c.eq(HHTierBrain.windup({ "tier": { "windup": 0.7 } }, 20), 20, "a window already under the floor is not stretched")


func test_easy_never_enters_the_tier_layer(c: HHSelfTest.HHCheck) -> void:
	var before := HHTierBrain.entered
	for arena_id in BIOMES:
		var s := _real(arena_id, str(BIOMES[arena_id]), 1, "easy")
		var tiers := 0
		for i in 900:
			var ev := s.step(HHNetBench.bot_orders(s, s.tick + 1))
			tiers += _tiers(ev).size()
		c.eq(tiers, 0, "%s easy: no tier events in 900 ticks" % BIOMES[arena_id])
		c.ok(not s.unit(str(BIOMES[arena_id])).has("tier"), "%s easy: no tier state on the unit" % BIOMES[arena_id])
	c.eq(HHTierBrain.entered, before, "the director was never called on EASY")


# ------------------------------------------------------------------ 7.1 enrage

func test_enrage_curve_and_scaling(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHTierBrain.enrage_at(0), 0.0, "0 at aggravation")
	c.eq(HHTierBrain.enrage_at(int(HHTierBrain.t("enrage_delay_s") * 30.0)), 0.0, "still 0 at the end of the delay")
	c.near(HHTierBrain.enrage_at(int((HHTierBrain.t("enrage_delay_s") + HHTierBrain.t("enrage_ramp_s") * 0.5) * 30.0)), 0.5, 0.01, "half way up the ramp")
	c.eq(HHTierBrain.enrage_at(99999), 1.0, "full, and capped")
	# a real Colambros: aggravate it, pretend the fight is 3 minutes old
	var s := _real("caldera", "colambros", 1, "normal")
	var e := _real("caldera", "colambros", 1, "easy")
	var m := s.unit("colambros")
	var me := e.unit("colambros")
	_quiet(true)
	var b: HHColambros = s.brains["colambros"]
	var be: HHColambros = e.brains["colambros"]
	b._force_phase(s, m, "aggravated")
	be._force_phase(e, me, "aggravated")
	s.step({})
	s.tick += 180 * 30                                    # the fight is 3 minutes older
	m.tier.sp_next = s.tick + 99999
	s.step({})
	c.eq(float(m.tier.enrage), 1.0, "3 minutes in: full enrage")
	c.near(float(m.tier.windup), HHTierBrain.t("enrage_windup_min"), 0.001, "windows at their minimum")
	c.near(float(m.tier.dmg), HHTierBrain.t("enrage_dmg_max"), 0.001, "damage at its maximum")
	c.eq(int(m.tier.bonus), HHTierBrain.ti("enrage_tier_full"), "painted tiers +2")
	# the same bite on both tiers: the enraged window is 0.7 of easy's
	var p := s.unit("p1")
	b._bite(s, m, p)
	be._bite(e, me, e.unit("p1"))
	var we := int(be.attacks[-1].ticks)
	var wn := int(b.attacks[-1].ticks)
	c.eq(wn, maxi(24, int(round(float(we) * 0.7))), "bite window %d -> %d" % [we, wn])
	# a telegraph the brain issues inside the director carries the damage and tier bonus
	b.busy_until = 0
	b.next_attack_at = 0
	var first := s._next_tg
	var dmg_ok := false
	var tier_ok := true
	for i in 600:
		s.step({})
		s.unit("p1").hp = s.unit("p1").max_hp
		for tg in s.telegraphs:
			if int(tg.id) >= first and str(tg.owner) == "colambros":
				var pl: Dictionary = tg.payload
				if bool(pl.get("tier_scaled", false)) and float(pl.get("dmg_pct", 0.0)) > 0.0:
					dmg_ok = true
				if int(pl.get("paint_steps", 0)) > 0 and int(pl.paint_steps) < 3 and str(pl.get("element", "")) != "":
					tier_ok = false
		if dmg_ok:
			break
	c.ok(dmg_ok, "its next attack's telegraph is scaled")
	c.ok(tier_ok, "painted attacks carry +2 tiers (capped at 3)")
	_quiet(false)


# ------------------------------------------------------------------ 7.2 pulse

func test_element_pulse_overrides_the_hull(c: HHSelfTest.HHCheck) -> void:
	_quiet(true, ["tier_pulse_every_s"])
	for kind in ["swampfang", "colambros", "rimeslithe", "spirewalker"]:
		var r := _stub(kind, "normal")
		var s: HHSim = r[0]
		var m: Dictionary = r[2]
		s.paint(s.footprint(m), "fire", "p1", 2)         # a hunter's fire carpet under it
		_steps(s, HHTierBrain.secs("pulse_every_s") + 2)
		var el := str(HHTierBrain.profile(kind).pulse)
		var all_own := true
		for h in s.footprint(m):
			if str(s.charge.at(h).get("source", "")) != kind or not s.charge.carries(h, el):
				all_own = false
		c.ok(all_own, "%s: after %d s every hull hex carries its own %s" % [kind, int(HHTierBrain.t("pulse_every_s")), el])
		c.eq(int(m.tier.pulses), 1, "%s: one pulse" % kind)
		if el in ["fire", "water"]:
			c.eq(s.charge.intensity(m.hex, el), HHTierBrain.ti("pulse_tier"), "%s: at tier %d" % [kind, HHTierBrain.ti("pulse_tier")])
		var hp := float(m.hp)
		_steps(s, 90)
		c.eq(float(m.hp), hp, "%s: its own element never hurts it" % kind)
		# easy: the carpet stays and burns it
		var re := _stub(kind, "easy")
		var se: HHSim = re[0]
		var mse: Dictionary = re[2]
		se.paint(se.footprint(mse), "fire", "p1", 2)
		_steps(se, HHTierBrain.secs("pulse_every_s") + 2)
		c.ok(se.charge.carries(mse.hex, "fire") and str(se.charge.at(mse.hex).source) == "p1", "%s easy: no pulse, the hunter's fire stays" % kind)
	# the cash-in: a hunter's fresh fire on Colambros's fire-3 pulse overheats and hurts it
	HHTune.set_value("tier_pulse_tier", 3.0)
	var r2 := _stub("colambros", "normal")
	var s2: HHSim = r2[0]
	var m2: Dictionary = r2[2]
	_steps(s2, HHTierBrain.secs("pulse_every_s") + 2)
	var hp2 := float(m2.hp)
	var edge: Vector2i = m2.hex + Vector2i(2, 0)
	var res := s2.paint([edge], "fire", "p1", 1)
	c.ok(not (res.overheat as Array).is_empty(), "fresh fire on the pulse's fire 3 overheats")
	c.ok(float(m2.hp) < hp2, "and the eruption hurts the monster (the pulse is cash-in-able)")
	HHTune.set_value("tier_pulse_tier", HHTune.default_of("tier_pulse_tier"))
	_quiet(false)


# ------------------------------------------------------------------ 7.4 avoidance

func test_avoidance_leaves_the_fire(c: HHSelfTest.HHCheck) -> void:
	_quiet(true, ["tier_avoid_frac", "tier_pain_pct"])
	for kind in ["colambros", "swampfang", "spirewalker"]:
		var r := _stub(kind, "normal")
		var s: HHSim = r[0]
		var m: Dictionary = r[2]
		s.paint(HHHex.area(m.hex, 1), "fire", "p1", 1)
		var start: Vector2i = m.hex
		var ev := _steps(s, 240)
		var av := _tiers(ev, "avoid")
		c.ok(not av.is_empty(), "%s: fire 1 under it (under the purge line): it avoids" % kind)
		c.eq(_tiers(ev, "purge").size(), 0, "%s: no purge for fire 1" % kind)
		if av.is_empty():
			continue
		var used := str(av[0].get("used", ""))
		c.eq(used, "water" if kind == "swampfang" else ("thunder" if kind == "spirewalker" else ""), "%s: uses its own element if it has water or thunder (%s)" % [kind, used])
		c.ok(m.hex != start, "%s: it moved off" % kind)
		c.ok(not (s.charge.intensity(m.hex, "fire") > 0 and HHElementBridge.foreign(s, m.hex, m)), "%s: nothing of the hunter's burns under its centre now" % kind)
		var re := _stub(kind, "easy")
		var se: HHSim = re[0]
		var mse: Dictionary = re[2]
		se.paint(HHHex.area(mse.hex, 1), "fire", "p1", 1)
		_steps(se, 240)
		c.eq(mse.hex, Vector2i(0, -2), "%s easy: stays in it" % kind)
	_quiet(false)


# ------------------------------------------------------------------ 8.1 fakeout

func test_fakeout(c: HHSelfTest.HHCheck) -> void:
	_quiet(true)
	for kind in ["colambros", "rimeslithe"]:
		var r := _stub(kind, "normal", Vector2i(0, -6), Vector2i(0, 8))
		var s: HHSim = r[0]
		var brain: Stub = r[1]
		var m: Dictionary = r[2]
		s.step({})
		var T: Dictionary = m.tier
		c.ok(HHTierBrain._start_fakeout(s, brain, m, T), "%s: a fakeout starts with the hunter 12 out" % kind)
		var act: Dictionary = T.act
		var lanes: Array = act.lanes
		c.eq(lanes.size(), 3, "three corridors")
		var truth := int(act.truth)
		var line: Array = lanes[truth].line
		c.eq(str(act.phase), "rear", "beat 1: rears")
		c.eq(int(act.tell), int(lanes[truth].side), "the body tell names the true lane's side")
		_steps(s, HHTierBrain.ti("fk_rear_ticks"))
		c.eq(str(act.phase), "chevrons", "beat 2: chevrons after %d ticks" % HHTierBrain.ti("fk_rear_ticks"))
		c.eq(s.telegraphs.size(), 0, "no damage shape yet: the corridors are warnings")
		_steps(s, HHTierBrain.ti("fk_chevron_ticks"))
		c.eq(str(act.phase), "vanish", "beat 3: decoys vanish")
		var lit := {}
		for tg in s.telegraphs:
			for h in tg.hexes:
				lit[h] = true
		var true_lane := {}
		for h in lanes[truth].lane:
			true_lane[h] = true
		c.ok(not lit.is_empty() and lit.keys().all(func(h): return true_lane.has(h)), "only the true lane is telegraphed red")
		var p := s.unit("p1")
		var visited := {}
		for i in 120:
			s.step({})
			visited[m.hex] = true
			p.hp = p.max_hp
			if (T.act as Dictionary).is_empty():
				break
		c.ok((T.act as Dictionary).is_empty(), "%s: the run ended" % kind)
		c.eq(m.hex, line[-1], "%s: it rocketed to the end of the true lane" % kind)
		var trail := 0
		for h in line:
			if str(s.charge.at(h).get("source", "")) == kind:
				trail += 1
		c.ok(trail >= line.size() - 1, "%s: a tier-3 trail of its element along the line (%d / %d)" % [kind, trail, line.size()])
		var el := "fire" if kind == "colambros" else "water"
		c.eq(s.charge.intensity(line[line.size() / 2], el), 3, "%s: the trail is tier 3" % kind)
		c.eq(brain.mode, "idle", "the brain gets it back idle")
	_quiet(false)


# ------------------------------------------------------------------ 8.2 sweep

func test_sweep_and_safe_wedge(c: HHSelfTest.HHCheck) -> void:
	_quiet(true)
	var r := _stub("spirewalker", "normal", Vector2i(0, 0), Vector2i(0, 7))
	var s: HHSim = r[0]
	var brain: Stub = r[1]
	var m: Dictionary = r[2]
	var p := s.unit("p1")
	p.weapon = "lance"
	s.step({})
	var T: Dictionary = m.tier
	c.ok(HHTierBrain._start_sweep(s, brain, m, T), "a sweep starts")
	var act: Dictionary = T.act
	# the guard: a lance hunter holding E is a block; the hexes behind it are a wedge
	var behind := [Vector2i(0, 9), Vector2i(0, 10), Vector2i(0, 11)]
	var hit_count := {}
	var painted_dark := 0
	var wedge_hits := 0
	for i in 400:
		p.guard = 30                                       # E held (refreshed: the test's hunter re-guards)
		var ev := s.step({})
		p.hp = p.max_hp
		for e in ev:
			if str(e.type) == "telegraph" and str(e.get("name", "")) == "tier_sweep":
				for h in e.hexes:
					hit_count[h] = int(hit_count.get(h, 0)) + 1
					if h in behind:
						wedge_hits += 1
		if (T.act as Dictionary).is_empty():
			break
	c.ok((T.act as Dictionary).is_empty(), "the sweep ended")
	var ring_hex := Vector2i(5, 0)
	c.eq(int(hit_count.get(ring_hex, 0)), int(HHTierBrain.t("sw_turns")), "a hex in reach is swept once per turn (%d turns)" % int(HHTierBrain.t("sw_turns")))
	c.eq(wedge_hits, 0, "the hexes behind the guarding lance are never in the beam: the safe wedge")
	c.ok(int(hit_count.get(p.hex, 0)) >= 1, "the guard itself takes the beam")
	for h in hit_count:
		if s.charge.intensity(h, "dark") == 3 and str(s.charge.at(h).source) == "spirewalker":
			painted_dark += 1
	c.ok(painted_dark > 0.8 * hit_count.size(), "swept hexes carry dark 3 (%d / %d)" % [painted_dark, hit_count.size()])
	c.ok(int(HHTierBrain.sweep_total()) == int(round(360.0 * HHTierBrain.t("sw_turns") / HHTierBrain.t("sw_deg_per_tick"))), "rotation length")
	# clockwise from above: the angle falls
	c.ok(HHTierBrain.sweep_angle({ "a0": 0.0 }, 10.0) < 0.0, "clockwise (atan2(x, z) falls)")
	# a breakable block (a pillar) survives the first pass and breaks on the second
	var r2 := _stub("rimeslithe", "normal", Vector2i(0, 0), Vector2i(0, 12))
	var s2: HHSim = r2[0]
	var m2: Dictionary = r2[2]
	var pil := Vector2i(4, 0)
	s2.arena.cells[pil] = { "walkable": false, "kind": "pillar", "depth": 0.0, "hp": 500.0, "kind_after": "floor" }
	s2.step({})
	HHTierBrain._start_sweep(s2, r2[1], m2, m2.tier)
	var broke_at := -1
	var half := -1
	for i in 400:
		var ev := s2.step({})
		s2.unit("p1").hp = s2.unit("p1").max_hp
		if not _tiers(ev, "block_broken").is_empty():
			broke_at = s2.tick
		if (m2.tier.act as Dictionary).get("start", -1) is int and int((m2.tier.act as Dictionary).get("start", -1)) > 0:
			half = int(m2.tier.act.start) + int(round(360.0 / HHTierBrain.t("sw_deg_per_tick")))
		if (m2.tier.act as Dictionary).is_empty():
			break
	c.ok(broke_at > half and half > 0, "the pillar broke on the second pass, not the first (broke %d, turn 1 ended %d)" % [broke_at, half])
	c.eq(str(s2.arena.kind(pil)), "floor", "and is gone")
	_quiet(false)


# ------------------------------------------------------------------ 8.3 siphon

func test_siphon(c: HHSelfTest.HHCheck) -> void:
	_quiet(true)
	var r := _stub("colambros", "normal", Vector2i(0, -8), Vector2i(-9, 6))
	var s: HHSim = r[0]
	var brain: Stub = r[1]
	var m: Dictionary = r[2]
	var cluster := HHHex.area(Vector2i(0, 4), 1)
	s.paint(cluster, "fire", "p1", 2)                    # 7 hexes x fire 2 = 14 points
	m.hp = float(m.max_hp) * 0.5
	s.step({})
	var T: Dictionary = m.tier
	c.ok(HHTierBrain._start_siphon(s, brain, m, T), "a 14-point fire cluster: it stalks it")
	c.ok((T.act.path as Array).size() >= 6, "its path is drawn (%d hexes)" % (T.act.path as Array).size())
	var ev := []
	for i in 400:
		ev.append_array(s.step({}))
		if (T.act as Dictionary).is_empty():
			break
	var si := _tiers(ev, "siphon")
	c.eq(si.size(), 1, "it siphoned")
	c.eq(int(si[0].points) if not si.is_empty() else 0, 14, "all 14 points")
	c.ok(float(m.hp) > float(m.max_hp) * 0.5, "it healed")
	c.near(float(T.buff), minf(HHTierBrain.t("si_buff_max"), 1.0 + 14.0 * HHTierBrain.t("si_buff_per_point")), 0.001, "an attack buff (capped)")
	c.eq(HHTierBrain.clusters(s, m, "fire").size(), 0, "the cluster is gone")
	# counter-play: douse it first; it arrives at empty ground
	var r2 := _stub("colambros", "normal", Vector2i(0, -8), Vector2i(-9, 6))
	var s2: HHSim = r2[0]
	var m2: Dictionary = r2[2]
	s2.paint(cluster, "fire", "p1", 2)
	m2.hp = float(m2.max_hp) * 0.5
	s2.step({})
	HHTierBrain._start_siphon(s2, r2[1], m2, m2.tier)
	_steps(s2, 30)
	s2.paint(cluster, "water", "p1", 1)                  # douse: fire meets water, both clear
	var ev2 := []
	for i in 400:
		ev2.append_array(s2.step({}))
		if (m2.tier.act as Dictionary).is_empty():
			break
	var si2 := _tiers(ev2, "siphon")
	c.eq(int(si2[0].points) if not si2.is_empty() else -1, 0, "doused first: it drinks nothing")
	c.eq(float(m2.tier.buff), 1.0, "no buff")
	c.eq(float(m2.hp), float(m2.max_hp) * 0.5, "no heal")
	# a small cluster is not worth it
	var r3 := _stub("colambros", "normal")
	var s3: HHSim = r3[0]
	s3.paint([Vector2i(5, 5)], "fire", "p1", 2)
	s3.step({})
	c.ok(not HHTierBrain._start_siphon(s3, r3[1], r3[2], r3[2].tier), "2 points: no siphon")
	_quiet(false)


# ------------------------------------------------------------------ 8.4 rooting

func test_rooting_on_authored_sun(c: HHSelfTest.HHCheck) -> void:
	_quiet(true)
	var s := _real("glade", "spirewalker", 1, "normal")
	var m := s.unit("spirewalker")
	var brain: HHSpirewalker = s.brains["spirewalker"]
	var sun := 0
	for h in s.arena.cells:
		if str(s.arena.kind(h)) == "sun":
			sun += 1
	c.ok(sun >= 20, "the glade authors sun hexes (%d)" % sun)
	brain._force_phase(s, m, "aggravated")
	s.step({})
	m.hp = float(m.max_hp) * 0.6
	var T: Dictionary = m.tier
	c.ok(HHTierBrain.root_spot(s, m) != HHTierBrain.NO_HEX, "a sun patch the hull fits on")
	c.ok(HHTierBrain._start_root(s, brain, m, T), "below 85 %: it goes to root")
	var p := s.unit("p1")
	for i in 400:
		s.step({})
		p.hp = p.max_hp
		if str((T.act as Dictionary).get("phase", "")) == "rooted":
			break
	c.eq(str(T.act.get("phase", "")), "rooted", "rooted on the sun")
	c.ok(HHTierBrain.sun_count(s, m, m.hex) >= HHTierBrain.ti("rt_min_sun"), "with sun under the hull")
	var hp0 := float(m.hp)
	_steps(s, 60)
	c.ok(float(m.hp) > hp0, "it heals while rooted")
	# corrupt it: fire under the hull
	s.paint([m.hex + Vector2i(1, 0)], "fire", "p1", 1)
	s.step({})
	c.eq(str(T.act.get("phase", "")), "stun", "fire under the root: stunned")
	c.ok(int(m.exposed) > 0, "and exposed (punish window)")
	var stun_t := 0
	for i in 300:
		s.step({})
		p.hp = p.max_hp
		stun_t += 1
		if (T.act as Dictionary).is_empty():
			break
	c.eq(stun_t, HHTierBrain.secs("rt_stun_s"), "for %.1f s" % HHTierBrain.t("rt_stun_s"))
	# full HP: no rooting
	var s2 := _real("glade", "spirewalker", 1, "normal")
	var m2 := s2.unit("spirewalker")
	s2.brains["spirewalker"]._force_phase(s2, m2, "aggravated")
	s2.step({})
	c.ok(not HHTierBrain._start_root(s2, s2.brains["spirewalker"], m2, m2.tier), "healthy: it does not root")
	# no sun on the arena: no rooting
	var r3 := _stub("spirewalker", "normal")
	r3[2].hp = 1000.0
	r3[0].step({})
	c.ok(not HHTierBrain._start_root(r3[0], r3[1], r3[2], r3[2].tier), "no sun hexes: no rooting")
	_quiet(false)


# ------------------------------------------------------------------ determinism and co-op

func test_normal_is_deterministic_and_reaches_the_mirror(c: HHSelfTest.HHCheck) -> void:
	for arena_id in BIOMES:
		var mon := str(BIOMES[arena_id])
		var a := _real(arena_id, mon, 2, "normal")
		var b := _real(arena_id, mon, 2, "normal")
		var mirror := HHNetBench.mirror_sim(arena_id, mon, 2, HHNetBench.party(1))
		mirror.set_difficulty("normal")
		var bad := 0
		var mirror_bad := 0
		for i in 1500:
			a.step(HHNetBench.bot_orders(a, a.tick + 1))
			b.step(HHNetBench.bot_orders(b, b.tick + 1))
			if a.state_hash() != b.state_hash():
				bad += 1
			if a.tick % 30 == 0:
				HHSnapshot.apply(mirror, HHSnapshot.decode(HHSnapshot.encode(HHSnapshot.capture(a))))
				var ta: Variant = a.unit(mon).get("tier")
				var tm: Variant = mirror.unit(mon).get("tier")
				if not (tm is Dictionary) or not HHSnapshot._deep_eq(HHSnapshot.clean(ta), tm) or mirror.state_hash() != a.state_hash():
					mirror_bad += 1
			if a.over != "":
				break
		c.eq(bad, 0, "%s normal: replays tick for tick (%d ticks)" % [mon, a.tick])
		c.eq(mirror_bad, 0, "%s normal: the mirror carries the same tier state" % mon)
		c.eq(HHSnapshot._deep_eq(a.unit(mon).get("tier"), b.unit(mon).get("tier")), true, "%s: same tier state at the end" % mon)
