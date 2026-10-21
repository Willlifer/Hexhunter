"""Hexhunt base player rig: the huntress, built from nothing (H80).

    blender -b --factory-startup --python tools/blender/build_base_rig.py

Writes (never hand-edit these; change this script and rebuild):
    art/characters/base_rig.glb     body (one mesh object per colour role, H303)
                                    + deform bones + socket empties; no baked clips
                                    (HHPlayerBody poses the skeleton at run time)
    art/characters/rig.json         bones, sockets, roles, height, tris (Godot coordinates)
    art/characters/blend/base_rig.blend  reference only (git-ignored, .gdignore)

Rig contract (unchanged since Black | White, H4): the same 20 deform bones and
six sockets (root hips spine chest neck head, shoulder / upper_arm / forearm /
hand _l/_r, thigh / shin / foot _l/_r; socket_weapon_r, socket_offhand_l,
socket_back, socket_chest, socket_hair, socket_hat), 2.20 m tall, A-pose rest.

Rig v2 (Lane Y, H80-H82): an 8-head heroic female figure after the author's
reference (design/art/hunter_ref/reference.jpg): long legs (hip joint at
1.15 m, crotch at 1.06), narrow waist, wide hips, full thighs, athletic
shoulders. The body is smooth: torso and both legs are ONE welded loft (the
leg tops share the torso's crotch ring and a crotch seam), arms and head are
lofts tucked into it, every vertex carries a smooth normal computed over the
welded part (custom split normals) so the colour-role split leaves no seam.
Outfit on top as offset shells of the same surfaces: a banded glossy suit
(role `suit`, tinted per player at run time), a teal-steel bust plate with an
original hex crest (no emblem from the reference), a spiked pauldron on the
left shoulder, bracer, wrapped right forearm with tattoo bands, strap bands,
spiked knee-high greaves, a half-cape at the hips, a headband with a hex
crest, and long hair down the back.

Coordinates are Blender's (Z up, character faces -Y, left +X). The glTF
exporter's +Y-up conversion maps that to Godot's Y up, facing +Z, left +X.
Deterministic: no randomness, fixed generation order.
"""

import json
import math
import os

import bmesh  # noqa: F401  (kept for parity with the other builders)
import bpy
from mathutils import Matrix, Vector, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GLB_OUT = os.path.join(ROOT, "art", "characters", "base_rig.glb")
JSON_OUT = os.path.join(ROOT, "art", "characters", "rig.json")
BLEND_OUT = os.path.join(ROOT, "art", "characters", "blend", "base_rig.blend")

RIG_VERSION = 2  # bump when bone names, socket names or proportions change


def V(x, y, z):
    return Vector((x, y, z))


def gd(p):
    """Blender (x, y, z) -> Godot (x, z, -y), rounded."""
    return [round(float(p[0]), 4), round(float(p[2]), 4), round(-float(p[1]), 4)]


def lerp(a, b, t):
    return a + (b - a) * t


