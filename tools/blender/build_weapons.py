"""Hexhunt weapons (Lane A, H4): the three kickoff weapons plus the bow's arrow,
built from nothing. Black | White's build_weapons.py pattern (WeaponMesh,
weapon space, the manifest contract), reduced to this roster and recoloured.

    blender -b --factory-startup --python tools/blender/build_weapons.py
    blender -b --factory-startup --python tools/blender/build_weapons.py -- --only karambit,bow

Writes (never hand-edit these; change this script and rebuild):
    art/weapons/<id>.glb          one rigid weapon: a MeshInstance3D per material role
    art/weapons/karambit_l.glb    the off-hand karambit, mirrored in x
    art/weapons/weapons.json      the manifest: hands, socket, mount, second_hand, tip,
                                  trail_base, aura_points, string (bow), length, aabb, tris
    art/weapons/blend/weapons.blend  every weapon in a row with its markers as empties
                                  (reference only; a .gdignore keeps Godot off it)

Conventions (Black | White's, unchanged so Lane B's sockets and clips line up):
  * The grip is the ORIGIN: the centre of the fist that holds it.
  * Modelled in "weapon space" (x, f, u): x = the wielder's left, f = forward
    (the edge / arrow direction), u = up the blade or shaft. Blender = (x, -f, u);
    the glTF +Y-up export makes that Godot (x, u, f): blade along +Y, edge +Z.
  * Look: lit, low poly, vertex COLOR carries the palette per face; the material
    slot names the ROLE (steel, wood, wrap, feather, gem, string) so the game
    can swap materials by role (HHMonsterBody.material_for does the same for
    monsters). Smooth normals per island.
  * Deterministic: no randomness, fixed order, fixed sampling.

The roster (design/kickoff: "glaive style lance, dual daggers, bow"; "The
karambit should be sword sized and big"):
    lance      two hands: a 2.8 m pole with a glaive head (weapon_glaive.png):
               a long single-edged blade curving to a swept tip, wavy back spur.
    karambit   a pair (one per hand, the left one mirrored): a sword-sized claw
               blade ~0.9 m along its arc, edge on the inner curve, ridged grip,
               finger ring at the butt (weapon_karambit.jpg).
    bow        left hand: a 1.6 m winged recurve (weapon_bow.jpg): gold riser with
               red heart gems, limbs that recurve forward, white feather wings
               fanning off each limb, a straight string with a "string" marker pair.
    arrow      the bow's projectile: shaft, slim steel head, three feather vanes.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

# ----------------------------------------------------------------- paths
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "art", "weapons")
JSON_OUT = os.path.join(OUT_DIR, "weapons.json")
BLEND_DIR = os.path.join(OUT_DIR, "blend")
BLEND_OUT = os.path.join(BLEND_DIR, "weapons.blend")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

WEAPONS_VERSION = 1   # bump when grip convention, metadata keys or ids change
RIG_VERSION = 1       # the player rig these are fitted to (2.2 m, HHLook.RIG_HEIGHT)

# ----------------------------------------------------------- material roles
# One Blender material (= one Godot surface) per role. The COLOR attribute
# carries the actual tint per face, so a role can hold several colours
# (the bow's riser is gold on the steel role; the karambit's blade flats are
# violet crystal on the gem role).
STEEL, WOOD, WRAP, FEATHER, GEM, STRING = range(6)
ROLE_NAMES = ["steel", "wood", "wrap", "feather", "gem", "string"]
ROLE_RGB = {   # the material's viewport colour and the default face colour of the role
    "steel": (0.78, 0.80, 0.85),
    "wood": (0.46, 0.30, 0.17),
    "wrap": (0.14, 0.12, 0.12),
    "feather": (0.95, 0.95, 0.97),
    "gem": (0.82, 0.14, 0.20),
    "string": (0.90, 0.88, 0.80),
}
# palette (sRGB intent, baked into COLOR)
C_STEEL = (0.78, 0.80, 0.85)
C_STEEL_DARK = (0.50, 0.53, 0.60)
C_EDGE = (0.95, 0.96, 1.00)       # the bevel band along a cutting edge: brightest
C_WOOD = (0.46, 0.30, 0.17)
C_WRAP = (0.14, 0.12, 0.12)
C_WRAP_RIDGE = (0.24, 0.21, 0.20)
C_GOLD = (0.86, 0.66, 0.24)
C_GOLD_DARK = (0.62, 0.45, 0.14)
C_RED = (0.82, 0.14, 0.20)
C_VIOLET = (0.42, 0.32, 0.86)     # the karambit's crystal blade (reference: blue-violet)
C_VIOLET_DEEP = (0.28, 0.20, 0.64)
C_FEATHER = (0.95, 0.95, 0.97)
C_FEATHER_SHADE = (0.80, 0.82, 0.88)
C_QUILL = (0.70, 0.62, 0.50)
C_STRING = (0.90, 0.88, 0.80)


def deg(a):
    return math.radians(a)


# ------------------------------------------------------------ builder
class WeaponMesh:
    """Collects islands in weapon space (x, f, u) and emits one Blender mesh
    with one material slot per role. Faces carry their own RGB (corner colour)."""

    def __init__(self):
        self.verts = []
        self.faces = []   # (indices, mat, rgb)
        self.string = None

    def v(self, p):
        self.verts.append(Vector(p))
        return len(self.verts) - 1

    def face(self, idx, mat, rgb):
        out = []
        for i in idx:
            if not out or out[-1] != i:
                out.append(i)
        if len(out) > 1 and out[0] == out[-1]:
            out.pop()
        if len(out) >= 3:
            self.faces.append((tuple(out), mat, rgb))

    # -- tubes, cones, rings ------------------------------------------
    def tube(self, pts, radii, sides=6, rgb=C_STEEL, mat=STEEL, closed=False, ref=(1, 0, 0), phase=0.5):
        """Tube along a polyline; radius 0 at an end makes a cone apex.
        Parallel-transported ring frames, ngon caps."""
        pts = [Vector(p) for p in pts]
        if isinstance(radii, (int, float)):
            radii = [radii] * len(pts)
        n = len(pts)
        tans = []
        for i in range(n):
            if closed:
                t = pts[(i + 1) % n] - pts[i - 1]
            elif i == 0:
                t = pts[1] - pts[0]
            elif i == n - 1:
                t = pts[-1] - pts[-2]
            else:
                t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
            tans.append(t.normalized())
        ref = Vector(ref)
        if abs(ref.dot(tans[0])) > 0.9:
            ref = Vector((0, 1, 0)) if abs(tans[0].y) < 0.9 else Vector((0, 0, 1))
        nrm = None
        rings = []
        for c, t, r in zip(pts, tans, radii):
            nrm = (ref if nrm is None else nrm)
            nrm = (nrm - t * nrm.dot(t)).normalized()
            b = t.cross(nrm)
            if r <= 1e-6:
                rings.append([self.v(c)])
                continue
            rings.append([self.v(c + (nrm * math.cos(a) + b * math.sin(a)) * r)
                          for a in (2 * math.pi * (k + phase) / sides for k in range(sides))])
        pairs = list(zip(rings, rings[1:]))
        if closed:
            pairs.append((rings[-1], rings[0]))
        for r0, r1 in pairs:
            if len(r0) == 1 and len(r1) == 1:
                continue
            if len(r0) == 1:
                for k in range(sides):
                    self.face((r0[0], r1[k], r1[(k + 1) % sides]), mat, rgb)
            elif len(r1) == 1:
                for k in range(sides):
                    self.face((r0[k], r0[(k + 1) % sides], r1[0]), mat, rgb)
            else:
                for k in range(sides):
                    k2 = (k + 1) % sides
                    self.face((r0[k], r0[k2], r1[k2], r1[k]), mat, rgb)
        if not closed:
            if len(rings[0]) > 1:
                self.face(tuple(reversed(rings[0])), mat, rgb)
            if len(rings[-1]) > 1:
                self.face(tuple(rings[-1]), mat, rgb)

    def ring(self, center, radius, tube_r, axis="x", segs=8, sides=5, rgb=C_STEEL, mat=STEEL):
        c = Vector(center)
        pts = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            if axis == "x":      # ring lies in the (f, u) plane
                pts.append(c + Vector((0, math.cos(a), math.sin(a))) * radius)
            else:                # ring lies in the (x, f) plane
                pts.append(c + Vector((math.cos(a), math.sin(a), 0)) * radius)
        self.tube(pts, tube_r, sides=sides, rgb=rgb, mat=mat, closed=True,
                  ref=(1, 0, 0) if axis == "x" else (0, 0, 1))

    def ellipsoid(self, center, radii, sides=6, rings=4, rgb=C_STEEL, mat=STEEL):
        c = Vector(center)
        rx, rf, ru = radii if isinstance(radii, (tuple, list)) else (radii,) * 3
        top = self.v(c + Vector((0, 0, ru)))
        lat = []
        for i in range(1, rings):
            th = math.pi * i / rings
            lat.append([self.v(c + Vector((rx * math.sin(th) * math.cos(2 * math.pi * (j + 0.5) / sides),
                                           rf * math.sin(th) * math.sin(2 * math.pi * (j + 0.5) / sides),
                                           ru * math.cos(th)))) for j in range(sides)])
        bot = self.v(c - Vector((0, 0, ru)))
        for j in range(sides):
            k = (j + 1) % sides
            self.face((top, lat[0][j], lat[0][k]), mat, rgb)
            self.face((bot, lat[-1][k], lat[-1][j]), mat, rgb)
        for i in range(len(lat) - 1):
            for j in range(sides):
                k = (j + 1) % sides
                self.face((lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k]), mat, rgb)

    # -- boxes ---------------------------------------------------------
    def hexa(self, c8, rgb=C_STEEL, mat=STEEL):
        """8 corners: bottom quad then top quad, same winding."""
        i = [self.v(p) for p in c8]
        for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face(tuple(i[k] for k in f), mat, rgb)

    def box(self, center, half, rgb=C_STEEL, mat=STEEL):
        cx, cf, cu = center
        hx, hf, hu = half
        bot = [(cx - hx, cf - hf, cu - hu), (cx + hx, cf - hf, cu - hu), (cx + hx, cf + hf, cu - hu), (cx - hx, cf + hf, cu - hu)]
        top = [(x, f, cu + hu) for x, f, _ in bot]
        self.hexa(bot + top, rgb, mat)

    # -- bevelled plates (blades, feathers, the riser) ------------------
    def plate(self, outline, h, bevel=0.02, edges=(), rgb=C_STEEL, edge_rgb=C_EDGE,
              o=(0, 0, 0), A=(0, 1, 0), B=(0, 0, 1), N=(1, 0, 0), blunt=0.75, mat=STEEL, edge_mat=STEEL):
        """A 2D outline (a, b) extruded to half-thickness h along N, with a
        bevel band of width `bevel` all round. Segment i runs from point i to
        i+1; segments listed in `edges` are cutting edges: their bevel faces
        take `edge_rgb` on `edge_mat` and their rim closes to a sharp edge."""
        pts = [Vector(p) for p in outline]
        n = len(pts)
        edge = [i in edges for i in range(n)]
        area = sum(pts[i].x * pts[(i + 1) % n].y - pts[(i + 1) % n].x * pts[i].y for i in range(n))
        if area < 0:
            pts = pts[::-1]
            edge = [edge[(n - 2 - j) % n] for j in range(n)]
        o, A, B, N = Vector(o), Vector(A), Vector(B), Vector(N)

        def P(a, b, w):
            return o + A * a + B * b + N * w

        ins = []
        for i in range(n):
            ep = (pts[i] - pts[i - 1]).normalized()
            en = (pts[(i + 1) % n] - pts[i]).normalized()
            npv = Vector((-ep.y, ep.x))
            nnv = Vector((-en.y, en.x))
            bis = npv + nnv
            bis = nnv if bis.length < 1e-6 else bis.normalized()
            m = min(bevel / max(bis.dot(nnv), 0.3), bevel * 2.4)
            ins.append(pts[i] + bis * m)
        sharp = [edge[i - 1] or edge[i] for i in range(n)]
        he = [0.0 if s else h * blunt for s in sharp]
        tq = [self.v(P(q.x, q.y, h)) for q in ins]
        bq = [self.v(P(q.x, q.y, -h)) for q in ins]
        tp, bp = [], []
        for p, e in zip(pts, he):
            t = self.v(P(p.x, p.y, e))
            tp.append(t)
            bp.append(t if e == 0.0 else self.v(P(p.x, p.y, -e)))
        for tri in tessellate_polygon([[Vector((q.x, q.y, 0)) for q in ins]]):
            a, b, c = tri
            self.face((tq[a], tq[b], tq[c]), mat, rgb)
            self.face((bq[c], bq[b], bq[a]), mat, rgb)
        for i in range(n):
            j = (i + 1) % n
            m, cv = (edge_mat, edge_rgb) if edge[i] else (mat, rgb)
            self.face((tp[i], tp[j], tq[j], tq[i]), m, cv)
            self.face((bp[j], bp[i], bq[i], bq[j]), m, cv)
            self.face((tp[i], bp[i], bp[j], tp[j]), m, cv)

    def vane(self, outline, h, rgb, o=(0, 0, 0), A=(0, 1, 0), B=(0, 0, 1), N=(1, 0, 0), mat=FEATHER):
        """A cheap flat leaf: the outline as a top and a bottom face 2h apart
        with a rim strip between them, no bevel (feathers, fletching)."""
        pts = [Vector(p) for p in outline]
        n = len(pts)
        area = sum(pts[i].x * pts[(i + 1) % n].y - pts[(i + 1) % n].x * pts[i].y for i in range(n))
        if area < 0:
            pts = pts[::-1]
        o, A, B, N = Vector(o), Vector(A), Vector(B), Vector(N)
        top = [self.v(o + A * p.x + B * p.y + N * h) for p in pts]
        bot = [self.v(o + A * p.x + B * p.y - N * h) for p in pts]
        for a, b, c in tessellate_polygon([[Vector((p.x, p.y, 0)) for p in pts]]):
            self.face((top[a], top[b], top[c]), mat, rgb)
            self.face((bot[c], bot[b], bot[a]), mat, rgb)
        for i in range(n):
            j = (i + 1) % n
            self.face((top[i], bot[i], bot[j], top[j]), mat, rgb)

    # -- emit -----------------------------------------------------------
    def build(self, name, materials):
        """One Blender mesh PER ROLE (rigkit's way): Blender 5.2's glTF
        exporter only keeps vertex colours on a mesh's first primitive, so a
        multi-material mesh would lose every role but the first. Returns
        [(role, mesh)] in role order; Godot sees one MeshInstance3D per role."""
        out = []
        # a vertex takes the colour of the first face that uses it, so a
        # plate's inner quad keeps the flat colour and its rim takes the edge
        vcol = [None] * len(self.verts)
        for idx, _, rgb in self.faces:
            for i in idx:
                if vcol[i] is None:
                    vcol[i] = rgb
        for mi, mat in enumerate(materials):
            faces = [f for f, m, _ in self.faces if m == mi]
            if not faces:
                continue
            remap = {}
            verts = []
            colors = []
            new_faces = []
            for f in faces:
                nf = []
                for vi in f:
                    if vi not in remap:
                        remap[vi] = len(verts)
                        p = self.verts[vi]
                        verts.append((p.x, -p.y, p.z))
                        colors.append(vcol[vi] or (1.0, 1.0, 1.0))
                    nf.append(remap[vi])
                new_faces.append(tuple(nf))
            me = bpy.data.meshes.new("%s_%s" % (name, ROLE_NAMES[mi]))
            me.from_pydata(verts, [], new_faces)
            me.materials.append(mat)
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
            for p in me.polygons:
                p.use_smooth = True
            # the palette is authored as displayed (sRGB) colour
            col = me.color_attributes.new("Color", 'BYTE_COLOR', 'POINT')
            for i, c in enumerate(colors):
                col.data[i].color_srgb = (c[0], c[1], c[2], 1.0)
            me.color_attributes.active_color = col
            me.color_attributes.render_color_index = 0
            me.update()
            out.append((ROLE_NAMES[mi], me))
        return out


# shared pieces ----------------------------------------------------------
def grip(w, u0, u1, r=0.026, rgb=C_WRAP, sides=6):
    w.tube([(0, 0, u0), (0, 0, u1)], [r, r * 0.94], sides=sides, rgb=rgb, mat=WRAP)


def ridged_grip(w, u0, u1, r=0.03, n=6, sides=7):
    """A wrapped grip with raised ridges (the karambit reference's textured handle)."""
    w.tube([(0, 0, u0), (0, 0, u1)], r, sides=sides, rgb=C_WRAP, mat=WRAP)
    for k in range(n):
        u = u0 + (u1 - u0) * (k + 0.5) / n
        w.tube([(0, 0, u - 0.009), (0, 0, u + 0.009)], r * 1.08, sides=sides, rgb=C_WRAP_RIDGE, mat=WRAP, phase=0.0)


def haft(w, u0, u1, r, rgb=C_WOOD, sides=6):
    w.tube([(0, 0, u0), (0, 0, u1)], [r, r * 0.92], sides=sides, rgb=rgb, mat=WOOD)


def rot2(p, ang):
    c, s = math.cos(ang), math.sin(ang)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


def feather(w, base, angle_deg, length, width, x=0.0, rgb=C_FEATHER, h=0.004):
    """A feather vane in the (f, u) plane: its quill root at `base` (f, u),
    pointing `angle_deg` from +u toward +f (negative = toward the back, -f).
    A tapered six-point vane with a quill line down its middle, rendered
    double-sided by the FEATHER material (cull off in the game)."""
    bf, bu = base
    ang = deg(angle_deg)
    vane = [(0.0, 0.0), (width * 0.55, length * 0.18), (width * 0.5, length * 0.62), (0.0, length),
            (-width * 0.5, length * 0.62), (-width * 0.55, length * 0.18)]
    pts = []
    for a, b in vane:
        # local (a across, b along) -> (f, u): along = (sin ang, cos ang), across = (cos ang, -sin ang)
        f = bf + a * math.cos(ang) + b * math.sin(ang)
        u = bu - a * math.sin(ang) + b * math.cos(ang)
        pts.append((f, u))
    w.vane(pts, h=h, rgb=rgb, o=(x, 0, 0))
    # the quill: a thin tube from the root to two thirds up
    tipf = bf + length * 0.7 * math.sin(ang)
    tipu = bu + length * 0.7 * math.cos(ang)
    w.tube([(x, bf, bu), (x, tipf, tipu)], [0.006, 0.003], sides=3, rgb=C_QUILL, mat=FEATHER)


# ------------------------------------------------------------ weapons
# Each builder fills a WeaponMesh and returns its markers in weapon space
# (x, f, u): tip / trail_base (the trail ribbon), second (the other hand's
# target), aura (particle anchors along the business end).

def build_lance(w):
    """Glaive-headed lance (weapon_glaive.png): a long pole, the right fist at
    the origin, the left hand 0.5 m up; a single-edged blade that widens off
    the socket, curves to a swept-back tip and carries a wavy spur on its
    back. The edge is the forward (+f) curve."""
    haft(w, -0.52, 1.40, 0.027)
    w.ellipsoid((0, 0, -0.54), (0.036, 0.036, 0.05), sides=6, rings=3, rgb=C_STEEL_DARK)      # butt cap
    grip(w, -0.10, 0.10, r=0.031)
    grip(w, 0.40, 0.60, r=0.031)
    w.tube([(0, 0, 1.32), (0, 0, 1.40), (0, 0, 1.52)], [0.030, 0.040, 0.034], sides=8, rgb=C_STEEL_DARK)   # socket collar
    w.tube([(0, 0, 1.52), (0, 0, 1.60)], [0.034, 0.026], sides=8, rgb=C_STEEL)                              # the tang collar
    # langets: two straps down the haft under the socket
    for s in (1, -1):
        w.box((0, s * 0.03, 1.22), (0.012, 0.006, 0.12), rgb=C_STEEL_DARK)
    # the blade (weapon_glaive.png): the back (-f) rises off the socket into a
    # flared wavy spur, then runs concave up to a tip that sweeps BACK over
    # the spine; the edge (+f) is one long convex belly, 0.32 m at its widest
    spine = [(-0.040, 1.56), (-0.035, 1.66), (-0.200, 1.70), (-0.140, 1.78), (-0.225, 1.84), (-0.120, 1.905),
             (-0.085, 2.02), (-0.075, 2.16), (-0.095, 2.30), (-0.145, 2.42), (-0.230, 2.52)]
    tip = [(-0.300, 2.58)]
    edge = [(-0.150, 2.53), (0.000, 2.46), (0.130, 2.34), (0.215, 2.16), (0.240, 1.96), (0.205, 1.76),
            (0.125, 1.61), (0.050, 1.56)]
    pts = spine + tip + edge
    n_spine = len(spine)
    cutting = tuple(range(n_spine, n_spine + len(tip) + len(edge) - 1))       # the tip and the whole +f belly
    w.plate(pts, h=0.011, bevel=0.024, edges=cutting, rgb=C_STEEL, edge_rgb=C_EDGE)
    # a fuller following the belly, a thin darker inset
    w.plate([(0.010, 1.66), (0.045, 1.66), (0.120, 1.96), (0.095, 2.26), (0.065, 2.26), (0.085, 1.96)],
            h=0.0125, bevel=0.005, rgb=C_STEEL_DARK, blunt=1.0)
    return dict(tip=(0, -0.30, 2.58), trail_base=(0, 0.02, 1.60), second=(0, 0, 0.50),
                aura=[(0, 0.14, 1.70), (0, 0.22, 1.96), (0, 0.19, 2.22), (0, 0.06, 2.44), (0, -0.22, 2.55), (0, -0.19, 1.80)])


def build_karambit(w):
    """Sword-sized karambit (weapon_karambit.jpg, kickoff: "sword sized and
    big"): a ridged black grip round the fist, a steel finger ring at the
    butt, a bolster, then a claw blade ~0.9 m along its arc that rises off
    the grip and hooks forward (+f) to the point. The edge is the INNER
    (concave, +f-facing) curve; the flats are violet crystal (gem role) with
    a bright steel bevel along the edge."""
    ridged_grip(w, -0.17, 0.17, r=0.030, n=9)
    w.tube([(0, 0, -0.17), (0, 0, -0.20)], [0.034, 0.030], sides=7, rgb=C_STEEL_DARK)          # butt ferrule
    w.ring((0, 0, -0.265), 0.062, 0.014, axis="x", segs=10, sides=5, rgb=C_STEEL)              # finger ring
    w.tube([(0, 0, 0.17), (0, 0, 0.215)], [0.036, 0.040], sides=7, rgb=C_STEEL_DARK)            # bolster
    w.tube([(0, 0.0, 0.215), (0, 0.0, 0.235)], [0.044, 0.034], sides=7, rgb=C_STEEL)
    # blade outline (f, u): 0.16 m wide at the bolster, the back (convex, -f)
    # rising and rolling forward over the top to the point; the inner edge
    # (concave, +f) back down to the bolster. About 110 degrees of hook.
    back = [(-0.075, 0.23), (-0.095, 0.40), (-0.070, 0.58), (0.010, 0.74), (0.130, 0.86), (0.290, 0.925),
            (0.450, 0.905), (0.570, 0.835)]
    point = [(0.660, 0.715)]
    inner = [(0.560, 0.715), (0.440, 0.760), (0.300, 0.770), (0.180, 0.715), (0.115, 0.610), (0.095, 0.480),
             (0.095, 0.350), (0.095, 0.23)]
    pts = back + point + inner
    nb = len(back)
    cutting = tuple(range(nb, nb + len(point) + len(inner) - 1))
    w.plate(pts, h=0.013, bevel=0.028, edges=cutting, rgb=C_VIOLET, edge_rgb=C_EDGE, mat=GEM, edge_mat=STEEL)
    # a deeper-violet spine band along the back of the blade
    w.plate([(-0.060, 0.30), (-0.030, 0.30), (-0.010, 0.60), (0.080, 0.78), (0.290, 0.875), (0.480, 0.85),
             (0.480, 0.885), (0.290, 0.905), (0.060, 0.805), (-0.040, 0.62)],
            h=0.0145, bevel=0.005, rgb=C_VIOLET_DEEP, mat=GEM, blunt=1.0)
    return dict(tip=(0, 0.66, 0.715), trail_base=(0, -0.05, 0.40),
                aura=[(0, -0.05, 0.50), (0, 0.04, 0.72), (0, 0.22, 0.86), (0, 0.44, 0.85), (0, 0.62, 0.76)])


def build_bow(w):
    """Winged recurve (weapon_bow.jpg): held in the LEFT hand. A gold riser
    with red heart gems above and below the grip, limbs that sweep back
    (-f) and recurve forward at the tips, white feather wings fanning off
    each limb (the big ones outward, the small ones near the riser), a
    straight string behind (the archer's side, -f) with a marker pair.
    1.6 m tall."""
    # riser: a carved gold plate, waisted at the grip, with a red inlay stripe
    w.plate([(-0.040, -0.32), (0.040, -0.32), (0.075, -0.20), (0.055, -0.10), (0.055, 0.10), (0.075, 0.20),
             (0.040, 0.32), (-0.040, 0.32), (-0.065, 0.16), (-0.045, 0.0), (-0.065, -0.16)],
            h=0.030, bevel=0.014, rgb=C_GOLD)
    w.plate([(-0.012, -0.30), (0.012, -0.30), (0.012, -0.11), (-0.012, -0.11)], h=0.032, bevel=0.004, rgb=C_RED, mat=GEM, blunt=1.0)
    w.plate([(-0.012, 0.11), (0.012, 0.11), (0.012, 0.30), (-0.012, 0.30)], h=0.032, bevel=0.004, rgb=C_RED, mat=GEM, blunt=1.0)
    grip(w, -0.085, 0.085, r=0.040)
    # heart gems on the riser's front (+f) face, above and below the grip:
    # two lobes and a point, in a gold bezel
    for s in (1, -1):
        cu = s * 0.20
        w.ellipsoid((0, 0.070, cu), (0.055, 0.025, 0.060), sides=8, rings=3, rgb=C_GOLD_DARK)
        for lx in (-0.024, 0.024):
            w.ellipsoid((lx, 0.085, cu + s * 0.018), (0.027, 0.020, 0.027), sides=6, rings=3, rgb=C_RED, mat=GEM)
        w.tube([(0, 0.085, cu + s * 0.010), (0, 0.085, cu - s * 0.055)], [0.040, 0.0], sides=6, rgb=C_RED, mat=GEM)
    # gold scrolls where the limbs leave the riser
    for s in (1, -1):
        w.ring((0, -0.01, s * 0.33), 0.034, 0.012, axis="x", segs=8, sides=4, rgb=C_GOLD)
    # limbs: (f, u) from the riser, sweeping back then recurving forward hard
    limb = [(0.00, 0.30), (-0.05, 0.42), (-0.12, 0.54), (-0.18, 0.64), (-0.20, 0.72), (-0.17, 0.78), (-0.10, 0.815)]
    radii = [0.034, 0.030, 0.027, 0.024, 0.021, 0.018, 0.015]
    for s in (1, -1):
        w.tube([(0, f, s * u) for f, u in limb], radii, sides=6, rgb=C_GOLD)
        w.tube([(0, f - 0.012, s * u) for f, u in limb[1:5]], [0.012, 0.012, 0.011, 0.010], sides=4, rgb=C_RED, mat=GEM)   # red inlay down the limb
        w.ellipsoid((0, -0.10, s * 0.825), (0.020, 0.020, 0.026), sides=5, rings=3, rgb=C_RED, mat=GEM)   # tip gem
        # the wing: nine feathers off the limb's back, overlapping, the longest
        # past the tip, fanning from "outward beyond the tip" round to "straight back"
        spec = [  # (t along limb 0..1, angle from +u toward +f (negative = back), length, width, x offset)
            (0.98, 8.0, 0.30, 0.09, 0.000),
            (0.90, -8.0, 0.38, 0.11, 0.014),
            (0.80, -24.0, 0.46, 0.13, -0.014),
            (0.68, -40.0, 0.48, 0.13, 0.026),
            (0.56, -56.0, 0.45, 0.12, -0.026),
            (0.44, -70.0, 0.40, 0.11, 0.036),
            (0.32, -84.0, 0.33, 0.10, -0.036),
            (0.20, -98.0, 0.26, 0.09, 0.044),
            (0.08, -112.0, 0.20, 0.08, -0.044),
        ]
        for k, (t, ang, ln, wd, x) in enumerate(spec):
            i = min(int(t * (len(limb) - 1)), len(limb) - 2)
            kk = t * (len(limb) - 1) - i
            f = limb[i][0] + (limb[i + 1][0] - limb[i][0]) * kk - 0.02
            u = limb[i][1] + (limb[i + 1][1] - limb[i][1]) * kk
            a = ang if s > 0 else -(180.0 + ang)          # the lower wing mirrors: outward is -u
            rgb = C_FEATHER if k % 2 == 0 else C_FEATHER_SHADE
            feather(w, (f, s * u), a, ln, wd, x=x, rgb=rgb)
    # the string: short runs over the recurve tips (steel, stays put) and the
    # straight drawable run between them (its own surface + marker pair)
    _string(w, [(0, -0.10, 0.825), (0, -0.215, 0.72)], mat=STEEL)
    _string(w, [(0, -0.215, 0.72), (0, -0.215, -0.72)])
    _string(w, [(0, -0.215, -0.72), (0, -0.10, -0.825)], mat=STEEL)
    return dict(tip=(0, 0.08, 0.05), trail_base=(0, -0.215, 0.0), second=(0, -0.215, 0.0),
                aura=[(0, -0.10, 0.825), (0, -0.10, -0.825), (0, -0.14, 0.60), (0, -0.14, -0.60), (0, 0.085, 0.20), (0, 0.085, -0.20)])


def _string(w, pts, mat=STRING):
    w.tube(pts, 0.006, sides=3, rgb=C_STRING, mat=mat)
    if mat == STRING:
        w.string = (pts[0], pts[-1])


def build_arrow(w):
    """The bow's projectile. Origin = the shaft's middle, +u toward the head
    (so the arrow flies along +Y in Godot; HHFight points +Y down the flight
    line). Wood shaft, slim bright steel head, three white vanes, a nock."""
    L = 0.42
    w.tube([(0, 0, -L), (0, 0, L - 0.02)], 0.009, sides=6, rgb=C_WOOD, mat=WOOD)
    w.tube([(0, 0, L - 0.03), (0, 0, L + 0.01)], [0.012, 0.012], sides=6, rgb=C_STEEL_DARK)        # ferrule
    w.plate([(-0.030, L - 0.01), (0.030, L - 0.01), (0.034, L + 0.02), (0.016, L + 0.09), (0.0, L + 0.14),
             (-0.016, L + 0.09), (-0.034, L + 0.02)],
            h=0.006, bevel=0.009, edges=(2, 3, 4, 5), rgb=C_STEEL, edge_rgb=C_EDGE)                   # the head
    w.tube([(0, 0, -L - 0.03), (0, 0, -L)], [0.012, 0.010], sides=6, rgb=C_STEEL_DARK)                # nock
    for k in range(3):
        a = 2 * math.pi * k / 3
        w.vane([(0.0, -L + 0.02), (0.0, -L + 0.20), (0.045, -L + 0.15), (0.052, -L + 0.08), (0.036, -L + 0.02)],
               h=0.003, rgb=C_FEATHER if k else C_RED, mat=FEATHER if k else GEM,
               o=(0, 0, 0), A=(math.cos(a), math.sin(a), 0), B=(0, 0, 1), N=(-math.sin(a), math.cos(a), 0))
    return dict(tip=(0, 0, L + 0.14), trail_base=(0, 0, -L),
                aura=[(0, 0, L + 0.05), (0, 0, 0.0), (0, 0, -L + 0.1)])


WEAPONS = [
    # id, class, hands, builder, notes
    ("lance", "lance", "two", build_lance, "Glaive-headed lance: 2.8 m pole, single-edged curved blade with a wavy back spur (weapon_glaive.png)."),
    ("karambit", "daggers", "pair", build_karambit, "Sword-sized karambit: ridged grip, finger ring, ~0.9 m violet claw blade, edge on the inner curve (weapon_karambit.jpg); one per hand."),
    ("bow", "bow", "bow", build_bow, "Winged recurve: gold riser, red heart gems, feather wings off both limbs, straight string behind (weapon_bow.jpg)."),
    ("arrow", "projectile", "none", build_arrow, "The bow's arrow: wood shaft, steel head, three vanes; origin at the shaft's middle, +Y toward the head."),
]

PROJECTILE = {"bow": "arrow"}

HANDS = {
    # hands -> (socket, offhand socket, which hand the second point is for)
    "two": ("socket_weapon_r", None, "l"),
    "pair": ("socket_weapon_r", "socket_offhand_l", None),
    "bow": ("socket_offhand_l", None, "r"),
    "none": (None, None, None),
}

TRI_BUDGET = 1500


def gd(p):
    """weapon space (x, f, u) -> Godot (x, y=u, z=f), rounded."""
    return [round(p[0], 4), round(p[2], 4), round(p[1], 4)]


# ------------------------------------------------------------------ main
def make_material(role, rgb):
    """Plain PBR per role: Principled, white base x vertex COLOR (Godot
    multiplies albedo by COLOR_0 when the mesh carries one; the game swaps
    in HHMonsterBody.material_for-style materials by role name)."""
    m = bpy.data.materials.new(role)
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = {"steel": 0.35, "gem": 0.2, "wood": 0.8, "wrap": 0.9,
                                              "feather": 0.85, "string": 0.9}[role]
    bsdf.inputs["Metallic"].default_value = 0.6 if role == "steel" else 0.0
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    if role == "feather":
        m.use_backface_culling = False
    return m


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


def export_glb(objs, path):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
        export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_skins=False, export_animations=False, export_morph=False,
        export_cameras=False, export_lights=False, export_extras=False,
    )
    imp = path + ".import"
    if not os.path.exists(imp):
        with open(imp, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(IMPORT_STUB)


def role_counts(meshes):
    return {role: sum(len(p.vertices) - 2 for p in me.polygons) for role, me in meshes}


def link_objects(name, meshes, scn):
    """One object per role mesh, linked into the scene. Returns them."""
    objs = []
    for role, me in meshes:
        o = bpy.data.objects.new("%s_%s" % (name, role), me)
        scn.collection.objects.link(o)
        objs.append(o)
    return objs


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scn = bpy.context.scene
    only = None
    if "--only" in ARGS:
        only = set(ARGS[ARGS.index("--only") + 1].split(","))
    mats = [make_material(r, ROLE_RGB[r]) for r in ROLE_NAMES]
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(BLEND_DIR, exist_ok=True)
    gdignore = os.path.join(BLEND_DIR, ".gdignore")
    if not os.path.exists(gdignore):
        open(gdignore, "w").close()

    meta = {}
    if only and os.path.exists(JSON_OUT):
        with open(JSON_OUT, encoding="utf-8") as fh:
            meta = json.load(fh).get("weapons", {})
    lay_x = 0.0
    for wid, wclass, hands, fn, notes in WEAPONS:
        if only and wid not in only:
            continue
        wm = WeaponMesh()
        pts = fn(wm)
        meshes = wm.build(wid, mats)
        objs = link_objects(wid, meshes, scn)
        counts = role_counts(meshes)
        tris = sum(counts.values())
        xs = [v.x for v in wm.verts]
        fs = [v.y for v in wm.verts]
        us = [v.z for v in wm.verts]
        lo, hi = gd((min(xs), min(fs), min(us))), gd((max(xs), max(fs), max(us)))
        socket, off_socket, second_hand = HANDS[hands]
        entry = {
            "class": wclass,
            "hands": hands,
            "socket": socket,
            "offhand_socket": off_socket,
            "mount": {"position": [0.0, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0]},
            "second_hand": ({"hand": second_hand, "point": gd(pts["second"])} if second_hand else None),
            "tip": gd(pts["tip"]),
            "trail_base": gd(pts["trail_base"]),
            "aura_points": [gd(p) for p in pts["aura"]],
            "length": round(max(us) - min(us), 3),
            "aabb": {"min": lo, "max": hi},
            "scale": 1.0,
            "tris": tris,
            "roles": sorted(role for role, _ in meshes),   # one MeshInstance3D per role (Godot orders them by name)
            "role_tris": counts,
            "glb": "res://art/weapons/%s.glb" % wid,
            "projectile": PROJECTILE.get(wclass),
            "notes": notes,
        }
        if wm.string:
            # the drawable string's ends (Godot weapon space): Lane B hides the
            # "string" surface and draws it bent to the draw hand
            entry["string"] = [gd(wm.string[0]), gd(wm.string[1])]
        if tris > TRI_BUDGET:
            raise SystemExit("%s: %d tris over the %d budget" % (wid, tris, TRI_BUDGET))
        objs_l = []
        if hands == "pair":
            # the left hand's piece: the same mesh mirrored in x, its own glb
            # (a negative-scale copy would flip the winding)
            wl = WeaponMesh()
            wl.verts = [Vector((-p.x, p.y, p.z)) for p in wm.verts]
            wl.faces = [(tuple(reversed(f)), m, c) for f, m, c in wm.faces]
            objs_l = link_objects(wid + "_l", wl.build(wid + "_l", mats), scn)
            entry["offhand_glb"] = "res://art/weapons/%s_l.glb" % wid
            entry["mirror_offhand"] = True
        meta[wid] = entry
        print("WEAPON %-10s %-10s %-4s tris %4d length %.2f roles %s" % (wid, wclass, hands, tris, entry["length"], entry["role_tris"]))

        export_glb(objs, os.path.join(OUT_DIR, wid + ".glb"))
        if objs_l:
            export_glb(objs_l, os.path.join(OUT_DIR, wid + "_l.glb"))
            for o in objs_l:
                o.location = (lay_x + 0.9, 0, 0)

        # reference layout in the .blend: weapon + its markers as empties
        obj = objs[0]
        for o in objs:
            o.location = (lay_x, 0, 0)
        markers = [("tip", pts["tip"]), ("trail_base", pts["trail_base"])]
        if second_hand:
            markers.append(("second_hand", pts["second"]))
        if wm.string:
            markers += [("string_0", wm.string[0]), ("string_1", wm.string[1])]
        markers += [("aura_%d" % i, p) for i, p in enumerate(pts["aura"])]
        for key, p in markers:
            e = bpy.data.objects.new("%s.%s" % (wid, key), None)
            e.empty_display_type = 'SPHERE' if key.startswith("aura") else 'ARROWS'
            e.empty_display_size = 0.02 if key.startswith("aura") else 0.05
            scn.collection.objects.link(e)
            e.parent = obj
            e.location = (p[0], -p[1], p[2])
        obj["weapon_class"] = wclass
        obj["hands"] = hands
        lay_x += 1.8 if hands == "pair" else 1.2

    doc = {
        "version": WEAPONS_VERSION,
        "rig_version": RIG_VERSION,
        "generator": "tools/blender/build_weapons.py",
        "space": "Godot weapon-local: origin = centre of the holding fist, +Y along the blade/shaft, "
                 "+Z the edge/arrow direction (the wielder's forward), +X the wielder's left. "
                 "Matches the rig sockets' rest frame, so mount is identity.",
        "hands": {
            "two": "right hand on socket_weapon_r; second_hand.point is the LEFT hand's IK target",
            "pair": "right hand on socket_weapon_r plus the x-mirrored offhand_glb on socket_offhand_l (its points mirror in x)",
            "bow": "LEFT hand on socket_offhand_l; second_hand.point is the RIGHT hand's draw (nock) target; "
                   "string = the straight run's two ends (its own 'string' surface, hide it and draw the drawn string)",
            "none": "a projectile: no socket; origin = the shaft's middle, tip = the head, trail_base = the nock",
        },
        "roles": ROLE_NAMES,
        "weapons": {k: meta[k] for k in [w[0] for w in WEAPONS] if k in meta},
    }
    with open(JSON_OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1, sort_keys=False)
        fh.write("\n")
    print("JSON", JSON_OUT)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=False)
    print("BLEND", BLEND_OUT)


if __name__ == "__main__":
    main()
