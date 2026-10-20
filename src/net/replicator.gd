class_name HHReplicator
extends Node
## H52: moves a fight over the wire. The fight adds one when cfg.net != "solo"
## (HHReplicator.attach) and never calls an RPC itself.
##
## HOST (runs the only stepping sim):
##   var orders := rep.merge(_pending)      # every client's latest orders under its unit id
##   var ev := sim.step(orders)
##   rep.publish(sim.tick, ev)              # each tick: a delta + the events (unreliable-ordered);
##                                          # a full snapshot every FULL_EVERY ticks, to a new
##                                          # client, and on a client's request (reliable)
##   collect(peer) is the per-peer form of merge.
## CLIENT (holds a mirror; never steps it):
##   rep.send_order(order)                  # reliable, to the host, for this machine's unit
##   rep.snapshot_applied.connect(...)      # (events) after each tick lands on the mirror
##   rep.lost.connect(...)                  # the host went away
## The client applies what arrives in tick order, catching up when several
## ticks land in one frame, dropping stale ones. A delta whose base never
## arrived (a lost unreliable packet) stalls the mirror; after GAP_MS it asks
## for a full snapshot. Each packet carries the host's state_hash every
## HASH_EVERY ticks; a mismatch counts in stats.mismatches and asks for a full.

signal snapshot_applied(events: Array)
signal lost()

const DELTA := 30
const FULL := 31
const ORDER := 32
const NEED_FULL := 33

const FULL_EVERY := 30
const HASH_EVERY := 5
const GAP_MS := 120
const REQUEST_EVERY_MS := 400
const ORDER_KEYS := ["move", "move_pos", "stop", "target", "attack", "run", "swap", "cast", "potion", "paint"]

var net: HHNet
var sim: HHSim
var cfg: Dictionary = {}
var role := ""                     ## "host" | "client"
var local_id := "p1"
var stats := { "fulls": 0, "deltas": 0, "stale": 0, "skipped_ticks": 0, "requests": 0, "mismatches": 0,
	"bad_base": 0, "orders": 0, "max_catchup": 0, "verified": 0 }

# host
var _unit_of := {}                 # peer -> unit id
var _orders := {}                  # peer -> merged order dict, cleared by collect
var _prev: Dictionary = {}
var _need_full := {}               # peer -> true

# client
var _buf := {}                     # tick -> { full: bool, data }
var _stuck_since := -1
var _last_request := -100000


## The fight's one call: find Shell/Net above `fight`, add the replicator
## under it, wire it to `sim`. Returns null in solo.
static func attach(fight: Node, p_sim: HHSim, p_cfg: Dictionary) -> HHReplicator:
	if str(p_cfg.get("net", "solo")) == "solo":
		return null
	var n := HHNet.find(fight)
	if n == null:
		push_warning("HHReplicator: cfg.net is %s but no HHNet above %s" % [p_cfg.get("net"), fight.get_path()])
		return null
	var r := HHReplicator.new()
	r.name = "Replicator"
	fight.add_child(r)
	r.setup(n, p_sim, p_cfg)
	return r


func setup(p_net: HHNet, p_sim: HHSim, p_cfg: Dictionary) -> void:
	net = p_net
	sim = p_sim
	cfg = p_cfg
	role = str(cfg.get("net", "host"))
	local_id = str(cfg.get("local_id", "p1"))
	for p in cfg.get("players", []):
		_unit_of[int(p.peer)] = str(p.id)
	if role == "client":
		sim.brains.clear()                 # a mirror never thinks (H52)
		sim.hooks.clear()
		request_full()                     # START and the first full travel on different channels: close the race
	else:
		_prev = HHSnapshot.capture(sim)
		for peer in _unit_of:
			if peer != 1:
				_need_full[peer] = true
	net.message.connect(_on_message)
	net.peer_left.connect(_on_peer_left)
	net.disconnected.connect(func(): lost.emit())


func _exit_tree() -> void:
	if net != null and is_instance_valid(net):
		if net.message.is_connected(_on_message):
			net.message.disconnect(_on_message)
		if net.peer_left.is_connected(_on_peer_left):
			net.peer_left.disconnect(_on_peer_left)


func _process(_delta: float) -> void:
	if role == "client":
		pump()


# ------------------------------------------------------------------ host

## Every client's pending orders, merged into `local` (the host's own; a
## remote order never lands on another peer's unit). Clears what it took.
func merge(local: Dictionary = {}) -> Dictionary:
	var out := local.duplicate()
	for peer in _orders.keys():
		out.merge(collect(peer), true)
	return out


## One client's pending orders as { unit_id: order }, cleared.
func collect(peer: int) -> Dictionary:
	var o: Dictionary = _orders.get(peer, {})
	_orders.erase(peer)
	var id := str(_unit_of.get(peer, ""))
	if o.is_empty() or id == "":
		return {}
	return { id: o }


