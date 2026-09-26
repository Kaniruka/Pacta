#!/usr/bin/env python3
"""Count source-file lines in this Git working tree.

Counts tracked files and unignored untracked files. Reports physical lines and
non-empty lines; both figures include comments. Build outputs and dependencies
excluded by Git's ignore rules are not included.
"""

from __future__ import annotations

import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


LANGUAGES = {
    "Dart": {".dart"},
    "Python": {".py"},
    "SQL": {".sql"},
    "JavaScript": {".js", ".jsx", ".cjs", ".mjs"},
    "TypeScript": {".ts", ".tsx", ".cts", ".mts"},
    "Kotlin": {".kt", ".kts"},
    "Java": {".java"},
    "C/C++": {".c", ".h", ".cc", ".cpp", ".cxx", ".hh", ".hpp", ".hxx"},
    "Swift": {".swift"},
    "Objective-C": {".m", ".mm"},
    "Shell": {".sh", ".bash", ".zsh"},
    "PowerShell": {".ps1", ".psm1"},
    "C#": {".cs"},
    "Go": {".go"},
    "Rust": {".rs"},
    "Ruby": {".rb"},
    "PHP": {".php"},
    "HTML": {".html", ".htm"},
    "CSS": {".css", ".scss", ".sass", ".less"},
}

EXTENSION_TO_LANGUAGE = {
    extension: language
    for language, extensions in LANGUAGES.items()
    for extension in extensions
}


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        print(f"无法读取 Git 文件列表：{message}", file=sys.stderr)
        return result.returncode

    totals: dict[str, list[int]] = defaultdict(lambda: [0, 0, 0])
    files = {
        os.fsdecode(name)
        for name in result.stdout.split(b"\0")
        if name
    }

    for relative_name in files:
        relative_path = Path(relative_name)
        language = EXTENSION_TO_LANGUAGE.get(relative_path.suffix.lower())
        if language is None:
            continue

        path = root / relative_path
        if not path.is_file():
            continue
        content = path.read_bytes().decode("utf-8-sig", errors="replace")
        lines = content.splitlines()
        totals[language][0] += 1
        totals[language][1] += len(lines)
        totals[language][2] += sum(bool(line.strip()) for line in lines)

    print(f"代码文件：{sum(values[0] for values in totals.values())} 个")
    print(f"物理行数（含空行和注释）：{sum(values[1] for values in totals.values()):,}")
    print(f"非空行数（含注释）：{sum(values[2] for values in totals.values()):,}")
    print("\n按语言统计：")
    for language, (file_count, physical_lines, non_empty_lines) in sorted(
        totals.items(), key=lambda item: item[1][1], reverse=True
    ):
        print(
            f"{language:14} {file_count:4} 个文件  "
            f"{physical_lines:8,} 行  {non_empty_lines:8,} 非空行"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
