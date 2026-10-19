"""Monster Rig Builder: an articulated low-poly monster from a spec dict.

Used by tools/blender/build_monster_<id>.py:

    import rigkit
    row = rigkit.build(SPEC, glb_path)        # writes the glb, returns the manifest row

Coordinates in the spec are Blender's: Z up, the creature faces -Y, its
left is +X, metres. The glTF exporter's +Y-up conversion makes that Godot's
Y up, facing +Z, left +X: (x, y, z) -> (x, z, -y). The manifest is written
in Godot coordinates. Everything is deterministic (no randomness; the mottle
is a hash of vertex indices).

SPEC (every key optional unless noted):
  id (required)       monster id; the armature and mesh are named after it
  version             int; bumped when bones, sockets or proportions change
  footprint_hexes     the sim footprint radius (manifest only)
  roles               { role: (r, g, b) }: hide, belly, frill, teeth, eye, claw ...
                      One Blender material per role (Principled, white base,
                      vertex COLOR carries the colour). The mesh's surfaces
                      are named after the roles.
  mottle              { "role": "hide", "alt": (r, g, b), "scale": m, "amount": 0..1 }
                      blotches of `alt` over the role's colour on the body loft
  belly               { "flat": 0..1, "role": "belly", "below": 0..1 }: flattens the
                      underside of the body loft and colours its lower part
  chains              [ chain ]: a chain is a loft of ellipse cross-sections
                      skinned to its own bones:
                        name, parent (bone the first bone hangs from, or None),
                        stations: [ { p: (x,y,z), rx, rz, drop (ellipse centre
                          shift, -z), role } ... ] in order along the chain,
                        bones: [ (bone_name, from_station, to_station) ... ],
                        sides (ring vertex count), blend (weight blend width, m),
                        cap_start / cap_end (close the loft), mottle (bool),
                        taper_end: fraction of the last radius kept at the tip
                      Bone i hangs from bone i-1 of the same chain; the first
                      from `parent`.
  extra_bones         [ (name, parent, head, tail, roll_hint) ]: bones with no
                      loft (jaw, frill_l, frill_r ...), deform
  legs                [ { id, parent, hip, knee, ankle, toe, radii: (hip, knee,
                        ankle), sides, claws, claw_len, foot: (w, l, h) } ]
                      bones hip_<id>, knee_<id>, ankle_<id>, toe_<id>; an IK
                      target empty ik_<id> at the toe
  jaw                 { bone: "jaw", width, length, height, teeth: n, tooth: m,
                        role, teeth_role }: a wedge hanging from the jaw bone's
                        head, teeth along both sides
  upper_teeth         { bone, at: (x,y,z), width, length, teeth, tooth }
  frill               { bones: ["frill_l","frill_r"], spikes, length, width,
                        sweep, role, spread_deg }: a fan of thin quads per side
  fins                [ { bone, base: (x,y,z), tip: (x,y,z), root_len, role } ]:
                      one thin triangle each, double sided
  eyes                [ { bone, at: (x,y,z), r, role } ]
  sockets             { socket_name: (bone, (x,y,z)) }: empties, exported as
                      Node3D children of BoneAttachment3D in Godot
"""

import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

RIGKIT_VERSION = 1

UP = Vector((0, 0, 1))
FORWARD = Vector((0, -1, 0))


