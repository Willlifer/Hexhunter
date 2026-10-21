class_name HHNet
extends Node
## H52: the connection. A Node the shell owns at `Shell/Net`; it owns its own
## SceneMultiplayer (registered for its own branch of the tree, so two of them
## can live in one process: tools/net_loopback.gd) and talks in raw packets
## (send_bytes), never RPCs, so node paths never have to match across peers.
##
##   host(port, max_peers) / join(address, port) / leave()
##   is_host(), is_online(), peer_id(), peers()
##   signals peer_joined(peer), peer_left(peer), connected(), failed(), disconnected()
##
## A join is only "connected" once the host has said welcome: the host checks
## the protocol version, whether the party is full, and `accepting` (HHSession
## clears it while a fight runs: late joins are refused with `refuse_reason`).
## A refused or unanswered join emits failed() with `last_error` set; nothing
## answers within JOIN_TIMEOUT_MS -> failed() too. ENet's own peer timeout is
## shortened (PEER_TIMEOUT_MS) so a vanished peer drops in seconds, not 30 s.
##
## Messages: send(peer, kind, data, channel) -> `message(peer, kind, data)` on
## the other side. Payloads go through HHSnapshot.encode (var_to_bytes, never
## objects; zstd when large). Channels: CH_CONTROL reliable (session, orders),
## CH_STREAM unreliable-ordered (deltas), CH_FULL reliable (full snapshots).
##
## The transport is make_peer(): ENet on desktop; Phase 5 swaps in a
## WebSocketMultiplayerPeer there and nothing else changes.

signal peer_joined(peer: int)
signal peer_left(peer: int)
signal connected()
signal failed()
signal disconnected()
signal message(peer: int, kind: int, data: Variant)

const PORT := 24631
const PROTOCOL := 1
const JOIN_TIMEOUT_MS := 5000
const PEER_TIMEOUT_MS := 6000
const REFUSE_LINGER_MS := 400
const MAX_NAME := 16

const CH_CONTROL := 1
const CH_STREAM := 2
const CH_FULL := 3
const CHANNELS := 3

## Message kinds. 1-9 belong to HHNet, 10-29 to HHSession, 30+ to HHReplicator.
const HELLO := 1
const WELCOME := 2
const REFUSE := 3

var api: SceneMultiplayer
var player_name := ""            ## this machine's hunter name (the lobby edits it)
var accepting := true            ## host: take new peers? (false during a fight)
var refuse_reason := "The party is mid-hunt. Join when they are back in the lobby."
var max_peers := 3
var last_error := ""
var names := {}                  ## peer -> name, for accepted peers (host: everyone; client: host + self)
var stats := { "sent": {}, "recv": {}, "sent_total": 0, "recv_total": 0, "since_ms": 0 }
var session: HHSession

var _mode := ""                  # "" | "host" | "client"
var _welcomed := false
var _join_started := -1
var _accepted := {}              # host: peer -> true once HELLO checked out
var _linger := {}                # host: refused peer -> ms to drop it at


func _init() -> void:
	api = MultiplayerAPI.create_default_interface() as SceneMultiplayer
	api.server_relay = false
	api.root_path = NodePath("/root")                 # raw packets only; _enter_tree sets our own branch
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.connected_to_server.connect(_on_connected_to_server)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)
	api.peer_packet.connect(_on_packet)
	player_name = clean_name(OS.get_environment("USERNAME"))
	if player_name == "":
		player_name = "Hunter"
	session = HHSession.new()
	session.name = "Session"
	session.net = self
	session._wire()
	add_child(session)


func _enter_tree() -> void:
	get_tree().set_multiplayer(api, get_path())


func _exit_tree() -> void:
	leave()
	get_tree().set_multiplayer(null, get_path())


func _process(_delta: float) -> void:
	poll()


## The nearest HHNet above `from` (a fight finds `Shell/Net` this way), or null.
static func find(from: Node) -> HHNet:
	var n := from
	while n != null:
		if n is HHNet:
			return n
		var c := n.get_node_or_null("Net")
		if c is HHNet:
			return c
		n = n.get_parent()
	return null


