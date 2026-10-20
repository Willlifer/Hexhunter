class_name HHCoopFakeNet
extends Node
## An in-process stand-in for Lane N's HHNet (guide/02) for tests and the
## capture tool: the same calls and signals, no sockets. `host()` makes this
## peer 1; `join()` takes the next peer id from its hub and emits
## `connected` at once (or `failed` when `refuse` is set). `drop()` plays the
## connection dying (`disconnected`).

signal peer_joined(peer: int)
signal peer_left(peer: int)
signal connected
signal failed
signal disconnected

var hub: HHCoopFakeHub = null
var online := false
var hosting := false
var my_id := 0
var refuse := false            ## join() fails (tests: "cannot connect")
var calls: Array = []          ## [method, args...] for assertions


func host(port: int = HHParty.PORT, max_peers: int = 3) -> int:
	calls.append(["host", port, max_peers])
	online = true
	hosting = true
	my_id = 1
	return OK


func join(address: String, port: int = HHParty.PORT) -> int:
	calls.append(["join", address, port])
	if refuse:
		failed.emit()
		return OK                   # ENet reports a refused connection later, through `failed`
	online = true
	hosting = false
	my_id = hub.next_peer() if hub != null else 2
	connected.emit()
	return OK


func leave() -> void:
	calls.append(["leave"])
	online = false
	hosting = false


func is_host() -> bool:
	return hosting


func is_online() -> bool:
	return online


func peer_id() -> int:
	return my_id


func drop() -> void:
	online = false
	disconnected.emit()
