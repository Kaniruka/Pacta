#!/usr/bin/env python3
"""Build a reproducible, credential-free National Focus skill ZIP (stdlib only)."""
import argparse
import hashlib
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile, ZipInfo

NAME = 'pacta-national-focus-analysis'
FILES = ('SKILL.md', 'references/contract.md', 'evals/README.md', 'evals/cases.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('build/skills'))
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / 'skills' / NAME
    # Explicit allowlist excludes local credentials, caches and editor files.
    payloads = [(name, (source / name).read_bytes()) for name in FILES]
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f'{NAME}.zip'
    with ZipFile(archive, 'w', compression=ZIP_STORED) as bundle:
        for name, data in payloads:
            entry = ZipInfo(f'{NAME}/{name}', date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            bundle.writestr(entry, data)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_suffix('.zip.sha256')
    checksum.write_text(f'{digest}  {archive.name}\n', encoding='ascii')
    print(f'{archive}\n{checksum}\nSHA-256: {digest}')


if __name__ == '__main__':
    main()
