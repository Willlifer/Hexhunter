class_name HHLobbyState
extends RefCounted
## The lobby's picks, node-free so the self-test drives it (H48). Holds one
## launch cfg (HHShell.default_cfg keys), the locked keys the hunt loop may
## pass, and the pick rules: a monster pick drags its biome arena along
## unless the arena was picked after the monster; the element strip's first
## click sets the active element, the second the backup (never the same
## one); a locked key refuses every pick. Saves to user://hexhunt_last.json
## and prefills from it next boot. Keeps the run history (L-19) in
## user://hexhunt_runs.json: newest first, RUNS_KEEP rows; the card shows
## the last RUNS_SHOWN.

const LAST_PATH := "user://hexhunt_last.json"
static var last_path := LAST_PATH   ## the self-test points this at a scratch file (H613)
const RUNS_PATH := "user://hexhunt_runs.json"
static var runs_path := RUNS_PATH   ## the self-test points this at a scratch file too (H810)
const RUNS_KEEP := 20
const RUNS_SHOWN := 5
const SAVED_KEYS := ["arena", "monster", "weapon", "element", "backup", "seed", "cam", "difficulty"]
const ROWS := ["arena", "monster", "weapon"]     # keys 1-3 jump these rows, 4 the elements

## Difficulty (Lane D, H240-H243): the tiers the lobby switch offers. HHSim.TIERS
## also defines "hard" (identical to normal today); the lobby adds it once
## something differs. A saved or passed "hard" is kept, never offered.
const LOBBY_TIERS := ["easy", "normal"]
const TIER_BLURB := {
	"easy": "Easy: every fight exactly as it plays today",
	"normal": "Normal: Easy plus the new monster behaviour as it lands (identical to Easy for now)",
	"hard": "Hard: defined for later; identical to Normal for now",
}

## The element picker's grouping (Lane D, H244, spec section 4): the axis
## elements under AXIS, then Wind, Ice and Thunder under a labelled OPERATORS
## group, each with one line naming its cash-in. Copy is the author's (H266).
## Swirl and Shatter are mechanics still to come (spec sections 2 and 3).
const AXIS := ["fire", "water", "dark", "light"]
const OPERATORS := ["wind", "ice", "thunder"]
const AXIS_COPY := "Build charges and create tier-based payoffs"
const OPERATOR_COPY := {
	"wind": "Swirl: rearranges the board and compresses charges",
	"ice": "Shatter: stores charges until something breaks the crystal",
	"thunder": "Detonate: cashes out charges immediately",
}


## The element strip in picker order: the axis group, then the operators.
static func element_order() -> Array:
	return AXIS + OPERATORS


static func is_operator(id: String) -> bool:
	return id in OPERATORS

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
	for k in HHParty.SESSION_KEYS:          # H909: a party's players / local_id / net never leak into the next launch
		cfg.erase(k)
	locked = Array(cfg.get("locked", []))
	if locked.has("arena"):
		arena_picked_after_monster = true     # a locked arena is never dragged by a monster pick
	element_phase = 0
	_sane()
	if save == null:
		save = HHSave.load_or_new()
	_sync_upgrades()


## R-L1 (H613): testing aid: own every upgrade in the table, saved. Refused
## during a hunt (anything locked), so drops still mean something there.
func own_all() -> int:
	if save == null or not (cfg.get("locked", []) as Array).is_empty():
		return 0
	var n := 0
	for id in HHUpgrades.TABLE:
		if save.own(str(id)):
			n += 1
	save.save()
	return n


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


var coop_locks: Array = []        ## H910: keys a party client follows from the host (arena, monster, seed)

func is_locked(key: String) -> bool:
	return locked.has(key) or coop_locks.has(key)


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


## The tier switch (H243). False when locked (a party client follows the host).
func set_difficulty(t: String) -> bool:
	if is_locked("difficulty") or not t in HHSim.TIERS:
		return false
	cfg.difficulty = t
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
		var ids := element_order()                     # the strip's own order (H244)
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
	var f := FileAccess.open(last_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()


static func load_last() -> Dictionary:
	if not FileAccess.file_exists(last_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(last_path))
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
	cfg.difficulty = HHSim.clean_tier(cfg.get("difficulty", "easy"))


# ------------------------------------------------------------------ run history

## One history row from a fight's finished payload { result, ticks, cfg }
## and the launch cfg (the payload's own cfg wins when it has one).
static func run_entry(result: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	var c: Dictionary = cfg
	if result.get("cfg", null) is Dictionary and not (result.cfg as Dictionary).is_empty():
		c = result.cfg
	var verdict := str(result.get("result", "abort"))
	if verdict == "dead":
		verdict = "fallen"
	return {
		"monster": str(c.get("monster", "")), "arena": str(c.get("arena", "")), "weapon": str(c.get("weapon", "")),
		"element": str(c.get("element", "")), "backup": str(c.get("backup", "")), "seed": int(c.get("seed", 1)),
		"result": verdict, "seconds": snappedf(float(result.get("ticks", 0)) * HHSim.TICK, 0.1),
		"hunt": not (c.get("locked", []) as Array).is_empty(),
		"difficulty": HHSim.clean_tier(c.get("difficulty", "easy")),
	}


## Prepend a row and save (keeps RUNS_KEEP). Returns the new list.
static func record_run(entry: Dictionary) -> Array:
	var runs := load_runs()
	runs.push_front(entry)
	while runs.size() > RUNS_KEEP:
		runs.pop_back()
	var f := FileAccess.open(runs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(runs, "  "))
		f.close()
	return runs


## The saved rows, newest first; [] when there are none or the file is bad.
static func load_runs() -> Array:
	if not FileAccess.file_exists(runs_path):
		return []
	var json := JSON.new()                     # an instance: a bad file reads as [] without an engine error
	var out: Array = []
	if json.parse(FileAccess.get_file_as_string(runs_path)) != OK:
		return out
	var parsed: Variant = json.data
	if parsed is Array:
		for r in parsed:
			if r is Dictionary:
				out.append(r)
	return out


const VERDICT_WORD := { "win": "VICTORY", "fallen": "FALLEN", "abort": "ABORTED" }


## "VICTORY 1:24" / "FALLEN 2:10" / "ABORTED 0:31" for a row.
static func run_verdict(entry: Dictionary) -> String:
	var secs := int(float(entry.get("seconds", 0.0)))
	var r := str(entry.get("result", ""))
	return "%s %d:%02d" % [str(VERDICT_WORD.get(r, r.to_upper())), secs / 60, secs % 60]
