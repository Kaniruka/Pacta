#!/usr/bin/env python3
"""Fail when local-only AI artifacts leak into the Git index.

The Git index is the only source of truth: paths come from `git ls-files` and
file contents from `git show :<path>`, never from the working tree or history.
Comparison is case-insensitive, because a Windows or macOS checkout cannot
tell `Docs/` from `docs/`.

Banned paths
  any depth, directory   .scratch/ .agent/ .agents/ .codex/ .claude/ .cursor/
  repository root, dir   docs/
  any depth, file        AGENTS.md AGENTS.override.md CLAUDE.md CLAUDE.local.md
  repository root, file  GLOSSARY.md MISSION.md CODING_STANDARDS.md

Banned Markdown links
  Every tracked Markdown file is read from the index, and its inline links,
  images and reference definitions are resolved against the repository. A link
  that lands on a banned path is reported, so a tracked README cannot publish a
  local-only document by pointing at it. Fenced code blocks, in-page anchors
  (`#...`) and external schemes (`https:`, `mailto:`, ...) are ignored.

Product sources, README files and `skills/` are not affected: only these
local-only AI artifacts are blocked.

Exit codes
  0  index is clean
  1  banned paths or links are tracked; each is printed with its rule
  2  the Git index could not be read (missing repo, broken `.git`, no git)
"""

import argparse
import os
import posixpath
import re
import subprocess
import sys
from urllib.parse import unquote

EXIT_CLEAN = 0
EXIT_VIOLATIONS = 1
EXIT_GIT_ERROR = 2

# Agent state and scratch directories belong to the machine, at any depth.
ANY_DEPTH_DIRECTORIES = ('.scratch', '.agent', '.agents', '.codex', '.claude', '.cursor')
# Process documentation is local-only, but only the repository root copy: a
# nested docs/ directory may belong to product or tooling sources.
ROOT_DIRECTORIES = ('docs',)
# Agent instruction files override behaviour wherever they are found.
ANY_DEPTH_FILES = ('agents.md', 'agents.override.md', 'claude.md', 'claude.local.md')
# Root-level AI design, glossary and standards documents.
ROOT_FILES = ('glossary.md', 'mission.md', 'coding_standards.md')

MARKDOWN_SUFFIX = '.md'
# `https://`, `http://`, `mailto:` and every other URI scheme are external.
EXTERNAL_LINK = re.compile(r'^[A-Za-z][A-Za-z0-9+.-]*:')
FENCE = re.compile(r'^( {0,3})(`{3,}|~{3,})')
REFERENCE_DEFINITION = re.compile(r'^\s*\[[^\]]+\]:\s*(\S+)')
LINK_TITLE = re.compile(r'^(.*?)\s+("[^"]*"|\'[^\']*\')\s*$')


class GitError(Exception):
    """The Git index could not be read."""


def run_git(repo, *arguments):
    """Run git in `repo` and return the completed process."""
    command = ['git', '-C', str(repo), '-c', 'core.quotepath=off', *arguments]
    try:
        return subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise GitError('cannot run git ({})'.format(error)) from error


def list_index_paths(repo):
    """Return every path recorded in the index of `repo`."""
    completed = run_git(repo, 'ls-files', '-z')
    if completed.returncode != 0:
        detail = completed.stderr.decode('utf-8', 'replace').strip()
        raise GitError(detail or 'git ls-files exited with {}'.format(completed.returncode))
    decoded = completed.stdout.decode('utf-8', 'surrogateescape')
    return [entry for entry in decoded.split('\0') if entry]


def read_index_file(repo, index_path):
    """Return the indexed content of `index_path`, or None when it is unreadable."""
    completed = run_git(repo, 'show', ':' + index_path)
    if completed.returncode != 0:
        return None
    return completed.stdout.decode('utf-8', 'replace')


def without_fenced_code(text):
    """Return `text` lines with fenced code blocks blanked out."""
    lines = []
    fence = None
    for line in text.splitlines():
        if fence is None:
            opening = FENCE.match(line)
            if opening:
                fence = opening.group(2)
                lines.append('')
                continue
            lines.append(line)
            continue
        stripped = line.strip()
        if stripped and stripped[0] == fence[0] and stripped == fence[0] * len(stripped) \
                and len(stripped) >= len(fence):
            fence = None
        lines.append('')
    return lines


def inline_link_targets(line):
    """Return the targets of every `[text](target)` and `![alt](target)` in `line`."""
    targets = []
    index = 0
    while True:
        opening = line.find('](', index)
        if opening == -1:
            return targets
        depth = 0
        cursor = opening + 1
        while cursor < len(line):
            character = line[cursor]
            if character == '(':
                depth += 1
            elif character == ')':
                depth -= 1
                if depth == 0:
                    break
            cursor += 1
        if depth != 0:
            return targets
        targets.append(line[opening + 2:cursor])
        index = cursor + 1


