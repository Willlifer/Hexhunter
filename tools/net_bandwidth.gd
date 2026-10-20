extends SceneTree
## Lane N: what one client costs on the wire, without a network. Runs a host
## sim (arena + monster brain + N bot hunters), encodes exactly what
## HHReplicator sends a client each tick (a delta + that tick's events; a full
## snapshot every 30 ticks instead), applies it to a mirror through
## encode/decode, and checks the mirror's state_hash every tick.
##   ARENA=pond MONSTER=swampfang HUNTERS=4 SECONDS=60 godot --headless --path . --script res://tools/net_bandwidth.gd


func _initialize() -> void:
	_run.call_deferred()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _run() -> void:
	var arena_id := _env("ARENA", "pond")
	var monster := _env("MONSTER", "swampfang")
	var n := int(_env("HUNTERS", "4"))
	var secs := float(_env("SECONDS", "60"))
	var seed := int(_env("SEED", "1"))
	var players := HHNetBench.party(n)
	var t0 := Time.get_ticks_msec()
	var host := HHNetBench.host_sim(arena_id, monster, seed, players)
	var mirror := HHNetBench.mirror_sim(arena_id, monster, seed, players)
	print("built in %d ms" % (Time.get_ticks_msec() - t0))
	var prev := HHSnapshot.capture(host)
	HHSnapshot.apply(mirror, HHSnapshot.decode(HHSnapshot.encode(prev)))
	var ticks := int(secs * 30.0)
	var bytes_delta := 0
	var bytes_full := 0
	var raw_total := 0
	var n_full := 0
	var max_pkt := 0
	var bad := 0
	var counts := { "tg": 0, "pr": 0, "charge_max": 0, "events": 0 }
	var cost_us := 0
	for i in ticks:
		var ev := host.step(HHNetBench.bot_orders(host, host.tick + 1))
		var c0 := Time.get_ticks_usec()
		var cur := HHSnapshot.capture(host)
		var pkt: PackedByteArray
		if host.tick % 30 == 0:
			pkt = HHSnapshot.encode({ "s": cur, "ev": HHSnapshot.clean(ev), "h": host.state_hash() })
			bytes_full += pkt.size()
			n_full += 1
			raw_total += var_to_bytes({ "s": cur, "ev": HHSnapshot.clean(ev) }).size()
		else:
			var d := HHSnapshot.delta(prev, cur)
			pkt = HHSnapshot.encode({ "d": d, "ev": HHSnapshot.clean(ev), "h": host.state_hash() })
			bytes_delta += pkt.size()
			raw_total += var_to_bytes({ "d": d, "ev": HHSnapshot.clean(ev) }).size()
		cost_us += Time.get_ticks_usec() - c0
		max_pkt = maxi(max_pkt, pkt.size())
		prev = cur
		var msg: Dictionary = HHSnapshot.decode(pkt)
		if msg.has("s"):
			HHSnapshot.apply(mirror, msg.s)
			if not HHSnapshot.same(HHSnapshot.capture(mirror), cur):
				bad += 1
				print("full mismatch at tick %d" % host.tick)
		else:
			if not HHSnapshot.apply_delta(mirror, msg.d):
				print("delta base mismatch at tick %d" % host.tick)
				bad += 1
		if mirror.state_hash() != int(msg.h):
			bad += 1
			if bad < 5:
				print("hash mismatch at tick %d" % host.tick)
				_diff(HHSnapshot.capture(mirror), cur)
		counts.tg = maxi(counts.tg, host.telegraphs.size())
		counts.pr = maxi(counts.pr, host.projectiles.size())
		counts.charge_max = maxi(counts.charge_max, host.charge.entries.size())
		counts.events += ev.size()
		if host.over != "":
			print("fight over at tick %d: %s" % [host.tick, host.over])
			break
	var played := float(host.tick) / 30.0
	print("arena %s, %s, %d hunters, %.1f s played (%d ticks)" % [arena_id, monster, n, played, host.tick])
	print("peaks: telegraphs %d, projectiles %d, charge entries %d; events %d" % [counts.tg, counts.pr, counts.charge_max, counts.events])
	print("deltas: %d B total, %.0f B avg" % [bytes_delta, float(bytes_delta) / maxf(1.0, host.tick - n_full)])
	print("fulls:  %d B total, %.0f B avg (%d sent)" % [bytes_full, float(bytes_full) / maxf(1.0, n_full), n_full])
	print("per client: %.1f KB/s compressed (uncompressed would be %.1f KB/s); largest packet %d B" % [
		(bytes_delta + bytes_full) / played / 1024.0, raw_total / played / 1024.0, max_pkt])
	print("host cost per tick per client: %.2f ms (capture + delta + encode)" % (cost_us / 1000.0 / maxf(1.0, host.tick)))
	print("mismatches: %d" % bad)
	print("NET_BANDWIDTH %s" % ("OK" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)


func _diff(a: Dictionary, b: Dictionary, path: String = "") -> void:
	for k in b:
		if not a.has(k):
			print("  missing ", path, "/", k)
		elif typeof(a[k]) == TYPE_DICTIONARY and typeof(b[k]) == TYPE_DICTIONARY:
			_diff(a[k], b[k], path + "/" + str(k))
		elif not HHSnapshot._deep_eq(a[k], b[k]):
			print("  differs ", path, "/", k, ": ", str(a[k]).left(200), " vs ", str(b[k]).left(200))
	for k in a:
		if not b.has(k):
			print("  extra ", path, "/", k)
