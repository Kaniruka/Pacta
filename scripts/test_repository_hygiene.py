#!/usr/bin/env python3
"""Black-box tests for scripts/check_repository_hygiene.py.

Each test builds a throwaway repository with a real `git init`, stages paths and
runs the checker as a subprocess, so the contract under test is exactly the one
CI and the local hook rely on: the Git index, the exit codes and the printed
paths. No network, no Flutter and no device are involved.
"""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('check_repository_hygiene.py')
GIT = shutil.which('git')


@unittest.skipUnless(GIT, 'git executable is required for repository hygiene tests')
class RepositoryHygieneTest(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.repo = Path(self._temporary.name) / 'repo'
        self.repo.mkdir()
        self.git('init', '--quiet', '-b', 'main')
        self.git('config', 'user.email', 'hygiene@example.invalid')
        self.git('config', 'user.name', 'Hygiene Test')
        self.git('config', 'commit.gpgsign', 'false')

    def git(self, *arguments, check=True):
        completed = subprocess.run(
            [GIT, '-C', str(self.repo), *arguments],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if check and completed.returncode != 0:
            self.fail(
                'git {} failed: {}'.format(
                    ' '.join(arguments), completed.stderr.decode('utf-8', 'replace')
                )
            )
        return completed

    def write(self, relative_path, text='content\n'):
        target = self.repo / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding='utf-8')
        return target

    def stage(self, *relative_paths, force=False, check=True):
        arguments = ['add']
        if force:
            arguments.append('-f')
        arguments.append('--')
        arguments.extend(relative_paths)
        return self.git(*arguments, check=check)

    def run_checker(self, repo=None, cwd=None, use_repo_option=True):
        command = [sys.executable, str(SCRIPT)]
        if use_repo_option:
            command.extend(['--repo', str(self.repo if repo is None else repo)])
        completed = subprocess.run(
            command,
            cwd=str(cwd if cwd is not None else self.repo),
            capture_output=True,
            check=False,
        )
        return (
            completed.returncode,
            completed.stdout.decode('utf-8', 'replace'),
            completed.stderr.decode('utf-8', 'replace'),
        )

    def assert_reports(self, stderr, *relative_paths):
        for relative_path in relative_paths:
            self.assertIn(relative_path, stderr)

    def test_clean_index_with_product_sources_is_accepted(self):
        self.write('README.md')
        self.write('lib/src/main.dart')
        self.write('test/widget_test.dart')
        self.write('supabase/migrations/20261114000000_init.sql')
        self.write('skills/pacta-national-focus-analysis/SKILL.md')
        self.write('skills/pacta-national-focus-analysis/references/contract.md')
        self.write('packages/panel/docs/readme.md')
        self.stage(
            'README.md',
            'lib',
            'test',
            'supabase',
            'skills',
            'packages',
        )

        returncode, stdout, stderr = self.run_checker()

        self.assertEqual(returncode, 0, stderr)
        self.assertIn('OK', stdout)

    def test_default_repository_is_the_current_directory(self):
        self.write('README.md')
        self.stage('README.md')

        returncode, stdout, stderr = self.run_checker(use_repo_option=False)

        self.assertEqual(returncode, 0, stderr)
        self.assertIn('OK', stdout)

    def test_force_added_ignored_docs_directory_fails(self):
        self.write('.gitignore', 'docs/\n')
        self.write('docs/plan.md')
        self.stage('.gitignore')
        self.stage('docs/plan.md', force=True)

        returncode, stdout, stderr = self.run_checker()

        self.assertEqual(returncode, 1, stderr)
        self.assert_reports(stderr, 'docs/plan.md', 'docs/')

    def test_untracked_but_present_paths_pass(self):
        self.write('README.md')
        self.stage('README.md')
        self.write('docs/plan.md')
        self.stage('docs/plan.md')
        self.git('rm', '--cached', '--quiet', '--', 'docs/plan.md')
        self.write('docs/local-only.md')

        returncode, stdout, stderr = self.run_checker()

        self.assertTrue((self.repo / 'docs' / 'plan.md').exists(), 'rm --cached must keep the file')
        self.assertEqual(returncode, 0, stderr)
        self.assertIn('OK', stdout)

    def test_root_local_documents_fail(self):
        names = ('AGENTS.md', 'CLAUDE.md', 'GLOSSARY.md', 'MISSION.md')
        for name in names:
            self.write(name)
            self.stage(name)

        returncode, stdout, stderr = self.run_checker()

        self.assertEqual(returncode, 1, stderr)
        self.assert_reports(stderr, *names)

    def test_nested_agent_instructions_fail(self):
        paths = (
            'lib/feature/AGENTS.md',
            'lib/feature/AGENTS.override.md',
            'app/CLAUDE.md',
            'app/CLAUDE.local.md',
        )
        for relative_path in paths:
            self.write(relative_path)
            self.stage(relative_path)

        returncode, stdout, stderr = self.run_checker()

        self.assertEqual(returncode, 1, stderr)
        self.assert_reports(stderr, *paths)

    def test_agent_state_directories_fail(self):
        paths = (
            '.scratch/notes.md',
            '.agent/notes.md',
            '.agents/skills/local.md',
            '.codex/config.toml',
            '.claude/settings.json',
            '.cursor/rules.mdc',
        )
        for relative_path in paths:
            self.write(relative_path)
            self.stage(relative_path)

        returncode, stdout, stderr = self.run_checker()

        self.assertEqual(returncode, 1, stderr)
        self.assert_reports(stderr, *paths)

    def test_matching_ignores_case(self):
        paths = ('DOCS/guide.md', 'Agents.md', 'Glossary.md', '.CLAUDE/settings.json')
        for relative_path in paths:
            self.write(relative_path)
            self.stage(relative_path)

        returncode, stdout, stderr = self.run_checker()

        self.assertEqual(returncode, 1, stderr)
        self.assert_reports(stderr, *paths)

    def test_repository_option_works_from_another_directory(self):
        self.write('lib/src/main.dart')
        self.stage('lib')
        elsewhere = Path(self._temporary.name) / 'elsewhere'
        elsewhere.mkdir()

        returncode, stdout, stderr = self.run_checker(cwd=elsewhere)

        self.assertEqual(returncode, 0, stderr)
        self.assertIn('OK', stdout)

    def test_unreadable_index_reports_git_failure(self):
        plain = Path(self._temporary.name) / 'plain'
        plain.mkdir()

        returncode, stdout, stderr = self.run_checker(repo=plain)

        self.assertEqual(returncode, 2, stderr)
        self.assertIn('cannot read the Git index', stderr)

    def test_broken_git_entry_reports_git_failure(self):
        broken = Path(self._temporary.name) / 'broken'
        broken.mkdir()
        (broken / '.git').write_text('not a git directory\n', encoding='utf-8')

        returncode, stdout, stderr = self.run_checker(repo=broken)

        self.assertEqual(returncode, 2, stderr)
        self.assertIn('cannot read the Git index', stderr)

    def test_missing_repository_path_reports_git_failure(self):
        missing = Path(self._temporary.name) / 'missing'

        returncode, stdout, stderr = self.run_checker(repo=missing)

        self.assertEqual(returncode, 2, stderr)
        self.assertIn('cannot read the Git index', stderr)


if __name__ == '__main__':
    unittest.main()
