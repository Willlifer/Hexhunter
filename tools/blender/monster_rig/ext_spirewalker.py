"""Spirewalker additions to the Monster Rig Builder (rigkit.py is shared and
read-only; this module extends it from the outside).

    import rigkit, ext_spirewalker as ext
    SPEC["extra_bones"] += ext.reed_bones(SPEC)      # one bone per reed row group
    row = ext.build(SPEC, glb_path, blend_path)      # rigkit.build + the extras

What it adds, from SPEC keys rigkit ignores:
  reeds     { chain: "spine", rows: [y ...], per_row: n, span: x half-width,
              length: (min, max), lean_back: m, role: "reed", bead_role: "arc",
              beads: n, bones: [(name, parent, y_from, y_to) ...], thick: m }
            a dense bed of tall blades rooted on the top of the body loft
            (the loft surface is sampled from the chain's stations), each
            weighted to the row group's bone (reed_<k>) so a bone pitch folds
            the whole bed flat (the squash tell). `beads` violet spheres sit on
            the tallest tips: the resting hint of the arcs that jump between
            the reeds when it is charged.
  bristles  [ { leg: "fl", count: n, length: m, role: "bristle" } ... ]
            short blades along the forearm (knee -> ankle tube) of a leg,
            on the knee_<leg> bone, pointing out and forward
  horns     { bone: "head", at: [(x, y, z) ...], length, back, role }
            the horned-lizard crown: blades off the back of the skull

Every helper is deterministic (rigkit._hash01 for the variation). Geometry
goes through rigkit's MeshBuilder so the per-role export (H303) and the sRGB
vertex colours (H304) apply unchanged. The hook: rigkit.build() calls
build_eyes() last; build() here wraps it for the duration of one build.
"""

import math

import rigkit
from mathutils import Vector

UP = rigkit.UP
FORWARD = rigkit.FORWARD
V = rigkit.V


# ------------------------------------------------------------ loft sampling
def _station_at(chain, y):
    """Interpolate (centre z, rx, rz) of a chain's stations at coordinate y
    (stations run along y; the body loft is symmetric about x = 0)."""
    st = chain["stations"]
    pts = [(float(s["p"][1]), float(s["p"][2]), float(s["rx"]), float(s["rz"])) for s in st]
    pts.sort(key=lambda q: q[0])
    if y <= pts[0][0]:
        return pts[0][1:]
    if y >= pts[-1][0]:
        return pts[-1][1:]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        if a[0] <= y <= b[0]:
            u = (y - a[0]) / max(1e-6, b[0] - a[0])
            return tuple(a[k] + (b[k] - a[k]) * u for k in (1, 2, 3))
    return pts[-1][1:]


def top_of_body(spec, chain_name, x, y):
    """Height of the body loft's upper surface at (x, y), or None off the body."""
    for ch in spec.get("chains", []):
        if ch["name"] == chain_name:
            cz, rx, rz = _station_at(ch, y)
            if abs(x) >= rx:
                return None
            return cz + rz * math.sqrt(max(0.0, 1.0 - (x / rx) ** 2))
    return None


# ------------------------------------------------------------------ bones
def reed_bones(spec):
    """Extra-bone tuples for the reed row groups: a vertical bone standing
    on the back at the group's mean y, parented to the spine bone under it."""
    r = spec.get("reeds")
    if not r:
        return []
    out = []
    for (name, parent, y0, y1) in r["bones"]:
        y = (y0 + y1) * 0.5
        z = top_of_body(spec, r.get("chain", "spine"), 0.0, y) or 1.0
        out.append((name, parent, (0.0, y, z - 0.1), (0.0, y, z + 1.0), FORWARD))
    return out


def _reed_bone_for(r, y):
    for (name, parent, y0, y1) in r["bones"]:
        if y0 <= y <= y1:
            return name
    # nearest group
    best = min(r["bones"], key=lambda b: min(abs(y - b[2]), abs(y - b[3])))
    return best[0]


