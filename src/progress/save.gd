class_name HHSave
extends RefCounted
## The hunter's file (H48 contract; Lane U, H556): `user://hunter.json`.
##   { version, owned: [ids], slotted: { lance: { q: [], w: [], e: [], r: [], t: [] },
##     daggers: {...}, bow: {...} }, hunts: [{ monster, arena, weapon, result, seconds, date }] }
## `path` is a static so tests write user://test_hunter.json. Slots go through
## HHUpgrades.slot (max 3, weapon fit, owned only). The lobby reads
## `slotted[weapon]` into the launch cfg's `upgrades`; the results screen
## calls `own()` for each drop and `record_hunt()`.

const VERSION := 1
const DEFAULT_PATH := "user://hunter.json"

static var path := DEFAULT_PATH

var version := VERSION
var owned: Array = []
var slotted := {}
var hunts: Array = []


func _init() -> void:
	for w in HHUpgrades.WEAPONS:
		slotted[w] = HHUpgrades.empty_slots()


static func load_or_new() -> HHSave:
	var s := HHSave.new()
	if not FileAccess.file_exists(path):
		return s
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return s
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(text) != OK:
		return s                                         # a corrupt file starts the hunter over (quietly)
	if j.data is Dictionary:
		s.from_dict(j.data)
	return s


func save() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("HHSave: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true


static func wipe() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func to_dict() -> Dictionary:
	return { "version": version, "owned": owned.duplicate(), "slotted": slotted.duplicate(true), "hunts": hunts.duplicate(true) }


func from_dict(d: Dictionary) -> void:
	version = int(d.get("version", VERSION))
	owned = []
	for id in d.get("owned", []):
		if HHUpgrades.TABLE.has(str(id)) and not str(id) in owned:
			owned.append(str(id))
	for w in HHUpgrades.WEAPONS:
		var src: Dictionary = (d.get("slotted", {}) as Dictionary).get(w, {})
		var dst: Dictionary = HHUpgrades.empty_slots()
		for sk in HHUpgrades.SKILLS:
			for id in src.get(sk, []):
				if str(id) in owned:
					HHUpgrades.slot(dst, sk, str(id), w)
		slotted[w] = dst
	hunts = []
	for h in d.get("hunts", []):
		if h is Dictionary:
			hunts.append((h as Dictionary).duplicate())


## Add a drop to the collection. False when already owned or unknown.
func own(id: String) -> bool:
	if not HHUpgrades.TABLE.has(id) or id in owned:
		return false
	owned.append(id)
	return true


func owns(id: String) -> bool:
	return id in owned


func slot(weapon: String, skill: String, id: String) -> bool:
	if not slotted.has(weapon) or not id in owned:
		return false
	return HHUpgrades.slot(slotted[weapon], skill, id, weapon)


func unslot(weapon: String, skill: String, id: String) -> bool:
	if not slotted.has(weapon):
		return false
	return HHUpgrades.unslot(slotted[weapon], skill, id)


## A copy of one weapon's slots, shaped for the launch cfg / sim.add_player.
func upgrades_for(weapon: String) -> Dictionary:
	var d: Dictionary = slotted.get(weapon, HHUpgrades.empty_slots())
	return d.duplicate(true)


func record_hunt(monster: String, arena: String, weapon: String, result: String, seconds: float) -> Dictionary:
	var row := { "monster": monster, "arena": arena, "weapon": weapon, "result": result,
		"seconds": snappedf(seconds, 0.1), "date": Time.get_datetime_string_from_system() }
	hunts.append(row)
	return row
