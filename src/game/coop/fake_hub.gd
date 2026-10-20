class_name HHCoopFakeHub
extends RefCounted
## The "wire" between HHCoopFakeSessions in one process (tests, captures):
## one shared members table and host cfg, copied to every session on each
## change, then each emits `changed`.

var sessions: Array = []
var members := {}
var host_cfg := {}
var _next := 2


## A connected net + session pair on this hub. `host` makes it peer 1.
func peer(host: bool) -> Array:
	var n := HHCoopFakeNet.new()
	n.hub = self
	var s := HHCoopFakeSession.new()
	s.net = n
	s.hub = self
	sessions.append(s)
	if host:
		n.host()
	return [n, s]


func next_peer() -> int:
	_next += 1
	return _next - 1


func set_row(peer: int, fields: Dictionary) -> void:
	var row: Dictionary = members.get(peer, {})
	row.merge(fields, true)
	members[peer] = row
	_sync()


func set_host(fields: Dictionary) -> void:
	host_cfg.merge(fields, true)
	_sync()


func remove(peer: int) -> void:
	members.erase(peer)
	_sync()


func _sync() -> void:
	for s in sessions:
		s.members = members.duplicate(true)
		s.host_cfg = host_cfg.duplicate(true)
	for s in sessions:
		s.changed.emit()


func free_all() -> void:
	for s in sessions:
		if is_instance_valid(s.net):
			s.net.free()
		if is_instance_valid(s):
			s.free()
	sessions.clear()