def ss(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    x = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return x * x * (3 - 2 * x)


def sgnpow(v, e):
    return math.copysign(abs(v) ** e, v)


def gauss(x, mu, sig):
    return math.exp(-((x - mu) / sig) ** 2)


def angdiff(a, b):
    """a - b wrapped to (-180, 180] degrees."""
    d = (a - b) % 360.0
    return d - 360.0 if d > 180.0 else d


# ----------------------------------------------------------- proportions
# 8 heads tall (head 0.275 m). Shoulder joints at 1.795, waist 1.35, hip
# joints 1.15, crotch 1.06, knees 0.605, ankles 0.09 (HHClipsShared.ANKLE_Y).
HEIGHT = 2.20
HEAD_C = V(0, 0.0, 2.07)
PELVIS_Z = 1.20
SPINE_Z = 1.37
CHEST_Z = 1.52
NECK_Z = 1.84
HEAD_Z = 1.95
SHOULDER_Z = 1.795
SHOULDER_X = 0.20
ARM_ABDUCT = 28.0
UPPER_ARM = 0.34
FOREARM = 0.29
HAND = 0.10
HIP_X = 0.10
HIP_Z = 1.19
CROTCH_Z = 1.10

FORWARD = V(0, -1, 0)
UP = V(0, 0, 1)

# palette: sRGB as displayed (written through color_srgb). `suit` is white
# here: HHPlayerBody multiplies it by the player's suit colour (H83).
ROLES = {
    "skin": (0.93, 0.72, 0.58),
    "suit": (1.0, 1.0, 1.0),
    "plate": (0.50, 0.70, 0.70),
    "armor": (0.20, 0.22, 0.27),
    "leather": (0.11, 0.11, 0.14),
    "cape": (1.0, 1.0, 1.0),        # tinted at run time: navy toward the suit colour (H83)
    "hair": (0.07, 0.065, 0.09),
    "wrap": (0.58, 0.54, 0.36),
}
SUIT_STRIPE = (1.0, 0.86)        # suit rings alternate these brightnesses: the wrapped-band read
LIP = (0.72, 0.16, 0.16)
EYE = (0.10, 0.08, 0.10)
BROW = (0.10, 0.08, 0.09)


def arm_points(s):
    """s = +1 left, -1 right. Elbow a touch back, wrist a touch forward."""
    a = math.radians(ARM_ABDUCT)
    sh = V(s * SHOULDER_X, 0, SHOULDER_Z)
    d1 = V(s * math.sin(a), 0.04, -math.cos(a)).normalized()
    el = sh + d1 * UPPER_ARM
    d2 = V(s * math.sin(a) * 0.8, -0.10, -math.cos(a)).normalized()
    wr = el + d2 * FOREARM
    tip = wr + d2 * HAND
    return sh, el, wr, tip


def leg_points(s):
    hip = V(s * HIP_X, 0, HIP_Z)
    knee = V(s * 0.088, -0.015, 0.63)
    ankle = V(s * 0.093, 0.0, 0.09)
    toe = V(s * 0.096, -0.17, 0.025)
    return hip, knee, ankle, toe


SIDES = (("l", 1), ("r", -1))


# ----------------------------------------------------------------- bones
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


def socket_table():
    _, _, wr_r, tip_r = arm_points(-1)
    _, _, wr_l, tip_l = arm_points(1)
    return [
        ("socket_hair", "head", HEAD_C.copy()),
        ("socket_hat", "head", V(0, 0, HEIGHT)),
        ("socket_weapon_r", "hand_r", wr_r + (tip_r - wr_r).normalized() * 0.05),
        ("socket_offhand_l", "hand_l", wr_l + (tip_l - wr_l).normalized() * 0.05),
        ("socket_chest", "chest", V(0, -0.13, 1.56)),
        ("socket_back", "chest", V(0, 0.16, 1.56)),
    ]


# ------------------------------------------------------------- weights
def torso_w(z):
    """Spine-chain weights by height, smooth over +-0.06 around each pivot."""
    w = {}
    chain = [("hips", -1, SPINE_Z), ("spine", SPINE_Z, CHEST_Z), ("chest", CHEST_Z, NECK_Z),
             ("neck", NECK_Z, HEAD_Z), ("head", HEAD_Z, 9)]
    for name, z0, z1 in chain:
        lo = ss(z0 - 0.06, z0 + 0.06, z) if z0 > 0 else 1
        hi = 1 - ss(z1 - 0.06, z1 + 0.06, z) if z1 < 9 else 1
        if lo * hi > 1e-4:
            w[name] = lo * hi
    return w or {"hips": 1}


def mix(*pairs):
    """mix((w_dict, k), ...) -> sum of k * w, normalised later."""
    out = {}
    for w, k in pairs:
        for b, v in w.items():
            out[b] = out.get(b, 0.0) + v * k
    return out


def chain_w(d, joints, bones, blends, start=None, start_blend=0.0, end=None, end_blend=0.0):
    """Weights along a joint chain: d (m from the first joint) in segment i
    belongs to bones[i]; around each inner joint the two bones cross-fade
    over +-blend. `start` / `end` bones fade in before the first joint /
    after the last."""
    w = {}
    n = len(bones)
    for i, b in enumerate(bones):
        lo = 1.0 if i == 0 else ss(joints[i] - blends[i], joints[i] + blends[i], d)
        hi = 1.0 if i == n - 1 else 1.0 - ss(joints[i + 1] - blends[i + 1], joints[i + 1] + blends[i + 1], d)
        v = lo * hi
        if v > 1e-4:
            w[b] = v
    if start and start_blend > 0:
        k = 0.5 * (1.0 - ss(joints[0] - start_blend, joints[0] + start_blend, d))
        if k > 1e-4:
            w = mix((w, 1 - k), ({start: 1}, k))
    if end and end_blend > 0:
        k = 0.5 * ss(joints[-1] - end_blend, joints[-1] + end_blend, d)
        if k > 1e-4:
            w = mix((w, 1 - k), ({end: 1}, k))
    return w


# -------------------------------------------------------- mesh builder
def newell(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


class MeshBuilder:
    """Verts / faces / weights / role / colour; emits ONE Blender mesh per
    role (H303). Every face is oriented on creation: its normal points away
    from the `inside` point given with it. Smooth normals are averaged over
    shared vertices (a welded part) and written as custom normals, so a role
    split across a welded surface shades without a seam."""

    def __init__(self):
        self.verts = []
        self.weights = []
        self.colors = []
        self.groups = []
        self.faces = []     # (indices, role)
        self.flat = set()   # vertex ids that take their face normal (hard parts)

    def add(self, co, w, role, col=None, group=""):
        self.verts.append(co.copy())
        self.weights.append(dict(w))
        c = col if col is not None else ROLES[role]
        self.colors.append((c[0], c[1], c[2], 1.0))
        self.groups.append(group)
        return len(self.verts) - 1

    def face(self, idx, role, inside):
        pts = [self.verts[i] for i in idx]
        n = newell(pts)
        if n.length < 1e-12:
            return
        c = sum(pts, Vector((0, 0, 0))) / len(pts)
        if n.dot(c - inside) < 0:
            idx = tuple(reversed(idx))
        self.faces.append((tuple(idx), role))

    def face_out(self, idx, role, outward):
        """Orient so the normal agrees with `outward` (a direction)."""
        pts = [self.verts[i] for i in idx]
        n = newell(pts)
        if n.length < 1e-12:
            return
        if n.dot(outward) < 0:
            idx = tuple(reversed(idx))
        self.faces.append((tuple(idx), role))

    # -- grids
    def grid(self, rows, role_of, inside_of, closed=True):
        """rows: list of lists of vertex ids (same length). Quads between
        consecutive rows; `closed` wraps each row. role_of(i, k) and
        inside_of(i, k) per quad (i = row, k = column)."""
        for i in range(len(rows) - 1):
            a, b = rows[i], rows[i + 1]
            m = len(a)
            for k in range(m if closed else m - 1):
                k2 = (k + 1) % m
                self.face((a[k], a[k2], b[k2], b[k]), role_of(i, k), inside_of(i, k))

    def fan(self, row, centre_id, role, inside):
        m = len(row)
        for k in range(m):
            self.face((centre_id, row[k], row[(k + 1) % m]), role, inside)

    def ellipsoid(self, center, radii, w_of, role, seg=12, rings=8, keep=None, axes=None, col=None, group="", flat=False):
        v0 = len(self.verts)
        self._ellipsoid(center, radii, w_of, role, seg, rings, keep, axes, col, group)
        if flat:
            self.flat.update(range(v0, len(self.verts)))

    def _ellipsoid(self, center, radii, w_of, role, seg=12, rings=8, keep=None, axes=None, col=None, group=""):
        """UV ellipsoid; `axes` = (ex, ey, ez) orientation (default world).
        keep(local) drops faces whose centroid (local, unit-free) fails it."""
        ex, ey, ez = axes or (V(1, 0, 0), V(0, 1, 0), V(0, 0, 1))

        def P(lx, ly, lz):
            return center + ex * lx + ey * ly + ez * lz

        locs = {}

        def vert(lx, ly, lz):
            p = P(lx, ly, lz)
            i = self.add(p, w_of(p), role, col, group)
            locs[i] = V(lx / radii.x, ly / radii.y, lz / radii.z)
            return i

        top = vert(0, 0, radii.z)
        lat = []
        for i in range(1, rings):
            th = math.pi * i / rings
            row = []
            for j in range(seg):
                ph = 2 * math.pi * j / seg
                row.append(vert(radii.x * math.sin(th) * math.cos(ph), radii.y * math.sin(th) * math.sin(ph),
                                radii.z * math.cos(th)))
            lat.append(row)
        bot = vert(0, 0, -radii.z)

        def ok(idx):
            if keep is None:
                return True
            c = sum((locs[i] for i in idx), Vector((0, 0, 0))) / len(idx)
            return keep(c)

        for j in range(seg):
            k = (j + 1) % seg
            for f in ((top, lat[0][j], lat[0][k]), (bot, lat[-1][k], lat[-1][j])):
                if ok(f):
                    self.face(f, role, center)
        for i in range(len(lat) - 1):
            for j in range(seg):
                k = (j + 1) % seg
                f = (lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k])
                if ok(f):
                    self.face(f, role, center)

    def cone(self, base, tip, r, w, role, sides=5, up=None):
        """A spike: flat-shaded open cone (the base sits inside a shell)."""
        ax = (tip - base).normalized()
        ref = up if up is not None else (V(0, 0, 1) if abs(ax.z) < 0.9 else V(1, 0, 0))
        u = (ref - ax * ref.dot(ax)).normalized()
        v = ax.cross(u)
        ring = [base + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * r
                for k in range(sides)]
        for k in range(sides):
            a, b = ring[k], ring[(k + 1) % sides]
            ids = [self.add(p, w, role) for p in (a, b, tip)]
            self.flat.update(ids)
            self.face(tuple(ids), role, base + ax * 0.001)

    def hexplate(self, centre, normal, up, r, depth, w, role, col=None):
        """A raised flat hexagon (top + sides), flat-shaded."""
        n = normal.normalized()
        u = (up - n * up.dot(n)).normalized()
        v = n.cross(u)
        corners = [centre + (u * math.cos(math.radians(90 + 60 * k)) + v * math.sin(math.radians(90 + 60 * k))) * r
                   for k in range(6)]
        top = [p + n * depth for p in corners]
        inside = centre - n * 0.05
        ids = [self.add(p, w, role, col) for p in top]
        c = self.add(centre + n * depth, w, role, col)
        self.flat.update(ids + [c])
        for k in range(6):
            self.face((c, ids[k], ids[(k + 1) % 6]), role, inside)
        for k in range(6):
            q = [top[k], top[(k + 1) % 6], corners[(k + 1) % 6], corners[k]]
            qi = [self.add(p, w, role, col) for p in q]
            self.flat.update(qi)
            self.face(tuple(qi), role, centre)

    # -- normals and output
    def normals(self):
        acc = [Vector((0, 0, 0)) for _ in self.verts]
        fn = []
        for idx, _ in self.faces:
            n = newell([self.verts[i] for i in idx])
            fn.append(n)
            for i in idx:
                acc[i] += n
        out = [a.normalized() if a.length > 1e-12 else Vector((0, 0, 1)) for a in acc]
        return out, fn

    def build(self, name, materials):
        vnorm, fnorm = self.normals()
        out = []
        for role, mat in materials:
            faces = [(fi, f) for fi, (f, r) in enumerate(self.faces) if r == role]
            if not faces:
                continue
            remap, verts, weights, colors, norms, new_faces = {}, [], [], [], [], []
            for fi, f in faces:
                nf = []
                for vi in f:
                    key = (vi, fi) if vi in self.flat else vi
                    if key not in remap:
                        remap[key] = len(verts)
                        verts.append(self.verts[vi])
                        weights.append(self.weights[vi])
                        colors.append(self.colors[vi])
                        norms.append(fnorm[fi].normalized() if vi in self.flat else vnorm[vi])
                    nf.append(remap[key])
                new_faces.append(tuple(nf))
            me = bpy.data.meshes.new("%s_%s" % (name, role))
            me.from_pydata([tuple(v) for v in verts], [], new_faces)
            me.materials.append(mat)
            for p in me.polygons:
                p.use_smooth = True
            me.normals_split_custom_set_from_vertices([tuple(n) for n in norms])
            col = me.color_attributes.new("Color", 'BYTE_COLOR', 'POINT')
            for i, c in enumerate(colors):
                col.data[i].color_srgb = c
            me.color_attributes.active_color = col
            me.color_attributes.render_color_index = 0
            me.update()
            out.append((role, me, weights))
        return out


# ------------------------------------------------------------ surfaces
def catmull(rows, z, cols):
    """rows: list of tuples whose [0] is the key (ascending). Catmull-Rom on
    each column in `cols` at key z (clamped)."""
    zs = [r[0] for r in rows]
    if z <= zs[0]:
        return [rows[0][c] for c in cols]
    if z >= zs[-1]:
        return [rows[-1][c] for c in cols]
    i = 0
    while zs[i + 1] < z:
        i += 1
    u = (z - zs[i]) / (zs[i + 1] - zs[i])
    out = []
    for c in cols:
        p1, p2 = rows[i][c], rows[i + 1][c]
        p0 = rows[i - 1][c] if i > 0 else p1
        p3 = rows[i + 2][c] if i + 2 < len(rows) else p2
        u2, u3 = u * u, u * u * u
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3))
    return out


def section(theta_deg, w, f, b, e):
    """Superellipse section point (x, y) at angle theta (0 = +X the left
    side, 90 = front (-Y), 270 = back); front depth f, back depth b."""
    t = math.radians(theta_deg)
    c, s = math.cos(t), math.sin(t)
    x = w * sgnpow(c, e)
    d = f if s > 0 else b
    y = -d * sgnpow(s, e)
    return x, y


# torso rows: z, half-width, front depth, back depth, centre y, exponent
TORSO = [
    (1.075, 0.180, 0.084, 0.112, 0.006, 0.92),
    (1.100, 0.190, 0.088, 0.120, 0.006, 0.90),
    (1.150, 0.204, 0.090, 0.126, 0.006, 0.88),
    (1.200, 0.192, 0.087, 0.114, 0.003, 0.90),
    (1.250, 0.164, 0.082, 0.096, 0.0, 0.94),
    (1.305, 0.134, 0.075, 0.082, 0.0, 1.0),
    (1.360, 0.121, 0.072, 0.078, 0.0, 1.0),
    (1.410, 0.126, 0.074, 0.080, 0.0, 1.0),
    (1.470, 0.144, 0.082, 0.088, 0.0, 0.96),
    (1.530, 0.158, 0.088, 0.093, 0.0, 0.94),
    (1.590, 0.166, 0.092, 0.094, 0.0, 0.92),
    (1.650, 0.173, 0.090, 0.092, 0.0, 0.90),
    (1.710, 0.181, 0.082, 0.085, 0.0, 0.86),
    (1.765, 0.184, 0.070, 0.075, 0.005, 0.80),
    (1.810, 0.152, 0.062, 0.066, 0.010, 0.88),
    (1.850, 0.064, 0.052, 0.055, 0.012, 1.0),
    (1.900, 0.050, 0.047, 0.051, 0.012, 1.0),
    (1.975, 0.048, 0.045, 0.050, 0.012, 1.0),
]
BUSTS = [(64.0, 1.585, 22.0, 0.060, 0.058), (116.0, 1.585, 22.0, 0.060, 0.058)]   # theta, z, sig_theta, sig_z, amp
GLUTES = [(-62.0, 1.125, 30.0, 0.055, 0.024), (-118.0, 1.125, 30.0, 0.055, 0.024)]


