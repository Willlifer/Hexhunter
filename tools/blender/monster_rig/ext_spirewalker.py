"""Spirewalker additions to the Monster Rig Builder (rigkit.py is shared and
read-only; this module extends it from the outside, through shapes_mb).

    import rigkit, ext_spirewalker as ext
    SPEC["extra_bones"] += ext.reed_bones(SPEC)      # one bone per reed row group
    row = ext.build(SPEC, glb_path, blend_path)      # rigkit.build + the extras

What it adds, from SPEC keys rigkit ignores (Phase 3.5 gauntlet, Lane MB:
a squat toad-crab whose back carries a raised mound with the reed bed growing
out of it, like the reference's plant mass):
  skull / lower_jaw / brows   the wide flat toad head with the toothy grin
            (ext_swampfang's builders: the same keys)
  mound     { stations: [{p, rx, rz}], bones, role }: the raised hump on the
            back that the reed bed grows from (darker ochre: the back contrast)
  reeds     { rows: [y ...], per_row, span, length: (min, max), spire, lean_back,
              role: "reed", bead_role: "arc", beads, bead_gap, bones:
              [(name, parent, y_from, y_to) ...], thick }
            a dense bed of copper blades rooted on the mound, tallest in the
            middle (`spire` shapes the falloff), each weighted to its row
            group's bone (reed_<k>) so a bone pitch folds the bed flat (the
            squash tell). `beads` violet spheres on the tallest tips, at least
            `bead_gap` apart (HHMonsterBody clusters them within 0.22 m): the
            resting hint of the arcs.
  fronds    { count, angles, centre, radius, length, width, droop, bones, role }:
            broad ochre-olive leaves splayed round the mound's base
  thorns    { chains: [...], role, length }: small barbs down the whip vines
            (the vines are ordinary rigkit chains, so they carry bones)
  bristles  [ { leg: "fl", count: n, length: m, role: "bristle" } ... ]
            short blades along a forearm (knee -> ankle), on the knee_<leg> bone
  horns     { bone: "head", at: [(x, y, z) ...], length, back, role }
            the horned-lizard crown: blades off the back of the skull

Every helper is deterministic (rigkit._hash01 for the variation).
"""

import math

import rigkit
import shapes_mb as sh
import ext_swampfang as heads
from mathutils import Vector

UP = rigkit.UP
FORWARD = rigkit.FORWARD
V = rigkit.V


def mound_top(spec, x, y):
    hit = sh.surface(spec["mound"]["stations"], x, y)
    return None if hit is None else hit[0].z


# ------------------------------------------------------------------ bones
def reed_bones(spec):
    """Extra-bone tuples for the reed row groups: a vertical bone standing
    on the mound at the group's mean y, parented to the spine bone under it."""
    r = spec.get("reeds")
    if not r:
        return []
    out = []
    for (name, parent, y0, y1) in r["bones"]:
        y = (y0 + y1) * 0.5
        z = mound_top(spec, 0.0, y) or 2.0
        out.append((name, parent, (0.0, y, z - 0.1), (0.0, y, z + 1.0), FORWARD))
    return out


def _reed_bone_for(r, y):
    for (name, parent, y0, y1) in r["bones"]:
        if y0 <= y <= y1:
            return name
    return min(r["bones"], key=lambda b: min(abs(y - b[2]), abs(y - b[3])))[0]


# -------------------------------------------------------------- geometry
def build_mound(mb, spec):
    m = spec["mound"]
    names = m["bones"]
    role = m.get("role", "mound")
    sh.loft(mb, m["stations"], lambda c: mb.auto_weight(c, names, 0.5), lambda i, k, z: role,
            int(m.get("sides", 14)), True, True, sh.mottle_fn(spec, 41, roles=(role,)))


