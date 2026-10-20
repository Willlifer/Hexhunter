class_name HHLobbyState
extends RefCounted
## The lobby's picks, node-free so the self-test drives it (H48). Holds one
## launch cfg (HHShell.default_cfg keys), the locked keys the hunt loop may
## pass, and the pick rules: a monster pick drags its biome arena along
## unless the arena was picked after the monster; the element strip's first
## click sets the active element, the second the backup (never the same
## one); a locked key refuses every pick. Saves to user://hexhunt_last.json
## and prefills from it next boot.

const LAST_PATH := "user://hexhunt_last.json"
const SAVED_KEYS := ["arena", "monster", "weapon", "element", "backup", "seed", "cam"]
const ROWS := ["arena", "monster", "weapon"]     # keys 1-3 jump these rows, 4 the elements

var cfg: Dictionary = HHShell.default_cfg()
var locked: Array = []
var save: HHSave = null          # the hunter's save (owned + slotted upgrades, Lane U); null in bare tests
var arena_picked_after_monster := false
var element_phase := 0            # 0: the next element click sets active; 1: sets backup
var row := 0                      # the row the keyboard cursor sits on (0-3)


## Start from the defaults, then the last saved cfg, then `given` (the hunt
## loop's locked keys and anything else it passes win).
func setup(given: Dictionary) -> void:
	cfg = HHShell.default_cfg()
	var last := load_last()
	for k in SAVED_KEYS:
		if last.has(k):
			cfg[k] = last[k]
	for k in given:
		cfg[k] = given[k]
	locked = Array(cfg.get("locked", []))
	if locked.has("arena"):
		arena_picked_after_monster = true     # a locked arena is never dragged by a monster pick
	element_phase = 0
	_sane()
	if save == null:
		save = HHSave.load_or_new()
	_sync_upgrades()


## cfg.upgrades follows the save's slots for the picked weapon (R-U1).
func _sync_upgrades() -> void:
	if save != null:
		cfg.upgrades = save.upgrades_for(str(cfg.weapon))


## Slot an owned upgrade into its skill for the picked weapon, or unslot it
## when it is there; saves the hunter. False when refused (unowned, full,
## wrong weapon, locked upgrades).
func toggle_upgrade(id: String) -> bool:
	if save == null or is_locked("upgrades"):
		return false
	var skill := str((HHUpgrades.TABLE.get(id, {}) as Dictionary).get("skill", ""))
	var weapon := str(cfg.weapon)
	var ok: bool
	if is_slotted(id):
		ok = save.unslot(weapon, skill, id)
	else:
		ok = save.slot(weapon, skill, id)
	if ok:
		save.save()
		_sync_upgrades()
	return ok


func is_slotted(id: String) -> bool:
	var ups: Dictionary = cfg.get("upgrades", {})
	for skill in ups:
		if id in (ups[skill] as Array):
			return true
	return false


func is_locked(key: String) -> bool:
	return locked.has(key)


## Pick an arena / monster / weapon tile. False when locked or unknown.
func pick(kind: String, id: String) -> bool:
	if is_locked(kind) or HHRegistry.entry(kind, id).is_empty():
		return false
	cfg[kind] = id
	match kind:
		"arena":
			arena_picked_after_monster = true
		"monster":
			var biome := HHRegistry.biome_of(id)
			if not arena_picked_after_monster and not is_locked("arena") and biome != "":
				cfg.arena = biome
			arena_picked_after_monster = false
		"weapon":
			_sync_upgrades()
	return true


## The element strip: first click = active, second = backup. Clicking the
## element already in the other slot swaps the two. False when locked.
func pick_element(id: String) -> bool:
	if is_locked("element") or HHRegistry.entry("element", id).is_empty():
		return false
	if element_phase == 0:
		if id == str(cfg.backup):
			cfg.backup = cfg.element
		cfg.element = id
		element_phase = 1
	else:
		if id == str(cfg.element):
			cfg.element = cfg.backup
		cfg.backup = id
		element_phase = 0
	return true


func set_seed(v: int) -> bool:
	if is_locked("seed"):
		return false
	cfg.seed = v
	return true


func roll_seed(rng: RandomNumberGenerator) -> bool:
	return set_seed(int(rng.randi_range(1, 99999)))


## Step the pick on the cursor row by `dir` (the arrow keys); the element
## row steps the active element.
func step_row(dir: int) -> void:
	if row < ROWS.size():
		var kind: String = ROWS[row]
		var ids := HHRegistry.ids(kind)
		var i := ids.find(str(cfg[kind]))
		pick(kind, str(ids[posmod(i + dir, ids.size())]))
	else:
		var ids := HHRegistry.ids("element")
		var i := ids.find(str(cfg.element))
		var next := str(ids[posmod(i + dir, ids.size())])
		if next == str(cfg.backup):
			next = str(ids[posmod(i + 2 * dir, ids.size())])
		element_phase = 0
		pick_element(next)


## The cfg to launch: a deep copy with the locked list kept.
func launch_cfg() -> Dictionary:
	return cfg.duplicate(true)


func save_last() -> void:
	var out := {}
	for k in SAVED_KEYS:
		out[k] = cfg[k]
	var f := FileAccess.open(LAST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()


static func load_last() -> Dictionary:
	if not FileAccess.file_exists(LAST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAST_PATH))
	return parsed if parsed is Dictionary else {}


## Unknown ids fall back to the defaults; the element pair never collides.
func _sane() -> void:
	var d := HHShell.default_cfg()
	for kind in ROWS:
		if HHRegistry.entry(kind, str(cfg[kind])).is_empty():
			cfg[kind] = d[kind]
	for k in ["element", "backup"]:
		if HHRegistry.entry("element", str(cfg[k])).is_empty():
			cfg[k] = d[k]
	if str(cfg.element) == str(cfg.backup):
		for el in HHRegistry.ids("element"):
			if str(el) != str(cfg.element):
				cfg.backup = el
				break
	cfg.seed = int(cfg.get("seed", 1))
