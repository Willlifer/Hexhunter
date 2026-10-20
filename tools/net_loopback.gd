extends SceneTree
## Lane N: a real co-op fight over ENet on 127.0.0.1, paced at 30 Hz.
##
##   godot --headless --path . --script res://tools/net_loopback.gd [-- options]
##     --role both     (default) host AND client in this one process, on two
##                     SceneTree multiplayer branches (/root/Host/Net and
##                     /root/Client/Net each register their own SceneMultiplayer
##                     with get_tree().set_multiplayer(api, branch_path))
##     --role host     only the host: waits for one client, then fights
##     --role client   only the client: joins --address, drives p2, verifies
##     --port N (24650)  --address A (127.0.0.1)  --seconds S (30)
##     --arena ID (pond) --monster ID (swampfang) --seed N (1)
##
## The host's p1 is a bot; p2 is driven by the CLIENT from its mirror (the
## same bot logic run on mirrored state, sent as orders), so any p2 motion on
## the host came over the wire. Checks (both): the mirror's state_hash equals
## the host's at every full snapshot (and every other tick it lands on), the
## client's orders moved p2 on the host, events arrived; also a late join is
## refused with a message, and a join to a dead port fails within ~5 s.
## Exit 0 = all checks passed. Prints NET_LOOPBACK OK / FAIL.

var opt := { "role": "both", "port": "24650", "address": "127.0.0.1", "seconds": "30",
	"arena": "pond", "monster": "swampfang", "seed": "1" }


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a.begins_with("--") and i + 1 < args.size() and opt.has(a.substr(2)):
			opt[a.substr(2)] = str(args[i + 1])
			i += 1
		i += 1
	var d := Driver.new()
	d.opt = opt
	d.name = "Driver"
	root.add_child.call_deferred(d)


