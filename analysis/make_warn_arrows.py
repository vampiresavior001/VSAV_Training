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

The empty button dot (no_button.png) is built the same way, for a late button
in the same trace (user, 2026-09-26: an orange frame round the dots looked
out of place; the arrows already warn by turning their fill orange). Its fill
is the pale (214,227,239), so it has a rule of its own. The pressed dots are
left alone - their colour is which strength was pressed.

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


def is_dot_fill(px):
    return px == (0xD6, 0xE3, 0xEF, 255)


def recolour(name, dst_name, fill):
    src = Image.open(os.path.join(IMAGES, name)).convert("RGBA")
    out = src.copy()
    pix = out.load()
    changed = 0
    for y in range(out.height):
        for x in range(out.width):
            if fill(pix[x, y]):
                pix[x, y] = WARN + (255,)
                changed += 1
    # Nothing but the fill may differ.
    a, b = list(src.getdata()), list(out.getdata())
    for p, q in zip(a, b):
        if p != q:
            assert fill(p) and q == WARN + (255,), (name, p, q)
    assert changed > 0, name
    out.save(os.path.join(IMAGES, dst_name))
    print("%s  %d pixels recoloured" % (dst_name, changed))


def main():
    for n in (1, 2, 3, 4, 6, 7, 8, 9):
        recolour("%d_dir.png" % n, "%d_dir_warn.png" % n, is_fill)
    recolour("no_button.png", "no_button_warn.png", is_dot_fill)


if __name__ == "__main__":
    main()
