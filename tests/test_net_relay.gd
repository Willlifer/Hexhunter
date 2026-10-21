extends RefCounted
## Lane R (H110-H119): online co-op through the relay. The frame codec on its
## own, then HHNet host and client through HHRelayPeer over an in-process fake
## relay (tests/relay_fake.gd): session start, a loopback fight whose mirror
## hash agrees with the host's, and the errors the lobby shows.

const FakeRelay := preload("res://tests/relay_fake.gd")
const ARENA := "round"
const MONSTER := "swampfang"
const URL := "ws://fake-relay"


func _poll(nets: Array, until: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		for n in nets:
			n.poll()
		if until.call():
			return true
		OS.delay_msec(1)
	return false


func _net(relay: Object, nm: String) -> HHNet:
	var n := HHNet.new()
	n.player_name = nm
	n.relay_url = URL
	n.relay_socket = relay.socket_factory()
	return n


func _free(nets: Array) -> void:
	for n in nets:
		n.leave()
		n.free()


func test_codec(c: HHSelfTest.HHCheck) -> void:
	var payload := PackedByteArray([9, 8, 7, 0, 255])
	var f := HHRelayPeer.encode_data(3, 0, HHNet.CH_STREAM, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, payload)
	c.eq(f.size(), HHRelayPeer.HEADER + payload.size(), "header is 5 bytes")
	c.eq(Array(f.slice(0, 5)), [1, 3, 0, 2, 1], "DATA, target, sender, channel, mode")
	var d := HHRelayPeer.decode_data(f)
	c.eq(int(d.target), 3, "target")
	c.eq(int(d.channel), HHNet.CH_STREAM, "channel")
	c.eq(int(d.mode), MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, "mode")
	c.eq(Array(d.payload), Array(payload), "payload round trip")
	c.ok(HHRelayPeer.decode_data(PackedByteArray([1, 0, 0])).is_empty(), "short frame refused")
	c.ok(HHRelayPeer.decode_data(PackedByteArray([2, 0, 0, 0, 0, 5])).is_empty(), "non-DATA frame refused")
	c.eq(HHRelayPeer.decode_data(HHRelayPeer.encode_data(0, 0, 0, 0, PackedByteArray())).payload.size(), 0, "empty payload")
	var h: Variant = JSON.parse_string(HHRelayPeer.hello("host"))
	c.eq(h, { "op": "host", "v": 1.0 }, "host hello")
	var j: Variant = JSON.parse_string(HHRelayPeer.hello("join", "KMRTX"))
	c.eq(j, { "op": "join", "v": 1.0, "room": "KMRTX" }, "join hello")
	c.eq(HHRelayPeer.clean_code(" kmr-tx "), "KMRTX", "codes clean up")
	c.eq(HHRelayPeer.clean_code("KMRT"), "", "four letters is not a code")
	c.eq(HHRelayPeer.clean_code("KMRTB"), "", "B is never in a code")
	c.ok(HHRelayPeer.describe("not_found").begins_with("room not found"), "not_found reads 'room not found'")
	c.ok(HHRelayPeer.describe("full").begins_with("room full"), "full reads 'room full'")
	c.eq(HHRelayPeer.describe("host_left"), "host left", "host_left")
	c.ok(HHRelayPeer.describe("weird", "x").contains("weird"), "unknown codes still say something")


## The fake relay end to end: host, join, session start, a 300-tick fight
## with every mirror hash checked, then the host leaving.
func test_relay_fight_hash_agreement(c: HHSelfTest.HHCheck) -> void:
	var relay := FakeRelay.new()
	var h := _net(relay, "Hosty")
	var k := _net(relay, "Kid")
	var codes := []
	h.room_ready.connect(func(code): codes.append(code))
	c.eq(h.host_online(), OK, "host_online")
	c.ok(h.api.multiplayer_peer is HHRelayPeer, "the host's transport is the relay peer")
	c.ok(_poll([h], func(): return not codes.is_empty(), 2000), "room_ready")
	if codes.is_empty():
		_free([h, k])
		return
	c.eq(str(codes[0]).length(), 5, "a five-letter code")
	c.eq(h.room, str(codes[0]), "HHNet.room")
	c.eq(k.join_online(str(codes[0])), OK, "join_online")
	c.ok(_poll([h, k], func(): return k.is_online() and h.session.members.size() == 2 and k.session.members.size() == 2, 3000), "welcomed; both see two members")
	c.eq(h.peer_id(), 1, "host is peer 1")
	c.ok(k.peer_id() > 1, "the joiner got a relay id (%d)" % k.peer_id())
	c.ok(k.is_relay() and h.is_relay(), "both report the relay")
	h.session.host_set({ "arena": ARENA, "monster": MONSTER, "seed": 1 })
	k.session.set_mine({ "weapon": "daggers", "ready": true })
	h.session.set_mine({ "ready": true })
	c.ok(_poll([h, k], func(): return h.session.all_ready() and k.session.fields.get("arena", "") == ARENA, 3000), "ready rows and host fields propagate")
	var cfgs := {}
	h.session.start_fight.connect(func(cfg): cfgs.host = cfg)
	k.session.start_fight.connect(func(cfg): cfgs.client = cfg)
	c.eq(h.session.start(), OK, "host starts")
	c.ok(_poll([h, k], func(): return cfgs.size() == 2, 3000), "both started")
	if cfgs.size() < 2:
		_free([h, k])
		return
	c.eq(str(cfgs.client.local_id), "p2", "the joiner plays p2")
	c.eq(str(cfgs.client.weapon), "daggers", "its pick travelled")
	var hs := HHNetBench.host_sim(ARENA, MONSTER, 1, cfgs.host.players)
	var ms := HHNetBench.mirror_sim(ARENA, MONSTER, 1, cfgs.client.players)
	var hr := HHReplicator.new()
	hr.setup(h, hs, cfgs.host)
	var kr := HHReplicator.new()
	kr.setup(k, ms, cfgs.client)
	var host_hash := {}
	var checked := 0
	var bad := 0
	var client_steps := 0
	var goal: Vector2i = hs.arena.spawns.player[0] + Vector2i(4, 3)
	for i in 300:
		var ev := hs.step(hr.merge(HHNetBench.bot_orders(hs, hs.tick + 1, ["p2"])))
		host_hash[hs.tick] = hs.state_hash()
		hr.publish(hs.tick, ev)
		h.poll()
		k.poll()
		kr.pump()
		h.poll()
		if host_hash.has(ms.tick) and ms.tick > 0:
			checked += 1
			if ms.state_hash() != int(host_hash[ms.tick]):
				bad += 1
		if ms.tick == 20 and i < 200:
			kr.send_order({ "move": goal, "move_pos": ms.arena.stand(goal) })
	_poll([h, k], func(): kr.pump(); return ms.tick == hs.tick, 2000)
	c.ok(ms.tick == hs.tick, "the mirror caught up (%d / %d)" % [ms.tick, hs.tick])
	c.ok(checked > 250, "hash checked on %d ticks (TCP: none lost)" % checked)
	c.eq(bad, 0, "mirror hash == host hash on every checked tick")
	c.eq(int(kr.stats.mismatches), 0, "packet hashes verified")
	c.eq(int(kr.stats.get("skipped_ticks", 0)), 0, "no skipped ticks over the relay")
	c.eq(hs.unit("p2").hex, goal, "the client's order moved its hunter on the host")
	c.ok(relay.frames > 300, "frames went through the relay (%d, %d B)" % [relay.frames, relay.bytes])
	# H55 over the relay: the host's last word ends the client's fight
	hs.over = "abort"
	hr.publish_final([{ "type": "over", "result": "abort", "tick": hs.tick + 1 }])
	c.ok(_poll([h, k], func(): kr.pump(); return ms.over == "abort", 2000), "the host leaving the fight reaches the mirror")
	hr.free()
	kr.free()
	# the host quits: the client hears "host left"
	var gone := []
	k.disconnected.connect(func(): gone.append(k.last_error))
	h.leave()
	c.ok(_poll([k], func(): return not gone.is_empty(), 2000), "the client notices the host leaving")
	c.ok(not gone.is_empty() and str(gone[0]) == "host left", "with 'host left': %s" % [gone])
	c.eq(relay.rooms.size(), 0, "the room closed")
	_free([h, k])


## The errors the lobby shows: room not found, room full, a mid-hunt refusal,
## a kick, and a sleeping relay that wakes on a retry.
func test_relay_errors(c: HHSelfTest.HHCheck) -> void:
	var relay := FakeRelay.new()
	var bad := _net(relay, "Lost")
	var why := []
	bad.failed.connect(func(): why.append(bad.last_error))
	c.eq(bad.join_online("KMRTX"), OK, "a join starts")
	c.ok(_poll([bad], func(): return not why.is_empty(), 2000), "a wrong code fails")
	c.ok(not why.is_empty() and str(why[0]).begins_with("room not found"), "'room not found': %s" % [why])
	c.ok(not bad.is_client(), "back to nothing")

	relay.max_peers = 2                       # host + one
	var h := _net(relay, "H")
	var a := _net(relay, "A")
	var b := _net(relay, "B")
	h.host_online()
	_poll([h], func(): return h.room != "", 2000)
	a.join_online(h.room)
	c.ok(_poll([h, a], func(): return a.is_online(), 2000), "first joiner in")
	var bwhy := []
	b.failed.connect(func(): bwhy.append(b.last_error))
	b.join_online(h.room)
	c.ok(_poll([h, a, b], func(): return not bwhy.is_empty(), 2000), "the next one is refused")
	c.ok(not bwhy.is_empty() and str(bwhy[0]).begins_with("room full"), "'room full': %s" % [bwhy])

	# HHNet's own refusal (mid-hunt) still travels, then the relay kick drops the peer
	relay.max_peers = 5
	h.accepting = false
	var lwhy := []
	var late := _net(relay, "Late")
	late.failed.connect(func(): lwhy.append(late.last_error))
	late.join_online(h.room)
	c.ok(_poll([h, a, late], func(): return not lwhy.is_empty(), 3000), "a mid-hunt joiner is refused")
	c.ok(not lwhy.is_empty() and str(lwhy[0]).contains("mid-hunt"), "with the host's reason: %s" % [lwhy])
	c.eq(h.peers().size(), 1, "only the first joiner is in the party")
	_free([late, b, a, h])

	# a sleeping relay: two sockets never open, the third does
	relay.asleep = 2
	var s := _net(relay, "Sleepy")
	var lines := []
	var rooms := []
	s.relay_status.connect(func(t): lines.append(t))
	s.room_ready.connect(func(code): rooms.append(code))
	s.host_online()
	(s.api.multiplayer_peer as HHRelayPeer).retry_every_ms = 20
	c.ok(_poll([s], func(): return not rooms.is_empty(), 3000), "the host gets a room after the relay wakes")
	c.ok(lines.any(func(t): return str(t).begins_with("relay asleep, retrying")), "'relay asleep, retrying…' shown: %s" % [lines])
	c.ok(not s.api.multiplayer_peer == null and int((s.api.multiplayer_peer as HHRelayPeer).stats.attempts) == 3, "three attempts")
	_free([s])


## The lobby's Online mode (H114) against the fake net: a room code to show,
## a joiner by code, and the errors as the ticker words them.
func test_lobby_online(c: HHSelfTest.HHCheck) -> void:
	HHSave.path = "user://test_net_relay_hunter.json"
	HHLobbyState.last_path = "user://test_net_relay_last.json"
	HHLobbyState.runs_path = "user://test_net_relay_runs.json"
	var hub := HHCoopFakeHub.new()
	var hn: Array = hub.peer(false)
	var gn: Array = hub.peer(false)
	var hc := HHLobbyCoop.new()
	var gc := HHLobbyCoop.new()
	hc.attach(hn[0], hn[1])
	gc.attach(gn[0], gn[1])
	var notes := []
	gc.note.connect(func(t): notes.append(t))
	c.ok(hc.host_online("Ana"), "host online")
	c.eq(hc.role, "host", "hosting")
	c.ok(hc.online, "online")
	c.eq(hc.share_code(), HHCoopFakeNet.ROOM, "the code to show")
	c.ok(not gc.join_online("KMR", "Bo"), "a short code is refused before the network")
	c.ok(str(notes[-1]).contains("five letters"), "with a hint: %s" % notes[-1])
	c.ok(not gc.join_online("ACDEF", "Bo"), "a wrong code fails")
	c.ok(str(notes[-1]).contains("room not found"), "'room not found': %s" % notes[-1])
	c.eq(gc.role, "solo", "back to solo")
	c.ok(gc.join_online(" kmr-tx ", "Bo"), "joins by the code (typed loosely)")
	c.eq(gc.role, "client", "in the party")
	c.eq(gc.address, "room KMRTX", "the address reads as the room")
	c.eq(gc.share_code(), "", "only the host shows the code big")
	(gn[0] as HHCoopFakeNet).last_error = "host left"
	(gn[0] as HHCoopFakeNet).drop()
	c.ok(str(notes[-1]).begins_with("Host left"), "'Host left': %s" % notes[-1])
	hc.detach()
	gc.detach()
	hub.free_all()
	HHSave.path = HHSave.DEFAULT_PATH
	HHLobbyState.last_path = HHLobbyState.LAST_PATH
	HHLobbyState.runs_path = HHLobbyState.RUNS_PATH
