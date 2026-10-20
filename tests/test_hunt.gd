extends RefCounted
## Lane H: the hunt loop. The flow walks map -> ambush -> prep -> fight ->
## results -> map with the right cfg at each step; the map picks its
## disturbance per seed; approach fires inside the radius and not outside;
## results handles a fight payload with and without HHDrops / HHSave; the
## ambush timeline and roar clips; the driver against the stub shell.


class FakeDrops:
	extends RefCounted
	var calls := 0
	func roll(monster: String, rng: RandomNumberGenerator) -> Array:
		calls += 1
		return ["%s_hide" % monster, "sharp_%d" % rng.randi_range(1, 3)]


class FakeSave:
	extends RefCounted
	var owned: Array = []
	var hunts: Array = []
	var saved := 0
	func load_or_new() -> FakeSave:
		return self
	func save() -> void:
		saved += 1


class NoPlayShell:
	extends Node
	## A shell with show_screen but no play(): HHHunt must fall back to launch_fight.
	var shown: Array = []
	func show_screen(screen: Node, cfg: Dictionary) -> void:
		shown.append(screen)
		add_child(screen)
		if screen.has_method("setup"):
			screen.setup(cfg)


# ------------------------------------------------------------------ flow

func test_flow_walks_a_whole_hunt(c: HHSelfTest.HHCheck) -> void:
	var st := HHHuntFlow.initial({ "seed": 7, "weapon": "bow" })
	c.eq(st.screen, "map", "starts on the map")
	c.eq(st.cfg.locked, [], "nothing locked on the map")
	var s1 := HHHuntFlow.next(st, { "result": "approach", "monster": "rimeslithe", "arena": "cave", "site": 2 })
	c.eq(s1.screen, "ambush", "approach -> ambush")
	c.eq(s1.cfg.monster, "rimeslithe", "ambush cfg carries the monster")
	c.eq(s1.cfg.arena, "cave", "ambush cfg carries the arena")
	var s2 := HHHuntFlow.next(st, { "result": "ambushed" })
	c.eq(s2.screen, "prep", "ambush -> prep")
	c.eq(s2.cfg.locked, ["arena", "monster"], "prep locks arena and monster")
	c.eq(s2.cfg.weapon, "bow", "prep keeps the hunter's weapon")
	var s3 := HHHuntFlow.next(st, { "result": "play", "cfg": { "weapon": "daggers", "element": "ice", "backup": "thunder", "arena": "pond", "monster": "swampfang" } })
	c.eq(s3.screen, "fight", "prep -> fight")
	c.eq(s3.cfg.weapon, "daggers", "the prep choice of weapon is taken")
	c.eq(s3.cfg.element, "ice", "the prep choice of element is taken")
	c.eq(s3.cfg.monster, "rimeslithe", "a locked key cannot be changed by prep")
	c.eq(s3.cfg.arena, "cave", "a locked arena cannot be changed by prep")
	c.eq(int(s3.cfg.seed), 7, "the seed rides through")
	var payload := { "result": "win", "cfg": s3.cfg, "ticks": 1800, "hp": 2100.0, "monster_hp": 0.0 }
	var s4 := HHHuntFlow.next(st, payload)
	c.eq(s4.screen, "results", "fight -> results")
	c.ok(s4.cfg.has("fight") and s4.cfg.fight.result == "win", "results cfg wraps the fight payload")
	c.eq(s4.cfg.cfg.monster, "rimeslithe", "results cfg wraps the launch cfg")
	var s5 := HHHuntFlow.next(st, { "result": "continue" })
	c.eq(s5.screen, "map", "results -> map")
	c.eq(s5.cfg.locked, [], "back on the map nothing is locked")
	c.eq(st.hunt, {}, "the hunt record is cleared")
	var s6 := HHHuntFlow.next(st, { "result": "quit" })
	c.eq(s6.screen, "", "quit from the map ends the loop")


