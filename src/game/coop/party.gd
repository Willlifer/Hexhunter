class_name HHParty
extends RefCounted
## The party side of the launch cfg (guide/02 "Phase 4 contracts", H52/H53),
## node-free. `cfg.players` is [{ peer, id: "p1".."p4", name, weapon,
## element, backup, upgrades }]; solo has none, so `players_of` builds the
## one-entry party from the cfg's own weapon / elements / upgrades and every
## caller reads one shape. `cfg.local_id` is the unit this machine drives
## (solo "p1"); `cfg.net` is "solo" | "host" | "client".
## Slot colours (p1..p4) are the accent every hunter wears: the ring under the
## feet, the nameplate rule, the party frame and the map token (H902).

const IDS := ["p1", "p2", "p3", "p4"]
const MAX := 4
const PORT := 24631                    ## HHNet's default (guide/02)
## p1 gold, p2 sky, p3 leaf, p4 rose: far apart in hue, none of them the telegraph red.
const SLOT_COLORS := {
	"p1": Color(0.98, 0.78, 0.32), "p2": Color(0.36, 0.72, 1.0),
	"p3": Color(0.45, 0.92, 0.48), "p4": Color(0.95, 0.48, 0.86),
}
const MODES := ["solo", "host", "client"]
## Launch-cfg keys that describe one co-op fight; the lobby drops them so a
## solo fight after a party never inherits them.
const SESSION_KEYS := ["players", "local_id", "net"]


## The party as an Array of player entries; never empty.
static func players_of(cfg: Dictionary) -> Array:
	var given: Variant = cfg.get("players", [])
	var out: Array = []
	if given is Array:
		for i in mini((given as Array).size(), MAX):
			var p: Variant = given[i]
			if p is Dictionary:
				out.append(_entry(p, i, cfg))
	if out.is_empty():
		out.append(_entry({ "peer": 1, "id": "p1" }, 0, cfg))
	return out


## One entry with every key filled (a missing field falls back to the cfg's own pick).
static func _entry(p: Dictionary, i: int, cfg: Dictionary) -> Dictionary:
	var id := str(p.get("id", IDS[i]))
	var ups: Variant = p.get("upgrades", cfg.get("upgrades", {}))
	return {
		"peer": int(p.get("peer", i + 1)), "id": id,
		"name": str(p.get("name", "Hunter" if i == 0 else "Hunter %d" % (i + 1))),
		"weapon": str(p.get("weapon", cfg.get("weapon", "lance"))),
		"element": str(p.get("element", cfg.get("element", "fire"))),
		"backup": str(p.get("backup", cfg.get("backup", "water"))),
		"upgrades": (ups as Dictionary).duplicate(true) if ups is Dictionary else {},
	}


static func local_id(cfg: Dictionary) -> String:
	var ps := players_of(cfg)
	var want := str(cfg.get("local_id", ""))
	for p in ps:
		if str(p.id) == want:
			return want
	return str(ps[0].id)


static func mode(cfg: Dictionary) -> String:
	var m := str(cfg.get("net", "solo"))
	return m if m in MODES else "solo"


static func entry(cfg: Dictionary, id: String) -> Dictionary:
	for p in players_of(cfg):
		if str(p.id) == id:
			return p
	return {}


## peer -> unit id, for routing a remote peer's orders to its own hunter only.
static func unit_of_peer(cfg: Dictionary) -> Dictionary:
	var out := {}
	for p in players_of(cfg):
		out[int(p.peer)] = str(p.id)
	return out


static func slot_color(id: String) -> Color:
	return SLOT_COLORS.get(id, Color(0.85, 0.85, 0.85))


## Party ids for a set of peers in peer order (the host, peer 1, is p1).
static func assign_ids(peers: Array) -> Dictionary:
	var sorted := peers.duplicate()
	sorted.sort()
	var out := {}
	for i in mini(sorted.size(), MAX):
		out[int(sorted[i])] = IDS[i]
	return out


## This machine's LAN IPv4 (192.168 / 10. / 172.16-31 preferred), "" when none.
static func lan_address() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.count(".") != 3 or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		if s.begins_with("192.168.") or s.begins_with("10."):
			return s
		if s.begins_with("172."):
			var second := int(s.split(".")[1])
			if second >= 16 and second <= 31:
				return s
		if best == "":
			best = s
	return best


## "1.2.3.4:5555" -> ["1.2.3.4", 5555]; a bare address takes PORT.
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	if t == "":
		return ["", PORT]
	var i := t.rfind(":")
	if i > 0 and t.count(":") == 1:
		var port := int(t.substr(i + 1))
		return [t.substr(0, i), port if port > 0 and port < 65536 else PORT]
	return [t, PORT]
