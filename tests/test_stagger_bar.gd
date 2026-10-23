extends RefCounted
## Lane SB (H510-H519): the monster stagger bar. Author: "I would add the
## stagger bar, it should take 10 full water combos to stagger, and scale
## everything from that". A combo is a water reaction (H520).

const Calib := preload("res://tools/stagger_bar_calib.gd")


func _flat(hunters: int = 1) -> HHSim:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	for i in hunters:
		s.add_player("p%d" % (i + 1), Vector2i(0, 4 + i), "water", "fire", "lance")
	s.add_monster("m", Vector2i(0, -2), 1.0e9, 2)
	return s


## A brain that only counts its ticks and keeps one telegraph in the air.
class CountBrain:
	extends RefCounted
	var ticks := 0
	var busy_until := 0
	func tick(sim: HHSim, u: Dictionary) -> void:
		ticks += 1
		if sim.telegraphs.filter(func(t): return str(t.owner) == str(u.id)).is_empty():
			sim.telegraph(str(u.id), [Vector2i(0, 3)], 60, { "dmg_pct": 10.0, "name": "slam" })


## H520: the author's combo is a water reaction ("geysers or water related
## reactions would be my definition of a combo"). A water hunter's basic
## string on a still monster topples it on its 10th water reaction, the blows
## that build each Geyser included; the bow on its 11th (its arrows feed less).
func test_ten_water_reactions_topple(c: HHSelfTest.HHCheck) -> void:
	for w in ["lance", "daggers", "bow"]:
		var s := _flat()
		s.unit("p1").weapon = w
		var m := s.unit("m")
		var n := 0
		var topple_at := -1
		for t in 30 * 120:
			var ev := s.step({ "p1": { "target": "m", "attack": true } } if t == 0 else {})
			for e in ev:
				if str(e.type) == "reaction" and str(e.id) == "m" and str(e.cause) in ["geyser", "steam"]:
					n += 1
				if str(e.type) == "topple" and topple_at < 0:
					topple_at = n
			if topple_at >= 0:
				break
		var want := 11 if w == "bow" else 10
		c.eq(topple_at, want, "%s: topples on water reaction %d" % [w, want])
		c.ok(int(m.topples) == 1, "%s: it is down" % w)


func test_water_fills_most(c: HHSelfTest.HHCheck) -> void:
	for w in ["lance", "daggers", "bow"]:
		var water: Array = Calib.measure(w, "water", 6).fills
		for el in HHFormulas.ELEMENTS:
			if el == "water":
				continue
			var other: Array = Calib.measure(w, el, 6).fills
			c.ok(float(other.back()) < 0.5 * float(water.back()), "%s: %s (%.2f) fills well under half of water (%.2f) over 6 combos" % [w, el, float(other.back()), float(water.back())])
	for el in HHFormulas.ELEMENTS:
		c.ok(HHTune.value("sb_hit_water") >= HHTune.value("sb_hit_" + el), "a water blow fills at least as much as a %s blow" % el)
	var geyser: float = HHFormulas.stagger_fill(HHTune.value("geyser_stagger"), "sb_geyser").value
	for k in ["steam", "shatter", "detonate", "glint", "eclipse", "overheat", "flux"]:
		var v: float = HHFormulas.stagger_fill(HHTune.value(k + "_stagger"), "sb_" + k).value
		c.ok(v < geyser, "%s fills less than a Geyser (%.3f < %.3f)" % [k, v, geyser])
	# H441's order among the reactions: control (shatter, steam) over cash-in (detonate) over the rest
	var fill := func(k: String) -> float: return float(HHFormulas.stagger_fill(HHTune.value(k + "_stagger"), "sb_" + k).value)
	c.ok(fill.call("shatter") > fill.call("detonate") and fill.call("steam") > fill.call("detonate"), "Shatter and Steam fill more than Detonate")
	c.ok(fill.call("detonate") > fill.call("eclipse") and fill.call("detonate") >= fill.call("overheat"), "Detonate fills more than Eclipse / Overheat")


