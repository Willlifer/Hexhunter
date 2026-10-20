extends RefCounted
## Lane A: the weapon models (art/weapons/*.glb + weapons.json): every glb loads,
## the manifest rows carry the sockets Lane B needs, tris under budget, aabb sane,
## the karambit is sword sized.

const MANIFEST := "res://art/weapons/weapons.json"
const IDS := ["lance", "karambit", "bow", "arrow"]
const TRI_BUDGET := 1500
const ROLES := ["steel", "wood", "wrap", "feather", "gem", "string"]


static func manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	return scene.instantiate() as Node3D


static func tris_of(n: Node3D) -> int:
	var t := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var arrays := m.surface_get_arrays(i)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				t += (idx as PackedInt32Array).size() / 3
			else:
				t += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


static func roles_of(n: Node3D) -> Array:
	var out: Array = []
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			out.append(mat.resource_name if mat else "")
	return out


static func bounds_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_manifest(c: HHSelfTest.HHCheck) -> void:
	var m := manifest()
	c.ok(not m.is_empty(), "weapons.json parses")
	if m.is_empty():
		return
	c.eq(int(m.get("version", 0)), 1, "manifest version 1")
	c.eq(int(m.get("rig_version", 0)), 1, "fitted to rig version 1")
	var rows: Dictionary = m.get("weapons", {})
	for id in IDS:
		c.ok(rows.has(id), "row %s" % id)
	for r in ROLES:
		c.ok(r in (m.get("roles", []) as Array), "role %s declared" % r)


func test_sockets_for_lane_b(c: HHSelfTest.HHCheck) -> void:
	var rows: Dictionary = manifest().get("weapons", {})
	if rows.is_empty():
		c.ok(false, "no manifest")
		return
	var lance: Dictionary = rows.get("lance", {})
	c.eq(str(lance.get("hands", "")), "two", "lance: two hands")
	c.eq(str(lance.get("socket", "")), "socket_weapon_r", "lance: right-hand socket")
	var lsh: Variant = lance.get("second_hand")
	c.ok(lsh is Dictionary and str((lsh as Dictionary).get("hand", "")) == "l", "lance: left-hand target")
	if lsh is Dictionary:
		c.ok(v3((lsh as Dictionary).point).y > 0.3, "lance: the left hand grips up the haft")
	var k: Dictionary = rows.get("karambit", {})
	c.eq(str(k.get("hands", "")), "pair", "karambit: a pair")
	c.eq(str(k.get("socket", "")), "socket_weapon_r", "karambit: right-hand socket")
	c.eq(str(k.get("offhand_socket", "")), "socket_offhand_l", "karambit: off-hand socket")
	c.ok(bool(k.get("mirror_offhand", false)), "karambit: the left one is mirrored")
	c.ok(ResourceLoader.exists(str(k.get("offhand_glb", ""))), "karambit_l.glb imported")
	c.ok(k.get("second_hand") == null, "karambit: no second-hand target (each hand holds one)")
	var bow: Dictionary = rows.get("bow", {})
	c.eq(str(bow.get("hands", "")), "bow", "bow: bow hands")
	c.eq(str(bow.get("socket", "")), "socket_offhand_l", "bow: held in the left hand")
	var bsh: Variant = bow.get("second_hand")
	c.ok(bsh is Dictionary and str((bsh as Dictionary).get("hand", "")) == "r", "bow: draw-hand target")
	var st: Variant = bow.get("string")
	c.ok(st is Array and (st as Array).size() == 2, "bow: string marker pair")
	if st is Array and (st as Array).size() == 2:
		var a := v3((st as Array)[0])
		var b := v3((st as Array)[1])
		c.ok(a.distance_to(b) > 1.2, "bow: the string spans the bow (%.2f m)" % a.distance_to(b))
		c.ok(a.z < 0.0 and b.z < 0.0, "bow: the string sits behind the riser (-Z, the archer's side)")
		if bsh is Dictionary:
			var nock := v3((bsh as Dictionary).point)
			c.ok(absf(nock.z - a.z) < 0.01 and absf(nock.y) < 0.01, "bow: the draw hand is on the string's middle")
	c.eq(str(bow.get("projectile", "")), "arrow", "bow: shoots the arrow")
	var arrow: Dictionary = rows.get("arrow", {})
	c.eq(str(arrow.get("hands", "")), "none", "arrow: a projectile")
	c.ok(arrow.get("socket") == null, "arrow: no socket")
	c.ok(v3(arrow.tip).y > 0.4 and v3(arrow.trail_base).y < -0.3, "arrow: head up +Y, nock down")
	for id in IDS:
		var row: Dictionary = rows[id]
		for key in ["tip", "trail_base", "aura_points", "mount", "length", "aabb", "tris", "glb"]:
			c.ok(row.has(key), "%s has %s" % [id, key])
		var mount: Dictionary = row.get("mount", {})
		c.ok(v3(mount.get("position", [1, 1, 1])).is_zero_approx() and v3(mount.get("rotation_deg", [1, 1, 1])).is_zero_approx(), "%s mount is identity" % id)
		c.ok((row.aura_points as Array).size() >= 3, "%s has aura anchors" % id)


