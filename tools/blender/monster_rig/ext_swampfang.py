"""Swampfang additions (Phase 3.5 gauntlet, Lane MB) to the Monster Rig
Builder, from SPEC keys rigkit ignores. Geometry goes through shapes_mb.

    import ext_swampfang as ext
    row = ext.build(SPEC, glb_path, blend_path)

  skull     { bone, rings: [{p, rx, rz, flat}], palate_below }: the heavy
            crocodilian upper head (hide on top, a dark-red palate under it)
  lower_jaw { bone, rings, teeth, tooth, mouth_above, belly_below }: a deep
            jaw loft: red mouth on top, hide on the sides, cream underneath,
            teeth along both edges
  throat    { rings, bones, blend }: the cream throat pouch under the neck,
            from the jaw hinge back onto the chest
  brows     [ { bone, at, size } ]: heavy brow ridges over the eyes
  sails     [ { ra, rb, tip, bones, blend, bow, hollow, ribs } ]: the red
            swept fins (crest, dorsal sails, tail sail), weighted by the
            nearest of `bones`, so a tail sail bends with the tail; a sail
            with `bone` + `parent` rides its own fold bone instead
            (sail_bones(spec) gives the extra-bone tuples)
  plates    [ { stations (chain name), bones, ys: [...], xs: [...], r, h } ]:
            raised scale plates on a loft's upper surface
"""

import rigkit
import shapes_mb as sh
from mathutils import Vector

V = rigkit.V


def _chain(spec, name):
    for ch in spec.get("chains", []):
        if ch["name"] == name:
            return ch
    raise KeyError(name)


def build_skull(mb, spec):
    s = spec["skull"]
    w = {s["bone"]: 1.0}
    below = float(s.get("palate_below", -0.62))
    col = sh.mottle_fn(spec, 11)
    sh.loft(mb, s["rings"], lambda c: w,
            lambda i, k, z: "mouth" if (z < below and i > 0) else ("belly" if z < below else "hide"),
            int(s.get("sides", 12)), True, True, col)


def build_lower_jaw(mb, spec):
    j = spec["lower_jaw"]
    w = {j["bone"]: 1.0}
    above = float(j.get("mouth_above", 0.75))
    below = float(j.get("belly_below", 0.05))
    col = sh.mottle_fn(spec, 23)
    rings = j["rings"]
    sides = int(j.get("sides", 10))
    sh.loft(mb, rings, lambda c: w,
            lambda i, k, z: "mouth" if z > above else ("belly" if z < below else "hide"), sides, True, True, col)
    # teeth: along both lips, pointing up
    n = int(j.get("teeth", 6))
    tl = float(j.get("tooth", 0.2))
    ys = [float(r["p"][1]) for r in rings]
    stations = [{"p": r["p"], "rx": r["rx"], "rz": r["rz"]} for r in rings]
    for side in (1, -1):
        for i in range(n):
            u = (i + 0.5) / n
            y = ys[0] + (ys[-1] - ys[0]) * (0.12 + 0.84 * u)
            cz, rx, rz, _ = sh.station_at(stations, y)
            c = Vector((side * rx * 0.74, y, cz + rz * 0.62))
            hw = tl * 0.28
            bp = [c + Vector((hw, hw, 0)), c + Vector((-hw, hw, 0)), c + Vector((-hw, -hw, 0)), c + Vector((hw, -hw, 0))]
            mb.pyramid(bp, c + Vector((0, 0, tl * (1.15 if i % 2 == 0 else 0.8))), w, "teeth")


def build_throat(mb, spec):
    t = spec["throat"]
    names = t["bones"]
    blend = float(t.get("blend", 0.5))
    below = float(t.get("belly_below", 0.35))

    def role(i, k, z):
        return "belly" if z < below else "hide"

    def col(i, k, r):
        if r == "belly":
            c = spec["roles"]["belly"]
            return sh.scale(c, 0.86 if i % 2 else 1.0)        # the throat's cross bands
        return sh.mottle_fn(spec, 31)(i, k, r)

    sh.loft(mb, t["rings"], lambda c: mb.auto_weight(c, names, blend), role, int(t.get("sides", 10)), True, True, col)


def build_brows(mb, spec):
    for b in spec.get("brows", []):
        at = V(b["at"])
        sx, sy, sz = b["size"]
        tip = at + Vector((0.0, -sy, -sz * 0.4))
        back = at + Vector((0.0, sy * 0.6, sz * 0.3))
        out = Vector((sx * (1 if at.x > 0 else -1), 0, 0))
        base = [back + out * 0.5, back - out * 0.5, back - out * 0.5 - Vector((0, 0, sz)), back + out * 0.5 - Vector((0, 0, sz))]
        mb.pyramid(list(reversed(base)), tip, {b["bone"]: 1.0}, "hide", color=b.get("color"))


def build_sails(mb, spec):
    roles = spec["roles"]
    for s in spec.get("sails", []):
        names = s["bones"]
        blend = float(s.get("blend", 0.4))
        role = s.get("role", "fin")
        base = roles[role]
        if s.get("bone"):
            wf = (lambda p, bn=s["bone"]: {bn: 1.0})          # a fold bone: the whole sail lays flat
        else:
            wf = (lambda p, n=names, bl=blend: mb.auto_weight(p, n, bl))
        sh.sail(mb, s["ra"], s["rb"], s["tip"], wf, role,
                bow=float(s.get("bow", 0.14)), hollow=float(s.get("hollow", 0.2)), thick=float(s.get("thick", 0.05)),
                root_col=sh.scale(base, 0.72), tip_col=sh.scale(base, 1.12), segs=int(s.get("segs", 3)),
                ribs=int(s.get("ribs", 0)), rib_col=sh.scale(base, 0.55))


def sail_bones(spec):
    """Extra-bone tuples for sails carrying a `bone`: from the root middle
    toward the tip, parented to `parent`; a pitch about the root folds it."""
    out = []
    for s in spec.get("sails", []):
        if not s.get("bone"):
            continue
        rm = (V(s["ra"]) + V(s["rb"])) * 0.5
        out.append((s["bone"], s["parent"], tuple(rm), tuple(rm + (V(s["tip"]) - rm) * 0.5), rigkit.FORWARD))
    return out


def build_plates(mb, spec):
    for p in spec.get("plates", []):
        st = _chain(spec, p["chain"])["stations"] if "chain" in p else p["stations"]
        names = p["bones"]
        cols = p.get("colors")
        k = 0
        for y in p["ys"]:
            for x in p["xs"]:
                hit = sh.surface(st, x, y)
                if hit is None:
                    continue
                pt, nrm = hit
                r = float(p["r"]) * (0.85 + 0.3 * rigkit._hash01(k, 3, 7))
                c = cols[k % len(cols)] if cols else None
                sh.boss(mb, pt, nrm, r, float(p["h"]), mb.auto_weight(pt, names, 0.3), "hide", c,
                        n=int(p.get("n", 6)), spin=0.5 * (k % 2), stretch=float(p.get("stretch", 1.3)))
                k += 1


def build(spec, glb_path, blend_path=None):
    row = sh.build_with(spec, glb_path, blend_path, extras=[
        build_skull, build_lower_jaw, build_throat, build_brows, build_sails, build_plates])
    row["jaw"] = spec["lower_jaw"]["bone"]
    return row