def build_reed_bed(mb, spec):
    r = spec.get("reeds")
    if not r:
        return
    role = r.get("role", "reed")
    bead_role = r.get("bead_role", "arc")
    per_row = int(r.get("per_row", 7))
    span = float(r.get("span", 1.5))
    lmin, lmax = r.get("length", (0.8, 1.8))
    sx, sy, yc = r.get("spire", (1.4, 1.2, 0.0))
    lean_back = float(r.get("lean_back", 0.12))
    thick = float(r.get("thick", 0.03))
    base = spec["roles"].get(role, (0.7, 0.4, 0.15))
    dark = sh.scale(base, 0.7)
    tip_col = r.get("tip_color", (min(1.0, base[0] * 1.25), min(1.0, base[1] * 1.2), base[2]))
    tips = []
    for ri, y in enumerate(r["rows"]):
        bone = _reed_bone_for(r, y)
        w = {bone: 1.0}
        n = per_row if ri % 2 == 0 else per_row - 1          # staggered rows read denser
        for k in range(n):
            u = (k + 0.5) / n - 0.5
            x = u * 2.0 * span + 0.08 * (rigkit._hash01(ri, k, 21) - 0.5)
            z = mound_top(spec, x, y)
            if z is None:
                continue
            h = rigkit._hash01(ri * 31 + 7, k * 17 + 3, 5)
            f = 1.0 - 0.65 * (x / sx) ** 2 - 0.55 * ((y - yc) / sy) ** 2      # tallest in the middle: a spire
            L = lmin + (lmax - lmin) * max(0.0, min(1.0, f * (0.7 + 0.3 * h)))
            lean = Vector((0.5 * u * 2.0, lean_back + 0.1 * h + 0.25 * (y - yc) / sy, 0.0))
            root = Vector((x, y, z - 0.08))
            tip = root + UP * L + lean * L
            side = Vector((1.0, 0.0, 0.0)) * (0.07 + 0.03 * h)
            mid = root + (tip - root) * 0.5
            mb.blade(root + side, root - side, mid + side * 0.6, w, role, thick=thick, color=dark)
            mb.blade(mid + side * 0.6, mid - side * 0.6, tip, w, role, thick=thick, color=tip_col)
            tips.append((L, tip, w))
    # beads: violet spheres on the tallest tips, spaced apart (the arc hint)
    nb = int(r.get("beads", 8))
    gap = float(r.get("bead_gap", 0.45))
    tips.sort(key=lambda t: -t[0])
    chosen = []
    for (L, tip, w) in tips:
        if len(chosen) >= nb:
            break
        if all((tip - c[1]).length >= gap for c in chosen):
            chosen.append((L, tip, w))
    for (L, tip, w) in chosen:
        mb.sphere(tip - UP * 0.05, float(r.get("bead_r", 0.08)), w, bead_role, seg=6, rings=3)


def build_fronds(mb, spec):
    f = spec.get("fronds")
    if not f:
        return
    names = f["bones"]
    role = f.get("role", "frond")
    base = spec["roles"][role]
    cx, cy = f.get("centre", (0.0, 0.0))
    rx, ry = f.get("radius", (1.2, 1.2))
    for i, a_deg in enumerate(f["angles"]):
        a = math.radians(a_deg)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        x, y = cx + rx * d.x, cy + ry * d.y
        z = mound_top(spec, x * 0.85, y * 0.85 + cy * 0.15) or 2.0
        root = Vector((x * 0.85, y * 0.85 + cy * 0.15, z))
        L = float(f.get("length", 1.6)) * (1.0 if i % 2 == 0 else 0.82)
        tip = root + d * L - UP * float(f.get("droop", 0.5)) * L * 0.5
        sh.leaf(mb, root, tip, float(f.get("width", 0.7)), lambda p: mb.auto_weight(p, names, 0.5), role,
                sh.scale(base, 0.78), sh.scale(base, 1.18), rib=0.1, thick=0.05)


def build_thorns(mb, spec):
    t = spec.get("thorns")
    if not t:
        return
    role = t.get("role", "bristle")
    L = float(t.get("length", 0.16))
    for ch in spec["chains"]:
        if ch["name"] not in t["chains"]:
            continue
        pts = [V(s["p"]) for s in ch["stations"]]
        names = [b[0] for b in ch["bones"]]
        k = 0
        for i in range(len(pts) - 1):
            for u in (0.3, 0.75):
                c = pts[i] + (pts[i + 1] - pts[i]) * u
                along = (pts[i + 1] - pts[i]).normalized()
                side = along.cross(UP).normalized()
                d = (side if k % 2 == 0 else -side) * 0.8 + UP * 0.6
                d = (d - along * d.dot(along)).normalized()
                r = float(ch["stations"][i]["rx"])
                root = c + d * (r * 0.8)
                tip = root + d * L + along * (L * 0.4)
                s2 = d.cross(along).normalized() * 0.03
                mb.blade(root + s2, root - s2, tip, mb.auto_weight(c, names, 0.1), role, thick=0.02)
                k += 1


def build_bristles(mb, spec):
    legs = {l["id"]: l for l in spec.get("legs", [])}
    for b in spec.get("bristles", []):
        leg = legs[b["leg"]]
        knee, ankle = V(leg["knee"]), V(leg["ankle"])
        rad = (float(leg["radii"][1]) + float(leg["radii"][2])) * 0.5 * float(leg.get("limb", {}).get("fore_bulge", 1.0))
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
            dirs = (out, (out + fwd).normalized(), fwd)[:int(b.get("dirs", 3))]
            for j, d in enumerate(dirs):
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
    row = sh.build_with(spec, glb_path, blend_path, extras=[
        heads.build_skull, heads.build_lower_jaw, heads.build_brows, build_mound, build_horns, build_bristles,
        build_fronds, build_thorns, build_reed_bed])
    row["jaw"] = spec["lower_jaw"]["bone"]
    r = spec.get("reeds", {})
    row["reeds"] = [b[0] for b in r.get("bones", [])]
    row["bristles"] = ["knee_" + b["leg"] for b in spec.get("bristles", [])]
    row["vines"] = {ch["name"]: [b[0] for b in ch["bones"]] for ch in spec["chains"] if ch["name"].startswith("vine")}
    return row
