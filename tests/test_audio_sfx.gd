extends RefCounted
## Lane F: the borrowed sound effects. Every sfx.json entry has its wav and
## ogg variants on disk, and every Hexhunt event the fight needs has a sound.

const SFX_DIR := "res://audio/sfx/"
const MANIFEST := SFX_DIR + "sfx.json"

const REQUIRED_EVENTS := [
	"paint:fire", "paint:water", "paint:ice", "paint:thunder", "paint:wind",
	"paint:dark", "paint:light",
	"detonate", "overheat", "overfreeze", "douse", "gale",
	"hurt", "stagger", "death", "step", "swing", "bow",
]


static func _load_manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) or ResourceLoader.exists(path)


func test_manifest_shape(c: HHSelfTest.HHCheck) -> void:
	var m := _load_manifest()
	c.ok(not m.is_empty(), "sfx.json parses")
	c.ok(m.has("sounds") and m.sounds is Dictionary, "sfx.json has sounds")
	c.near(float(m.get("target_loudness", 0.0)), -16.0, 0.01, "target loudness -16 LUFS")
	c.near(float(m.get("peak_ceiling_db", 0.0)), -1.0, 0.01, "peak ceiling -1 dB")
	c.ok(m.get("sounds", {}).size() >= 20, "at least 20 sounds listed")


func test_every_variant_on_disk(c: HHSelfTest.HHCheck) -> void:
	var m := _load_manifest()
	var sounds: Dictionary = m.get("sounds", {})
	c.ok(not sounds.is_empty(), "sounds present")
	for name in sounds:
		var s: Dictionary = sounds[name]
		var n := int(s.get("variants", 0))
		c.ok(n > 0, "%s has variants" % name)
		c.ok(s.has("use") and str(s.use) != "", "%s has a use" % name)
		c.ok(s.get("levels", []).size() == n, "%s levels match variants" % name)
		for i in range(1, n + 1):
			c.ok(_exists("%s%s_%d.wav" % [SFX_DIR, name, i]), "%s_%d.wav exists" % [name, i])
			c.ok(_exists("%s%s_%d.ogg" % [SFX_DIR, name, i]), "%s_%d.ogg exists" % [name, i])


func test_required_events_covered(c: HHSelfTest.HHCheck) -> void:
	var m := _load_manifest()
	var sounds: Dictionary = m.get("sounds", {})
	var uses := {}
	for name in sounds:
		var u := str(sounds[name].get("use", ""))
		uses[u] = int(uses.get(u, 0)) + 1
	for ev in REQUIRED_EVENTS:
		c.ok(uses.get(ev, 0) >= 1, "event %s has a sound" % ev)
