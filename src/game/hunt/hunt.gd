class_name HHHunt
extends Node
## The hunt loop driver (Lane H, H48): map -> ambush -> prep -> fight ->
## results -> map, against a shell. `HHHunt.start(shell, cfg_seed)` makes
## one, parents it to the shell and shows the map; every screen's
## `finished(result)` goes through HHHuntFlow.next and the next screen is
## shown. The driver frees itself when the loop ends (quit from the map).
##
## The shell is duck-typed (H48 contract, Lane L): `show_screen(screen,
## cfg)` to show a screen and `play(cfg)` to start a fight, which must
## return the node that emits `finished(result)`. Without those, screens are
## parented to the shell node directly and the fight is built through
## HHHuntShellStub.launch_fight, so `tools/hunt_run.gd` plays the whole
## loop before Lane L merges. The prep screen is Lane L's lobby (class
## HHLobby, or src/game/lobby/lobby.gd) with cfg.locked = ["arena",
## "monster"], else HHHuntPrepStub.

signal screen_changed(screen: String, node: Node)
signal ended

const LOBBY_CLASSES := ["HHLobby", "HHLobbyScreen"]
const LOBBY_PATH := "res://src/game/lobby/lobby.gd"

var shell: Object = null
var state := {}
var screen := ""               ## the current screen's name
var node: Node = null          ## the current screen (or the fight's finished source)
var history: Array = []        ## [{ screen, result }] as screens finish (tests)
var immediate := false         ## tests: transition inside the finished signal, not deferred


static func start(p_shell: Object, cfg_seed: Dictionary = {}) -> HHHunt:
	var h := HHHunt.new()
	h.name = "Hunt"
	h.shell = p_shell
	h.state = HHHuntFlow.initial(cfg_seed)
	if p_shell is Node:
		(p_shell as Node).add_child(h)
	h.go({ "screen": "map", "cfg": h.state.cfg })
	return h


## Show a screen from a flow step { screen, cfg }.
func go(step: Dictionary) -> void:
	screen = str(step.screen)
	var cfg: Dictionary = step.cfg
	match screen:
		"":
			ended.emit()
			queue_free()
			return
		"map":
			_show(HHWorldMap.new(), cfg)
		"ambush":
			_show(HHAmbush.new(), cfg)
		"prep":
			_show(_prep_screen(), cfg)
		"fight":
			_fight(cfg)
		"results":
			_show(HHResults.new(), cfg)
	screen_changed.emit(screen, node)


func _show(n: Node, cfg: Dictionary) -> void:
	node = n
	n.name = screen.capitalize()
	if n.has_signal("finished"):
		n.finished.connect(_on_finished)
	if shell != null and shell.has_method("show_screen"):
		shell.show_screen(n, cfg)
	else:
		_host_show(n, cfg)


## No shell: host screens ourselves (one at a time) and call setup.
var _hosted: Node = null
func _host_show(n: Node, cfg: Dictionary) -> void:
	if _hosted != null and is_instance_valid(_hosted):
		_hosted.queue_free()
	_hosted = n
	var host: Node = shell if shell is Node else self
	host.add_child(n)
	if n.has_method("setup"):
		n.setup(cfg)


func _prep_screen() -> Node:
	for cls in LOBBY_CLASSES:
		var s := HHHuntFlow.script_named(cls)
		if s != null:
			return s.new()
	if ResourceLoader.exists(LOBBY_PATH):
		var s: GDScript = load(LOBBY_PATH)
		return s.new()
	return HHHuntPrepStub.new()


func _fight(cfg: Dictionary) -> void:
	var src: Node = null
	if shell != null and shell.has_method("play"):
		var got: Variant = shell.play(cfg)
		if got is Node:
			src = got
	if src == null:
		if _hosted != null and is_instance_valid(_hosted):
			_hosted.queue_free()
			_hosted = null
		var host: Node = shell if shell is Node else self
		src = HHHuntShellStub.launch_fight(host, cfg)
		_hosted = src if src.get_parent() == host else src.get_parent()
	node = src
	if src != null and src.has_signal("finished"):
		src.finished.connect(_on_finished)
	else:
		push_warning("HHHunt: the fight node has no finished signal; the loop cannot continue (request to Lane L)")


func _on_finished(result: Dictionary) -> void:
	history.append({ "screen": screen, "result": result })
	var step := HHHuntFlow.next(state, result)
	if immediate:
		go(step)
	else:
		go.call_deferred(step)   # let the emitting screen finish its frame before it is freed
