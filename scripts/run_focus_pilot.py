#!/usr/bin/env python3
"""Run one focus-chain pilot screenshot scenario and keep its evidence apart.

Replaces the throwaway ``run_pilot.sh`` workflow: a run gets its own directory,
the desktop fixture and the screenshot driver receive the same subdirectory, and
stdout/stderr, exit code and a manifest are written next to the images.

Usage (repo root, Windows):

    python scripts/run_focus_pilot.py --scenario default --view wide
    python scripts/run_focus_pilot.py --scenario zero --theme light --manual-hold 300
    python scripts/run_focus_pilot.py --scenario long --device emulator-5554

``--flutter`` takes either a single executable path (spaces allowed, no shell
quoting) or a quoted command line such as ``--flutter '"C:/Python/python.exe"
"D:/my scripts/fake.py"'``. No hard timeout is provided: the tool only reports
the child's exit status.

A successful automatic run is `passed`; a successful `--manual-hold` run is
`captured` and carries `native_review_required`, because a driver image may
omit system overlays such as dialogs, ANRs or the on-screen keyboard. Failure
and source drift still win over both. Every manifest also records
`head_start`/`git_status_start` next to the end-of-run `head`/`git_status`, and
`visual_review_required` stays true: a status here means the command, the images
and the fingerprints, never a visual acceptance.

`--verify <run_dir>` checks an existing run without running anything: it reads
the manifest, compares the start-of-run SHA-256 values it actually recorded
against the current working tree, and prints match/missing/mismatch/unsafe and
unverifiable. End-of-run digests are reported, never used as the baseline. It
never rewrites the manifest, never marks a run as passed for reuse, and reports
a different HEAD without treating it as invalid. Unrecorded dependencies and
HEAD equivalence stay unproven.

The legacy
``build/ui-layout-evidence/focus-pilot/run_pilot.sh`` is kept as a historical
record and is not called from here.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
EVIDENCE_ROOT = Path('build/ui-layout-evidence')

SCENARIOS = ('default', 'zero', 'few', 'long')
VIEWS = ('wide', 'narrow')

# Rendering inputs of the one target a run actually drives. The runner and the
# shared driver are included: editing either mid-run invalidates the evidence.
# Targets this runner does not drive (the sync card, the national-focus page)
# are outside its scope rather than missing fingerprints.
_SHARED_SOURCE_FILES = (
    'test_driver/ui_layout_acceptance_test.dart',
    'scripts/run_focus_pilot.py',
)

TARGET_SOURCE_FILES = {
    'focus': _SHARED_SOURCE_FILES + (
        'lib/main.dart',
        'lib/src/focus/chain_signals_card.dart',
        'lib/src/calendar/calendar_page.dart',
        'integration_test/focus_chain_design_device_test.dart',
    ),
    'board': _SHARED_SOURCE_FILES + (
        'lib/main.dart',
        'lib/src/board/national_focus_summary_card.dart',
        'lib/src/calendar/calendar_page.dart',
        'lib/src/focus/chain_signals_card.dart',
        'integration_test/board_design_device_test.dart',
    ),
}

RUN_ID_PATTERN = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def source_files_for(target):
    return TARGET_SOURCE_FILES[target]


def snapshot_sources(target):
    return {
        path: (sha256(REPO / path) if (REPO / path).is_file() else None)
        for path in source_files_for(target)
    }


def drift_between(before, after, target):
    return sorted(
        path for path in source_files_for(target) if before[path] != after[path]
    )


def git(*args):
    try:
        return subprocess.run(
            ['git', *args],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def head_revision():
    return git('rev-parse', 'HEAD')


def work_tree_status():
    return (git('status', '--porcelain') or '').splitlines()


def flutter_command(flutter):
    """Split ``flutter`` into argv and resolve the executable through PATH.

    On Windows the launcher is ``flutter.bat``, which ``subprocess`` cannot start
    without ``shell=True``; resolving with :func:`shutil.which` applies PATHEXT
    and yields the real file. An explicit path is kept as given.
    """
    text = flutter.replace('\\', '/') if os.name == 'nt' else flutter
    if Path(text).is_file():
        return [text]
    parts = shlex.split(text)
    if parts:
        resolved = shutil.which(parts[0])
        if resolved:
            parts[0] = resolved.replace('\\', '/') if os.name == 'nt' else resolved
    return parts


def non_negative_int(text):
    value = int(text)
    if value < 0:
        raise argparse.ArgumentTypeError('must be >= 0')
    return value


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--target', default='focus', choices=('focus', 'board'))
    parser.add_argument('--scenario', default='default', choices=SCENARIOS,
                        help='one scenario per run (default: %(default)s)')
    parser.add_argument('--view', default='wide', choices=VIEWS)
    parser.add_argument('--theme', default='dark', choices=('dark', 'light'))
    parser.add_argument('--device', default='windows',
                        help='flutter -d target, e.g. windows or emulator-5554')
    parser.add_argument('--manual-hold', type=non_negative_int, default=0,
                        metavar='SECONDS',
                        help='hold the first screen for manual input; '
                             'implies --snapshot-only')
    parser.add_argument('--snapshot-only', action='store_true',
                        help='stop after the first screen')
    parser.add_argument('--run-id', default=None,
                        help='[A-Za-z0-9][A-Za-z0-9._-]* ; defaults to a timestamp')
    parser.add_argument('--verify', metavar='RUN_DIR', default=None,
                        help='read-only check of an existing run manifest '
                             'against the current working tree; runs nothing')
    parser.add_argument('--flutter', default=None,
                        help='executable path (spaces ok) or quoted command line; '
                             'also FOCUS_PILOT_FLUTTER')
    return parser


def _recorded_digests(manifest):
    recorded = {}
    for key in ('source_files', 'source_files_end'):
        part = manifest.get(key)
        if not isinstance(part, dict):
            continue
        for path_text, digest in part.items():
            entry = recorded.setdefault(str(path_text), {})
            entry['start' if key == 'source_files' else 'end'] = digest
    return recorded


_DIGEST_PATTERN = re.compile(r'^[0-9a-f]{64}$')


def _normalized_digest(value):
    if not isinstance(value, str):
        return None
    text = value.strip().lower()
    return text if _DIGEST_PATTERN.match(text) else None


def _repo_relative(path_text):
    """Return a repo-relative path, or None when the record is unsafe."""
    candidate = Path(str(path_text).replace('\\', '/'))
    if candidate.is_absolute() or '..' in candidate.parts:
        return None
    return candidate


def _inside_repository(repo, destination):
    try:
        resolved = destination.resolve()
    except OSError:
        return False
    return resolved == repo or repo in resolved.parents


def verify_run(target):
    """Compare one existing run manifest with the tree. No writes, no rerun."""
    repo = REPO.resolve()
    directory = Path(target)
    if not directory.is_absolute():
        directory = repo / directory
    try:
        directory = directory.resolve()
    except OSError:
        print(f'verify_status=error reason=unreadable-path path={target}', file=sys.stderr)
        return 2
    if directory != repo and repo not in directory.parents:
        print('verify_status=error reason=run-dir-outside-repo '
              f'path={directory}', file=sys.stderr)
        return 2
    manifest_path = directory / 'manifest.json'
    if not manifest_path.is_file():
        print('verify_status=error reason=manifest-missing '
              f'path={manifest_path}', file=sys.stderr)
        return 2
    try:
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        print('verify_status=error reason=manifest-unreadable '
              f'detail={error}', file=sys.stderr)
        return 2
    if not isinstance(manifest, dict):
        print('verify_status=error reason=manifest-not-object '
              f'path={manifest_path}', file=sys.stderr)
        return 2
    recorded = _recorded_digests(manifest)
    if not recorded:
        print('verify_status=error reason=no-source-files '
              f'path={manifest_path}', file=sys.stderr)
        return 2

    states = {}
    notes = []
    for path_text in sorted(recorded):
        entry = recorded[path_text]
        relative = _repo_relative(path_text)
        if relative is None:
            states[path_text] = 'unsafe'
            continue
        destination = repo / relative
        if not _inside_repository(repo, destination):
            states[path_text] = 'unsafe'
            continue
        current = sha256(destination) if destination.is_file() else None
        has_start = 'start' in entry
        raw = entry.get('start') if has_start else entry.get('end')
        expected = _normalized_digest(raw)
        if not has_start:
            notes.append('degraded end-only %s' % path_text)
        elif 'end' in entry and _normalized_digest(entry['end']) != expected:
            notes.append('end-changed %s' % path_text)
        if raw is None:
            notes.append('recorded-absent %s' % path_text)
        elif expected is None:
            notes.append('invalid-hash %s' % path_text)
        if expected is None:
            states[path_text] = 'unverifiable'
        elif current is None:
            states[path_text] = 'missing'
        elif current == expected:
            states[path_text] = 'match'
        else:
            states[path_text] = 'mismatch'

    print('[verify] run=%s recorded_status=%s'
          % (manifest.get('run_id'), manifest.get('status')))
    print('[verify] manifest_head=%s current_head=%s'
          % (manifest.get('head'), head_revision()))
    print('[verify] drift_recorded=%s' % (manifest.get('source_drift') or []))
    for path_text in sorted(states):
        print('[verify] %-12s %s' % (states[path_text], path_text))
    for note in notes:
        print('[verify] note: %s' % note)
    failures = sum(1 for state in states.values() if state != 'match')
    print('[verify] files=%d match=%d other=%d'
          % (len(states), len(states) - failures, failures))
    print('[verify] baseline: source files recorded at run start; the end-of-run'
          ' digest is reported only. Only recorded files are checked; unrecorded'
          ' dependencies and HEAD equivalence stay unproven; a different head is'
          ' reported, not invalid.')
    print('[verify] this command never marks a run as passed for reuse.')
    print('verify_status=%s' % ('ok' if not failures else 'mismatch'))
    return 0 if not failures else 1


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.verify is not None:
        return verify_run(args.verify)

    run_id = time.strftime('%Y%m%dT%H%M%S') if args.run_id is None else args.run_id
    if not RUN_ID_PATTERN.match(run_id) or '..' in run_id:
        parser.error(f'unsafe run id: {run_id!r}')

    name = f'{run_id}-{args.scenario}-{args.view}'
    if args.theme == 'light':
        name += '-light'
    if args.manual_hold:
        name += f'-hold{args.manual_hold}'

    subdir = f'{args.target}-pilot/runs/{name}'
    out_dir = REPO / EVIDENCE_ROOT / subdir
    if out_dir.exists():
        print(f'refusing to reuse evidence directory: {out_dir}', file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True)

    flutter = args.flutter or os.environ.get('FOCUS_PILOT_FLUTTER') or 'flutter'
    flutter_cmd = flutter_command(flutter)
    if not flutter_cmd:
        print('empty flutter command', file=sys.stderr)
        return 2

    snapshot_only = args.snapshot_only or args.manual_hold > 0
    command = [
        *flutter_cmd,
        'drive',
        '--keep-app-running',
        '--driver=test_driver/ui_layout_acceptance_test.dart',
        ('--target=integration_test/board_design_device_test.dart' if args.target == 'board'
         else '--target=integration_test/focus_chain_design_device_test.dart'),
        '-d',
        args.device,
        '--dart-define=FOCUS_PILOT_MODE=true',
        f'--dart-define=FOCUS_PILOT_SCENARIO={args.scenario}',
        f'--dart-define=FOCUS_PILOT_VIEW={args.view}',
        f'--dart-define=FOCUS_PILOT_DIR={subdir}',
    ]
    if args.target == 'board':
        command.append('--dart-define=BOARD_PILOT_MODE=true')
    if args.theme == 'light':
        command.append('--dart-define=FOCUS_PILOT_LIGHT=true')
    if args.manual_hold:
        command.append(f'--dart-define=FOCUS_PILOT_HOLD_SECONDS={args.manual_hold}')
    if snapshot_only:
        command.append('--dart-define=FOCUS_DESIGN_SNAPSHOT_ONLY=true')

    env = os.environ.copy()
    # Same subdirectory for the driver process and the Dart fixture.
    env['UI_EVIDENCE_SUBDIR'] = subdir
    env['UI_EVIDENCE_FAIL_ON_EXIST'] = '1'

    log_path = out_dir / 'run.log'
    rc_path = out_dir / 'run.rc'
    manifest_path = out_dir / 'manifest.json'

    started = time.time()
    started_at = time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(started))
    sources_before = snapshot_sources(args.target)
    head_start = head_revision()
    git_status_start = work_tree_status()
    print(f'[run_focus_pilot] {name} -> {out_dir}')
    with open(log_path, 'wb') as log:
        log.write(f'$ {" ".join(command)}\n'.encode())
        try:
            rc = subprocess.run(
                command,
                cwd=REPO,
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
            ).returncode
        except OSError as error:
            log.write(f'\n[run_focus_pilot] cannot start flutter: {error}\n'.encode())
            rc = 127
    sources_after = snapshot_sources(args.target)
    drift = drift_between(sources_before, sources_after, args.target)

    if rc != 0:
        status = 'failed'
    elif drift:
        status = 'invalid'
    elif args.manual_hold:
        # A driver image may omit system overlays, so a manual run only
        # captured evidence; a human still reviews it natively.
        status = 'captured'
    else:
        status = 'passed'
    # ``process_rc`` is flutter's own code; the runner-owned code is what the
    # caller and run.rc see, so drift cannot be reported as a success.
    exit_code = rc if rc != 0 else (3 if drift else 0)

    rc_path.write_text(f'{exit_code}\n', encoding='utf-8')
    manifest = {
        'run_id': run_id,
        'name': name,
        'status': status,
        'rc': exit_code,
        'process_rc': rc,
        'args': vars(args),
        'resolved': {
            'snapshot_only': snapshot_only,
            'flutter': flutter,
        },
        'command': command,
        'evidence_subdir': subdir,
        'out_dir': str(out_dir.relative_to(REPO)),
        'log': str(log_path.relative_to(REPO)),
        'started_at': started_at,
        'duration_seconds': round(time.time() - started, 1),
        'native_review_required': bool(args.manual_hold),
        'visual_review_required': True,
        'head_start': head_start,
        'git_status_start': git_status_start,
        'head': head_revision(),
        'git_status': work_tree_status(),
        'source_files': sources_before,
        'source_files_end': sources_after,
        'source_drift': drift,
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8',
    )

    if status == 'invalid':
        print('[run_focus_pilot] sources changed during the run, evidence invalid: '
              + ', '.join(drift), file=sys.stderr)
        print(f'[run_focus_pilot] status=invalid exit_code={exit_code} '
              f'manifest={manifest_path}')
        return exit_code
    print(f'[run_focus_pilot] rc={exit_code} process_rc={rc} status={status} '
          f'native_review_required={bool(args.manual_hold)} '
          f'visual_review_required=true '
          f'manifest={manifest_path.relative_to(REPO)}')
    return exit_code


if __name__ == '__main__':
    sys.exit(main())
