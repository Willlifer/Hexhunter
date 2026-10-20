"""Shared primitives for Lane MA's monsters (Colambros, Rimeslithe), visual pass
3.5. rigkit.py is shared and read-only; these build on its MeshBuilder from
outside (mb.add_vert / mb.faces / mb.tube / mb.sphere / mb.pyramid).

  ellipsoid(mb, centre, ax, ay, az, w, role)    a faceted ellipsoid on three axes
                                                (muscle masses: thighs, haunches, chest)
  digi_leg(mb, spec, leg, rigkit)               a digitigrade leg: hip -> knee -> hock
                                                (ankle) -> ball of the foot (toe), a thigh
                                                mass, a hock knob, splayed toes with claws
  horn(mb, pts, radii, w, role, colors)         a tapered, ringed horn along a polyline
                                                (alternating colour bands per segment)
  plate(mb, pts, widths, normal, w, role, ...)  a swept crest / fin plate: a tapered slab
                                                along a curve, with thickness (both faces
                                                light), optional per-point colours

Everything is deterministic and in Blender coordinates (Z up, faces -Y, left +X).
"""

import math

from mathutils import Matrix, Vector

UP = Vector((0, 0, 1))
FORWARD = Vector((0, -1, 0))


def V(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


def _ortho(d):
    d = d.normalized()
    ref = UP if abs(d.dot(UP)) < 0.9 else Vector((1.0, 0.0, 0.0))
    a = (ref - d * ref.dot(d)).normalized()
    b = d.cross(a).normalized()
    return a, b


# ------------------------------------------------------------- ellipsoid
def ellipsoid(mb, centre, ax, ay, az, w, role, seg=8, rings=5, color=None):
    """A UV ellipsoid whose local x/y/z are the (scaled) vectors ax, ay, az."""
    c = V(centre)
    ax, ay, az = V(ax), V(ay), V(az)
    top = mb.add_vert(c + az, w, role, color)
    lat = []
    for i in range(1, rings):
        th = math.pi * i / rings
        row = []
        for j in range(seg):
            ph = 2 * math.pi * (j + 0.5 * (i % 2)) / seg
            p = c + ax * (math.sin(th) * math.cos(ph)) + ay * (math.sin(th) * math.sin(ph)) + az * math.cos(th)
            row.append(mb.add_vert(p, w, role, color))
        lat.append(row)
    bot = mb.add_vert(c - az, w, role, color)
    for j in range(seg):
        k = (j + 1) % seg
        mb.faces.append(((top, lat[0][j], lat[0][k]), role))
        mb.faces.append(((bot, lat[-1][k], lat[-1][j]), role))
    for i in range(len(lat) - 1):
        for j in range(seg):
            k = (j + 1) % seg
            mb.faces.append(((lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k]), role))


def mass_along(mb, a, b, u, r_side, r_len, r_fwd, w, role, seg=8, rings=5, color=None):
    """An ellipsoid centred at fraction u of the segment a->b, long axis along it."""
    a, b = V(a), V(b)
    d = (b - a)
    c = a + d * u
    d = d.normalized()
    side = d.cross(UP)
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side = side.normalized()
    fwd = side.cross(d).normalized()
    ellipsoid(mb, c, side * r_side, fwd * r_fwd, d * r_len, w, role, seg, rings, color)


