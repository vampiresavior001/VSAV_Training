"""Build the warning-coloured direction arrows for GC Command Trace.

gui.image (FBNeo's gui.gdoverlay) takes a position, an image and an opacity -
there is no colour argument, so an arrow cannot be tinted when it is drawn.
The warning arrows are therefore separate images, derived here from the
input viewer's own arrows so the two can never drift apart.

Only the white fill changes. A pixel is recoloured when it is fully opaque and
every channel is 240 or more - the arrows use exactly (255,255,255) on the
diagonals and (247,255,247) on the straights. The black outline (16,16,0) and
every transparent pixel (alpha 0, whatever its RGB) are copied untouched.
The neutral arrow (5) has no white and is not built; the drawing falls back to
the ordinary one.

Usage (from the fbneo repo root):
    python analysis/make_warn_arrows.py
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(ROOT, "scripts", "images")

# Must match GCT_WARN in scripts/hud.lua.
WARN = (0xFF, 0x7F, 0x00)


def is_fill(px):
    r, g, b, a = px
    return a == 255 and min(r, g, b) >= 240


def main():
    for n in (1, 2, 3, 4, 6, 7, 8, 9):
        src = Image.open(os.path.join(IMAGES, "%d_dir.png" % n)).convert("RGBA")
        out = src.copy()
        pix = out.load()
        changed = 0
        for y in range(out.height):
            for x in range(out.width):
                if is_fill(pix[x, y]):
                    pix[x, y] = WARN + (255,)
                    changed += 1
        # Nothing but the fill may differ.
        a, b = list(src.getdata()), list(out.getdata())
        for p, q in zip(a, b):
            if p != q:
                assert is_fill(p) and q == WARN + (255,), (n, p, q)
        assert changed > 0, n
        dst = os.path.join(IMAGES, "%d_dir_warn.png" % n)
        out.save(dst)
        print("%d_dir_warn.png  %d pixels recoloured" % (n, changed))


if __name__ == "__main__":
    main()
