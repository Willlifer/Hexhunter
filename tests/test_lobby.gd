extends RefCounted
## Lane L (H450+): the registry, the launch cfg into a fight, `finished`,
## and the lobby's pick rules (HHLobbyState, headless).


func test_registry_check_is_empty(c: HHSelfTest.HHCheck) -> void:
	var problems := HHRegistry.check()
	c.eq(problems.size(), 0, "registry check: %s" % str(problems))
	c.eq(HHRegistry.ARENAS.size(), 4, "four arenas")
	c.eq(HHRegistry.MONSTERS.size(), 4, "four monsters")
	c.eq(HHRegistry.WEAPONS.size(), 3, "three weapons")
	c.eq(HHRegistry.ELEMENTS.size(), HHFormulas.ELEMENTS.size(), "every element")


func test_every_id_resolves(c: HHSelfTest.HHCheck) -> void:
	for r in HHRegistry.ARENAS:
		var loaded := HHRegistry.load_arena(str(r.id), 1)
		var a: HHArena = loaded.arena
		c.ok(a.cells.size() > 100 and a.spawns.has("player"), "arena %s loads with spawns" % r.id)
		c.ok(str(r.blurb) != "" and (r.look as Array).size() == 2, "arena %s has a blurb and a look" % r.id)
	for r in HHRegistry.MONSTERS:
		c.ok(ResourceLoader.exists("res://src/monster/%s.gd" % str(r.id)), "monster %s brain exists" % r.id)
		c.ok(not HHRegistry.entry("arena", HHRegistry.biome_of(str(r.id))).is_empty(), "monster %s has a biome arena" % r.id)
	c.eq(HHRegistry.biome_of("colambros"), "caldera", "H10 biome")
	c.eq(HHRegistry.biome_of("nobody"), "", "unknown monster: no biome")
	for r in HHRegistry.WEAPONS:
		c.ok(HHWeapons.script(str(r.id)) != null, "weapon %s script loads" % r.id)
	c.ok(HHRegistry.entry("weapon", "sword").is_empty(), "unknown id -> {}")


func test_setup_cfg_puts_the_elements_on_the_player(c: HHSelfTest.HHCheck) -> void:
	for r in HHRegistry.WEAPONS:
		var f := HHFight.new()
		f.setup_cfg({ "arena": "round", "monster": "swampfang", "weapon": str(r.id),
			"element": "thunder", "backup": "dark", "seed": 7, "headless": true })
		var p := f.sim.unit("p1")
		c.eq(str(p.element), "thunder", "%s: active element from the cfg" % r.id)
		c.eq(str(p.backup), "dark", "%s: backup element from the cfg" % r.id)
		c.eq(str(p.weapon), str(r.id), "%s: weapon from the cfg" % r.id)
		c.eq(f.sim.seed, 7, "%s: seed from the cfg" % r.id)
		c.ok(f.sim.units.has("swampfang"), "%s: the monster is in" % r.id)
		c.ok(f.sim.brains.has("swampfang"), "%s: with its brain" % r.id)
		f.free()


func test_finished_fires_win_after_the_hold(c: HHSelfTest.HHCheck) -> void:
	var f := HHFight.new()
	f.setup_cfg({ "arena": "round", "monster": "swampfang", "weapon": "lance", "seed": 1, "headless": true })
	var got: Array = []
	f.finished.connect(func(r: Dictionary): got.append(r))
	var m := f.sim.unit("swampfang")
	f.sim.hurt(m, float(m.hp) + 1.0, "test")
	f._process(HHSim.TICK)
	c.eq(f.sim.over, "win", "the sim is over")
	c.eq(got.size(), 0, "not finished before the hold")
	var hold := HHTune.value("fight_end_hold_s")
	var steps := int(hold / HHSim.TICK) + 3
	for i in steps:
		f._process(HHSim.TICK)
	c.eq(got.size(), 1, "finished once after the hold")
	if got.size() == 1:
		var r: Dictionary = got[0]
		c.eq(str(r.result), "win", "result win")
		c.ok(r.has("cfg") and r.has("ticks") and r.has("hp") and r.has("monster_hp"), "payload per the contract")
		c.ok(float(r.monster_hp) <= 0.0, "monster hp in the payload")
	for i in 10:
		f._process(HHSim.TICK)
	c.eq(got.size(), 1, "never twice")
	f.free()


