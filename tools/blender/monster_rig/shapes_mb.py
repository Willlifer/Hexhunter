"""Lane MB shapes: extra primitives for the Monster Rig Builder (rigkit.py is
shared and read-only; Lane MA rebuilds the other two monsters on it). Used by
ext_swampfang.py and ext_spirewalker.py.

    import shapes_mb as sh
    row = sh.build_with(SPEC, glb, blend, extras=[fn, ...])   # rigkit.build + extras

build_with() patches two rigkit hooks for one build:
  build_eyes   -> the original, then every `extras` fn(mb, spec) (the hook
                  ext_spirewalker used since Phase 2)
  build_leg    -> limb() for a leg carrying a "limb" key (thick muscled arm,
                  broad paw, fingers and long claws), rigkit's tube leg otherwise

Primitives (all through rigkit's MeshBuilder, so the per-role export H303 and
the sRGB vertex colours H304 apply unchanged; deterministic, no randomness):
  loft(mb, rings, w_fn, role_fn, ...)  ellipse sections along any path
  prism(mb, a, b, c, w_fn, role, ...)  a thin closed triangle (sails, fronds)
  sail(mb, ra, rb, tip, w_fn, ...)     a swept fin: convex leading edge,
                                       hollow trailing edge, dark root -> bright tip
  leaf(mb, root, tip, width, ...)      a broad frond with a raised midrib
  boss(mb, c, nrm, r, h, ...)          a raised hexagonal scale plate
  surface(stations, x, y)              a point + normal on a loft's upper surface
  mottle_fn(spec, seed)                the body loft's mottle for extra lofts
"""

import math

import rigkit
from mathutils import Vector

UP = rigkit.UP
FORWARD = rigkit.FORWARD
V = rigkit.V
_h = rigkit._hash01


# ------------------------------------------------------------------ build
def build_with(spec, glb_path, blend_path=None, extras=()):
    orig_eyes = rigkit.build_eyes
    orig_leg = rigkit.build_leg

    def eyes_then_extras(mb, s):
        orig_eyes(mb, s)
        for fn in extras:
            fn(mb, s)

    def leg_or_limb(mb, s, leg):
        if leg.get("limb"):
            limb(mb, s, leg)
        else:
            orig_leg(mb, s, leg)

    rigkit.build_eyes = eyes_then_extras
    rigkit.build_leg = leg_or_limb
    try:
        return rigkit.build(spec, glb_path, blend_path)
    finally:
        rigkit.build_eyes = orig_eyes
        rigkit.build_leg = orig_leg


def append_manifest(path, row):
    """Replace this monster's row in place; every other row and the order are
    kept (rigkit.write_manifest would move ours first)."""
    import json
    import os
    doc = None
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    if not isinstance(doc, dict) or "monsters" not in doc:
        doc = {"version": rigkit.RIGKIT_VERSION, "generator": "tools/blender/build_monster_*.py + monster_rig/rigkit.py",
               "space": "Godot model-local: origin at the ground under the hips, +Y up, +Z the monster's forward, "
                        "+X its left. Bones carry head/tail at rest; sockets are Node3D under BoneAttachment3D.",
               "monsters": {}}
    doc["monsters"][row["id"]] = row
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1, sort_keys=False)
        fh.write("\n")


# ------------------------------------------------------------- colour
def mix(a, b, u):
    return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u)


def scale(c, f):
    return (min(1.0, c[0] * f), min(1.0, c[1] * f), min(1.0, c[2] * f))


def mottle_fn(spec, seed, roles=("hide",)):
    """A colour_fn(i, k, role) like the body loft's mottle (rigkit.build_chain)."""
    mot = spec.get("mottle", {})

    def fn(i, k, role):
        if role not in roles or not mot:
            return None
        base = spec["roles"][role]
        alt = mot.get("alt", base)
        if _h(i * 7 + 3 + seed, k * 13 + 1, 17) < float(mot.get("amount", 0.5)):
            return mix(base, alt, 0.55 + 0.45 * _h(i, k + seed, 99))
        return scale(base, 0.9 + 0.1 * _h(k, i + seed, 5))
    return fn


