class_name HHCoopWire
extends RefCounted
## Lane C's own party messages (H915, H918) over Lane N's HHNet: the hunt's
## tokens, the host's approach, a peer leaving the map, the host setting out
## on a hunt. One HHNet message kind (KIND) carries { k: name, d: data,
## from: originating peer }. A client sends to the host; the host relays to
## every other client and handles it itself, so every peer hears every other
## peer. With an in-process fake session (tests: it has `broadcast` and a
## `message(peer, kind, data)` signal) the same calls go through the fake.
##   var w := HHCoopWire.open(net, session)
##   w.message.connect(func(peer, kind, data): ...)
##   w.send("token", { x, z })
##   w.close()

signal message(peer: int, kind: String, data: Dictionary)

const KIND := 40               ## HHNet message kind (Lane N uses 1-3, 10-12, 30-33)

var net: Object = null
var session: Object = null
var _fake := false


static func open(p_net: Object, p_session: Object) -> HHCoopWire:
	var w := HHCoopWire.new()
	w.net = p_net
	w.session = p_session
	w._fake = p_session != null and p_session.has_method("broadcast") and p_session.has_signal("message")
	if w._fake:
		p_session.connect("message", w._from_fake)
	elif p_net != null and p_net.has_signal("message"):
		p_net.connect("message", w._from_net)
	return w


func close() -> void:
	if _fake and is_instance_valid(session) and session.is_connected("message", _from_fake):
		session.disconnect("message", _from_fake)
	if not _fake and net != null and is_instance_valid(net) and net.is_connected("message", _from_net):
		net.disconnect("message", _from_net)


func _me() -> int:
	return int(net.peer_id()) if net != null and net.has_method("peer_id") else 1


func send(kind: String, data: Dictionary) -> void:
	if _fake:
		session.broadcast(kind, data)
		return
	if net == null or not net.has_method("send"):
		return
	var payload := { "k": kind, "d": data, "from": _me() }
	if net.is_host():
		for p in net.peers():
			net.send(int(p), KIND, payload)
	else:
		net.send(1, KIND, payload)


func _from_fake(peer: int, kind: String, data: Dictionary) -> void:
	message.emit(peer, kind, data)


func _from_net(peer: int, kind: int, payload: Variant) -> void:
	if kind != KIND or not payload is Dictionary:
		return
	var p: Dictionary = payload
	var from := int(p.get("from", peer))
	if net.is_host():
		from = peer                            # a client cannot speak for another peer
		p["from"] = peer
		for other in net.peers():
			if int(other) != peer:
				net.send(int(other), KIND, p)
	var d: Variant = p.get("d", {})
	message.emit(from, str(p.get("k", "")), d if d is Dictionary else {})
