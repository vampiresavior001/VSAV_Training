"""Reproduce the static evidence for COMMAND_TRAINER_DESIGN.ja.md.

Reads existing, locally supplied MAME listings and a vsavj program ROM zip.
Does not download ROMs, modify a ROM, or emit a ROM/dump. JSON goes to stdout.
Run from any directory with --code-dir and --rom-zip. Requires vsav_tool.py
beside this script. The result is static evidence, not a runtime test.
"""
import argparse
import hashlib
import json
from pathlib import Path

from vsav_tool import Rom


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code-dir", required=True)
    parser.add_argument("--rom-zip", required=True)
    args = parser.parse_args()
    rom = Rom(args.code_dir, args.rom_zip)
    if len(rom.data) != 0x400000:
        raise SystemExit("Expected all eight vsavj program parts (4 MiB total).")

    # Check relevant decrypted instructions, not mnemonic alignment in a dump.
    signatures = {
        0x0397FE: "49ee03304eb900029e7a",  # DI block and recognizer
        0x04DCF6: "49ee03484eb900029e7a",  # LI block and recognizer
        0x029E7A: "47fa085260000248",      # table and shared recognizer
        0x02A0E4: "302e01acb041",          # compare complete press-edge word
        0x02A112: "302e01acb041",          # subsequent steps do the same
        0x02A53A: "542c0001",              # accepted non-final step: +1 += 2
        0x02A57A: "421470004e75",          # clear phase, return zero
        0x02A580: "421470014e75",          # clear phase, return one
        0x039994: "1d7c00080106",          # DI move id
        0x04DD96: "1d7c00180106",          # LI move id
    }
    checks = []
    for address, hex_bytes in signatures.items():
        expected = bytes.fromhex(hex_bytes)
        end = address + len(expected)
        if not all(rom.have[address:end]):
            raise SystemExit(f"Missing listing bytes at {address:06X}")
        if bytes(rom.mem[address:end]) != expected:
            raise SystemExit(f"Unexpected opcode signature at {address:06X}")
        checks.append(f"0x{address:06X}")

    table = 0x02A6CE
    words = [rom.d16(table + 2 * i) for i in range(5)]
    if words != [0x0100, 0x0100, 0x0002, 0x1000, 0x0410]:
        raise SystemExit("Unexpected Illusion command table")
    labels = ["LP", "LP", "forward", "LK", "HP"]
    steps = [dict(index=i + 1, label=label, table_word=f"0x{word:04X}",
                  edge_equals=f"0x{word & 0x770F:04X}",
                  terminal=bool(word & 0x10))
             for i, (label, word) in enumerate(zip(labels, words))]

    # Preserve both views: do not resolve this discrepancy by guessing.
    timer_address = 0x02A55A
    timer_count = 32
    timer_end = timer_address + timer_count
    if not all(rom.have[timer_address:timer_end]):
        raise SystemExit("Missing timer table listing bytes")
    sources = {}
    for name in ("c20.txt", "c28.txt", "c38.txt", "c040000.txt"):
        path = Path(args.code_dir) / name
        sources[name] = hashlib.sha256(path.read_bytes()).hexdigest()

    print(json.dumps({
        "status": "static_verified_runtime_pending",
        "repository_commit": "7745eb19f15cc7961280e07adaa60c493585a107",
        "rom_set": "vsavj (970519 Japan)",
        "program_data_sha256": hashlib.sha256(rom.data).hexdigest(),
        "listing_sha256": sources,
        "opcode_signature_checks_passed": checks,
        "shared_recognizer": "0x02A0C8",
        "wrapper": "0x029E7A",
        "table_address": "0x02A6CE",
        "steps": steps,
        "profiles": [
            dict(character="Morrigan", character_id="0x05", move_id="0x08",
                 name="Darkness Illusion", block_offset="0x330",
                 call_pc="0x039802", return_pc="0x039808",
                 move_commit_end_pc="0x0399A2"),
            dict(character="Lilith", character_id="0x0E", move_id="0x18",
                 name="Luminous Illusion", block_offset="0x348",
                 call_pc="0x04DCFA", return_pc="0x04DD00",
                 move_commit_end_pc="0x04DDA4"),
        ],
        "timer_evidence": {
            "address": "0x02A55A", "status": "memory_view_requires_runtime_confirmation",
            "data_view_bytes": list(rom.data[timer_address:timer_end]),
            "listing_view_bytes": list(rom.mem[timer_address:timer_end]),
            "rule": "Measure block+4 and actual return events; do not hardcode a window.",
        },
    }, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
