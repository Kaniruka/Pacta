#!/usr/bin/env python3
"""Fetch the official MiSans TTF files needed by Pacta.

This script verifies all archive members before writing any font file. It does
not modify, subset, or re-encode the fonts and does not automate acceptance of
Xiaomi's license agreement.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
from pathlib import Path
import tempfile
from urllib.request import Request, urlopen
from zipfile import BadZipFile, ZipFile


SOURCE_URL = "https://hyperos.mi.com/font-download/MiSans.zip"
LICENSE_URL = (
    "https://hyperos.mi.com/font-download/"
    "MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83"
    "%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf"
)
FAQ_URL = "https://hyperos.mi.com/font/faq"
FONTS = {
    "MiSans-Regular.ttf": (
        "MiSans/ttf/MiSans-Regular.ttf",
        "9c120f0a849bc0aa5048daae2a3c0f6eecd828b5b33fce682a9622833f5feea6",
    ),
    "MiSans-Medium.ttf": (
        "MiSans/ttf/MiSans-Medium.ttf",
        "b03e98374e971594b0b7a9706d0704241f76e1b88556cdda79c5039ef8a638d1",
    ),
    "MiSans-Semibold.ttf": (
        "MiSans/ttf/MiSans-Semibold.ttf",
        "77c23f31ae124867778344970155a0c8d34a89897dedaab81aeee82ff00a4ce6",
    ),
    "MiSans-Bold.ttf": (
        "MiSans/ttf/MiSans-Bold.ttf",
        "d0c1d327952ed935e86fb78a97a6c182b44f2c2b08777326786b1f8b26d1fe1e",
    ),
}


def fetch_archive() -> bytes:
    request = Request(SOURCE_URL, headers={"User-Agent": "Pacta font setup"})
    with urlopen(request, timeout=60) as response:
        return response.read()


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch and verify MiSans Version 4.009 TTF files from Xiaomi's "
            "official archive. The license requires a MiSans notice in the "
            "software. Review the official agreement before use; this script "
            "does not accept it automatically."
        ),
        epilog=f"Official agreement: {LICENSE_URL}\nOfficial FAQ: {FAQ_URL}",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.parse_args()

    destination = Path(__file__).resolve().parents[1] / "assets" / "fonts"
    missing: list[str] = []
    for filename, (_, expected_hash) in FONTS.items():
        target = destination / filename
        if not target.exists():
            missing.append(filename)
            continue
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest != expected_hash:
            raise SystemExit(
                f"Refusing to overwrite damaged/unexpected file {target}: "
                f"expected SHA256 {expected_hash}, got {digest}."
            )
        print(f"Already present and verified: {target}")

    if not missing:
        print("All four MiSans files are already present and verified; no download needed.")
        return 0

    print(f"Downloading MiSans from {SOURCE_URL}")
    try:
        archive = fetch_archive()
        with ZipFile(io.BytesIO(archive)) as bundle:
            verified: dict[str, bytes] = {}
            total_bytes = 0
            for filename, (member, expected_hash) in FONTS.items():
                try:
                    data = bundle.read(member)
                except KeyError as error:
                    raise RuntimeError(
                        f"Official archive is missing expected member: {member}"
                    ) from error
                digest = hashlib.sha256(data).hexdigest()
                if digest != expected_hash:
                    raise RuntimeError(
                        f"SHA256 mismatch for {member}: expected {expected_hash}, "
                        f"got {digest}; no font files were written."
                    )
                verified[filename] = data
                total_bytes += len(data)
    except (OSError, BadZipFile) as error:
        raise SystemExit(f"Could not fetch/read the official MiSans archive: {error}")
    except RuntimeError as error:
        raise SystemExit(str(error))

    destination.mkdir(parents=True, exist_ok=True)
    to_write = {filename: verified[filename] for filename in missing}

    if to_write:
        with tempfile.TemporaryDirectory(prefix=".misans-", dir=destination) as staging:
            staging_dir = Path(staging)
            staged_files: dict[str, Path] = {}
            for filename, data in to_write.items():
                staged = staging_dir / filename
                staged.write_bytes(data)
                staged_files[filename] = staged
            for filename, staged in staged_files.items():
                target = destination / filename
                if target.exists():
                    raise SystemExit(
                        f"Refusing to overwrite a file created during fetch: {target}"
                    )
                os.replace(staged, target)
                print(f"Installed verified font: {target}")

    print(f"All four MiSans files verified ({total_bytes:,} bytes total).")
    print(f"Review the official license: {LICENSE_URL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