def torso_pt(theta, z, off=0.0):
    w, f, b, cy, e = catmull(TORSO, z, (1, 2, 3, 4, 5))
    x, y = section(theta, w, f, b, e)
    d = Vector((x, y, 0))
    r = d.length
    dirn = d / r if r > 1e-9 else V(1, 0, 0)
    bump = 0.0
    for tb, zb, st, sz, amp in BUSTS + GLUTES:
        bump += amp * gauss(angdiff(theta, tb), 0.0, st) * gauss(z, zb, sz)
    p = V(0, cy, z) + dirn * (r + bump + off)
    # the bust also lifts: a touch of forward-up fullness
    return p


def torso_centre(z):
    return V(0, catmull(TORSO, z, (4,))[0], z)


# limbs: profile rows (d, out, in, front, back, shift_out, shift_fwd)
LEG = [
    (0.10, 0.130, 0.094, 0.096, 0.130, 0.010, -0.004),
    (0.16, 0.128, 0.092, 0.094, 0.124, 0.010, -0.008),
    (0.24, 0.124, 0.092, 0.096, 0.110, 0.008, -0.004),
    (0.34, 0.114, 0.088, 0.092, 0.096, 0.004, 0.0),
    (0.44, 0.090, 0.076, 0.082, 0.078, 0.0, 0.0),
    (0.51, 0.066, 0.060, 0.066, 0.058, 0.0, 0.0),
    (0.545, 0.056, 0.054, 0.060, 0.055, 0.0, 0.0),
    (0.60, 0.057, 0.055, 0.056, 0.060, 0.0, 0.0),
    (0.70, 0.060, 0.054, 0.054, 0.074, 0.0, 0.0),
    (0.84, 0.047, 0.043, 0.046, 0.054, 0.0, 0.0),
    (0.97, 0.037, 0.035, 0.037, 0.039, 0.0, 0.0),
    (1.06, 0.034, 0.033, 0.035, 0.036, 0.0, 0.0),
]
ARM = [
    (-0.06, 0.030, 0.030, 0.030, 0.030, 0.0, 0.0),
    (-0.035, 0.060, 0.052, 0.058, 0.060, 0.0, 0.0),
    (0.00, 0.079, 0.061, 0.070, 0.072, 0.0, 0.0),
    (0.07, 0.077, 0.059, 0.066, 0.068, 0.0, 0.0),
    (0.14, 0.064, 0.055, 0.060, 0.062, 0.0, 0.0),
    (0.22, 0.056, 0.052, 0.059, 0.055, 0.0, 0.0),
    (0.30, 0.046, 0.044, 0.046, 0.046, 0.0, 0.0),
    (0.34, 0.042, 0.041, 0.041, 0.045, 0.0, 0.0),
    (0.39, 0.051, 0.046, 0.048, 0.048, 0.0, 0.0),
    (0.47, 0.046, 0.042, 0.044, 0.044, 0.0, 0.0),
    (0.56, 0.035, 0.033, 0.034, 0.034, 0.0, 0.0),
    (0.63, 0.027, 0.025, 0.022, 0.024, 0.0, 0.0),
]


class Limb:
    """A limb surface round a joint chain. `d` everywhere is in the profile's
    reference length `ref_len` (so the outfit's hard-coded positions survive a
    proportion change); the chain itself may be longer or shorter."""

    def __init__(self, pts, s, profile, fwd_hint=FORWARD, ref_len=None):
        self.pts = pts
        self.s = s
        self.profile = profile
        self.lens = [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]
        self.joints = [0.0]
        for L in self.lens:
            self.joints.append(self.joints[-1] + L)
        self.k = (self.joints[-1] / ref_len) if ref_len else 1.0
        self.joints_ref = [j / self.k for j in self.joints]
        self.fwd_hint = fwd_hint

    def axis(self, d):
        """centre point and unit tangent at d (extrapolates beyond the ends)."""
        d = d * self.k
        i = 0
        while i < len(self.lens) - 1 and d > self.joints[i + 1]:
            i += 1
        a, b = self.pts[i], self.pts[i + 1]
        t = (b - a).normalized()
        p = a + t * (d - self.joints[i])
        # smooth the tangent across a joint
        for j in range(1, len(self.pts) - 1):
            if abs(d - self.joints[j]) < 0.05:
                t0 = (self.pts[j] - self.pts[j - 1]).normalized()
                t1 = (self.pts[j + 1] - self.pts[j]).normalized()
                k = 0.5 + 0.5 * (d - self.joints[j]) / 0.05
                t = t0.lerp(t1, k).normalized()
        return p, t

    def frame(self, d):
        p, t = self.axis(d)
        lat0 = V(self.s, 0, 0)
        lat = (lat0 - t * lat0.dot(t)).normalized()
        fwd = t.cross(lat).normalized()
        if fwd.dot(self.fwd_hint) < 0:
            fwd = -fwd
        return p, t, lat, fwd

    def pt(self, phi, d, off=0.0):
        """phi: 0 = outward (lateral), 90 = front."""
        p, t, lat, fwd = self.frame(d)
        ro, ri, rf, rb, so, sf = catmull(self.profile, d, (1, 2, 3, 4, 5, 6))
        a = math.radians(phi)
        c, s = math.cos(a), math.sin(a)
        rl = ro if c > 0 else ri
        rd = rf if s > 0 else rb
        lx = rl * sgnpow(c, 0.95)
        ly = rd * sgnpow(s, 0.95)
        rad = Vector((lx, ly, 0))
        n = rad.normalized() if rad.length > 1e-9 else Vector((1, 0, 0))
        lx += n.x * off
        ly += n.y * off
        return p + lat * (lx + so) + fwd * (ly - sf)

    def centre(self, d):
        return self.axis(d)[0]


# ------------------------------------------------------------- the body
NT = 24          # torso sides
NL = 16          # leg sides (13 shared with the torso half + 3 crotch seam)
NA = 12          # arm sides


def torso_role(theta, z):
    """H230: the suit runs up to a mock neck under the gorget; skin above."""
    return "skin" if z > 1.872 else "suit"


def plate_top(theta):
    """H230: the plate is a cuirass front: low under the arms, rising to the
    gorget at the sternum (no neckline opening)."""
    s = max(0.0, math.sin(math.radians(theta)))
    return 1.665 + 0.140 * s ** 3


def plate_bottom(theta):
    return 1.488 - 0.052 * max(0.0, 1.0 - abs(angdiff(theta, 90.0)) / 34.0) + 0.01 * (1 - math.sin(math.radians(theta)))


def suit_col(i):
    v = SUIT_STRIPE[i % 2]
    return (v, v, v)


