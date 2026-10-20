extends RefCounted
## Lane FX (H700-H714): the telegraph effect library, pooling, the hunter's
## skill effects, L-4's standing cards, the env tint, and a 20 s fight with
## every effect on.

const BRAINS := ["swampfang", "colambros", "rimeslithe", "spirewalker"]


## Every telegraph name the brains (and the arena, H51) can emit, read from
## their sources: _attack(sim, u, "<clip>" ...), _telegraph(sim, u, "<name>" ...),
## "name": "<name>", the ripple's "clip": "swim", env _tg("<name>" ...).
static func emitted_names() -> Array:
	var out: Array = []
	var pats := [
		'_attack\\(sim, u, "([a-z_]+)"',
		'_telegraph\\(sim, u, "([a-z_]+)"',
		'"name": "([a-z_ ]+)"',
		'"clip": "swim", "ripple"',
		'_tg\\("([a-z_]+)"',
	]
	var files: Array = []
	for b in BRAINS:
		files.append("res://src/monster/%s.gd" % b)
	files.append("res://src/core/env.gd")
	for f in files:
		var txt := FileAccess.get_file_as_string(f)
		for pat in pats:
			var re := RegEx.new()
			re.compile(pat)
			for m in re.search_all(txt):
				var n := "swim" if m.get_group_count() == 0 else m.get_string(1)
				if not n in out:
					out.append(n)
	out.sort()
	return out


func test_every_brain_telegraph_has_an_effect(c: HHSelfTest.HHCheck) -> void:
	var names := emitted_names()
	c.ok(names.size() >= 35, "found the brains' telegraph names (%d)" % names.size())
	for must in ["ember_spit", "charge", "cold_slam", "frost_beam", "meteor_drop", "leaping_squash", "pollen_shake", "dark_spray", "water_jet", "death_roll_spin", "env_swell", "env_vent", "env_rockfall"]:
		c.ok(must in names, "scan finds %s" % must)
	for n in names:
		c.ok(HHTelegraphFx.covers(n), "telegraph '%s' maps to an effect (special or generic)" % n)
	# the signature moves get their specials
	var want := { "ember_spit": "breath_fire", "charge": "charge_lane", "cold_slam": "fist_frost", "frost_beam": "beam_charge",
		"meteor_drop": "meteor", "leaping_squash": "landing_shadow", "pollen_shake": "pollen_haze", "dark_spray": "swamp_spit",
		"water_jet": "swamp_spit", "death_roll_spin": "vortex", "env_swell": "env_swell", "env_vent": "env_vent", "env_rockfall": "env_rockfall" }
	for n in want:
		c.eq(str(HHTelegraphFx.recipe({ "name": n }).special), str(want[n]), "%s special" % n)
	c.eq(str(HHTelegraphFx.recipe({ "clip": "swim", "ripple": true }).special), "surface_ripple", "swampfang's ripple (no name, ripple flag)")
	c.eq(str(HHTelegraphFx.recipe({ "name": "bite", "element": "" }).special), "", "bite: generic only")
	# breath vs charge never share a look
	c.ok(HHTelegraphFx.SPECIAL["ember_spit"] != HHTelegraphFx.SPECIAL["charge"], "breath and charge are different effects")
	for el in ["", "fire", "water", "ice", "thunder", "wind", "dark", "light"]:
		c.ok(HHTelegraphFx.GROUND_MODE.has(el), "element '%s' has a ground mode" % el)


func _view() -> Array:
	var a := HHArena.round_flat(1, 14.0, 0)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 4))
	s.add_monster("colambros", Vector2i(0, -4), 3000.0, 2, [])
	var v := HHArenaView.new()
	v.build(a)
	return [a, s, v]


