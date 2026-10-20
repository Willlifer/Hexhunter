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

## Co-op (Lane C, H913, H915-H917): when the shell's net is online the hunt
## is a party hunt. The host's map decides the approach (any hunter's token
## near the stir), every peer sees every token (each peer moves its own and
## broadcasts it), the ambush plays everywhere, prep is each peer's own lobby
## (the lobby's own co-op ready gate starts the fight), results are each
## peer's own. Messages ride HHSession.broadcast / message (R-C3):
##   "token"    { x, z, name, weapon }      every peer, ~8 Hz while moving
##   "approach" { monster, arena, site }    host -> all
##   "leave"    {}                          a peer left the map hunt
var role := "solo"             ## "solo" | "host" | "client"
var session: Object = null
var net: Object = null
var tokens := {}               ## peer -> the last "token" data (applied to each new map)
var end_note := ""             ## why the hunt ended on its own (the host left)
var _pending_approach := {}
var _over := false             # the loop ended: late results (a fight finishing as the host leaves) are ignored    # a client's approach that arrived off the map (applied when it is back)


static func start(p_shell: Object, cfg_seed: Dictionary = {}) -> HHHunt:
	var h := HHHunt.new()
	h.name = "Hunt"
	h.shell = p_shell
	h.state = HHHuntFlow.initial(cfg_seed)
	h._attach_coop()
	if p_shell is Node:
		(p_shell as Node).add_child(h)
	h.go({ "screen": "map", "cfg": h.state.cfg })
	return h


## A shell with an online net + session makes this a party hunt.
func _attach_coop() -> void:
	if shell == null:
		return
	var n: Variant = shell.get("net")
	var s: Variant = shell.get("session")
	if not (n is Object and s is Object) or n == null or s == null:
		return
	if not (n.has_method("is_online") and n.is_online()):
		return
	net = n
	session = s
	role = "host" if n.is_host() else "client"
	state.cfg.net = role
	if session.has_signal("message"):
		session.connect("message", _on_message)
	if net.has_signal("disconnected"):
		net.connect("disconnected", _on_disconnected)


func _exit_tree() -> void:
	if session != null and is_instance_valid(session) and session.is_connected("message", _on_message):
		session.disconnect("message", _on_message)
	if net != null and is_instance_valid(net) and net.has_signal("disconnected") and net.is_connected("disconnected", _on_disconnected):
		net.disconnect("disconnected", _on_disconnected)


func _send(kind: String, data: Dictionary) -> void:
	if session != null and session.has_method("broadcast"):
		session.broadcast(kind, data)


func _on_message(peer: int, kind: String, data: Dictionary) -> void:
	match kind:
		"token":
			tokens[peer] = data
			if screen == "map" and node is HHWorldMap:
				(node as HHWorldMap).set_remote(peer, data)
		"leave":
			tokens.erase(peer)
			if screen == "map" and node is HHWorldMap:
				(node as HHWorldMap).remove_remote(peer)
		"approach":
			if role != "client":
				return
			if screen == "map" and node is HHWorldMap:
				(node as HHWorldMap).approach_from(data)
			else:
				_pending_approach = data


func _on_disconnected() -> void:
	if role == "solo":
		return
	end_note = "The host left: the hunt is over, back to solo" if role == "client" else "Disconnected: back to solo"
	role = "solo"
	go({ "screen": "", "cfg": state.cfg })


## The map as a party sees it: other hunters' tokens, the host deciding the approach.
func _coop_map(m: HHWorldMap) -> void:
	m.coop_role = role
	m.my_peer = int(net.peer_id()) if net != null and net.has_method("peer_id") else 1
	var ms: Variant = session.get("members") if session != null else null
	if ms is Dictionary:
		m.peer_ids = HHParty.assign_ids((ms as Dictionary).keys())
		m.my_name = str(((ms as Dictionary).get(m.my_peer, {}) as Dictionary).get("name", "Hunter"))
	m.token_moved.connect(func(data: Dictionary): _send("token", data))
	for peer in tokens:
		m.set_remote(int(peer), tokens[peer])
	if role == "client" and not _pending_approach.is_empty():
		m.approach_on_setup = _pending_approach
		_pending_approach = {}


## Show a screen from a flow step { screen, cfg }.
func go(step: Dictionary) -> void:
	screen = str(step.screen)
	var cfg: Dictionary = step.cfg
	match screen:
		"":
			_over = true
			ended.emit()
			queue_free()
			return
		"map":
			var m := HHWorldMap.new()
			if role != "solo":
				_coop_map(m)
			_show(m, cfg)
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
	if shell is HHShell:                                   # H612: the shell connects our handler, not its routing
		(shell as HHShell).show_screen(n, cfg, _on_finished)
		return
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
	if shell is HHShell:                                   # H612
		node = (shell as HHShell).play(cfg, _on_finished)
		return
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
	if _over:
		return
	history.append({ "screen": screen, "result": result })
	if role == "host" and screen == "map" and str(result.get("result", "")) == "approach":
		_send("approach", { "monster": str(result.get("monster", "")), "arena": str(result.get("arena", "")), "site": int(result.get("site", -1)) })
	if role != "solo" and screen == "map" and str(result.get("result", "")) == "quit":
		_send("leave", {})
	var step := HHHuntFlow.next(state, result)
	if immediate:
		go(step)
	else:
		go.call_deferred(step)   # let the emitting screen finish its frame before it is freed
