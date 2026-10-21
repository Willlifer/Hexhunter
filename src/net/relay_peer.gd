class_name HHRelayPeer
extends MultiplayerPeerExtension
## H110-H113: a MultiplayerPeer over one WebSocket to the relay (relay/relay.py),
## so browsers and desktops behind routers can play together. HHNet.make_peer
## builds one when playing online (always on the web); SceneMultiplayer, HHNet,
## HHSession and HHReplicator run on it unchanged.
##
## Protocol v1 (guide/02 "Online co-op through the relay"):
##   hello, text JSON:  {"op":"host","v":1} | {"op":"join","v":1,"room":"KMRTX"}
##   relay replies:     hosted{room,id:1,max} | joined{room,id};
##                      the host also gets peer_join{id} / peer_leave{id}
##                      error{code,msg}, then the relay closes
##   host -> relay:     kick{id}
##   data, binary:      [1=DATA][target, 0 = all but sender][sender][channel][mode] + payload
## A joiner reaches only the host; the host reaches one peer or everyone.
##
## Everything travels over one TCP stream, so every channel is reliable and
## ordered whatever transfer mode HHNet asks for (the mode byte still travels
## so get_packet_mode() reports what was sent).
##
## Connecting: the socket opens, the hello goes out, and only when the relay
## answers hosted / joined does the status turn CONNECTED. A joiner's
## peer_connected(1) is emitted after that, because SceneMultiplayer answers it
## with connected_to_server, HHNet sends its HELLO from there, and send_bytes
## refuses unless the status already reads CONNECTED. A socket that never opens
## (a sleeping free-tier relay) is retried for RETRY_FOR_MS, with status_text
## telling the player why they are waiting.
##
## The socket is anything WebSocketPeer-shaped: `make_socket` builds it (the
## self-test's fake relay passes fake sockets; tests/relay_fake.gd).

signal room_ready(code: String)          ## host: the relay gave us a room
signal status_text(text: String)         ## a line for the lobby while connecting

const VERSION := 1
const DATA := 1
const HEADER := 5
const MAX_FRAME := 256 * 1024
const ROOM_ALPHABET := "ACDEFHJKMNPRTWXY"
const ROOM_LEN := 5
const RETRY_FOR_MS := 90000              ## a free Render instance takes up to a minute to wake
var retry_every_ms := 2500                ## between attempts while the relay sleeps (tests shorten it)
const REPLY_WAIT_MS := 15000             ## socket open, no hosted / joined yet
const ATTEMPT_MS := 12000                ## one socket stuck connecting this long is dropped and retried
                                         ## (Godot's own TCP connect gives up only after 30 s)
const CLOSE_NORMAL := 1000

## Relay error codes -> what the lobby says.
const ERRORS := {
	"not_found": "room not found: check the code (a room closes when its host leaves)",
	"full": "room full: the party already has four hunters",
	"rooms_full": "the relay is busy (no free rooms): try again in a minute",
	"busy": "the relay is busy: try again in a minute",
	"bad_request": "the relay did not understand us",
	"version": "this game version does not match the relay: update the game",
	"host_left": "host left",
	"idle": "the room closed after 15 minutes without play",
	"rate": "the relay cut us off for sending too fast",
	"slow": "the connection to the relay fell too far behind",
	"kicked": "the host removed you from the party",
	"unreachable": "could not reach the relay",
	"lost": "lost the connection to the relay",
}

var url := ""
var role := ""                           ## "host" | "join"
var room := ""                           ## the room code (host: once hosted)
var error_code := ""                     ## a relay error code, or unreachable / lost
var error_detail := ""
var max_room := 0                        ## the relay's peer cap (hosted.max)
var make_socket: Callable = default_socket
var stats := { "frames_out": 0, "bytes_out": 0, "frames_in": 0, "bytes_in": 0, "attempts": 0 }

var _sock: Object = null
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _id := 0
var _peers := {}                         # host: joiner id -> true
var _queue: Array = []                   # [sender, channel, mode, payload]
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refusing := false
var _started_ms := 0
var _retry_at := -1
var _opened_ms := -1                     # the current socket reached OPEN
var _attempt_ms := 0                     # the current socket started
var _replied := false


# ------------------------------------------------------------------ codec (node-free; tested on its own)