func publish(tick: int, events: Array) -> void:
	if role != "host":
		return
	var cur := HHSnapshot.capture(sim)
	var ev: Array = HHSnapshot.clean(events)
	var h: Variant = sim.state_hash() if tick % HASH_EVERY == 0 or tick % FULL_EVERY == 0 else null
	var peers := net.peers()
	var full_bytes := PackedByteArray()
	var delta_bytes := PackedByteArray()
	for peer in peers:
		if not _unit_of.has(int(peer)):
			continue
		if tick % FULL_EVERY == 0 or _need_full.get(peer, false):
			if full_bytes.is_empty():
				full_bytes = HHSnapshot.encode({ "s": cur, "ev": ev, "h": sim.state_hash() })
			net.send_encoded(int(peer), FULL, full_bytes, HHNet.CH_FULL)
			_need_full.erase(peer)
		else:
			if delta_bytes.is_empty():
				delta_bytes = HHSnapshot.encode({ "d": HHSnapshot.delta(_prev, cur), "ev": ev, "h": h })
			net.send_encoded(int(peer), DELTA, delta_bytes, HHNet.CH_STREAM)
	_prev = cur


func _on_peer_left(peer: int) -> void:
	_orders.erase(peer)
	_need_full.erase(peer)


## Only order keys the sim knows, with the right types. Anything else from
## the wire is dropped (paint only in a sandbox fight).
static func clean_order(o: Variant, sandbox: bool) -> Dictionary:
	var out := {}
	if not o is Dictionary:
		return out
	var d: Dictionary = o
	for k in d:
		var v: Variant = d[k]
		match str(k):
			"move":
				if v is Vector2i:
					out.move = v
			"move_pos":
				if v is Vector3:
					out.move_pos = v
			"stop", "attack", "run", "swap", "potion":
				if v is bool:
					out[k] = v
			"target":
				if v is String or v is StringName:
					out.target = str(v)
			"cast":
				if v is Dictionary and str((v as Dictionary).get("skill", "")) in ["q", "w", "e", "r"] and (v as Dictionary).get("aim") is Vector2i:
					out.cast = { "skill": str(v.skill), "aim": v.aim }
			"paint":
				if sandbox and v is Dictionary and (v as Dictionary).get("hex") is Vector2i and str((v as Dictionary).get("element", "")) in HHFormulas.ELEMENTS:
					out.paint = { "element": str(v.element), "hex": v.hex, "steps": clampi(int(v.get("steps", 1)), 1, 3) }
	return out


# ------------------------------------------------------------------ client

func send_order(o: Dictionary) -> void:
	if role != "client" or o.is_empty():
		return
	net.send(1, ORDER, o, HHNet.CH_CONTROL)
	stats.orders = int(stats.orders) + 1


## Apply every tick that can land now, in order. _process calls it; headless
## tests call it after net.poll().
func pump() -> void:
	var applied := 0
	while true:
		for t in _buf.keys():
			if int(t) <= sim.tick:
				_buf.erase(t)
				stats.stale = int(stats.stale) + 1
		if _buf.is_empty():
			break
		var nxt := sim.tick + 1
		var take := -1
		if _buf.has(nxt):
			take = nxt
		else:
			var fulls: Array = _buf.keys().filter(func(t): return bool(_buf[t].full))
			if not fulls.is_empty():
				fulls.sort()
				take = int(fulls[0])
				stats.skipped_ticks = int(stats.skipped_ticks) + (take - nxt)
		if take < 0:
			break
		var m: Dictionary = _buf[take]
		_buf.erase(take)
		if not _land(m):
			break
		applied += 1
	stats.max_catchup = maxi(int(stats.max_catchup), applied)
	var now := Time.get_ticks_msec()
	if _buf.is_empty() and sim.tick > 0:
		_stuck_since = -1
	elif not _buf.is_empty() or sim.tick == 0:
		if _stuck_since < 0:
			_stuck_since = now
		elif now - _stuck_since > GAP_MS:
			request_full()


func request_full() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_request < REQUEST_EVERY_MS:
		return
	_last_request = now
	stats.requests = int(stats.requests) + 1
	net.send(1, NEED_FULL, { "at": sim.tick }, HHNet.CH_CONTROL)


func _land(m: Dictionary) -> bool:
	var data: Dictionary = m.data
	if m.full:
		HHSnapshot.apply(sim, data.s)
		stats.fulls = int(stats.fulls) + 1
	else:
		if not HHSnapshot.apply_delta(sim, data.d):
			stats.bad_base = int(stats.bad_base) + 1
			request_full()
			return false
		stats.deltas = int(stats.deltas) + 1
	if data.get("h") != null:
		if sim.state_hash() != int(data.h):
			stats.mismatches = int(stats.mismatches) + 1
			request_full()
		else:
			stats.verified = int(stats.verified) + 1
	_stuck_since = -1
	snapshot_applied.emit(data.get("ev", []))
	return true


# ------------------------------------------------------------------ wire

func _on_message(peer: int, kind: int, data: Variant) -> void:
	if role == "host":
		match kind:
			ORDER:
				if _unit_of.has(peer) and peer != 1:
					var o := clean_order(data, sim.sandbox)
					if not o.is_empty():
						var cur: Dictionary = _orders.get(peer, {})
						cur.merge(o, true)
						_orders[peer] = cur
						stats.orders = int(stats.orders) + 1
			NEED_FULL:
				if _unit_of.has(peer):
					_need_full[peer] = true
	elif peer == 1 and data is Dictionary:
		match kind:
			FULL:
				if (data as Dictionary).has("s"):
					_buf[int(data.s.t)] = { "full": true, "data": data }
			DELTA:
				if (data as Dictionary).has("d"):
					var t := int(data.d.t)
					if not (_buf.has(t) and bool(_buf[t].full)):
						_buf[t] = { "full": false, "data": data }