func test_finished_fires_abort(c: HHSelfTest.HHCheck) -> void:
	var f := HHFight.new()
	f.setup_cfg({ "arena": "round", "monster": "", "weapon": "bow", "seed": 1, "headless": true })
	var got: Array = []
	f.finished.connect(func(r: Dictionary): got.append(r))
	f._finish("abort")
	f._finish("abort")
	c.eq(got.size(), 1, "abort once")
	c.eq(str(got[0].result), "abort", "result abort")
	c.eq(float(got[0].monster_hp), 0.0, "no monster: hp 0")
	f.free()


func test_lobby_picks_and_biome(c: HHSelfTest.HHCheck) -> void:
	var s := HHLobbyState.new()
	s.cfg = HHShell.default_cfg()
	c.ok(s.pick("monster", "rimeslithe"), "monster pick")
	c.eq(str(s.cfg.arena), "cave", "monster drags its biome arena")
	c.ok(s.pick("arena", "glade"), "arena pick after the monster")
	c.eq(str(s.cfg.arena), "glade", "arena picked")
	c.ok(s.pick("monster", "colambros"), "a later monster pick")
	c.eq(str(s.cfg.arena), "glade", "arena picked after the monster stays")
	c.ok(s.pick("monster", "swampfang"), "and the next monster pick")
	c.eq(str(s.cfg.arena), "pond", "drags the biome again")
	c.ok(not s.pick("weapon", "sword"), "unknown weapon refused")
	c.ok(s.pick("weapon", "daggers"), "weapon pick")
	c.eq(str(s.cfg.weapon), "daggers", "weapon set")


func test_lobby_element_pair(c: HHSelfTest.HHCheck) -> void:
	var s := HHLobbyState.new()
	s.cfg = HHShell.default_cfg()
	c.ok(s.pick_element("ice"), "first click")
	c.eq(str(s.cfg.element), "ice", "sets active")
	c.eq(str(s.cfg.backup), "water", "backup untouched")
	c.ok(s.pick_element("light"), "second click")
	c.eq(str(s.cfg.backup), "light", "sets backup")
	c.eq(str(s.cfg.element), "ice", "active untouched")
	c.ok(s.pick_element("light"), "third click (active) on the backup")
	c.eq(str(s.cfg.element), "light", "becomes active")
	c.eq(str(s.cfg.backup), "ice", "the old active moves to backup")
	c.ok(str(s.cfg.element) != str(s.cfg.backup), "never the same")


func test_locked_keys_refuse_picks(c: HHSelfTest.HHCheck) -> void:
	var s := HHLobbyState.new()
	s.setup({ "arena": "cave", "monster": "rimeslithe", "locked": ["arena", "monster"] })
	c.eq(str(s.cfg.arena), "cave", "prefilled arena")
	c.eq(str(s.cfg.monster), "rimeslithe", "prefilled monster")
	c.ok(not s.pick("arena", "pond"), "locked arena refused")
	c.ok(not s.pick("monster", "swampfang"), "locked monster refused")
	c.eq(str(s.cfg.arena), "cave", "arena unchanged")
	c.eq(str(s.cfg.monster), "rimeslithe", "monster unchanged")
	c.ok(s.pick("weapon", "bow"), "weapon still free")
	c.ok(s.pick_element("wind"), "element still free")
	s.row = 0
	s.step_row(1)
	c.eq(str(s.cfg.arena), "cave", "the arrow keys respect the lock")
	c.ok(s.is_locked("arena") and not s.is_locked("weapon"), "is_locked")
	var s2 := HHLobbyState.new()
	s2.setup({ "locked": ["element", "seed"] })
	c.ok(not s2.pick_element("dark"), "locked elements refused")
	c.ok(not s2.set_seed(9), "locked seed refused")


func test_result_line(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHShell.result_line({ "result": "win", "ticks": 84 * 30 }), "VICTORY in 84 s", "win line")
	c.eq(HHShell.result_line({ "result": "fallen", "ticks": 130 * 30 }), "FALLEN at 2:10", "fallen line")
	c.eq(HHShell.result_line({ "result": "abort", "ticks": 31 * 30 }), "aborted at 0:31", "abort line")
	c.eq(HHShell.result_line({}), "", "no result")