def build_body(mb, groups):
    # ---- torso: rings from the crotch to the neck top
    zs = [1.10, 1.125, 1.15, 1.175, 1.20, 1.225, 1.25, 1.275, 1.30, 1.33, 1.36, 1.385, 1.41, 1.44, 1.47, 1.50,
          1.53, 1.555, 1.58, 1.605, 1.63, 1.655, 1.68, 1.71, 1.74, 1.765, 1.79, 1.815, 1.84, 1.87, 1.91, 1.975]
    thetas = [360.0 * k / NT for k in range(NT)]
    rows = []
    for ri, z in enumerate(zs):
        row = []
        for th in thetas:
            p = torso_pt(th, z)
            w = torso_w(z)
            # the shoulder tops follow the shoulder bones
            ax = abs(p.x)
            side = "l" if p.x > 0 else "r"
            ksh = ss(0.09, 0.16, ax) * ss(1.66, 1.75, z) * (1 - ss(1.80, 1.84, z)) * 0.55
            if ksh > 1e-3:
                w = mix((w, 1 - ksh), ({"shoulder_" + side: 1}, ksh))
            # the lowest rings share the thighs
            kth = (1 - ss(1.10, 1.24, z)) * 0.5 * min(1.0, ax / 0.12)
            if kth > 1e-3:
                w = mix((w, 1 - kth), ({"thigh_" + side: 1}, kth))
            role = torso_role(th, z)
            col = suit_col(ri) if role == "suit" else None
            row.append(mb.add(p, w, role, col, "torso"))
        rows.append(row)
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        zc = (zs[i] + zs[i + 1]) * 0.5
        for k in range(NT):
            k2 = (k + 1) % NT
            thc = thetas[k] + 180.0 / NT
            mb.face((a[k], a[k2], b[k2], b[k]), torso_role(thc, zc), torso_centre(zc))
    top = mb.add(V(0, 0.012, zs[-1]), torso_w(zs[-1]), "skin", None, "torso")
    mb.fan(rows[-1], top, "skin", torso_centre(zs[-1] - 0.05))
    groups["torso"] = list(range(rows[0][0], top + 1))

    # ---- crotch seam (shared by both legs), front to back at x = 0
    base = rows[0]
    yf = mb.verts[base[6]].y
    yb = mb.verts[base[18]].y
    seam = []
    for k, (u, dz) in enumerate(((0.25, 0.022), (0.5, 0.03), (0.75, 0.022))):
        p = V(0, lerp(yf, yb, u), CROTCH_Z - dz)
        seam.append(mb.add(p, {"hips": 0.5, "thigh_l": 0.25, "thigh_r": 0.25}, "suit", suit_col(1), "torso"))
    groups["torso"] += seam

    # ---- legs
    limbs = {}
    for side, s in SIDES:
        hip, knee, ankle, toe = leg_points(s)
        leg = Limb([hip, knee, ankle], s, LEG, ref_len=1.06)
        limbs["leg_" + side] = leg
        th, sn, ft = "thigh_" + side, "shin_" + side, "foot_" + side
        if s > 0:
            ring0 = [base[k % NT] for k in range(18, 31)] + seam            # back -> left -> front, seam front -> back
        else:
            ring0 = [base[k] for k in range(6, 19)] + list(reversed(seam))  # front -> right -> back, seam back -> front
        # each ring0 vertex's angle round the leg (phi: 0 = out, 90 = front)
        _, _, lat, fwd = leg.frame(0.12)
        c0 = leg.centre(0.10)
        phis0 = []
        for vi in ring0:
            r = mb.verts[vi] - c0
            phis0.append(math.degrees(math.atan2(r.dot(fwd), r.dot(lat))))
        # unwrap into a monotonic run
        un = [phis0[0]]
        for a in phis0[1:]:
            b = a
            while b - un[-1] > 180:
                b -= 360
            while b - un[-1] < -180:
                b += 360
            un.append(b)
        sign = 1 if un[-1] > un[0] else -1
        uniform = [un[0] + sign * 360.0 * i / NL for i in range(NL)]
        ds = [0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.49, 0.52, 0.545, 0.57, 0.60, 0.65, 0.70, 0.76, 0.82,
              0.88, 0.94, 1.00, 1.06]
        lrows = [ring0]
        joints = leg.joints_ref
        for j, d in enumerate(ds):
            k = min(1.0, (j + 1) / 3.0)
            row = []
            for i in range(NL):
                phi = lerp(un[i], uniform[i], k)
                p = leg.pt(phi, d)
                w = chain_w(d, joints, [th, sn], [0.0, 0.05, 0.03], start="hips", start_blend=0.0)
                kh = 0.5 * (1 - ss(0.10, 0.30, d))
                if kh > 1e-3:
                    w = mix((w, 1 - kh), ({"hips": 1}, kh))
                kf = 0.5 * ss(1.0, 1.06, d)
                if kf > 1e-3:
                    w = mix((w, 1 - kf), ({ft: 1}, kf))
                row.append(mb.add(p, w, "suit", suit_col(j), "leg_" + side))
            lrows.append(row)
        lc = [c0] + [leg.centre(d) for d in ds]
        mb.grid(lrows, lambda i, k: "suit", lambda i, k: (lc[i] + lc[i + 1]) * 0.5, closed=True)
        end = mb.add(leg.centre(ds[-1]), {sn: 0.5, ft: 0.5}, "suit", suit_col(0), "leg_" + side)
        mb.fan(lrows[-1], end, "suit", leg.centre(ds[-1] - 0.05))
        groups["leg_" + side] = [i for r in lrows[1:] for i in r] + [end]

    # ---- arms
    for side, s in SIDES:
        sh, el, wr, tip = arm_points(s)
        arm = Limb([sh, el, wr], s, ARM)
        limbs["arm_" + side] = arm
        ua, fa, hd, so = "upper_arm_" + side, "forearm_" + side, "hand_" + side, "shoulder_" + side
        role = "suit" if s > 0 else "skin"          # the left arm is sleeved, the weapon arm bare below a short sleeve (H230)
        sleeve = 1.0 if s > 0 else 0.15
        ds = [-0.06, -0.045, -0.025, 0.0, 0.03, 0.06, 0.10, 0.14, 0.18, 0.22, 0.26, 0.30, 0.325, 0.35, 0.375,
              0.40, 0.44, 0.48, 0.52, 0.56, 0.60, 0.63]
        arows = []
        for j, d in enumerate(ds):
            row = []
            for i in range(NA):
                phi = 360.0 * i / NA
                p = arm.pt(phi, d)
                w = chain_w(d, arm.joints, [ua, fa], [0.0, 0.04, 0.02], start=so, start_blend=0.07, end=hd, end_blend=0.02)
                rj = "suit" if d < sleeve - 0.02 else role     # the hem ring takes the skin colour (under the hem band)
                row.append(mb.add(p, w, rj, suit_col(j) if rj == "suit" else None, "arm_" + side))
            arows.append(row)
        ac = [arm.centre(d) for d in ds]
        mb.grid(arows, lambda i, k: "suit" if (ds[i] + ds[i + 1]) * 0.5 < sleeve else role,
                lambda i, k: (ac[i] + ac[i + 1]) * 0.5, closed=True)
        c_in = mb.add(arm.centre(ds[0] - 0.012), {so: 0.45, ua: 0.55}, role, None, "arm_" + side)
        mb.fan(arows[0], c_in, role, arm.centre(ds[1]))
        c_out = mb.add(arm.centre(ds[-1]), {hd: 0.5, fa: 0.5}, role, None, "arm_" + side)
        mb.fan(arows[-1], c_out, role, arm.centre(ds[-2]))
        groups["arm_" + side] = [i for r in arows for i in r] + [c_in, c_out]
        build_hand(mb, side, s, wr, tip)

    build_head(mb, groups)
    return limbs


def build_hand(mb, side, s, wr, tip):
    """A mitten hand: palm loft along the hand bone (width front-back, the
    palm facing in) and a thumb."""
    hd = "hand_" + side
    t = (tip - wr).normalized()
    lat0 = V(s, 0, 0)
    lat = (lat0 - t * lat0.dot(t)).normalized()
    fwd = t.cross(lat).normalized()
    if fwd.dot(FORWARD) < 0:
        fwd = -fwd
    rows_def = [(-0.01, 0.024, 0.020), (0.02, 0.036, 0.020), (0.055, 0.044, 0.018), (0.09, 0.045, 0.016),
                (0.125, 0.040, 0.014), (0.155, 0.030, 0.012), (0.178, 0.016, 0.009)]
    n = 10
    rows = []
    cs = []
    for h, wd, th in rows_def:
        c = wr + t * h - lat * 0.004
        cs.append(c)
        row = []
        for k in range(n):
            a = 2 * math.pi * k / n
            p = c + fwd * (wd * math.sin(a)) + lat * (th * math.cos(a))
            w = {hd: 1.0} if h > 0.015 else {hd: 0.6, "forearm_" + side: 0.4}
            row.append(mb.add(p, w, "skin", None, "hand_" + side))
        rows.append(row)
    mb.grid(rows, lambda i, k: "skin", lambda i, k: (cs[i] + cs[i + 1]) * 0.5, closed=True)
    tipc = mb.add(wr + t * 0.186 - lat * 0.004, {hd: 1}, "skin", None, "hand_" + side)
    mb.fan(rows[-1], tipc, "skin", cs[-1] - t * 0.01)
    # thumb: from the front of the palm, out and down
    b0 = wr + t * 0.03 + fwd * 0.03 - lat * 0.008
    b1 = b0 + t * 0.05 + fwd * 0.02 - lat * 0.012
    tube(mb, [b0, b1, b1 + t * 0.03 + fwd * 0.004], [0.014, 0.012, 0.007], {hd: 1}, "skin", sides=6, group="hand_" + side)


def tube(mb, pts, radii, w, role, sides=6, cap=True, group="", w_of=None, col=None):
    """A tube through points (catmull-rom resampled by the caller if needed)."""
    loops = []
    n = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if n is None:
            ref = V(0, 0, 1) if abs(t.z) < 0.9 else V(1, 0, 0)
            n = (ref - t * ref.dot(t)).normalized()
        else:
            n = (n - t * n.dot(t)).normalized()
        b = t.cross(n)
        row = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            q = p + (n * math.cos(a) + b * math.sin(a)) * radii[i]
            row.append(mb.add(q, w_of(q, i) if w_of else w, role, col, group))
        loops.append(row)
    mb.grid(loops, lambda i, k: role, lambda i, k: (pts[i] + pts[i + 1]) * 0.5, closed=True)
    if cap:
        e = mb.add(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 0.6, w_of(pts[-1], len(pts) - 1) if w_of else w,
                   role, col, group)
        mb.fan(loops[-1], e, role, pts[-2])
        s0 = mb.add(pts[0] - (pts[1] - pts[0]).normalized() * radii[0] * 0.4, w_of(pts[0], 0) if w_of else w, role, col, group)
        mb.fan(loops[0], s0, role, pts[1])


# head rows: z, half-width, front, back, centre y, exponent
HEAD = [
    (1.918, 0.018, 0.018, 0.010, -0.066, 1.0),
    (1.934, 0.044, 0.042, 0.036, -0.034, 1.0),
    (1.960, 0.066, 0.076, 0.060, -0.010, 1.0),
    (1.995, 0.080, 0.094, 0.080, -0.002, 1.0),
    (2.030, 0.090, 0.102, 0.094, 0.0, 1.0),
    (2.065, 0.095, 0.103, 0.103, 0.0, 1.0),
    (2.100, 0.095, 0.100, 0.107, 0.0, 1.0),
    (2.135, 0.090, 0.090, 0.105, 0.0, 1.0),
    (2.165, 0.076, 0.071, 0.090, 0.0, 1.0),
    (2.188, 0.048, 0.046, 0.060, 0.0, 1.0),
    (2.200, 0.018, 0.016, 0.022, 0.0, 1.0),
]


def head_pt(theta, z, off=0.0):
    w, f, b, cy, e = catmull(HEAD, z, (1, 2, 3, 4, 5))
    x, y = section(theta, w, f, b, e)
    d = Vector((x, y, 0))
    r = d.length
    n = d / r if r > 1e-9 else V(1, 0, 0)
    return V(0, cy, z) + n * (r + off)


def build_head(mb, groups):
    hw = {"head": 1.0}
    zs = [1.918, 1.934, 1.95, 1.97, 1.985, 2.0, 2.02, 2.04, 2.06, 2.08, 2.10, 2.12, 2.14, 2.16, 2.177, 2.19, 2.2]
    n = 20
    thetas = [360.0 * k / n for k in range(n)]
    rows = []
    for z in zs:
        rows.append([mb.add(head_pt(th, z), hw, "skin", None, "head") for th in thetas])
    cy = [V(0, catmull(HEAD, z, (4,))[0], z) for z in zs]
    mb.grid(rows, lambda i, k: "skin", lambda i, k: (cy[i] + cy[i + 1]) * 0.5, closed=True)
    top = mb.add(V(0, 0, 2.203), hw, "skin", None, "head")
    mb.fan(rows[-1], top, "skin", V(0, 0, 2.15))
    bot = mb.add(V(0, -0.062, 1.915), hw, "skin", None, "head")
    mb.fan(rows[0], bot, "skin", V(0, -0.03, 1.97))
    groups["head"] = list(range(rows[0][0], bot + 1))
    build_face(mb, hw)


