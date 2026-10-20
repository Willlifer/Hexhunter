class_name HHHuntFlow
extends RefCounted
## The hunt loop as pure data (Lane H, H48): no nodes, so a headless test can
## walk a whole hunt. `next(state, result)` turns the screen that just
## finished plus its result into the next screen and the cfg to set it up
## with. HHHunt drives it against a shell.
##
##   map ---approach---> ambush ----> prep ---play---> fight ----> results ---continue---> map
##    |                                |  \---back---> map
##    \---quit---> (end)
##
## The cfg is the Phase 3 launch config (guide 02). The map stage keeps
## `seed` (the region) and the hunter's weapon / elements; approaching a
## disturbance fixes `monster` and `arena` and locks them for the prep screen.

const SCREENS := ["map", "ambush", "prep", "fight", "results"]
const LOCKED := ["arena", "monster"]

## Fallbacks for HHRegistry when it is missing (Lane L).
const BIOME := { "swampfang": "pond", "colambros": "caldera", "rimeslithe": "cave", "spirewalker": "glade" }
const NAMES := {
	"swampfang": "Swampfang", "colambros": "Colambros", "rimeslithe": "Rimeslithe", "spirewalker": "Spirewalker",
	"pond": "the Pond", "cave": "the Cave", "glade": "the Glade", "caldera": "the Caldera",
}

const DEFAULT_CFG := {
	"arena": "pond", "monster": "swampfang", "weapon": "lance",
	"element": "fire", "backup": "water", "seed": 1,
	"upgrades": { "q": [], "w": [], "e": [], "r": [] },
	"locked": [], "cam": "30,44",
}


## The state a hunt starts in: on the map, with the seed cfg over the defaults.
static func initial(cfg_seed: Dictionary = {}) -> Dictionary:
	var cfg := DEFAULT_CFG.duplicate(true)
	for k in cfg_seed:
		cfg[k] = cfg_seed[k]
	cfg.locked = []
	return { "screen": "map", "cfg": cfg, "hunt": {} }


## The transition. Returns { screen, cfg } and mutates `state` to match;
## `screen` is "" when the loop ends (quit from the map).
static func next(state: Dictionary, result: Dictionary) -> Dictionary:
	var screen := str(state.get("screen", "map"))
	var cfg: Dictionary = (state.get("cfg", DEFAULT_CFG) as Dictionary).duplicate(true)
	var hunt: Dictionary = state.get("hunt", {})
	var verdict := str(result.get("result", ""))
	var to := ""
	match screen:
		"map":
			if verdict == "approach":
				cfg.monster = str(result.get("monster", cfg.monster))
				cfg.arena = str(result.get("arena", biome_of(cfg.monster)))
				cfg.locked = LOCKED.duplicate()
				hunt = { "monster": cfg.monster, "arena": cfg.arena, "site": result.get("site", -1) }
				to = "ambush"
			else:
				to = ""                                             # quit / abort: the loop ends
		"ambush":
			to = "prep"                                             # ambushed or skipped, the same
		"prep":
			if verdict in ["abort", "back", "quit"]:
				cfg.locked = []
				to = "map"
			else:
				var chosen: Dictionary = result.get("cfg", {})
				for k in chosen:
					if not k in LOCKED:                             # the prep screen may not change these
						cfg[k] = chosen[k]
				cfg.locked = LOCKED.duplicate()
				to = "fight"
		"fight":
			hunt["fight"] = result
			to = "results"
		"results":
			cfg.locked = []
			hunt = {}
			to = "map"
		_:
			to = "map"
	state.screen = to
	state.cfg = cfg
	state.hunt = hunt
	var out_cfg := cfg
	if to == "results":
		out_cfg = { "cfg": cfg, "fight": result }
	return { "screen": to, "cfg": out_cfg }


## The arena a monster lives in: HHRegistry.biome_of when Lane L has merged, else the table.
static func biome_of(monster: String) -> String:
	var reg := script_named("HHRegistry")
	if reg != null and reg.has_method("biome_of"):
		var b: Variant = reg.biome_of(monster)
		if b is String and b != "":
			return b
	return str(BIOME.get(monster, "pond"))


## A display name for a monster or arena id, from the registry when present.
static func display_name(id: String) -> String:
	var reg := script_named("HHRegistry")
	if reg != null:
		for table in ["MONSTERS", "ARENAS"]:
			var rows: Variant = reg.get(table)
			if rows is Array:
				for r in rows:
					if r is Dictionary and str(r.get("id", "")) == id:
						return str(r.get("name", id))
			elif rows is Dictionary and rows.has(id):
				return str((rows[id] as Dictionary).get("name", id))
	return str(NAMES.get(id, id.capitalize()))


## A global class (HHRegistry, HHDrops, HHSave, HHUpgrades...) as a script, or
## null when that lane has not merged. Looked up by name, not path, so a
## sibling lane may put the file where it likes.
static func script_named(cls: String) -> GDScript:
	for row in ProjectSettings.get_global_class_list():
		if str(row.get("class", "")) == cls:
			var path := str(row.get("path", ""))
			if ResourceLoader.exists(path):
				return load(path) as GDScript
	return null
