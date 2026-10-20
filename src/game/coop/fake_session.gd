class_name HHCoopFakeSession
extends Node
## An in-process stand-in for Lane N's HHSession (guide/02 + the requested
## host_cfg / broadcast / message, R-C2, R-C3) for tests and the capture
## tool. Sessions that share an HHCoopFakeHub see each other's rows, the
## host's picks, the start and messages, as if over the wire, synchronously.

signal changed
signal start_fight(cfg: Dictionary)
signal message(peer: int, kind: String, data: Dictionary)

var net: HHCoopFakeNet = null
var hub: HHCoopFakeHub = null
var members := {}               ## peer -> { name, weapon, element, backup, upgrades, ready }
var host_cfg := {}              ## the host's arena / monster / seed (R-C2)
var sent: Array = []            ## [kind, data] this session broadcast


func me() -> int:
	return net.peer_id() if net != null else 1


func set_mine(fields: Dictionary) -> void:
	if hub != null:
		hub.set_row(me(), fields)
	else:
		var row: Dictionary = members.get(me(), {})
		row.merge(fields, true)
		members[me()] = row
		changed.emit()


func host_set(cfg_fields: Dictionary) -> void:
	if net != null and not net.is_host():
		return
	if hub != null:
		hub.set_host(cfg_fields)
	else:
		host_cfg.merge(cfg_fields, true)
		changed.emit()


func all_ready() -> bool:
	if members.is_empty():
		return false
	for p in members:
		if not bool((members[p] as Dictionary).get("ready", false)):
			return false
	return true


## Host only: the launch cfg with `players`, sent to every session with its own local_id and net.
func start() -> void:
	if net != null and not net.is_host():
		return
	var base := host_cfg.duplicate(true)
	var peers := members.keys()
	peers.sort()
	var ids := HHParty.assign_ids(peers)
	var players: Array = []
	for p in peers:
		var r: Dictionary = members[p]
		players.append({ "peer": int(p), "id": str(ids[int(p)]), "name": str(r.get("name", "Hunter")), "weapon": str(r.get("weapon", "lance")),
			"element": str(r.get("element", "fire")), "backup": str(r.get("backup", "water")), "upgrades": (r.get("upgrades", {}) as Dictionary).duplicate(true) })
	base.players = players
	var all: Array = hub.sessions if hub != null else [self]
	for s in all:
		var c := base.duplicate(true)
		c.local_id = str(ids.get(s.me(), "p1"))
		c.net = "host" if s.me() == 1 else "client"
		s.start_fight.emit(c)


func broadcast(kind: String, data: Dictionary) -> void:
	sent.append([kind, data])
	if hub != null:
		for s in hub.sessions:
			if s != self:
				s.message.emit(me(), kind, data)