def _strip(mb, top, bot, w, col, flat=True):
    """A painted strip on the face: two point rows -> quads, proud of the skin."""
    a = [mb.add(p, w, "skin", col) for p in top]
    b = [mb.add(p, w, "skin", col) for p in bot]
    for k in range(len(top) - 1):
        mb.face((a[k], a[k + 1], b[k + 1], b[k]), "skin", HEAD_C)
    if flat:
        mb.flat.update(a + b)


def build_face(mb, hw):
    """H233: a comic face in hard planes and ink: an angular nose with a shadow
    line, almond eyes (sclera, iris, a heavy upper lash line with a wing),
    strong arched brows, two-tone red lips, and a jaw-line shadow. Every mark
    is a few flat-shaded faces proud of the skin, so it holds at the gameplay
    camera as dark eyes, brows and a red mouth."""
    SCL = (0.96, 0.93, 0.90)
    IRIS = (0.22, 0.12, 0.08)
    INK = (0.07, 0.05, 0.07)
    LIP_U = (0.58, 0.06, 0.09)
    LIP_L = (0.82, 0.14, 0.15)
    SHADE = (0.72, 0.50, 0.42)
    # nose: a bridge ridge and a wedge tip, flat planes
    pts = [head_pt(90, 2.062, 0.001), head_pt(90, 2.035, 0.008), head_pt(90, 2.010, 0.022),
           head_pt(84, 2.004, 0.004), head_pt(96, 2.004, 0.004), head_pt(90, 2.000, 0.010),
           head_pt(85, 2.04, 0.0015), head_pt(95, 2.04, 0.0015)]
    ids = [mb.add(p, hw, "skin") for p in pts]
    mb.flat.update(ids)
    t, m, tip, nl, nr, under, sl, sr = ids
    for f in ((t, sl, m), (t, m, sr), (sl, nl, tip, m), (m, tip, nr, sr), (nl, under, tip), (tip, under, nr)):
        mb.face(f, "skin", V(0, 0.02, 2.03))
    # the nose shadow line down her right side of the bridge (light from her left)
    _strip(mb, [head_pt(95.5, z, 0.0035) for z in (2.058, 2.035, 2.012)],
           [head_pt(97.5, z, 0.0035) for z in (2.058, 2.035, 2.010)], hw, SHADE)
    for s in (1, -1):
        c_th = 90 - s * 21.0

        def E(da, dz, off=0.003):
            return head_pt(c_th + s * da, 2.059 + dz, off)
        # sclera almond
        ring = [mb.add(E(da, dz, 0.0026), hw, "skin", SCL) for da, dz in ((-12, 0.0), (-5, 0.007), (5, 0.007), (13, 0.002), (5, -0.005), (-5, -0.005))]
        ci = mb.add(E(0, 0.001, 0.003), hw, "skin", SCL)
        mb.fan(ring, ci, "skin", HEAD_C)
        mb.flat.update(ring + [ci])
        # iris
        ring = [mb.add(E(2 + 4.2 * math.cos(a), 0.001 + 0.0055 * math.sin(a), 0.0034), hw, "skin", IRIS)
                for a in [2 * math.pi * k / 7 for k in range(7)]]
        ci = mb.add(E(2, 0.001, 0.0036), hw, "skin", INK)
        mb.fan(ring, ci, "skin", HEAD_C)
        mb.flat.update(ring + [ci])
        # upper lash line with a flick: thick, dark, sweeping out and up
        top = [E(-13, 0.002, 0.004), E(-5, 0.009, 0.004), E(5, 0.0095, 0.004), E(14, 0.005, 0.004), E(20, 0.011, 0.004)]
        bot = [E(-13, -0.001, 0.004), E(-5, 0.0055, 0.004), E(5, 0.006, 0.004), E(13, 0.0015, 0.004), E(19, 0.008, 0.004)]
        _strip(mb, top, bot, hw, INK)
        # lower lash, thin
        _strip(mb, [E(-8, -0.0045, 0.0038), E(4, -0.0055, 0.0038), E(12, -0.0015, 0.0038)],
               [E(-8, -0.0062, 0.0038), E(4, -0.0072, 0.0038), E(12, -0.003, 0.0038)], hw, INK)
        # brow: a strong arch, heavy at the inner end, tapering out and up
        bt = [E(-12, 0.022, 0.0045), E(-3, 0.028, 0.0045), E(8, 0.029, 0.0045), E(17, 0.023, 0.0045)]
        bb = [E(-12, 0.012, 0.0045), E(-3, 0.018, 0.0045), E(8, 0.022, 0.0045), E(17, 0.020, 0.0045)]
        _strip(mb, bt, bb, hw, INK)
    # lips: a darker upper lip with a cupid's bow, a fuller lighter lower lip
    up_t = [head_pt(90 + da, 1.974 + dz, 0.0042) for da, dz in ((-16, 0.0), (-6, 0.008), (0, 0.0055), (6, 0.008), (16, 0.0))]
    up_b = [head_pt(90 + da, 1.973 + dz, 0.0042) for da, dz in ((-16, -0.0005), (-6, 0.0005), (0, 0.001), (6, 0.0005), (16, -0.0005))]
    _strip(mb, up_t, up_b, hw, LIP_U)
    lo_t = [head_pt(90 + da, 1.9725 + dz, 0.0046) for da, dz in ((-14, 0.0), (-6, -0.0005), (0, -0.0005), (6, -0.0005), (14, 0.0))]
    lo_b = [head_pt(90 + da, 1.972 + dz, 0.0046) for da, dz in ((-14, -0.001), (-6, -0.009), (0, -0.011), (6, -0.009), (14, -0.001))]
    _strip(mb, lo_t, lo_b, hw, LIP_L)
    _strip(mb, [head_pt(90 + da, 1.9728, 0.0050) for da in (-15, 0, 15)],
           [head_pt(90 + da, 1.9718, 0.0050) for da in (-15, 0, 15)], hw, INK)
    # a shadow under the cheekbones (the comic planes)
    for s in (1, -1):
        _strip(mb, [head_pt(90 - s * da, z, 0.0025) for da, z in ((28, 2.035), (34, 2.015), (36, 1.99))],
               [head_pt(90 - s * da, z, 0.0025) for da, z in ((24, 2.028), (30, 2.008), (33, 1.985))], hw, SHADE)


# --------------------------------------------------------------- hair
def hair_w(z):
    if z > 2.02:
        return {"head": 1.0}
    if z > 1.90:
        k = ss(1.90, 2.02, z)
        return {"head": k, "neck": 1 - k}
    if z > 1.78:
        k = ss(1.78, 1.90, z)
        return {"neck": k * 0.8, "chest": 1 - k * 0.8}
    k = ss(1.35, 1.6, z)
    return {"chest": 0.55 + 0.45 * k, "spine": 0.45 * (1 - k)}


def ribbon(mb, pts, widths, thick, wave, sides=8):
    """A flat hair clump: an elliptical tube, wide across the body's
    surface (round the vertical axis) and thin away from it, waved sideways."""
    loops, cs = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        r = Vector((p.x, p.y - 0.03, 0))
        r = r.normalized() if r.length > 1e-6 else V(0, 1, 0)
        n = (r - t * r.dot(t)).normalized()
        b = t.cross(n).normalized()
        c = p + b * wave[i]
        cs.append(c)
        row = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            q = c + n * (thick[i] * math.cos(a)) + b * (widths[i] * math.sin(a))
            row.append(mb.add(q, hair_w(q.z), "hair"))
        loops.append(row)
    mb.grid(loops, lambda i, k: "hair", lambda i, k: (cs[i] + cs[i + 1]) * 0.5, closed=True)
    e = mb.add(cs[-1] + (cs[-1] - cs[-2]).normalized() * 0.02, hair_w(cs[-1].z), "hair")
    mb.fan(loops[-1], e, "hair", cs[-2])


def catmull_path(ctrl, n):
    """n points along a Catmull-Rom through ctrl."""
    out = []
    segs = len(ctrl) - 1
    for i in range(n):
        u = i / (n - 1) * segs
        j = min(int(u), segs - 1)
        t = u - j
        p0 = ctrl[max(j - 1, 0)]
        p1, p2 = ctrl[j], ctrl[j + 1]
        p3 = ctrl[min(j + 2, segs)]
        t2, t3 = t * t, t * t * t
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return out


# hair mass down the back: z, centre y, outer half-width, outer depth, inner half-width, inner depth, arc start (deg)
HAIR_BACK = [
    (2.13, 0.010, 0.100, 0.118, 0.060, 0.070, 15.0),
    (2.06, 0.012, 0.118, 0.132, 0.080, 0.090, 15.0),
    (1.98, 0.022, 0.135, 0.145, 0.084, 0.080, 0.0),
    (1.90, 0.035, 0.175, 0.150, 0.090, 0.070, -10.0),
    (1.81, 0.045, 0.262, 0.155, 0.160, 0.088, -28.0),
    (1.70, 0.055, 0.300, 0.158, 0.185, 0.098, -32.0),
    (1.58, 0.062, 0.290, 0.152, 0.178, 0.100, -34.0),
    (1.47, 0.070, 0.255, 0.142, 0.160, 0.102, -38.0),
    (1.38, 0.076, 0.205, 0.128, 0.130, 0.100, -42.0),
    (1.31, 0.080, 0.120, 0.104, 0.080, 0.090, -50.0),
]


