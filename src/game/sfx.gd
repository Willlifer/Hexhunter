class_name HHSfx
extends Node
## Sound effects by event (H357: the integrator's playback helper). Reads
## audio/sfx/sfx.json (Lane F): every sound carries a `use` such as
## "paint:fire", "detonate", "hurt". `play_use(use, at)` picks a variant
## round-robin from a seeded order and plays it positioned in 3D (or flat
## when no position is given). Web builds get the .ogg; desktop the .wav.
## Headless runs make no sound and never error.

const MANIFEST := "res://audio/sfx/sfx.json"
const POOL := 12

var _by_use := {}            # use -> [sound names]
var _variants := {}          # name -> n
var _streams := {}           # path -> AudioStream
var _players: Array = []
var _next := 0
var _rr := {}                # use -> round robin index
var enabled := true


func _ready() -> void:
	if not FileAccess.file_exists(MANIFEST):
		enabled = false
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		enabled = false
		return
	var sounds: Dictionary = (parsed as Dictionary).get("sounds", {})
	for name in sounds:
		var s: Dictionary = sounds[name]
		var use := str(s.get("use", ""))
		if use == "":
			continue
		if not _by_use.has(use):
			_by_use[use] = []
		_by_use[use].append(str(name))
		_variants[str(name)] = int(s.get("variants", 1))
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 60.0
		p.unit_size = 6.0
		add_child(p)
		_players.append(p)
	if DisplayServer.get_name() == "headless":
		enabled = false


func has_use(use: String) -> bool:
	return _by_use.has(use)


func play_use(use: String, at: Vector3 = Vector3.INF, volume_db: float = 0.0) -> void:
	if not enabled or not _by_use.has(use):
		return
	var names: Array = _by_use[use]
	var k := int(_rr.get(use, 0))
	_rr[use] = k + 1
	var name: String = names[k % names.size()]
	var v := (k / names.size()) % maxi(1, int(_variants[name])) + 1
	var ext := "ogg" if OS.has_feature("web") else "wav"
	var path := "res://audio/sfx/%s_%d.%s" % [name, v, ext]
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _streams[path]
	if stream == null:
		return
	var p: AudioStreamPlayer3D = _players[_next % POOL]
	_next += 1
	p.stream = stream
	p.volume_db = volume_db
	if at == Vector3.INF:
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	else:
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.global_position = at
	p.play()


## The sim event -> sound mapping, in one place.
func on_event(e: Dictionary, sim: HHSim) -> void:
	var t := str(e.type)
	match t:
		"paint":
			if e.has("changed") and not (e.changed as Array).is_empty():
				play_use("paint:%s" % str(e.element), sim.arena.world((e.changed as Array)[0]))
		"detonate": play_use("detonate", sim.arena.world(e.hex))
		"overheat": play_use("overheat", sim.arena.world(e.hex))
		"overfreeze": play_use("overfreeze", sim.arena.world(e.hex))
		"douse": play_use("douse", sim.arena.world(e.hex))
		"gale": play_use("gale", sim.arena.world(e.hex))
		"strike": play_use("hurt", sim.unit(str(e.target)).pos)
		"hurt":
			if str(e.cause) in ["telegraph", "fire_cross"] or str(e.cause).begins_with("tg"):
				play_use("hurt", sim.unit(str(e.id)).pos)
		"stagger": play_use("stagger", sim.unit(str(e.id)).pos)
		"death": play_use("death", sim.unit(str(e.id)).pos)
		"cast": play_use("swing", sim.unit(str(e.id)).pos)
		"heal": play_use("heal", sim.unit(str(e.id)).pos, -6.0)
		"arrive": play_use("step", sim.unit(str(e.id)).pos, -10.0)
