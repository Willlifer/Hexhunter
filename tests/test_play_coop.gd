extends RefCounted
## Lane C (H900+): the multi-hunter fight. A cfg with `players` builds every
## hunter (own weapon / elements / upgrades, distinct spawn hexes), input
## drives only `local_id`, the host merges a remote peer's orders under that
## peer's own hunter and publishes, a client never steps its mirror and its
## orders go out through the replicator, downed / revive state reads from the
## unit and the events, the payload carries every hunter. Solo is untouched.


const TWO := [
	{ "peer": 1, "id": "p1", "name": "Ana", "weapon": "lance", "element": "fire", "backup": "water" },
	{ "peer": 2, "id": "p2", "name": "Bo", "weapon": "bow", "element": "ice", "backup": "thunder", "upgrades": { "q": [], "w": [], "e": [], "r": [] } },
]


func _fight(cfg: Dictionary) -> HHFight:
	var base := { "arena": "round", "monster": "swampfang", "seed": 3, "headless": true }
	base.merge(cfg, true)
	var f := HHFight.new()
	f.setup_cfg(base)
	return f


func _four() -> Array:
	var out: Array = TWO.duplicate(true)
	out.append({ "peer": 3, "id": "p3", "name": "Cy", "weapon": "daggers", "element": "dark", "backup": "light" })
	out.append({ "peer": 4, "id": "p4", "name": "Di", "weapon": "lance", "element": "wind", "backup": "fire" })
	return out


func test_solo_default_is_one_hunter(c: HHSelfTest.HHCheck) -> void:
	var f := _fight({ "weapon": "daggers", "element": "thunder", "backup": "dark" })
	c.eq(f.sim.players().size(), 1, "solo: one hunter")
	c.eq(f.player_id, "p1", "solo drives p1")
	c.eq(f.net_mode, "solo", "solo net mode")
	c.eq(str(f.sim.unit("p1").weapon), "daggers", "the cfg's own weapon")
	c.eq(f.replicator, null, "solo has no replicator")
	c.ok(f.get_node_or_null("Replicator") == null, "and no replicator node")
	f._process(HHSim.TICK)
	c.eq(f.steps_taken, 1, "solo steps its sim")
	f.free()


func test_two_hunters_from_cfg(c: HHSelfTest.HHCheck) -> void:
	var f := _fight({ "players": TWO, "local_id": "p2" })
	c.eq(f.sim.players().size(), 2, "two hunters in the sim")
	c.eq(f.player_id, "p2", "local_id drives p2")
	c.eq(f.weapon, "bow", "the local hunter's weapon is the fight's weapon")
	var a := f.sim.unit("p1")
	var b := f.sim.unit("p2")
	c.eq(str(a.weapon), "lance", "p1 keeps its weapon")
	c.eq(str(b.weapon), "bow", "p2 has its own weapon")
	c.eq(str(b.element), "ice", "p2 has its own element")
	c.eq(str(b.backup), "thunder", "p2 has its own backup")
	c.ok(a.hex != b.hex, "they stand on different hexes")
	c.ok(f.arena.walkable(a.hex) and f.arena.walkable(b.hex), "both on walkable ground")
	f.free()


func test_four_hunters_fan_out(c: HHSelfTest.HHCheck) -> void:
	var f := _fight({ "players": _four(), "local_id": "p3" })
	c.eq(f.sim.players().size(), 4, "four hunters")
	var seen := {}
	for p in f.sim.players():
		seen[p.hex] = true
		c.ok(f.arena.walkable(p.hex), "%s on walkable ground" % p.id)
	c.eq(seen.size(), 4, "four distinct spawn hexes")
	c.eq(str(f.sim.unit("p3").weapon), "daggers", "p3 daggers")
	c.eq(f.player_id, "p3", "local p3")
	f.free()


func test_input_drives_only_local(c: HHSelfTest.HHCheck) -> void:
	var f := _fight({ "players": TWO, "local_id": "p2" })
	var p1_hex: Vector2i = f.sim.unit("p1").hex
	var start: Vector3 = f.sim.unit("p2").pos
	var goal: Vector2i = f.sim.unit("p2").hex + Vector2i(3, -2)
	f._order({ "move": goal, "move_pos": f.arena.stand(goal) })
	f._order({ "run": true })
	c.eq(f._pending.keys(), ["p2"], "input lands under the local hunter only")
	for i in 20:
		f._process(HHSim.TICK)
	c.ok((f.sim.unit("p2").pos as Vector3).distance_to(start) > 0.5, "p2 moved toward the click")
	c.eq(f.sim.unit("p1").hex, p1_hex, "p1 did not move")
	f.free()


