# -*- coding: utf-8 -*-
"""Reads the dash_facing marks out of the knockdown logs.

WHAT THIS SETTLES. The engine corrects the lever for facing in two places and
they read different bytes:

    02218E: tst.b ($b,A6)      -> $122 is swapped on $b ALONE
    0221DC: move.b ($120,A6)   -> $12a is swapped on $120 when grounded

guardCancel's facing_for_input() implements the $12a rule. If the dash is
recognised out of $122 instead, every direction injected while $b and $120
disagree arrives as its opposite - and crossing over is exactly when they
disagree, because $120 follows the X positions while $b only moves when the
character actually turns, which a character in a dash does not do.

Each mark packs:

    val = $b * 100000 + $120 * 10000 + used * 1000 + airborne * 100
          + injected lever bits
    pc  = $123 as it stood BEFORE this tick's correction, which is the lever
          the game kept from the PREVIOUS injection

$123 AND NOT $122. The 68000 is big-endian and this is a word: $122 is the
button byte, $123 is the lever. Reading $122 gave 0x00 on every row.

Lever bits: 0x01 and 0x02 are the two horizontals, 0x04 down, 0x08 up.

THE DASH_FACING, SEQ_FRZ AND FACE_HOLD MARKS WERE REMOVED ON 2026-09-23.
Those sections now read archived logs only - see
scripts/reversal_logs_archive/2026-09-20_*. The land_gate section still
works on fresh captures: that mark is kept as a test seam.

Usage:  python read_dash_facing.py [log_dir]
"""
import glob
import json
import os
import sys

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "scripts", "reversal_logs")


def lever(bits):
    names = []
    if bits & 0x01: names.append("L1")
    if bits & 0x02: names.append("L2")
    if bits & 0x04: names.append("down")
    if bits & 0x08: names.append("up")
    return "+".join(names) if names else "-"


