extends SceneTree
## Lane W probe: run the HHNetBench bot fight headless and print what hurt the hunters.
## godot --headless --path . --script res://tools/bench_probe.gd

func _init() -> void:
	var players := HHNetBench.party(2)
	var a := HHNetBench.load_arena("round", 1)
	var host: HHSim = HHNetBench.host_sim("round", "swampfang", 1, players, a)
	var by := {}
	var downs: Array = []
	for i in 1800:
		for e in host.step(HHNetBench.bot_orders(host, host.tick + 1)):
			if e.type == "hurt" and str(e.id).begins_with("p"):
				by[str(e.cause)] = float(by.get(str(e.cause), 0.0)) + float(e.amount)
			if e.type in ["downed", "death"]:
				downs.append("%d %s %s" % [host.tick, e.id, e.get("cause", "")])
		if host.over != "":
			break
	print("tick ", host.tick, " over ", host.over)
	print(by)
	print(downs)
	quit(0)