def build_hair(mb):
    # cap: a shell over the skull, the face cut out
    def keep(p):
        if p.z < -0.75 and p.y < 0.3:
            return False
        if p.y < -0.30 and p.z < 0.50 and abs(p.x) < 0.78:
            return False
        return True
    mb.ellipsoid(V(0, 0.020, 2.082), V(0.124, 0.140, 0.156), lambda p: hair_w(p.z), "hair", seg=20, rings=12, keep=keep)
    # the mass down the back: a closed crescent loft
    M = 11
    rows = []
    cents = []
    for ri, (z, cy, wo, do, wi, di, a0) in enumerate(HAIR_BACK):
        outer, inner = [], []
        for k in range(M):
            th = a0 - (180.0 + 2 * a0) * k / (M - 1)       # from the left side round the back to the right
            t = math.radians(th)
            wave = 0.012 * math.sin(k * 1.7 + ri * 0.9)
            zo = z
            if ri == len(HAIR_BACK) - 1:
                zo = z - 0.07 * (0.5 + 0.5 * math.cos(k * 2.2))     # lock tips
            if ri == len(HAIR_BACK) - 2:
                zo = z - 0.03 * (0.5 + 0.5 * math.cos(k * 2.2 + 0.6))
            outer.append(V((wo + wave) * math.cos(t), cy - (do + wave) * math.sin(t), zo))
            inner.append(V(wi * math.cos(t), cy - di * math.sin(t), zo + 0.01))
        ring = outer + list(reversed(inner))
        rows.append([mb.add(p, hair_w(p.z), "hair") for p in ring])
        cents.append(V(0, cy + (do + di) * 0.5, z))
    # inside reference: a point between the arcs, behind the body
    mb.grid(rows, lambda i, k: "hair", lambda i, k: (cents[i] + cents[i + 1]) * 0.5, closed=True)
    endc = mb.add(cents[-1] + V(0, 0, -0.05), hair_w(1.3), "hair")
    mb.fan(rows[-1], endc, "hair", cents[-2])
    # r2: generated locks (waving, tapering) instead of the stiff tubes
    locks = []
    for s, ln in ((1, 1.70), (-1, 1.78)):
        # framing the face down to the collar
        locks.append(([V(s * 0.07, -0.085, 2.15), V(s * 0.108, -0.072, 2.04), V(s * 0.122, -0.062, 1.93),
                       V(s * 0.138, -0.075, 1.82), V(s * 0.13, -0.09, ln)], 0.034, 0.006, 0.014, 0.0, s))
        for k in range(3):
            # big side volume: out over the shoulders, behind them, waving down the back
            locks.append(([V(s * (0.09 + 0.012 * k), 0.0 + 0.03 * k, 2.10 - 0.025 * k),
                           V(s * (0.19 + 0.03 * k), 0.06 + 0.03 * k, 1.88), V(s * (0.29 + 0.025 * k), 0.10 + 0.02 * k, 1.68),
                           V(s * (0.28 + 0.035 * k), 0.13, 1.52), V(s * (0.29 + 0.025 * k), 0.12 + 0.01 * k, 1.36 + 0.035 * k)],
                          0.064, 0.010, 0.030, k * 1.3, s))
    for x in (-0.085, 0.0, 0.085):
        locks.append(([V(x, 0.11, 2.06), V(x * 1.4, 0.17, 1.82), V(x * 1.7, 0.18, 1.56), V(x * 1.8, 0.155, 1.28)],
                      0.066, 0.012, 0.02, x * 20.0, 1))
    # r4: the face-framing locks stay tubes; the big volume is a curtain of
    # flat overlapping ribbons (clumps) round the back and over the shoulders
    for ctrl, r0, r1, amp, ph, s in locks[:: 4][:2]:
        # H234: the face-framing locks as flat waved clumps too
        n = 13
        pts = catmull_path(ctrl, n)
        widths = [lerp(0.040, 0.008, (i / (n - 1)) ** 1.1) * (1.0 + 0.25 * math.sin(i * 1.3 + ph)) for i in range(n)]
        thick = [lerp(0.020, 0.006, i / (n - 1)) for i in range(n)]
        wave = [0.022 * math.sin(i / (n - 1) * 2 * math.pi * 1.4 + ph) * (i / (n - 1)) for i in range(n)]
        ribbon(mb, pts, widths, thick, wave)
    prof = [(2.15, 0.112), (2.05, 0.15), (1.93, 0.205), (1.80, 0.27), (1.66, 0.325), (1.52, 0.31), (1.40, 0.265), (1.28, 0.20)]
    # H234: two layers of clumps (a long inner curtain, a shorter outer layer
    # between them), each waved with its own phase and length, the lower half
    # swept by a wind toward her left and back, tips pointed.
    n_rib = 14
    for j in range(n_rib):
        outer = j % 2 == 1
        th = -16.0 - (180.0 - 32.0) * j / (n_rib - 1)
        t = math.radians(th)
        ph = j * 2.17
        tip = (1.20 + 0.14 * (0.5 + 0.5 * math.sin(j * 2.9))) + (0.16 if outer else 0.0)
        side = abs(math.cos(t))
        lift = 0.035 if outer else 0.0
        ctrl = [V(0.035 * math.cos(t), 0.03 - 0.03 * math.sin(t), 2.215 - (0.03 if outer else 0.0))]   # from the crown: covers the cap
        for z, r in prof:
            if z < tip + 0.02:
                break
            rr = r * (1.0 + 0.12 * side) + lift
            ctrl.append(V(rr * math.cos(t), 0.035 - rr * 0.78 * math.sin(t), z))
        ctrl.append(V(ctrl[-1].x * 0.95, ctrl[-1].y, tip))
        n = 15
        pts = catmull_path(ctrl, n)
        wind = [V(0.075, 0.035, 0.02) * ((i / (n - 1)) ** 1.6) for i in range(n)]
        pts = [p + wnd for p, wnd in zip(pts, wind)]
        widths, thick = [], []
        for i in range(n):
            u = i / (n - 1)
            widths.append(lerp(0.070 if not outer else 0.06, 0.010, u ** 1.2) * (1.0 + 0.28 * math.sin(u * 8.0 + ph)))
            thick.append(lerp(0.038, 0.008, u))
        freq = 1.1 + 0.5 * (0.5 + 0.5 * math.sin(j * 1.7))
        wave = [0.048 * math.sin(i / (n - 1) * 2 * math.pi * freq + ph) * (i / (n - 1)) ** 0.8 for i in range(n)]
        ribbon(mb, pts, widths, thick, wave)


# ------------------------------------------------------------- outfit
def nearest_weights(mb, kd_by_group, groups, p):
    for g in groups:
        kd, ids = kd_by_group[g]
        co, idx, dist = kd.find(p)
        if idx is not None:
            return dict(mb.weights[ids[idx]])
    return {"chest": 1.0}


def patch(mb, F, us, vs_of, off_of, role, inside_of, w_of, closed=False, rim=False, col_of=None, flat=False):
    """A surface patch: columns at parameters `us`, rows at vs_of(u) (a list
    per column, same length), offset off_of(u, v). Rim: quads from the
    patch edge down to the surface (off 0) so the shell reads thick. `flat`:
    every face takes its own normal (hard-edged armour facets, H232)."""
    v0 = len(mb.verts)
    cols = _patch(mb, F, us, vs_of, off_of, role, inside_of, w_of, closed, rim, col_of)
    if flat:
        mb.flat.update(range(v0, len(mb.verts)))
    return cols


def _patch(mb, F, us, vs_of, off_of, role, inside_of, w_of, closed=False, rim=False, col_of=None):
    cols = []
    for ui, u in enumerate(us):
        col = []
        for vi, v in enumerate(vs_of(u)):
            p = F(u, v, off_of(u, v))
            c = col_of(ui, vi) if col_of else None
            col.append((mb.add(p, w_of(p), role, c), p, F(u, v, 0.0)))
        cols.append(col)
    nu, nv = len(cols), len(cols[0])
    rows = [[cols[ui][vi][0] for ui in range(nu)] for vi in range(nv)]
    for vi in range(nv - 1):
        for ui in range(nu if closed else nu - 1):
            u2 = (ui + 1) % nu
            a, b, c, d = rows[vi][ui], rows[vi][u2], rows[vi + 1][u2], rows[vi + 1][ui]
            mb.face((a, b, c, d), role, inside_of(us[ui], vs_of(us[ui])[vi]))
    if rim:
        assert not closed
        edge = [(ui, 0) for ui in range(nu)] + [(nu - 1, vi) for vi in range(1, nv)]
        edge += [(ui, nv - 1) for ui in range(nu - 2, -1, -1)] + [(0, vi) for vi in range(nv - 2, 0, -1)]
        centre = sum((cols[ui][vi][1] for ui in range(nu) for vi in range(nv)), Vector((0, 0, 0))) / (nu * nv)
        m = len(edge)
        for i in range(m):
            (u1, v1), (u2, v2) = edge[i], edge[(i + 1) % m]
            a, pa, sa = cols[u1][v1]
            b, pb, sb = cols[u2][v2]
            ia = mb.add(sa + (pa - sa) * 0.15, mb.weights[a], role, mb.colors[a][:3])
            ib = mb.add(sb + (pb - sb) * 0.15, mb.weights[b], role, mb.colors[b][:3])
            mb.face_out((a, b, ib, ia), role, (pa + pb) * 0.5 - centre)
    return cols


