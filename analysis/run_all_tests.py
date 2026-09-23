# -*- coding: utf-8 -*-
"""Runs every offline test there is, by finding them rather than being told.

WHY THIS EXISTS. The run list lived in CLAUDE.md, by hand, in two places - one
PowerShell line and one bash line. Tests were added without being added to it:
on 2026-09-23 four were missing (test_after_ground_dash,
test_landing_ground_recovery, test_wakeup_facing, test_position_row), and three
of those guard the hardest fixes in the project. They had been passing all
along, but nothing was running them. A test that is not run protects nothing,
and a hand-copied list is the only thing that decides which ones are.

So the list is gone. This walks the directories instead, and a new file is
picked up because it is there.

WORKING DIRECTORY IS DECLARED BY THE TEST. Most of these dofile their subject
with a relative path and only work from scripts/; the rest read scripts/ from
the package root. Nothing in the file's location says which, so the header line
does:

    -- Run from scripts/ ...              -> run with cwd = scripts/
    --   cd scripts && lua5.1 ../analysis/foo.lua
    --   cd C:/.../fbneo && lua5.1 analysis/foo.lua   -> run from the root

A test that says neither is a FAILURE, not a guess. Guessing is how the old
loop in the chat hid a broken test behind a fallback: it tried scripts/, then
the root, and reported "ok" when either happened to work.

Usage (from the fbneo repo root):
    python analysis/run_all_tests.py [-v]
"""
import glob
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
HEADER_LINES = 30


def discover():
    """Every offline test, wherever it lives."""
    found = []
    found += sorted(glob.glob(os.path.join(ROOT, "analysis", "test_*.lua")))
    found += sorted(glob.glob(os.path.join(SCRIPTS, "tests", "*_test.lua")))
    return found


def where(path):
    """scripts/ or the repo root, as the file's own header declares."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        head = "".join(fh.readline() for _ in range(HEADER_LINES))
    from_scripts = ("Run from scripts" in head
                    or "cd scripts && lua5.1" in head
                    or "cd scripts; lua5.1" in head)
    from_root = ("lua5.1 analysis/" in head
                 or "lua5.1 scripts/tests/" in head)
    if from_scripts and not from_root:
        return SCRIPTS
    if from_root and not from_scripts:
        return ROOT
    return None


def main():
    verbose = "-v" in sys.argv
    # RESOLVED ONCE, NOT LEFT TO THE SHELL. CreateProcess does not search PATH
    # the way a shell does and does not add .exe, so a bare "lua5.1" raises
    # WinError 2 even when the same word works when typed.
    lua = shutil.which("lua5.1") or shutil.which("lua")
    if lua is None:
        print("lua5.1 が PATH に無い")
        return 1
    tests = discover()
    if not tests:
        print("テストが 1 本も見つからない - 置き場所が変わった?")
        return 1

    undeclared, failed, passed = [], [], 0
    for path in tests:
        name = os.path.basename(path)[:-4]
        cwd = where(path)
        if cwd is None:
            undeclared.append(name)
            continue
        rel = os.path.relpath(path, cwd).replace(os.sep, "/")
        r = subprocess.run([lua, rel], cwd=cwd,
                           capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        if r.returncode == 0:
            passed += 1
            if verbose:
                print("  ok   %s" % name)
        else:
            failed.append((name, cwd, (r.stdout or "") + (r.stderr or "")))

    for name, cwd, out in failed:
        print("=" * 62)
        print("NG  %s   (cwd=%s)" % (name, os.path.basename(cwd)))
        tail = [l for l in out.splitlines() if l.strip()][-12:]
        for l in tail:
            print("    " + l)

    if undeclared:
        print("=" * 62)
        print("走らせ方が宣言されていないテスト %d 本:" % len(undeclared))
        for n in undeclared:
            print("    " + n)
        print("  先頭 %d 行に、次のどちらかの行を書くこと:" % HEADER_LINES)
        print("    --   cd scripts && lua5.1 ../analysis/<name>.lua")
        print("    --   cd C:/fightcaVSAV-Debug/emulator/fbneo && "
              "lua5.1 analysis/<name>.lua")

    print("=" * 62)
    print("見つけた %d 本 / 通過 %d / NG %d / 宣言なし %d"
          % (len(tests), passed, len(failed), len(undeclared)))
    return 0 if (not failed and not undeclared) else 1


if __name__ == "__main__":
    sys.exit(main())
