extends RefCounted
## Lane N (H52): snapshots, deltas, Callable stripping, the session's launch
## cfg, and a headless loopback fight (host + client HHNet in one process on
## 127.0.0.1, polled by hand) whose mirror hash agrees with the host's.

const ARENA := "round"
const MONSTER := "swampfang"


func _fight(players: Array) -> Array:
	var a := HHNetBench.load_arena(ARENA, 1)
	var b := HHNetBench.load_arena(ARENA, 1)
	return [HHNetBench.host_sim(ARENA, MONSTER, 1, players, a), HHNetBench.mirror_sim(ARENA, MONSTER, 1, players, b)]


## 60 s of a bot fight (monster brain, telegraphs, knives, charge): every
## tick goes over as a delta through encode/decode, every 30th as a full.
func test_snapshot_and_delta_round_trip(c: HHSelfTest.HHCheck) -> void:
	var players := HHNetBench.party(2)
	var pair := _fight(players)
	var host: HHSim = pair[0]
	var mirror: HHSim = pair[1]
	var full_mirror: HHSim = _fight(players)[1]
	var prev := HHSnapshot.capture(host)
	HHSnapshot.apply(mirror, HHSnapshot.decode(HHSnapshot.encode(prev)))
	c.eq(mirror.state_hash(), host.state_hash(), "a full apply at tick 0 matches")
	var seen := { "tg": 0, "pr": 0, "charge": 0, "windup": 0, "leap": 0 }
	var bad_delta := 0
	var bad_full := 0
	var fulls := 0
	for i in 1800:
		host.step(HHNetBench.bot_orders(host, host.tick + 1))
		var cur := HHSnapshot.capture(host)
		var d: Dictionary = HHSnapshot.decode(HHSnapshot.encode(HHSnapshot.delta(prev, cur)))
		if not HHSnapshot.apply_delta(mirror, d) or mirror.state_hash() != host.state_hash():
			bad_delta += 1
		if host.tick % 30 == 0:
			fulls += 1
			HHSnapshot.apply(full_mirror, HHSnapshot.decode(HHSnapshot.encode(cur)))
			if full_mirror.state_hash() != host.state_hash() or not HHSnapshot.same(HHSnapshot.capture(full_mirror), cur):
				bad_full += 1
			if not HHSnapshot.same(HHSnapshot.capture(mirror), cur):
				bad_delta += 1
		prev = cur
		seen.tg = maxi(seen.tg, host.telegraphs.size())
		seen.pr = maxi(seen.pr, host.projectiles.size())
		seen.charge = maxi(seen.charge, host.charge.entries.size())
		for u in host.units.values():
			if not (u.windup as Dictionary).is_empty():
				seen.windup += 1
			if not (u.leap as Dictionary).is_empty():
				seen.leap += 1
		if host.over != "":
			break
	c.ok(host.tick >= 1800, "the fight ran 60 s (tick %d, over '%s')" % [host.tick, host.over])
	c.ok(seen.tg > 0 and seen.pr > 0 and seen.charge > 0 and seen.windup > 0 and seen.leap > 0,
		"the fight had telegraphs, projectiles, charge, wind-ups and leaps: %s" % [seen])
	c.eq(bad_delta, 0, "every delta tick: mirror hash == host hash")
	c.eq(bad_full, 0, "every full snapshot (%d): mirror hash == host hash and same state" % fulls)


func test_delta_is_small_and_exact(c: HHSelfTest.HHCheck) -> void:
	var pair := _fight(HHNetBench.party(1))
	var host: HHSim = pair[0]
	var mirror: HHSim = pair[1]
	host.sandbox = true
	host.step({ "p1": { "paint": { "element": "fire", "hex": host.unit("p1").hex, "steps": 3 } } })
	var prev := HHSnapshot.capture(host)
	HHSnapshot.apply(mirror, prev)
	host.step({})
	var cur := HHSnapshot.capture(host)
	var d := HHSnapshot.delta(prev, cur)
	c.ok(not d.has("c"), "a quiet tick ships no charge: decay is predicted (%s)" % [d.get("c", {})])
	c.ok(HHSnapshot.apply_delta(mirror, d), "delta applies on its base")
	c.eq(mirror.state_hash(), host.state_hash(), "hash agrees after a predicted-decay delta")
	c.ok(not HHSnapshot.apply_delta(mirror, d), "the same delta again is refused (wrong base)")
	c.ok(HHSnapshot.encode(d).size() < 600, "a quiet tick is small (%d B)" % HHSnapshot.encode(d).size())


