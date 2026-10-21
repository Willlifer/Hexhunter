extends RefCounted
## Lane D (H240-H245): difficulty tiers and the element picker's grouping.
## The tier is sim state (state_hash, snapshots), rides the launch cfg and the
## co-op session (the host's tier rules), persists as a lobby pick; EASY is
## pinned to its pre-gate baseline (H240, H360).

const BIOMES := { "pond": "swampfang", "caldera": "colambros", "cave": "rimeslithe", "glade": "spirewalker" }


func _scratch() -> void:
	HHSave.path = "user://test_difficulty_hunter.json"
	HHLobbyState.last_path = "user://test_difficulty_last.json"
	HHLobbyState.runs_path = "user://test_difficulty_runs.json"


func _restore() -> void:
	for p in [HHSave.path, HHLobbyState.last_path, HHLobbyState.runs_path]:
		if str(p).begins_with("user://test_difficulty") and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	HHSave.path = HHSave.DEFAULT_PATH
	HHLobbyState.last_path = HHLobbyState.LAST_PATH
	HHLobbyState.runs_path = HHLobbyState.RUNS_PATH


## A host fight as HHFight builds it, with the tier given at construction.
func _sim(arena_id: String, monster: String, seed: int, tier: String, hunters: int = 1) -> HHSim:
	var a := HHNetBench.load_arena(arena_id, seed)
	var sim := HHSim.new(a, seed, tier)
	sim.sandbox = true
	HHNetBench._hunters(sim, HHNetBench.party(hunters))
	var brain: Object = (load("res://src/monster/%s.gd" % monster) as GDScript).new()
	var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
	var u := sim.add_monster(monster, a.spawns.monster, HHTune.value("monster_hp"), 2, allowed)
	sim.brains[monster] = brain
	if brain.has_method("setup"):
		brain.setup(sim, u)
	return sim


func test_tier_accessor(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 10.0, 0.0), 1)
	c.eq(s.difficulty, "easy", "a sim defaults to easy (every old caller plays as today)")
	c.ok(s.tier_at_least("easy") and not s.tier_at_least("normal") and not s.tier_at_least("hard"), "easy gates nothing on")
	s.set_difficulty("normal")
	c.ok(s.tier_at_least("easy") and s.tier_at_least("normal") and not s.tier_at_least("hard"), "normal >= easy, < hard")
	s.set_difficulty("hard")
	c.ok(s.tier_at_least("normal") and s.tier_at_least("hard"), "hard >= normal")
	s.set_difficulty("NORMAL ")
	c.eq(s.difficulty, "normal", "case and spaces forgiven")
	s.set_difficulty("nightmare")
	c.eq(s.difficulty, "easy", "an unknown tier plays easy")
	c.eq(HHSim.clean_tier(null), "easy", "a missing tier plays easy")
	c.eq(HHSim.TIERS, ["easy", "normal", "hard"], "the tier list, lowest first")
	c.eq(HHSim.new(HHArena.round_flat(1, 10.0, 0.0), 1, "normal").difficulty, "normal", "the constructor takes the tier")


func test_tier_in_state_hash_and_deterministic(c: HHSelfTest.HHCheck) -> void:
	var a := _sim("pond", "swampfang", 3, "easy")
	var b := _sim("pond", "swampfang", 3, "normal")
	var a2 := _sim("pond", "swampfang", 3, "easy")
	c.ok(a.state_hash() != b.state_hash(), "the tier is in state_hash (tick 0: easy != normal)")
	c.eq(a.state_hash(), a2.state_hash(), "same seed + same tier: same hash at tick 0")
	var b2 := _sim("pond", "swampfang", 3, "normal")
	var bad := 0
	for i in 450:
		var o := HHNetBench.bot_orders(b, b.tick + 1)
		b.step(o)
		b2.step(HHNetBench.bot_orders(b2, b2.tick + 1))
		if b.state_hash() != b2.state_hash():
			bad += 1
	c.eq(bad, 0, "a normal fight replays tick for tick from its seed (450 ticks)")