func test_effects_pooled_and_freed(c: HHSelfTest.HHCheck) -> void:
	var r := _view()
	var s: HHSim = r[1]
	var v: HHArenaView = r[2]
	var fx := v.fxl
	v.sync(s, "p1", 0.033)
	c.eq(fx.effects.size(), 0, "no telegraphs, no effects")
	# one attack = several telegraphs on the same tick (the charge's segments): one effect
	s.telegraph("colambros", [Vector2i(0, -1)], 20, { "name": "charge", "element": "" })
	s.telegraph("colambros", [Vector2i(0, 0)], 26, { "name": "charge", "element": "" })
	s.telegraph("colambros", [Vector2i(0, 1)], 32, { "name": "charge", "element": "" })
	s.telegraph("colambros", [Vector2i(3, 0), Vector2i(4, 0)], 20, { "name": "ember_spit", "element": "fire" })
	v.sync(s, "p1", 0.033)
	c.eq(fx.effects.size(), 2, "two attacks -> two effects (the lane segments share one)")
	c.eq(fx.made, 2, "two built")
	var builds := 0
	for i in 18:
		s.step({})
		v.sync(s, "p1", 0.033)
	for e in fx.effects.values():
		var t: HHTelegraphFx = e
		c.ok(t.p > 0.8, "%s built up over its countdown (p %.2f)" % [t.tg_name, t.p])
		builds += t.add.live() + t.mix.live()
	c.ok(builds > 10, "sprites live during the wind-ups (%d)" % builds)
	for i in 4:
		s.step({})
		v.sync(s, "p1", 0.033)
	var breath: HHTelegraphFx = null
	for e in fx.effects.values():
		if (e as HHTelegraphFx).tg_name == "ember_spit":
			breath = e
	c.ok(breath != null and breath.committed, "the breath committed at contact")
	for i in 120:
		s.step({})
		v.sync(s, "p1", 0.033)
	c.eq(fx.effects.size(), 0, "every effect freed once its telegraphs ended and its burst faded")
	c.eq(fx.pool.size(), 2, "both parked in the pool")
	s.telegraph("colambros", [Vector2i(1, 1)], 15, { "name": "bite" })
	v.sync(s, "p1", 0.033)
	c.eq(fx.made, 2, "the next attack reuses a pooled effect")
	c.eq(fx.effects.size(), 1, "one live")
	var t2: HHTelegraphFx = fx.effects.values()[0]
	c.eq(t2.add.live() + t2.mix.live() <= 2, true, "a reused effect starts empty")
	v.free()


func test_env_and_player_tints(c: HHSelfTest.HHCheck) -> void:
	c.ok(HHArenaView.is_env_telegraph({ "owner": "env", "payload": { "name": "env_swell", "env": true } }), "owner env: env tint")
	c.ok(not HHArenaView.is_env_telegraph({ "owner": "colambros", "payload": { "name": "bite" } }), "a monster's: not env")
	var r := _view()
	var s: HHSim = r[1]
	var v: HHArenaView = r[2]
	s.telegraph("env", [Vector2i(2, 2)], 30, { "name": "env_swell", "element": "water", "env": true })
	s.telegraph("colambros", [Vector2i(-2, 2)], 30, { "name": "bite" })
	v.sync(s, "p1", 0.033)
	var mats := {}
	for mi in v.tg_pool:
		if (mi as MeshInstance3D).visible:
			mats[(mi as MeshInstance3D).material_override] = true
	c.eq(mats.size(), 2, "env and monster telegraphs draw in different materials")
	# the arena's drops each get their own effect (they land apart)
	s.telegraph("env", [Vector2i(5, 0)], 30, { "name": "env_rockfall", "element": "dark", "env": true })
	s.telegraph("env", [Vector2i(-5, 0)], 30, { "name": "env_rockfall", "element": "dark", "env": true })
	v.sync(s, "p1", 0.033)
	c.eq(v.fxl.effects.size(), 4, "swell, bite and two separate rockfalls")
	v.free()


