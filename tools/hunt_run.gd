extends SceneTree
## Play the whole hunt loop windowed, before `--hunt` is wired in boot.gd
## and before Lane L's shell lands (it runs on HHHuntShellStub):
##   godot --path . --script res://tools/hunt_run.gd [-- --seed N --weapon lance|daggers|bow]
## Map (right-click runs; walk into the disturbance) -> ambush (any key
## skips) -> prep (Hunt!) -> the fight (F10 aborts, Esc quits) -> results
## (Continue) -> map. Esc on the map quits.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := 1
	var weapon := "lance"
	var i := args.find("--seed")
	if i >= 0 and i + 1 < args.size():
		seed = int(args[i + 1])
	i = args.find("--weapon")
	if i >= 0 and i + 1 < args.size():
		weapon = args[i + 1]
	root.size = Vector2i(1600, 900)
	var shell := HHHuntShellStub.new()
	shell.name = "Shell"
	root.add_child(shell)
	var hunt := HHHunt.start(shell, { "seed": seed, "weapon": weapon })
	hunt.ended.connect(func() -> void: quit(0))