static func clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and out.length() < MAX_NAME:
			out += ch
	return out


# ------------------------------------------------------------------ transport

## The one transport function (Phase 5: WebSocketMultiplayerPeer here).
## Returns null and sets last_error on failure.
func make_peer(server: bool, address: String, port: int, peers: int) -> MultiplayerPeer:
	if OS.has_feature("web"):
		last_error = "co-op is not in the browser build yet: play together from the desktop build"   # H79: no UDP in a browser
		return null
	var p := ENetMultiplayerPeer.new()
	var err: Error
	if server:
		err = p.create_server(port, peers + 1, CHANNELS)     # +1: a refused peer must get in to hear why
	else:
		err = p.create_client(address, port, CHANNELS)
	if err != OK:
		last_error = ("could not open port %d (%s)" if server else "could not reach %s:%d (%s)") % (
			[port, error_string(err)] if server else [address, port, error_string(err)])
		return null
	return p


func _tune_peer(peer: int) -> void:
	var mp := api.multiplayer_peer
	if mp is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = (mp as ENetMultiplayerPeer).get_peer(peer)
		if pp != null:
			pp.set_timeout(0, PEER_TIMEOUT_MS / 2, PEER_TIMEOUT_MS)
			# ENet's packet throttle drops unreliable packets when it thinks the
			# link is congested (two processes on one machine lost ~7% of deltas).
			# Our stream is ~10 KB/s and self-healing: never throttle.
			pp.throttle_configure(5000, 32, 0)


# ------------------------------------------------------------------ host / join / leave

func host(port: int = PORT, p_max_peers: int = 3) -> Error:
	leave()
	max_peers = clampi(p_max_peers, 1, 3)
	var p := make_peer(true, "", port, max_peers)
	if p == null:
		return ERR_CANT_CREATE
	api.multiplayer_peer = p
	_mode = "host"
	_welcomed = true
	accepting = true
	last_error = ""
	names = { 1: player_name }
	_reset_stats()
	session.begin()
	return OK


func join(address: String, port: int = PORT) -> Error:
	leave()
	var p := make_peer(false, address, port, 0)
	if p == null:
		return ERR_CANT_CONNECT
	api.multiplayer_peer = p
	_mode = "client"
	_welcomed = false
	_join_started = Time.get_ticks_msec()
	last_error = ""
	names = {}
	_reset_stats()
	return OK


func leave() -> void:
	var was := _mode
	var mp := api.multiplayer_peer
	if mp != null and not (mp is OfflineMultiplayerPeer):
		mp.close()
	api.multiplayer_peer = null
	_mode = ""
	_welcomed = false
	_join_started = -1
	_accepted.clear()
	_linger.clear()
	names.clear()
	if was != "":
		session.clear()


func is_host() -> bool:
	return _mode == "host"


func is_client() -> bool:
	return _mode == "client"


func is_online() -> bool:
	return _mode == "host" or (_mode == "client" and _welcomed)


func peer_id() -> int:
	return api.get_unique_id() if _mode != "" else 1


## Accepted peers (host: every client; client: [1]).
func peers() -> Array:
	if is_host():
		return _accepted.keys()
	return [1] if is_online() else []


## Pump the connection: _process does it; headless tests call it in a loop.
func poll() -> void:
	if _mode == "":
		return
	api.poll()
	var now := Time.get_ticks_msec()
	if _mode == "client" and not _welcomed and _join_started >= 0 and now - _join_started > JOIN_TIMEOUT_MS:
		_fail("no answer from the host within %d s" % (JOIN_TIMEOUT_MS / 1000))
	for peer in _linger.keys():
		if now >= int(_linger[peer]):
			_linger.erase(peer)
			if api.multiplayer_peer != null and _mode == "host":
				api.multiplayer_peer.disconnect_peer(peer)


# ------------------------------------------------------------------ messages

