extends RefCounted
## Lane C (H913, H915-H917): the co-op hunt loop with a fake session. Two
## drivers (host, guest) on one HHCoopFakeHub: each sees the other's token,
## only the host's map decides the approach (here: the guest's token reaching
## the stir), the ambush follows on the guest, a guest's approach that lands
## off the map waits for it, the fight launches in each peer's mode, each
## peer rolls its own drops, the host leaving ends the guest's hunt. Solo
## hunts keep their old drop roll.


class CoopShell:
	extends HHHuntShellStub
	var net: Object = null
	var session: Object = null


class RngDrops:
	extends RefCounted
	func roll(_monster: String, rng: RandomNumberGenerator, _weapon: String = "", _owned: Array = []) -> Array:
		return ["roll_%d" % rng.randi()]


func _scratch() -> void:
	HHSave.path = "user://test_coop_hunt_hunter.json"
	HHLobbyState.last_path = "user://test_coop_hunt_last.json"
	HHLobbyState.runs_path = "user://test_coop_hunt_runs.json"


func _restore() -> void:
	for p in [HHSave.path, HHLobbyState.last_path, HHLobbyState.runs_path]:
		if str(p).begins_with("user://test_coop_hunt") and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	HHSave.path = HHSave.DEFAULT_PATH
	HHLobbyState.last_path = HHLobbyState.LAST_PATH
	HHLobbyState.runs_path = HHLobbyState.RUNS_PATH


func _shell(hub: HHCoopFakeHub, host: bool, name: String) -> CoopShell:
	var ns := hub.peer(host)
	if not host:
		(ns[0] as HHCoopFakeNet).join("127.0.0.1")
	var sh := CoopShell.new()
	sh.net = ns[0]
	sh.session = ns[1]
	(ns[1] as HHCoopFakeSession).set_mine({ "name": name, "weapon": "lance", "ready": false })
	return sh


func test_coop_hunt_flow(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var hub := HHCoopFakeHub.new()
	var hs := _shell(hub, true, "Ana")
	var gs := _shell(hub, false, "Bo")
	var host := HHHunt.start(hs, { "seed": 4 })
	var guest := HHHunt.start(gs, { "seed": 4 })
	host.immediate = true
	guest.immediate = true
	c.eq(host.role, "host", "the host's hunt is the host")
	c.eq(guest.role, "client", "the guest's is a client")
	var hm: HHWorldMap = host.node
	var gm: HHWorldMap = guest.node
	c.eq(gm.disturbance, hm.disturbance, "same seed, same stir on both maps")
	c.eq(gm.coop_role, "client", "the guest's map knows it does not decide")
	# the guest walks onto the stir: its own map must not spring it
	var sp: Vector3 = gm.sites[gm.disturbance].pos
	gm.teleport(sp.x, sp.z)
	gm._process(1.0 / 60.0)
	c.ok(hm.remotes.has(gs.net.peer_id()), "the host's map shows the guest's token")
	c.eq(gm.my_name, "Bo", "the guest's token carries its name")
	c.ok(guest.screen == "ambush" or guest.screen == "map", "the guest did not approach on its own")
	c.eq(host.screen, "map", "the host has not checked yet")
	hm._process(1.0 / 60.0)
	c.eq(host.screen, "ambush", "the host's map saw the guest's token at the stir and approached")
	c.eq(guest.screen, "ambush", "the approach reached the guest: its ambush plays")
	c.eq(str(guest.state.cfg.monster), str(hm.sites[hm.disturbance].monster), "the guest hunts the host's monster")
	c.eq(str(guest.state.cfg.arena), str(host.state.cfg.arena), "in the same arena")
	# prep -> fight: the session's start hands each lobby its cfg (see test_lobby_coop); here it arrives as the prep result
	host.node.finished.emit({ "result": "skipped" })
	guest.node.finished.emit({ "result": "skipped" })
	c.eq(guest.screen, "prep", "guest at prep")
	c.ok(guest.state.cfg.locked.has("monster"), "prep locks the monster")
	var players := [{ "peer": 1, "id": "p1", "name": "Ana", "weapon": "lance" }, { "peer": gs.net.peer_id(), "id": "p2", "name": "Bo", "weapon": "bow" }]
	guest.node.finished.emit({ "result": "fight", "cfg": { "weapon": "bow", "players": players, "local_id": "p2", "net": "client", "monster": "colambros" } })
	c.eq(guest.screen, "fight", "guest fights")
	c.ok(gs.current is HHFight, "a fight was built")
	if gs.current is HHFight:
		var f: HHFight = gs.current
		c.eq(f.net_mode, "client", "in client mode")
		c.eq(f.player_id, "p2", "driving p2")
		c.eq(f.sim.players().size(), 2, "with both hunters")
		c.eq(f.monster_id, str(hm.sites[hm.disturbance].monster), "the locked monster, not the prep's")
	guest.node.finished.emit({ "result": "win", "ticks": 600, "hp": 1500.0, "monster_hp": 0.0, "local_id": "p2" })
	c.eq(guest.screen, "results", "guest results")
	var res: HHResults = guest.node
	c.eq(str(res.cfg.get("net", "")), "client", "results know it was a party fight")
	# the host leaves: the guest's hunt ends with a note
	var ended := []
	guest.ended.connect(func(): ended.append(true))
	(gs.net as HHCoopFakeNet).drop()
	c.eq(ended.size(), 1, "the guest's hunt ended when the host left")
	c.ok(guest.end_note.contains("host left"), "with a note for the lobby")
	host.free()
	hs.free()
	gs.free()
	hub.free_all()
	_restore()


func test_guest_approach_waits_for_map(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var hub := HHCoopFakeHub.new()
	var gs := _shell(hub, false, "Bo")
	var guest := HHHunt.start(gs, { "seed": 2 })
	guest.immediate = true
	guest.screen = "results"                         # pretend the guest is still reading its results
	guest._on_message(1, "approach", { "monster": "spirewalker", "arena": "glade", "site": 1 })
	c.eq(guest._pending_approach.get("monster", ""), "spirewalker", "held while off the map")
	var m := HHWorldMap.new()
	guest._coop_map(m)
	c.ok(guest._pending_approach.is_empty() and str(m.approach_on_setup.get("monster", "")) == "spirewalker", "handed to the next map")
	m.free()
	gs.free()
	hub.free_all()
	_restore()


func test_party_drops_are_per_hunter(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var fight := { "result": "win", "ticks": 777, "hp": 100.0, "monster_hp": 0.0 }
	var rolls := []
	for who in ["p1", "p2", ""]:
		var r := HHResults.new()
		r.record_run = false
		r.inject(RngDrops.new(), null)
		var cfg := { "monster": "swampfang", "arena": "pond", "seed": 5, "weapon": "lance" }
		if who != "":
			cfg.net = "client"
			cfg.local_id = who
		r.setup({ "cfg": cfg, "fight": fight })
		rolls.append(r.drops)
		r.free()
	c.ok(rolls[0] != rolls[1], "p1 and p2 roll different drops from one fight")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("drops-%s-%d-%d" % ["swampfang", 5, 777])
	c.eq(rolls[2], ["roll_%d" % rng.randi()], "solo keeps the old roll")
	_restore()


func test_solo_hunt_has_no_party(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var sh := HHHuntShellStub.new()
	var h := HHHunt.start(sh, { "seed": 1 })
	c.eq(h.role, "solo", "a shell without a net: solo hunt")
	c.eq((h.node as HHWorldMap).coop_role, "solo", "a solo map")
	c.ok(not h.state.cfg.has("net"), "no net key in a solo hunt")
	sh.free()
	_restore()