# ------------------------------------------------------------- legs
def digi_leg(mb, spec, leg, rigkit):
    """A digitigrade leg. Spec keys (beyond rigkit's): radii = (hip, knee, hock,
    ball); thigh = (r_side, r_len, r_fwd, u) the muscle mass on the hip bone;
    toes (n), toe_len, toe_w, toe_spread_deg, claw_len, calf = (r_side, r_len, r_fwd)
    an optional mass on the shin."""
    lid = leg["id"]
    pts = [V(leg["hip"]), V(leg["knee"]), V(leg["ankle"]), V(leg["toe"])]
    radii = list(leg["radii"])
    if len(radii) < 4:
        radii.append(radii[-1] * 0.8)
    names = ["hip_" + lid, "knee_" + lid, "ankle_" + lid]
    sides = int(leg.get("sides", 8))
    role = leg.get("role", "hide")
    mb.tube(pts, radii, names, float(leg.get("blend", 0.18)), sides, role)
    th = leg.get("thigh")
    if th:
        mass_along(mb, pts[0], pts[1], float(th[3]) if len(th) > 3 else 0.42, th[0], th[1], th[2],
                   {names[0]: 1.0}, role, seg=10, rings=6)
    calf = leg.get("calf")
    if calf:
        mass_along(mb, pts[1], pts[2], float(calf[3]) if len(calf) > 3 else 0.3, calf[0], calf[1], calf[2],
                   {names[1]: 1.0}, role, seg=8, rings=4)
    # knee and hock knobs hide the hard joints
    mb.sphere(pts[1], radii[1] * 1.08, {names[0]: 0.5, names[1]: 0.5}, role, seg=8, rings=4)
    mb.sphere(pts[2], radii[2] * 1.12, {names[1]: 0.4, names[2]: 0.6}, role, seg=6, rings=3)
    # the toes: wedges fanned forward from the ball of the foot, flat on the ground
    ball = pts[3]
    tw = {"toe_" + lid: 1.0}
    d = (pts[3] - pts[2])
    d.z = 0.0
    d = d.normalized() if d.length > 1e-6 else FORWARD.copy()
    n = int(leg.get("toes", 3))
    tl = float(leg.get("toe_len", 0.6))
    twid = float(leg.get("toe_w", 0.2))
    spread = math.radians(float(leg.get("toe_spread_deg", 34.0)))
    cl = float(leg.get("claw_len", 0.3))
    croll = leg.get("claw_role", "claw")
    mb.sphere(ball, radii[3] * 1.15, tw, role, seg=6, rings=3)
    for i in range(n):
        u = (i / float(n - 1) - 0.5) if n > 1 else 0.0
        ang = u * spread
        td = Matrix.Rotation(ang, 3, 'Z') @ d
        side = td.cross(UP).normalized()
        L = tl * (1.0 - 0.25 * abs(u) * 2.0)
        r0 = ball + side * (u * radii[3] * 1.2)
        r0.z = 0.0
        tip = r0 + td * L
        h0 = radii[3] * 1.3
        h1 = 0.1
        hw0 = twid * 0.5
        hw1 = twid * 0.32
        base = [r0 + side * hw0, r0 - side * hw0, r0 - side * hw0 + UP * h0, r0 + side * hw0 + UP * h0]
        top = [tip + side * hw1, tip - side * hw1, tip - side * hw1 + UP * h1, tip + side * hw1 + UP * h1]
        mb.wedge(base, top, tw, role)
        # claw off the toe end, pointing forward and down
        cb = tip + UP * (h1 * 0.5)
        cbase = [cb + side * hw1 - UP * 0.05, cb - side * hw1 - UP * 0.05, cb - side * hw1 + UP * 0.07, cb + side * hw1 + UP * 0.07]
        ctip = cb + td * cl
        ctip.z = 0.02
        mb.pyramid(cbase, ctip, tw, croll)


# ------------------------------------------------------------- horns
def horn(mb, pts, radii, w, role, colors=None, sides=6):
    """A tapered horn along `pts` (root first) ending in a point; `colors`
    alternate per ring (the reference's ringed horn)."""
    P = [V(p) for p in pts]
    rings = []
    for i, p in enumerate(P[:-1]):
        if i == 0:
            t = P[1] - P[0]
        else:
            t = (P[i] - P[i - 1]).normalized() + (P[i + 1] - P[i]).normalized()
        a, b = _ortho(t)
        col = colors[i % len(colors)] if colors else None
        row = []
        for k in range(sides):
            ang = 2 * math.pi * k / sides
            row.append(mb.add_vert(p + (a * math.cos(ang) + b * math.sin(ang)) * radii[i], w, role, col))
        rings.append(row)
    tipcol = colors[(len(P) - 1) % len(colors)] if colors else None
    apex = mb.add_vert(P[-1], w, role, tipcol)
    mb.faces.append((tuple(reversed(rings[0])), role))
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(sides):
            k2 = (k + 1) % sides
            mb.faces.append(((r0[k], r0[k2], r1[k2], r1[k]), role))
    last = rings[-1]
    for k in range(sides):
        mb.faces.append(((last[k], last[(k + 1) % sides], apex), role))


