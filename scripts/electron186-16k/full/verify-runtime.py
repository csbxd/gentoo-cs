#!/usr/bin/env python3
"""Check the actual ELF load layout of every binary in a runtime directory."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

parser = argparse.ArgumentParser()
parser.add_argument('runtime', type=Path)
parser.add_argument('--page-size', type=int, default=16384)
parser.add_argument('--json', type=Path)
args = parser.parse_args()
root = args.runtime.resolve()
results = []
errors = []
for path in sorted(root.rglob('*')):
    if not path.is_file():
        continue
    with path.open('rb') as binary:
        header = binary.read(64)
        if header[:4] != b'\x7fELF':
            continue
        name = str(path.relative_to(root))
        if header[4:6] != b'\x02\x01':
            errors.append(name + ': expected little endian ELF64')
            continue
        machine = struct.unpack_from('<H', header, 18)[0]
        offset = struct.unpack_from('<Q', header, 32)[0]
        entry_size, count = struct.unpack_from('<HH', header, 54)
        if machine != 183:
            errors.append(name + ': expected AArch64 machine 183')
        segments = []
        for index in range(count):
            binary.seek(offset + index * entry_size)
            entry = binary.read(entry_size)
            kind, flags, file_offset, address, _, file_size, memory_size, alignment = struct.unpack_from('<IIQQQQQQ', entry)
            if kind != 1:
                continue
            ok = alignment >= args.page_size and (address - file_offset) % args.page_size == 0
            segments.append({'offset': file_offset, 'address': address,
                             'alignment': alignment, 'flags': flags, 'ok': ok})
            if not ok:
                errors.append(name + ': PT_LOAD is incompatible with the requested page size')
        if not segments:
            errors.append(name + ': no PT_LOAD segments')
    results.append({'path': name, 'size': path.stat().st_size,
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'machine': machine, 'loadSegments': segments})
if not results:
    errors.append('runtime directory contains no ELF binaries')
report = {'runtime': str(root), 'pageSize': args.page_size,
          'elfCount': len(results), 'ok': not errors,
          'errors': errors, 'binaries': results}
if args.json:
    args.json.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'elfCount': len(results), 'ok': not errors, 'errors': errors}))
raise SystemExit(bool(errors))
