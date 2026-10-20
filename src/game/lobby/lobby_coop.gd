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
var _pushed_mine := {}
var _pushed_host := {}
var _wired: Array = []               # [object, signal, callable] to undo in detach()


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
	_wire(session, "changed", _on_changed)
	_wire(session, "start_fight", _on_start_fight)
	_wire(session, "message", _on_message)
	if _call(net, "is_online", false):
		role = "host" if _call(net, "is_host", false) else "client"
		var mine: Dictionary = members().get(my_peer(), {})
		my_name = str(mine.get("name", my_name))
		ready = false                     # back from a fight: everyone re-readies
		if role == "host":
			address = "%s:%d" % [_lan(), HHParty.PORT]


func detach() -> void:
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
	var err: int = net.host(HHParty.PORT, HHParty.MAX - 1)
	if err != OK:
		note.emit("Could not host on port %d (error %d): is another Hexhunt already hosting?" % [HHParty.PORT, err])
		return false
	role = "host"
	ready = false
	address = "%s:%d" % [_lan(), HHParty.PORT]
	note.emit("Hosting on %s: friends on your network join with that address" % address)
	refreshed.emit()
	return true


func join_game(p_address: String, p_name: String) -> bool:
	if not available():
		note.emit("Play together needs the network layer (src/net), which is not in this build yet")
		return false
	var ap := HHParty.parse_address(p_address)
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
	_to_solo("Could not connect to %s" % address)


func _on_disconnected() -> void:
	if role == "solo":
		return
	_to_solo("The host left" if role in ["client", "joining"] else "Disconnected")


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
	for k in ["host_cfg", "cfg"]:
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
	var ids := HHParty.assign_ids(peers)
	var out: Array = []
	for peer in peers:
		var r: Dictionary = ms[peer]
		out.append({ "peer": int(peer), "id": str(ids.get(int(peer), "")), "name": str(r.get("name", "Hunter")),
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
	session.start()
	return true


## Tell the party the host started a hunt (clients' lobbies follow).
func broadcast_hunt(data: Dictionary) -> void:
	if role == "host" and session != null and session.has_method("broadcast"):
		session.broadcast("hunt", data)


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
		c.local_id = str(HHParty.assign_ids(members().keys()).get(my_peer(), "p1"))
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
