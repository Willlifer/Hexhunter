class_name HHSession
extends Node
## H52: the party before a fight. HHNet makes one (`net.session`, at
## Shell/Net/Session). The host owns the truth and rebroadcasts it whole on
## every change (a party is four small rows; deltas would be noise).
##
##   members: { peer: { name, weapon, element, backup, upgrades, ready } }
##   joined:  [peer, ...] in join order: the host first, so host = p1, then p2..p4
##   fields:  { arena, monster, seed, locked, cam }: host only
##
##   set_mine(fields)   this peer's own row (to the host, which rebroadcasts)
##   host_set(fields)   host only
##   all_ready()        every member ready
##   start(force)       host only: builds each peer's launch cfg and sends it;
##                      every peer (host included) emits start_fight(cfg) with
##                      its own local_id. Refused unless all_ready() or force.
##   end_fight()        each peer, when its fight screen finishes: the host
##                      takes new peers again (late joins are refused mid-fight)
## Signals changed(), start_fight(cfg).

signal changed()
signal start_fight(cfg: Dictionary)

const ROW := 10        # client -> host: { field: value } for its own row
const STATE := 11      # host -> all: { members, joined, fields }
const START := 12      # host -> one peer: its launch cfg

const ROW_KEYS := ["name", "weapon", "element", "backup", "upgrades", "ready"]
const HOST_KEYS := ["arena", "monster", "seed", "locked", "cam", "difficulty"]   # H241: the host's tier rules
const WEAPONS := ["lance", "daggers", "bow"]

var net: HHNet
var members := {}
var joined: Array = []
var fields := { "arena": "pond", "monster": "swampfang", "seed": 1, "locked": [], "cam": "30,44", "difficulty": "easy" }
var in_fight := false
var _connected := false


func _ready() -> void:
	_wire()


func _wire() -> void:
	if _connected or net == null:
		return
	_connected = true
	net.peer_joined.connect(_on_peer_joined)
	net.peer_left.connect(_on_peer_left)
	net.connected.connect(_on_connected)
	net.disconnected.connect(clear)
	net.message.connect(_on_message)


## Host: a fresh party with the host's own row.
func begin() -> void:
	_wire()
	members = { 1: _row(net.player_name) }
	joined = [1]
	in_fight = false
	changed.emit()


func clear() -> void:
	members = {}
	joined = []
	in_fight = false
	changed.emit()


func mine() -> Dictionary:
	return members.get(net.peer_id(), {})


## The unit id a peer plays: p1 for the host, then join order.
func unit_id(peer: int) -> String:
	var i := joined.find(peer)
	return "p%d" % (i + 1) if i >= 0 else ""


func set_mine(f: Dictionary) -> void:
	var clean := _clean_row(f)
	if clean.is_empty():
		return
	if net.is_host() or not net.is_online():
		var me: int = net.peer_id() if net.is_online() else 1
		if not members.has(me):
			members[me] = _row(net.player_name)
		(members[me] as Dictionary).merge(clean, true)
		if clean.has("name"):
			net.player_name = str(clean.name)
		_broadcast()
	else:
		if clean.has("name"):
			net.player_name = str(clean.name)
		net.send(1, ROW, clean)


func host_set(f: Dictionary) -> void:
	if not net.is_host():
		return
	for k in f:
		if k in HOST_KEYS:
			fields[k] = f[k]
	_broadcast()


func all_ready() -> bool:
	if members.is_empty():
		return false
	for p in members:
		if not bool((members[p] as Dictionary).get("ready", false)):
			return false
	return true


func start(force: bool = false) -> Error:
	if not net.is_host():
		return ERR_UNAUTHORIZED
	if not force and not all_ready():
		return ERR_UNAVAILABLE
	in_fight = true
	net.accepting = false
	var mine_cfg := {}
	for peer in joined:
		var cfg := build_cfg(peer)
		if int(peer) == 1:
			mine_cfg = cfg
		else:
			net.send(int(peer), START, cfg)
	for p in members:
		(members[p] as Dictionary).ready = false
	start_fight.emit(mine_cfg)
	return OK