class Driver:
	extends Node

	var opt: Dictionary
	var role := "both"
	var port := 24650
	var ticks_goal := 900
	var host_net: HHNet
	var client_net: HHNet
	var hsim: HHSim
	var msim: HHSim
	var hrep: HHReplicator
	var krep: HHReplicator
	var host_hash := {}
	var full_checks := 0
	var full_bad := 0
	var tick_checks := 0
	var tick_bad := 0
	var events := {}
	var acc := 0.0
	var phase := "connect"
	var t_start := 0
	var t_fight := 0
	var p2_start := Vector3.ZERO
	var p2_max_move := 0.0
	var checks: Array = []
	var late: HHNet
	var late_result := ""
	var dead: HHNet
	var dead_t0 := 0
	var dead_ms := -1
	var host_done_at := -1
	var lat_samples: Array = []
	var _order_sent_at := {}

	func _ready() -> void:
		Engine.max_fps = 240
		role = str(opt.role)
		port = int(opt.port)
		ticks_goal = int(float(opt.seconds) * 30.0)
		t_start = Time.get_ticks_msec()
		if role in ["both", "host"]:
			var b := Node.new()
			b.name = "Host"
			add_child(b)
			host_net = HHNet.new()
			host_net.name = "Net"
			host_net.player_name = "HostBot"
			b.add_child(host_net)
			var err := host_net.host(port)
			print("[host] listening on %d: %s" % [port, error_string(err)])
			host_net.session.start_fight.connect(_on_host_start)
			host_net.peer_joined.connect(func(p): print("[host] peer %d joined (%s)" % [p, host_net.names.get(p, "?")]))
			host_net.peer_left.connect(func(p): print("[host] peer %d left" % p))
			host_net.session.host_set({ "arena": opt.arena, "monster": opt.monster, "seed": int(opt.seed) })
			host_net.session.set_mine({ "weapon": "lance", "element": "fire", "backup": "water", "ready": true })
		if role in ["both", "client"]:
			var b := Node.new()
			b.name = "Client"
			add_child(b)
			client_net = HHNet.new()
			client_net.name = "Net"
			client_net.player_name = "ClientBot"
			b.add_child(client_net)
			client_net.connected.connect(_on_client_connected)
			client_net.failed.connect(func(): print("[client] join failed: %s" % client_net.last_error); _end(false))
			client_net.disconnected.connect(_on_client_lost)
			client_net.session.start_fight.connect(_on_client_start)
			var err := client_net.join(str(opt.address), port)
			print("[client] joining %s:%d: %s" % [opt.address, port, error_string(err)])
		if role == "both":
			dead = HHNet.new()
			dead.name = "Net"
			var b := Node.new()
			b.name = "Dead"
			add_child(b)
			b.add_child(dead)
			dead.failed.connect(func(): dead_ms = Time.get_ticks_msec() - dead_t0)
			dead_t0 = Time.get_ticks_msec()
			dead.join("127.0.0.1", port + 7)            # nobody there

	func _on_client_connected() -> void:
		print("[client] welcomed by %s; my peer id %d" % [client_net.names.get(1, "?"), client_net.peer_id()])
		client_net.session.set_mine({ "weapon": "daggers", "element": "thunder", "backup": "ice",
			"upgrades": { "q": [], "w": [], "e": ["daggerleap_homing"], "r": [] }, "ready": true })

	func _on_host_start(cfg: Dictionary) -> void:
		hsim = HHNetBench.host_sim(str(cfg.arena), str(cfg.monster), int(cfg.seed), cfg.players)
		var b := host_net.get_parent()
		hrep = HHReplicator.new()
		hrep.name = "Replicator"
		b.add_child(hrep)
		hrep.setup(host_net, hsim, cfg)
		p2_start = hsim.unit("p2").pos
		host_hash[0] = hsim.state_hash()
		t_fight = Time.get_ticks_msec()
		print("[host] fight: %s / %s seed %d, players %s" % [cfg.arena, cfg.monster, cfg.seed, (cfg.players as Array).map(func(p): return "%s=%s(%s)" % [p.id, p.name, p.weapon])])
		phase = "fight"
		if role == "both":
			late = HHNet.new()
			late.name = "Net"
			var lb := Node.new()
			lb.name = "Late"
			add_child(lb)
			lb.add_child(late)
			late.failed.connect(func(): late_result = late.last_error)
			late.join("127.0.0.1", port)

	func _on_client_start(cfg: Dictionary) -> void:
		msim = HHNetBench.mirror_sim(str(cfg.arena), str(cfg.monster), int(cfg.seed), cfg.players)
		var b := client_net.get_parent()
		krep = HHReplicator.new()
		krep.name = "Replicator"
		b.add_child(krep)
		krep.setup(client_net, msim, cfg)
		krep.snapshot_applied.connect(_on_applied)
		print("[client] fight starts, I am %s" % cfg.local_id)
		if role == "client":
			phase = "fight"

	func _on_applied(ev: Array) -> void:
		for e in ev:
			events[str(e.type)] = int(events.get(str(e.type), 0)) + 1
		var t := msim.tick
		var me := msim.unit("p2")
		for g in _order_sent_at.keys():                    # the mirror shows p2 heading for (or at) a probe goal
			var path: Array = me.get("path", [])
			if HHHex.distance(me.hex, g) <= 1 or (not path.is_empty() and HHHex.distance(path[-1], g) <= 2):
				lat_samples.append(Time.get_ticks_msec() - int(_order_sent_at[g]))
				_order_sent_at.erase(g)
		var full := t % HHReplicator.FULL_EVERY == 0
		if host_hash.has(t):                               # same process: compare with the host directly
			tick_checks += 1
			var ok := msim.state_hash() == int(host_hash[t])
			if not ok:
				tick_bad += 1
			if full:
				full_checks += 1
				if not ok:
					full_bad += 1
		if full and role == "client":
			print("[client] full t=%d hash=%d" % [t, msim.state_hash()])
		# drive p2 from the mirror, like a player looking at their screen
		var o := HHNetBench.bot_order(msim, "p2", t + 1, 1)
		var spawn: Vector2i = msim.arena.spawns.player[0]
		if t % 90 == 40:                                   # latency probe: a click to run somewhere
			var g: Vector2i = spawn + (Vector2i(3, 1) if (t / 90) % 2 == 0 else Vector2i(-2, 2))
			o = { "move": g, "move_pos": msim.arena.stand(g) }
		elif t % 90 == 70 and not msim.monsters().is_empty():
			o = { "target": msim.monsters()[0].id, "attack": true }
		if not o.is_empty():
			if o.has("move") and t % 90 == 40:
				_order_sent_at.clear()
				_order_sent_at[o.move] = Time.get_ticks_msec()
			krep.send_order(o)

	func _on_client_lost() -> void:
		print("[client] host left at mirror tick %d" % (msim.tick if msim != null else -1))
		if role == "client":
			_report_client()
			_end(int(krep.stats.mismatches) == 0 and int(krep.stats.verified) > 0)

	func _process(delta: float) -> void:
		if Time.get_ticks_msec() - t_start > (int(opt.seconds) + 90) * 1000:
			print("timeout in phase %s" % phase)
			_end(false)
			return
		if hsim == null or phase != "fight":
			if host_net != null and phase == "connect" and host_net.session.members.size() >= 2 and host_net.session.all_ready():
				print("[host] all ready: %s" % [host_net.session.members.values().map(func(r): return "%s/%s" % [r.name, r.weapon])])
				host_net.session.start()
			return
		if hsim.tick < ticks_goal and hsim.over == "":
			acc += delta
			var n := 0
			while acc >= HHSim.TICK and n < 6:
				acc -= HHSim.TICK
				n += 1
				var ev := hsim.step(hrep.merge(HHNetBench.bot_orders(hsim, hsim.tick + 1, ["p2"])))
				host_hash[hsim.tick] = hsim.state_hash()
				hrep.publish(hsim.tick, ev)
				p2_max_move = maxf(p2_max_move, (hsim.unit("p2").pos as Vector3).distance_to(p2_start))
				if hsim.tick % 30 == 0 and role == "host":
					print("[host]   full t=%d hash=%d" % [hsim.tick, host_hash[hsim.tick]])
				if hsim.tick >= ticks_goal or hsim.over != "":
					break
			return
		if host_done_at < 0:
			host_done_at = Time.get_ticks_msec()
		if role == "host":
			if Time.get_ticks_msec() - host_done_at > 1500:      # let the last packets out, then leave
				_report_host()
				_end(p2_max_move > 2.0 and int(hrep.stats.orders) > 0)
			return
		# both: wait for the mirror to catch up and the side checks to finish
		var caught := msim != null and msim.tick == hsim.tick
		var side_done := late_result != "" and dead_ms >= 0
		if (caught and side_done) or Time.get_ticks_msec() - host_done_at > 8000:
			_report_host()
			_report_client()
			print("late join: %s" % (late_result if late_result != "" else "(no answer)"))
			print("join to a dead port failed after %d ms: %s" % [dead_ms, dead.last_error])
			var ok := true
			ok = _check(ok, caught, "mirror caught up (%d / %d)" % [msim.tick if msim else -1, hsim.tick])
			ok = _check(ok, full_checks >= ticks_goal / 30 - 1 and full_bad == 0, "hash agrees at every full snapshot (%d checked, %d bad)" % [full_checks, full_bad])
			ok = _check(ok, tick_bad == 0, "hash agrees on every tick the mirror landed on (%d checked, %d bad)" % [tick_checks, tick_bad])
			ok = _check(ok, p2_max_move > 2.0, "the client's orders moved p2 on the host (%.1f m)" % p2_max_move)
			ok = _check(ok, events.get("telegraph", 0) > 0 and events.get("strike", 0) > 0, "events arrived (%d types)" % events.size())
			ok = _check(ok, late_result.contains("mid-hunt"), "a late join is refused with a message")
			ok = _check(ok, dead_ms > 0 and dead_ms < 6500, "a failed join reports within ~5 s")
			_end(ok)

	func _check(ok: bool, cond: bool, what: String) -> bool:
		print("  %s %s" % ["PASS" if cond else "FAIL", what])
		return ok and cond

	func _report_host() -> void:
		var secs := (Time.get_ticks_msec() - t_fight) / 1000.0
		print("[host] %d ticks in %.1f s wall; monster hp %d / %d; over '%s'" % [hsim.tick, secs, int(hsim.monsters()[0].hp), int(hsim.monsters()[0].max_hp), hsim.over])
		print("[host] p2 (remote) moved up to %.1f m from spawn; %d orders received" % [p2_max_move, int(hrep.stats.orders)])
		for p in host_net.stats.sent:
			print("[host] sent to peer %d: %d B = %.1f KB/s" % [p, int(host_net.stats.sent[p]), host_net.stats.sent[p] / maxf(0.1, secs) / 1024.0])
		for p in host_net.stats.recv:
			print("[host] received from peer %d: %d B = %.2f KB/s" % [p, int(host_net.stats.recv[p]), host_net.stats.recv[p] / maxf(0.1, secs) / 1024.0])

	func _report_client() -> void:
		if krep == null:
			print("[client] never started")
			return
		print("[client] mirror tick %d; stats %s" % [msim.tick, krep.stats])
		var ev := events.keys()
		ev.sort()
		print("[client] events: %s" % [ev.map(func(k): return "%s %d" % [k, events[k]])])
		if not lat_samples.is_empty():
			lat_samples.sort()
			print("[client] own-move click -> the mirror shows p2 routed there: median %d ms, max %d ms (%d samples)" % [lat_samples[lat_samples.size() / 2], lat_samples[-1], lat_samples.size()])

	func _end(ok: bool) -> void:
		print("NET_LOOPBACK %s (%s)" % ["OK" if ok else "FAIL", role])
		for n in [late, dead, client_net, host_net]:
			if n != null and is_instance_valid(n):
				n.leave()
		get_tree().quit(0 if ok else 1)
		set_process(false)
