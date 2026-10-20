"""Hexhunt base player rig: a low-poly hooded hunter, built from nothing.

    blender -b --factory-startup --python tools/blender/build_base_rig.py

Writes (never hand-edit these; change this script and rebuild):
    art/characters/base_rig.glb     body (one mesh object per colour role, H303)
                                    + deform bones + socket empties; no baked clips
                                    (HHPlayerBody poses the skeleton at run time)
    art/characters/rig.json         bones, sockets, roles, height, tris (Godot coordinates)
    art/characters/blend/base_rig.blend  reference only (.gdignore keeps Godot off it)

Ported from Black | White's game/tools/blender/build_base_rig.py (H4): the same
20 deform bones and six sockets (root hips spine chest neck head, shoulder /
upper_arm / forearm / hand _l/_r, thigh / shin / foot _l/_r; socket_weapon_r,
socket_offhand_l, socket_back, socket_chest, socket_hair, socket_hat), the
same 2.20 m height, the same A-pose rest. The stick figure is replaced by a
hunter: leather jerkin, bracers and boots, a deep-green hooded mantle, bare
hands and face. Vertex colour per role; faceted low-poly like Lane E's monsters.

Coordinates are Blender's (Z up, character faces -Y, left +X). The glTF
exporter's +Y-up conversion maps that to Godot's Y up, facing +Z, left +X.
Everything is deterministic: no randomness, fixed generation order.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "characters", "base_rig.glb")
JSON_OUT = os.path.join(ROOT, "art", "characters", "rig.json")
BLEND_OUT = os.path.join(ROOT, "art", "characters", "blend", "base_rig.blend")

RIG_VERSION = 1  # bump when bone names, socket names or proportions change


def V(x, y, z):
    return Vector((x, y, z))


def gd(p):
    """Blender (x, y, z) -> Godot (x, z, -y), rounded."""
    return [round(float(p[0]), 4), round(float(p[2]), 4), round(-float(p[1]), 4)]


# ----------------------------------------------------------- proportions
# About 6.3 heads tall: a stylised adult, not a stick figure. Wide shoulders,
# narrow waist, long legs (42% of height) so the 1.73 m hex stride reads.
HEIGHT = 2.20
HEAD_C = V(0, 0.005, 2.00)
HEAD_R = V(0.145, 0.16, 0.175)
PELVIS_Z = 1.00
SPINE_Z = 1.18
CHEST_Z = 1.42
NECK_Z = 1.72
HEAD_Z = 1.84
SHOULDER_Z = 1.66
SHOULDER_X = 0.21
ARM_ABDUCT = 28.0
UPPER_ARM = 0.33
FOREARM = 0.30
HAND = 0.10

R_ARM = (0.064, 0.054, 0.046)      # shoulder, elbow, wrist
R_LEG = (0.095, 0.072, 0.054)      # hip, knee, ankle
RADIAL = 8

FORWARD = V(0, -1, 0)
UP = V(0, 0, 1)

# palette: sRGB as displayed (written through color_srgb, see MeshBuilder)
ROLES = {
    "skin": (0.86, 0.68, 0.55),
    "leather": (0.46, 0.30, 0.17),
    "cloak": (0.19, 0.36, 0.24),
    "boots": (0.23, 0.15, 0.10),
    "straps": (0.15, 0.11, 0.09),
}


def arm_points(s):
    """s = +1 left, -1 right. Elbow a touch back, wrist a touch forward: a
    readable bend direction."""
    a = math.radians(ARM_ABDUCT)
    sh = V(s * SHOULDER_X, 0, SHOULDER_Z)
    d1 = V(s * math.sin(a), 0.04, -math.cos(a)).normalized()
    el = sh + d1 * UPPER_ARM
    d2 = V(s * math.sin(a) * 0.8, -0.10, -math.cos(a)).normalized()
    wr = el + d2 * FOREARM
    tip = wr + d2 * HAND
    return sh, el, wr, tip


def leg_points(s):
    hip = V(s * 0.11, 0, PELVIS_Z)
    knee = V(s * 0.12, -0.015, 0.54)
    ankle = V(s * 0.125, 0.0, 0.09)
    toe = V(s * 0.125, -0.17, 0.03)
    return hip, knee, ankle, toe


SIDES = (("l", 1), ("r", -1))


# ----------------------------------------------------------------- bones
# (name, head, tail, parent, connected, roll_z_hint)
# Every bone's local Z points to the character's front (up for the foot), as
# in Black | White. HHPlayerBody rotates about MODEL axes from the global rest
# basis, so the roll only matters for tools that read the bones directly.
def bone_table():
    t = [
        ("root", V(0, 0, 0), V(0, 0, 0.25), None, False, FORWARD),
        ("hips", V(0, 0, PELVIS_Z), V(0, 0, SPINE_Z), "root", False, FORWARD),
        ("spine", V(0, 0, SPINE_Z), V(0, 0, CHEST_Z), "hips", True, FORWARD),
        ("chest", V(0, 0, CHEST_Z), V(0, 0, NECK_Z), "spine", True, FORWARD),
        ("neck", V(0, 0, NECK_Z), V(0, 0, HEAD_Z), "chest", True, FORWARD),
        ("head", V(0, 0, HEAD_Z), V(0, 0, HEIGHT), "neck", True, FORWARD),
    ]
    for side, s in SIDES:
        sh, el, wr, tip = arm_points(s)
        hip, knee, ankle, toe = leg_points(s)
        t += [
            ("shoulder_" + side, V(s * 0.04, 0, SHOULDER_Z), sh, "chest", False, FORWARD),
            ("upper_arm_" + side, sh, el, "shoulder_" + side, True, FORWARD),
            ("forearm_" + side, el, wr, "upper_arm_" + side, True, FORWARD),
            ("hand_" + side, wr, tip, "forearm_" + side, True, FORWARD),
            ("thigh_" + side, hip, knee, "hips", False, FORWARD),
            ("shin_" + side, knee, ankle, "thigh_" + side, True, FORWARD),
            ("foot_" + side, ankle, toe, "shin_" + side, True, UP),
        ]
    return t


BONES = [b[0] for b in bone_table()]


# socket empties: name -> (parent bone, Blender world position)
def socket_table():
    _, _, wr_r, tip_r = arm_points(-1)
    _, _, wr_l, tip_l = arm_points(1)
    return [
        ("socket_hair", "head", HEAD_C.copy()),
        ("socket_hat", "head", V(0, 0, HEIGHT)),
        ("socket_weapon_r", "hand_r", wr_r + (tip_r - wr_r).normalized() * 0.05),
        ("socket_offhand_l", "hand_l", wr_l + (tip_l - wr_l).normalized() * 0.05),
        ("socket_chest", "chest", V(0, -0.12, 1.50)),
        ("socket_back", "chest", V(0, 0.14, 1.50)),
    ]


# -------------------------------------------------------- mesh builders
class MeshBuilder:
    """Collects verts / faces / weights / role / colour and emits ONE Blender
    mesh per role (H303: the 5.2 glTF exporter mangles a colour attribute
    shared across materials)."""

    def __init__(self):
        self.verts = []
        self.weights = []
        self.faces = []     # (indices, role)
        self.colors = []

    def add_vert(self, co, w, role):
        self.verts.append(co.copy())
        tot = sum(w.values())
        self.weights.append({k: v / tot for k, v in w.items() if v > 1e-6})
        c = ROLES[role]
        self.colors.append((c[0], c[1], c[2], 1.0))
        return len(self.verts) - 1

    def ellipsoid(self, center, radii, w, role, seg=10, rings=6, keep=None):
        """UV ellipsoid, poles along Z. `keep(p_local)` drops faces whose
        centre fails it (the hood's face opening)."""
        top = self.add_vert(center + V(0, 0, radii.z), w, role)
        lat = []
        for i in range(1, rings):
            th = math.pi * i / rings
            row = []
            for j in range(seg):
                ph = 2 * math.pi * j / seg
                p = V(radii.x * math.sin(th) * math.cos(ph), radii.y * math.sin(th) * math.sin(ph), radii.z * math.cos(th))
                row.append(self.add_vert(center + p, w, role))
            lat.append(row)
        bot = self.add_vert(center + V(0, 0, -radii.z), w, role)

        def ok(idx):
            if keep is None:
                return True
            c = Vector((0, 0, 0))
            for i in idx:
                c += self.verts[i] - center
            return keep(c / len(idx))

        for j in range(seg):
            k = (j + 1) % seg
            f = (top, lat[0][j], lat[0][k])
            if ok(f):
                self.faces.append((f, role))
            f = (bot, lat[-1][k], lat[-1][j])
            if ok(f):
                self.faces.append((f, role))
        for i in range(len(lat) - 1):
            for j in range(seg):
                k = (j + 1) % seg
                f = (lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k])
                if ok(f):
                    self.faces.append((f, role))

    def cowl(self, rings, peak, peak_w, role, sides=12, keep=None):
        """A hood: stacked elliptical rings (z, cy, rx, ry, weights) each
        centred at (0, cy, z), closed at the top by a `peak` vertex, open at
        the bottom. `keep(p)` (p in model space) drops faces whose centroid
        fails it: the face opening."""
        loops = []
        for z, cy, rx, ry, w in rings:
            row = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                row.append(self.add_vert(V(rx * math.cos(a), cy + ry * math.sin(a), z), w, role))
            loops.append(row)
        top = self.add_vert(peak, peak_w, role)

        def ok(idx):
            if keep is None:
                return True
            c = Vector((0, 0, 0))
            for i in idx:
                c += self.verts[i]
            return keep(c / len(idx))

        for i in range(len(loops) - 1):
            for k in range(sides):
                k2 = (k + 1) % sides
                f = (loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k])
                if ok(f):
                    self.faces.append((f, role))
        for k in range(sides):
            k2 = (k + 1) % sides
            f = (loops[-1][k], loops[-1][k2], top)
            if ok(f):
                self.faces.append((f, role))

    def tube(self, rings, role, radial=RADIAL, cap_start=True, cap_end=True):
        """rings: list of (center, tangent, radius, weights). Parallel
        transport keeps the ring frames from twisting."""
        n = None
        loops = []
        for c, t, r, w in rings:
            if n is None:
                ref = FORWARD if abs(t.dot(FORWARD)) < 0.9 else V(1, 0, 0)
                n = (ref - t * ref.dot(t)).normalized()
            else:
                n = (n - t * n.dot(t)).normalized()
            b = t.cross(n)
            row = []
            for k in range(radial):
                a = 2 * math.pi * k / radial
                row.append(self.add_vert(c + (n * math.cos(a) + b * math.sin(a)) * r, w, role))
            loops.append(row)
        for i in range(len(loops) - 1):
            for k in range(radial):
                k2 = (k + 1) % radial
                self.faces.append(((loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k]), role))
        caps = []
        if cap_start:
            caps.append((loops[0], rings[0]))
        if cap_end:
            caps.append((loops[-1], rings[-1]))
        for row, (c, t, r, w) in caps:
            ctr = self.add_vert(c, w, role)
            for k in range(radial):
                self.faces.append(((ctr, row[(k + 1) % radial], row[k]), role))

    def loft(self, rings, role, sides=8, half=None, cap_start=False, cap_end=False, a0=0.0):
        """Stacked elliptical rings in the XY plane: rings = (z, rx, ry, weights).
        `half` = "back" keeps only the +Y half (an open sheet), angles from
        a0. A full loft can be capped."""
        loops = []
        for z, rx, ry, w in rings:
            row = []
            if half == "back":
                for k in range(sides + 1):
                    a = math.pi * k / sides
                    row.append(self.add_vert(V(rx * math.cos(a), ry * math.sin(a), z), w, role))
            else:
                for k in range(sides):
                    a = a0 + 2 * math.pi * k / sides
                    row.append(self.add_vert(V(rx * math.cos(a), ry * math.sin(a), z), w, role))
            loops.append(row)
        wrap = half is None
        m = len(loops[0])
        for i in range(len(loops) - 1):
            for k in range(m - (0 if wrap else 1)):
                k2 = (k + 1) % m
                self.faces.append(((loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k]), role))
        if wrap:
            for row, (z, rx, ry, w), do in ((loops[0], rings[0], cap_start), (loops[-1], rings[-1], cap_end)):
                if not do:
                    continue
                ctr = self.add_vert(V(0, 0, z), w, role)
                for k in range(m):
                    self.faces.append(((ctr, row[(k + 1) % m], row[k]), role))

    def box(self, center, half, w, role):
        x, y, z = half.x, half.y, half.z
        c = [self.add_vert(center + V(sx * x, sy * y, sz * z), w, role)
             for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        # index: sx*4 + sy*2 + sz  (0..7)
        quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        for q in quads:
            self.faces.append((tuple(c[i] for i in q), role))

    def build(self, name, materials):
        out = []
        for role, mat in materials:
            faces = [f for f, r in self.faces if r == role]
            if not faces:
                continue
            remap, verts, weights, colors, new_faces = {}, [], [], [], []
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
                p.use_smooth = False
            col = me.color_attributes.new("Color", 'BYTE_COLOR', 'POINT')
            for i, c in enumerate(colors):
                col.data[i].color_srgb = c
            me.color_attributes.active_color = col
            me.color_attributes.render_color_index = 0
            me.update()
            out.append((role, me, weights))
        return out


def chain_rings(points, radii, bones, start_bone=None, end_bone=None, blend=None, loops=5):
    """Rings along a joint chain: points[i] -> points[i+1] belongs to bones[i].
    Around each pivot the weights blend over +-blend[i] (linear)."""
    nseg = len(bones)
    dirs = [(points[i + 1] - points[i]).normalized() for i in range(nseg)]
    lens = [(points[i + 1] - points[i]).length for i in range(nseg)]
    out = []
    for i in range(nseg):
        L = lens[i]
        b0, b1 = blend[i], blend[i + 1]
        ds = {0.0}
        if loops >= 5:
            ds |= {b0 * 0.5, b0, L - b1, L - b1 * 0.5}
        else:
            ds |= {b0, L - b1}
        if i == nseg - 1:
            ds.add(L)
        ds = sorted(d for d in ds if 0 <= d <= L + 1e-9)
        clean = []
        for d in ds:
            if not clean or d - clean[-1] > 0.006:
                clean.append(d)
        for d in clean:
            if d >= L - 1e-9 and i < nseg - 1:
                continue
            c = points[i] + dirs[i] * d
            r = radii[i] + (radii[i + 1] - radii[i]) * (d / L)
            t = dirs[i]
            if d < 1e-9 and i > 0:
                t = (dirs[i - 1] + dirs[i]).normalized()
            w = {bones[i]: 1.0}
            prev = bones[i - 1] if i > 0 else start_bone
            nxt = bones[i + 1] if i < nseg - 1 else end_bone
            if prev and b0 > 0 and d < b0:
                wp = 0.5 * (1 - d / b0)
                w = {bones[i]: 1 - wp, prev: wp}
            if nxt and b1 > 0 and L - d < b1:
                wn = 0.5 * (1 - (L - d) / b1)
                w = dict(w)
                w[bones[i]] = w.get(bones[i], 0) - wn
                w[nxt] = w.get(nxt, 0) + wn
            out.append((c, t, r, w))
    return out


def ss(e0, e1, x):
    x = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return x * x * (3 - 2 * x)


def torso_w(z):
    """Spine-chain weights by height, smooth over +-0.07 around each pivot."""
    w = {}
    chain = [("hips", -1, SPINE_Z), ("spine", SPINE_Z, CHEST_Z), ("chest", CHEST_Z, NECK_Z), ("neck", NECK_Z, 9)]
    for name, z0, z1 in chain:
        lo = ss(z0 - 0.07, z0 + 0.07, z) if z0 > 0 else 1
        hi = 1 - ss(z1 - 0.07, z1 + 0.07, z) if z1 < 9 else 1
        if lo * hi > 1e-4:
            w[name] = lo * hi
    return w or {"hips": 1}


# ------------------------------------------------------------- the body
def build_body():
    mb = MeshBuilder()

    # torso: a jerkin lofted on elliptical rings, pelvis to the collar
    torso = [
        (0.93, 0.165, 0.115), (1.02, 0.175, 0.125), (1.18, 0.150, 0.110), (1.30, 0.165, 0.125),
        (1.42, 0.195, 0.140), (1.56, 0.215, 0.145), (1.66, 0.205, 0.135), (1.74, 0.110, 0.095),
    ]
    mb.loft([(z, rx, ry, torso_w(z)) for z, rx, ry in torso], "leather", sides=10, cap_start=True, cap_end=True, a0=math.pi / 10)
    # belt and chest strap
    mb.loft([(1.11, 0.178, 0.128, {"spine": 0.6, "hips": 0.4}), (1.16, 0.172, 0.124, {"spine": 0.8, "hips": 0.2})],
            "straps", sides=10, cap_start=False, cap_end=False, a0=math.pi / 10)
    strap = [V(-0.13, -0.15, 1.63), V(-0.05, -0.155, 1.45), V(0.06, -0.14, 1.28), V(0.13, -0.125, 1.14)]
    mb.tube([(p, (strap[min(i + 1, 3)] - strap[max(i - 1, 0)]).normalized(), 0.022, torso_w(p.z)) for i, p in enumerate(strap)],
            "straps", radial=6)
    # neck and head
    mb.tube([(V(0, 0, 1.70), UP, 0.058, {"chest": 0.3, "neck": 0.7}), (V(0, 0, 1.80), UP, 0.055, {"neck": 1}),
             (V(0, 0, 1.90), UP, 0.055, {"neck": 0.3, "head": 0.7})], "skin", radial=8)
    mb.ellipsoid(HEAD_C, HEAD_R, {"head": 1}, "skin", seg=10, rings=6)
    # hood (L-13): a cowl lofted from the shoulders to a peak, each ring
    # pushed forward as it climbs so the crown overhangs the brow; the face
    # opening is cut only below the brow and between the cheeks, so from the
    # front it reads as a hood with a shaded face, not a ring round the head.
    # Rings: (z, cy forward shift (-y is forward), rx, ry, weights).
    cowl = [
        (1.63, 0.01, 0.30, 0.23, {"chest": 0.7, "neck": 0.3}),
        (1.75, 0.00, 0.255, 0.205, {"neck": 0.8, "chest": 0.2}),
        (1.87, -0.01, 0.22, 0.21, {"neck": 0.4, "head": 0.6}),
        (2.00, -0.02, 0.212, 0.222, {"head": 1}),
        (2.10, -0.03, 0.205, 0.228, {"head": 1}),
        (2.19, -0.03, 0.155, 0.185, {"head": 1}),
        (2.255, -0.015, 0.075, 0.095, {"head": 1}),
    ]
    # opening: between the cheeks below the brow, then the whole front below the chin
    mb.cowl(cowl, V(0, 0.05, 2.30), {"head": 1}, "cloak", sides=12,
            keep=lambda p: not ((p.y < -0.085 and p.z < 2.085 and abs(p.x) < 0.125)
                                or (p.y < -0.03 and p.z < 1.87)))
    # mantle: a sheet down the back from the collar to the hips, hanging free
    mantle = [(1.72, 0.20, 0.13), (1.66, 0.28, 0.17), (1.58, 0.31, 0.20), (1.46, 0.31, 0.22),
              (1.30, 0.30, 0.235), (1.12, 0.285, 0.25), (0.98, 0.27, 0.255)]
    mb.loft([(z, rx, ry, torso_w(min(z, 1.68))) for z, rx, ry in mantle], "cloak", sides=8, half="back")

    for side, s in SIDES:
        sh, el, wr, tip = arm_points(s)
        hip, knee, ankle, toe = leg_points(s)
        ua, fa, hd = "upper_arm_" + side, "forearm_" + side, "hand_" + side
        th, sn, ft = "thigh_" + side, "shin_" + side, "foot_" + side
        # arm: leather sleeve to the elbow, a bracer to the wrist, a bare hand
        ra = R_ARM
        mb.ellipsoid(sh, V(1, 1, 1) * ra[0] * 1.18, {ua: 0.7, "shoulder_" + side: 0.3}, "leather", seg=8, rings=4)
        mb.tube(chain_rings([sh, el], (ra[0], ra[1]), [ua], start_bone="shoulder_" + side, end_bone=fa,
                            blend=[ra[0] * 0.8, ra[1] * 0.9]), "leather")
        mb.ellipsoid(el, V(1, 1, 1) * ra[1] * 1.1, {fa: 1}, "leather", seg=8, rings=4)
        mb.tube(chain_rings([el, wr], (ra[1] * 1.08, ra[2] * 1.15), [fa], start_bone=ua, end_bone=hd,
                            blend=[ra[1] * 0.9, ra[2] * 0.6]), "boots")
        hand_c = wr + (tip - wr).normalized() * 0.045
        hd_dir = (tip - wr).normalized()
        mb.tube([(wr + hd_dir * 0.0, hd_dir, 0.044, {hd: 1}), (wr + hd_dir * 0.05, hd_dir, 0.058, {hd: 1}),
                 (wr + hd_dir * 0.10, hd_dir, 0.052, {hd: 1}), (wr + hd_dir * 0.13, hd_dir, 0.030, {hd: 1})], "skin", radial=7)
        # leg: leather thigh, boot shin, boot foot
        rl = R_LEG
        mb.tube(chain_rings([hip, knee], (rl[0], rl[1]), [th], start_bone="hips", end_bone=sn,
                            blend=[rl[0] * 0.8, rl[1] * 0.9]), "leather")
        mb.ellipsoid(knee, V(1, 1, 1) * rl[1] * 1.08, {sn: 1}, "boots", seg=8, rings=4)
        mb.tube(chain_rings([knee, ankle], (rl[1] * 1.05, rl[2] * 1.2), [sn], start_bone=th, end_bone=ft,
                            blend=[rl[1] * 0.9, rl[2] * 0.5]), "boots")
        foot_c = V(ankle.x, -0.075, 0.048)
        mb.box(foot_c, V(0.062, 0.135, 0.048), {ft: 1}, "boots")
    return mb


# ------------------------------------------------------------ materials
def make_material(role, rgb):
    m = bpy.data.materials.new(role)
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


# ------------------------------------------------------------------ rig
def build_armature():
    arm = bpy.data.armatures.new("base_rig_armature")
    arm.display_type = 'OCTAHEDRAL'
    obj = bpy.data.objects.new("base_rig", arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for name, head, tail, parent, conn, zhint in bone_table():
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.align_roll(zhint)
        b.use_deform = True
        if parent:
            b.parent = eb[parent]
            b.use_connect = conn
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in arm.bones:
        b.inherit_scale = 'FULL'
    return obj


def bind(mesh_obj, rig, weights):
    for name in BONES:
        mesh_obj.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        for bone, val in w.items():
            mesh_obj.vertex_groups[bone].add([i], val, 'REPLACE')
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    mod.use_deform_preserve_volume = False   # Godot is linear-blend; match it
    mesh_obj.parent = rig


def make_sockets(rig):
    out = []
    vl = bpy.context.view_layer
    for name, bone, pos in socket_table():
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = 'ARROWS'
        e.empty_display_size = 0.08
        bpy.context.scene.collection.objects.link(e)
        e.parent = rig
        e.parent_type = 'BONE'
        e.parent_bone = bone
        vl.update()
        e.matrix_world = Matrix.Translation(pos)   # world-aligned at rest
        out.append(e)
    vl.update()
    return out


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


# ----------------------------------------------------------------- main
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scn = bpy.context.scene
    scn.unit_settings.system = 'METRIC'

    materials = [(r, make_material(r, ROLES[r])) for r in ROLES]
    rig = build_armature()
    mb = build_body()
    bodies = []
    for role, me, weights in mb.build("body", materials):
        body = bpy.data.objects.new("body_" + role, me)
        scn.collection.objects.link(body)
        bind(body, rig, weights)
        bodies.append(body)
    sockets = make_sockets(rig)
    rig["rig_version"] = RIG_VERSION
    bpy.context.view_layer.update()

    tris = {b.name[5:]: sum(len(p.vertices) - 2 for p in b.data.polygons) for b in bodies}
    nverts = sum(len(b.data.vertices) for b in bodies)
    xs = [v.co.x for b in bodies for v in b.data.vertices]
    ys = [v.co.y for b in bodies for v in b.data.vertices]
    zs = [v.co.z for b in bodies for v in b.data.vertices]

    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    gdignore = os.path.join(os.path.dirname(BLEND_OUT), ".gdignore")
    if not os.path.exists(gdignore):
        open(gdignore, "w").close()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=False)

    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in [rig] + bodies + sockets:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUT, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
        export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_skins=True, export_def_bones=True, export_leaf_bone=False, export_influence_nb=4,
        export_animations=False, export_morph=False, export_cameras=False, export_lights=False,
        export_extras=False, export_rest_position_armature=True,
    )
    stub = GLB_OUT + ".import"
    if not os.path.exists(stub):
        with open(stub, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(IMPORT_STUB)

    row = {
        "version": RIG_VERSION,
        "generator": "tools/blender/build_base_rig.py",
        "space": "Godot model-local: origin on the ground between the feet, +Y up, +Z the character's forward, "
                 "+X its left. Rest is an A-pose. Sockets are Node3D under BoneAttachment3D, world-aligned at rest "
                 "(+Y up, +Z forward): a weapon with identity mount points +Y up out of the fist.",
        "height": HEIGHT,
        "head_centre": gd(HEAD_C),
        "aabb": {"min": gd((min(xs), max(ys), min(zs))), "max": gd((max(xs), min(ys), max(zs)))},
        "tris": sum(tris.values()),
        "tris_by_role": tris,
        "verts": nverts,
        "meshes": ["body_" + r for r in tris],
        "roles": {r: [round(c, 3) for c in ROLES[r]] for r in ROLES},
        "bones": [{"name": n, "parent": p or "", "head": gd(h), "tail": gd(t)} for n, h, t, p, _, _ in bone_table()],
        "sockets": {n: {"bone": b, "at": gd(p)} for n, b, p in socket_table()},
        "limbs": {
            "arm_l": ["upper_arm_l", "forearm_l", "hand_l"], "arm_r": ["upper_arm_r", "forearm_r", "hand_r"],
            "leg_l": ["thigh_l", "shin_l", "foot_l"], "leg_r": ["thigh_r", "shin_r", "foot_r"],
            "spine": ["hips", "spine", "chest", "neck", "head"],
        },
    }
    with open(JSON_OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(row, fh, indent=1)
        fh.write("\n")
    print("GLB", GLB_OUT)
    print("JSON", JSON_OUT, "tris", row["tris"], "verts", nverts)


main()
