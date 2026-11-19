import tempfile
import unittest
from pathlib import Path
from unittest import mock

import run_ui_baseline as subject


class SourceSnapshotTests(unittest.TestCase):
    def test_all_declared_source_files_exist(self):
        missing = [
            path
            for path in subject.SOURCE_FILES
            if not (subject.REPO / path).is_file()
        ]
        self.assertEqual([], missing)

    def test_sha256_missing_path_raises(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / 'missing.dart'
            with self.assertRaises(FileNotFoundError):
                subject.sha256(missing)

    def test_snapshot_missing_path_raises(self):
        with mock.patch.object(
            subject, 'SOURCE_FILES', ('does-not-exist/source.dart',)
        ):
            with self.assertRaises(FileNotFoundError):
                subject.source_snapshot()

    def test_non_strict_snapshot_marks_missing_source(self):
        with mock.patch.object(
            subject, 'SOURCE_FILES', ('does-not-exist/source.dart',)
        ):
            snapshot = subject.source_snapshot(strict=False)
        self.assertEqual(
            subject.MISSING_SOURCE, snapshot['does-not-exist/source.dart']
        )


if __name__ == '__main__':
    unittest.main()