def build_outfit(mb, limbs, kd, groups_ids):
    torso_F = lambda th, z, off: torso_pt(th, z, off)
    tw = lambda p: nearest_weights(mb, kd, ["torso"], p)

    # -- bust plate (teal steel) over the front, sweetheart top, V bottom
    us = [8.0 + (172.0 - 8.0) * i / 12 for i in range(13)]
    nv = 6

    def plate_off(th, z):
        keel = 0.012 * max(0.0, 1.0 - abs(angdiff(th, 90.0)) / 26.0)          # a centre ridge line
        ridge = 0.006 * gauss(z, 1.545, 0.02) * (1 - max(0.0, 1.0 - abs(angdiff(th, 90.0)) / 26.0))  # under-bust crease
        return 0.013 + 0.004 * math.sin(math.radians(th)) + keel - ridge
    plate_cols = patch(
        mb, torso_F, us,
        lambda th: [lerp(plate_bottom(th), plate_top(th), j / (nv - 1)) for j in range(nv)],
        plate_off, "plate", lambda th, z: torso_centre(z), tw, rim=True, flat=True)
    band_torso(mb, lambda th: plate_top(th) - 0.003, 0.006, 0.020, 12.0, 168.0, "leather", tw, closed=False)
    # gorget: a faceted dark collar round the neck base, standing up to the jaw line
    gz = [1.772, 1.80, 1.83, 1.858, 1.885]
    patch(mb, torso_F, [360.0 * i / 12 + 15.0 for i in range(12)], lambda th: gz,
          lambda th, z: 0.020 + 0.012 * ss(1.84, 1.885, z) + 0.006 * max(0.0, math.sin(math.radians(th))),
          "armor", lambda th, z: torso_centre(z), tw, closed=True, flat=True)
    band_torso(mb, lambda th: 1.776, 0.006, 0.024, 0.0, 360.0, "plate", tw, closed=True)
    # a centre ridge between the cups and the crest (original: a hex with an inset hex)
    cz = 1.548
    cp = torso_pt(90.0, cz, 0.032)            # on the plate's centre ridge (H232 raised it)
    cn = (cp - torso_centre(cz)).normalized()
    mb.hexplate(cp - cn * 0.004, cn, V(0, 0, 1), 0.032, 0.008, tw(cp), "armor")
    mb.hexplate(cp + cn * 0.003, cn, V(0, 0, 1), 0.017, 0.006, tw(cp), "suit", (1.0, 1.0, 1.0))
    # under-plate trim: a dark rim line under the bust plate
    band_torso(mb, lambda th: plate_bottom(th) - 0.006, 0.006, 0.010, 10.0, 170.0, "leather", tw, closed=False)

    # -- hip band: a V in front (to the crotch), level round the back, the cape hangs from it
    def belt_z(th):
        s = math.sin(math.radians(th))
        if s > 0:
            k = max(0.0, 1.0 - abs(angdiff(th, 90.0)) / 80.0)
            return lerp(1.235, 1.122, k ** 1.2)
        return 1.235
    band_torso(mb, belt_z, 0.016, 0.009, 0.0, 360.0, "leather", tw, closed=True)
    # waist cincher seams: two thin dark lines down the front of the suit
    for th in (70.0, 110.0):
        pts = [torso_pt(th + (90 - th) * 0.25 * (1.45 - z) / 0.25, z, 0.004) for z in (1.47, 1.40, 1.33, 1.26, 1.20)]
        tube(mb, pts, [0.004] * len(pts), None, "leather", sides=4, cap=False, w_of=lambda q, i: tw(q))

    # -- half-cape from the hip band, open at the front
    build_cape(mb)

    # -- legs: strap bands on the thighs, greaves, knee stars, boots
    for side, s in SIDES:
        leg = limbs["leg_" + side]
        lw = lambda p, g="leg_" + side: nearest_weights(mb, kd, [g], p)
        for dc, tilt in ((0.22, 0.03), (0.40, -0.03)):
            band_limb(mb, leg, lambda phi, dc=dc, tilt=tilt: dc + tilt * math.cos(math.radians(phi - 90)), 0.017, 0.008, "leather", lw)
        build_greave(mb, leg, side, s, lw)
        build_boot(mb, side, s)

    # -- arms
    for side, s in SIDES:
        arm = limbs["arm_" + side]
        aw = lambda p, g="arm_" + side: nearest_weights(mb, kd, [g], p)
        if s > 0:
            # the sleeved arm: dark strap bands and a flared bracer
            for dc in (0.13, 0.21, 0.29):
                band_limb(mb, arm, lambda phi, dc=dc: dc + 0.012 * math.cos(math.radians(phi)), 0.012, 0.006, "leather", aw)
            us_ = [360.0 * i / 9 for i in range(9)]
            patch(mb, lambda phi, d, off: arm.pt(phi, d, off), us_,
                  lambda phi: [0.43, 0.47, 0.51, 0.55, 0.59, 0.615],
                  lambda phi, d: 0.011 + 0.016 * ss(0.56, 0.43, d) + 0.010 * max(0.0, math.cos(math.radians(phi))) ** 6,
                  "armor", lambda phi, d: arm.centre(d), aw, closed=True, rim=False, flat=True)
            band_limb(mb, arm, lambda phi: 0.445, 0.010, 0.026, "leather", aw)
            band_limb(mb, arm, lambda phi: 0.605, 0.008, 0.016, "leather", aw)
            build_pauldron(mb, arm, side, s)
        else:
            # the weapon arm: red tattoo bands on the upper arm, a wrapped forearm
            band_limb(mb, arm, lambda phi: 0.15, 0.010, 0.006, "leather", aw)       # the sleeve's hem
            for dc, hw in ((0.19, 0.006), (0.215, 0.003), (0.245, 0.009), (0.28, 0.003)):
                band_limb(mb, arm, lambda phi, dc=dc: dc + 0.01 * math.cos(math.radians(phi)), hw, 0.0025, "suit", aw)
            build_cap(mb, arm, side, s)
            us_ = [360.0 * i / 14 for i in range(14)]
            nrow = 16

            def wrap_rows(phi):
                return [0.40 + (0.635 - 0.40) * j / (nrow - 1) + 0.012 * (phi / 360.0) for j in range(nrow)]
            patch(mb, lambda phi, d, off: arm.pt(phi, d, off), us_, wrap_rows,
                  lambda phi, d: 0.006 + 0.0035 * (round((d - 0.40) / (0.235 / (nrow - 1))) % 2),
                  "wrap", lambda phi, d: arm.centre(d), aw, closed=True)

    # -- headband with a hex crest
    hw = lambda p: {"head": 1.0}
    hb_z = lambda th: 2.142 - 0.010 * math.sin(math.radians(th))
    band_surface(mb, lambda th, z, off: head_pt(th, z, off), [360.0 * i / 24 for i in range(24)], hb_z, 0.0085, 0.006,
                 "armor", hw, lambda th, z: V(0, 0, z), closed=True)
    hp = head_pt(90.0, 2.138, 0.009)
    mb.hexplate(hp, V(0, -1, 0.15), V(0, 0, 1), 0.020, 0.006, hw(hp), "plate")
    mb.hexplate(hp + V(0, -0.005, 0.0007), V(0, -1, 0.15), V(0, 0, 1), 0.010, 0.005, hw(hp), "suit", (1.0, 1.0, 1.0))


def band_surface(mb, F, us, vc_of, hw, off, role, w_of, inside_of, closed=True):
    """A raised band on a surface: three strips (edge, top, edge)."""
    rows = []
    for v_rel, o in ((-hw, 0.0), (-hw, off), (hw, off), (hw, 0.0)):
        rows.append([mb.add(F(u, vc_of(u) + v_rel, o), w_of(F(u, vc_of(u), 0)), role) for u in us])
    n = len(us)
    for i in range(3):
        for k in range(n if closed else n - 1):
            k2 = (k + 1) % n
            mb.face((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]), role, inside_of(us[k], vc_of(us[k])))


def band_torso(mb, z_of, hw, off, th0, th1, role, w_of, closed=True):
    n = 36 if closed else 24
    us = [th0 + (th1 - th0) * i / (n if closed else n - 1) for i in range(n)]
    band_surface(mb, lambda th, z, o: torso_pt(th, z, o), us, z_of, hw, off, role, w_of,
                 lambda th, z: torso_centre(z), closed=closed)


def band_limb(mb, limb, d_of, hw, off, role, w_of):
    us = [360.0 * i / 16 for i in range(16)]
    band_surface(mb, lambda phi, d, o: limb.pt(phi, d, o + 0.002), us, d_of, hw, off, role, w_of,
                 lambda phi, d: limb.centre(d), closed=True)


def build_cape(mb):
    """A half-cape from the hip band: open front, flaring, longest at the back,
    a scalloped hem. Hips weight at the top; the lower half shares the thighs
    on its side so a stride does not cut through it."""
    nu, nv = 22, 9
    us = [12.0 - (12.0 + 192.0) * i / (nu - 1) for i in range(nu)]    # left side, round the back, right side
    rows = []
    for j in range(nv):
        v = j / (nv - 1)
        row = []
        for i, th in enumerate(us):
            t = math.radians(th)
            back = max(0.0, -math.sin(t))
            hem = 1.235 - lerp(0.36, 0.80, back ** 0.8) - 0.04 * math.sin(i * 1.3)
            z = lerp(1.235, hem, v)
            zt = max(z, 1.10)
            base = torso_pt(th, min(zt, 1.24), 0.0)
            c = torso_centre(min(zt, 1.24))
            rdir = Vector((base.x - c.x, base.y - c.y, 0)).normalized()
            r = Vector((base.x - c.x, base.y - c.y, 0)).length + 0.020 + 0.30 * (1.235 - z) * (0.6 + 0.5 * back)
            fold = 0.012 * math.sin(i * 2.1) * v
            p = V(c.x, c.y, z) + rdir * (r + fold)
            w = {"hips": 1.0}
            kt = 0.55 * ss(1.19, 0.68, z)
            if kt > 1e-3:
                x = p.x
                kl = ss(-0.12, 0.12, x)
                w = {"hips": 1 - kt, "thigh_l": kt * kl, "thigh_r": kt * (1 - kl)}
            row.append(mb.add(p, w, "cape"))
        rows.append(row)
    mb.grid(rows, lambda i, k: "cape", lambda i, k: torso_centre(1.19) + V(0, -0.02, 0), closed=False)