func test_models_load_and_budget(c: HHSelfTest.HHCheck) -> void:
	var rows: Dictionary = manifest().get("weapons", {})
	for id in IDS:
		var row: Dictionary = rows.get(id, {})
		var path := "res://art/weapons/%s.glb" % id
		c.ok(ResourceLoader.exists(path), "%s.glb imported" % id)
		var n := instance(path)
		c.ok(n != null, "%s instances" % id)
		if n == null or row.is_empty():
			continue
		var tris := tris_of(n)
		c.ok(tris > 40 and tris <= TRI_BUDGET, "%s under %d tris (%d)" % [id, TRI_BUDGET, tris])
		c.eq(tris, int(row.tris), "%s tris match the manifest" % id)
		var roles := roles_of(n)
		roles.sort()
		var want: Array = (row.roles as Array).duplicate()
		want.sort()
		c.eq(roles, want, "%s surfaces are the manifest's roles (one MeshInstance3D per role)" % id)
		for r in roles:
			c.ok(r in ROLES, "%s role %s is known" % [id, r])
		# aabb sane: the manifest box matches the mesh, nothing degenerate or huge
		var box := bounds_of(n)
		var lo := v3(row.aabb.min)
		var hi := v3(row.aabb.max)
		c.ok(box.position.distance_to(lo) < 0.02 and box.end.distance_to(hi) < 0.02, "%s aabb matches the mesh" % id)
		var size := hi - lo
		c.ok(size.x > 0.01 and size.y > 0.3 and size.z > 0.01, "%s has volume (%s)" % [id, size])
		c.ok(size.x < 1.0 and size.y < 3.5 and size.z < 2.0, "%s is weapon sized (%s)" % [id, size])
		c.near(size.y, float(row.length), 0.02, "%s length is the +Y extent" % id)
		c.ok(absf(lo.x + hi.x) < 0.05, "%s is centred on the grip in x" % id)
		# the grip (origin) is inside the model; the tip is a long way from it, inside the box
		var grown := AABB(lo, size).grow(0.05)
		c.ok(grown.has_point(Vector3.ZERO), "%s grip origin inside the model" % id)
		var tip := v3(row.tip)
		c.ok(grown.has_point(tip), "%s tip inside the bounds" % id)
		c.ok(tip.length() > (0.04 if id == "bow" else 0.4), "%s tip away from the grip" % id)
		c.ok(tip.distance_to(v3(row.trail_base)) > 0.2, "%s trail has length" % id)
		for p in row.aura_points:
			c.ok(grown.has_point(v3(p)), "%s aura point inside the bounds" % id)
		n.free()


func test_karambit_is_sword_sized(c: HHSelfTest.HHCheck) -> void:
	var rows: Dictionary = manifest().get("weapons", {})
	var k: Dictionary = rows.get("karambit", {})
	if k.is_empty():
		c.ok(false, "no karambit row")
		return
	c.ok(float(k.length) >= 0.8, "karambit length >= 0.8 m (%.2f)" % float(k.length))
	var tip := v3(k.tip)
	c.ok(tip.z > 0.4, "the point hooks forward (+Z) (%.2f)" % tip.z)
	c.ok(tip.y > 0.5, "the point is high up the blade (%.2f)" % tip.y)
	var l := instance("res://art/weapons/karambit_l.glb")
	var r := instance("res://art/weapons/karambit.glb")
	c.ok(l != null and r != null, "both hands' karambits load")
	if l != null and r != null:
		var bl := bounds_of(l)
		var br := bounds_of(r)
		c.ok(bl.size.is_equal_approx(br.size), "the left karambit is the right one's size")
		c.ok(absf(bl.position.x + br.end.x) < 0.01, "...mirrored in x")
		c.eq(tris_of(l), tris_of(r), "same tris")
	if l != null:
		l.free()
	if r != null:
		r.free()
	var lance: Dictionary = rows.get("lance", {})
	c.ok(float(lance.get("length", 0.0)) >= 2.4, "the glaive-lance is a long pole (%.2f m)" % float(lance.get("length", 0.0)))
	var bow: Dictionary = rows.get("bow", {})
	var bb := v3(bow.aabb.max) - v3(bow.aabb.min)
	c.ok(bb.y >= 1.5 and bb.y <= 2.6, "the bow stands about a rig tall with its wings (%.2f m)" % bb.y)
