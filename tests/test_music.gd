extends RefCounted
## H431: the author's music: every track loads, loops loop and stings don't,
## and the director picks the right music for each screen and fight moment.


func test_tracks_load(c: HHSelfTest.HHCheck) -> void:
	var m := HHMusic.new()
	for name in HHMusic.LOBBY + ["prefight_a", "prefight_b", "fight", "fight_enrage"]:
		var s := m.stream(name) as AudioStreamWAV
		c.ok(s != null, "%s loads" % name)
		if s != null:
			c.eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % name)
			c.ok(s.get_length() > 7.0 and s.get_length() < 8.5, "%s is a 4-bar loop (%.2f s)" % [name, s.get_length()])
	for name in ["sting_title", "sting_fight", "victory"]:
		var s := m.stream(name) as AudioStreamWAV
		c.ok(s != null and s.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s plays once" % name)
	m.free()


func test_director(c: HHSelfTest.HHCheck) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var m := HHMusic.new()
	root.add_child(m)
	var lobby := HHLobby.new()
	m.on_screen(lobby)
	c.eq(m.state, "lobby", "the lobby builds")
	c.eq(m.track, HHMusic.LOBBY[0], "... from the drums")
	m._on_loop_end()
	c.eq(m.track, HHMusic.LOBBY[1], "a loop end adds a layer")
	for i in 5:
		m._on_loop_end()
	c.eq(m.track, HHMusic.LOBBY[3], "... and the full mix holds")
	var fight := HHFight.new()
	m.on_screen(fight)
	c.eq(m.state, "fight", "a fight")
	c.eq(m.track, "fight", "the fight loop")
	var sim := HHSim.new(HHArena.round_flat(1, 10.0, 0.0), 1)
	var mon := sim.add_monster("m", Vector2i(0, 0), 1000.0, 1)
	fight.set("sim", sim)
	m._watch_fight()
	c.ok(not m.enraged, "calm while the monster is healthy")
	mon.hp = 400.0
	m._watch_fight()
	m._on_loop_end()
	c.eq(m.track, "fight_enrage", "below half HP: enrage from the next loop")
	sim.over = "win"
	m._watch_fight()
	c.eq(m.track, "victory", "a win plays the victory")
	m.free()
	fight.free()
	lobby.free()
