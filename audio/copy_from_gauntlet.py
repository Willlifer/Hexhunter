"""Copy the borrowed sound effects from Gamers Gauntlet and write audio/sfx/sfx.json.

Run from anywhere:  python -I audio/copy_from_gauntlet.py
Standard library only. Re-running is idempotent (files are overwritten with
the same bytes). The "use" field maps each sound to a Hexhunt event; the
test in tests/test_audio_sfx.gd checks every required event has a sound.
"""
import json
import os
import shutil
import sys

SRC = r"..\Gamers Gauntlet\game\audio\sfx"
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sfx")

# sound name -> Hexhunt event
USE = {
    "elem_fire": "paint:fire", "elem_water": "paint:water", "elem_ice": "paint:ice",
    "elem_thunder": "paint:thunder", "elem_wind": "paint:wind", "elem_dark": "paint:dark",
    "elem_light": "paint:light",
    "tile_detonate": "detonate", "tile_gale": "gale", "tile_glaze": "overfreeze",
    "hit_crit": "overheat", "cast_whoom": "douse",
    "hit_flesh": "hurt", "hit_glance": "hurt", "hit_block": "stagger", "ko_thud": "death",
    "step_stone": "step", "swing_light": "swing", "swing_heavy": "swing", "hit_miss": "swing",
    "bow_draw": "bow", "bow_release": "bow", "arrow_thunk": "bow", "heal": "heal",
}


def main():
    src = json.load(open(os.path.join(SRC, "sfx.json")))
    os.makedirs(DST, exist_ok=True)
    out = {
        "format": src["format"],
        "target_loudness": src["target_loudness"],
        "peak_ceiling_db": src["peak_ceiling_db"],
        "source": "Gamers Gauntlet game/audio/sfx, copied unchanged; use = Hexhunt event",
        "sounds": {},
    }
    copied = 0
    for name, use in USE.items():
        entry = dict(src["sounds"][name])
        entry["use"] = use
        for n in range(1, entry["variants"] + 1):
            for ext in ("wav", "ogg"):
                fn = f"{name}_{n}.{ext}"
                shutil.copyfile(os.path.join(SRC, fn), os.path.join(DST, fn))
                copied += 1
        out["sounds"][name] = entry
    with open(os.path.join(DST, "sfx.json"), "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print(f"{len(out['sounds'])} sounds, {copied} files -> {DST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