func test_fill_goes_through_formulas(c: HHSelfTest.HHCheck) -> void:
	var calc := HHFormulas.stagger_fill(0.5, "sb_hit_water")
	c.near(float(calc.value), 0.5 * HHTune.value("sb_hit_water"), 1e-6, "stagger x factor")
	c.ok(str(calc.formula).contains("sb_hit_water") and str(calc.values) != "", "a breakdown")
	c.near(float(HHFormulas.stagger_fill(1.0, "sb_geyser", 0.25).value), 0.25 * HHTune.value("sb_geyser"), 1e-6, "a monster-triggered fraction")
	c.near(float(HHFormulas.stagger_fill(1.0, "sb_nonsense").value), 0.0, 1e-9, "an unknown source fills nothing")
	var s := _flat()
	var m := s.unit("m")
	var p := s.unit("p1")
	s.strike(p, m, 100.0, Vector2i(0, 0), "basic", 0.3)
	c.near(float(m.sbar), 0.3 * HHTune.value("sb_hit_water"), 1e-6, "a water blow feeds stagger x sb_hit_water")
	p.element = "fire"
	s.strike(p, m, 100.0, Vector2i(0, 0), "basic", 0.3)
	c.near(float(m.sbar), 0.3 * (HHTune.value("sb_hit_water") + HHTune.value("sb_hit_fire")), 1e-6, "a fire blow feeds x sb_hit_fire")
	var before := float(m.sbar)
	s.strike(p, m, 100.0, Vector2i(0, 0), "basic", 0.0)
	c.near(float(m.sbar), before, 1e-9, "a blow with no stagger feeds nothing")
	# a Geyser the hunter set off
	p.element = "water"
	var hx := Vector2i(1, -2)
	s.paint([hx], "water", "p1", 3)
	before = float(m.sbar)
	s.paint([hx], "water", "p1", 1)
	c.near(float(m.sbar) - before, HHTune.value("geyser_stagger") * HHTune.value("sb_geyser"), 1e-6, "a Geyser feeds geyser_stagger x sb_geyser")
	# the per-hit stagger is untouched (the bar is a layer on top)
	c.eq(int(m.stagger), int(float(HHFormulas.stagger_ticks(HHTune.value("geyser_stagger")).value) * HHTune.value("monster_stagger_mult")), "the Geyser's own stagger is as before")


func test_topple(c: HHSelfTest.HHCheck) -> void:
	var s := _flat()
	var m := s.unit("m")
	var brain := CountBrain.new()
	s.brains["m"] = brain
	s.step()
	c.eq(s.telegraphs.size(), 1, "the brain has an attack in the air")
	var need := float(m.sbar_need)
	c.near(need, HHTune.value("sb_need"), 1e-6, "solo, first topple: sb_need")
	m.sbar = need - 0.01
	m.path = [Vector2i(0, -1)] as Array[Vector2i]
	var hp := float(m.hp)
	s.strike(s.unit("p1"), m, 100.0, Vector2i(0, 0), "basic", 0.5)
	var ticks := int(roundf(HHTune.value("sb_topple_s") * 30.0))
	c.eq(int(m.toppled), ticks, "full: toppled for sb_topple_s")
	c.eq(int(m.topples), 1, "counted")
	c.ok(s.telegraphs.is_empty(), "its attack in the air is cancelled")
	c.ok(s.events.any(func(e): return str(e.type) == "telegraph_end" and bool(e.get("cancelled", false))), "telegraph_end { cancelled }")
	c.ok(s.events.any(func(e): return str(e.type) == "topple"), "a topple event")
	c.ok(s.events.any(func(e): return str(e.type) == "monster_anim" and str(e.clip) == "stagger"), "the body plays its stagger clip")
	c.ok((m.path as Array).is_empty(), "it stops")
	c.ok(int(m.exposed) >= ticks, "exposed (H57) for the whole topple")
	var bt := brain.ticks
	var at: Vector2i = m.hex
	s.step()
	c.eq(brain.ticks, bt, "its brain does not run while it is down")
	c.ok(s.telegraphs.is_empty(), "so no new attack")
	c.ok(float(m.sbar) < need, "the bar drains while it is down")
	hp = float(m.hp)
	s.strike(s.unit("p1"), m, 100.0, Vector2i(0, 0), "basic", 0.0)
	c.near(hp - float(m.hp), 100.0 * HHTune.value("exposed_dmg_mult"), 1.0, "a blow on a toppled monster lands x exposed_dmg_mult")
	var fill := float(m.sbar)
	s.strike(s.unit("p1"), m, 1.0, Vector2i(0, 0), "basic", 1.0)
	c.near(float(m.sbar), fill, 1e-6, "no fill while it is down")
	for i in ticks:
		s.step()
	c.eq(int(m.toppled), 0, "it stands after sb_topple_s")
	c.eq(m.hex, at, "it did not move while down")
	c.near(float(m.sbar), 0.0, 1e-6, "the bar is empty")
	c.near(float(m.sbar_need), need * HHTune.value("sb_rise_mult"), 1e-4, "the next topple needs x sb_rise_mult (H520: twice)")
	s.step()
	c.ok(brain.ticks > bt, "its brain runs again")