# ------------------------------------------------------------- plates
def plate(mb, pts, widths, normal, w, role, thick=0.06, colors=None):
    """A swept slab: along the polyline `pts`, `widths[i]` across (in the plane
    whose normal is `normal`), `thick` through it. The last point's width can
    be 0 for a pointed blade. `w` is one weight dict or a list per point."""
    P = [V(p) for p in pts]
    nrm = V(normal).normalized()
    n = len(P)
    left = []
    right = []
    for i in range(n):
        if i == 0:
            t = P[1] - P[0]
        elif i == n - 1:
            t = P[-1] - P[-2]
        else:
            t = (P[i] - P[i - 1]).normalized() + (P[i + 1] - P[i]).normalized()
        t = t.normalized()
        across = nrm.cross(t)
        if across.length < 1e-6:
            across = Vector((0, 0, 1))
        across = across.normalized()
        wi = w[i] if isinstance(w, list) else w
        col = colors[i] if colors else None
        hw = float(widths[i]) * 0.5
        ht = thick * 0.5 * (0.35 if hw < 1e-4 else 1.0)
        quad = [P[i] + across * hw + nrm * ht, P[i] - across * hw + nrm * ht,
                P[i] - across * hw - nrm * ht, P[i] + across * hw - nrm * ht]
        idx = [mb.add_vert(q, wi, role, col) for q in quad]
        left.append(idx)
    # faces between consecutive cross-sections (4 sides)
    for i in range(n - 1):
        a, b = left[i], left[i + 1]
        for k in range(4):
            k2 = (k + 1) % 4
            mb.faces.append(((a[k], a[k2], b[k2], b[k]), role))
    mb.faces.append((tuple(reversed(left[0])), role))
    mb.faces.append((tuple(left[-1]), role))


# ------------------------------------------------------------- normals (H652)
def install_normal_fix(rigkit):
    """rigkit exports one mesh per colour role and recalculates normals per
    role. An open strip (the belly band of a loft) has no inside, so bmesh may
    point it inward: it then catches the sun from below and reads as a bright
    bar under the body. This wraps MeshBuilder.build: afterwards every
    connected island votes, face by face, on whether its normal points away
    from the nearest bone; an island that mostly points inward is flipped.
    Closed islands already agree with the vote and are left alone. Idempotent."""
    import bmesh
    MB = rigkit.MeshBuilder
    if getattr(MB, "_ma_normal_fix", False):
        return
    orig = MB.build

    def build(self, name, materials):
        out = orig(self, name, materials)
        bones = list(self.bones.values())
        for role, me, weights in out:
            bm = bmesh.new()
            bm.from_mesh(me)
            bm.faces.ensure_lookup_table()
            seen = set()
            flip = []
            for f in bm.faces:
                if f.index in seen:
                    continue
                island = []
                stack = [f]
                seen.add(f.index)
                while stack:
                    g = stack.pop()
                    island.append(g)
                    for e in g.edges:
                        for h in e.link_faces:
                            if h.index not in seen:
                                seen.add(h.index)
                                stack.append(h)
                bad = 0
                for g in island:
                    c = g.calc_center_median()
                    best = None
                    bd = 1e9
                    for b in bones:
                        d = b.tail - b.head
                        L2 = d.length_squared
                        u = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, (c - b.head).dot(d) / L2))
                        q = b.head + d * u
                        dist = (c - q).length
                        if dist < bd:
                            bd = dist
                            best = q
                    if g.normal.dot(c - best) < 0.0:
                        bad += 1
                if bad * 2 > len(island):
                    flip.extend(island)
            if flip:
                bmesh.ops.reverse_faces(bm, faces=flip)
                bm.to_mesh(me)
                me.update()
            bm.free()
        return out

    MB.build = build
    MB._ma_normal_fix = True
