"""Read wake-up facing and the first action from existing knockdown logs.

This is read-only. The short action window is for displaying evidence, not
an acceptance window or a change to input timing.
"""
import json
from pathlib import Path
import sys

from classify_reversals import reconstruct, get_byte


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        Path(__file__).resolve().parent.parent / "scripts" / "reversal_logs")
    for path in sorted(directory.glob("kd_*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        frames = reconstruct(doc.get("rows", []))
        rows = sorted(frames.items())
        for i, (frame, mem) in enumerate(rows):
            if i == 0:
                continue
            before = rows[i - 1][1]
            if not (get_byte(before, 0xFF8805) == 2
                    and get_byte(mem, 0xFF8805) == 0
                    and get_byte(before, 0xFF8940) == 0x0A):
                continue
            around = [(f, m) for f, m in rows if frame - 6 <= f <= frame + 12]
            actions = [(f, get_byte(m, 0xFF8806)) for f, m in around
                       if f >= frame and get_byte(m, 0xFF8806) in (0x0A, 0x14)]
            result = ("%02X@%+df" % (actions[0][1], actions[0][0] - frame)
                      if actions else "none in +12f")
            faces = [(f, get_byte(m, 0xFF880B), get_byte(m, 0xFF8920))
                     for f, m in around]
            changes = []
            for j, face in enumerate(faces):
                if j == 0 or face[1:] != faces[j - 1][1:]:
                    changes.append("%+d:%d/%d" % (face[0] - frame, *face[1:]))
            marks = [w for w in doc.get("writes", [])
                     if frame - 6 <= w.get("f", -1) <= frame + 3
                     and w.get("addr") in ("kd_step", "press_defer", "press_now",
                                           "dash_facing", "face_hold")]
            print("%s free=%d first=%s facing(b/side)=%s" %
                  (path.name, frame, result, " ".join(changes)))
            if result.startswith("0A") or not result.startswith("14"):
                for w in marks:
                    print("  f=%+d lg=%s %-12s val=%s pc=%s" %
                          (w["f"] - frame, w.get("lg"), w["addr"],
                           w.get("val"), w.get("pc")))


if __name__ == "__main__":
    main()