func test_callables_stripped(c: HHSelfTest.HHCheck) -> void:
	var pair := _fight(HHNetBench.party(1))
	var host: HHSim = pair[0]
	var mirror: HHSim = pair[1]
	var u := host.unit("p1")
	host.begin_windup(u, "test", 20, { "cb": Callable(host, "step"), "n": 3 }, Callable(host, "_potion_land"))
	host.begin_leap(u, u.hex + Vector2i(2, 0), 15, Callable(host, "_potion_land"))
	var s := HHSnapshot.capture(host)
	c.eq(s.u.p1.windup.on_done, null, "windup.on_done -> null")
	c.eq(s.u.p1.windup.data.cb, null, "a Callable inside windup.data -> null")
	c.eq(s.u.p1.leap.on_land, null, "leap.on_land -> null")
	c.ok((u.windup.on_done as Callable).is_valid(), "the host's own unit keeps its Callable")
	var bytes := HHSnapshot.encode(s)
	var back: Dictionary = HHSnapshot.decode(bytes)
	c.ok(back.u.p1.pos is Vector3 and back.u.p1.hex is Vector2i, "Vector3 / Vector2i survive the wire")
	HHSnapshot.apply(mirror, back)
	c.eq(mirror.state_hash(), host.state_hash(), "mirror hash after apply")
	c.ok(mirror.unit("p1").path is Array and (mirror.unit("p1").path as Array).is_typed(), "path stays Array[Vector2i]")


func _port() -> int:
	return 24700 + (Time.get_ticks_usec() % 200)


