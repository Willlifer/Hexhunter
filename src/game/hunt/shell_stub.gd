class_name HHHuntShellStub
extends Node
## A minimal shell with HHShell's surface (H48: `show_screen(screen, cfg)`,
## `play(cfg)`, `last_cfg`) so the hunt loop runs and tests alone before
## Lane L's shell lands. show_screen frees the current screen, adds the new
## one and calls its setup(cfg). play(cfg) builds an HHFight from the
## launch cfg (setup_cfg when Lane L has added it, else the Phase 2 setup
## through HHHuntKit.load_arena) and returns the node whose `finished`
## carries the fight's result (an HHHuntFightWatch until HHFight has its
## own signal).

var current: Node = null
var last_cfg := {}


func show_screen(screen: Node, cfg: Dictionary = {}) -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = screen
	add_child(screen)
	if screen.has_method("setup"):
		screen.setup(cfg)


func play(cfg: Dictionary) -> Node:
	last_cfg = cfg.duplicate(true)
	return launch_fight(self, cfg)


## Build and add a fight for `cfg` under `host` (a shell or any node) and
## return the node that will emit finished(result). Static so HHHunt can
## use it as its fallback when the shell has no play().
static func launch_fight(host: Node, cfg: Dictionary) -> Node:
	if host is HHHuntShellStub and host.current != null and is_instance_valid(host.current):
		host.current.queue_free()
	var fight := HHFight.new()
	fight.name = "Fight"
	if host is HHHuntShellStub:
		host.current = fight
	host.add_child(fight)
	if fight.has_method("setup_cfg"):
		fight.setup_cfg(cfg)
	else:
		fight.weapon = str(cfg.get("weapon", "lance"))
		var seed := int(cfg.get("seed", 1))
		var loaded := HHHuntKit.load_arena(str(cfg.get("arena", "pond")), seed)
		fight.setup(loaded.arena, seed, str(cfg.get("monster", "")), loaded.asset)
		var cp := str(cfg.get("cam", "30,44")).split(",")
		if cp.size() == 2 and fight.camera != null:
			fight.camera.dist = float(cp[0])
			fight.camera.pitch = deg_to_rad(float(cp[1]))
	if fight.has_signal("finished"):
		return fight
	var watch := HHHuntFightWatch.new()
	watch.name = "Watch"
	watch.bind(fight, cfg)
	fight.add_child(watch)
	return watch
