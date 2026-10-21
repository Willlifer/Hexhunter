class_name HHLobbyCoop
extends RefCounted
## The lobby's "Play together" logic (Lane C, H908-H912), node-free so the
## self-test drives it with a fake session. It wraps Lane N's HHNet and
## HHSession (guide/02 "Phase 4 contracts"), both duck-typed:
##   net:      host(port, max_peers) -> Error, join(address, port) -> Error,
##             leave(), is_host(), is_online(), peer_id(); signals connected,
##             failed, disconnected
##   session:  members { peer: { name, weapon, element, backup, upgrades,
##             ready } }, set_mine(fields), host_set(cfg_fields), all_ready(),
##             start(); signals changed, start_fight(cfg)
##             (requested, R-C2/R-C3: host_cfg, broadcast(kind, data), signal message(peer, kind, data))
## Roles: "solo" (no party), "joining" (waiting for the host), "host",
## "client". The host owns arena / monster / seed (a client's lobby follows
## them, locked); every peer owns its own weapon, elements, upgrades and
## Ready. The host's FIGHT starts when every other member is ready.
## Errors (cannot connect, host left) go to `note` and drop back to solo.
## Online (Lane R, H114): host_online / join_online go through the relay
## (net.host_online(), net.join_online(code); signals room_ready, relay_status);
## `online` is set and `room` holds the code to share.

signal note(text: String)            ## a line for the lobby's ticker
signal refreshed                     ## the party or the host's picks changed: redraw
signal started(cfg: Dictionary)      ## the session started the fight (this peer's own cfg, see launch_cfg)
signal hunt_started(data: Dictionary)   ## the host began a co-op hunt (clients follow)

const HOST_KEYS := ["arena", "monster", "seed"]
const MINE_KEYS := ["weapon", "element", "backup", "upgrades"]

var net: Object = null
var session: Object = null
var role := "solo"
var my_name := "Hunter"
var address := ""                    ## host: "lan-ip:port" to tell friends; client: where we joined
var ready := false
var online := false                  ## this party goes through the relay (H114)
var room := ""                       ## online: the room code (host: once the relay gave it)
var port := HHParty.PORT             ## boot's --port (tests and smoke runs stay off the author's game)
var _pushed_mine := {}
var _pushed_host := {}
var _wired: Array = []               # [object, signal, callable] to undo in detach()
var wire: HHCoopWire = null          ## Lane C's own messages (the host setting out on a hunt)


## Bind to the shell's net + session (either may be null: Play together then
## says the network is not built yet). A session already online (back from a
## fight) resumes its role and this peer's ready tick.
func attach(p_net: Object, p_session: Object) -> void:
	detach()
	net = p_net
	session = p_session
	if not available():
		return
	_wire(net, "connected", _on_connected)
	_wire(net, "failed", _on_failed)
	_wire(net, "disconnected", _on_disconnected)
	_wire(net, "room_ready", _on_room_ready)
	_wire(net, "relay_status", _on_relay_status)
	_wire(session, "changed", _on_changed)
	_wire(session, "start_fight", _on_start_fight)
	wire = HHCoopWire.open(net, session)
	wire.message.connect(_on_message)
	var pn: Variant = net.get("player_name")
	if pn is String and pn != "":
		my_name = pn
	if _call(net, "is_online", false):
		if session.get("in_fight") == true and session.has_method("end_fight"):
			session.end_fight()           # R-N3: back from a fight, the host takes joiners again
		role = "host" if _call(net, "is_host", false) else "client"
		var mine: Dictionary = members().get(my_peer(), {})
		my_name = str(mine.get("name", my_name))
		ready = false                     # back from a fight: everyone re-readies
		online = bool(_call(net, "is_relay", false))
		room = str(net.get("room")) if online and net.get("room") != null else ""
		if online:
			address = "room %s" % room
		elif role == "host":
			address = "%s:%d" % [_lan(), HHParty.PORT]


func detach() -> void:
	if wire != null:
		wire.close()
		wire = null
	for w in _wired:
		var o: Object = w[0]
		if is_instance_valid(o) and o.is_connected(w[1], w[2]):
			o.disconnect(w[1], w[2])
	_wired.clear()


func _wire(o: Object, sig: String, cb: Callable) -> void:
	if o != null and o.has_signal(sig) and not o.is_connected(sig, cb):
		o.connect(sig, cb)
		_wired.append([o, sig, cb])


static func _call(o: Object, m: String, fallback: Variant) -> Variant:
	if o != null and o.has_method(m):
		return o.call(m)
	return fallback


func available() -> bool:
	return net != null and session != null


func in_party() -> bool:
	return role in ["host", "client"]


func _lan() -> String:
	var a := HHParty.lan_address()
	return a if a != "" else "127.0.0.1"


# ------------------------------------------------------------------ host / join / leave

func host_game(p_name: String) -> bool:
	if not available():
		note.emit("Play together needs the network layer (src/net), which is not in this build yet")
		return false
	my_name = _clean_name(p_name)
	var err: int = net.host(port, HHParty.MAX - 1)
	if err != OK:
		note.emit("Could not host on port %d (error %d): is another Hexhunt already hosting?" % [port, err])
		return false
	role = "host"
	ready = false
	online = false
	address = "%s:%d" % [_lan(), port]
	note.emit("Hosting on %s: friends on your network join with that address" % address)
	refreshed.emit()
	return true


