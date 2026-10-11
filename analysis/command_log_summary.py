"""Read scripts/reversal_logs/command_log.jsonl (scripts/commandLog.lua) and
answer what the probe is for (analysis/COMMAND_TRAINER_DESIGN.ja.md, section 7):

  1. the timer each accepted step set at +4 - is it always 14-19?
  2. when the timer ran out: how many recognizer calls after the last accepted
     step, against the timer that step set
  3. how many calls and ticks went by between accepted steps
  4. a completed command against a started move (meter at the test)

Usage: python analysis/command_log_summary.py [path to command_log.jsonl]
"""
import collections
import json
import os
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts",
                       "reversal_logs", "command_log.jsonl")
NAMES = [(0x0100, "LP"), (0x0200, "MP"), (0x0400, "HP"), (0x1000, "LK"), (0x2000, "MK"),
         (0x4000, "HK"), (0x0001, "back"), (0x0002, "forward"), (0x0004, "down"), (0x0008, "up")]
STEPS = ["LP", "LP", "forward", "LK", "HP"]


def keys(edge_hex):
    v = int(edge_hex, 16)
    out = [n for b, n in NAMES if v & b]
    rest = v & ~0x770F
    if rest:
        out.append("0x%04X" % rest)
    return "+".join(out) or "-"


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    rows = []
    for line in open(path, encoding="utf-8"):
        o = json.loads(line)
        if "seq" in o:          # the first line is the header
            rows.append(o)
    print("rows:", len(rows), "from", path)

    timers = collections.Counter()
    gaps = []        # (from step, to step, calls, ticks, timer set by the from step)
    expiries = []    # (waiting for, calls since the last step, timer it set, ticks)
    ends = collections.Counter()
    for p in (1, 2):
        mine = [r for r in rows if r["p"] == p]
        if not mine:
            continue
        print("\n== P%d" % p)
        last_step = None      # the row of the last accepted step
        calls_since = 0
        for r in mine:
            calls_since += r["calls"]
            k = r["kind"]
            tick = r["tick"]
            if k == "step":
                if r["step"] == 1:
                    print("  --- attempt at tick %d" % tick)
                elif last_step is not None:
                    gaps.append((last_step["step"], r["step"], calls_since,
                                 tick - last_step["tick"], last_step["tm2"]))
                timers[r["tm2"]] += 1
                print("  tick %6d  step %d %-7s accepted   timer %2d   (%d calls since the last step)"
                      % (tick, r["step"], keys(r["edge"]), r["tm2"], calls_since if r["step"] > 1 else 0))
                last_step, calls_since = r, 0
            elif k == "complete":
                if last_step is not None:
                    gaps.append((last_step["step"], 5, calls_since, tick - last_step["tick"], last_step["tm2"]))
                print("  tick %6d  step 5 %-7s COMPLETE   (%d calls since the last step)"
                      % (tick, keys(r["edge"]), calls_since))
                last_step, calls_since = None, 0
                ends["complete"] += 1
            elif k == "met":
                print("  tick %6d  meter test: meter %d" % (tick, r["meter"]))
            elif k == "started":
                print("  tick %6d  STARTED: move %s state %s" % (tick, r["move"], r["state"]))
                ends["started"] += 1
            elif k == "expired":
                if last_step is not None:
                    expiries.append((r["step"], calls_since, last_step["tm2"], tick - last_step["tick"]))
                    print("  tick %6d  EXPIRED waiting for step %d (%s): %d calls after step %d, which set %d"
                          % (tick, r["step"], STEPS[r["step"] - 1], calls_since, last_step["step"], last_step["tm2"]))
                else:
                    print("  tick %6d  EXPIRED waiting for step %d (the step before it is not in the log)"
                          % (tick, r["step"]))
                last_step, calls_since = None, 0
                ends["expired"] += 1
            elif k == "miss":
                if r["step"] > 1:
                    print("  tick %6d    miss: %-9s while waiting for step %d (%s)"
                          % (tick, keys(r["edge"]), r["step"], STEPS[r["step"] - 1]))
            elif k == "cleared":
                print("  tick %6d  CLEARED from outside while waiting for step %d (state %s)"
                      % (tick, r["step"], r["state"]))
                last_step, calls_since = None, 0
                ends["cleared"] += 1

    print("\n== 1. timers set at +4:", dict(sorted(timers.items())))
    outside = [t for t in timers if not 14 <= t <= 19]
    print("   all within 14-19" if timers and not outside else "   OUTSIDE 14-19: %s" % outside)
    print("\n== 2. expiries (calls after the last step == the timer it set?)")
    for w, c, t, ticks in expiries:
        print("   waiting for step %d: %d calls, %d ticks, timer %d  %s"
              % (w, c, ticks, t, "same" if c == t else "DIFFERENT"))
    print("\n== 3. accepted steps: calls since the step before, and the timer it set")
    for a, b, c, ticks, t in gaps:
        print("   step %d -> %d: %d calls, %d ticks, timer %d  %s"
              % (a, b, c, ticks, t, "within" if c < t else "NOT BELOW THE TIMER"))
    print("\n== 4.", dict(ends))


if __name__ == "__main__":
    main()