def markdown_references(index_path, text):
    """Yield (line number, raw target) for links in the indexed Markdown `text`."""
    for number, line in enumerate(without_fenced_code(text), start=1):
        candidates = inline_link_targets(line)
        definition = REFERENCE_DEFINITION.match(line)
        if definition:
            candidates.append(definition.group(1))
        for candidate in candidates:
            yield number, candidate


def resolve_reference(index_path, target):
    """Return the repository-relative path `target` points at, or None to skip it."""
    value = target.strip()
    if value.startswith('<') and '>' in value:
        value = value[1:value.index('>')]
    title = LINK_TITLE.match(value)
    if title:
        value = title.group(1)
    value = value.split('#', 1)[0].split('?', 1)[0]
    value = unquote(value).strip()
    if not value or value.startswith('#'):
        return None
    if EXTERNAL_LINK.match(value):
        return None
    if value.startswith('/'):
        resolved = posixpath.normpath(value.lstrip('/'))
    else:
        resolved = posixpath.normpath(
            posixpath.join(posixpath.dirname(index_path), value)
        )
    if not resolved or resolved == '.' or resolved == '..' or resolved.startswith('../'):
        return None
    return resolved


def classify(index_path):
    """Return why `index_path` must not be tracked, or None when it may be."""
    normalized = index_path.replace(os.sep, '/').replace(os.altsep or os.sep, '/').strip('/')
    segments = [segment for segment in normalized.split('/') if segment]
    if not segments:
        return None
    folded = [segment.casefold() for segment in segments]
    for directory in folded[:-1]:
        if directory in ANY_DEPTH_DIRECTORIES:
            return directory + '/ is local-only'
    if len(folded) > 1 and folded[0] in ROOT_DIRECTORIES:
        return folded[0] + '/ at the repository root is local-only'
    if folded[-1] in ANY_DEPTH_FILES:
        return folded[-1] + ' is local-only'
    if len(folded) == 1 and folded[-1] in ROOT_FILES:
        return folded[-1] + ' at the repository root is local-only'
    return None


def markdown_violations(repo, paths):
    """Return (markdown path, line, raw target, rule) for links to banned paths."""
    violations = []
    for index_path in paths:
        if not index_path.casefold().endswith(MARKDOWN_SUFFIX):
            continue
        text = read_index_file(repo, index_path)
        if text is None:
            continue
        for number, target in markdown_references(index_path, text):
            resolved = resolve_reference(index_path, target)
            if not resolved:
                continue
            reason = classify(resolved)
            if reason:
                violations.append((index_path, number, target, reason))
    return violations


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=
            'Report local-only AI artifacts that are tracked in a Git index.',
    )
    parser.add_argument(
        '--repo',
        default='.',
        help='working tree or repository to inspect (default: the current directory)',
    )
    arguments = parser.parse_args(argv)

    try:
        paths = list_index_paths(arguments.repo)
        link_violations = markdown_violations(arguments.repo, paths)
    except GitError as error:
        print(
            'repository hygiene: cannot read the Git index of {}: {}'.format(
                arguments.repo, error
            ),
            file=sys.stderr,
        )
        return EXIT_GIT_ERROR

    violations = sorted(
        (index_path, reason)
        for index_path, reason in ((path, classify(path)) for path in paths)
        if reason
    )
    if not violations and not link_violations:
        print('repository hygiene: OK ({} indexed path(s) checked)'.format(len(paths)))
        return EXIT_CLEAN

    if violations:
        print(
            'repository hygiene: {} of {} indexed path(s) must not be tracked:'.format(
                len(violations), len(paths)
            ),
            file=sys.stderr,
        )
        for index_path, reason in violations:
            print('  {}  ({})'.format(index_path, reason), file=sys.stderr)
        print(
            'The index is authoritative; untracking keeps the files on disk:',
            file=sys.stderr,
        )
        print('  git rm --cached --quiet -- <path>', file=sys.stderr)
    if link_violations:
        print(
            'repository hygiene: {} tracked Markdown link(s) point at local-only paths:'.format(
                len(link_violations)
            ),
            file=sys.stderr,
        )
        for index_path, number, target, reason in link_violations:
            print('  {}:{}  {}  ({})'.format(index_path, number, target, reason), file=sys.stderr)
        print(
            'Unlink the local-only document from the tracked Markdown file.',
            file=sys.stderr,
        )
    return EXIT_VIOLATIONS


if __name__ == '__main__':
    sys.exit(main())
