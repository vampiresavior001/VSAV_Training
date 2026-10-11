"""Read-only survey of vsavj's exact-edge sequence recognizer (0x02A0C8).

Uses local MAME listings and a local ROM zip; downloads/writes no ROM data.
Outputs small derived JSON to stdout. Static evidence, not runtime validation.
"""
import argparse
import hashlib
import json
from vsav_tool import Rom

LABELS = {0x100: "LP", 0x200: "MP", 0x400: "HP", 0x1000: "LK",
          0x2000: "MK", 0x4000: "HK", 1: "back", 2: "forward",
          4: "down", 8: "up"}
# Sequence names follow charMoves.lua; Pharaoh names also checked against
# Darkstalkers Frame Data (2026-10-07). Existing move-id labels are reversed.
KNOWN = {
    0x02FF9C: ("Demitri", "Midnight Pleasure", 0x14, 0x030134),
    0x031D36: ("Gallon", "Moment Slice", 0x06, 0x031EC0),
    0x0397D8: ("Morrigan", "Cryptic Needle", 0x0A, 0x0399D0),
    0x0397F4: ("Morrigan", "Finishing Shower", 0x00, 0x0398EC),
    0x039802: ("Morrigan", "Darkness Illusion", 0x08, 0x0399A2),
    0x03B86E: ("Anakaris", "Pharaoh Salvation", 0x14, 0x03BAD4),
    0x03B87C: ("Anakaris", "Pharaoh Decoration", 0x1C, 0x03BB10),
    0x03B88A: ("Anakaris", "Pharaoh Magic", 0x10, 0x03BA98),
    0x04B364: ("Lei-Lei", "Tenraiha", 0x0C, 0x04B4EA),
    0x04DCFA: ("Lilith", "Luminous Illusion", 0x18, 0x04DDA4),
}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-dir", required=True)
    p.add_argument("--rom-zip", required=True)
    args = p.parse_args()
    r = Rom(args.code_dir, args.rom_zip)
    if len(r.data) != 0x400000:
        raise SystemExit("Missing vsavj program data")

    def op(a, n):
        if not all(r.have[a:a+n]):
            raise ValueError(f"Missing instruction bytes at {a:06X}")
        return bytes(r.mem[a:a+n])

    def word(a):
        return int.from_bytes(op(a, 2), "big")

    tables = {}
    for wrapper in range(0x029E6A, 0x029EBA, 8):
        if op(wrapper, 2) != bytes.fromhex("47fa") or op(wrapper+4, 2) != bytes.fromhex("6000"):
            raise ValueError("Unexpected wrapper")
        table = wrapper + 2 + int.from_bytes(op(wrapper+2, 2), "big", signed=True)
        dest = wrapper + 6 + int.from_bytes(op(wrapper+6, 2), "big", signed=True)
        if dest != 0x02A0C8:
            raise ValueError("Unexpected recognizer")
        steps = []
        for i in range(16):
            v = r.d16(table + 2*i)
            mask = v & 0x770F
            steps.append({"word": f"0x{v:04X}", "edge_equals": f"0x{mask:04X}",
                          "label": LABELS.get(mask, "UNKNOWN"), "terminal": bool(v & 0x10)})
            if v & 0x10:
                break
        else:
            raise ValueError("No terminal word")
        tables[wrapper] = {"wrapper": f"0x{wrapper:06X}", "table": f"0x{table:06X}",
                           "steps": steps, "direct_references": []}

    # Even-address scan: includes bytes hidden by incorrect disassembly alignment.
    # Candidates still need code-flow review; indirect references are not resolved.
    extra = []
    for a in range(0, len(r.mem)-6, 2):
        if not all(r.have[a:a+6]):
            continue
        opcode = word(a)
        dest = None
        if opcode in (0x4EB9, 0x4EF9):
            dest = int.from_bytes(op(a+2, 4), "big")
        elif opcode & 0xFF00 in (0x6000, 0x6100):
            d = opcode & 255
            delta = int.from_bytes(op(a+2, 2), "big", signed=True) if d == 0 else d-256 if d >= 128 else d
            dest = a + 2 + delta
        if dest not in tables:
            if dest == 0x02A0C8:
                extra.append(f"0x{a:06X}")
            continue
        entry = {"pc": f"0x{a:06X}", "opcode": f"0x{opcode:04X}"}
        if opcode == 0x4EB9:
            entry["return_pc"] = f"0x{a+6:06X}"
            if op(a-4, 2) == bytes.fromhex("49ee"):
                entry["block_offset"] = f"0x{word(a-2):03X}"
        if a in KNOWN:
            char, name, move_id, end = KNOWN[a]
            if op(end, 2) != bytes.fromhex("4e75"):
                raise ValueError("Unexpected commit end")
            signature = bytes.fromhex("1d7c") + move_id.to_bytes(2, "big") + bytes.fromhex("0106")
            if signature not in op(end-24, 24):
                raise ValueError("Move-id write not found near commit end")
            entry.update(character=char, sequence_name=name, move_id=f"0x{move_id:02X}",
                         commit_end_pc=f"0x{end:06X}", status="static_move_path_confirmed")
        else:
            entry["status"] = "unclassified_call_path"
        tables[dest]["direct_references"].append(entry)

    print(json.dumps({"status": "static_analysis_runtime_pending",
                      "baseline_commit": "7745eb19f15cc7961280e07adaa60c493585a107",
                      "rom_set": "vsavj (970519 Japan)",
                      "program_data_sha256": hashlib.sha256(r.data).hexdigest(),
                      "recognizer": "0x02A0C8", "tables": list(tables.values()),
                      "direct_recognizer_references": extra,
                      "scope": "Direct absolute JSR/JMP and relative BRA/BSR candidates; indirect flow not exhaustive",
                      "name_reference": {"url": "https://darkstalkers.web.fc2.com/savior/data-s/anakaris-s/anakaris-s-ex-move.html", "checked": "2026-10-07", "scope": "Pharaoh names, commands and gauge costs"},
                      "warning": "Existing Anakaris move-id labels are reversed: Salvation=0x14, Decoration=0x1C. See SEQUENCE_COMMAND_ROM_SURVEY.ja.md"},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