func test_host_merges_remote_orders(c: HHSelfTest.HHCheck) -> void:
	var f := _fight({ "players": TWO, "local_id": "p1", "net": "host" })
	c.ok(f.replicator != null, "a host has a replicator")
	c.ok(f.replicator is HHCoopStubReplicator or ResourceLoader.exists(HHFight.REPLICATOR_PATH), "the stub stands in until Lane N lands")
	if not (f.replicator is HHCoopStubReplicator):
		f.free()
		return
	var r: HHCoopStubReplicator = f.replicator
	var p1_hex: Vector2i = f.sim.unit("p1").hex
	var start: Vector3 = f.sim.unit("p2").pos
	var goal: Vector2i = f.sim.unit("p2").hex + Vector2i(-3, -2)
	r.queue(2, { "move": goal, "move_pos": f.arena.stand(goal) })
	for i in 15:
		f._process(HHSim.TICK)
	c.ok((f.sim.unit("p2").pos as Vector3).distance_to(start) > 0.5, "peer 2's order moved p2")
	c.eq(f.sim.unit("p1").hex, p1_hex, "and nobody else")
	c.ok(r.collected >= 15, "collect() asked every tick")
	c.eq(r.published.size(), f.steps_taken, "published once per step")
	c.ok(f.steps_taken >= 15, "the host steps")
	c.eq(int(r.published[-1].tick), f.sim.tick, "with the sim's tick")
	f.free()


func test_client_never_steps(c: HHSelfTest.HHCheck) -> void:
	var f := _fight({ "players": TWO, "local_id": "p2", "net": "client" })
	c.ok(f.sim.brains.is_empty(), "a client's mirror has no brains")
	c.ok(f.replicator != null, "a client has a replicator")
	f._order({ "stop": true })
	for i in 30:
		f._process(HHSim.TICK)
	c.eq(f.steps_taken, 0, "the client never called sim.step")
	c.eq(f.sim.tick, 0, "the mirror's tick only moves by snapshot")
	if f.replicator is HHCoopStubReplicator:
		var r: HHCoopStubReplicator = f.replicator
		c.eq(r.sent.size(), 1, "the order went out once")
		c.eq(r.sent[0], { "stop": true }, "as the local hunter's order")
		r.deliver([{ "type": "over", "result": "win", "tick": 99 }, { "type": "revive", "id": "p1", "ticks": 45, "total": 90, "tick": 99 }])
		c.ok(f._log.size() > 0 and f._log[-1].contains("OVER: win"), "replicated events reach the fight's event path")
		c.near(f.revive_frac("p1"), 0.5, 0.001, "a replicated revive event fills the ring")
	f.free()


func test_downed_and_revive(c: HHSelfTest.HHCheck) -> void:
	var f := _fight({ "players": TWO, "local_id": "p1" })
	var u := f.sim.unit("p1")
	u.downed = true                          # Lane S's field (H53), forced here
	f._process(0.0)
	c.eq(int(f.downs.get("p1", 0)), 1, "the downed transition counted once")
	f._process(0.0)
	c.eq(int(f.downs.get("p1", 0)), 1, "and only once")
	c.eq(f.follow_id(), "p2", "a downed local hunter spectates the nearest ally")
	f._note({ "type": "revive", "id": "p1", "by": "p2", "frac": 0.3, "tick": 5 })
	c.near(f.revive_frac("p1"), 0.3, 0.001, "frac from the event")
	c.near(HHFight.revive_event_frac({ "ticks": 30, "total": 60 }), 0.5, 0.001, "ticks / total")
	c.near(HHFight.revive_event_frac({ "left": 15, "total": 60 }), 0.75, 0.001, "left counts down")
	for i in 30:
		f._track_downed(0.05)
	c.ok(f.revive_frac("p1") < 0.3, "the ring empties when the events stop")
	u.downed = false
	f._process(0.0)
	c.eq(f.follow_id(), "p1", "back up: the camera is ours again")
	var pl := f.payload("win")
	c.eq((pl.hunters as Array).size(), 2, "the payload carries both hunters")
	c.eq(int(pl.hunters[0].downs), 1, "with p1's down")
	c.eq(str(pl.local_id), "p1", "and who this machine was")
	c.ok(float(pl.max_hp) > 0.0 and float(pl.monster_max_hp) > 0.0, "max hps for the results screen")
	f.free()


func test_party_helpers(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHParty.players_of({}).size(), 1, "solo party of one")
	c.eq(str(HHParty.players_of({ "weapon": "bow" })[0].weapon), "bow", "built from the cfg's own pick")
	c.eq(HHParty.local_id({ "players": TWO, "local_id": "p9" }), "p1", "an unknown local id falls back to the first")
	c.eq(HHParty.mode({ "net": "nonsense" }), "solo", "unknown mode is solo")
	c.eq(HHParty.unit_of_peer({ "players": TWO }), { 1: "p1", 2: "p2" }, "peer -> unit")
	c.eq(HHParty.assign_ids([7, 1, 3]), { 1: "p1", 3: "p2", 7: "p3" }, "ids in peer order")
	c.eq(HHParty.parse_address("10.0.0.2:5000"), ["10.0.0.2", 5000], "address with port")
	c.eq(HHParty.parse_address(" 10.0.0.2 "), ["10.0.0.2", HHParty.PORT], "bare address takes the default port")
	c.ok(HHParty.slot_color("p1") != HHParty.slot_color("p2"), "slots differ in colour")
