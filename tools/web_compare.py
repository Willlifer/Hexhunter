"""Lane Z (H90): Forward+ vs Compatibility side-by-sides for the web build.

Renders the same fight shot in both renderers (Forward+ is the desktop look,
gl_compatibility is what browsers get) and stitches them, Forward+ left,
Compatibility right, into <out>/<tag>_<arena>.png.

    python tools/web_compare.py <out_dir> <tag> [arena:monster ...]

GODOT must point at the Godot 4.7 console binary (test.bat's default is used
when it is unset). Needs a window: --shot reads the drawn frame back.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.join(
    os.path.expanduser("~"), "Downloads", "Godot_v4.7-stable_win64.exe",
    "Godot_v4.7-stable_win64_console.exe")
FIGHTS = ["pond:swampfang", "caldera:colambros", "cave:rimeslithe", "glade:spirewalker"]
RENDERERS = ["forward_plus", "gl_compatibility"]


def shoot(out_dir, arena, monster, renderer, extra):
    d = os.path.join(out_dir, "raw", f"{arena}_{renderer}")
    os.makedirs(d, exist_ok=True)
    args = [GODOT, "--path", ROOT, "--rendering-method", renderer, "--", "--fight", monster,
            "--weapon", "daggers", "--shot", d, "--count", "2", "--every", "2", "--cam", "30,42"]
    if arena != "round":
        args += ["--arena", arena]
    args += extra
    log = subprocess.run(args, capture_output=True, text=True, errors="replace").stdout
    errs = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "ERROR:" in l]
    print(f"{arena} {renderer}: {len(errs)} error lines")
    for l in sorted(set(errs))[:6]:
        print("   ", l[:200])
    return os.path.join(d, "shot_01.png")


def main():
    out_dir = os.path.abspath(sys.argv[1])
    tag = sys.argv[2]
    fights = [f for f in sys.argv[3:] if ":" in f] or FIGHTS
    extra = [f for f in sys.argv[3:] if ":" not in f]
    for f in fights:
        arena, monster = f.split(":")
        imgs = [Image.open(shoot(out_dir, arena, monster, r, extra)).convert("RGB") for r in RENDERERS]
        w, h = imgs[0].size
        sheet = Image.new("RGB", (w * 2, h + 28), (16, 16, 20))
        for i, (im, r) in enumerate(zip(imgs, RENDERERS)):
            sheet.paste(im.resize((w, h)), (i * w, 28))
            ImageDraw.Draw(sheet).text((i * w + 10, 8), f"{arena} / {monster} - {r}", fill=(230, 230, 230))
        sheet = sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS)
        p = os.path.join(out_dir, f"{tag}_{arena}.png")
        sheet.save(p)
        print("wrote", p)


if __name__ == "__main__":
    main()
