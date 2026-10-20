class_name HHCoopStubReplicator
extends Node
## Lane C's stand-in for Lane N's HHReplicator (src/net/replicator.gd,
## guide/02 "Phase 4 contracts") with the same surface, so a host or client
## fight runs and tests before the net lane merges. HHFight builds the real
## one when its script exists, else this.
##   host:   collect(peer) -> the order that peer queued (one order dict, {} none)
##           publish(tick, events)
##   client: send_order(order); signal snapshot_applied(events)
##   both:   bind(sim, cfg, net)
## Tests (and the capture tool) drive it by hand: `queue(peer, order)` plays a
## remote peer, `deliver(events)` plays a snapshot arriving; `sent` and
## `published` record what the fight pushed out.

signal snapshot_applied(events: Array)

var sim: HHSim = null
var cfg := {}
var net: Object = null
var sent: Array = []            ## client: every order the fight sent
var published: Array = []       ## host: [{ tick, events }]
var collected := 0              ## host: collect() calls
var _queued := {}               # peer -> order


func bind(p_sim: HHSim, p_cfg: Dictionary, p_net: Object = null) -> void:
	sim = p_sim
	cfg = p_cfg
	net = p_net


func collect(peer: int) -> Dictionary:
	collected += 1
	var o: Dictionary = _queued.get(peer, {})
	_queued.erase(peer)
	return o


func publish(tick: int, events: Array) -> void:
	published.append({ "tick": tick, "events": events.duplicate() })


func send_order(order: Dictionary) -> void:
	sent.append(order.duplicate(true))


## Tests: a remote peer's order, merged like a frame's worth of input.
func queue(peer: int, order: Dictionary) -> void:
	var cur: Dictionary = _queued.get(peer, {})
	cur.merge(order, true)
	_queued[peer] = cur


## Tests: a snapshot "arrived" (the mirror is already overwritten) with these events.
func deliver(events: Array) -> void:
	snapshot_applied.emit(events)