## Host a room on the relay; the code arrives through room_ready (H114).
func host_online(p_name: String) -> bool:
	if not available() or not net.has_method("host_online"):
		note.emit("Online play needs the relay transport (src/net/relay_peer.gd), which is not in this build")
		return false
	my_name = _clean_name(p_name)
	online = true
	room = ""
	address = "the relay"
	role = "host"
	ready = false
	note.emit("Opening a room on the relay ...")
	var err: int = net.host_online(HHParty.MAX - 1)
	if err != OK:
		_to_solo("Could not host online: %s" % _why("the relay address is wrong"))
		return false
	refreshed.emit()
	return role == "host"


## Join a friend's room by its code (H114).
func join_online(code: String, p_name: String) -> bool:
	if not available() or not net.has_method("join_online"):
		note.emit("Online play needs the relay transport (src/net/relay_peer.gd), which is not in this build")
		return false
	var clean := HHRelayPeer.clean_code(code)
	if clean == "":
		note.emit("Type the host's room code: five letters, e.g. KMRTX")
		return false
	my_name = _clean_name(p_name)
	online = true
	room = clean
	address = "room %s" % clean
	role = "joining"
	note.emit("Joining room %s ..." % clean)
	var err: int = net.join_online(clean)
	if err != OK:
		_to_solo("Could not join room %s: %s" % [clean, _why("the relay address is wrong")])
		return false
	refreshed.emit()
	return role != "solo"


func _why(fallback: String) -> String:
	var why: Variant = net.get("last_error") if net != null else null
	return str(why) if why is String and why != "" else fallback


## The text the lobby shows big and copies: the room code, or "" off the relay.
func share_code() -> String:
	return room if online and role == "host" else ""


func join_game(p_address: String, p_name: String) -> bool:
	if not available():
		note.emit("Play together needs the network layer (src/net), which is not in this build yet")
		return false
	var ap := HHParty.parse_address(p_address)
	if not ":" in p_address:
		ap[1] = port
	if str(ap[0]) == "":
		note.emit("Type the host's address first (it shows on the host's lobby)")
		return false
	my_name = _clean_name(p_name)
	address = "%s:%d" % [ap[0], ap[1]]
	role = "joining"                         # before join(): a net may report connected / failed inside the call
	note.emit("Joining %s ..." % address)
	var err: int = net.join(str(ap[0]), int(ap[1]))
	if err != OK:
		_to_solo("Could not connect to %s (error %d)" % [address, err])
		return false
	refreshed.emit()
	return role != "solo"


func leave() -> void:
	if available():
		net.leave()
	_to_solo("You left the party")


func _to_solo(msg: String) -> void:
	role = "solo"
	ready = false
	online = false
	room = ""
	_pushed_mine = {}
	_pushed_host = {}
	if msg != "":
		note.emit(msg + ": back to solo")
	refreshed.emit()


func _on_connected() -> void:
	if role == "joining":
		role = "client"
		note.emit("Joined the party at %s: pick your weapon and elements, then Ready" % address)
	refreshed.emit()


func _on_failed() -> void:
	var why: Variant = net.get("last_error") if net != null else null
	var tail: String = (": %s" % why) if why is String and why != "" else ""
	if online and role == "host":
		_to_solo("Could not host online" + tail)
	elif online:
		_to_solo("Could not join room %s%s" % [room, tail])
	else:
		_to_solo("Could not connect to %s%s" % [address, tail])


func _on_disconnected() -> void:
	if role == "solo":
		return
	if online:
		var why: Variant = net.get("last_error") if net != null else null
		_to_solo(str(why).substr(0, 1).to_upper() + str(why).substr(1) if why is String and why != "" else "Lost the relay")
		return
	_to_solo("The host left" if role in ["client", "joining"] else "Disconnected")


func _on_room_ready(code: String) -> void:
	room = code
	address = "room %s" % code
	note.emit("Room %s is open: tell your friends the code" % code)
	refreshed.emit()


func _on_relay_status(text: String) -> void:
	note.emit(text.substr(0, 1).to_upper() + text.substr(1))


func _on_changed() -> void:
	refreshed.emit()


func _on_start_fight(cfg: Dictionary) -> void:
	started.emit(cfg)


func _on_message(_peer: int, kind: String, data: Dictionary) -> void:
	if kind == "hunt" and role == "client":
		hunt_started.emit(data)


static func _clean_name(s: String) -> String:
	var t := s.strip_edges().replace("\n", " ")
	if t == "":
		t = "Hunter"
	return t.substr(0, 16)


# ------------------------------------------------------------------ the party

func my_peer() -> int:
	return int(_call(net, "peer_id", 1))


func members() -> Dictionary:
	var m: Variant = session.get("members") if session != null else null
	return m if m is Dictionary else {}