def V(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


def gd(p):
    """Blender (x, y, z) -> Godot (x, z, -y), rounded."""
    return [round(float(p[0]), 4), round(float(p[2]), 4), round(-float(p[1]), 4)]


def _hash01(*ints):
    """Deterministic 0..1 from integers (a small LCG, no random module)."""
    h = 2166136261
    for i in ints:
        h = ((h ^ (int(i) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFFFF) / float(0xFFFFFF)


def _smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


# ----------------------------------------------------------------- bones
class Bone:
    def __init__(self, name, parent, head, tail, roll_hint=UP, connect=False, deform=True):
        self.name = name
        self.parent = parent
        self.head = V(head)
        self.tail = V(tail)
        self.roll_hint = roll_hint
        self.connect = connect
        self.deform = deform

    def closest(self, p):
        """Distance from p to the bone segment."""
        d = self.tail - self.head
        L2 = d.length_squared
        if L2 < 1e-9:
            return (p - self.head).length
        u = max(0.0, min(1.0, (p - self.head).dot(d) / L2))
        return (p - (self.head + d * u)).length


# ------------------------------------------------------------------ mesh
class MeshBuilder:
    """Collects verts / faces / weights / role / colour, emits one mesh.
    Islands stay separate (hard joints are fine at this scale)."""

    def __init__(self, bones, roles):
        self.verts = []
        self.weights = []
        self.faces = []       # (indices, role)
        self.colors = []
        self.bones = bones    # name -> Bone
        self.roles = roles    # role -> (r, g, b)

    def add_vert(self, co, w, role, color=None):
        self.verts.append(V(co))
        tot = sum(w.values())
        self.weights.append({k: v / tot for k, v in w.items() if v > 1e-6})
        c = color or self.roles.get(role, (1, 1, 1))
        self.colors.append((c[0], c[1], c[2], 1.0))
        return len(self.verts) - 1

    def auto_weight(self, p, names, blend):
        """Nearest two bones among `names`, blended when within `blend`."""
        ds = sorted((self.bones[n].closest(p), n) for n in names)
        if len(ds) == 1 or ds[1][0] - ds[0][0] >= blend:
            return {ds[0][1]: 1.0}
        t = (ds[1][0] - ds[0][0]) / blend          # 0 at a tie, 1 at the blend edge
        w1 = 0.5 + 0.5 * _smooth(t)
        return {ds[0][1]: w1, ds[1][1]: 1.0 - w1}

    # -- primitives ---------------------------------------------------
    def loft(self, rings, role_fn, w_fn, sides, cap_start, cap_end, color_fn=None):
        """rings: list of (centre, tangent, rx, rz, drop, flat). Parallel
        transport keeps the frames from twisting. `role_fn(ring_i, k, local_z)`
        gives the role; `w_fn(centre)` the weights; `color_fn(i, k, role)`
        an optional colour override."""
        n = None
        loops = []
        for i, (c, t, rx, rz, drop, flat) in enumerate(rings):
            t = t.normalized()
            if n is None:
                ref = UP if abs(t.dot(UP)) < 0.9 else Vector((1, 0, 0))
                n = (ref - t * ref.dot(t)).normalized()
            else:
                n = (n - t * n.dot(t)).normalized()
            b = t.cross(n)                     # side axis
            w = w_fn(c)
            row = []
            for k in range(sides):
                a = 2 * math.pi * (k + 0.5) / sides
                z = math.cos(a)                 # +1 top (along n = up-ish)
                x = math.sin(a)
                zz = z * rz
                if z < 0:
                    zz *= flat                  # flatter belly
                p = c + n * (zz - drop) + b * (x * rx)
                role = role_fn(i, k, z)
                col = color_fn(i, k, role) if color_fn else None
                row.append(self.add_vert(p, w, role, col))
            loops.append((row, w))
        for i in range(len(loops) - 1):
            r0, r1 = loops[i][0], loops[i + 1][0]
            for k in range(sides):
                k2 = (k + 1) % sides
                role = self._face_role(i, k)
                self.faces.append(((r0[k], r0[k2], r1[k2], r1[k]), role))
        if cap_start:
            c, _, _, _, drop, _ = rings[0]
            ctr = self.add_vert(c - UP * drop, loops[0][1], role_fn(0, 0, 1.0))
            row = loops[0][0]
            for k in range(sides):
                self.faces.append(((ctr, row[(k + 1) % sides], row[k]), role_fn(0, k, 1.0)))
        if cap_end:
            c, _, _, _, drop, _ = rings[-1]
            ctr = self.add_vert(c - UP * drop, loops[-1][1], role_fn(len(rings) - 1, 0, 1.0))
            row = loops[-1][0]
            for k in range(sides):
                self.faces.append(((ctr, row[k], row[(k + 1) % sides]), role_fn(len(rings) - 1, k, 1.0)))
        return loops

    def _face_role(self, i, k):
        # the role of a quad: the role of its first vertex's colour role is
        # not stored; use the per-face role recorded by loft_roles
        return self._cur_face_roles[i][k] if hasattr(self, "_cur_face_roles") else "hide"

    def tube(self, pts, radii, w_names, blend, sides, role, cap_start=True, cap_end=True, explicit_w=None):
        """A tapered tube along a polyline with ball-ish joints: rings at
        each point (and at the half-way of each segment), weights auto."""
        rings = []
        n = len(pts)
        for i in range(n):
            if i > 0:
                mid = (pts[i - 1] + pts[i]) * 0.5
                rm = (radii[i - 1] + radii[i]) * 0.5
                t = (pts[i] - pts[i - 1]).normalized()
                rings.append((mid, t, rm, rm, 0.0, 1.0))
            if i == 0:
                t = (pts[1] - pts[0]).normalized()
            elif i == n - 1:
                t = (pts[-1] - pts[-2]).normalized()
            else:
                t = ((pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()).normalized()
            rings.append((pts[i], t, radii[i], radii[i], 0.0, 1.0))
        self._cur_face_roles = [[role] * sides for _ in rings]
        wf = (lambda c: explicit_w) if explicit_w else (lambda c: self.auto_weight(c, w_names, blend))
        return self.loft(rings, lambda i, k, z: role, wf, sides, cap_start, cap_end)

    def box(self, center, half, basis, w, role, color=None):
        """An oriented box: basis columns = local x, y, z axes."""
        idx = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    p = center + basis @ Vector((sx * half[0], sy * half[1], sz * half[2]))
                    idx.append(self.add_vert(p, w, role, color))
        # idx order: (-,-,-) (-,-,+) (-,+,-) (-,+,+) (+,-,-) (+,-,+) (+,+,-) (+,+,+)
        quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        for q in quads:
            self.faces.append((tuple(idx[i] for i in q), role))

    def wedge(self, base_pts, tip_pts, w, role, color=None):
        """A prism from 4 base points to 4 tip points (quad -> quad), closed."""
        b = [self.add_vert(p, w, role, color) for p in base_pts]
        t = [self.add_vert(p, w, role, color) for p in tip_pts]
        self.faces.append(((b[0], b[1], b[2], b[3]), role))
        self.faces.append(((t[3], t[2], t[1], t[0]), role))
        for i in range(4):
            j = (i + 1) % 4
            self.faces.append(((b[i], t[i], t[j], b[j]), role))

    def pyramid(self, base_pts, apex, w, role, color=None):
        b = [self.add_vert(p, w, role, color) for p in base_pts]
        a = self.add_vert(apex, w, role, color)
        self.faces.append((tuple(reversed(b)), role))
        for i in range(len(b)):
            self.faces.append(((b[i], b[(i + 1) % len(b)], a), role))

    def blade(self, root_a, root_b, tip, w, role, thick=0.02, color=None):
        """A thin double-sided spike: two triangles with a tiny thickness
        so it never z-fights and both faces light."""
        n = (root_b - root_a).cross(tip - root_a)
        if n.length < 1e-9:
            n = UP
        n = n.normalized() * thick * 0.5
        a0 = self.add_vert(root_a + n, w, role, color)
        b0 = self.add_vert(root_b + n, w, role, color)
        t0 = self.add_vert(tip + n, w, role, color)
        a1 = self.add_vert(root_a - n, w, role, color)
        b1 = self.add_vert(root_b - n, w, role, color)
        t1 = self.add_vert(tip - n, w, role, color)
        self.faces.append(((a0, b0, t0), role))
        self.faces.append(((b1, a1, t1), role))
        self.faces.append(((a0, a1, b1, b0), role))
        self.faces.append(((b0, b1, t1, t0), role))
        self.faces.append(((t0, t1, a1, a0), role))

    def sphere(self, center, r, w, role, seg=8, rings=4, color=None):
        top = self.add_vert(center + UP * r, w, role, color)
        lat = []
        for i in range(1, rings):
            th = math.pi * i / rings
            row = []
            for j in range(seg):
                ph = 2 * math.pi * j / seg
                p = Vector((r * math.sin(th) * math.cos(ph), r * math.sin(th) * math.sin(ph), r * math.cos(th)))
                row.append(self.add_vert(center + p, w, role, color))
            lat.append(row)
        bot = self.add_vert(center - UP * r, w, role, color)
        for j in range(seg):
            k = (j + 1) % seg
            self.faces.append(((top, lat[0][j], lat[0][k]), role))
            self.faces.append(((bot, lat[-1][k], lat[-1][j]), role))
        for i in range(len(lat) - 1):
            for j in range(seg):
                k = (j + 1) % seg
                self.faces.append(((lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k]), role))

    # -- emit ----------------------------------------------------------
    def build(self, name, materials):
        """materials: ordered list of (role, bpy material). Returns a list of
        (role, mesh, weights) with ONE mesh per role: Blender 5.2's glTF
        exporter drops the vertex colour of every primitive after the first
        when several materials share one colour attribute
        (primitive_extract.py stores the attribute key instead of COLOR_0),
        so each role is exported as its own object and primitive."""
        out = []
        for role, mat in materials:
            faces = [f for f, r in self.faces if r == role]
            if not faces:
                continue
            remap = {}
            verts = []
            weights = []
            colors = []
            new_faces = []
            for f in faces:
                nf = []
                for vi in f:
                    if vi not in remap:
                        remap[vi] = len(verts)
                        verts.append(self.verts[vi])
                        weights.append(self.weights[vi])
                        colors.append(self.colors[vi])
                    nf.append(remap[vi])
                new_faces.append(tuple(nf))
            me = bpy.data.meshes.new("%s_%s" % (name, role))
            me.from_pydata([tuple(v) for v in verts], [], new_faces)
            me.materials.append(mat)
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
            for p in me.polygons:
                p.use_smooth = False          # low-poly: faceted
            # The palette is authored as displayed (sRGB) colour; `.color` is
            # scene-linear and would wash everything out after export.
            col = me.color_attributes.new("Color", 'BYTE_COLOR', 'POINT')
            for i, c in enumerate(colors):
                col.data[i].color_srgb = c
            me.color_attributes.active_color = col
            me.color_attributes.render_color_index = 0
            me.update()
            out.append((role, me, weights))
        return out


# ------------------------------------------------------------ materials
def make_material(role, rgb):
    """Plain PBR per role: Principled, white base x vertex COLOR (Godot
    multiplies albedo by COLOR_0 when the mesh carries one)."""
    m = bpy.data.materials.new(role)
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85 if role in ("hide", "belly", "frill") else 0.4
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


# ------------------------------------------------------------------ rig
def collect_bones(spec):
    """All bones in skeleton order: root, chains, extra bones, legs."""
    bones = []
    order = []

    def add(b):
        bones.append(b)
        order.append(b.name)

    add(Bone("root", None, (0, 0, 0), (0, 0, 0.5), FORWARD))
    for ch in spec.get("chains", []):
        st = ch["stations"]
        prev = ch.get("parent", "root")
        for (name, i0, i1) in ch["bones"]:
            add(Bone(name, prev, st[i0]["p"], st[i1]["p"], ch.get("roll", UP)))
            prev = name
    for (name, parent, head, tail, hint) in spec.get("extra_bones", []):
        add(Bone(name, parent, head, tail, hint))
    for leg in spec.get("legs", []):
        lid = leg["id"]
        pts = [V(leg["hip"]), V(leg["knee"]), V(leg["ankle"]), V(leg["toe"])]
        names = ["hip_" + lid, "knee_" + lid, "ankle_" + lid, "toe_" + lid]
        parent = leg["parent"]
        for i in range(3):
            add(Bone(names[i], parent, pts[i], pts[i + 1], FORWARD))
            parent = names[i]
        toe_tip = pts[3] + (pts[3] - pts[2]).normalized() * float(leg.get("toe_len", 0.35))
        toe_tip.z = max(0.02, pts[3].z)
        add(Bone(names[3], parent, pts[3], toe_tip, UP))
    return bones, order


def build_armature(spec, bones):
    arm = bpy.data.armatures.new(spec["id"] + "_armature")
    arm.display_type = 'OCTAHEDRAL'
    obj = bpy.data.objects.new(spec["id"], arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for b in bones:
        e = eb.new(b.name)
        e.head, e.tail = b.head, b.tail
        if (e.tail - e.head).length < 1e-4:
            e.tail = e.head + Vector((0, 0, 0.05))
        e.align_roll(b.roll_hint)
        e.use_deform = b.deform
        if b.parent:
            e.parent = eb[b.parent]
            e.use_connect = b.connect
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in arm.bones:
        b.inherit_scale = 'FULL'
    return obj


# ------------------------------------------------------------- body parts
def chain_rings(ch):
    """Rings for a chain's stations: (centre, tangent, rx, rz, drop, flat)."""
    st = ch["stations"]
    pts = [V(s["p"]) for s in st]
    out = []
    n = len(pts)
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()
        s = st[i]
        out.append((pts[i], t.normalized(), float(s["rx"]), float(s["rz"]), float(s.get("drop", 0.0)),
                    float(s.get("flat", ch.get("flat", 1.0)))))
    return out


def build_chain(mb, spec, ch):
    rings = chain_rings(ch)
    names = [b[0] for b in ch["bones"]]
    sides = int(ch.get("sides", 12))
    blend = float(ch.get("blend", 0.3))
    belly = spec.get("belly", {})
    below = float(belly.get("below", -0.35))
    mottle = spec.get("mottle", {})
    use_mottle = bool(ch.get("mottle", False)) and mottle
    st = ch["stations"]

    def role_fn(i, k, z):
        r = st[i].get("role", ch.get("role", "hide"))
        if r == "hide" and belly and z < below and bool(ch.get("belly", True)):
            return belly.get("role", "belly")
        return r

    def color_fn(i, k, role):
        if not use_mottle or role != mottle.get("role", "hide"):
            return None
        base = spec["roles"][role]
        alt = mottle.get("alt", base)
        h = _hash01(i * 7 + 3, k * 13 + 1, 17)
        amt = float(mottle.get("amount", 0.5))
        if h < amt:
            f = 0.55 + 0.45 * _hash01(i, k, 99)
            return (base[0] + (alt[0] - base[0]) * f, base[1] + (alt[1] - base[1]) * f, base[2] + (alt[2] - base[2]) * f)
        f = 0.9 + 0.1 * _hash01(k, i, 5)
        return (base[0] * f, base[1] * f, base[2] * f)

    # per-face roles: a quad takes its lower ring vertex's role
    face_roles = []
    for i in range(len(rings)):
        row = []
        for k in range(sides):
            a = 2 * math.pi * (k + 0.5) / sides
            row.append(role_fn(i, k, math.cos(a)))
        face_roles.append(row)
    mb._cur_face_roles = face_roles
    mb.loft(rings, role_fn, lambda c: mb.auto_weight(c, names, blend), sides,
            bool(ch.get("cap_start", True)), bool(ch.get("cap_end", True)), color_fn)


def build_leg(mb, spec, leg):
    lid = leg["id"]
    pts = [V(leg["hip"]), V(leg["knee"]), V(leg["ankle"])]
    radii = list(leg["radii"])
    names = ["hip_" + lid, "knee_" + lid, "ankle_" + lid]
    sides = int(leg.get("sides", 8))
    mb.tube(pts, radii, names[:2], float(leg.get("blend", 0.18)), sides, leg.get("role", "hide"))
    # the foot: a flat box from the ankle forward to the toe, on the toe bone
    ankle = pts[2]
    toe = V(leg["toe"])
    fw, fl, fh = leg.get("foot", (0.4, 0.7, 0.18))
    d = (toe - ankle)
    d.z = 0
    if d.length < 1e-6:
        d = FORWARD.copy()
    d = d.normalized()
    side = d.cross(UP).normalized()
    basis = Matrix((side, d, UP)).transposed()
    centre = ankle + d * (fl * 0.5)
    centre.z = fh * 0.5 + 0.02
    wtoe = {"toe_" + lid: 0.7, "ankle_" + lid: 0.3}
    mb.box(centre, (fw * 0.5, fl * 0.5, fh * 0.5), basis, wtoe, leg.get("role", "hide"))
    # a wrist block joins shin and foot (hides the hard joint)
    mb.sphere(ankle, radii[2] * 1.05, {"ankle_" + lid: 1.0}, leg.get("role", "hide"), seg=6, rings=3)
    # claws
    n = int(leg.get("claws", 3))
    cl = float(leg.get("claw_len", 0.3))
    front = centre + d * (fl * 0.5)
    for i in range(n):
        u = (i + 0.5) / n - 0.5
        base_c = front + side * (u * fw * 0.8)
        base_c.z = fh * 0.45
        hw = fw * 0.4 / n
        base = [base_c + side * hw - UP * (fh * 0.35), base_c - side * hw - UP * (fh * 0.35),
                base_c - side * hw + UP * (fh * 0.35), base_c + side * hw + UP * (fh * 0.35)]
        tip = base_c + d * cl - UP * (fh * 0.3)
        tip.z = max(tip.z, 0.02)
        mb.pyramid(base, tip, {"toe_" + lid: 1.0}, leg.get("claw_role", "claw"))


def build_jaw(mb, spec, bones):
    j = spec.get("jaw")
    if not j:
        return
    b = bones[j["bone"]]
    hinge = b.head
    d = (b.tail - b.head).normalized()
    side = d.cross(UP).normalized()
    w0 = float(j["width"])
    L = float(j["length"])
    h = float(j["height"])
    role = j.get("role", "hide")
    tip_w = w0 * float(j.get("tip_w", 0.55))
    w = {j["bone"]: 1.0}
    base = [hinge + side * (w0 * 0.5), hinge - side * (w0 * 0.5),
            hinge - side * (w0 * 0.5) - UP * h, hinge + side * (w0 * 0.5) - UP * h]
    tipc = hinge + d * L
    tip = [tipc + side * (tip_w * 0.5) - UP * (h * 0.25), tipc - side * (tip_w * 0.5) - UP * (h * 0.25),
           tipc - side * (tip_w * 0.5) - UP * (h * 0.7), tipc + side * (tip_w * 0.5) - UP * (h * 0.7)]
    mb.wedge(base, tip, w, role)
    # the belly colour on the underside of the jaw is handled by role; teeth:
    n = int(j.get("teeth", 5))
    tl = float(j.get("tooth", 0.18))
    trole = j.get("teeth_role", "teeth")
    for s in (1, -1):
        for i in range(n):
            u = (i + 0.5) / n
            wu = w0 * 0.5 + (tip_w * 0.5 - w0 * 0.5) * u
            c = hinge + d * (L * u) + side * (s * wu * 0.95)
            hw = tl * 0.3
            bp = [c + d * hw + side * (s * hw * 0.3), c - d * hw + side * (s * hw * 0.3),
                  c - d * hw - side * (s * hw * 0.5), c + d * hw - side * (s * hw * 0.5)]
            mb.pyramid(bp, c + UP * tl + d * (hw * 0.3), w, trole)


def build_upper_teeth(mb, spec, bones):
    t = spec.get("upper_teeth")
    if not t:
        return
    b = bones[t["bone"]]
    d = (b.tail - b.head).normalized()
    side = d.cross(UP).normalized()
    at = V(t["at"])
    n = int(t.get("teeth", 5))
    tl = float(t.get("tooth", 0.2))
    w0 = float(t["width"])
    L = float(t["length"])
    tip_w = w0 * float(t.get("tip_w", 0.55))
    w = {t["bone"]: 1.0}
    for s in (1, -1):
        for i in range(n):
            u = (i + 0.5) / n
            wu = w0 * 0.5 + (tip_w * 0.5 - w0 * 0.5) * u
            c = at + d * (L * u) + side * (s * wu)
            hw = tl * 0.3
            bp = [c + d * hw + side * (s * hw * 0.3), c - d * hw + side * (s * hw * 0.3),
                  c - d * hw - side * (s * hw * 0.5), c + d * hw - side * (s * hw * 0.5)]
            mb.pyramid(list(reversed(bp)), c - UP * tl + d * (hw * 0.3), w, t.get("role", "teeth"))


def build_frill(mb, spec, bones):
    """A gill collar: per side, `spikes` rays rooted around the neck's
    cross-section (from `top_deg` above horizontal down to `bottom_deg`),
    raked back by `sweep`, webbed between neighbours, each ray a spine that
    runs a little past the web (a scalloped fan). Weighted to the side's
    frill bone, so a bone rotation flares it."""
    f = spec.get("frill")
    if not f:
        return
    role = f.get("role", "frill")
    n = int(f.get("spikes", 5))
    L = float(f.get("length", 1.2))
    sweep = float(f.get("sweep", 0.6))
    top = math.radians(float(f.get("top_deg", 70.0)))
    bottom = math.radians(float(f.get("bottom_deg", -25.0)))
    rx = float(f.get("neck_rx", 0.7))
    rz = float(f.get("neck_rz", 0.65))
    web = float(f.get("web", 0.75))          # web edge at this fraction of the ray length
    thick = float(f.get("thick", 0.03))
    centre = V(f.get("centre", (0.0, -3.0, 1.66)))
    back = -FORWARD
    for s, bname in ((1, f["bones"][0]), (-1, f["bones"][1])):
        w = {bname: 1.0}
        roots = []
        tips = []
        for i in range(n):
            u = i / float(n - 1) if n > 1 else 0.5
            a = top + (bottom - top) * u              # angle above horizontal, around the neck
            radial = Vector((s * math.cos(a), 0.0, math.sin(a))).normalized()
            root = centre + Vector((s * rx * math.cos(a), 0.0, rz * math.sin(a)))
            # the top rays are the long crest, the low ones shorter; all rake back
            length = L * (1.05 - 0.45 * u)
            tip = root + radial * length + back * (sweep * (0.5 + 0.7 * (1 - u)))
            roots.append(root)
            tips.append(tip)
        # the web: quads between neighbouring rays, double sided, inset from the tips
        for i in range(n - 1):
            ea = roots[i] + (tips[i] - roots[i]) * web
            eb = roots[i + 1] + (tips[i + 1] - roots[i + 1]) * web
            nrm = (roots[i + 1] - roots[i]).cross(ea - roots[i])
            if nrm.length < 1e-9:
                nrm = Vector((s, 0, 0))
            nrm = nrm.normalized() * thick * 0.5
            for sign in (1, -1):
                q = [mb.add_vert(p + nrm * sign, w, role) for p in (roots[i], roots[i + 1], eb, ea)]
                mb.faces.append((tuple(q) if sign > 0 else tuple(reversed(q)), role))
        # the rays: thin spines along each ray, past the web edge
        for i in range(n):
            d = (tips[i] - roots[i]).normalized()
            side = d.cross(UP)
            if side.length < 1e-6:
                side = Vector((1, 0, 0))
            side = side.normalized() * (0.09 * (1.0 - 0.4 * i / max(1, n - 1)))
            mb.blade(roots[i] + side, roots[i] - side, tips[i], w, role, thick=thick)


def build_fins(mb, spec, bones):
    for fin in spec.get("fins", []):
        bname = fin["bone"]
        b = bones[bname]
        base = V(fin["base"])
        tip = V(fin["tip"])
        rl = float(fin.get("root_len", 0.5))
        along = (b.tail - b.head).normalized()
        ra = base - along * (rl * 0.5)
        rb = base + along * (rl * 0.5)
        w = fin.get("weights") or {bname: 1.0}
        mb.blade(ra, rb, tip, w, fin.get("role", "frill"), thick=float(fin.get("thick", 0.03)))


def build_eyes(mb, spec):
    for e in spec.get("eyes", []):
        mb.sphere(V(e["at"]), float(e["r"]), {e["bone"]: 1.0}, e.get("role", "eye"), seg=6, rings=3)


# --------------------------------------------------------------- sockets
def make_sockets(spec, rig, bones_by_name):
    out = []
    vl = bpy.context.view_layer
    for name, (bone, pos) in spec.get("sockets", {}).items():
        e = bpy.data.objects.new("socket_" + name, None)
        e.empty_display_type = 'ARROWS'
        e.empty_display_size = 0.2
        bpy.context.scene.collection.objects.link(e)
        e.parent = rig
        e.parent_type = 'BONE'
        e.parent_bone = bone
        vl.update()
        e.matrix_world = Matrix.Translation(V(pos))
        out.append(e)
    for leg in spec.get("legs", []):
        e = bpy.data.objects.new("ik_" + leg["id"], None)
        e.empty_display_type = 'SPHERE'
        e.empty_display_size = 0.15
        bpy.context.scene.collection.objects.link(e)
        e.parent = rig
        vl.update()
        e.matrix_world = Matrix.Translation(V(leg["toe"]))
        out.append(e)
    vl.update()
    return out


def bind(mesh_obj, rig, weights, bone_order):
    for name in bone_order:
        mesh_obj.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        for bone, val in w.items():
            mesh_obj.vertex_groups[bone].add([i], val, 'REPLACE')
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    mod.use_deform_preserve_volume = False
    mesh_obj.parent = rig


IMPORT_STUB = """[remap]

importer="scene"
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=1
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
materials/extract=0
gltf/naming_version=2
"""


# ------------------------------------------------------------------ main
def build(spec, glb_path, blend_path=None):
    """Build the rig + mesh in the current (emptied) scene, export the glb,
    return the manifest row (Godot coordinates)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scn = bpy.context.scene
    scn.unit_settings.system = 'METRIC'

    bones, order = collect_bones(spec)
    by_name = {b.name: b for b in bones}
    rig = build_armature(spec, bones)

    roles = dict(spec.get("roles", {}))
    materials = [(r, make_material(r, roles[r])) for r in roles]
    mb = MeshBuilder(by_name, roles)
    for ch in spec.get("chains", []):
        build_chain(mb, spec, ch)
    for leg in spec.get("legs", []):
        build_leg(mb, spec, leg)
    build_jaw(mb, spec, by_name)
    build_upper_teeth(mb, spec, by_name)
    build_frill(mb, spec, by_name)
    build_fins(mb, spec, by_name)
    build_eyes(mb, spec)
    bodies = []
    for role, me, weights in mb.build("body", materials):
        body = bpy.data.objects.new("body_" + role, me)
        scn.collection.objects.link(body)
        bind(body, rig, weights, order)
        bodies.append(body)
    sockets = make_sockets(spec, rig, by_name)
    rig["rig_version"] = int(spec.get("version", 1))
    bpy.context.view_layer.update()

    # stats
    tris = sum(len(p.vertices) - 2 for b in bodies for p in b.data.polygons)
    nverts = sum(len(b.data.vertices) for b in bodies)
    xs = [v.co.x for b in bodies for v in b.data.vertices]
    ys = [v.co.y for b in bodies for v in b.data.vertices]
    zs = [v.co.z for b in bodies for v in b.data.vertices]
    aabb_min = gd((min(xs), max(ys), min(zs)))     # Godot z = -y: max y -> min z
    aabb_max = gd((max(xs), min(ys), max(zs)))

    os.makedirs(os.path.dirname(glb_path), exist_ok=True)
    if blend_path:
        os.makedirs(os.path.dirname(blend_path), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=blend_path, compress=False)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in [rig] + bodies + sockets:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=glb_path, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
        export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_skins=True, export_def_bones=True, export_leaf_bone=False, export_influence_nb=4,
        export_animations=False, export_morph=False, export_cameras=False, export_lights=False,
        export_extras=False, export_rest_position_armature=True,
    )
    stub = glb_path + ".import"
    if not os.path.exists(stub):
        with open(stub, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(IMPORT_STUB)

    # manifest row
    chains = {}
    for ch in spec.get("chains", []):
        chains[ch["name"]] = [b[0] for b in ch["bones"]]
    legs = {}
    for leg in spec.get("legs", []):
        lid = leg["id"]
        legs[lid] = {"hip": "hip_" + lid, "knee": "knee_" + lid, "ankle": "ankle_" + lid, "toe": "toe_" + lid,
                     "ik": "ik_" + lid, "toe_at": gd(leg["toe"]), "hip_at": gd(leg["hip"])}
    socks = {}
    for name, (bone, pos) in spec.get("sockets", {}).items():
        socks[name] = {"bone": bone, "at": gd(pos)}
    row = {
        "id": spec["id"],
        "version": int(spec.get("version", 1)),
        "rigkit_version": RIGKIT_VERSION,
        "footprint_hexes": int(spec.get("footprint_hexes", 2)),
        "length": round(max(ys) - min(ys), 3),
        "height": round(max(zs), 3),
        "width": round(max(xs) - min(xs), 3),
        "aabb": {"min": aabb_min, "max": aabb_max},
        "tris": tris,
        "verts": nverts,
        "meshes": ["body_" + r for r, _, _ in [(b.name[5:], None, None) for b in bodies]],
        "bones": [{"name": b.name, "parent": b.parent or "", "head": gd(b.head), "tail": gd(b.tail)} for b in bones],
        "chains": chains,
        "jaw": spec.get("jaw", {}).get("bone", ""),
        "frill": list(spec.get("frill", {}).get("bones", [])),
        "legs": legs,
        "sockets": socks,
        "roles": {r: [round(c, 3) for c in roles[r]] for r in roles},
    }
    return row


def write_manifest(path, rows, generator):
    doc = {
        "version": RIGKIT_VERSION,
        "generator": generator,
        "space": "Godot model-local: origin at the ground under the hips, +Y up, +Z the monster's forward, "
                 "+X its left. Bones carry head/tail at rest; sockets are Node3D under BoneAttachment3D.",
        "monsters": {r["id"]: r for r in rows},
    }
    existing = {}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                existing = json.load(fh).get("monsters", {})
        except Exception:
            existing = {}
    for k, v in existing.items():
        doc["monsters"].setdefault(k, v)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1, sort_keys=False)
        fh.write("\n")
    return path