func test_flow_prep_back_and_biome(c: HHSelfTest.HHCheck) -> void:
	var st := HHHuntFlow.initial()
	HHHuntFlow.next(st, { "result": "approach", "monster": "colambros" })
	c.eq(st.cfg.arena, "caldera", "arena defaults to the monster's biome")
	HHHuntFlow.next(st, { "result": "skipped" })
	var back := HHHuntFlow.next(st, { "result": "back" })
	c.eq(back.screen, "map", "back from prep returns to the map")
	c.eq(back.cfg.locked, [], "and unlocks")
	for m in HHHuntFlow.BIOME:
		c.ok(HHHuntFlow.biome_of(m) in ["pond", "cave", "glade", "caldera"], "biome of %s is an arena" % m)
	c.eq(HHHuntFlow.display_name("swampfang"), "Swampfang", "monster display name")


# ------------------------------------------------------------------ map

func test_map_layout_is_seeded(c: HHSelfTest.HHCheck) -> void:
	var a := HHWorldMap.layout(5)
	var b := HHWorldMap.layout(5)
	c.eq(a.disturbance, b.disturbance, "same seed, same disturbance site")
	c.eq((a.sites[0].pos as Vector3), (b.sites[0].pos as Vector3), "same seed, same site positions")
	c.eq(a.sites.size(), 4, "four sites")
	var biomes := []
	for s in a.sites:
		biomes.append(s.biome)
	biomes.sort()
	c.eq(biomes, ["caldera", "cave", "glade", "pond"], "one site per biome")
	var seen := {}
	for seed in range(1, 13):
		seen[HHWorldMap.layout(seed).disturbance] = true
	c.ok(seen.size() >= 3, "across twelve seeds the disturbance lands on at least three different sites (%d)" % seen.size())
	for s in a.sites:
		var p: Vector3 = s.pos
		c.ok(Vector2(p.x, p.z).length() > 40.0, "site %s is well away from the start" % s.biome)


func test_map_approach_radius(c: HHSelfTest.HHCheck) -> void:
	var map := HHWorldMap.new()
	map.setup({ "seed": 3, "weapon": "lance" })
	var got: Array = []
	map.finished.connect(func(r: Dictionary) -> void: got.append(r))
	var site: Dictionary = map.sites[map.disturbance]
	var sp: Vector3 = site.pos
	var r := HHHuntKit.t("approach_m")
	map.teleport(sp.x + r + 3.0, sp.z)
	c.ok(not map.check_approach(), "outside the radius: no approach")
	map._process(1.0 / 60.0)
	c.eq(got.size(), 0, "no finished outside the radius")
	map.teleport(sp.x + r * 0.5, sp.z)
	c.ok(map.check_approach(), "inside the radius: approach")
	map._process(1.0 / 60.0)
	map._process(1.0 / 60.0)
	c.eq(got.size(), 1, "finished fires exactly once")
	if got.size() == 1:
		c.eq(got[0].result, "approach", "result is approach")
		c.eq(got[0].monster, site.monster, "carries the site's monster")
		c.eq(got[0].arena, site.biome, "carries the site's biome as the arena")
	# the other sites do not trigger
	var other := (map.disturbance + 1) % 4
	var map2 := HHWorldMap.new()
	map2.setup({ "seed": 3 })
	var op: Vector3 = map2.sites[other].pos
	map2.teleport(op.x, op.z)
	c.ok(not map2.check_approach(), "standing on a quiet site is not an approach")
	map.free()
	map2.free()


func test_map_runs_at_fight_pace(c: HHSelfTest.HHCheck) -> void:
	var map := HHWorldMap.new()
	map.setup({ "seed": 1 })
	map.teleport(0.0, 0.0)
	map.run_to(40.0, 0.0)
	for i in 30:
		map._process(1.0 / 30.0)
	var x := map.hunter.position.x
	c.near(x, HHHuntKit.t("run_mps"), 0.6, "after one second the hunter has run run_mps metres")
	c.near(map.hunter.position.y, map.height_at(x, 0.0), 0.01, "the hunter stands on the ground")
	map.free()


# ------------------------------------------------------------------ ambush

