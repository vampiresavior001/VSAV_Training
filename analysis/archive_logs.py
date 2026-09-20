"""
Move the current reversal logs into a versioned archive.

Replaces deleting them. The rule that matters is that the folder the tool
writes into must not contain two script versions at once - pooling them
produces averaged nonsense. Deleting satisfies that rule and also throws away
the evidence, which has now cost three separate follow-up analyses: the
question that comes after "here are the numbers" is almost always "why did
those particular ones fail", and by then the traces are gone.

Moving satisfies the same rule and keeps them. Archives are named after the
script version that produced them, so an old batch can be re-analysed:

    python explain_leads.py ../scripts/reversal_logs_archive/v81-wider-sweep.1

Usage:  python archive_logs.py
"""
import glob
import json
import os
import shutil
import sys

# THE REPOSITORY MOVED. These pointed at C:\fightcade, which CLAUDE.md says
# is migrated and not to be touched - so a run from the new tree archived 66
# recordings into the OLD one and they had to be carried back by hand
# (2026-09-20).
LOG_DIR = r"C:\fightcaVSAV-Debug\emulator\fbneo\scripts\reversal_logs"
ARCHIVE = r"C:\fightcaVSAV-Debug\emulator\fbneo\scripts\reversal_logs_archive"


def main():
    log_dir = sys.argv[1] if len(sys.argv) > 1 else LOG_DIR
    paths = sorted(glob.glob(os.path.join(log_dir, "kd_*.json")))
    # ag_prox.json is All Guard's own log. It is rewritten whole rather than
    # rotated, so it has to be moved out with the batch or the next session
    # silently overwrites it.
    extra = [p for p in (os.path.join(log_dir, "ag_prox.json"),)
             if os.path.exists(p)]
    if not paths and not extra:
        print("nothing to archive in", log_dir)
        return

    versions = set()
    if not paths:
        versions.add('ag-only')
    for p in paths:
        try:
            with open(p, encoding='utf-8') as fh:
                versions.add(json.load(fh).get('script_version'))
        except Exception:
            versions.add('unreadable')
    name = sorted(versions, key=str)[0] if len(versions) == 1 else \
        "mixed-" + "+".join(sorted(str(v) for v in versions))

    dest = os.path.join(ARCHIVE, str(name))
    n = 1
    while os.path.exists(dest):
        n += 1
        dest = os.path.join(ARCHIVE, "%s_%d" % (name, n))
    os.makedirs(dest)
    for p in paths + extra:
        shutil.move(p, os.path.join(dest, os.path.basename(p)))
    print("archived %d recordings%s -> %s"
          % (len(paths), " + ag_prox.json" if extra else "", dest))
    if len(versions) > 1:
        print("  (mixed versions in one batch: %s)" % sorted(str(v) for v in versions))


if __name__ == "__main__":
    main()