def build_greave(mb, leg, side, s, lw):
    sn, th = "shin_" + side, "thigh_" + side
    us = [360.0 * i / 10 + 9.0 for i in range(10)]
    rows_d = [0.555, 0.60, 0.67, 0.75, 0.83, 0.91, 0.98, 1.05]
    patch(mb, lambda phi, d, off: leg.pt(phi, d, off), us, lambda phi: rows_d,
          lambda phi, d: (0.010 + 0.028 * ss(0.68, 0.555, d) + 0.007 * gauss(d, 0.75, 0.05)
                          + 0.016 * max(0.0, math.sin(math.radians(phi))) ** 8),      # a keel down the shin
          "armor", lambda phi, d: leg.centre(d), lambda p: nearest_weights(mb, KD, ["leg_" + side], p), closed=True, flat=True)
    # a cuff ridge at the top and a strap round the calf
    band_limb(mb, leg, lambda phi: 0.585, 0.010, 0.040, "armor", lw)
    band_limb(mb, leg, lambda phi: 0.80, 0.010, 0.020, "leather", lw)
    # knee star: a dome on the knee and radiating spikes
    p, t, lat, fwd = leg.frame(0.545)
    kc = p + fwd * 0.045
    kw = {sn: 0.8, th: 0.2}
    up = -t
    mb.ellipsoid(kc, V(0.070, 0.052, 0.080), lambda q: kw, "armor", seg=8, rings=5,
                 keep=lambda q: q.y > -0.3, axes=(lat, fwd, up), flat=True)
    # an eight-point star round the knee: the long points up and out
    for k in range(8):
        a = math.radians(90 + k * 45.0)
        dirn = (lat * math.cos(a) + up * math.sin(a)).normalized()
        base = kc + fwd * 0.026 + dirn * 0.040
        length = (0.125 if k in (0, 7, 1) else 0.095) if k not in (4,) else 0.07
        tip = base + (dirn * 0.82 + fwd * 0.42).normalized() * length
        mb.cone(base, tip, 0.028, kw, "armor", sides=5)
    # a spike off the greave's shin and the calf flare
    for d, ln in ((0.70, 0.06), (0.86, 0.05)):
        q, t2, lat2, fwd2 = leg.frame(d)
        base = leg.pt(90.0, d, 0.012)
        mb.cone(base, base + (fwd2 * 0.7 - t2 * 0.7).normalized() * ln, 0.016, {sn: 1.0}, "armor", sides=4)
    for sgn_ in (1, -1):
        d = 0.64
        base = leg.pt(0.0 if sgn_ > 0 else 180.0, d, 0.02)
        q, t2, lat2, fwd2 = leg.frame(d)
        mb.cone(base, base + (lat2 * sgn_ * 0.8 - t2 * 0.6).normalized() * 0.07, 0.02, {sn: 1.0}, "armor", sides=4)


def build_boot(mb, side, s):
    """An armoured pointed boot round the foot bone (sole flat on z = 0)."""
    hip, knee, ankle, toe = leg_points(s)
    sn, ft = "shin_" + side, "foot_" + side
    rows_def = [(0.062, 0.030, 0.105), (0.040, 0.040, 0.140), (0.010, 0.043, 0.150), (-0.03, 0.046, 0.128),
                (-0.075, 0.047, 0.098), (-0.12, 0.042, 0.072), (-0.16, 0.034, 0.052), (-0.195, 0.022, 0.036),
                (-0.225, 0.006, 0.022)]
    n = 8
    rows, cs = [], []
    v0 = len(mb.verts)
    for y, hw, ht in rows_def:
        c = V(ankle.x, y, ht * 0.5)
        cs.append(c)
        row = []
        for k in range(n):
            a = 2 * math.pi * k / n
            x = hw * sgnpow(math.cos(a), 0.8)
            z = ht * 0.5 + ht * 0.5 * sgnpow(math.sin(a), 0.8)
            p = V(ankle.x + x, y, max(0.0, z))
            kf = ss(0.03, -0.05, y)
            w = {ft: kf, sn: 1 - kf} if 0 < kf < 1 else ({ft: 1.0} if kf >= 1 else {sn: 1.0})
            row.append(mb.add(p, w, "armor"))
        rows.append(row)
    mb.grid(rows, lambda i, k: "armor", lambda i, k: (cs[i] + cs[i + 1]) * 0.5, closed=True)
    e0 = mb.add(cs[0] + V(0, 0.01, 0), {sn: 1}, "armor")
    mb.fan(rows[0], e0, "armor", cs[1])
    e1 = mb.add(cs[-1] + V(0, -0.008, 0), {ft: 1}, "armor")
    mb.fan(rows[-1], e1, "armor", cs[-2])
    mb.flat.update(range(v0, len(mb.verts)))           # H232: faceted boot


def build_pauldron(mb, arm, side, s):
    """The big dark spiked pauldron on the left shoulder: a dome, two lames
    below it round the upper arm, a row of spikes along the top."""
    ua, so = "upper_arm_" + side, "shoulder_" + side
    sh = arm.pts[0]
    out = V(s * 0.62, 0, 0.78).normalized()
    fwd = V(0, -1, 0)
    side_ax = out.cross(fwd).normalized()
    w = {ua: 0.65, so: 0.35}
    c = sh + out * 0.02 + V(0, 0.004, 0)
    mb.ellipsoid(c, V(0.155, 0.152, 0.132), lambda q: w, "armor", seg=10, rings=6,
                 keep=lambda q: q.z > -0.22, axes=(side_ax, fwd, out), flat=True)
    # a second, raised plate over the top: the layered read
    mb.ellipsoid(c + out * 0.045 - V(s, 0, 0) * 0.02, V(0.118, 0.130, 0.102), lambda q: w, "armor", seg=10, rings=5,
                 keep=lambda q: q.z > 0.05, axes=(side_ax, fwd, out), flat=True)
    # lames: partial bands round the arm's outer side below the dome
    for k, (dd, rr) in enumerate(((0.10, 0.075), (0.15, 0.062), (0.195, 0.05))):
        us = [360.0 * i / 12 for i in range(-4, 5)]
        lam = []
        v0 = len(mb.verts)
        for row_off in (0.0, 0.038):
            lam.append([mb.add(arm.pt(u, dd + row_off - 0.019, rr - row_off * 0.4), {ua: 1.0}, "armor") for u in us])
        for i in range(len(us) - 1):
            mb.face((lam[0][i], lam[0][i + 1], lam[1][i + 1], lam[1][i]), "armor", arm.centre(dd))
        mb.flat.update(range(v0, len(mb.verts)))
    # spikes along the top ridge, raking back and out, and two off the outer rim
    for k, (u, ln) in enumerate(((-0.7, 0.09), (-0.35, 0.13), (0.0, 0.15), (0.35, 0.13), (0.7, 0.09))):
        base = c + out * 0.13 + fwd * (u * 0.12)
        tip = base + (out * 0.9 + fwd * (u * 0.45) + V(s * 0.3, 0, 0.1)).normalized() * ln
        mb.cone(base, tip, 0.028, w, "armor", sides=5)
    for u in (-0.6, 0.6):
        base = c + side_ax * 0.0 + fwd * (u * 0.13) + V(s, 0, 0) * 0.12 - out * 0.02
        tip = base + (V(s, 0, -0.35) + fwd * u * 0.5).normalized() * 0.08
        mb.cone(base, tip, 0.024, w, "armor", sides=5)


def build_cap(mb, arm, side, s):
    """H230: a small faceted cap on the weapon shoulder (the pauldron's lesser
    twin), one lame, two short spikes."""
    ua, so = "upper_arm_" + side, "shoulder_" + side
    sh = arm.pts[0]
    out = V(s * 0.62, 0, 0.78).normalized()
    fwd = V(0, -1, 0)
    side_ax = out.cross(fwd).normalized()
    w = {ua: 0.65, so: 0.35}
    c = sh + out * 0.015
    mb.ellipsoid(c, V(0.108, 0.106, 0.092), lambda q: w, "armor", seg=9, rings=5,
                 keep=lambda q: q.z > -0.2, axes=(side_ax, fwd, out), flat=True)
    us = [360.0 * i / 12 for i in range(-3, 4)]
    v0 = len(mb.verts)
    lam = [[mb.add(arm.pt(u, 0.085 + ro - 0.017, 0.045 - ro * 0.4), {ua: 1.0}, "armor") for u in us] for ro in (0.0, 0.034)]
    for i in range(len(us) - 1):
        mb.face((lam[0][i], lam[0][i + 1], lam[1][i + 1], lam[1][i]), "armor", arm.centre(0.085))
    mb.flat.update(range(v0, len(mb.verts)))
    for u, ln in ((-0.35, 0.06), (0.35, 0.06)):
        base = c + out * 0.085 + fwd * (u * 0.09)
        mb.cone(base, base + (out * 0.9 + fwd * u * 0.4 + V(s * 0.3, 0, 0)).normalized() * ln, 0.02, w, "armor", sides=4)


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
    bsdf.inputs["Roughness"].default_value = 0.6
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
        tot = sum(v for v in w.values() if v > 1e-6) or 1.0
        # keep the four strongest (glTF influence count), renormalised
        top = sorted(((v, b) for b, v in w.items() if v > 1e-6), reverse=True)[:4]
        tot = sum(v for v, _ in top) or 1.0
        for v, bone in top:
            mesh_obj.vertex_groups[bone].add([i], v / tot, 'REPLACE')
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

KD = {}


def make_kd(mb, groups):
    out = {}
    for g, ids in groups.items():
        kd = kdtree.KDTree(len(ids))
        for j, i in enumerate(ids):
            kd.insert(mb.verts[i], j)
        kd.balance()
        out[g] = (kd, ids)
    return out


# ----------------------------------------------------------------- main
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scn = bpy.context.scene
    scn.unit_settings.system = 'METRIC'

    materials = [(r, make_material(r, ROLES[r])) for r in ROLES]
    rig = build_armature()
    mb = MeshBuilder()
    groups = {}
    limbs = build_body(mb, groups)
    KD.update(make_kd(mb, groups))
    build_hair(mb)
    build_outfit(mb, limbs, KD, groups)
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
        "tint_roles": ["suit", "cape"],
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
    print("JSON", JSON_OUT, "tris", row["tris"], "verts", nverts, tris)


main()
