extends RefCounted
## Lane UI (H800+, L-19): the lobby's run history round-trips through the
## redirected path, trims to RUNS_KEEP, and is fed once by a fight routed
## back to the lobby and once by the results screen.


func _clear() -> void:
	if FileAccess.file_exists(HHLobbyState.runs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HHLobbyState.runs_path))


func test_runs_path_is_redirected(c: HHSelfTest.HHCheck) -> void:
	c.ok(HHLobbyState.runs_path != HHLobbyState.RUNS_PATH, "the self-test points the history at a scratch file (%s)" % HHLobbyState.runs_path)


func test_run_history_round_trips(c: HHSelfTest.HHCheck) -> void:
	_clear()
	c.eq(HHLobbyState.load_runs(), [], "no file: no runs")
	var cfg := { "monster": "colambros", "arena": "caldera", "weapon": "daggers", "element": "water", "backup": "ice", "seed": 12, "locked": [] }
	var e := HHLobbyState.run_entry({ "result": "win", "ticks": 2760 }, cfg)
	c.eq(e.monster, "colambros", "entry monster")
	c.eq(e.weapon, "daggers", "entry weapon")
	c.eq([e.element, e.backup], ["water", "ice"], "entry elements")
	c.eq(int(e.seed), 12, "entry seed")
	c.eq(e.result, "win", "entry result")
	c.near(float(e.seconds), 92.0, 0.05, "entry seconds from ticks")
	c.eq(bool(e.hunt), false, "a plain fight")
	HHLobbyState.record_run(e)
	HHLobbyState.record_run(HHLobbyState.run_entry({ "result": "dead", "ticks": 300, "cfg": { "monster": "rimeslithe", "weapon": "bow", "element": "fire", "backup": "wind", "seed": 3, "locked": ["arena"] } }))
	var runs := HHLobbyState.load_runs()
	c.eq(runs.size(), 2, "two rows")
	c.eq(str(runs[0].monster), "rimeslithe", "newest first")
	c.eq(str(runs[0].result), "fallen", "dead reads as fallen")
	c.eq(bool(runs[0].hunt), true, "locked keys mark a hunt")
	c.eq(str(runs[1].monster), "colambros", "older second")
	c.eq(int(runs[1].seed), 12, "seed survives the file")
	c.eq(HHLobbyState.run_verdict(runs[1]), "VICTORY 1:32", "verdict line")
	c.eq(HHLobbyState.run_verdict({ "result": "abort", "seconds": 31.0 }), "ABORTED 0:31", "abort line")
	for i in HHLobbyState.RUNS_KEEP + 5:
		HHLobbyState.record_run(HHLobbyState.run_entry({ "result": "win", "ticks": i }, cfg))
	c.eq(HHLobbyState.load_runs().size(), HHLobbyState.RUNS_KEEP, "trimmed to RUNS_KEEP")
	var f := FileAccess.open(HHLobbyState.runs_path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	c.eq(HHLobbyState.load_runs(), [], "a bad file reads as empty")
	_clear()


func test_a_routed_fight_records_one_run(c: HHSelfTest.HHCheck) -> void:
	_clear()
	var shell := HHShell.new()
	var cfg := HHShell.default_cfg()
	cfg.arena = "round"
	cfg.headless = true
	cfg.seed = 9
	shell.play(cfg)
	(shell.screen as HHFight)._finish("abort")
	c.ok(shell.screen is HHLobby, "back in the lobby")
	var runs := HHLobbyState.load_runs()
	c.eq(runs.size(), 1, "one run recorded")
	if runs.size() == 1:
		c.eq(str(runs[0].result), "abort", "with the result")
		c.eq(int(runs[0].seed), 9, "and the seed")
	(shell.screen as HHLobby).setup(cfg)
	c.eq(HHLobbyState.load_runs().size(), 1, "a second setup does not record it again")
	shell.free()
	var plain := HHLobby.new()
	plain.setup({})
	c.eq(HHLobbyState.load_runs().size(), 1, "a lobby with no result records nothing")
	plain.free()
	_clear()


func test_results_record_a_run(c: HHSelfTest.HHCheck) -> void:
	_clear()
	var r := HHResults.new()
	r.inject(null, null)
	r.setup({ "cfg": { "monster": "swampfang", "arena": "pond", "seed": 2, "weapon": "lance", "element": "fire", "backup": "water", "locked": ["arena", "monster"] },
		"fight": { "result": "win", "ticks": 900, "hp": 2000.0, "monster_hp": 0.0 } })
	var runs := HHLobbyState.load_runs()
	c.eq(runs.size(), 1, "the results screen recorded the hunt")
	if runs.size() == 1:
		c.eq(str(runs[0].monster), "swampfang", "its monster")
		c.eq(bool(runs[0].hunt), true, "marked as a hunt")
	r.reveal_at(10.0)
	c.ok(r.get_child_count() > 0, "the screen built and the reveal finished")
	r.free()
	var quiet := HHResults.new()
	quiet.record_run = false
	quiet.inject(null, null)
	quiet.setup({ "cfg": { "monster": "swampfang" }, "fight": { "result": "fallen", "ticks": 10 } })
	c.eq(HHLobbyState.load_runs().size(), 1, "record_run = false records nothing")
	quiet.free()
	_clear()


func test_lobby_element_hint(c: HHSelfTest.HHCheck) -> void:
	var lobby := HHLobby.new()
	lobby.state.setup({})
	c.eq(lobby.next_hint(), "next click sets the ACTIVE element", "phase 0: active")
	lobby.state.pick_element("ice")
	c.eq(lobby.next_hint(), "next click sets the BACKUP element", "phase 1: backup")
	lobby.state.locked = ["element"]
	c.eq(lobby.next_hint(), "locked for this hunt", "locked")
	lobby.free()
