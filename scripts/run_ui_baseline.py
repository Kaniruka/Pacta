#!/usr/bin/env python3
"""Run one UI baseline screenshot pass and keep its evidence apart.

Usage (repo root, Windows):

    python scripts/run_ui_baseline.py --device windows --mode matrix --run-id t6-matrix
    python scripts/run_ui_baseline.py --device emulator-5554 --mode device --run-id t6-android

Each run writes `build/ui-layout-evidence/ui-baseline/runs/<run-id>/` with the
images, `run.log`, `run.rc` and a `manifest.json` that records the command,
HEAD, working-tree status and the SHA-256 of every rendering input. Directories
are never reused; a repeated run id is refused.
"""

import argparse
import hashlib
import json
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
EVIDENCE_ROOT = Path('build/ui-layout-evidence')
RUNS = EVIDENCE_ROOT / 'ui-baseline' / 'runs'

SOURCE_FILES = (
    'test_driver/ui_baseline_test.dart',
    'scripts/run_ui_baseline.py',
    'integration_test/ui_baseline_device_test.dart',
    'lib/main.dart',
    'lib/src/focus/chain_signals_card.dart',
    'lib/src/focus/focus_statistics.dart',
    'lib/src/plan/plan_calendar_view.dart',
    'lib/src/calendar/calendar_page.dart',
    'lib/src/profile/profile_card.dart',
    'lib/src/sync/cloud_sync_card.dart',
    'lib/src/national_focus/national_focus_tree_page.dart',
    'lib/src/theme/pacta_spacing.dart',
    'lib/src/theme/pacta_surfaces.dart',
    'lib/src/ui/pacta_page_header.dart',
)

RUN_ID_PATTERN = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def git(*args):
    try:
        return subprocess.run(
            ['git', *args], cwd=REPO, capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def flutter_command(flutter):
    text = flutter.replace('\\', '/')
    if Path(text).is_file():
        return [text]
    parts = shlex.split(text)
    if parts:
        resolved = shutil.which(parts[0])
        if resolved:
            parts[0] = resolved.replace('\\', '/')
    return parts


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--device', default='windows')
    parser.add_argument('--mode', default='device', choices=('device', 'matrix'))
    parser.add_argument('--pages', default='focus,plan-goals,plan-calendar,my')
    parser.add_argument('--run-id', default=None)
    parser.add_argument('--flutter', default=None)
    args = parser.parse_args(argv)

    run_id = time.strftime('%Y%m%dT%H%M%S') if args.run_id is None else args.run_id
    if not RUN_ID_PATTERN.match(run_id) or '..' in run_id:
        parser.error('unsafe run id: %r' % run_id)

    name = '%s-%s' % (args.mode, args.device.replace(':', '-'))
    out_dir = REPO / RUNS / ('%s-%s' % (run_id, name))
    if out_dir.exists():
        print('refusing to reuse evidence directory: %s' % out_dir, file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True)

    subdir = out_dir.relative_to(REPO / EVIDENCE_ROOT).as_posix()
    command = flutter_command(args.flutter or 'flutter') + [
        'drive',
        '--keep-app-running',
        '--driver=test_driver/ui_baseline_test.dart',
        '--target=integration_test/ui_baseline_device_test.dart',
        '-d',
        args.device,
        '--dart-define=UI_BASELINE_DIR=%s' % subdir,
        '--dart-define=UI_BASELINE_MODE=%s' % args.mode,
        '--dart-define=UI_BASELINE_PAGES=%s' % args.pages,
    ]

    sources = {
        path: (sha256(REPO / path) if (REPO / path).is_file() else None)
        for path in SOURCE_FILES
    }
    head_start = git('rev-parse', 'HEAD')
    status_start = (git('status', '--porcelain') or '').splitlines()
    started = time.strftime('%Y-%m-%dT%H:%M:%S')

    env = dict(**__import__('os').environ)
    env['UI_EVIDENCE_SUBDIR'] = subdir
    log_path = out_dir / 'run.log'
    with open(log_path, 'w', encoding='utf-8') as log:
        log.write('$ %s\n' % ' '.join(command))
        log.flush()
        process = subprocess.run(
            command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, env=env
        )
    (out_dir / 'run.rc').write_text(str(process.returncode) + '\n', encoding='utf-8')

    sources_end = {
        path: (sha256(REPO / path) if (REPO / path).is_file() else None)
        for path in SOURCE_FILES
    }
    manifest = {
        'run_id': run_id,
        'status': 'passed' if process.returncode == 0 else 'failed',
        'rc': process.returncode,
        'device': args.device,
        'mode': args.mode,
        'pages': args.pages,
        'command': command,
        'evidence_subdir': subdir,
        'started_at': started,
        'duration_seconds': round(time.time() - time.mktime(
            time.strptime(started, '%Y-%m-%dT%H:%M:%S')
        ), 1),
        'head_start': head_start,
        'head': git('rev-parse', 'HEAD'),
        'git_status_start': status_start,
        'git_status': (git('status', '--porcelain') or '').splitlines(),
        'source_files': sources,
        'source_files_end': sources_end,
        'source_drift': sorted(
            path for path in SOURCE_FILES if sources[path] != sources_end[path]
        ),
        'visual_review_required': True,
    }
    (out_dir / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8'
    )
    print('run=%s status=%s dir=%s' % (run_id, manifest['status'], out_dir))
    print('rc=%d drift=%s' % (process.returncode, manifest['source_drift']))
    return 0 if process.returncode == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
