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
the child's exit status. The legacy
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

# Files whose content decides whether the screenshots match the working tree.
# The runner itself is included: editing it mid-run invalidates the evidence.
SOURCE_FILES = (
    'lib/main.dart',
    'lib/src/focus/chain_signals_card.dart',
    'test/focus/chain_signals_card_test.dart',
    'integration_test/focus_chain_design_device_test.dart',
    'test_driver/ui_layout_acceptance_test.dart',
    'scripts/run_focus_pilot.py',
)

RUN_ID_PATTERN = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def snapshot_sources():
    return {
        path: (sha256(REPO / path) if (REPO / path).is_file() else None)
        for path in SOURCE_FILES
    }


def drift_between(before, after):
    return sorted(path for path in SOURCE_FILES if before[path] != after[path])


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
    parser.add_argument('--flutter', default=None,
                        help='executable path (spaces ok) or quoted command line; '
                             'also FOCUS_PILOT_FLUTTER')
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)

    run_id = time.strftime('%Y%m%dT%H%M%S') if args.run_id is None else args.run_id
    if not RUN_ID_PATTERN.match(run_id) or '..' in run_id:
        parser.error(f'unsafe run id: {run_id!r}')

    name = f'{run_id}-{args.scenario}-{args.view}'
    if args.theme == 'light':
        name += '-light'
    if args.manual_hold:
        name += f'-hold{args.manual_hold}'

    subdir = f'focus-pilot/runs/{name}'
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
        '--driver=test_driver/ui_layout_acceptance_test.dart',
        '--target=integration_test/focus_chain_design_device_test.dart',
        '-d',
        args.device,
        '--dart-define=FOCUS_PILOT_MODE=true',
        f'--dart-define=FOCUS_PILOT_SCENARIO={args.scenario}',
        f'--dart-define=FOCUS_PILOT_VIEW={args.view}',
        f'--dart-define=FOCUS_PILOT_DIR={subdir}',
    ]
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
    sources_before = snapshot_sources()
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
    sources_after = snapshot_sources()
    drift = drift_between(sources_before, sources_after)

    if rc != 0:
        status = 'failed'
    elif drift:
        status = 'invalid'
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
        'head': git('rev-parse', 'HEAD'),
        'git_status': (git('status', '--porcelain') or '').splitlines(),
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
          f'manifest={manifest_path.relative_to(REPO)}')
    return exit_code


if __name__ == '__main__':
    sys.exit(main())