func test_ambush_timeline(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHAmbush.phase_at(0.0), "lurk", "starts lurking")
	c.eq(HHAmbush.phase_at(HHHuntKit.t("ambush_burst_at") + 0.1), "burst", "then the burst")
	c.eq(HHAmbush.phase_at(HHHuntKit.t("ambush_name_at") + 0.1), "name", "then the name")
	c.eq(HHAmbush.phase_at(HHHuntKit.t("ambush_seconds") + 0.1), "done", "then done")
	c.ok(HHHuntKit.t("ambush_seconds") >= 3.0 and HHHuntKit.t("ambush_seconds") <= 4.5, "three to four seconds")
	for m in ["swampfang", "colambros", "rimeslithe", "spirewalker"]:
		var clip := HHAmbush.roar_clip(m)
		var table: Dictionary = HHMonsterBody.clips(m)
		c.ok(table.has(clip), "%s's roar clip '%s' exists" % [m, clip])
	var am := HHAmbush.new()
	am.setup({ "monster": "swampfang", "arena": "pond", "seed": 1 })
	var got: Array = []
	am.finished.connect(func(r: Dictionary) -> void: got.append(r))
	c.ok(not am.monster.visible, "the monster is hidden before the burst")
	am.scrub(HHAmbush.peak_time())
	c.ok(am.monster.visible, "the monster is out at the peak")
	c.near(am.monster.scale.x, 1.0, 0.05, "at full scale")
	c.eq(got.size(), 0, "not finished at the peak")
	am.scrub(HHHuntKit.t("ambush_seconds") + 0.1)
	c.eq(got.size(), 1, "finished once at the end")
	if got.size() == 1:
		c.eq(got[0].result, "ambushed", "result ambushed")
	am.free()


# ------------------------------------------------------------------ results

func test_results_summary(c: HHSelfTest.HHCheck) -> void:
	HHTune.reset()
	var s := HHResults.summarize({ "result": "win", "ticks": 900, "hp": 1500.0, "monster_hp": 0.0 })
	c.ok(s.won, "win is won")
	c.eq(s.verdict, "VICTORY", "verdict text")
	c.near(s.seconds, 30.0, 0.01, "900 ticks is 30 s")
	c.near(s.dealt, HHTune.value("monster_hp"), 0.01, "dealt = monster max hp when it died")
	c.near(s.taken, HHTune.value("player_hp") - 1500.0, 0.01, "taken from player hp")
	var f := HHResults.summarize({ "result": "fallen", "ticks": 300, "hp": 0.0, "monster_hp": 12000.0, "monster_max_hp": 20000.0, "max_hp": 3000.0 })
	c.ok(not f.won, "fallen is not won")
	c.eq(f.verdict, "FALLEN", "fallen verdict")
	c.near(f.dealt, 8000.0, 0.01, "dealt from the payload's max")


func test_results_without_drops_lane(c: HHSelfTest.HHCheck) -> void:
	var r := HHResults.new()
	r.inject(null, null)
	r.setup({ "cfg": { "monster": "swampfang", "arena": "pond", "seed": 1 }, "fight": { "result": "win", "ticks": 600, "hp": 2000.0, "monster_hp": 0.0 } })
	c.eq(r.drops, [], "no HHDrops: no drops")
	c.ok(r.get_child_count() > 0, "the screen built")
	var got: Array = []
	r.finished.connect(func(x: Dictionary) -> void: got.append(x))
	r._continue()
	r._continue()
	c.eq(got.size(), 1, "continue fires once")
	if got.size() == 1:
		c.eq(got[0].result, "continue", "result continue")
	r.free()


func test_results_with_drops_and_save(c: HHSelfTest.HHCheck) -> void:
	var drops := FakeDrops.new()
	var save := FakeSave.new()
	var r := HHResults.new()
	r.inject(drops, save)
	r.setup({ "cfg": { "monster": "colambros", "arena": "caldera", "seed": 4 }, "fight": { "result": "win", "ticks": 1200, "hp": 900.0, "monster_hp": 0.0 } })
	c.eq(drops.calls, 1, "rolled once")
	c.eq(r.drops.size(), 2, "two drops")
	c.eq(r.drops[0], "colambros_hide", "drop ids from the roll")
	c.ok("colambros_hide" in save.owned, "drops added to owned")
	c.eq(save.hunts.size(), 1, "the hunt recorded")
	c.eq(save.saved, 1, "saved once")
	# a second identical win rolls the same (seeded)
	var r2 := HHResults.new()
	r2.inject(FakeDrops.new(), null)
	r2.setup({ "cfg": { "monster": "colambros", "arena": "caldera", "seed": 4 }, "fight": { "result": "win", "ticks": 1200, "hp": 900.0, "monster_hp": 0.0 } })
	c.eq(r2.drops, r.drops, "same seed + ticks, same drops")
	# a loss rolls nothing but is still recorded
	var save2 := FakeSave.new()
	var r3 := HHResults.new()
	r3.inject(FakeDrops.new(), save2)
	r3.setup({ "cfg": { "monster": "colambros" }, "fight": { "result": "fallen", "ticks": 400, "hp": 0.0, "monster_hp": 15000.0 } })
	c.eq(r3.drops, [], "a loss drops nothing")
	c.eq(save2.hunts.size(), 1, "but the hunt is recorded")
	c.eq(HHResults.card_text("mystery_id").name, "Mystery Id", "an unknown id still gets a card name")
	r.free()
	r2.free()
	r3.free()