def main():
    log_dir = sys.argv[1] if len(sys.argv) > 1 else LOG_DIR
    paths = sorted(glob.glob(os.path.join(log_dir, "kd_*.json")))
    if not paths:
        print("no kd_*.json in", log_dir)
        return

    rows = []
    holds = []
    steps = []
    fires = []
    gates = []
    pend = {}
    for p in paths:
        try:
            with open(p, encoding="utf-8") as fh:
                doc = json.load(fh)
        except Exception as e:
            print("unreadable:", os.path.basename(p), e)
            continue
        for rec in doc.get("records", [doc]):
            for w in rec.get("writes", []):
                # The wait added on 2026-09-20. It is for crossovers only, so
                # a long run of these on a repeated dash means it is firing
                # where it was never meant to.
                if w.get("addr") == "seq_tick":
                    pend[w.get("seq")] = (int(w.get("val") or 0),
                                          int(w.get("pc") or 0))
                    continue
                if w.get("addr") == "seq_frz":
                    v = int(w.get("val") or 0)
                    prev = pend.get((w.get("seq") or 0) - 1, (0, 0))
                    steps.append({
                        "file": os.path.basename(p), "lg": w.get("lg"),
                        "e": (v // 100) % 10, "bits": prev[0] >> 8,
                        "land": (v // 100000) % 10,
                        "saw": (v // 10000) % 10,
                        "air": (v // 1000) % 10,
                        "frz": v % 100,
                        "tl": int(w.get("pc") or 99),
                    })
                    continue
                if w.get("addr") == "land_gate":
                    v = int(w.get("val") or 0)
                    gates.append({
                        "file": os.path.basename(p), "lg": w.get("lg"),
                        "gate": v // 100000,
                        "lead": (v // 1000) % 100,
                        "frz": (v // 10) % 100,
                        "air": v % 10,
                        "tl": int(w.get("pc") or 99),
                    })
                    continue
                if w.get("addr") == "seq_restart":
                    v = int(w.get("val") or 0)
                    fires.append({
                        "file": os.path.basename(p), "lg": w.get("lg"),
                        "e": v // 100, "ent": v % 100,
                        "frz": int(w.get("pc") or 0),
                    })
                    continue
                if w.get("addr") == "face_hold":
                    v = int(w.get("val") or 0)
                    st = int(w.get("pc") or 0)
                    holds.append({
                        "file": os.path.basename(p),
                        "lg":   w.get("lg"),
                        "b":    (v // 1000) % 10,
                        "f120": (v // 100) % 10,
                        "n":    v % 100,
                        "s05":  (st >> 8) & 0xFF,
                        "air":  st & 0xFF,
                    })
                    continue
                if w.get("addr") != "dash_facing":
                    continue
                v = int(w.get("val") or 0)
                rows.append({
                    "file": os.path.basename(p),
                    "lg":   w.get("lg"),
                    "b":    (v // 100000) % 10,
                    "f120": (v // 10000) % 10,
                    "used": (v // 1000) % 10,
                    "air":  (v // 100) % 10,
                    "bits": v % 100,
                    "got":  int(w.get("pc") or 0),
                })

    if not rows and not holds and not steps:
        print("no marks found - is the knockdown logger on?")
        return
    if not rows:
        rows = []

    print("%-20s %4s  %2s %4s %4s %3s  %-10s  %s" %
          ("file", "lg", "$b", "$120", "used", "air", "injected",
           "lever kept last tick"))
    split, flipped = 0, 0
    prev = None
    for r in rows:
        flag = ""
        if r["b"] != r["f120"]:
            flag = "   $b/$120 SPLIT"
            split += 1
        # The direction the game kept, against the one we put in the tick
        # before: opposite horizontals mean the correction went the other way.
        if prev is not None and (prev["bits"] & 0x03) != 0 and (r["got"] & 0x03) != 0:
            if (prev["bits"] & 0x03) != (r["got"] & 0x03):
                flag += "   <<< ARRIVED REVERSED"
                flipped += 1
        print("%-20s %4s  %2d %4d %4d %3d  %-10s  %-10s%s" %
              (r["file"], r["lg"], r["b"], r["f120"], r["used"], r["air"],
               lever(r["bits"]), lever(r["got"] & 0x0F), flag))
        prev = r

    print()
    if gates:
        print()
        print("--- which gate let the landing step out ---")
        print("%-20s %4s  %-14s %5s %6s %5s %4s" %
              ("file", "lg", "gate", "lead", "toLand", "$5C", "air"))
        aimed = missed = 0
        for g in gates:
            name = "landing_ready" if g["gate"] == 1 else "timing_missed"
            note = ""
            if g["gate"] == 2:
                note = "   <<< the prediction was NOT used"
                missed += 1
            else:
                aimed += 1
                if g["tl"] != 99 and g["tl"] > g["lead"]:
                    note = "   <<< opened early for its own lead"
            print("%-20s %4s  %-14s %5d %6s %5d %4d%s" %
                  (g["file"], g["lg"], name, g["lead"],
                   (g["tl"] if g["tl"] != 99 else "-"), g["frz"], g["air"], note))
        print("aimed at the touchdown: %d,  fired by the deadline: %d"
              % (aimed, missed))

    if steps:
        print()
        print("--- the walker, entry by entry ---")
        print("%-20s %4s  %2s %5s %5s %5s %5s %6s" %
              ("file", "lg", "e", "land", "saw", "air", "$5C", "toLand"))
        for t in steps:
            note = ""
            if t["land"] == 0:
                note = "   <<< seq_land NOT set - the landing guard cannot fire"
            elif t["tl"] == 99 and t["air"]:
                note = "   <<< airborne but not on the way down"
            print("%-20s %4s  %2d %5d %5d %5d %5d %6s%s" %
                  (t["file"], t["lg"], t["e"], t["land"], t["saw"], t["air"],
                   t["frz"], (t["tl"] if t["tl"] != 99 else "-"), note))
    if fires:
        print()
        print("--- the restart guard firing ---")
        for f in fires:
            print("%-20s lg %-4s entry %d after %d ticks, $5C=%d" %
                  (f["file"], f["lg"], f["e"], f["ent"], f["frz"]))
    else:
        print()
        print("--- the restart guard NEVER fired ---")

    if holds:
        print()
        print("--- the turn wait (face_hold) ---")
        print("%-20s %4s  %2s %4s %4s  %4s %4s" %
              ("file", "lg", "$b", "$120", "held", "$05", "air"))
        capped = 0
        for h in holds:
            note = ""
            if h["s05"] == 0 and h["air"] == 0:
                note = "   <<< on the ground and not stunned"
            if h["n"] > 10:
                capped += 1
            print("%-20s %4s  %2d %4d %4d  0x%02X %4d%s" %
                  (h["file"], h["lg"], h["b"], h["f120"], h["n"],
                   h["s05"], h["air"], note))
        print("waits: %d,  ticks past the cap: %d" % (len(holds), capped))
        print("A repeated dash should show a handful. Dozens means the wait is")
        print("firing on ordinary point-blank range, not on a crossover.")

    print()
    print("marks: %d,  $b/$120 splits: %d,  arrived reversed: %d"
          % (len(rows), split, flipped))
    if flipped > 0:
        print("The game turned an injected direction into its opposite. That is")
        print("$122 being corrected on $b while the tool resolved on $120.")
    elif split == 0:
        print("The two bytes never split here, so this is NOT the cause.")
    else:
        print("They split, but nothing arrived reversed - so what breaks the")
        print("dash is the tool changing its own answer between the two taps,")
        print("not the engine correcting it the other way.")


if __name__ == "__main__":
    main()
