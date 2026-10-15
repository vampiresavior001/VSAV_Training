"""
What the chain and rapid cancel check did, counted from the contact.

Reads scripts/chainLog.lua's log (reversal_logs/chain_log.jsonl, or an
archive's copy). For every body contact (the attacker's $169 set to 14) it
follows that attacker until its next contact, and lists:

  press   a tick whose $126 had an attack button: Tick from the contact (C+n),
          $169 as that update's check saw it, the buttons, and what the check
          did on that tick - accepted (chain / rapid), or the last stage it
          passed
  hold    a press held into $12E during hit stop
  accept  a check that accepted, with the presses that came before it

and, for the link window, the Ticks from each react (the impact freeze over)
to the next sig (the reversal tick) of the same player, by its $59 / $140.

Then one table over every contact: for each C+n, how many presses there were
and what the check made of them. This is the observation the Chain Trainer's
window has to be drawn from (handoff 2026-10-14, section 10 A): a press is
"accepted" only when the check on that tick accepted, so a press held and
used later shows as held here and as an accept on the later tick.

Usage:  python analysis/chain_log_summary.py [chain_log.jsonl] [--detail]
"""
import collections
import json
import os
import sys

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "scripts", "reversal_logs", "chain_log.jsonl")
BUTTON = {0x0100: "LP", 0x0200: "MP", 0x0400: "HP", 0x1000: "LK", 0x2000: "MK", 0x4000: "HK"}


def buttons(word):
    w = int(word, 16) if isinstance(word, str) else (word or 0)
    return "+".join(n for b, n in sorted(BUTTON.items()) if w & b)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    detail = "--detail" in sys.argv
    path = args[0] if args else LOG
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            if "seq" in r:
                rows.append(r)
    rows.sort(key=lambda r: r["seq"])
    print("%s: %d rows" % (path, len(rows)))

    contacts = [r for r in rows if r["kind"] == "contact"]
    table = collections.defaultdict(collections.Counter)
    for i, c in enumerate(contacts):
        p, C = c["p"], c["tick"]
        nxt = next((d["tick"] for d in contacts[i + 1:] if d["p"] == p), None)
        span = [r for r in rows if r["p"] == p and r["seq"] > c["seq"]
                and (nxt is None or r["tick"] < nxt) and r["tick"] <= C + 40]
        checks = collections.defaultdict(list)
        for r in span:
            if r["kind"] == "check":
                checks[r["tick"]].append(r)
        if detail:
            print("== contact p%d at tick %d (lg %d), char %s, opp p%d"
                  % (p, C, c["lg"], c["char"], c.get("opp", 0)))
        for r in span:
            n = r["tick"] - C
            if r["kind"] == "tick" and buttons(r["edge"]):
                cs = checks.get(r["tick"], [])
                acc = next((x["accept"] for x in cs if x.get("accept")), "")
                what = acc or (cs[-1]["stage"] if cs else "no check")
                table[n][what] += 1
                if detail:
                    print("   C%+3d press %-5s t169 %2d held %-5s hs %2d  -> %s"
                          % (n, buttons(r["edge"]), r["t169"], buttons(r["held"]), r["hs"], what))
            elif r["kind"] == "hold" and detail:
                print("   C%+3d hold  %-5s t169 %2d hs %2d" % (n, buttons(r["edge"]), r["t169"], r["hs"]))
            elif r["kind"] == "check" and r.get("accept"):
                if not buttons(r["edge"]):
                    table[n][r["accept"] + " (held)"] += 1
                if detail:
                    print("   C%+3d ACCEPT %s  btn %s mask %s  next str %d typ %d  path %s"
                          % (n, r["accept"], buttons(r["d0"]), r["d1"], r["next_str"], r["next_typ"], r["path"]))

    print()
    print("contacts: %d" % len(contacts))
    print("C+n   what the check did on the tick of the press (count)")
    for n in sorted(table):
        print("C%+3d  %s" % (n, ", ".join("%s %d" % kv for kv in sorted(table[n].items()))))

    # THE REVERSAL TICK, FROM THE END OF THE IMPACT FREEZE (react -> sig).
    # guardCancel.lua's HS_LEAD_BY_59 says 14 / 19 / 23 by $59; a link's window
    # can be drawn in advance only if this is one number per class.
    lead = collections.defaultdict(collections.Counter)
    last_react = {}
    for r in rows:
        if r["kind"] == "react":
            last_react[r["p"]] = r
        elif r["kind"] == "sig":
            a = last_react.pop(r["p"], None)
            if a is not None:
                lead[(a["s59"], a["s140"])][r["tick"] - a["tick"]] += 1
    print()
    print("react -> sig (the reversal tick), by $59 / $140 of the react: Ticks (count)")
    for k in sorted(lead):
        print("  $59 %d  $140 0x%02X : %s" % (k[0], k[1], ", ".join("%dt %d" % kv for kv in sorted(lead[k].items()))))


if __name__ == "__main__":
    main()