func test_topple_waits_for_the_ground(c: HHSelfTest.HHCheck) -> void:
	var s := _flat()
	var m := s.unit("m")
	m.untargetable = true
	m.sbar = float(m.sbar_need) - 0.01
	s.sbar_feed(m, 1.0)
	c.eq(int(m.toppled), 0, "a dived (untargetable) monster does not topple yet")
	m.untargetable = false
	s.step()
	c.ok(int(m.toppled) > 0, "it topples on the first tick it can")


func test_decay(c: HHSelfTest.HHCheck) -> void:
	var s := _flat()
	var m := s.unit("m")
	s.sbar_feed(m, 5.0)
	var delay := int(HHTune.value("sb_decay_delay_s") * 30.0)
	for i in delay:
		s.step()
	c.near(float(m.sbar), 5.0, 1e-6, "held for sb_decay_delay_s")
	for i in 30:
		s.step()
	c.ok(float(m.sbar) < 5.0, "then it drains")
	c.near(5.0 - float(m.sbar), float(m.sbar_need) * HHTune.value("sb_decay_pct_s") / 100.0, 0.05, "about sb_decay_pct_s of the threshold per second")


func test_party_scale(c: HHSelfTest.HHCheck) -> void:
	for n in [1, 2, 4]:
		var s := _flat(n)
		var want := HHTune.value("sb_need") * (1.0 + HHTune.value("sb_party_mult") * float(n - 1))
		c.near(float(s.unit("m").sbar_need), want, 1e-4, "%d hunters: sb_need x(1 + sb_party_mult per extra)" % n)
	var s4 := _flat(4)
	c.ok(float(s4.unit("m").sbar_need) / HHTune.value("sb_need") > 2.5, "four hunters do not topple four times as often (threshold x%.1f)" % (float(s4.unit("m").sbar_need) / HHTune.value("sb_need")))


func test_off_switch_and_monster_triggered(c: HHSelfTest.HHCheck) -> void:
	var s := _flat()
	var m := s.unit("m")
	HHTune.set_value("sb_on", 0.0)
	s.strike(s.unit("p1"), m, 100.0, Vector2i(0, 0), "basic", 1.0)
	c.near(float(m.sbar), 0.0, 1e-9, "sb_on 0: no fill")
	HHTune.set_value("sb_on", 1.0)
	# a Geyser the monster set off on a hunter's water: the 3.3 fraction
	var hx := Vector2i(1, -2)
	s.paint([hx], "water", "p1", 3)
	s.step()
	s.paint([hx], "water", "m", 1)
	c.near(float(m.sbar), HHTune.value("geyser_stagger") * HHTune.value("sb_geyser") * HHTune.value("sb_monster_trigger_frac"), 1e-6,
		"a monster-triggered Geyser fills x sb_monster_trigger_frac")
	HHTune.reset()


