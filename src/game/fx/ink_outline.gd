class_name HHInk
extends RefCounted
## H84-H85 (Lane Y): the comic ink outline, shared by the hunter and the
## monsters. An inverted hull: for every MeshInstance3D of a body, a sibling
## `ink_<name>` draws a copy of its mesh (all surfaces merged into one, the
## normals averaged across hard edges and role seams so the hull never
## cracks) with shaders/ink_outline.gdshader, on the same Skin and skeleton,
## so it deforms with the body. Telegraph glows (fx_glow emission) are on the
## body's own materials; the hull only shows outside the silhouette, so a
## glow still reads.
##
##   var inks := HHInk.apply(model, 1.0)        # once, after the body is built
##   HHInk.sync(inks, 1.0)                      # every frame: on/off and width from HHTune
##
## Tune (F1): ink_on (1 = on, the default), ink_px (line width in pixels at
## 1080 lines), ink_max_m (cap in metres). `scale` per body: a big monster
## passes < 1 so its line is not fatter than the hunter's.

const SHADER := "res://shaders/ink_outline.gdshader"
const PREFIX := "ink_"

const META := "hh_ink_hull"     # the hull mesh is cached on its source mesh (no static resource refs: clean exit)


## Add the hull siblings under `root`. Returns the hull MeshInstance3Ds.
static func apply(root: Node, scale: float = 1.0) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root == null:
		return out
	var mat := material(scale)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or str(mi.name).begins_with(PREFIX):
			continue
		var hull_mesh := hull(mi.mesh)
		if hull_mesh == null:
			continue
		var h := MeshInstance3D.new()
		h.name = PREFIX + str(mi.name)
		h.mesh = hull_mesh
		h.material_override = mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.transform = mi.transform
		h.layers = mi.layers
		mi.get_parent().add_child(h)
		if mi.skin != null:
			h.skin = mi.skin
			h.skeleton = mi.skeleton         # a sibling: the same relative path
		out.append(h)
	sync(out, scale)
	return out


## Per frame: visibility and line weight from HHTune.
static func sync(inks: Array, scale: float = 1.0) -> void:
	var on := enabled()
	var done := {}
	for h in inks:
		if not is_instance_valid(h):
			continue
		var mi := h as MeshInstance3D
		mi.visible = on
		var m := mi.material_override as ShaderMaterial
		if on and m != null and not done.has(m):
			done[m] = true
			m.set_shader_parameter("width_px", HHTune.value("ink_px") * scale)
			m.set_shader_parameter("max_world", HHTune.value("ink_max_m") * scale)


static func enabled() -> bool:
	return HHTune.value("ink_on") > 0.5


## A body's outline material (one per apply: every hull of the body shares it).
static func material(scale: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("width_px", HHTune.value("ink_px") * scale)
	m.set_shader_parameter("max_world", HHTune.value("ink_max_m") * scale)
	return m


## One-surface copy of `src` with smoothed normals (cached per mesh).
static func hull(src: Mesh) -> ArrayMesh:
	if src.has_meta(META):
		return src.get_meta(META) as ArrayMesh
	var verts := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var skinned := false
	var eight := false
	for s in src.get_surface_count():
		if src is ArrayMesh and (src as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var a := src.surface_get_arrays(s)
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if sv.is_empty():
			continue
		var base := verts.size()
		verts.append_array(sv)
		var sb: Variant = a[Mesh.ARRAY_BONES]
		var sw: Variant = a[Mesh.ARRAY_WEIGHTS]
		if sb != null and (sb as PackedInt32Array).size() > 0:
			skinned = true
			if (sb as PackedInt32Array).size() == sv.size() * 8:
				eight = true
			bones.append_array(sb)
			weights.append_array(sw)
		var si: Variant = a[Mesh.ARRAY_INDEX]
		if si != null and (si as PackedInt32Array).size() > 0:
			for i in (si as PackedInt32Array):
				idx.append(base + i)
		else:
			for i in sv.size():
				idx.append(base + i)
	if verts.is_empty():
		return null
	# smooth normals: face normals summed per welded position (1 mm grid)
	var acc := {}
	var keys := PackedInt32Array()
	keys.resize(verts.size())
	var key_of := {}
	for i in verts.size():
		var p := verts[i]
		var k := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not key_of.has(k):
			key_of[k] = key_of.size()
		keys[i] = key_of[k]
	var sums: Array[Vector3] = []
	sums.resize(key_of.size())
	sums.fill(Vector3.ZERO)
	for t in range(0, idx.size() - 2, 3):
		var a0 := verts[idx[t]]
		var n := (verts[idx[t + 2]] - a0).cross(verts[idx[t + 1]] - a0)   # Godot's clockwise front faces
		for j in 3:
			sums[keys[idx[t + j]]] += n
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = sums[keys[i]]
		normals[i] = n.normalized() if n.length_squared() > 1e-16 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var flags := 0
	if skinned and bones.size() == verts.size() * (8 if eight else 4):
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		if eight:
			flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	src.set_meta(META, out)
	return out