## H240 / H360: everything that existed on 2026-10-21 is EASY. Lane M gated
## the first behaviours (spec 7 and 8) on NORMAL, so this test now proves
## EASY untouched instead: every monster on its biome, seeds 1 and 2, 900
## ticks of the bot, state_hash at 300 / 600 / 900 equal to the hashes
## recorded on dev 455e2ef BEFORE any gate existed. A lane that changes EASY
## on purpose (and says so in DECIDE / DECISIONS) re-records EASY_BASELINE with
## the printed values; a lane that did not mean to has broken EASY.
const EASY_BASELINE := {
	"swampfang": { 1: [2601370570, 4035524293, 602630068], 2: [819866009, 2817945527, 3352696997] },
	"colambros": { 1: [772734022, 1060920298, 1304489024], 2: [3377750115, 1150314469, 1881194558] },
	"rimeslithe": { 1: [2063619023, 2581957993, 3572603836], 2: [2942525458, 3327141680, 1180565078] },
	"spirewalker": { 1: [760228968, 1564917287, 826376885], 2: [2788904138, 920991410, 3842980882] },
}


func test_easy_matches_the_recorded_baseline(c: HHSelfTest.HHCheck) -> void:
	for arena_id in BIOMES:
		var monster := str(BIOMES[arena_id])
		for seed in [1, 2]:
			var e := _sim(arena_id, monster, seed, "easy")
			var got: Array = []
			for i in 900:
				e.step(HHNetBench.bot_orders(e, e.tick + 1))
				if e.tick % 300 == 0:
					got.append(e.state_hash())
			c.eq(got, EASY_BASELINE[monster][seed], "%s on %s seed %d: EASY is the fight it was before any tier gate" % [monster, arena_id, seed])


## And NORMAL is now a different fight (the gate is live), from the same seed.
func test_normal_differs_from_easy(c: HHSelfTest.HHCheck) -> void:
	for arena_id in BIOMES:
		var monster := str(BIOMES[arena_id])
		var e := _sim(arena_id, monster, 1, "easy")
		var n := _sim(arena_id, monster, 1, "normal")
		var diff := -1
		for i in 900:
			e.step(HHNetBench.bot_orders(e, e.tick + 1))
			n.step(HHNetBench.bot_orders(n, n.tick + 1))
			if e.tick % 30 == 0 and diff < 0:
				var se := HHSnapshot.capture(e)
				var sn := HHSnapshot.capture(n)
				se.erase("dif")
				sn.erase("dif")
				if not HHSnapshot.same(se, sn):
					diff = e.tick
			if e.over != "" or n.over != "":
				break
		c.ok(diff > 0, "%s on %s: normal differs from easy (first at tick %d)" % [monster, arena_id, diff])


func test_snapshot_carries_the_tier(c: HHSelfTest.HHCheck) -> void:
	var host := _sim("round", "swampfang", 1, "normal", 2)
	var players := HHNetBench.party(2)
	var mirror := HHNetBench.mirror_sim("round", "swampfang", 1, players)
	c.eq(mirror.difficulty, "easy", "a mirror built without the cfg starts easy")
	var snap: Dictionary = HHSnapshot.decode(HHSnapshot.encode(HHSnapshot.capture(host)))
	c.eq(str(snap.get("dif", "")), "normal", "the full snapshot names the tier")
	HHSnapshot.apply(mirror, snap)
	c.eq(mirror.difficulty, "normal", "applying it sets the mirror's tier")
	c.eq(mirror.state_hash(), host.state_hash(), "and the hashes agree")