func test_determinism(c: HHSelfTest.HHCheck) -> void:
	var hashes: Array = []
	var fed := false
	for run in 2:
		var s := HHNetBench.host_sim("pond", "swampfang", 3, HHNetBench.party(2))
		var got: Array = []
		for i in 900:
			s.step(HHNetBench.bot_orders(s, s.tick + 1))
			if s.tick % 150 == 0:
				got.append(s.state_hash())
			if float(s.unit("swampfang").get("sbar", 0.0)) > 0.0:
				fed = true
		hashes.append(got)
	c.eq(hashes[0], hashes[1], "same seed, same orders: the same fight, bar included")
	c.ok(fed, "the bots fed the bar")
	var s := _flat()
	var h0 := s.state_hash()
	s.unit("m").sbar = 1.5
	c.ok(s.state_hash() != h0, "the bar is in state_hash")


func test_coop_replication(c: HHSelfTest.HHCheck) -> void:
	HHTune.set_value("sb_need", 2.0)                   # a topple inside the window
	var players := HHNetBench.party(2)
	var host := HHNetBench.host_sim("pond", "swampfang", 1, players)
	var mirror := HHNetBench.mirror_sim("pond", "swampfang", 1, players)
	var prev := HHSnapshot.capture(host)
	HHSnapshot.apply(mirror, prev)
	var bad := 0
	var fed := false
	var toppled := false
	for i in 900:
		host.step(HHNetBench.bot_orders(host, host.tick + 1))
		var cur := HHSnapshot.capture(host)
		HHSnapshot.apply_delta(mirror, HHSnapshot.decode(HHSnapshot.encode(HHSnapshot.delta(prev, cur))))
		prev = cur
		var hm := host.unit("swampfang")
		var mm := mirror.unit("swampfang")
		for k in ["sbar", "sbar_need", "toppled", "topples"]:
			if str(hm.get(k)) != str(mm.get(k)):
				bad += 1
		fed = fed or float(mm.get("sbar", 0.0)) > 0.0
		toppled = toppled or int(mm.get("toppled", 0)) > 0
	c.eq(bad, 0, "the mirror's bar, threshold and topple match the host's every tick")
	c.ok(fed, "the mirror saw the bar fill")
	c.ok(toppled, "the mirror saw a topple")
	c.eq(mirror.state_hash(), host.state_hash(), "and the hashes agree")
	var hm := host.unit("swampfang")
	var stood := int(hm.topples) - (1 if int(hm.toppled) > 0 else 0)   # the threshold rises when it stands
	c.near(float(hm.sbar_need) / pow(HHTune.value("sb_rise_mult"), float(stood)),
		2.0 * (1.0 + HHTune.value("sb_party_mult")), 1e-3, "two hunters: the threshold carries the party")
	HHTune.reset()


func test_view(c: HHSelfTest.HHCheck) -> void:
	var bar := Rect2(100, 38, 520, 16)
	var r := HHHud.stagger_rect(bar)
	c.ok(r.position.y > bar.end.y and r.size.x == bar.size.x, "the stagger bar sits under the HP bar, as wide")
	c.near(HHHud.stagger_frac({ "sbar": 6.0, "sbar_need": 24.0 }), 0.25, 1e-6, "fill fraction")
	c.near(HHHud.stagger_frac({}), 0.0, 1e-6, "no bar: 0")
	# the body: down to the slump, held, recovers in the last part
	var d := 1.5
	c.near(HHMonsterBody.topple_hold("stagger", 0.3, d, 120, 0.5), 0.3, 1e-6, "sagging down")
	c.near(HHMonsterBody.topple_hold("stagger", 1.2, d, 100, 0.5), 0.75, 1e-6, "held at the slump")
	c.near(HHMonsterBody.topple_hold("stagger", 0.75, d, 15, 0.5), 1.0, 1e-6, "recovering as it stands")
	c.near(HHMonsterBody.topple_hold("stagger", 1.2, d, 0, 0.5), 1.2, 1e-6, "not toppled: untouched")
	c.near(HHMonsterBody.topple_hold("walk", 1.2, d, 100, 0.5), 1.2, 1e-6, "another clip: untouched")
