"""CPS2 sprite graphics decoder for vsav (static, for the UBK shadow survey).

Region build follows MAME cps2.cpp for vsav: ROM_LOAD64_WORD of
13m/15m/17m/19m at 0,2,4,6 (first 16MB) and 14m/16m/18m/20m (second 16MB),
then cps2_gfx_decode's unshuffle on every 0x200000 bank, then
cps1_layout16x16 (planes {24,16,8,0}, x {STEP8(0,1), STEP8(32,1)},
y STEP16(0,64), 128 bytes a tile). Pen 15 is transparent for sprites.
"""
import sys
import zipfile
import numpy as np

HALVES = [["vm3.13m", "vm3.15m", "vm3.17m", "vm3.19m"],
          ["vm3.14m", "vm3.16m", "vm3.18m", "vm3.20m"]]


def unshuffle(buf):
    n = len(buf)
    if n == 2:
        return
    half = n // 2
    unshuffle(buf[:half])
    unshuffle(buf[half:])
    q = half // 2
    t = buf[q:half].copy()
    buf[q:half] = buf[half:half + q]
    buf[half:half + q] = t


def load_region(zip_path, which_half):
    with zipfile.ZipFile(zip_path) as z:
        parts = [np.frombuffer(z.read(n), dtype=np.uint8) for n in HALVES[which_half]]
    size = 0x1000000
    out = np.zeros(size, dtype=np.uint8)
    for k, p in enumerate(parts):
        words = p.reshape(-1, 2)
        dst = out.reshape(-1, 8)
        dst[:, 2 * k:2 * k + 2] = words
    q = out.view(np.uint64)
    bank = 0x200000 // 8
    for i in range(0, len(q), bank):
        unshuffle(q[i:i + bank])
    return out


class Gfx:
    def __init__(self, zip_path):
        self.zip_path = zip_path
        self.half = {}

    def tile(self, code):
        """16x16 array of pens (0..15) for an 18-bit tile code."""
        off = code * 128
        h = off // 0x1000000
        if h not in self.half:
            self.half[h] = load_region(self.zip_path, h)
        b = self.half[h][off % 0x1000000: off % 0x1000000 + 128].reshape(16, 2, 4)
        pens = np.zeros((16, 16), dtype=np.uint8)
        for g in range(2):
            for x in range(8):
                mask = 0x80 >> x
                pen = np.zeros(16, dtype=np.uint8)
                for plane_bit, byte_i in ((3, 3), (2, 2), (1, 1), (0, 0)):
                    pen |= (((b[:, g, byte_i] & mask) != 0).astype(np.uint8) << plane_bit)
                pens[:, g * 8 + x] = pen
        return pens


def block(gfx, code, nx, ny, flipx=False):
    """A CPS sprite block, as MAME's cps1 renderer lays its tiles out."""
    img = np.full((16 * ny, 16 * nx), 15, dtype=np.uint8)
    for j in range(ny):
        for i in range(nx):
            src_i = (nx - 1 - i) if flipx else i
            c = (code & ~0xF) + ((code + src_i) & 0xF) + 0x10 * j
            t = gfx.tile(c)
            if flipx:
                t = t[:, ::-1]
            img[16 * j:16 * j + 16, 16 * i:16 * i + 16] = t
    return img


if __name__ == "__main__":
    from PIL import Image
    zp, first, count, out = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3]), sys.argv[4]
    g = Gfx(zp)
    cols = 16
    rows = (count + cols - 1) // cols
    sheet = np.full((rows * 17, cols * 17), 15, dtype=np.uint8)
    for k in range(count):
        t = g.tile(first + k)
        r, c = divmod(k, cols)
        sheet[r * 17:r * 17 + 16, c * 17:c * 17 + 16] = t
    rgb = np.zeros(sheet.shape + (3,), dtype=np.uint8)
    rgb[:] = (255, 0, 255)
    vis = sheet != 15
    shade = (sheet.astype(np.int32) * 16).clip(0, 255).astype(np.uint8)
    rgb[vis] = np.stack([shade[vis]] * 3, axis=1)
    Image.fromarray(rgb).resize((rgb.shape[1] * 3, rgb.shape[0] * 3), Image.NEAREST).save(out)
    print("saved", out, sheet.shape)