# -------------------------------------------------------------- geometry
def build_reed_bed(mb, spec):
    r = spec.get("reeds")
    if not r:
        return
    chain = r.get("chain", "spine")
    role = r.get("role", "reed")
    bead_role = r.get("bead_role", "arc")
    per_row = int(r.get("per_row", 7))
    span = float(r.get("span", 1.5))
    lmin, lmax = r.get("length", (1.4, 2.1))
    lean_back = float(r.get("lean_back", 0.15))
    thick = float(r.get("thick", 0.03))
    base = spec["roles"].get(role, (0.7, 0.4, 0.15))
    tip_col = r.get("tip_color", (min(1.0, base[0] * 1.25), min(1.0, base[1] * 1.2), base[2]))
    tips = []
    for ri, y in enumerate(r["rows"]):
        bone = _reed_bone_for(r, y)
        w = {bone: 1.0}
        n = per_row if ri % 2 == 0 else per_row - 1          # staggered rows read denser
        for k in range(n):
            u = (k + 0.5) / n - 0.5
            x = u * 2.0 * span
            z = top_of_body(spec, chain, x, y)
            if z is None:
                continue
            h = rigkit._hash01(ri * 31 + 7, k * 17 + 3, 5)
            L = lmin + (lmax - lmin) * h
            # outer reeds fan outward, every reed rakes a little back
            lean = Vector((0.35 * u * 2.0, lean_back + 0.1 * h, 0.0))
            root = Vector((x, y, z - 0.06))
            tip = root + UP * L + lean * L
            side = Vector((1.0, 0.0, 0.0)) * (0.06 + 0.03 * h)
            if abs(u) > 0.3:
                side = Vector((0.5, 0.0, 0.0)).normalized() * (0.06 + 0.03 * h)
            # a blade with a mid vertex so the colour brightens toward the tip
            mid = root + (tip - root) * 0.55
            mb.blade(root + side, root - side, mid + side * 0.5, w, role, thick=thick, color=base)
            mb.blade(mid + side * 0.5, mid - side * 0.5, tip, w, role, thick=thick, color=tip_col)
            tips.append((L, tip, w))
    # beads: violet spheres on the tallest tips (the arc hint)
    nb = int(r.get("beads", 8))
    tips.sort(key=lambda t: -t[0])
    for (L, tip, w) in tips[:nb]:
        mb.sphere(tip - UP * 0.05, float(r.get("bead_r", 0.08)), w, bead_role, seg=6, rings=3)


def build_bristles(mb, spec):
    legs = {l["id"]: l for l in spec.get("legs", [])}
    for b in spec.get("bristles", []):
        leg = legs[b["leg"]]
        knee, ankle = V(leg["knee"]), V(leg["ankle"])
        rad = (float(leg["radii"][1]) + float(leg["radii"][2])) * 0.5
        n = int(b.get("count", 6))
        L = float(b.get("length", 0.35))
        role = b.get("role", "bristle")
        w = {"knee_" + leg["id"]: 1.0}
        along = (ankle - knee).normalized()
        s = 1.0 if knee.x >= 0 else -1.0
        out = Vector((s, 0.0, 0.0))
        out = (out - along * out.dot(along)).normalized()
        fwd = (FORWARD - along * FORWARD.dot(along)).normalized()
        for i in range(n):
            u = (i + 0.5) / n
            c = knee + (ankle - knee) * (0.12 + 0.76 * u)
            h = rigkit._hash01(i * 11 + 1, 3, 9)
            for j, d in enumerate((out, (out + fwd).normalized(), fwd)):
                root = c + d * (rad * 0.92)
                tip = root + d * (L * (0.75 + 0.5 * h)) + along * (0.12 * L)
                side = d.cross(along).normalized() * 0.035
                mb.blade(root + side, root - side, tip, w, role, thick=0.02)


def build_horns(mb, spec):
    hn = spec.get("horns")
    if not hn:
        return
    bone = hn.get("bone", "head")
    w = {bone: 1.0}
    L = float(hn.get("length", 0.6))
    back = float(hn.get("back", 0.5))
    role = hn.get("role", "claw")
    for i, at in enumerate(hn["at"]):
        p = V(at)
        s = 0.0 if abs(p.x) < 1e-6 else (1.0 if p.x > 0 else -1.0)
        tip = p + Vector((s * 0.35 * L, back * L, L))
        d = (tip - p).normalized()
        side = d.cross(FORWARD)
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side = side.normalized() * (0.11 if i % 2 == 0 else 0.09)
        mb.blade(p + side, p - side, tip, w, role, thick=0.05)


# ------------------------------------------------------------------ build
def build(spec, glb_path, blend_path=None):
    """rigkit.build with the Spirewalker extras appended to the mesh."""
    original = rigkit.build_eyes

    def eyes_then_extras(mb, s):
        original(mb, s)
        build_horns(mb, s)
        build_bristles(mb, s)
        build_reed_bed(mb, s)

    rigkit.build_eyes = eyes_then_extras
    try:
        row = rigkit.build(spec, glb_path, blend_path)
    finally:
        rigkit.build_eyes = original
    r = spec.get("reeds", {})
    row["reeds"] = [b[0] for b in r.get("bones", [])]
    row["bristles"] = ["knee_" + b["leg"] for b in spec.get("bristles", [])]
    return row