## The host's arena / monster / seed as the session last carried them.
func host_cfg() -> Dictionary:
	if session == null:
		return {}
	for k in ["fields", "host_cfg", "cfg"]:
		var v: Variant = session.get(k)
		if v is Dictionary:
			return v
	return {}


## Rows for the party list, peer order (the host first):
## { peer, id, name, weapon, element, backup, ready, host, me }.
func party_rows() -> Array:
	var ms := members()
	var peers := ms.keys()
	peers.sort()
	var order: Variant = session.get("joined") if session != null else null
	if order is Array and not (order as Array).is_empty():   # HHSession: join order (host p1, then p2..)
		var j: Array = (order as Array).filter(func(p): return ms.has(p))
		for p in peers:
			if not p in j:
				j.append(p)
		peers = j
	var ids := HHParty.assign_ids(peers)
	var out: Array = []
	for peer in peers:
		var r: Dictionary = ms[peer]
		var uid := str(ids.get(int(peer), ""))
		if session.has_method("unit_id") and str(session.unit_id(int(peer))) != "":
			uid = str(session.unit_id(int(peer)))
		out.append({ "peer": int(peer), "id": uid, "name": str(r.get("name", "Hunter")),
			"weapon": str(r.get("weapon", "lance")), "element": str(r.get("element", "fire")), "backup": str(r.get("backup", "water")),
			"ready": bool(r.get("ready", false)), "host": int(peer) == 1, "me": int(peer) == my_peer() })
	return out


## Every member but the host is ready (the host's FIGHT readies the host).
func others_ready() -> bool:
	var rows := party_rows()
	if rows.size() < 2:
		return false
	for r in rows:
		if not bool(r.me) and not bool(r.ready):
			return false
	return true


func all_ready() -> bool:
	if session != null and session.has_method("all_ready"):
		return bool(session.all_ready())
	var rows := party_rows()
	return not rows.is_empty() and rows.all(func(r): return bool(r.ready))


func can_start() -> bool:
	return role == "host" and others_ready()


## Keys a client may not pick (they follow the host's).
func locks() -> Array:
	return HOST_KEYS.duplicate() if role in ["client", "joining"] else []


## Send this peer's row (and the host's picks) when they changed.
func push(state: HHLobbyState) -> void:
	if not in_party() or session == null:
		return
	var mine := { "name": my_name, "ready": ready }
	for k in MINE_KEYS:
		mine[k] = state.cfg.get(k)
	if mine != _pushed_mine:
		_pushed_mine = mine.duplicate(true)
		session.set_mine(mine)
	if role == "host":
		var hf := {}
		for k in HOST_KEYS:
			hf[k] = state.cfg.get(k)
		if hf != _pushed_host:
			_pushed_host = hf.duplicate(true)
			session.host_set(hf)


## A client's lobby takes the host's arena / monster / seed.
func pull(state: HHLobbyState) -> void:
	if role != "client":
		return
	var hc := host_cfg()
	for k in HOST_KEYS:
		if hc.has(k):
			state.cfg[k] = int(hc[k]) if k == "seed" else str(hc[k])


func toggle_ready(state: HHLobbyState) -> void:
	if not in_party():
		return
	ready = not ready
	push(state)
	refreshed.emit()


## Host: everyone else is ready; ready ourselves and start. False otherwise.
func start(state: HHLobbyState) -> bool:
	if not can_start():
		return false
	ready = true
	push(state)
	var err: Variant = session.start()
	if err is int and err != OK:
		note.emit("The party could not start (error %d): everyone must be ready" % err)
		return false
	return true


## Tell the party the host started a hunt (clients' lobbies follow).
func broadcast_hunt(data: Dictionary) -> void:
	if role == "host" and wire != null:
		wire.send("hunt", data)


## This peer's launch cfg from the session's start cfg: our own lobby cfg
## (cam, locked, our picks) under the session's (players, local_id, net,
## the host's arena / monster / seed), the top-level weapon / elements /
## upgrades from our own entry, then this process's `extras` (autoplay).
func launch_cfg(state: HHLobbyState, started_cfg: Dictionary, extras: Dictionary = {}) -> Dictionary:
	var c := state.launch_cfg()
	for k in started_cfg:
		c[k] = started_cfg[k]
	if not c.has("net"):
		c.net = "host" if role == "host" else "client"
	if not c.has("players"):
		c.players = build_players()
	if not c.has("local_id"):
		var mine := party_rows().filter(func(r): return bool(r.me))
		c.local_id = str(mine[0].id) if not mine.is_empty() else "p1"
	var me := HHParty.entry(c, str(c.local_id))
	for k in MINE_KEYS:
		if me.has(k):
			c[k] = me[k]
	for k in extras:
		c[k] = extras[k]
	return c


## cfg.players from the members (the shape the session's start() sends).
func build_players() -> Array:
	var out: Array = []
	for r in party_rows():
		var row: Dictionary = members().get(r.peer, {})
		out.append({ "peer": int(r.peer), "id": str(r.id), "name": str(r.name), "weapon": str(r.weapon),
			"element": str(r.element), "backup": str(r.backup), "upgrades": (row.get("upgrades", {}) as Dictionary).duplicate(true) })
	return out