# ------------------------------------------------------------- lofts
def station_at(stations, y):
    """(z, rx, rz, flat) of a station list at coordinate y (stations along y)."""
    pts = sorted(((float(s["p"][1]), float(s["p"][2]), float(s["rx"]), float(s["rz"]), float(s.get("flat", 1.0)))
                  for s in stations), key=lambda q: q[0])
    if y <= pts[0][0]:
        return pts[0][1:]
    if y >= pts[-1][0]:
        return pts[-1][1:]
    for a, b in zip(pts, pts[1:]):
        if a[0] <= y <= b[0]:
            u = (y - a[0]) / max(1e-6, b[0] - a[0])
            return tuple(a[k] + (b[k] - a[k]) * u for k in (1, 2, 3, 4))
    return pts[-1][1:]


def surface(stations, x, y):
    """A point on the upper surface of a loft at (x, y) and its outward
    normal; None off the loft."""
    cz, rx, rz, _ = station_at(stations, y)
    if abs(x) >= rx * 0.98:
        return None
    zz = rz * math.sqrt(max(0.0, 1.0 - (x / rx) ** 2))
    p = Vector((x, y, cz + zz))
    n = Vector((x / (rx * rx), 0.0, zz / (rz * rz)))
    return p, n.normalized()


def loft(mb, rings, w_fn, role_fn, sides=10, cap_start=True, cap_end=True, color_fn=None):
    """rings: [{p, rx, rz, drop, flat}] in order. role_fn(i, k, z) with z the
    ring's cos (1 top, -1 bottom); w_fn(centre) the ring's weights."""
    pts = [V(r["p"]) for r in rings]
    n = len(pts)
    out = []
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()
        r = rings[i]
        out.append((pts[i], t.normalized(), float(r["rx"]), float(r["rz"]), float(r.get("drop", 0.0)),
                    float(r.get("flat", 1.0))))
    mb._cur_face_roles = [[role_fn(i, k, math.cos(2 * math.pi * (k + 0.5) / sides)) for k in range(sides)]
                          for i in range(n)]
    return mb.loft(out, role_fn, w_fn, sides, cap_start, cap_end, color_fn)


# ------------------------------------------------------------- sheets
def prism(mb, a, b, c, w_fn, role, thick=0.04, cols=None):
    """A thin closed triangle (both faces light, never z-fights)."""
    a, b, c = V(a), V(b), V(c)
    n = (b - a).cross(c - a)
    if n.length < 1e-9:
        return
    n = n.normalized() * thick * 0.5
    cols = cols or (None, None, None)
    top = [mb.add_vert(p + n, w_fn(p), role, col) for p, col in ((a, cols[0]), (b, cols[1]), (c, cols[2]))]
    bot = [mb.add_vert(p - n, w_fn(p), role, col) for p, col in ((a, cols[0]), (b, cols[1]), (c, cols[2]))]
    mb.faces.append(((top[0], top[1], top[2]), role))
    mb.faces.append(((bot[2], bot[1], bot[0]), role))
    for i in range(3):
        j = (i + 1) % 3
        mb.faces.append(((top[i], bot[i], bot[j], top[j]), role))


def _bowed(a, b, nrm, away, amount, segs):
    """Points strictly between a and b, bowed `amount` x length off the
    chord, away from the point `away` (negative bows toward it)."""
    d = b - a
    L = d.length
    perp = nrm.cross(d).normalized()
    if perp.dot(away - (a + b) * 0.5) > 0:
        perp = -perp
    return [a + d * (i / segs) + perp * (amount * L * math.sin(math.pi * i / segs)) for i in range(1, segs)]


