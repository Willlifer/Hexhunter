extends RefCounted
## Lane ENV (H750): the visual pass changes only meshes, materials, props
## and lights. This suite proves the hex logic did not move: every biome's
## default preset, regenerated now, must match the committed arenas/<id>.json
## (cells, kinds, walkability, heightfield, spawns, extras, authored rows).
## Numbers compare within 1e-4 (the file went through JSON once already).

const EPS := 1e-4


func _export(id: String, params: Dictionary) -> Dictionary:
	if id == "pond":
		return HHPondGen.export_dict(params)
	var def := HHArenaGens.make(id)
	var q := def.validate(params)
	return HHGenUtil.export_dict(HHArenaGens.arena(id, q), id, 1, q)


## "" when a and b agree (numbers within EPS), else the first difference's path.
static func diff(a: Variant, b: Variant, path: String = "") -> String:
	if (a is float or a is int) and (b is float or b is int):
		return "" if absf(float(a) - float(b)) <= EPS else "%s: %s vs %s" % [path, a, b]
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return "%s: keys %s vs %s" % [path, da.keys(), db.keys()]
		for k in da:
			if not db.has(k):
				return "%s: missing %s" % [path, k]
			var d := diff(da[k], db[k], "%s.%s" % [path, k])
			if d != "":
				return d
		return ""
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return "%s: size %d vs %d" % [path, aa.size(), ab.size()]
		for i in aa.size():
			var d := diff(aa[i], ab[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, a, b]


func test_regenerated_matches_committed(c: HHSelfTest.HHCheck) -> void:
	for id in HHArenaGens.ids():
		var path := "res://arenas/%s.json" % id
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		c.ok(parsed is Dictionary, "%s: the committed JSON parses" % id)
		if not (parsed is Dictionary):
			continue
		var d: Dictionary = parsed
		var params: Dictionary = (d.gen as Dictionary).params
		var now: Dictionary = JSON.parse_string(JSON.stringify(_export(id, params)))
		# core's to_dict now keeps the extra cell keys (cover, hp, kind_after,
		# sun); the committed file carries them in its own blocks instead
		var nc: Array = now.get("cells", [])
		var dc: Array = d.get("cells", [])
		if nc.size() == dc.size():
			for i in nc.size():
				var cn: Dictionary = nc[i]
				for key in cn.keys():
					if not (dc[i] as Dictionary).has(key):
						cn.erase(key)
		var keys := d.keys()
		keys.sort()
		for k in keys:
			var why := diff(now.get(k), d[k], "%s.%s" % [id, k])
			c.ok(why == "", "%s: '%s' unchanged by the look %s" % [id, k, why])
