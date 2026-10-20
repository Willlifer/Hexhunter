extends RefCounted
## Lane C (H908-H914): the lobby's "Play together" state against an
## in-process fake net + session (HHCoopFakeHub): hosting and joining, the
## host's arena / monster / seed flowing to a client and locked there, each
## peer's own kit, the ready gate, the start handing each peer its own cfg,
## errors dropping back to solo, and the panel itself on a live lobby node.


## The self-test already points these at scratch files; one_suite.gd does
## not, so every test here does it itself (never the player's files).
func _scratch() -> void:
	HHSave.path = "user://test_lobby_coop_hunter.json"
	HHLobbyState.last_path = "user://test_lobby_coop_last.json"
	HHLobbyState.runs_path = "user://test_lobby_coop_runs.json"


func _restore() -> void:
	for p in [HHSave.path, HHLobbyState.last_path, HHLobbyState.runs_path]:
		if str(p).begins_with("user://test_lobby_coop") and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	HHSave.path = HHSave.DEFAULT_PATH
	HHLobbyState.last_path = HHLobbyState.LAST_PATH
	HHLobbyState.runs_path = HHLobbyState.RUNS_PATH


func _peer(hub: HHCoopFakeHub, host: bool) -> Array:
	var ns := hub.peer(host)
	var co := HHLobbyCoop.new()
	var st := HHLobbyState.new()
	st.setup({})
	co.attach(ns[0], ns[1])
	return [co, st, ns[0], ns[1]]


