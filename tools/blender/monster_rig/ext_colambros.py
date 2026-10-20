"""rigkit extensions for Colambros (Lane E-Colambros). rigkit.py is shared and
read-only; this module adds what a biped needs without editing it:

    import rigkit, ext_colambros
    ext_colambros.install(rigkit)     # once, before rigkit.build(SPEC, ...)

install() wraps two rigkit builders:

  build_leg  -> a leg with "hang": True is an ARM: its foot box and claws sit
                at the ankle (rigkit snaps every foot to the ground, which is
                right for a planted leg and wrong for a vestigial arm hanging
                off the chest of a creature standing on its hind legs).
                Planted legs ("hang" absent) go through rigkit unchanged.
  build_fins -> after the fins, the QUILL RIDGE: spec["quills"] =
                { role, tip: (r,g,b), items: [ { bone, base, tip, width } ] }.
                Each quill is a four-sided spike (6 tris) coloured per vertex
                from the role's colour at the root to `tip` at the point
                ("bone quills darkening toward the tips"), weighted 100% to
                its `bone` so a bone rotation sways, rattles or flattens it.

Helpers for the build script:
  quill_row(stations, bones, n, ...) -> items along a polyline of spine
                stations: raked back, long over the shoulders, short at the
                ends; one quill bone name per item (the script declares those
                as extra_bones with quill_bones()).
  quill_bones(items, parents) -> the extra_bones tuples for the items.

Everything stays deterministic and in Blender coordinates (Z up, faces -Y).
"""

import math

from mathutils import Matrix, Vector

UP = Vector((0, 0, 1))
FORWARD = Vector((0, -1, 0))

_orig = {}


def install(rigkit):
    """Wrap rigkit.build_leg and rigkit.build_fins (idempotent)."""
    if _orig:
        return
    _orig["build_leg"] = rigkit.build_leg
    _orig["build_fins"] = rigkit.build_fins
    _orig["V"] = rigkit.V

    def build_leg(mb, spec, leg):
        if leg.get("hang"):
            build_arm(mb, spec, leg, rigkit)
        else:
            _orig["build_leg"](mb, spec, leg)

    def build_fins(mb, spec, bones):
        _orig["build_fins"](mb, spec, bones)
        build_quills(mb, spec, rigkit)

    rigkit.build_leg = build_leg
    rigkit.build_fins = build_fins


# ------------------------------------------------------------------ arms
def build_arm(mb, spec, leg, rigkit):
    """A hanging arm: upper arm + forearm tube (rigkit.tube), a wrist ball,
    a paw box at the ankle pointing along ankle->toe, claws off its end."""
    V = rigkit.V
    lid = leg["id"]
    pts = [V(leg["hip"]), V(leg["knee"]), V(leg["ankle"])]
    radii = list(leg["radii"])
    names = ["hip_" + lid, "knee_" + lid, "ankle_" + lid]
    sides = int(leg.get("sides", 6))
    role = leg.get("role", "hide")
    mb.tube(pts, radii, names[:2], float(leg.get("blend", 0.12)), sides, role)
    ankle = pts[2]
    toe = V(leg["toe"])
    fw, fl, fh = leg.get("foot", (0.3, 0.45, 0.16))
    d = toe - ankle
    if d.length < 1e-6:
        d = FORWARD.copy()
    d = d.normalized()
    side = d.cross(UP)
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side = side.normalized()
    up = side.cross(d).normalized()
    basis = Matrix((side, d, up)).transposed()
    centre = ankle + d * (fl * 0.5)
    wtoe = {"toe_" + lid: 0.7, "ankle_" + lid: 0.3}
    mb.box(centre, (fw * 0.5, fl * 0.5, fh * 0.5), basis, wtoe, role)
    mb.sphere(ankle, radii[2] * 1.05, {"ankle_" + lid: 1.0}, role, seg=6, rings=3)
    n = int(leg.get("claws", 3))
    cl = float(leg.get("claw_len", 0.2))
    front = centre + d * (fl * 0.5)
    for i in range(n):
        u = (i + 0.5) / n - 0.5
        base_c = front + side * (u * fw * 0.8)
        hw = fw * 0.4 / n
        hh = fh * 0.35
        base = [base_c + side * hw - up * hh, base_c - side * hw - up * hh,
                base_c - side * hw + up * hh, base_c + side * hw + up * hh]
        tip = base_c + d * cl - up * (fh * 0.2)
        mb.pyramid(base, tip, {"toe_" + lid: 1.0}, leg.get("claw_role", "claw"))


