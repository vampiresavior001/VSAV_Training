"""Build the release zip the same way every previous one was built, with the
manifest DERIVED FROM THE CURRENT TREE instead of a frozen list.

The v11.7.6 and v11.7.7 zips shipped without scripts/pattern_file.ps1 and
scripts/name_prompt.ps1: the manifest was copied from v11.7.5, and both
PowerShell helpers were added later by the Action Pattern Library. In a
release install the file dialog and the name window therefore never opened -
"ERROR: pattern_file.ps1 not found" (user, 2026-09-21). Deriving the list
from the tree makes the next added file ship by default.

Usage (from the fbneo repo root):
    python analysis/make_release_zip.py [version]

    version  the tag suffix, default "v11.7.7". Writes
             ..\\..\\dist\\VSAV_Training_<version>.zip - the built zip is never
             left in the repository.

Exclusions (the same list every handoff section 7 has carried):
    training_settings.json        the user's live settings, logger state and all
    training_settings_pre_action_patterns.json
    *.log, action_patterns_transfer.json
    scripts/reversal_logs/  scripts/reversal_logs_archive/  scripts/savestate/
    macro/last_recording.mis  macro/wizard_temp.mis  macro/*/test/
"""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "dist")

ROOT_FILES = [
    "README.md",
    "run_vsav_training.bat",
    "run_vsav_training.sh",
    "run_vsav_training_flatpak.sh",
    "training_modes.json",
    "vsav_training_flatpak.desktop",
]

EXCLUDE_FILES = {
    "training_settings.json",
    "training_settings_pre_action_patterns.json",
    "action_patterns_transfer.json",
    "last_recording.mis",
    "wizard_temp.mis",
    # The recording wizard's scratch name: "macro/<char>/test" is a work
    # recording, not a slot (handoff section 7, "*/test 作業用の録画").
    "test",
}

EXCLUDE_DIRS = {"reversal_logs", "reversal_logs_archive", "savestate"}


def excluded(name):
    return name in EXCLUDE_FILES or name.endswith(".log")


def walk(rel_dir, out):
    full = os.path.join(ROOT, rel_dir.replace("/", os.sep))
    for entry in sorted(os.listdir(full)):
        rel = rel_dir + "/" + entry
        full_entry = os.path.join(full, entry)
        if os.path.isdir(full_entry):
            if entry in EXCLUDE_DIRS or entry == ".svn":
                continue
            walk(rel, out)
        else:
            if excluded(entry):
                continue
            out.append(rel)


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "v11.7.7"
    names = []
    missing = []
    for f in ROOT_FILES:
        if os.path.isfile(os.path.join(ROOT, f.replace("/", os.sep))):
            names.append(f)
        else:
            missing.append(f)
    walk("support/ips", names)
    walk("scripts", names)
    if missing:
        print("MISSING root files (skipped):", missing)

    out = os.path.join(DIST, "VSAV_Training_%s.zip" % version)
    os.makedirs(DIST, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:
            z.write(os.path.join(ROOT, n.replace("/", os.sep)), n)
    print("entries:", len(names))
    for must in ("scripts/pattern_file.ps1", "scripts/name_prompt.ps1"):
        print("contains %s:" % must, must in names)
    for must_not in ("scripts/training_settings.json", "scripts/reversal_logs",
                     "scripts/action_pattern_trace.log"):
        hit = [n for n in names if n.startswith(must_not)]
        print("excluded %s:" % must_not, not hit)
    print("wrote", out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()