func test_host_and_join(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var hub := HHCoopFakeHub.new()
	var h := _peer(hub, false)
	var g := _peer(hub, false)
	var hc: HHLobbyCoop = h[0]
	var gc: HHLobbyCoop = g[0]
	var notes: Array = []
	gc.note.connect(func(t): notes.append(t))
	c.eq(hc.role, "solo", "starts solo")
	c.ok(hc.host_game("Ana"), "host")
	c.eq(hc.role, "host", "now hosting")
	c.ok(hc.address.ends_with(":%d" % HHParty.PORT), "the address shows the port: %s" % hc.address)
	c.ok(gc.join_game("127.0.0.1", "Bo"), "join")
	c.eq(gc.role, "client", "connected -> client")
	c.ok(notes.size() > 0 and str(notes[-1]).begins_with("Joined"), "the ticker says so")
	hc.push(h[1])
	gc.push(g[1])
	var rows := hc.party_rows()
	c.eq(rows.size(), 2, "two in the party list")
	c.eq(str(rows[0].name), "Ana", "host first")
	c.ok(bool(rows[0].host) and bool(rows[0].me), "host row is the host and me")
	c.eq(str(rows[1].id), "p2", "guest is p2")
	hub.free_all()
	_restore()


func test_host_fields_lock_for_clients(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var hub := HHCoopFakeHub.new()
	var h := _peer(hub, false)
	var g := _peer(hub, false)
	var hc: HHLobbyCoop = h[0]
	var gc: HHLobbyCoop = g[0]
	var hs: HHLobbyState = h[1]
	var gs: HHLobbyState = g[1]
	hc.host_game("Ana")
	gc.join_game("127.0.0.1", "Bo")
	hs.pick("monster", "rimeslithe")
	hs.set_seed(42)
	hc.push(hs)
	gs.coop_locks = gc.locks()
	gc.pull(gs)
	c.eq(str(gs.cfg.monster), "rimeslithe", "the client follows the host's monster")
	c.eq(str(gs.cfg.arena), "cave", "and the arena it dragged along")
	c.eq(int(gs.cfg.seed), 42, "and the seed")
	c.ok(gs.is_locked("arena") and gs.is_locked("monster") and gs.is_locked("seed"), "host-only fields are locked for the client")
	c.ok(not gs.pick("monster", "colambros"), "a client cannot pick the monster")
	c.ok(not gs.set_seed(7), "nor the seed")
	c.ok(gs.pick("weapon", "bow"), "but picks its own weapon")
	c.ok(gs.pick_element("ice"), "and its own elements")
	c.eq(hc.locks(), [], "the host locks nothing")
	gc.push(gs)
	var guest_row: Dictionary = hub.members.get(gc.my_peer(), {})
	c.eq(str(guest_row.get("weapon", "")), "bow", "the guest's own weapon reaches the session")
	c.eq(str(hs.cfg.weapon), "lance", "the host's weapon is untouched")
	hub.free_all()
	_restore()


func test_ready_gate_and_start(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var hub := HHCoopFakeHub.new()
	var h := _peer(hub, false)
	var g := _peer(hub, false)
	var hc: HHLobbyCoop = h[0]
	var gc: HHLobbyCoop = g[0]
	var hs: HHLobbyState = h[1]
	var gs: HHLobbyState = g[1]
	hc.host_game("Ana")
	c.ok(not hc.can_start(), "alone: no start")
	gc.join_game("127.0.0.1", "Bo")
	gs.pick("weapon", "daggers")
	hc.push(hs)
	gc.push(gs)
	c.ok(not hc.can_start(), "guest not ready: no start")
	c.ok(not hc.start(hs), "start refused")
	c.ok(not gc.can_start(), "a client never starts")
	var got := {}
	hc.started.connect(func(cfg): got["host"] = hc.launch_cfg(hs, cfg))
	gc.started.connect(func(cfg): got["guest"] = gc.launch_cfg(gs, cfg, { "autoplay": true }))
	gc.toggle_ready(gs)
	c.ok(gc.ready, "guest ready")
	c.ok(hc.can_start(), "everyone else ready: the host may start")
	c.ok(hc.start(hs), "start")
	c.ok(got.has("host") and got.has("guest"), "both peers got a start cfg")
	if got.has("host") and got.has("guest"):
		var a: Dictionary = got.host
		var b: Dictionary = got.guest
		c.eq(str(a.net), "host", "host cfg is host mode")
		c.eq(str(b.net), "client", "guest cfg is client mode")
		c.eq(str(a.local_id), "p1", "host drives p1")
		c.eq(str(b.local_id), "p2", "guest drives p2")
		c.eq((b.players as Array).size(), 2, "two players")
		c.eq(str(b.weapon), "daggers", "the guest's top-level weapon is its own")
		c.eq(str(b.arena), str(hs.cfg.arena), "the host's arena")
		c.eq(bool(b.get("autoplay", false)), true, "per-process extras ride along")
		c.eq(str(HHParty.entry(a, "p2").weapon), "daggers", "the host's cfg knows the guest's weapon")
	hub.free_all()
	_restore()


func test_errors_return_to_solo(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var hub := HHCoopFakeHub.new()
	var h := _peer(hub, false)
	var g := _peer(hub, false)
	var hc: HHLobbyCoop = h[0]
	var gc: HHLobbyCoop = g[0]
	var notes: Array = []
	gc.note.connect(func(t): notes.append(t))
	(g[2] as HHCoopFakeNet).refuse = true
	gc.join_game("10.9.9.9", "Bo")
	c.eq(gc.role, "solo", "cannot connect: back to solo")
	c.ok(str(notes[-1]).contains("Could not connect"), "and the ticker says why: %s" % str(notes[-1]))
	(g[2] as HHCoopFakeNet).refuse = false
	hc.host_game("Ana")
	gc.join_game("127.0.0.1", "Bo")
	c.eq(gc.role, "client", "joined on retry")
	(g[2] as HHCoopFakeNet).drop()
	c.eq(gc.role, "solo", "host left: back to solo")
	c.ok(str(notes[-1]).contains("host left"), "the ticker says the host left")
	c.eq(gc.locks(), [], "nothing locked once solo")
	var bare := HHLobbyCoop.new()
	var bn: Array = []
	bare.note.connect(func(t): bn.append(t))
	c.ok(not bare.host_game("X"), "no network layer: hosting refused")
	c.ok(bn.size() == 1 and str(bn[0]).contains("network"), "with a note")
	hub.free_all()
	_restore()


func test_lobby_panel_live(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var hub := HHCoopFakeHub.new()
	var hp := hub.peer(false)
	var gp := hub.peer(false)
	var host := HHLobby.new()
	host.coop.attach(hp[0], hp[1])
	host.setup({})
	root.add_child(host)
	var guest := HHLobby.new()
	guest.coop.attach(gp[0], gp[1])
	guest.setup({})
	root.add_child(guest)
	c.ok(host._coop_solo.visible and not host._coop_party.visible, "solo: name / Host / address / Join showing")
	host.coop.host_game("Ana")
	c.ok(host._coop_party.visible and not host._coop_solo.visible, "hosting: the party panel")
	c.ok(host._coop_status.text.contains(str(HHParty.PORT)), "the status shows the address and port")
	guest._addr_edit.text = "127.0.0.1"
	guest._name_edit.text = "Bo"
	guest._join()
	host._pick("monster", "colambros")
	c.eq(str(guest.state.cfg.monster), "colambros", "the guest's lobby follows the host's monster")
	c.ok((guest._tiles["monster"][0] as HHLobbyTile).locked, "the guest's monster tiles are greyed")
	c.ok(not (host._tiles["monster"][0] as HHLobbyTile).locked, "the host's are not")
	c.eq(host._party_box.get_child_count() - _queued(host._party_box), 2, "two party rows")
	c.ok(host._fight_btn.disabled, "host FIGHT waits for ready")
	c.ok(guest._fight_btn.disabled and guest._fight_btn.text == "HOST STARTS", "the guest has no FIGHT")
	var out: Array = []
	host.finished.connect(func(r): out.append(["host", r]))
	guest.finished.connect(func(r): out.append(["guest", r]))
	guest._ready_btn.button_pressed = true
	guest._ready_btn.pressed.emit()
	c.ok(guest.coop.ready, "the Ready toggle readied the guest")
	c.ok(not host._fight_btn.disabled, "host FIGHT is live once everyone is ready")
	host._fight()
	c.eq(out.size(), 2, "both lobbies launched")
	if out.size() == 2:
		var gcfg: Dictionary = out[1][1].cfg
		c.eq(str(out[1][1].result), "fight", "as a fight")
		c.eq(str(gcfg.monster), "colambros", "on the host's monster")
		c.eq(str(gcfg.local_id), "p2", "the guest drives p2")
	root.remove_child(host)
	root.remove_child(guest)
	host.free()
	guest.free()
	hub.free_all()
	_restore()


func test_lobby_drops_session_keys(c: HHSelfTest.HHCheck) -> void:
	_scratch()
	var st := HHLobbyState.new()
	st.setup({ "players": [{ "id": "p1" }], "local_id": "p2", "net": "client", "monster": "colambros" })
	for k in HHParty.SESSION_KEYS:
		c.ok(not st.launch_cfg().has(k), "%s does not leak into a solo launch" % k)
	c.eq(str(st.cfg.monster), "colambros", "other keys still prefill")
	_restore()


func _queued(n: Node) -> int:
	var q := 0
	for ch in n.get_children():
		if ch.is_queued_for_deletion():
			q += 1
	return q
