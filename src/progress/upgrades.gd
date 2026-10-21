class_name HHUpgrades
## Boss drops that modify a weapon's skills (kickoff "Re: upgrades from
## bosses"; H48 contract; Lane U, H550). Every skill has three slots. An
## upgrade is data here; its effect lives in the weapon script at the point
## of effect (`HHUpgrades.has(u, id)`), its numbers in that weapon's TUNE.
## `weapon: "any"` upgrades (Elemental Exchange, the potion) slot into any
## weapon. `skill: "t"` is the potion (every weapon has one).
##
## Readable list: design/progress/UPGRADES.md.

const SKILLS := ["q", "w", "e", "r", "t"]
const WEAPONS := ["lance", "daggers", "bow"]
const MAX_PER_SKILL := 3

const TABLE := {
	# ---- the six kickoff examples
	"exchange_immune": { "skill": "w", "weapon": "any", "name": "Exchange Ward",
		"blurb": "Elemental Exchange grants 1 s of immunity.", "drops_from": ["swampfang", "colambros"] },
	"exchange_burst": { "skill": "w", "weapon": "any", "name": "Exchange Nova",
		"blurb": "Elemental Exchange explodes your new element in a radius of 3 around you.", "drops_from": ["colambros", "spirewalker"] },
	"energized_double": { "skill": "q", "weapon": "bow", "name": "Overcharged Shot",
		"blurb": "Energized Shot lays your element twice along its whole line.", "drops_from": ["colambros", "spirewalker"] },
	"arcing_twice": { "skill": "e", "weapon": "bow", "name": "Cluster Shot",
		"blurb": "Arcing Shot bursts twice: six bomblets land in a wider ring half a second after the first burst.", "drops_from": ["swampfang", "rimeslithe"] },
	"daggerleap_homing": { "skill": "e", "weapon": "daggers", "name": "Hunting Knives",
		"blurb": "Daggerleap's landing releases three fast knives that home on a monster within 6 hexes, painting the element you cast with as they fly.", "drops_from": ["colambros"] },
	"pierce_wide": { "skill": "q", "weapon": "lance", "name": "Broad Pierce",
		"blurb": "Pierce is three hexes wide.", "drops_from": ["rimeslithe", "spirewalker"] },
	# ---- six more in the same spirit (Claude, decided: H551)
	"guard_stagger": { "skill": "e", "weapon": "lance", "name": "Staggering Guard",
		"blurb": "Guard's counter also staggers the monster hard.", "drops_from": ["swampfang"] },
	"eruption_twice": { "skill": "r", "weapon": "lance", "name": "Aftershock",
		"blurb": "Eruption lands twice: a second eruption on the same ground 1 s later.", "drops_from": ["rimeslithe", "swampfang"] },
	"flourish_twin": { "skill": "q", "weapon": "daggers", "name": "Twin Flourish",
		"blurb": "Flourish also lays your backup element on the ring just beyond its edge.", "drops_from": ["swampfang", "spirewalker"] },
	"knifedance_long": { "skill": "r", "weapon": "daggers", "name": "Long Dance",
		"blurb": "Knifedance lasts 9 s.", "drops_from": ["rimeslithe", "colambros"] },
	"arrowstorm_glaze": { "skill": "r", "weapon": "bow", "name": "Frozen Storm",
		"blurb": "Arrowstorm's downfall freezes over: its element is crystallised in place.", "drops_from": ["rimeslithe"] },
	"potion_cleanse": { "skill": "t", "weapon": "any", "name": "Clean Draught",
		"blurb": "A potion also clears burn, poison, slow and paralysis.", "drops_from": ["swampfang", "spirewalker"] },
}


## Does unit `u` carry upgrade `id` in the slot of the skill it belongs to?
static func has(u: Dictionary, id: String) -> bool:
	var row: Dictionary = TABLE.get(id, {})
	if row.is_empty():
		return false
	var ups: Dictionary = u.get("upgrades", {})
	var slotted: Array = ups.get(str(row.skill), [])
	return id in slotted


static func name_of(id: String) -> String:
	return str((TABLE.get(id, {}) as Dictionary).get("name", id))


static func blurb_of(id: String) -> String:
	return str((TABLE.get(id, {}) as Dictionary).get("blurb", ""))


## Fits this weapon? "any" fits all three.
static func fits(id: String, weapon: String) -> bool:
	var row: Dictionary = TABLE.get(id, {})
	if row.is_empty():
		return false
	return str(row.weapon) == "any" or str(row.weapon) == weapon


## Put `id` into `upgrades[skill]` (an Array of ids). Refused when the id is
## unknown, belongs to another skill, does not fit `weapon` (when given), is
## already slotted, or the skill already holds MAX_PER_SKILL. Mutates
## `upgrades`; returns whether it slotted.
static func slot(upgrades: Dictionary, skill: String, id: String, weapon: String = "") -> bool:
	var row: Dictionary = TABLE.get(id, {})
	if row.is_empty() or str(row.skill) != skill:
		return false
	if weapon != "" and not fits(id, weapon):
		return false
	if not upgrades.has(skill):
		upgrades[skill] = []
	var slotted: Array = upgrades[skill]
	if id in slotted or slotted.size() >= MAX_PER_SKILL:
		return false
	slotted.append(id)
	return true


static func unslot(upgrades: Dictionary, skill: String, id: String) -> bool:
	if not upgrades.has(skill):
		return false
	var slotted: Array = upgrades[skill]
	var i := slotted.find(id)
	if i < 0:
		return false
	slotted.remove_at(i)
	return true


## Every upgrade id that can sit on `weapon`, table order.
static func for_weapon(weapon: String) -> Array:
	var out: Array = []
	for id in TABLE:
		if fits(id, weapon):
			out.append(id)
	return out


## An empty slot map for one weapon: { q: [], w: [], e: [], r: [], t: [] }.
static func empty_slots() -> Dictionary:
	var d := {}
	for s in SKILLS:
		d[s] = []
	return d


## Every row is well formed and its skill exists on its weapon (q/w/e/r via
## HHWeapons.skills; t is the potion, on every weapon). Returns the problems;
## empty = fine.
static func check() -> Array:
	var problems: Array = []
	for id in TABLE:
		var row: Dictionary = TABLE[id]
		var skill := str(row.get("skill", ""))
		var weapon := str(row.get("weapon", ""))
		if not skill in SKILLS:
			problems.append("%s: bad skill %s" % [id, skill])
		if weapon != "any" and not weapon in WEAPONS:
			problems.append("%s: bad weapon %s" % [id, weapon])
		if str(row.get("name", "")) == "" or str(row.get("blurb", "")) == "":
			problems.append("%s: needs a name and a blurb" % id)
		if (row.get("drops_from", []) as Array).is_empty():
			problems.append("%s: drops from no monster" % id)
		if skill != "t" and skill in SKILLS:
			var targets: Array = WEAPONS if weapon == "any" else [weapon]
			for w in targets:
				if not HHWeapons.skills(w).has(skill):
					problems.append("%s: %s has no skill %s" % [id, w, skill])
	return problems
