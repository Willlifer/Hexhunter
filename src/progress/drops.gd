class_name HHDrops
## What a slain monster drops (H48 contract; Lane U, H555). One or two
## upgrade ids whose `drops_from` names the monster, drawn without
## replacement from the sim's seeded rng (deterministic per seed). When the
## weapon used is known, its own upgrades are weighted WEIGHT_WEAPON against
## WEIGHT_OTHER (an "any" upgrade sits between). Ids in `owned` never drop
## again. An empty list means the monster has nothing left to give.

const WEIGHT_WEAPON := 3.0     # an upgrade for the weapon you hunted with
const WEIGHT_ANY := 2.0        # an "any"-weapon upgrade
const WEIGHT_OTHER := 1.0      # an upgrade for another weapon
const DOUBLE_CHANCE := 0.35    # chance of two drops instead of one


## Every upgrade this monster can drop, table order, minus `owned`.
static func pool(monster_id: String, owned: Array = []) -> Array:
	var out: Array = []
	for id in HHUpgrades.TABLE:
		var row: Dictionary = HHUpgrades.TABLE[id]
		if monster_id in (row.get("drops_from", []) as Array) and not id in owned:
			out.append(id)
	return out


static func weight_of(id: String, weapon: String) -> float:
	if weapon == "":
		return WEIGHT_OTHER
	var w := str((HHUpgrades.TABLE.get(id, {}) as Dictionary).get("weapon", ""))
	if w == weapon:
		return WEIGHT_WEAPON
	if w == "any":
		return WEIGHT_ANY
	return WEIGHT_OTHER


static func roll(monster_id: String, rng: RandomNumberGenerator, weapon: String = "", owned: Array = []) -> Array:
	var cands := pool(monster_id, owned)
	if cands.is_empty():
		return []
	var want := 2 if rng.randf() < DOUBLE_CHANCE else 1
	want = mini(want, cands.size())
	var out: Array = []
	for n in want:
		var total := 0.0
		for id in cands:
			total += weight_of(id, weapon)
		var pick := rng.randf() * total
		var chosen: String = cands[-1]
		for id in cands:
			pick -= weight_of(id, weapon)
			if pick <= 0.0:
				chosen = id
				break
		out.append(chosen)
		cands.erase(chosen)
	return out