## The real session (HHNet loopback): the host's tier reaches the client's cfg.
func test_session_carries_the_hosts_tier(c: HHSelfTest.HHCheck) -> void:
	var h := HHNet.new()
	var k := HHNet.new()
	var port := 24900 + (Time.get_ticks_usec() % 90)
	c.eq(h.host(port), OK, "host on %d" % port)
	c.eq(k.join("127.0.0.1", port), OK, "join")
	var poll := func(until: Callable) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			h.poll()
			k.poll()
			if until.call():
				return true
			OS.delay_msec(2)
		return false
	c.ok(poll.call(func(): return k.is_online() and h.session.members.size() == 2), "connected")
	c.eq(str(h.session.fields.difficulty), "easy", "a new session is easy")
	h.session.host_set({ "difficulty": "normal" })
	k.session.host_set({ "difficulty": "easy" })              # a client's host_set is ignored
	k.session.set_mine({ "ready": true })
	h.session.set_mine({ "ready": true })
	c.ok(poll.call(func(): return str(k.session.fields.get("difficulty", "")) == "normal" and h.session.all_ready()), "the host's tier reaches the client's session")
	var got := {}
	h.session.start_fight.connect(func(cfg): got.host = cfg)
	k.session.start_fight.connect(func(cfg): got.client = cfg)
	h.session.start()
	c.ok(poll.call(func(): return got.size() == 2), "both started")
	if got.size() == 2:
		c.eq(str(got.host.difficulty), "normal", "host cfg tier")
		c.eq(str(got.client.difficulty), "normal", "client cfg tier = the host's")
		var f := HHFight.new()
		var cc: Dictionary = (got.client as Dictionary).duplicate(true)
		cc.headless = true
		cc.arena = "round"
		f.setup_cfg(cc)
		c.eq(f.sim.difficulty, "normal", "the client's fight (mirror) builds on the host's tier")
		f.free()
	for n in [k, h]:
		n.leave()
		n.free()