func _poll(nets: Array, until: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for n in nets:
			n.poll()
		if until.call():
			return true
		OS.delay_msec(2)
	return false


func test_session_start_builds_cfg(c: HHSelfTest.HHCheck) -> void:
	var h := HHNet.new()
	var k := HHNet.new()
	h.player_name = "Hosty"
	k.player_name = "Kid"
	var port := _port()
	c.eq(h.host(port), OK, "host on %d" % port)
	c.eq(k.join("127.0.0.1", port), OK, "join")
	c.ok(_poll([h, k], func(): return k.is_online() and h.session.members.size() == 2 and k.session.members.size() == 2, 3000), "client welcomed and both see two members")
	k.session.set_mine({ "weapon": "daggers", "element": "thunder", "backup": "ice", "ready": true, "hp": 9999 })
	h.session.set_mine({ "ready": true })
	h.session.host_set({ "arena": "cave", "monster": "rimeslithe", "seed": 7 })
	c.ok(_poll([h, k], func(): return h.session.all_ready() and k.session.fields.arena == "cave", 3000), "ready rows and host fields propagate")
	c.ok(not (h.session.members[k.peer_id()] as Dictionary).has("hp"), "unknown row keys are dropped")
	var got := []
	k.session.start_fight.connect(func(cfg): got.append(cfg))
	h.session.start_fight.connect(func(cfg): got.append(cfg))
	c.eq(k.session.start(), ERR_UNAUTHORIZED, "a client cannot start")
	c.eq(h.session.start(), OK, "host starts")
	c.ok(_poll([h, k], func(): return got.size() == 2, 3000), "both peers got start_fight")
	if got.size() < 2:
		h.free()
		k.free()
		return
	var hc: Dictionary = got[0] if str(got[0].local_id) == "p1" else got[1]
	var kc: Dictionary = got[1] if str(got[0].local_id) == "p1" else got[0]
	c.eq(hc.net, "host", "host cfg.net")
	c.eq(kc.net, "client", "client cfg.net")
	c.eq(kc.local_id, "p2", "the joiner plays p2")
	c.eq((kc.players as Array).size(), 2, "two players")
	c.eq(int(kc.players[0].peer), 1, "host = peer 1 = p1")
	c.eq(str(kc.players[1].weapon), "daggers", "the joiner's pick travels")
	c.eq(str(kc.weapon), "daggers", "the client's cfg.weapon is its own")
	c.eq(str(hc.arena) + str(hc.monster) + str(hc.seed), "caverimeslithe7", "host fields in the cfg")
	# a late join while the fight runs is refused with a message
	var late := HHNet.new()
	var failed := []
	late.failed.connect(func(): failed.append(late.last_error))
	late.join("127.0.0.1", port)
	c.ok(_poll([h, k, late], func(): return not failed.is_empty(), 3000), "a late joiner is refused")
	c.ok(not failed.is_empty() and str(failed[0]).contains("mid-hunt"), "with the reason: %s" % [failed])
	c.eq(h.peers().size(), 1, "the refused peer never joined the party")
	for n in [late, k, h]:
		n.leave()
		n.free()


func test_loopback_fight_hash_agreement(c: HHSelfTest.HHCheck) -> void:
	var h := HHNet.new()
	var k := HHNet.new()
	var port := _port() + 1
	h.host(port)
	k.join("127.0.0.1", port)
	c.ok(_poll([h, k], func(): return k.is_online() and h.session.members.size() == 2, 3000), "connected")
	h.session.host_set({ "arena": ARENA, "monster": MONSTER, "seed": 1 })
	k.session.set_mine({ "weapon": "daggers", "ready": true })
	h.session.set_mine({ "ready": true })
	_poll([h, k], func(): return h.session.all_ready(), 2000)
	var cfgs := {}
	h.session.start_fight.connect(func(cfg): cfgs.host = cfg)
	k.session.start_fight.connect(func(cfg): cfgs.client = cfg)
	h.session.start()
	c.ok(_poll([h, k], func(): return cfgs.size() == 2, 3000), "both started")
	if cfgs.size() < 2:
		h.free()
		k.free()
		return
	var hs := HHNetBench.host_sim(ARENA, MONSTER, 1, cfgs.host.players)
	var ms := HHNetBench.mirror_sim(ARENA, MONSTER, 1, cfgs.client.players)
	var hr := HHReplicator.new()
	hr.setup(h, hs, cfgs.host)
	var kr := HHReplicator.new()
	kr.setup(k, ms, cfgs.client)
	var events := []
	kr.snapshot_applied.connect(func(ev): events.append_array(ev))
	var host_hash := {}
	var checked := 0
	var bad := 0
	var p2_start: Vector3 = hs.unit("p2").pos
	var goal: Vector2i = hs.arena.spawns.player[0] + Vector2i(4, 3)
	for i in 300:
		var ev := hs.step(hr.merge(HHNetBench.bot_orders(hs, hs.tick + 1, ["p2"])))
		host_hash[hs.tick] = hs.state_hash()
		hr.publish(hs.tick, ev)
		for n in 3:
			h.poll()
			k.poll()
		kr.pump()
		if host_hash.has(ms.tick) and ms.tick > 0:
			checked += 1
			if ms.state_hash() != int(host_hash[ms.tick]):
				bad += 1
		if ms.tick == 20 and i < 200:
			kr.send_order({ "move": goal, "move_pos": ms.arena.stand(goal) })
	_poll([h, k], func(): kr.pump(); return ms.tick == hs.tick, 2000)
	c.ok(ms.tick == hs.tick, "the mirror caught up (%d / %d)" % [ms.tick, hs.tick])
	c.ok(checked > 100, "hash checked on %d ticks" % checked)
	c.eq(bad, 0, "client mirror hash == host hash on every checked tick")
	c.ok(int(kr.stats.fulls) >= 9, "full snapshots arrived (%d)" % int(kr.stats.fulls))
	c.eq(int(kr.stats.mismatches), 0, "the packet hashes all verified")
	c.ok((hs.unit("p2").pos as Vector3).distance_to(p2_start) > 2.0, "the client's order moved its hunter on the host")
	c.eq(hs.unit("p2").hex, goal, "... to the hex it asked for")
	c.ok(events.any(func(e): return str(e.type) == "telegraph") and events.any(func(e): return str(e.type) == "move"), "events arrive (%d)" % events.size())
	hr.free()
	kr.free()
	k.leave()
	h.leave()
	k.free()
	h.free()