func test_skill_fx_and_reaction_numbers(c: HHSelfTest.HHCheck) -> void:
	var r := _view()
	var s: HHSim = r[1]
	var v: HHArenaView = r[2]
	var sk := v.fxl.skill
	var p := s.unit("p1")
	p.windup = { "left": 5, "total": 10, "kind": "pierce", "data": {}, "on_done": Callable() }
	v.sync(s, "p1", 0.033)
	c.ok(sk.add.live() >= 2, "wind-up: the element builds at the hand (%d)" % sk.add.live())
	c.ok(sk.light.visible, "wind-up light on")
	p.windup = {}
	v.on_event({ "type": "eruption", "id": "p1", "hex": Vector2i(0, 4), "hexes": [Vector2i(0, 4), Vector2i(1, 4), Vector2i(0, 5)], "element": "fire" }, s)
	c.ok(sk.rings.size() >= 2, "eruption: the big ring burst")
	v.on_event({ "type": "strike", "id": "p1", "target": "colambros", "hex": Vector2i(0, -2), "amount": 120.0, "cause": "basic", "rear": false }, s)
	v.on_event({ "type": "reaction", "id": "colambros", "amount": 1872.0, "blasts": 3, "cause": "overheat" }, s)
	c.eq(sk.numbers.size(), 1, "a reaction floats its damage number")
	c.eq(str((sk.numbers[0].label as Label3D).text), "1872  x3", "number and blast count")
	v.on_event({ "type": "detonate", "hex": Vector2i(1, 0), "mult": 2.4, "pct": 2.4, "mix": "" }, s)
	c.eq(sk.numbers.size(), 2, "a detonation floats its multiplier")
	for i in 60:
		v.sync(s, "p1", 0.033)
	c.eq(sk.numbers.size(), 0, "numbers fade out")
	c.eq(sk.rings.size(), 0, "rings fade out")
	v.free()


func test_l4_standing_cards(c: HHSelfTest.HHCheck) -> void:
	var r := _view()
	var s: HHSim = r[1]
	var v: HHArenaView = r[2]
	s.paint([Vector2i(2, 0)], "fire", "p1", 3)
	for i in 10:
		v.sync(s, "p1", 0.05)
	var node: Dictionary = v.fx.get(Vector2i(2, 0), {})
	c.ok(not node.is_empty(), "painted hex has fx nodes")
	if not node.is_empty():
		var cards: MeshInstance3D = node.cards_h
		c.ok(cards.visible, "fire 3: the flame cards stand")
		c.ok(cards.material_override == HHTileFX.material("tile_flame"), "flame card material")
		c.ok(not (node.cards_v as MeshInstance3D).visible, "no light/dark axis: no cards there")
	c.eq(HHTileFX.card_mesh().get_surface_count(), 1, "card mesh built")
	v.free()


## The fight with effects on for 20 s of sim: no errors, effects come and go,
## sprite counts stay bounded (the 60 fps budget: pooled, capped).
func test_fight_20s_with_effects(c: HHSelfTest.HHCheck) -> void:
	for m in ["colambros", "rimeslithe"]:
		var f := HHFight.new()
		f.setup_cfg({ "arena": HHRegistry.biome_of(m), "monster": m, "weapon": "lance", "seed": 3 })
		f.set_process(false)
		var peak := 0
		var made := 0
		var p := f.sim.unit("p1")
		for i in 600:
			if i == 30:
				f._order({ "target": m, "attack": true, "run": true })
			f._process(HHSim.TICK)
			if f.view != null and f.view.fxl != null:
				peak = maxi(peak, f.view.fxl.sprite_count())
				made = f.view.fxl.made
		c.ok(f.sim.tick >= 590, "%s: 20 s stepped (tick %d)" % [m, f.sim.tick])
		c.ok(f.view != null and f.view.fxl != null, "%s: the effects layer is on" % m)
		c.ok(made >= 2, "%s: telegraph effects built during the fight (%d)" % [m, made])
		c.ok(peak > 0 and peak < 2500, "%s: sprite count bounded (peak %d)" % [m, peak])
		c.ok(f.view.fxl.effects.size() <= 12, "%s: live effects bounded (%d)" % [m, f.view.fxl.effects.size()])
		f.free()
