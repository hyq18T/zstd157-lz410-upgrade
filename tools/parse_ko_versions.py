#!/usr/bin/env python3
"""Print symbol CRCs from a Linux ELF64 module's __versions section."""

import struct
import sys


MODVERSION_ENTRY = struct.Struct("<Q56s")


def read_versions(path):
    with open(path, "rb") as handle:
        data = handle.read()

    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise ValueError("expected a little-endian ELF64 file")

    section_offset = struct.unpack_from("<Q", data, 0x28)[0]
    entry_size, section_count, string_index = struct.unpack_from("<HHH", data, 0x3A)
    sections = []
    for index in range(section_count):
        offset = section_offset + index * entry_size
        name, kind, flags, address, file_offset, size = struct.unpack_from(
            "<IIQQQQ", data, offset
        )
        sections.append((name, kind, flags, address, file_offset, size))

    string_offset = sections[string_index][4]
    string_size = sections[string_index][5]
    names = data[string_offset : string_offset + string_size]

    for section in sections:
        name_end = names.find(b"\x00", section[0])
        name = names[section[0] : name_end].decode("ascii", errors="replace")
        if name != "__versions":
            continue

        versions = {}
        for offset in range(section[4], section[4] + section[5], MODVERSION_ENTRY.size):
            crc, raw_name = MODVERSION_ENTRY.unpack_from(data, offset)
            symbol = raw_name.split(b"\x00", 1)[0].decode("ascii", errors="replace")
            if symbol:
                versions[symbol] = crc
        return versions

    raise ValueError("no __versions section found")


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} MODULE.ko")
    for symbol, crc in sorted(read_versions(sys.argv[1]).items()):
        print(f"{symbol}\t0x{crc:08x}")


if __name__ == "__main__":
    main()