def sail(mb, ra, rb, tip, w_fn, role, bow=0.14, hollow=0.2, thick=0.05, root_col=None, tip_col=None, segs=3,
         ribs=0, rib_col=None):
    """A swept fin (the reference's shark-sail fins): root ra (front) -> rb
    (back) along the body, a convex leading edge up to the tip, a hollow
    trailing edge back down; a fan of thin prisms from the root middle.
    Colour runs from root_col to tip_col. `ribs` dark lines (thin blades)
    from the root to the leading edge."""
    ra, rb, tip = V(ra), V(rb), V(tip)
    nrm = (rb - ra).cross(tip - ra).normalized()
    lead = _bowed(ra, tip, nrm, rb, bow, segs)
    trail = _bowed(tip, rb, nrm, ra, -hollow, segs)
    outline = [ra] + lead + [tip] + trail + [rb]
    rm = (ra + rb) * 0.5
    axis = tip - rm
    L2 = max(1e-6, axis.length_squared)

    def col(p):
        if root_col is None:
            return None
        u = max(0.0, min(1.0, (p - rm).dot(axis) / L2))
        return mix(root_col, tip_col or root_col, u)

    for i in range(len(outline) - 1):
        a, b = outline[i], outline[i + 1]
        prism(mb, rm, a, b, w_fn, role, thick, (col(rm), col(a), col(b)))
    for r in range(ribs):
        u = (r + 1.0) / (ribs + 1.0)
        root = ra + (rb - ra) * (0.15 + 0.6 * u)
        end = outline[min(len(outline) - 2, 1 + int(u * (len(lead) + 1)))]
        end = root + (end - root) * 0.92
        s = (end - root).cross(nrm).normalized() * 0.03
        prism(mb, root + s, root - s, end, w_fn, role, thick * 1.6, (rib_col, rib_col, rib_col))
    return outline


def leaf(mb, root, tip, width, w_fn, role, base_col, tip_col, rib=0.08, thick=0.04):
    """A broad frond: widest at 40%, a raised midrib, double sided."""
    root, tip = V(root), V(tip)
    a = tip - root
    L = a.length
    side = a.cross(UP)
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side = side.normalized()
    up = side.cross(a).normalized()
    if up.z < 0:
        up = -up
    pts = {}
    for u, wf in ((0.35, 1.0), (0.7, 0.72)):
        c = root + a * u
        pts[u] = (c + side * (width * 0.5 * wf), c + up * (rib * L), c - side * (width * 0.5 * wf))
    l1, m1, r1 = pts[0.35]
    l2, m2, r2 = pts[0.7]
    cr = lambda p: mix(base_col, tip_col, max(0.0, min(1.0, (p - root).dot(a) / (L * L))))
    for tri in ((root, l1, m1), (root, m1, r1), (l1, l2, m1), (m1, l2, m2), (m1, m2, r1), (r1, m2, r2),
                (l2, tip, m2), (m2, tip, r2)):
        prism(mb, tri[0], tri[1], tri[2], w_fn, role, thick, tuple(cr(p) for p in tri))


def boss(mb, c, nrm, r, h, w, role, color=None, n=6, spin=0.0, stretch=1.0, along=None):
    """A raised scale plate: an n-gon base sunk a little into the surface, a
    smaller flat top `h` out along `nrm`. `stretch` elongates it `along`."""
    c, nrm = V(c), V(nrm).normalized()
    t1 = (along or FORWARD).copy()
    t1 = (t1 - nrm * t1.dot(nrm))
    if t1.length < 1e-6:
        t1 = Vector((1, 0, 0)) - nrm * nrm.x
    t1 = t1.normalized()
    t2 = nrm.cross(t1).normalized()
    base = []
    top = []
    for i in range(n):
        a = 2 * math.pi * (i + spin) / n
        d = t1 * (math.cos(a) * stretch) + t2 * math.sin(a)
        base.append(mb.add_vert(c + d * r - nrm * 0.06, w, role, color))
        top.append(mb.add_vert(c + d * (r * 0.62) + nrm * h, w, role, scale(color, 1.08) if color else None))
    mb.faces.append((tuple(top), role))
    mb.faces.append((tuple(reversed(base)), role))
    for i in range(n):
        j = (i + 1) % n
        mb.faces.append(((base[i], base[j], top[j], top[i]), role))


