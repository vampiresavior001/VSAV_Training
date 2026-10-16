"""The visible bounds of every character shadow, for scripts/shadowGuide.lua.

Usage:  python analysis/gen_shadow_bounds.py          (prints the Lua table)
        python analysis/gen_shadow_bounds.py --png    (also writes analysis/shadow_shapes.png)

Static, from the ROMs in analysis/mame_roms (vsavj program, vsav graphics).

THE ROUTE (ROM, analysis/mame_code c18.txt; design UBK_SHADOW_GUIDE_DESIGN,
2026-10-16). 01BC9C draws one ground sprite for each player:
  01BCB0  the height is $3A (the ground under it), not $14
  01BCBA  ($1C,A6) the cel; cel+$11 the shape number, 0 = none
  01BCC4  cel+$15 a signed x offset, negated when $0B (facing) is set
  01BCD4  0x2837EC + word[2837EC + 2n] -> long at +4: the shape's descriptor
  01BD46  mode 2: parts of (tile, attr), x/y from a table. Flipped, a part's
          x becomes -x - width (01BD6A) and attr bit 5 is toggled
The tiles are 16x16, 4 bits; pen 15 is transparent (cps2_gfx.py).

THE OUTPUT. For each shape number, the columns [L, R) and rows [T, B) that
have a visible pixel, relative to the point the shape is placed at (the
player's X + the cel's offset), unflipped. Flipped, a pixel at u lands at
-u - 1, so the columns become [-R, -L). Every shape is a dark ellipse, palette
0x16, pen 0.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from vsav_tool import Rom          # noqa: E402
from cps2_gfx import Gfx, block    # noqa: E402

TABLE = 0x2837EC


def signed(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def shapes(r):
    """Every shape number the table holds: the entries stop where an offset
    no longer points at a mode-2 descriptor inside the ROM."""
    n = 1
    while True:
        off = r.d16(TABLE + 2 * n)
        entry = TABLE + off
        if entry + 8 > len(r.data):
            return
        p = r.d32(entry + 4)
        if p + 10 > len(r.data) or r.d16(p) != 2:
            return
        yield n, p
        n += 1


def parts_of(r, p):
    count = r.d16(p + 4) + 1
    xy = r.d32(p + 6)
    out = []
    for j in range(count):
        tile, attr = r.d16(p + 10 + 4 * j), r.d16(p + 12 + 4 * j)
        x, y = signed(r.d16(xy + 4 * j), 16), signed(r.d16(xy + 4 * j + 2), 16)
        out.append((x, y, tile, attr))
    return out


def visible(g, parts):
    import numpy as np
    x0 = min(q[0] for q in parts)
    y0 = min(q[1] for q in parts)
    x1 = max(q[0] + 16 * ((q[3] >> 8 & 15) + 1) for q in parts)
    y1 = max(q[1] + 16 * ((q[3] >> 12 & 15) + 1) for q in parts)
    canvas = np.full((y1 - y0, x1 - x0), 15, dtype=np.uint8)
    for x, y, tile, attr in parts:
        nx, ny = (attr >> 8 & 15) + 1, (attr >> 12 & 15) + 1
        img = block(g, tile, nx, ny, flipx=bool(attr & 0x20))
        sub = canvas[y - y0:y - y0 + 16 * ny, x - x0:x - x0 + 16 * nx]
        sub[img != 15] = img[img != 15]
    vis = canvas != 15
    cols = np.where(vis.any(axis=0))[0]
    rows = np.where(vis.any(axis=1))[0]
    return (x0 + int(cols[0]), x0 + int(cols[-1]) + 1, y0 + int(rows[0]), y0 + int(rows[-1]) + 1), canvas


def main():
    r = Rom(os.path.join(HERE, "mame_code"), os.path.join(HERE, "mame_roms", "vsavj.zip"))
    assert r.data, "analysis/mame_roms/vsavj.zip is missing"
    g = Gfx(os.path.join(HERE, "mame_roms", "vsav.zip"))
    rows, canvases = [], []
    for n, p in shapes(r):
        (L, R, T, B), canvas = visible(g, parts_of(r, p))
        rows.append((n, L, R, T, B))
        canvases.append(canvas)
    print("-- %d shapes, from analysis/gen_shadow_bounds.py" % len(rows))
    print("M.SHAPES = {")
    for n, L, R, T, B in rows:
        print("\t[%d] = { %d, %d, %d, %d }," % (n, L, R, T, B))
    print("}")
    if "--png" in sys.argv:
        import numpy as np
        from PIL import Image
        h = sum(c.shape[0] + 4 for c in canvases)
        w = max(c.shape[1] for c in canvases)
        sheet = np.full((h, w), 15, dtype=np.uint8)
        y = 0
        for c in canvases:
            x = (w - c.shape[1]) // 2
            sheet[y:y + c.shape[0], x:x + c.shape[1]] = c
            y += c.shape[0] + 4
        rgb = np.zeros(sheet.shape + (3,), dtype=np.uint8)
        rgb[:] = (255, 0, 255)
        rgb[sheet != 15] = (0, 0, 0)
        Image.fromarray(rgb).resize((w * 3, h * 3), Image.NEAREST).save(os.path.join(HERE, "shadow_shapes.png"))


if __name__ == "__main__":
    main()