func end_fight() -> void:
	in_fight = false
	if net.is_host():
		net.accepting = true
		_broadcast()


## The launch cfg (guide/02) for `peer`: the host's fields, every hunter in
## `players`, and this peer's own pick in the single-hunter keys so solo-era
## readers still see their own hunter.
func build_cfg(peer: int) -> Dictionary:
	var players: Array = []
	for p in joined:
		var r: Dictionary = members.get(p, _row("Hunter"))
		players.append({ "peer": int(p), "id": unit_id(p), "name": str(r.name), "weapon": str(r.weapon),
			"element": str(r.element), "backup": str(r.backup), "upgrades": (r.upgrades as Dictionary).duplicate(true) })
	var me: Dictionary = members.get(peer, _row("Hunter"))
	return {
		"arena": str(fields.arena), "monster": str(fields.monster), "seed": int(fields.seed),
		"locked": (fields.locked as Array).duplicate(), "cam": str(fields.cam),
		"difficulty": HHSim.clean_tier(fields.get("difficulty", "easy")),
		"weapon": str(me.weapon), "element": str(me.element), "backup": str(me.backup),
		"upgrades": (me.upgrades as Dictionary).duplicate(true),
		"players": players, "local_id": unit_id(peer), "net": "host" if peer == 1 else "client",
	}


# ------------------------------------------------------------------ internals

func _row(nm: String) -> Dictionary:
	return { "name": nm, "weapon": "lance", "element": "fire", "backup": "water",
		"upgrades": { "q": [], "w": [], "e": [], "r": [], "t": [] }, "ready": false }


## Only known keys with sane types (a client's row comes off the wire).
func _clean_row(f: Variant) -> Dictionary:
	var out := {}
	if not f is Dictionary:
		return out
	var d: Dictionary = f
	for k in d:
		if not k in ROW_KEYS:
			continue
		var v: Variant = d[k]
		match str(k):
			"name":
				var nm := HHNet.clean_name(str(v))
				if nm != "":
					out.name = nm
			"weapon":
				if str(v) in WEAPONS:
					out.weapon = str(v)
			"element", "backup":
				if str(v) in HHFormulas.ELEMENTS:
					out[k] = str(v)
			"upgrades":
				if v is Dictionary:
					var ups := {}
					for s in ["q", "w", "e", "r", "t"]:
						var list: Variant = (v as Dictionary).get(s, [])
						ups[s] = (list as Array).slice(0, 3).map(func(x): return str(x)) if list is Array else []
					out.upgrades = ups
			"ready":
				out.ready = bool(v)
	return out


func _broadcast() -> void:
	if net.is_host():
		var state := { "members": members, "joined": joined, "fields": fields, "in_fight": in_fight }
		for p in net.peers():
			net.send(int(p), STATE, state)
	changed.emit()


func _on_peer_joined(peer: int) -> void:
	if not net.is_host():
		return
	members[peer] = _row(str(net.names.get(peer, "Hunter")))
	if not peer in joined:
		joined.append(peer)
	_broadcast()


func _on_peer_left(peer: int) -> void:
	if not net.is_host():
		return
	members.erase(peer)
	joined.erase(peer)
	_broadcast()


func _on_connected() -> void:
	members = {}
	joined = []
	changed.emit()


func _on_message(peer: int, kind: int, data: Variant) -> void:
	match kind:
		ROW:
			if net.is_host() and members.has(peer):
				(members[peer] as Dictionary).merge(_clean_row(data), true)
				_broadcast()
		STATE:
			if net.is_client() and peer == 1 and data is Dictionary:
				members = data.get("members", {})
				joined = data.get("joined", [])
				fields = data.get("fields", fields)
				in_fight = bool(data.get("in_fight", false))
				changed.emit()
		START:
			if net.is_client() and peer == 1 and data is Dictionary:
				in_fight = true
				start_fight.emit(data)
