extends RefCounted
## An in-process stand-in for relay/relay.py (protocol v1, H110) with fake
## WebSocketPeer-shaped sockets, so the self-test runs HHNet host and client
## through HHRelayPeer without a network. `socket_factory()` is what
## HHNet.relay_socket takes. Frames are delivered synchronously into the
## receiver's inbox; the peers read them on their next poll.
##
## Knobs: `asleep` (the next N sockets never open: a waking free instance),
## `max_peers`. Counters: `frames`, `bytes`, `rooms_opened`.

const RelayPeer := preload("res://src/net/relay_peer.gd")


class FakeSocket:
	extends RefCounted
	var relay: Object
	var state := WebSocketPeer.STATE_CLOSED
	var url := ""
	var inbox: Array = []            # [bytes, is_string]
	var last_string := false
	var close_code := -1
	var close_reason := ""
	var fail := false
	# relay-side
	var id := 0
	var room := ""
	var helloed := false

	func connect_to_url(u: String, _tls: Variant = null) -> Error:
		url = u
		if not u.begins_with("ws"):
			return ERR_INVALID_PARAMETER
		state = WebSocketPeer.STATE_CONNECTING
		return OK

	func poll() -> void:
		if state == WebSocketPeer.STATE_CONNECTING:
			if fail:
				state = WebSocketPeer.STATE_CLOSED
				close_code = 1006
			else:
				state = WebSocketPeer.STATE_OPEN
				relay.opened(self)

	func get_ready_state() -> int:
		return state

	func send_text(s: String) -> Error:
		if state != WebSocketPeer.STATE_OPEN:
			return ERR_UNCONFIGURED
		relay.on_text(self, s)
		return OK

	func send(b: PackedByteArray, _mode: int = 0) -> Error:
		if state != WebSocketPeer.STATE_OPEN:
			return ERR_UNCONFIGURED
		relay.on_binary(self, b)
		return OK

	func get_available_packet_count() -> int:
		return inbox.size()

	func get_packet() -> PackedByteArray:
		if inbox.is_empty():
			return PackedByteArray()
		var e: Array = inbox.pop_front()
		last_string = bool(e[1])
		return e[0]

	func was_string_packet() -> bool:
		return last_string

	func close(code: int = 1000, reason: String = "") -> void:
		if state == WebSocketPeer.STATE_CLOSED:
			return
		state = WebSocketPeer.STATE_CLOSED
		close_code = code
		close_reason = reason
		relay.closed(self)

	func get_close_code() -> int:
		return close_code

	func get_close_reason() -> String:
		return close_reason

	# relay -> client
	func push_text(d: Dictionary) -> void:
		inbox.append([JSON.stringify(d).to_utf8_buffer(), true])

	func push_bin(b: PackedByteArray) -> void:
		inbox.append([b, false])


var rooms := {}                      # code -> { host: FakeSocket, peers: { id: FakeSocket }, next: int }
var asleep := 0
var max_peers := 5
var frames := 0
var bytes := 0
var rooms_opened := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 7


func socket_factory() -> Callable:
	return func() -> Object:
		var s := FakeSocket.new()
		s.relay = self
		if asleep > 0:
			asleep -= 1
			s.fail = true
		return s


func opened(_s: FakeSocket) -> void:
	pass


func _error(s: FakeSocket, code: String) -> void:
	s.push_text({ "op": "error", "code": code, "msg": code })
	_leave(s)
	# the real relay lingers a second so the client reads it and closes first


func on_text(s: FakeSocket, t: String) -> void:
	var m: Variant = JSON.parse_string(t)
	if not m is Dictionary:
		_error(s, "bad_request")
		return
	var d: Dictionary = m
	if not s.helloed:
		s.helloed = true
		if int(d.get("v", 0)) != RelayPeer.VERSION:
			_error(s, "version")
			return
		if str(d.get("op", "")) == "host":
			var code := ""
			while code == "" or rooms.has(code):
				code = ""
				for i in RelayPeer.ROOM_LEN:
					code += RelayPeer.ROOM_ALPHABET[_rng.randi_range(0, RelayPeer.ROOM_ALPHABET.length() - 1)]
			rooms[code] = { "host": s, "peers": { 1: s }, "next": 2 }
			rooms_opened += 1
			s.id = 1
			s.room = code
			s.push_text({ "op": "hosted", "room": code, "id": 1, "max": max_peers })
			return
		var code := str(d.get("room", "")).to_upper()
		if not rooms.has(code):
			_error(s, "not_found")
			return
		var r: Dictionary = rooms[code]
		if (r.peers as Dictionary).size() >= max_peers:
			_error(s, "full")
			return
		var pid := int(r.next)
		r.next = pid + 1
		r.peers[pid] = s
		s.id = pid
		s.room = code
		s.push_text({ "op": "joined", "room": code, "id": pid })
		(r.host as FakeSocket).push_text({ "op": "peer_join", "id": pid })
		return
	if str(d.get("op", "")) == "kick" and s.id == 1 and rooms.has(s.room):
		var target: FakeSocket = (rooms[s.room].peers as Dictionary).get(int(d.get("id", 0)))
		if target != null and target != s:
			_error(target, "kicked")
		return
	_error(s, "bad_request")


func on_binary(s: FakeSocket, b: PackedByteArray) -> void:
	if not rooms.has(s.room):
		return
	var f := RelayPeer.decode_data(b)
	if f.is_empty():
		_error(s, "bad_request")
		return
	frames += 1
	bytes += b.size()
	var r: Dictionary = rooms[s.room]
	var out := b.duplicate()
	out[2] = s.id
	var dests: Array = []
	if s.id == 1:
		var t := int(f.target)
		for pid in r.peers:
			if pid != 1 and (t == 0 or t == pid):
				dests.append(r.peers[pid])
	else:
		out[1] = 1
		dests.append(r.host)
	for d in dests:
		(d as FakeSocket).push_bin(out)


func closed(s: FakeSocket) -> void:
	_leave(s)


func _leave(s: FakeSocket) -> void:
	if not rooms.has(s.room):
		return
	var r: Dictionary = rooms[s.room]
	if not (r.peers as Dictionary).has(s.id) or r.peers[s.id] != s:
		return
	r.peers.erase(s.id)
	if s.id == 1:
		rooms.erase(s.room)
		for pid in r.peers:
			var o: FakeSocket = r.peers[pid]
			o.push_text({ "op": "error", "code": "host_left", "msg": "the host left" })
			o.room = ""
	else:
		(r.host as FakeSocket).push_text({ "op": "peer_leave", "id": s.id })
	s.room = ""