# ------------------------------------------------------------------ driver

func test_hunt_driver_against_stub_shell(c: HHSelfTest.HHCheck) -> void:
	var shell := HHHuntShellStub.new()
	var hunt := HHHunt.start(shell, { "seed": 2 })
	hunt.immediate = true
	c.eq(hunt.screen, "map", "driver opens the map")
	c.ok(hunt.node is HHWorldMap, "the map screen is an HHWorldMap")
	c.ok(shell.current == hunt.node, "shown through the shell")
	var map: HHWorldMap = hunt.node
	var sp: Vector3 = map.sites[map.disturbance].pos
	map.teleport(sp.x, sp.z)
	map._process(1.0 / 60.0)
	c.eq(hunt.screen, "ambush", "approach -> ambush through the driver")
	c.ok(hunt.node is HHAmbush, "an HHAmbush")
	(hunt.node as HHAmbush).scrub(HHHuntKit.t("ambush_seconds") + 0.1)
	c.eq(hunt.screen, "prep", "ambush -> prep")
	c.ok(hunt.node is HHHuntPrepStub or hunt.node.has_method("setup"), "a prep screen")
	c.eq(hunt.state.cfg.locked, ["arena", "monster"], "prep is locked")
	hunt.node.finished.emit({ "result": "play", "cfg": { "weapon": "daggers" } })
	c.eq(hunt.screen, "fight", "prep -> fight")
	c.ok(hunt.node != null and hunt.node.has_signal("finished"), "the fight source has a finished signal")
	c.ok(shell.current is HHFight, "the stub shell built an HHFight")
	if shell.current is HHFight:
		var f: HHFight = shell.current
		c.eq(f.weapon, "daggers", "the fight took the prep weapon")
		c.eq(f.monster_id, map.sites[map.disturbance].monster, "the fight has the ambushing monster")
	hunt.node.finished.emit({ "result": "win", "ticks": 100, "hp": 2500.0, "monster_hp": 0.0 })
	c.eq(hunt.screen, "results", "fight -> results")
	c.ok(hunt.node is HHResults, "an HHResults")
	hunt.node.finished.emit({ "result": "continue" })
	c.eq(hunt.screen, "map", "results -> map")
	c.eq(hunt.history.size(), 5, "five transitions logged")
	shell.free()


func test_hunt_driver_without_play(c: HHSelfTest.HHCheck) -> void:
	var shell := NoPlayShell.new()
	var hunt := HHHunt.start(shell, { "seed": 1 })
	hunt.immediate = true
	hunt.node.finished.emit({ "result": "approach", "monster": "spirewalker", "arena": "glade" })
	hunt.node.finished.emit({ "result": "skipped" })
	hunt.node.finished.emit({ "result": "play", "cfg": {} })
	c.eq(hunt.screen, "fight", "reached the fight")
	c.ok(hunt.node is HHHuntFightWatch, "no play(): the fallback fight watch")
	var watch: HHHuntFightWatch = hunt.node
	c.ok(watch.fight is HHFight, "wrapping an HHFight")
	c.eq(str(watch.fight.get("monster_id")), "spirewalker", "with the ambushing monster")
	var p := watch.payload("win")
	c.eq(p.result, "win", "payload verdict")
	c.ok(float(p.max_hp) > 0.0 and float(p.monster_max_hp) > 0.0, "payload carries both max hps")
	shell.free()