func test_fight_and_lobby_tier(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var f := HHFight.new()
	f.setup_cfg({ "arena": "round", "monster": "swampfang", "weapon": "lance", "seed": 1, "headless": true, "difficulty": "normal" })
	c.eq(f.sim.difficulty, "normal", "setup_cfg puts the cfg's tier on the sim")
	c.eq(HHHud.tier_tag(f.sim), "NORMAL", "the HUD's tag")
	f.free()
	var g := HHFight.new()
	g.setup_cfg({ "arena": "round", "monster": "swampfang", "weapon": "lance", "seed": 1, "headless": true })
	c.eq(g.sim.difficulty, "easy", "no tier in the cfg: easy")
	g.free()
	c.eq(str(HHShell.default_cfg().difficulty), "easy", "the default cfg is easy")
	var s := HHLobbyState.new()
	s.save = HHSave.new()
	s.setup({})
	c.eq(str(s.cfg.difficulty), "easy", "a first lobby is easy")
	c.ok(s.set_difficulty("normal"), "the switch picks normal")
	c.ok(not s.set_difficulty("nightmare"), "an unknown tier is refused")
	s.save_last()
	var s2 := HHLobbyState.new()
	s2.save = HHSave.new()
	s2.setup({})
	c.eq(str(s2.cfg.difficulty), "normal", "the pick persists like the other lobby picks")
	c.eq(str(s2.launch_cfg().difficulty), "normal", "and launches")
	c.ok(HHLobbyState.last_path.begins_with("user://test_difficulty"), "on a scratch file, never the player's (H613)")
	s2.coop_locks = ["difficulty"]
	c.ok(not s2.set_difficulty("easy"), "a party client cannot change the tier")
	c.eq(str(HHLobbyState.run_entry({ "result": "win", "ticks": 30 }, s2.cfg).difficulty), "normal", "the run history notes the tier")
	_restore()


func test_lobby_coop_client_follows_the_hosts_tier(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var hub := HHCoopFakeHub.new()
	var mk := func() -> Array:
		var ns := hub.peer(false)
		var co := HHLobbyCoop.new()
		var st := HHLobbyState.new()
		st.setup({})
		co.attach(ns[0], ns[1])
		return [co, st]
	var h: Array = mk.call()
	var g: Array = mk.call()
	(h[0] as HHLobbyCoop).host_game("Ana")
	(g[0] as HHLobbyCoop).join_game("127.0.0.1", "Bo")
	(h[1] as HHLobbyState).set_difficulty("normal")
	(h[0] as HHLobbyCoop).push(h[1])
	var gs: HHLobbyState = g[1]
	gs.coop_locks = (g[0] as HHLobbyCoop).locks()
	(g[0] as HHLobbyCoop).pull(gs)
	c.eq(str(gs.cfg.difficulty), "normal", "the client's lobby follows the host's tier")
	c.ok(gs.is_locked("difficulty"), "and cannot change it")
	hub.free_all()
	_restore()


## H244 (spec section 4): Wind, Ice and Thunder sit under a labelled
## OPERATORS group with one line of copy each; the axis elements come first.
func test_picker_groups_the_operators(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	c.eq(HHLobbyState.OPERATORS, ["wind", "ice", "thunder"], "the operators")
	c.eq(HHLobbyState.AXIS, ["fire", "water", "dark", "light"], "the axis elements")
	var all := HHLobbyState.element_order().duplicate()
	all.sort()
	var reg := HHRegistry.ids("element")
	reg.sort()
	c.eq(all, reg, "the two groups hold every element once")
	for id in HHLobbyState.OPERATORS:
		var line := str(HHLobbyState.OPERATOR_COPY[id])
		c.ok(not line.contains("\n"), "%s: one line" % id)
	c.ok(str(HHLobbyState.OPERATOR_COPY.wind).contains("Swirl"), "Wind cashes in with Swirl")
	c.ok(str(HHLobbyState.OPERATOR_COPY.ice).contains("Shatter"), "Ice with Shatter")
	c.ok(str(HHLobbyState.OPERATOR_COPY.thunder).contains("Detonate"), "Thunder with Detonate")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var lobby := HHLobby.new()
	lobby.setup({})
	root.add_child(lobby)
	c.eq(lobby._discs.size(), 7, "the same seven discs (the existing picker)")
	c.ok(lobby._op_label != null and lobby._op_label.text == "OPERATORS", "the OPERATORS label")
	c.ok(lobby._axis_label != null and lobby._axis_label.text == "AXIS", "the AXIS label (H266)")
	c.eq(lobby._axis_copy.text, HHLobbyState.AXIS_COPY, "the axis line")
	var max_axis := -INF
	for id in HHLobbyState.AXIS:
		max_axis = maxf(max_axis, (lobby._discs[id] as Control).position.x)
	var ok_right := true
	for id in HHLobbyState.OPERATORS:
		ok_right = ok_right and (lobby._discs[id] as Control).position.x > max_axis
		c.eq((lobby._op_copy[id] as Label).text, str(HHLobbyState.OPERATOR_COPY[id]), "%s: its copy line shows" % id)
	c.ok(ok_right and lobby._op_label.position.x > max_axis, "the operators sit together right of the axis group, under their label")
	c.ok(lobby._tier_btns.has("easy") and lobby._tier_btns.has("normal"), "the tier switch is on the card")
	c.ok((lobby._tier_btns.easy as Button).button_pressed, "showing easy")
	(lobby._tier_btns.normal as Button).pressed.emit()
	c.eq(str(lobby.state.cfg.difficulty), "normal", "clicking Normal picks it")
	c.ok((lobby._tier_btns.normal as Button).button_pressed and not (lobby._tier_btns.easy as Button).button_pressed, "and the switch shows it")
	lobby.state.element_phase = 0
	lobby.state.row = 3
	lobby.state.cfg.element = "light"
	lobby.state.cfg.backup = "fire"
	lobby.state.step_row(1)
	c.eq(str(lobby.state.cfg.element), "wind", "the arrow keys walk the strip's order (light -> wind)")
	root.remove_child(lobby)
	lobby.free()
	_restore()