# ------------------------------------------------------------- limbs
def limb(mb, spec, leg):
    """A thick, muscled limb: hip -> bulging upper arm -> knee -> bulging
    forearm -> wrist, a broad paw, fanned fingers and long claws.
    leg["limb"]: { bulge, fore_bulge, paw: (w, l, h), fingers, finger_len,
    finger_r, claw_len, claw_r, fan_deg, claw_role }."""
    lid = leg["id"]
    L = leg["limb"]
    hip, knee, ankle, toe = V(leg["hip"]), V(leg["knee"]), V(leg["ankle"]), V(leg["toe"])
    rh, rk, ra = [float(x) for x in leg["radii"]]
    role = leg.get("role", "hide")
    sides = int(leg.get("sides", 10))
    names = ["hip_" + lid, "knee_" + lid]
    out = Vector((1.0 if hip.x >= 0 else -1.0, 0.0, 0.0))
    bu = float(L.get("bulge", 1.15))
    fb = float(L.get("fore_bulge", 1.12))
    up_mid = hip + (knee - hip) * 0.45 + out * (rh * (bu - 1.0))
    fo_mid = knee + (ankle - knee) * 0.35 + out * (rk * (fb - 1.0))
    pts = [hip, up_mid, knee, fo_mid, ankle]
    radii = [rh, rh * bu, rk, (rk + ra) * 0.5 * fb, ra]
    col_fn = mottle_fn(spec, 37 + len(lid))
    rings = []
    for i, p in enumerate(pts):
        if i > 0:
            rings.append({"p": (pts[i - 1] + p) * 0.5, "rx": (radii[i - 1] + radii[i]) * 0.5,
                          "rz": (radii[i - 1] + radii[i]) * 0.5})
        rings.append({"p": p, "rx": radii[i], "rz": radii[i]})
    loft(mb, rings, lambda c: mb.auto_weight(c, names, float(leg.get("blend", 0.2))), lambda i, k, z: role,
         sides, True, True, col_fn)
    # wrist and paw
    mb.sphere(ankle, ra * 1.08, {"ankle_" + lid: 1.0}, role, seg=8, rings=4)
    fw, fl, fh = L.get("paw", (0.8, 0.8, 0.28))
    d = toe - ankle
    d.z = 0
    d = d.normalized() if d.length > 1e-6 else FORWARD.copy()
    side = d.cross(UP).normalized()
    wt = {"toe_" + lid: 0.7, "ankle_" + lid: 0.3}
    ctr = ankle + d * (fl * 0.35)
    ctr.z = fh * 0.5 + 0.02
    paw = [{"p": ankle + d * (-fl * 0.1) + UP * (fh * 0.55 - ankle.z + 0.02), "rx": fw * 0.42, "rz": fh * 0.6},
           {"p": ctr + UP * 0.0, "rx": fw * 0.5, "rz": fh * 0.5, "flat": 0.6},
           {"p": ctr + d * (fl * 0.45) - UP * (fh * 0.08), "rx": fw * 0.46, "rz": fh * 0.38, "flat": 0.5}]
    loft(mb, paw, lambda c: wt, lambda i, k, z: role, 8, True, True, col_fn)
    # fingers and claws
    n = int(L.get("fingers", 3))
    flen = float(L.get("finger_len", 0.3))
    fr = float(L.get("finger_r", 0.1))
    cl = float(L.get("claw_len", 0.4))
    cr = float(L.get("claw_r", 0.09))
    fan = math.radians(float(L.get("fan_deg", 40.0)))
    crole = L.get("claw_role", "claw")
    front = ctr + d * (fl * 0.5)
    wtoe = {"toe_" + lid: 1.0}
    for i in range(n):
        u = (i + 0.5) / n - 0.5
        ang = u * fan
        fd = d * math.cos(ang) + side * math.sin(ang)
        base = front + side * (u * fw * 0.75)
        base.z = fh * 0.45
        knuck = base + fd * flen
        knuck.z = fh * 0.32
        mb.tube([base, knuck], [fr, fr * 0.85], ["toe_" + lid], 0.1, 6, role, explicit_w=wtoe)
        s2 = fd.cross(UP).normalized()
        b0 = knuck + fd * 0.02
        bp = [b0 + s2 * cr + UP * cr, b0 - s2 * cr + UP * cr, b0 - s2 * cr - UP * cr * 0.8, b0 + s2 * cr - UP * cr * 0.8]
        apex = b0 + fd * cl
        apex.z = 0.02
        mb.pyramid(bp, apex, wtoe, crole)