func send(peer: int, kind: int, data: Variant, channel: int = CH_CONTROL) -> void:
	send_encoded(peer, kind, HHSnapshot.encode(data), channel)


## Send bytes already made by HHSnapshot.encode (the replicator encodes once
## per tick and sends the same bytes to every client).
func send_encoded(peer: int, kind: int, encoded: PackedByteArray, channel: int = CH_CONTROL) -> void:
	if _mode == "" or api.multiplayer_peer == null:
		return
	var b := PackedByteArray([kind])
	b.append_array(encoded)
	var mode := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if channel == CH_STREAM else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if api.send_bytes(b, peer, mode, channel) == OK:
		stats.sent[peer] = int(stats.sent.get(peer, 0)) + b.size()
		stats.sent_total = int(stats.sent_total) + b.size()


## Bytes per second sent to `peer` (0 = all) since host/join or reset_stats.
func sent_rate(peer: int = 0) -> float:
	var secs := maxf(0.001, (Time.get_ticks_msec() - int(stats.since_ms)) / 1000.0)
	return float(stats.sent_total if peer == 0 else stats.sent.get(peer, 0)) / secs


func _reset_stats() -> void:
	stats = { "sent": {}, "recv": {}, "sent_total": 0, "recv_total": 0, "since_ms": Time.get_ticks_msec() }


func _on_packet(peer: int, packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	stats.recv[peer] = int(stats.recv.get(peer, 0)) + packet.size()
	stats.recv_total = int(stats.recv_total) + packet.size()
	var kind := int(packet[0])
	var data: Variant = HHSnapshot.decode(packet.slice(1))
	match kind:
		HELLO:
			if is_host():
				_on_hello(peer, data)
			return
		WELCOME:
			if is_client() and not _welcomed:
				_welcomed = true
				_join_started = -1
				names[1] = clean_name(str((data as Dictionary).get("host", "Host"))) if data is Dictionary else "Host"
				names[peer_id()] = player_name
				connected.emit()
			return
		REFUSE:
			if is_client():
				_fail(str((data as Dictionary).get("why", "refused")) if data is Dictionary else "refused")
			return
	if is_host() and not _accepted.has(peer):
		return                                        # nothing but HELLO before the welcome
	message.emit(peer, kind, data)


func _on_hello(peer: int, data: Variant) -> void:
	if _accepted.has(peer) or _linger.has(peer):
		return
	var d: Dictionary = data if data is Dictionary else {}
	var why := ""
	if int(d.get("protocol", -1)) != PROTOCOL:
		why = "Version mismatch (host %d, you %d)." % [PROTOCOL, int(d.get("protocol", -1))]
	elif not accepting:
		why = refuse_reason
	elif _accepted.size() >= max_peers:
		why = "The party is full (%d hunters)." % (max_peers + 1)
	if why != "":
		send(peer, REFUSE, { "why": why })
		_linger[peer] = Time.get_ticks_msec() + REFUSE_LINGER_MS
		return
	_accepted[peer] = true
	var nm := clean_name(str(d.get("name", "")))
	names[peer] = nm if nm != "" else "Hunter %d" % (_accepted.size() + 1)
	send(peer, WELCOME, { "host": player_name })
	peer_joined.emit(peer)


# ------------------------------------------------------------------ multiplayer callbacks

func _on_peer_connected(peer: int) -> void:
	_tune_peer(peer)


func _on_peer_disconnected(peer: int) -> void:
	_linger.erase(peer)
	if is_host() and _accepted.has(peer):
		_accepted.erase(peer)
		names.erase(peer)
		peer_left.emit(peer)


func _on_connected_to_server() -> void:
	send(1, HELLO, { "protocol": PROTOCOL, "name": player_name })


func _on_connection_failed() -> void:
	_fail("could not connect")


func _on_server_disconnected() -> void:
	if _mode != "client":
		return
	if not _welcomed:
		if last_error == "":
			_fail("the host closed the connection")
		return
	leave()
	last_error = "the host left"
	disconnected.emit()


func _fail(why: String) -> void:
	last_error = why
	leave()
	failed.emit()