## One DATA frame: the 5-byte header + payload.
static func encode_data(target: int, sender: int, channel: int, mode: int, payload: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray([DATA, clampi(target, 0, 255), clampi(sender, 0, 255), clampi(channel, 0, 255), clampi(mode, 0, 255)])
	b.append_array(payload)
	return b


## { target, sender, channel, mode, payload } or {} when it is not a DATA frame.
static func decode_data(frame: PackedByteArray) -> Dictionary:
	if frame.size() < HEADER or frame[0] != DATA:
		return {}
	return { "target": int(frame[1]), "sender": int(frame[2]), "channel": int(frame[3]),
		"mode": int(frame[4]), "payload": frame.slice(HEADER) }


static func hello(p_role: String, p_room: String = "") -> String:
	var d := { "op": "host" if p_role == "host" else "join", "v": VERSION }
	if p_role != "host":
		d.room = p_room
	return JSON.stringify(d)


## A typed room code made fit to send: upper case, spaces and dashes gone.
## "" when it cannot be a code (wrong length or a letter codes never use).
static func clean_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if ch in ROOM_ALPHABET:
			out += ch
		elif ch in " -_\t":
			continue
		else:
			return ""
	return out if out.length() == ROOM_LEN else ""


static func describe(code: String, detail: String = "") -> String:
	if ERRORS.has(code):
		return str(ERRORS[code]) + ((" (%s)" % detail) if code == "unreachable" and detail != "" else "")
	return "relay error %s%s" % [code, (": " + detail) if detail != "" else ""]


static func default_socket() -> Object:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20     # a frame may be up to MAX_FRAME; several can queue
	ws.outbound_buffer_size = 1 << 22    # the host streams to up to four peers
	ws.max_queued_packets = 8192
	return ws


# ------------------------------------------------------------------ start

## Host a new room. OK, or an error when the socket could not even start
## (a malformed URL); everything after that arrives through status / signals.
func start_host(p_url: String) -> Error:
	role = "host"
	_id = 1                              # the host is peer 1 from the start (HHSession keys its row by it)
	return _start(p_url)


func start_join(p_url: String, code: String) -> Error:
	role = "join"
	room = code
	return _start(p_url)


func _start(p_url: String) -> Error:
	url = p_url
	error_code = ""
	_started_ms = Time.get_ticks_msec()
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	var err := _open()
	if err != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		error_code = "unreachable"
		error_detail = "%s (%s)" % [url, error_string(err)]
	else:
		status_text.emit("connecting to the relay ...")
	return err


func _open() -> Error:
	stats.attempts = int(stats.attempts) + 1
	_attempt_ms = Time.get_ticks_msec()
	_sock = make_socket.call()
	_opened_ms = -1
	_replied = false
	_retry_at = -1
	if _sock == null:
		return ERR_CANT_CREATE
	var err: int = _sock.connect_to_url(url)
	if err != OK:
		_sock = null
	return err


## The sentence for the last error ("" when there is none).
func error_text() -> String:
	return describe(error_code, error_detail) if error_code != "" else ""


# ------------------------------------------------------------------ the pump

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var now := Time.get_ticks_msec()
	if _sock == null:
		if _retry_at >= 0 and now >= _retry_at:
			if _open() != OK:
				_schedule_retry(now)
		return
	_sock.poll()
	var st: int = _sock.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and _opened_ms < 0:
		_opened_ms = now
		_sock.send_text(hello(role, room))
		status_text.emit("connected to the relay, %s ..." % ("opening a room" if role == "host" else "joining room %s" % room))
	while _sock != null and _sock.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _sock.get_packet()
		if _sock.was_string_packet():
			_on_text(pkt.get_string_from_utf8())
		else:
			_on_frame(pkt)
	if _sock == null or _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	st = _sock.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING and _opened_ms < 0 and now - _attempt_ms > ATTEMPT_MS:
		_sock.close(CLOSE_NORMAL, "")
		_sock = null
		_schedule_retry(now)
	elif st == WebSocketPeer.STATE_CLOSED:
		if _status == MultiplayerPeer.CONNECTION_CONNECTING and _opened_ms < 0 and error_code == "":
			_sock = null
			_schedule_retry(now)
		elif error_code == "":
			var reason := str(_sock.get_close_reason())
			_drop("lost" if reason == "" or not ERRORS.has(reason) else reason, reason)
		else:
			_drop(error_code, error_detail)
	elif _status == MultiplayerPeer.CONNECTION_CONNECTING and _opened_ms >= 0 and now - _opened_ms > REPLY_WAIT_MS:
		_drop("unreachable", "the relay never answered the hello")


func _schedule_retry(now: int) -> void:
	if now - _started_ms >= RETRY_FOR_MS:
		_drop("unreachable", "no answer in %d s" % (RETRY_FOR_MS / 1000))
		return
	_retry_at = now + retry_every_ms
	status_text.emit("relay asleep, retrying… (%d s)" % ((now - _started_ms) / 1000))


func _on_text(s: String) -> void:
	var msg: Variant = JSON.parse_string(s)
	if not msg is Dictionary:
		return
	var d: Dictionary = msg
	match str(d.get("op", "")):
		"hosted":
			if role == "host" and _status == MultiplayerPeer.CONNECTION_CONNECTING:
				room = str(d.get("room", ""))
				max_room = int(d.get("max", 0))
				_id = 1
				_replied = true
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				room_ready.emit(room)
		"joined":
			if role == "join" and _status == MultiplayerPeer.CONNECTION_CONNECTING:
				room = str(d.get("room", room))
				_id = int(d.get("id", 0))
				_replied = true
				_status = MultiplayerPeer.CONNECTION_CONNECTED   # before peer_connected: see the header
				peer_connected.emit(1)
		"peer_join":
			var pid := int(d.get("id", 0))
			if role == "host" and pid > 1 and not _peers.has(pid):
				_peers[pid] = true
				peer_connected.emit(pid)
		"peer_leave":
			var pid := int(d.get("id", 0))
			if role == "host" and _peers.has(pid):
				_peers.erase(pid)
				peer_disconnected.emit(pid)
		"error":
			error_code = str(d.get("code", "lost"))
			error_detail = str(d.get("msg", ""))
			_drop(error_code, error_detail)


func _on_frame(frame: PackedByteArray) -> void:
	var f := decode_data(frame)
	if f.is_empty() or _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var sender := int(f.sender)
	if role == "host" and not _peers.has(sender):
		return
	stats.frames_in = int(stats.frames_in) + 1
	stats.bytes_in = int(stats.bytes_in) + frame.size()
	_queue.append([sender, int(f.channel), int(f.mode), f.payload])


## Close the socket and go DISCONNECTED (SceneMultiplayer turns that into
## connection_failed while connecting, server_disconnected after).
func _drop(code: String, detail: String = "") -> void:
	if error_code == "":
		error_code = code
		error_detail = detail
	if _sock != null:
		if _sock.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			_sock.close(CLOSE_NORMAL, "")
		_sock = null
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_peers.clear()


# ------------------------------------------------------------------ MultiplayerPeer

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return role == "host"


func _is_server_relay_supported() -> bool:
	return false


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_peer() -> int:
	return int(_queue[0][0]) if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_queue[0][1]) if not _queue.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return (int(_queue[0][2]) if not _queue.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE) as MultiplayerPeer.TransferMode


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	return _queue.pop_front()[3]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED or _sock == null:
		return ERR_UNCONFIGURED
	if buffer.size() + HEADER > MAX_FRAME:
		return ERR_OUT_OF_MEMORY
	if role != "host":
		return _send(1, buffer)
	if _target >= 0:
		return _send(_target, buffer)
	var err := OK                                   # "everyone but -target": one frame each
	for pid in _peers:
		if pid != -_target:
			err = _send(pid, buffer)
	return err


func _send(target: int, payload: PackedByteArray) -> Error:
	var f := encode_data(target, 0, _channel, _mode, payload)
	var err: int = _sock.send(f, WebSocketPeer.WRITE_MODE_BINARY)
	if err == OK:
		stats.frames_out = int(stats.frames_out) + 1
		stats.bytes_out = int(stats.bytes_out) + f.size()
	return err


func _get_max_packet_size() -> int:
	return MAX_FRAME - HEADER


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


## Host: ask the relay to drop a joiner. Its peer_leave reports it back
## (force: report it now and ignore the later one, as ENet does).
func _disconnect_peer(peer: int, force: bool) -> void:
	if role != "host" or not _peers.has(peer) or _sock == null:
		return
	_sock.send_text(JSON.stringify({ "op": "kick", "id": peer }))
	if force:
		_peers.erase(peer)


func _close() -> void:
	if _sock != null and _sock.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_sock.close(CLOSE_NORMAL, "")
	_sock = null
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_peers.clear()
	_queue.clear()