# ------------------------------------------------------------------ quills
def build_quills(mb, spec, rigkit):
    q = spec.get("quills")
    if not q:
        return
    V = rigkit.V
    role = q.get("role", "quill")
    base_c = tuple(spec["roles"].get(role, (0.9, 0.85, 0.7)))
    tip_c = tuple(q.get("tip", (0.2, 0.15, 0.12)))
    for it in q["items"]:
        root = V(it["base"])
        tip = V(it["tip"])
        w = {it["bone"]: 1.0}
        d = tip - root
        if d.length < 1e-6:
            continue
        d = d.normalized()
        side = d.cross(FORWARD)
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side = side.normalized()
        back = side.cross(d).normalized()
        hw = float(it.get("width", 0.08)) * 0.5
        hb = hw * float(it.get("depth", 1.4))
        base = [root + side * hw - back * hb, root - side * hw - back * hb,
                root - side * hw + back * hb, root + side * hw + back * hb]
        # a darker ring two thirds up, then the dark point
        mid_c = tuple(base_c[i] + (tip_c[i] - base_c[i]) * 0.45 for i in range(3))
        mid = root + (tip - root) * 0.62
        mw = hw * 0.55
        mb_ = hb * 0.55
        ring = [mid + side * mw - back * mb_, mid - side * mw - back * mb_,
                mid - side * mw + back * mb_, mid + side * mw + back * mb_]
        b = [mb.add_vert(p, w, role, base_c) for p in base]
        m = [mb.add_vert(p, w, role, mid_c) for p in ring]
        a = mb.add_vert(tip, w, role, tip_c)
        mb.faces.append((tuple(reversed(b)), role))
        for i in range(4):
            j = (i + 1) % 4
            mb.faces.append(((b[i], b[j], m[j], m[i]), role))
            mb.faces.append(((m[i], m[j], a), role))


def quill_row(stations, bones, n, length_fn, rake=0.55, lift=0.08, side=0.0, prefix="quill", start=0.04, end=0.96, width=0.11):
    """Items along the polyline of `stations` (list of (x,y,z) on the dorsal
    line). `bones[i]` names the quill bone of item i (declare them with
    quill_bones). `length_fn(u)` gives the quill length at 0..1 along the
    row; `rake` is how far back the tip leans per metre of length; `side`
    shifts the row sideways. Returns [ { bone, base, tip, width, u } ]."""
    pts = [Vector(s) for s in stations]
    segs = []
    total = 0.0
    for i in range(len(pts) - 1):
        L = (pts[i + 1] - pts[i]).length
        segs.append(L)
        total += L
    items = []
    for i in range(n):
        u = start + (end - start) * (i / float(max(1, n - 1)))
        dist = u * total
        k = 0
        acc = 0.0
        while k < len(segs) - 1 and acc + segs[k] < dist:
            acc += segs[k]
            k += 1
        f = (dist - acc) / max(segs[k], 1e-6)
        p = pts[k].lerp(pts[k + 1], f)
        t = (pts[k + 1] - pts[k]).normalized()           # along the spine (toward the tail: +y)
        # dorsal normal: up, tilted by the spine's slope
        nrm = UP - t * UP.dot(t)
        nrm = nrm.normalized() if nrm.length > 1e-6 else UP
        L = float(length_fn(u))
        base = p + Vector((side, 0.0, 0.0)) + nrm * lift
        tip = base + nrm * L + t * (rake * L)
        items.append({"bone": bones[i], "base": tuple(base), "tip": tuple(tip), "width": width * (0.7 + 0.5 * L), "u": u})
    return items


def quill_bones(items, parent_fn, hint=UP):
    """extra_bones tuples (name, parent, head, tail, roll_hint) for quill items;
    parent_fn(item) names the spine bone it hangs from."""
    out = []
    for it in items:
        out.append((it["bone"], parent_fn(it), it["base"], it["tip"], hint))
    return out
