class_name HHShell
extends Node
## The screen owner (H48; Gamers Gauntlet's tourney.gd `_swap` pattern). One
## screen lives under the shell at a time: a plain Node with `setup(cfg)` and
## `signal finished(result)`. `show_screen` frees the old one and adds the
## next; no change_scene. The shell keeps `last_cfg`, so Replay and New seed
## are one call, and routes by default: a lobby's `finished` starts the
## fight it describes, a fight's `finished` returns to the lobby with the
## result in the ticker. A caller (the hunt loop, Lane H) passes its own
## `on_finished` to drive the flow itself.

signal screen_changed(screen: Node)

var screen: Node = null
var last_cfg: Dictionary = {}
var last_result: Dictionary = {}
var fights_run := 0


## The cfg a fresh lobby starts from (guide/02 "Launch config").
static func default_cfg() -> Dictionary:
	return {
		"arena": "pond", "monster": "swampfang", "weapon": "lance",
		"element": "fire", "backup": "water", "seed": 1,
		"upgrades": { "q": [], "w": [], "e": [], "r": [], "t": [] },   # t = the potion (Lane U)
		"locked": [], "cam": "30,44",
	}


## Free the current screen, add `s`, call `s.setup(cfg)`, connect its
## `finished`. With no `on_finished` the shell's own routing applies.
func show_screen(s: Node, cfg: Dictionary, on_finished: Callable = Callable()) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = s
	add_child(s)
	if s.has_method("setup_cfg"):          # HHFight keeps the old setup(arena, seed, ...) for tests
		s.setup_cfg(cfg)
	elif s.has_method("setup"):
		s.setup(cfg)
	if s.has_signal("finished"):
		var cb := on_finished if on_finished.is_valid() else _route.bind(s)
		s.connect("finished", cb, CONNECT_ONE_SHOT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screen_changed.emit(s)


func _route(result: Dictionary, from: Node) -> void:
	if from is HHFight:
		last_result = result
		fights_run += 1
		go_lobby(last_cfg, result)
	elif str(result.get("result", "")) == "fight":
		play(result.get("cfg", last_cfg))
	elif str(result.get("result", "")) == "hunt":
		hunt(result.get("cfg", last_cfg))
	elif str(result.get("result", "")) == "quit":
		get_tree().quit(0)


## The lobby, prefilled with `cfg`, the last result (if any) in its ticker.
func go_lobby(cfg: Dictionary = last_cfg, result: Dictionary = {}) -> void:
	var lobby := HHLobby.new()
	lobby.name = "Lobby"
	lobby.can_replay = fights_run > 0
	lobby.result_text = result_line(result)
	show_screen(lobby, cfg)


## Build and show the fight `cfg` describes. The hunt loop passes its own
## `on_finished` and gets the fight back (H612).
func play(cfg: Dictionary, on_finished: Callable = Callable()) -> Node:
	last_cfg = cfg.duplicate(true)
	var fight := HHFight.new()
	fight.name = "Fight"
	show_screen(fight, last_cfg, on_finished)
	return fight


## The hunt loop (Lane H): map -> ambush -> prep (this lobby, arena and
## monster locked) -> fight -> results -> map. Quitting the map returns here.
func hunt(cfg: Dictionary = last_cfg) -> void:
	var h: Node = HHHunt.start(self, { "seed": int(cfg.get("seed", 1)), "weapon": str(cfg.get("weapon", "lance")),
		"element": str(cfg.get("element", "fire")), "backup": str(cfg.get("backup", "water")) })
	h.connect("ended", func(): go_lobby(last_cfg), CONNECT_ONE_SHOT)


func replay() -> void:
	if last_cfg.is_empty():
		last_cfg = default_cfg()
	play(last_cfg)


func new_seed() -> void:
	if last_cfg.is_empty():
		last_cfg = default_cfg()
	last_cfg.seed = int(last_cfg.get("seed", 1)) + 1
	play(last_cfg)


## "VICTORY in 84 s" / "FALLEN at 2:10" / "aborted at 0:31"; "" for no result.
static func result_line(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var secs := int(r.get("ticks", 0)) * HHSim.TICK
	var clock := "%d:%02d" % [int(secs) / 60, int(secs) % 60]
	match str(r.get("result", "")):
		"win": return "VICTORY in %d s" % int(secs)
		"fallen": return "FALLEN at %s" % clock
		"abort": return "aborted at %s" % clock
	return str(r.get("result", ""))
