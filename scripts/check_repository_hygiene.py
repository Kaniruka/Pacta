#!/usr/bin/env python3
"""Fail when local-only AI artifacts are tracked in the Git index.

The Git index is the only source of truth: this reads `git ls-files` and never
scans file contents or history. Comparison is case-insensitive, because a
Windows or macOS checkout cannot tell `Docs/` from `docs/`.

Banned paths
  any depth, directory  .scratch/ .agent/ .agents/ .codex/ .claude/ .cursor/
  repository root, dir  docs/
  any depth, file       AGENTS.md AGENTS.override.md CLAUDE.md CLAUDE.local.md
  repository root, file  GLOSSARY.md MISSION.md

Product sources, README files and `skills/` are not affected: only these
local-only AI artifacts are blocked.

Exit codes
  0  index is clean
  1  banned paths are tracked; each path is printed with its rule
  2  the Git index could not be read (missing repo, broken `.git`, no git)
"""

import argparse
import os
import subprocess
import sys

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
# Root-level AI design and glossary documents.
ROOT_FILES = ('glossary.md', 'mission.md')


class GitError(Exception):
    """The Git index could not be listed."""


def list_index_paths(repo):
    """Return every path recorded in the index of `repo`."""
    command = ['git', '-C', str(repo), '-c', 'core.quotepath=off', 'ls-files', '-z']
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise GitError('cannot run git ({})'.format(error)) from error
    if completed.returncode != 0:
        detail = completed.stderr.decode('utf-8', 'replace').strip()
        raise GitError(detail or 'git ls-files exited with {}'.format(completed.returncode))
    decoded = completed.stdout.decode('utf-8', 'surrogateescape')
    return [entry for entry in decoded.split('\0') if entry]


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


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Report local-only AI artifacts that are tracked in a Git index.',
    )
    parser.add_argument(
        '--repo',
        default='.',
        help='working tree or repository to inspect (default: the current directory)',
    )
    arguments = parser.parse_args(argv)

    try:
        paths = list_index_paths(arguments.repo)
    except GitError as error:
        print(
            'repository hygiene: cannot read the Git index of {}: {}'.format(arguments.repo, error),
            file=sys.stderr,
        )
        return EXIT_GIT_ERROR

    violations = sorted(
        (index_path, reason)
        for index_path, reason in ((path, classify(path)) for path in paths)
        if reason
    )
    if not violations:
        print('repository hygiene: OK ({} indexed path(s) checked)'.format(len(paths)))
        return EXIT_CLEAN

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
    return EXIT_VIOLATIONS


if __name__ == '__main__':
    sys.exit(main())
