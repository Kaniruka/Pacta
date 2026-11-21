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

    def test_tracks_focus_chain_history_renderer(self):
        self.assertIn('lib/src/focus/focus_chain_history.dart', subject.SOURCE_FILES)

    def test_no_removed_legacy_sources_are_tracked(self):
        # 这些页面与转换器已在 Phase 5 删除；清单若还指向它们，基线会在
        # source_snapshot 里直接抛 FileNotFoundError。
        removed = (
            'lib/src/focus/focus_month_page.dart',
            'lib/src/national_focus/national_focus_reconciliation_page.dart',
            'lib/src/sync/legacy_cloud_snapshot.dart',
        )
        tracked = set(subject.SOURCE_FILES)
        self.assertEqual([], [path for path in removed if path in tracked])

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
