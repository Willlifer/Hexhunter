class_name HHPhases
## The boss phase framework, after Black | White's BWPhases (D255 there): a
## monster carries a phase script (data) and this evaluates its triggers.
## Pure rules on a state dictionary; no nodes, no rng. Monster files own the
## mechanics each phase turns on; they read `rule()`.
##
## A script: { "phases": [ { "id", "name", "trigger": {...}, "rules": {...} } ],
##             "rules": { base rules } }
## Triggers (all optional, every given one must hold):
##   hp_below: f        the monster is under f of its max HP
##   after: id          another phase has already fired
##   delay_ticks: d     once the other conditions hold, wait d ticks (PENDING)
## Each phase fires once, in script order when several are due.


static func start(script: Dictionary) -> Dictionary:
	return {
		"script": script.duplicate(true),
		"rules": Dictionary(script.get("rules", {})).duplicate(true),
		"fired": [],
		"pending": {},        # id -> due tick
	}


static func rule(st: Dictionary, key: String, def: Variant = null) -> Variant:
	return st.rules.get(key, def)


static func fired(st: Dictionary, id: String) -> bool:
	return id in st.fired


## Ticks until pending phase `id` fires (-1: not pending).
static func countdown(st: Dictionary, id: String, tick: int) -> int:
	if not st.pending.has(id):
		return -1
	return maxi(0, int(st.pending[id]) - tick)


## Evaluate every trigger now. Returns the ids that fired this call.
static func check(st: Dictionary, hp_frac: float, tick: int) -> Array:
	var out: Array = []
	for p in st.script.get("phases", []):
		var id := str(p.id)
		if id in st.fired:
			continue
		var tr: Dictionary = p.get("trigger", {})
		if tr.has("after") and not str(tr.after) in st.fired:
			continue
		if tr.has("hp_below") and hp_frac >= float(tr.hp_below):
			continue
		var d := int(tr.get("delay_ticks", 0))
		if d > 0:
			if not st.pending.has(id):
				st.pending[id] = tick + d
			if tick < int(st.pending[id]):
				continue
		st.fired.append(id)
		st.pending.erase(id)
		st.rules.merge(Dictionary(p.get("rules", {})), true)
		out.append(id)
	return out
