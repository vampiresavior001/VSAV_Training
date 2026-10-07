# -*- coding: utf-8 -*-
"""Fill an Action Steps sequence with a repeated step, for load testing.

Building 4096 steps by hand is not possible, so the list is written straight
into training_settings.json. The step that gets repeated is one that is already
in the sequence, so whatever it does in game is what it did before - this only
changes HOW MANY.

  python analysis/gen_max_steps.py show
  python analysis/gen_max_steps.py fill --char 1 --count 4096
  python analysis/gen_max_steps.py restore

The first fill copies the whole settings file to analysis/ (never packaged,
gitignored). restore puts that copy back. Close FBNeo first: it writes the file
on exit and would overwrite this.
"""
import argparse
import io
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# training_data/ since the settings moved out of scripts/ (2026-10-07). The old
# scripts/ copy is a backup the tool no longer reads or writes.
SETTINGS = os.path.join(ROOT, "training_data", "training_settings.json")
BACKUP = os.path.join(HERE, "training_settings.backup.json")

# actionSequenceEditor.lua: local MAX_STEPS = 4096
MAX_STEPS = 4096

CHARS = {
    0x00: "Bulleta", 0x01: "Demitri", 0x02: "Gallon", 0x03: "Victor",
    0x04: "Zabel", 0x05: "Morrigan", 0x06: "Anakaris", 0x07: "Felicia",
    0x08: "Bishamon", 0x09: "Aulbath", 0x0A: "Sasquatch", 0x0B: "Zabel 2",
    0x0C: "Q-Bee", 0x0D: "Lei-Lei", 0x0E: "Lilith", 0x0F: "Jedah",
    0x12: "Dark Gallon", 0x18: "Oboro",
}


def char_name(key):
    try:
        return CHARS.get(int(key), "Char %02X" % int(key))
    except ValueError:
        return "Char " + str(key)


def load(path):
    with io.open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save(path, data):
    # dkjson's shape: two space indent, no space after the colon, CRLF - the
    # tool rewrites the file on its own save anyway, but a matching shape keeps
    # a hand diff readable.
    text = json.dumps(data, indent=2, separators=(",", ":"), ensure_ascii=True)
    text = text.replace(chr(10), chr(13) + chr(10)) + chr(13) + chr(10)
    with io.open(path, "w", encoding="ascii", newline="") as f:
        f.write(text)


def steps_of(data, trigger, char):
    per = (data.get("action_sequences") or {}).get(trigger)
    if not isinstance(per, dict):
        return None
    if "steps" in per:
        return None                      # pre-split entry, belongs to no one
    entry = per.get(str(char))
    if not isinstance(entry, dict):
        return None
    return entry.get("steps")


def cmd_show(args):
    data = load(SETTINGS)
    root = data.get("action_sequences") or {}
    for trigger in sorted(root.keys()):
        per = root[trigger]
        if not isinstance(per, dict):
            continue
        if "steps" in per:
            print("%-10s (pre-split)  %d steps" % (trigger, len(per["steps"])))
            continue
        for key in sorted(per.keys(), key=lambda k: int(k) if k.isdigit() else 999):
            n = len(per[key].get("steps") or [])
            print("%-10s %-3s %-12s %d steps" % (trigger, key, char_name(key), n))
    print("backup: " + ("present" if os.path.exists(BACKUP) else "none"))
    return 0


def cmd_fill(args):
    if args.count < 1 or args.count > MAX_STEPS:
        print("count must be 1..%d (the editor's own MAX_STEPS)" % MAX_STEPS)
        return 1
    data = load(SETTINGS)
    steps = steps_of(data, args.trigger, args.char)
    if steps is None or len(steps) == 0:
        print("no sequence saved for %s / %s (%s)"
              % (args.trigger, args.char, char_name(args.char)))
        print("save one in the editor first - this tool only multiplies a step.")
        return 1

    index = args.template if args.template is not None else len(steps)
    if index < 1 or index > len(steps):
        print("--template must be 1..%d" % len(steps))
        return 1
    template = steps[index - 1]

    if not os.path.exists(BACKUP):
        shutil.copyfile(SETTINGS, BACKUP)
        print("backed up  -> " + os.path.relpath(BACKUP, ROOT))
    else:
        print("backup already present, left alone")

    # Everything up to and including the template stays; the tail is the
    # template again and again. A count below what is kept truncates instead.
    head = steps[:index]
    out = head[:args.count]
    while len(out) < args.count:
        out.append(json.loads(json.dumps(template)))
    data["action_sequences"][args.trigger][str(args.char)]["steps"] = out
    save(SETTINGS, data)
    print("%s / %s (%s): %d steps, step %d repeated"
          % (args.trigger, args.char, char_name(args.char), len(out), index))
    print("file is now %d bytes" % os.path.getsize(SETTINGS))
    return 0


def cmd_restore(args):
    if not os.path.exists(BACKUP):
        print("no backup at " + os.path.relpath(BACKUP, ROOT))
        return 1
    shutil.copyfile(BACKUP, SETTINGS)
    os.remove(BACKUP)
    print("restored, backup removed")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("show")
    f = sub.add_parser("fill")
    f.add_argument("--char", type=int, default=1)
    f.add_argument("--trigger", default="reversal")
    f.add_argument("--count", type=int, default=MAX_STEPS)
    f.add_argument("--template", type=int, default=None,
                   help="1-based step to repeat (default: the last one)")
    sub.add_parser("restore")
    args = ap.parse_args()
    if args.cmd == "show":
        return cmd_show(args)
    if args.cmd == "fill":
        return cmd_fill(args)
    if args.cmd == "restore":
        return cmd_restore(args)
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
