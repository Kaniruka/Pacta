#!/usr/bin/env python3
"""Tests for scripts/run_focus_pilot.py using a fake flutter executable.

No device, build or network is involved: the fake command only records argv and
its environment, writes one screenshot into the requested directory and exits
with the code given by FAKE_FLUTTER_RC.
"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

SCRIPT = Path(__file__).with_name('run_focus_pilot.py')

FAKE_FLUTTER = r'''
import json, os, sys
from pathlib import Path
record = os.environ.get("FAKE_FLUTTER_RECORD")
if record:
    Path(record).write_text(json.dumps({
        "argv": sys.argv[1:],
        "subdir": os.environ.get("UI_EVIDENCE_SUBDIR"),
        "strict": os.environ.get("UI_EVIDENCE_FAIL_ON_EXIST"),
    }), encoding="utf-8")
touch = os.environ.get("FAKE_FLUTTER_TOUCH")
if touch:
    Path(touch).write_bytes(b"changed during run")
subdirs = [a.split("FOCUS_PILOT_DIR=", 1)[1] for a in sys.argv[1:] if a.startswith("--dart-define=FOCUS_PILOT_DIR=")]
print("stdout line: drive started")
print("stderr line: fake warning", file=sys.stderr)
if subdirs:
    target = Path("build/ui-layout-evidence") / subdirs[0]
    target.mkdir(parents=True, exist_ok=True)
    (target / "focus-default-wide-overview.png").write_bytes(b"png")
sys.exit(int(os.environ.get("FAKE_FLUTTER_RC", "0")))
'''


def load_module():
    spec = importlib.util.spec_from_file_location('run_focus_pilot', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RunFocusPilotTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fake = self.root / 'fake_flutter.py'
        self.fake.write_text(FAKE_FLUTTER, encoding='utf-8')
        self.record = self.root / 'record.json'
        self.module = load_module()
        self.module.REPO = self.root
        # Working-tree stand-ins so the source snapshot has real hashes.
        for relative in self.module.SOURCE_FILES:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f'stub {relative}\n', encoding='utf-8')
        self.flutter = f'{sys.executable} {self.fake}'
        os.environ['FAKE_FLUTTER_RECORD'] = str(self.record)
        for key in ('FAKE_FLUTTER_RC', 'FAKE_FLUTTER_TOUCH'):
            os.environ.pop(key, None)

    def tearDown(self):
        for key in ('FAKE_FLUTTER_RECORD', 'FAKE_FLUTTER_RC', 'FAKE_FLUTTER_TOUCH'):
            os.environ.pop(key, None)
        self.tmp.cleanup()

    def runs(self):
        return self.root / 'build/ui-layout-evidence/focus-pilot/runs'

    def manifest(self, name):
        directory = self.runs() / name
        return directory, json.loads(
            (directory / 'manifest.json').read_text(encoding='utf-8'))

    def test_success_isolates_evidence_and_logs(self):
        rc = self.module.main(['--flutter', self.flutter, '--run-id', 'r1'])
        self.assertEqual(rc, 0)

        run_dir = self.runs() / 'r1-default-wide'
        self.assertTrue((run_dir / 'focus-default-wide-overview.png').exists())
        log = (run_dir / 'run.log').read_text(encoding='utf-8')
        self.assertIn('stdout line: drive started', log)
        self.assertIn('stderr line: fake warning', log)
        self.assertEqual((run_dir / 'run.rc').read_text(encoding='utf-8').strip(), '0')

        manifest = json.loads((run_dir / 'manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest['status'], 'passed')
        self.assertEqual(manifest['evidence_subdir'], 'focus-pilot/runs/r1-default-wide')
        self.assertEqual(manifest['source_drift'], [])
        self.assertEqual(manifest['source_files'], manifest['source_files_end'])
        self.assertIn('scripts/run_focus_pilot.py', manifest['source_files'])
        self.assertIn('lib/src/focus/chain_signals_card.dart', manifest['source_files'])
        self.assertIsNotNone(manifest['source_files']['scripts/run_focus_pilot.py'])
        self.assertEqual(manifest['args']['scenario'], 'default')
        self.assertFalse(manifest['resolved']['snapshot_only'])

        record = json.loads(self.record.read_text(encoding='utf-8'))
        self.assertEqual(record['subdir'], manifest['evidence_subdir'])
        self.assertEqual(record['strict'], '1')
        self.assertIn('--dart-define=FOCUS_PILOT_DIR=focus-pilot/runs/r1-default-wide',
                      record['argv'])
        self.assertIn('drive', record['argv'])

    def test_board_target_uses_existing_fixture_and_tracks_its_source(self):
        rc = self.module.main(['--flutter', self.flutter, '--run-id', 'board',
                               '--target', 'board', '--scenario', 'long'])
        self.assertEqual(rc, 0)
        record = json.loads(self.record.read_text(encoding='utf-8'))
        self.assertIn('--target=integration_test/board_design_device_test.dart',
                      record['argv'])
        self.assertIn('--dart-define=BOARD_PILOT_MODE=true', record['argv'])
        run_dir = self.root / 'build/ui-layout-evidence/board-pilot/runs/board-long-wide'
        manifest = json.loads((run_dir / 'manifest.json').read_text(encoding='utf-8'))
        self.assertIn('integration_test/board_design_device_test.dart', manifest['source_files'])

    def test_source_drift_marks_evidence_invalid(self):
        os.environ['FAKE_FLUTTER_TOUCH'] = str(self.root / 'lib/main.dart')
        rc = self.module.main(['--flutter', self.flutter, '--run-id', 'drift'])
        self.assertEqual(rc, 3)
        run_dir, manifest = self.manifest('drift-default-wide')
        self.assertEqual(manifest['status'], 'invalid')
        self.assertEqual(manifest['rc'], rc)
        self.assertEqual(manifest['process_rc'], 0)
        self.assertEqual(manifest['source_drift'], ['lib/main.dart'])
        self.assertNotEqual(manifest['source_files']['lib/main.dart'],
                            manifest['source_files_end']['lib/main.dart'])
        self.assertEqual((run_dir / 'run.rc').read_text(encoding='utf-8').strip(), '3')

    def test_failure_propagates_exit_code(self):
        os.environ['FAKE_FLUTTER_RC'] = '7'
        rc = self.module.main(['--flutter', self.flutter, '--run-id', 'r2'])
        self.assertEqual(rc, 7)
        run_dir, manifest = self.manifest('r2-default-wide')
        self.assertEqual(manifest['status'], 'failed')
        self.assertEqual(manifest['rc'], rc)
        self.assertEqual(manifest['process_rc'], 7)
        self.assertEqual((run_dir / 'run.rc').read_text(encoding='utf-8').strip(), '7')

    def test_failure_with_drift_keeps_process_code(self):
        os.environ['FAKE_FLUTTER_RC'] = '9'
        os.environ['FAKE_FLUTTER_TOUCH'] = str(self.root / 'lib/main.dart')
        rc = self.module.main(['--flutter', self.flutter, '--run-id', 'fd'])
        self.assertEqual(rc, 9)
        run_dir, manifest = self.manifest('fd-default-wide')
        self.assertEqual(manifest['status'], 'failed')
        self.assertEqual(manifest['rc'], rc)
        self.assertEqual(manifest['process_rc'], 9)
        self.assertEqual(manifest['source_drift'], ['lib/main.dart'])
        self.assertEqual((run_dir / 'run.rc').read_text(encoding='utf-8').strip(), '9')

    def test_refuses_existing_run_directory(self):
        self.assertEqual(
            self.module.main(['--flutter', self.flutter, '--run-id', 'dup']), 0)
        rc = self.module.main(['--flutter', self.flutter, '--run-id', 'dup'])
        self.assertEqual(rc, 2)
        run_dir = self.runs() / 'dup-default-wide'
        self.assertTrue((run_dir / 'focus-default-wide-overview.png').exists())
        self.assertEqual((run_dir / 'run.rc').read_text(encoding='utf-8').strip(), '0')

    def test_manual_hold_forces_snapshot_only(self):
        self.assertEqual(
            self.module.main([
                '--flutter', self.flutter, '--run-id', 'lt',
                '--theme', 'light', '--manual-hold', '300',
            ]),
            0,
        )
        run_dir, manifest = self.manifest('lt-default-wide-light-hold300')
        self.assertTrue((run_dir / 'run.log').exists())
        self.assertTrue(manifest['resolved']['snapshot_only'])
        record = json.loads(self.record.read_text(encoding='utf-8'))
        self.assertIn('--dart-define=FOCUS_PILOT_LIGHT=true', record['argv'])
        self.assertIn('--dart-define=FOCUS_PILOT_HOLD_SECONDS=300', record['argv'])
        self.assertIn('--dart-define=FOCUS_DESIGN_SNAPSHOT_ONLY=true', record['argv'])

    def test_rejects_bad_arguments(self):
        for argv in (
            ['--scenario', 'defualt', '--flutter', self.flutter],
            ['--view', 'wd', '--flutter', self.flutter],
            ['--manual-hold', '-1', '--flutter', self.flutter],
            ['--run-id', '..', '--flutter', self.flutter],
            ['--run-id', 'a/b', '--flutter', self.flutter],
            ['--run-id', '', '--flutter', self.flutter],
        ):
            with self.assertRaises(SystemExit, msg=argv):
                self.module.main(argv)
        self.assertFalse(self.runs().exists())

    def test_flutter_command_keeps_paths_with_spaces(self):
        spaced = self.root / 'fake dir' / 'fake_flutter.py'
        spaced.parent.mkdir()
        spaced.write_text(FAKE_FLUTTER, encoding='utf-8')
        self.assertEqual(self.module.flutter_command(str(spaced)), [str(spaced).replace('\\', '/')])
        self.assertEqual(
            self.module.flutter_command(f'"{sys.executable}" "{spaced}"'),
            [sys.executable.replace('\\', '/'), str(spaced).replace('\\', '/')],
        )
        with mock.patch.object(self.module.shutil, 'which', return_value=None):
            self.assertEqual(self.module.flutter_command('flutter'), ['flutter'])

    def test_default_flutter_resolves_through_path(self):
        launcher = 'C:/tools/flutter/bin/flutter.bat'
        with mock.patch.object(self.module.shutil, 'which', return_value=launcher) as which:
            self.assertEqual(self.module.flutter_command('flutter'), [launcher])
            which.assert_called_once_with('flutter')

    def test_explicit_flutter_path_is_not_rewritten(self):
        explicit = self.root / 'bin' / 'flutter.bat'
        explicit.parent.mkdir()
        explicit.write_text('@echo off\n', encoding='utf-8')
        with mock.patch.object(self.module.shutil, 'which', return_value='C:/other/flutter.bat') as which:
            self.assertEqual(
                self.module.flutter_command(str(explicit)),
                [str(explicit).replace('\\', '/')],
            )
            which.assert_not_called()

    def test_quoted_command_with_spaces_runs(self):
        spaced = self.root / 'fake dir' / 'fake_flutter.py'
        spaced.parent.mkdir()
        spaced.write_text(FAKE_FLUTTER, encoding='utf-8')
        rc = self.module.main([
            '--flutter', f'"{sys.executable}" "{spaced}"', '--run-id', 'sp',
        ])
        self.assertEqual(rc, 0)
        _, manifest = self.manifest('sp-default-wide')
        self.assertEqual(len(manifest['command'][0:2]), 2)
        self.assertTrue(manifest['command'][1].endswith('fake_flutter.py'))


if __name__ == '__main__':
    unittest.main()
