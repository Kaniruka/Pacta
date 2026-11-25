"""Offline tests for scripts/pacta_build.py.

No test starts Flutter, Gradle, git or the network: the whitelist JSON, the
command assembly and the keystore flow are all exercised through an injected
fake runner, mirroring scripts/test_run_ui_baseline.py.
"""

import datetime
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
import unittest.mock
import urllib.error

import pacta_build as subject

SECRET_URL = 'https://project-ref.supabase.co'
SECRET_KEY = 'sb_publishable_value_for_tests'
SECRET_VALUE = 'super-secret-value-must-never-be-injected'


class FakeRunner(subject.Runner):
    """Records commands and optionally satisfies them without executing."""

    def __init__(self, *, responses=None, devices=(), hook=None):
        self.commands = []
        self.environments = []
        self._responses = list(responses or [])
        self._devices = list(devices)
        self._hook = hook

    def run(self, command, *, cwd=None, env=None, capture=False, echo=True):
        command = list(command)
        self.commands.append(command)
        self.environments.append(dict(env or {}))
        if self._hook is not None:
            result = self._hook(command)
            if result is not None:
                return result
        if self._responses:
            return self._responses.pop(0)
        if capture:
            return subject.CommandResult(0, json.dumps(self._devices), '')
        return subject.CommandResult(0, '', '')


def dotenv_path(directory, text):
    path = Path(directory) / '.env'
    path.write_text(text, encoding='utf-8', newline='\n')
    return path


def defines_path_from(command):
    for part in command:
        if part.startswith('--dart-define-from-file='):
            return Path(part.split('=', 1)[1])
    return None


class DotenvParsingTests(unittest.TestCase):
    def test_plain_pairs(self):
        values = subject.parse_dotenv('A=1\nB=two\n')
        self.assertEqual({'A': '1', 'B': 'two'}, values)

    def test_bom_crlf_comments_and_blank_lines(self):
        text = '\ufeff# header\r\n\r\nA=1\r\n  # indented comment\r\nB=2\r\n'
        self.assertEqual({'A': '1', 'B': '2'}, subject.parse_dotenv(text))

    def test_quoted_values_keep_spaces_and_strip_comment(self):
        text = 'A=" two words "\nB=\' literal # not a comment \'\nC="v" # trailing\n'
        values = subject.parse_dotenv(text)
        self.assertEqual(' two words ', values['A'])
        self.assertEqual(' literal # not a comment ', values['B'])
        self.assertEqual('v', values['C'])

    def test_double_quote_escapes(self):
        values = subject.parse_dotenv('A="line1\\nline2"\nB="say \\"hi\\""\n')
        self.assertEqual('line1\nline2', values['A'])
        self.assertEqual('say "hi"', values['B'])

    def test_unquoted_inline_comment(self):
        values = subject.parse_dotenv('A=value # note\nB=http://x/y#fragment\n')
        self.assertEqual('value', values['A'])
        self.assertEqual('http://x/y#fragment', values['B'])

    def test_export_prefix_and_empty_value(self):
        values = subject.parse_dotenv('export A=1\nB=\n')
        self.assertEqual({'A': '1', 'B': ''}, values)

    def test_ignores_lines_without_key_or_separator(self):
        values = subject.parse_dotenv('NOT_A_PAIR\n=orphan\n1BAD=x\nOK=1\n')
        self.assertEqual({'OK': '1'}, values)

    def test_read_env_file_missing_is_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual({}, subject.read_env_file(Path(directory) / 'absent.env'))

    def test_read_env_file_reads_bom_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '.env'
            path.write_bytes('\ufeffA=1\r\nB=2\r\n'.encode('utf-8'))
            self.assertEqual({'A': '1', 'B': '2'}, subject.read_env_file(path))


class WhitelistTests(unittest.TestCase):
    def test_priority_cli_then_environment_then_file(self):
        resolved = subject.collect_client_defines(
            cli={'SUPABASE_URL': 'cli-url'},
            environ={'SUPABASE_URL': 'env-url', 'SUPABASE_PUBLISHABLE_KEY': 'env-key'},
            file_values={'SUPABASE_URL': 'file-url', 'SUPABASE_PUBLISHABLE_KEY': 'file-key'},
        )
        self.assertEqual(
            {'SUPABASE_URL': 'cli-url', 'SUPABASE_PUBLISHABLE_KEY': 'env-key'}, resolved
        )

    def test_blank_values_fall_through(self):
        resolved = subject.collect_client_defines(
            cli={'SUPABASE_URL': '   '},
            environ={'SUPABASE_URL': ''},
            file_values={'SUPABASE_URL': 'file-url'},
        )
        self.assertEqual({'SUPABASE_URL': 'file-url'}, resolved)

    def test_only_two_keys_survive(self):
        resolved = subject.collect_client_defines(
            environ={
                'SUPABASE_URL': SECRET_URL,
                'SUPABASE_PUBLISHABLE_KEY': SECRET_KEY,
                'SUPABASE_SECRET_KEY': SECRET_VALUE,
                'SUPABASE_SERVICE_ROLE_KEY': SECRET_VALUE,
                'SUPABASE_ACCESS_TOKEN': SECRET_VALUE,
                'TEST_PASSWORD': SECRET_VALUE,
                'ANDROID_KEYSTORE_PASSWORD': SECRET_VALUE,
            }
        )
        self.assertEqual({'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY'}, set(resolved))

    def test_secret_keys_are_reported_as_ignored(self):
        file_values = {
            'SUPABASE_URL': SECRET_URL,
            'SUPABASE_PUBLISHABLE_KEY': SECRET_KEY,
            'SUPABASE_SECRET_KEY': SECRET_VALUE,
            'SUPABASE_ACCESS_TOKEN': SECRET_VALUE,
            'TEST_PASSWORD': SECRET_VALUE,
        }
        self.assertEqual(
            ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_SECRET_KEY', 'TEST_PASSWORD'],
            subject.ignored_keys(file_values),
        )

    def test_payload_rejects_injected_extra_keys(self):
        payload = subject.defines_payload(
            {'SUPABASE_URL': SECRET_URL, 'SUPABASE_SECRET_KEY': SECRET_VALUE}
        )
        self.assertEqual({'SUPABASE_URL': SECRET_URL}, payload)

    def test_mask_hides_the_value(self):
        masked = subject.mask(SECRET_KEY)
        self.assertNotIn(SECRET_KEY, masked)
        self.assertIn(str(len(SECRET_KEY)), masked)


class DefinesFileTests(unittest.TestCase):
    def test_file_holds_only_whitelisted_keys(self):
        defines = {
            'SUPABASE_URL': SECRET_URL,
            'SUPABASE_PUBLISHABLE_KEY': SECRET_KEY,
            'SUPABASE_SECRET_KEY': SECRET_VALUE,
        }
        with subject.defines_file(defines) as path:
            self.assertTrue(path.is_file())
            payload = json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual(
                {'SUPABASE_URL': SECRET_URL, 'SUPABASE_PUBLISHABLE_KEY': SECRET_KEY}, payload
            )
            self.assertNotIn(SECRET_VALUE, path.read_text(encoding='utf-8'))
            captured = path
        self.assertFalse(captured.exists())

    def test_file_is_deleted_when_the_body_raises(self):
        captured = None
        with self.assertRaises(RuntimeError):
            with subject.defines_file({'SUPABASE_URL': SECRET_URL}) as path:
                captured = path
                raise RuntimeError('boom')
        self.assertIsNotNone(captured)
        self.assertFalse(captured.exists())

    def test_file_is_not_the_dotenv_path(self):
        with subject.defines_file({'SUPABASE_URL': SECRET_URL}) as path:
            self.assertNotEqual('.env', path.name)
            self.assertTrue(path.name.startswith(subject.DEFINES_FILE_PREFIX))


class MissingConfigTests(unittest.TestCase):
    def setUp(self):
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.repo = Path(self._directory.name)

    def _main(self, argv, *, runner=None, environ=None):
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            argv,
            runner=runner or FakeRunner(),
            environ={} if environ is None else environ,
            out=out,
            err=err,
            repo=self.repo,
        )
        return code, out.getvalue(), err.getvalue()

    def test_build_without_configuration_fails_with_exit_code_two(self):
        code, out, err = self._main(['build', '--target', 'apk', '--dry-run'])
        self.assertEqual(subject.EXIT_MISSING_CONFIG, code)
        self.assertIn('SUPABASE_URL', err)
        self.assertIn('SUPABASE_PUBLISHABLE_KEY', err)

    def test_run_without_configuration_fails_with_exit_code_two(self):
        code, _, err = self._main(['run', '--target', 'windows', '--dry-run'])
        self.assertEqual(subject.EXIT_MISSING_CONFIG, code)
        self.assertIn('.env', err)

    def test_partial_configuration_names_the_missing_key(self):
        code, _, err = self._main(
            ['build', '--target', 'apk', '--dry-run'],
            environ={'SUPABASE_URL': SECRET_URL},
        )
        self.assertEqual(subject.EXIT_MISSING_CONFIG, code)
        self.assertIn('SUPABASE_PUBLISHABLE_KEY', err)
        self.assertNotIn('SUPABASE_URL,', err)

    def test_configuration_file_satisfies_the_requirement(self):
        dotenv_path(self.repo, 'SUPABASE_URL=%s\nSUPABASE_PUBLISHABLE_KEY=%s\n' % (SECRET_URL, SECRET_KEY))
        code, out, _ = self._main(['build', '--target', 'apk', '--dry-run'])
        self.assertEqual(subject.EXIT_OK, code)
        self.assertNotIn(SECRET_URL, out)
        self.assertNotIn(SECRET_KEY, out)


class CommandAssemblyTests(unittest.TestCase):
    def test_windows_build(self):
        command = subject.flutter_build_commands(
            'windows', defines_path=Path('defines.json'), mode='release'
        )[0]
        expected = ['build', 'windows', '--release', '--dart-define-from-file=defines.json']
        self.assertEqual(expected, command[-len(expected):])

    def test_apk_split_per_abi(self):
        commands = subject.flutter_build_commands(
            'apk', defines_path=Path('d.json'), mode='release', split_per_abi=True
        )
        self.assertEqual(1, len(commands))
        self.assertIn('--split-per-abi', commands[0])
        self.assertIn('apk', commands[0])
        self.assertIn('build', commands[0])

    def test_appbundle_ignores_split_per_abi(self):
        commands = subject.flutter_build_commands(
            'appbundle', defines_path=Path('d.json'), mode='profile', split_per_abi=True
        )
        self.assertNotIn('--split-per-abi', commands[0])
        self.assertIn('--profile', commands[0])
        self.assertIn('build', commands[0])

    def test_all_expands_to_three_targets(self):
        commands = subject.flutter_build_commands(
            'all', defines_path=Path('d.json'), mode='release'
        )
        self.assertEqual(
            ['windows', 'apk', 'appbundle'],
            [command[command.index('build') + 1] for command in commands],
        )

    def test_run_command_uses_device_and_mode(self):
        command = subject.flutter_run_command(
            device='emulator-5554', defines_path=Path('d.json'), mode='profile'
        )
        self.assertIn('run', command)
        self.assertEqual('emulator-5554', command[command.index('-d') + 1])
        self.assertIn('--profile', command)
        self.assertTrue(command[-1].endswith('--dart-define-from-file=d.json'))

    def test_prepare_steps_order_and_skips(self):
        repo = Path('repo')
        steps = subject.prepare_steps(repo, python='py')
        self.assertEqual('py', steps[0][0])
        self.assertTrue(steps[0][1].endswith(os.path.join('scripts', 'fetch_misans.py')))
        self.assertIn('pub', steps[1])
        self.assertEqual([], subject.prepare_steps(repo, skip_fonts=True, skip_pub_get=True))
        self.assertEqual(1, len(subject.prepare_steps(repo, skip_fonts=True)))
        self.assertEqual(1, len(subject.prepare_steps(repo, skip_pub_get=True)))

    def test_tool_command_wraps_windows_batch_shims(self):
        with unittest.mock.patch.object(subject.shutil, 'which', return_value=r'C:\flutter\flutter.BAT'):
            with unittest.mock.patch.object(subject.sys, 'platform', 'win32'):
                command = subject.tool_command('flutter', 'build', 'apk')
        self.assertEqual(r'C:\flutter\flutter.BAT', command[2])
        self.assertEqual(['build', 'apk'], command[3:])

    def test_tool_command_passes_plain_binary_through(self):
        with unittest.mock.patch.object(subject.shutil, 'which', return_value='/usr/bin/flutter'):
            with unittest.mock.patch.object(subject.sys, 'platform', 'linux'):
                command = subject.tool_command('flutter', 'build', 'apk')
        self.assertEqual(['/usr/bin/flutter', 'build', 'apk'], command)

    def test_build_env_only_sets_gradle_flags_when_required(self):
        plain = subject.build_env({'PATH': 'x'}, require_release_signing=False)
        self.assertEqual({'PATH': 'x'}, plain)
        strict = subject.build_env({'PATH': 'x'}, require_release_signing=True)
        self.assertEqual('true', strict[subject.GRADLE_REQUIRE_SIGNING_ENV])
        self.assertEqual('true', strict[subject.SIGNING_REQUIRED_ENV])


class BuildExecutionTests(unittest.TestCase):
    def setUp(self):
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.repo = Path(self._directory.name)
        dotenv_path(
            self.repo,
            'SUPABASE_URL=%s\n'
            'SUPABASE_PUBLISHABLE_KEY=%s\n'
            'SUPABASE_SECRET_KEY=%s\n'
            'TEST_PASSWORD=%s\n' % (SECRET_URL, SECRET_KEY, SECRET_VALUE, SECRET_VALUE),
        )

    def _run_build(self, argv, *, hook=None):
        runner = FakeRunner(hook=hook)
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            argv, runner=runner, environ={'PATH': 'x'}, out=out, err=err, repo=self.repo
        )
        return code, out.getvalue(), err.getvalue(), runner

    def test_apk_build_runs_prepare_steps_then_flutter_with_temp_defines(self):
        seen = {}

        def hook(command):
            path = defines_path_from(command)
            if path is not None:
                seen['exists'] = path.is_file()
                seen['payload'] = json.loads(path.read_text(encoding='utf-8'))
                seen['path'] = path
            return None

        code, out, err, runner = self._run_build(
            ['build', '--target', 'apk', '--release'], hook=hook
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertEqual(3, len(runner.commands))
        self.assertIn('pub', runner.commands[1])
        self.assertIn('build', runner.commands[2])
        self.assertTrue(seen['exists'])
        self.assertEqual(
            {'SUPABASE_URL': SECRET_URL, 'SUPABASE_PUBLISHABLE_KEY': SECRET_KEY},
            seen['payload'],
        )
        self.assertFalse(seen['path'].exists())
        self.assertNotIn(SECRET_VALUE, out)

    def test_require_release_signing_sets_gradle_environment(self):
        code, _, err, runner = self._run_build(
            ['build', '--target', 'appbundle', '--release', '--require-release-signing']
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertEqual('true', runner.environments[-1][subject.GRADLE_REQUIRE_SIGNING_ENV])

    def test_no_requirements_flag_leaves_gradle_environment_alone(self):
        _, _, _, runner = self._run_build(['build', '--target', 'windows', '--release'])
        self.assertNotIn(subject.GRADLE_REQUIRE_SIGNING_ENV, runner.environments[-1])

    def test_skip_flags_drop_prepare_steps(self):
        _, _, _, runner = self._run_build(
            ['build', '--target', 'windows', '--skip-fonts', '--skip-pub-get']
        )
        self.assertEqual(1, len(runner.commands))

    def test_prepare_step_failure_returns_one_and_runs_nothing_else(self):
        runner = FakeRunner(responses=[subject.CommandResult(1, '', 'font boom')])
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            ['build', '--target', 'apk'],
            runner=runner,
            environ={'PATH': 'x'},
            out=out,
            err=err,
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('fetch_misans.py', err.getvalue())
        self.assertEqual(1, len(runner.commands))

    def test_flutter_failure_removes_the_temp_defines_file(self):
        captured = {}

        def hook(command):
            path = defines_path_from(command)
            if path is not None:
                captured['path'] = path
            return None

        runner = FakeRunner(
            responses=[subject.CommandResult(0), subject.CommandResult(1, '', 'gradle boom')],
            hook=hook,
        )
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            ['build', '--target', 'apk', '--skip-pub-get'],
            runner=runner,
            environ={'PATH': 'x'},
            out=out,
            err=err,
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('构建失败', err.getvalue())
        self.assertIn('path', captured)
        self.assertFalse(captured['path'].exists())

    def test_dry_run_executes_nothing(self):
        code, out, err, runner = self._run_build(['build', '--target', 'windows', '--release', '--dry-run'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertEqual([], runner.commands)
        self.assertIn('[dry-run]', out)
        self.assertIn('--dart-define-from-file=' + subject.DEFINES_PLACEHOLDER, out)
        self.assertNotIn(SECRET_URL, out)
        self.assertNotIn(SECRET_KEY, out)
        self.assertIn('已忽略的非白名单键', out)
        self.assertIn('SUPABASE_SECRET_KEY', out)

    def test_dotenv_path_is_never_passed_to_flutter(self):
        _, _, _, runner = self._run_build(['build', '--target', 'apk'])
        for command in runner.commands:
            for part in command:
                self.assertNotIn('--dart-define-from-file=.env', part)
                if part.startswith('--dart-define-from-file='):
                    self.assertNotEqual('.env', Path(part.split('=', 1)[1]).name)


class RunExecutionTests(unittest.TestCase):
    def setUp(self):
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.repo = Path(self._directory.name)
        dotenv_path(self.repo, 'SUPABASE_URL=%s\nSUPABASE_PUBLISHABLE_KEY=%s\n' % (SECRET_URL, SECRET_KEY))

    def test_run_targets_windows_by_default_with_debug(self):
        runner = FakeRunner()
        code = subject.main(
            ['run', '--skip-fonts', '--skip-pub-get'],
            runner=runner,
            environ={'PATH': 'x'},
            out=io.StringIO(),
            err=io.StringIO(),
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_OK, code)
        command = runner.commands[-1]
        self.assertEqual('windows', command[command.index('-d') + 1])
        self.assertIn('--debug', command)

    def test_run_android_resolves_first_android_device(self):
        runner = FakeRunner(
            devices=[
                {'id': 'windows', 'targetPlatform': 'windows-x64', 'isSupported': True},
                {'id': 'emulator-5554', 'targetPlatform': 'android-x64', 'isSupported': True},
            ]
        )
        code = subject.main(
            ['run', '--target', 'android', '--profile', '--skip-fonts', '--skip-pub-get'],
            runner=runner,
            environ={'PATH': 'x'},
            out=io.StringIO(),
            err=io.StringIO(),
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_OK, code)
        command = runner.commands[-1]
        self.assertEqual('emulator-5554', command[command.index('-d') + 1])
        self.assertIn('--profile', command)

    def test_run_android_without_device_fails_clearly(self):
        runner = FakeRunner(devices=[])
        err = io.StringIO()
        code = subject.main(
            ['run', '--target', 'android', '--skip-fonts', '--skip-pub-get'],
            runner=runner,
            environ={'PATH': 'x'},
            out=io.StringIO(),
            err=err,
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('Android', err.getvalue())

    def test_run_explicit_device_id_is_forwarded(self):
        runner = FakeRunner()
        subject.main(
            ['run', '-d', 'R58M12345', '--skip-fonts', '--skip-pub-get'],
            runner=runner,
            environ={'PATH': 'x'},
            out=io.StringIO(),
            err=io.StringIO(),
            repo=self.repo,
        )
        command = runner.commands[-1]
        self.assertEqual('R58M12345', command[command.index('-d') + 1])


class KeytoolTests(unittest.TestCase):
    def test_prefers_path_lookup(self):
        found = subject.find_keytool(
            environ={}, which=lambda name: r'C:\jdk\bin\keytool.exe', platform='win32'
        )
        self.assertEqual(Path(r'C:\jdk\bin\keytool.exe'), found)

    def test_falls_back_to_java_home(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'bin' / 'keytool.exe'
            binary.parent.mkdir(parents=True)
            binary.write_text('', encoding='utf-8')
            found = subject.find_keytool(
                environ={'JAVA_HOME': directory}, which=lambda name: None, platform='win32'
            )
        self.assertEqual(binary, found)

    def test_falls_back_to_android_studio_jbr(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'keytool.exe'
            binary.write_text('', encoding='utf-8')
            found = subject.find_keytool(
                environ={},
                which=lambda name: None,
                platform='win32',
                studio_roots=[Path(directory)],
            )
        self.assertEqual(binary, found)

    def test_returns_none_when_nothing_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertIsNone(
                subject.find_keytool(
                    environ={'JAVA_HOME': directory},
                    which=lambda name: None,
                    platform='win32',
                    studio_roots=[Path(directory) / 'empty'],
                )
            )

    def test_generated_password_shape(self):
        password = subject.generate_password()
        self.assertEqual(subject.DEFAULT_PASSWORD_LENGTH, len(password))
        self.assertTrue(password[0].isupper())
        self.assertTrue(password[1].islower())
        self.assertTrue(password[2].isdigit())
        self.assertTrue(all(character.isalnum() for character in password))

    def test_generated_password_uses_the_injected_chooser(self):
        password = subject.generate_password(12, chooser=lambda seq: seq[0])
        self.assertEqual(12, len(password))

    def test_generate_password_rejects_short_lengths(self):
        with self.assertRaises(ValueError):
            subject.generate_password(8)

    def test_keytool_command_carries_every_required_argument(self):
        command = subject.keytool_command(
            Path('keytool'),
            keystore=Path('k.jks'),
            alias='pacta-upload',
            dname='CN=Pacta',
            store_password='storepw',
            key_password='keypw',
            storetype='JKS',
        )
        self.assertEqual('keytool', command[0])
        self.assertIn('-genkeypair', command)
        for flag, value in (
            ('-keystore', 'k.jks'),
            ('-alias', 'pacta-upload'),
            ('-storetype', 'JKS'),
            ('-storepass', 'storepw'),
            ('-keypass', 'keypw'),
            ('-dname', 'CN=Pacta'),
        ):
            self.assertEqual(value, command[command.index(flag) + 1])

    def test_masked_command_hides_both_passwords(self):
        command = subject.keytool_command(
            Path('keytool'),
            keystore=Path('k.jks'),
            alias='a',
            dname='CN=P',
            store_password='storepw',
            key_password='storepw',
        )
        text = subject.masked_command(command, ('storepw',))
        self.assertNotIn('storepw', text)
        self.assertIn('<hidden>', text)

    def test_properties_text_uses_relative_store_file(self):
        text = subject.properties_text(
            store_file='upload-keystore.jks',
            store_password='p',
            key_alias='pacta-upload',
            key_password='p',
        )
        self.assertIn('storeFile=upload-keystore.jks', text)
        self.assertIn('keyAlias=pacta-upload', text)
        self.assertTrue(text.endswith('\n'))

    def test_store_file_is_relative_to_the_app_module(self):
        app_dir = Path('repo') / 'android' / 'app'
        value = subject.gradle_store_file_value(app_dir / 'upload-keystore.jks', app_dir=app_dir)
        self.assertEqual('upload-keystore.jks', value)

    def test_store_file_outside_the_app_module_stays_absolute(self):
        app_dir = Path('repo') / 'android' / 'app'
        value = subject.gradle_store_file_value(
            Path('other') / 'elsewhere.jks', app_dir=app_dir
        )
        self.assertEqual('other/elsewhere.jks', value)


class InitKeystoreTests(unittest.TestCase):
    def setUp(self):
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.repo = Path(self._directory.name)
        binary_dir = self.repo / 'jdk' / 'bin'
        binary_dir.mkdir(parents=True)
        (binary_dir / 'keytool.exe').write_text('', encoding='utf-8')
        self.environ = {'JAVA_HOME': str(self.repo / 'jdk')}
        # `keytool` must resolve through JAVA_HOME only, never through this machine's PATH.
        patcher = unittest.mock.patch.object(subject.shutil, 'which', return_value=None)
        patcher.start()
        self.addCleanup(patcher.stop)

    def _main(self, argv, *, runner):
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            argv, runner=runner, environ=self.environ, out=out, err=err, repo=self.repo
        )
        return code, out.getvalue(), err.getvalue()

    @staticmethod
    def _create_keystore(command):
        if '-keystore' not in command:
            return None
        path = Path(command[command.index('-keystore') + 1])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'fake-keystore')
        return None

    def test_dry_run_writes_nothing_and_hides_passwords(self):
        code, out, err = self._main(
            ['init-keystore', '--dry-run', '--store-password', 'StorePassword1'], runner=FakeRunner()
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('[dry-run]', out)
        self.assertNotIn('StorePassword1', out)
        self.assertIn('<hidden>', out)
        self.assertFalse((self.repo / subject.DEFAULT_KEYSTORE).exists())
        self.assertFalse((self.repo / subject.DEFAULT_PROPERTIES).exists())

    def test_generates_keystore_and_properties(self):
        runner = FakeRunner(hook=self._create_keystore)
        code, out, err = self._main(['init-keystore'], runner=runner)
        self.assertEqual(subject.EXIT_OK, code, err)
        keystore = self.repo / subject.DEFAULT_KEYSTORE
        properties = self.repo / subject.DEFAULT_PROPERTIES
        self.assertTrue(keystore.is_file())
        text = properties.read_text(encoding='utf-8')
        self.assertIn('storeFile=upload-keystore.jks\n', text)
        self.assertIn('keyAlias=pacta-upload\n', text)
        store_password = text.split('storePassword=', 1)[1].split('\n', 1)[0]
        self.assertEqual(subject.DEFAULT_PASSWORD_LENGTH, len(store_password))
        self.assertNotIn(store_password, out)
        self.assertIn('ANDROID_KEYSTORE_BASE64', out)
        command = runner.commands[0]
        self.assertEqual('PKCS12', command[command.index('-storetype') + 1])
        self.assertEqual('pacta-upload', command[command.index('-alias') + 1])
        ignore_check = runner.commands[1]
        self.assertIn('check-ignore', ignore_check)
        # `git check-ignore -q` accepts a single path only.
        self.assertNotIn('-q', ignore_check)

    def test_custom_alias_and_keystore_path(self):
        runner = FakeRunner(hook=self._create_keystore)
        code, _, err = self._main(
            ['init-keystore', '--keystore', 'secrets/my.jks', '--alias', 'custom-alias'],
            runner=runner,
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        text = (self.repo / subject.DEFAULT_PROPERTIES).read_text(encoding='utf-8')
        store_file = text.split('storeFile=', 1)[1].split('\n', 1)[0]
        # Outside android/app the path must stay absolute: Gradle resolves
        # relative storeFile values against the app module.
        self.assertTrue(store_file.endswith('/secrets/my.jks'), store_file)
        self.assertNotIn('\\', store_file)
        self.assertIn('keyAlias=custom-alias\n', text)

    def test_different_key_password_switches_to_jks(self):
        runner = FakeRunner(hook=self._create_keystore)
        code, _, err = self._main(
            [
                'init-keystore',
                '--store-password',
                'StorePassword1',
                '--key-password',
                'KeyPassword2',
            ],
            runner=runner,
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        command = runner.commands[0]
        self.assertEqual('JKS', command[command.index('-storetype') + 1])
        self.assertEqual('KeyPassword2', command[command.index('-keypass') + 1])

    def test_existing_files_are_not_overwritten_without_force(self):
        properties = self.repo / subject.DEFAULT_PROPERTIES
        properties.parent.mkdir(parents=True, exist_ok=True)
        properties.write_text('storeFile=keep.jks\n', encoding='utf-8')
        runner = FakeRunner(hook=self._create_keystore)
        code, out, err = self._main(['init-keystore'], runner=runner)
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertEqual([], runner.commands)
        self.assertEqual('storeFile=keep.jks\n', properties.read_text(encoding='utf-8'))
        self.assertIn('--force', out)

    def test_force_regenerates_everything(self):
        properties = self.repo / subject.DEFAULT_PROPERTIES
        properties.parent.mkdir(parents=True, exist_ok=True)
        properties.write_text('storeFile=stale.jks\n', encoding='utf-8')
        runner = FakeRunner(hook=self._create_keystore)
        code, _, err = self._main(['init-keystore', '--force'], runner=runner)
        self.assertEqual(subject.EXIT_OK, code, err)
        text = properties.read_text(encoding='utf-8')
        self.assertIn('storeFile=upload-keystore.jks\n', text)
        self.assertNotIn('stale.jks', text)

    def test_missing_keytool_reports_an_error(self):
        with unittest.mock.patch.object(subject, 'find_keytool', return_value=None):
            code, _, err = self._main(['init-keystore'], runner=FakeRunner())
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('keytool', err)

    def test_keytool_failure_reports_an_error(self):
        runner = FakeRunner(responses=[subject.CommandResult(1, '', 'keytool boom')])
        code, _, err = self._main(['init-keystore'], runner=runner)
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('keytool', err)
        self.assertFalse((self.repo / subject.DEFAULT_PROPERTIES).exists())

    def test_missing_keystore_after_keytool_fails(self):
        code, _, err = self._main(['init-keystore'], runner=FakeRunner())
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('keystore', err)


class FakeHTTPResponse:
    """Minimal urllib response: a JSON body plus a close hook."""

    def __init__(self, payload, status=200):
        self._body = json.dumps(payload).encode('utf-8')
        self.status = status

    def read(self):
        return self._body

    def close(self):
        pass


class FakeSupabaseAPI:
    """Offline urllib opener: routes by URL and by the POSTed SQL text."""

    def __init__(self, *, overview=None, tables=(), users=(), project=None, service=None):
        self.requests = []
        self.overview = overview if overview is not None else {}
        self.tables = list(tables)
        self.users = list(users)
        self.project = project if project is not None else {
            'name': 'pacta',
            'region': 'ap-southeast-1',
            'status': 'ACTIVE_HEALTHY',
        }
        self.service = dict(service or {})

    def __call__(self, request, timeout=None):
        self.requests.append(request)
        url = request.full_url
        if url.endswith('/database/query'):
            query = json.loads(request.data.decode('utf-8'))['query']
            if 'pg_database_size' in query:
                return FakeHTTPResponse([self.overview])
            if 'has_user_id' in query:
                return FakeHTTPResponse(self.tables)
            return FakeHTTPResponse(self.users)
        if '/projects/' in url:
            return FakeHTTPResponse(self.project)
        if '/auth/v1/admin/users' in url:
            return FakeHTTPResponse({'users': self.service.get('users', [])})
        for table in (
            'cloud_business_snapshots',
            'cloud_business_snapshot_history',
            'profile_accounts',
        ):
            if '/rest/v1/' + table in url:
                return FakeHTTPResponse(self.service.get(table, []))
        raise urllib.error.HTTPError(url, 404, 'Not Found', {}, None)


class InteractiveAndReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.repo = Path(self._directory.name)
        (self.repo / '.env').write_text(
            'SUPABASE_URL=https://example.supabase.co\n'
            'SUPABASE_PUBLISHABLE_KEY=sb_publishable_demo\n'
            'SUPABASE_SECRET_KEY=sb_secret_never_inject\n',
            encoding='utf-8',
        )
        binary_dir = self.repo / 'jdk' / 'bin'
        binary_dir.mkdir(parents=True)
        (binary_dir / 'keytool.exe').write_text('', encoding='utf-8')
        self.environ = {'JAVA_HOME': str(self.repo / 'jdk')}
        patcher = unittest.mock.patch.object(subject.shutil, 'which', return_value=None)
        patcher.start()
        self.addCleanup(patcher.stop)

    def _run_interactive(self, argv, choices, *, runner=None, is_tty=None, urlopen_fn=None):
        iterator = iter(choices or ())
        prompts = []

        def fake_input(prompt=''):
            prompts.append(prompt)
            try:
                return next(iterator)
            except StopIteration as stop:
                raise EOFError() from stop

        runner = FakeRunner() if runner is None else runner
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            argv,
            runner=runner,
            environ=self.environ,
            out=out,
            err=err,
            repo=self.repo,
            input_fn=fake_input if choices is not None else None,
            is_tty=is_tty,
            urlopen_fn=urlopen_fn,
        )
        return code, out.getvalue(), err.getvalue(), runner, prompts

    def test_non_tty_without_subcommand_prints_help_and_exits_2(self):
        code, _, err, runner, _ = self._run_interactive([], None, is_tty=False)
        self.assertEqual(subject.EXIT_MISSING_CONFIG, code)
        self.assertEqual([], runner.commands)
        self.assertIn('usage:', err)

    def test_main_menu_lists_two_level_categories_and_quit_exits_cleanly(self):
        for quit_choice in ('0', 'q', 'quit', 'exit'):
            code, out, err, runner, _ = self._run_interactive([], [quit_choice])
            self.assertEqual(subject.EXIT_OK, code, err)
            self.assertEqual([], runner.commands)
            self.assertIn('交互式构建与运行', out)
            self.assertIn('1) 运行调试 (Run)', out)
            self.assertIn('2) 构建与打包 (Build)', out)
            self.assertIn('3) 签名与发布凭据 (Signing & GitHub Secrets)', out)
            self.assertIn('4) Supabase 云端配额与用量 (Supabase Usage)', out)
            self.assertNotIn('sb_secret_never_inject', out + err)

    def test_menu_header_reports_quota_mode_and_signing_status(self):
        code, out, err, _, _ = self._run_interactive([], ['0'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('Supabase 配额查询：Service API 估算模式', out)
        self.assertIn('Android Release 签名：未生成', out)

    def test_invalid_main_menu_choice_reprompts(self):
        code, out, err, _, _ = self._run_interactive([], ['bad-option', '0'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('无效编号', err)
        self.assertIn('交互式构建与运行', out)

    def test_run_category_runs_windows_and_android_with_a_mode(self):
        device_json = json.dumps(
            [{'id': 'emulator-5554', 'targetPlatform': 'android-arm64', 'isSupported': True}]
        )
        scenarios = (
            (['1', '1', '1'], [], 'run -d windows --debug'),
            (['1', '1', ''], [], 'run -d windows --debug'),
            (
                ['1', '2', '2'],
                [subject.CommandResult(0, device_json, '')],
                'run -d emulator-5554 --profile',
            ),
            (
                ['1', '2', '3'],
                [subject.CommandResult(0, device_json, '')],
                'run -d emulator-5554 --release',
            ),
        )
        for choices, responses, expected in scenarios:
            runner = FakeRunner(responses=responses)
            code, out, err, _, _ = self._run_interactive(
                ['--dry-run', 'interactive'], choices, runner=runner
            )
            self.assertEqual(subject.EXIT_OK, code, err)
            self.assertIn(expected, out)
            self.assertNotIn('sb_secret_never_inject', out + err)

    def test_run_category_rejects_blank_device_and_back_returns_to_main_menu(self):
        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['1', '3', '   ', '0', '0'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('设备 ID 不能为空', err)
        self.assertNotIn('flutter run', out)

    def test_run_category_accepts_a_manual_device_id(self):
        code, out, err, _, _ = self._run_interactive(
            ['--dry-run', 'interactive'], ['1', '3', 'emulator-9999', '1']
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('run -d emulator-9999 --debug', out)

    def test_build_category_maps_every_option(self):
        scenarios = (
            ('1', 'build --target windows --release'),
            ('2', 'build --target apk --release'),
            ('4', 'build --target appbundle --release'),
            ('5', 'build --target all --release'),
        )
        for choice, expected in scenarios:
            code, out, err, runner, _ = self._run_interactive(['--dry-run', 'interactive'], ['2', choice])
            self.assertEqual(subject.EXIT_OK, code, err)
            self.assertIn(expected, out)
            self.assertEqual([], runner.commands)
        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['2', '3'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('build --target apk --release', out)
        self.assertIn('--split-per-abi', out)
        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['2', '5'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('requireReleaseSigning=true', out)

    def test_signing_category_generates_keystore_and_guards_force_overwrite(self):
        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['3', '1'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('keytool', out)

        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['3', '2', 'n', '0', '0'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('已取消，未覆盖任何签名文件', out)
        self.assertNotIn('keytool', out)

        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['3', '2', 'y'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('keytool', out)

    def test_signing_category_exports_github_secrets_manifest(self):
        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['3', '3'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('GitHub Secrets', out)

        code, out, err, _, _ = self._run_interactive(['--dry-run', 'interactive'], ['3', '4'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('gh secret set', out)

    def test_supabase_category_prints_report_and_pauses_after_an_error(self):
        api = FakeSupabaseAPI(
            overview={'db_bytes': 1024, 'total_users': 0, 'mau_30d': 0, 'storage_bytes': 0}
        )
        (self.repo / '.env').write_text(
            'SUPABASE_URL=https://example.supabase.co\n'
            'SUPABASE_PUBLISHABLE_KEY=sb_publishable_demo\n'
            'SUPABASE_ACCESS_TOKEN=menu-token\n',
            encoding='utf-8',
        )
        code, out, err, _, _ = self._run_interactive(['interactive'], ['4', '1'], urlopen_fn=api)
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('Management API 精确模式', out)
        self.assertNotIn('menu-token', out + err)

        (self.repo / '.env').write_text(
            'SUPABASE_URL=https://example.supabase.co\n'
            'SUPABASE_PUBLISHABLE_KEY=sb_publishable_demo\n',
            encoding='utf-8',
        )
        code, out, err, _, prompts = self._run_interactive(['interactive'], ['4', '1', '', '0'])
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('SUPABASE_ACCESS_TOKEN', err)
        self.assertIn('按回车返回主菜单', prompts[-2])

    def test_release_workflow_declares_android_signing_secrets_and_strict_flag(self):
        workflow_path = Path(subject.__file__).resolve().parent.parent / '.github' / 'workflows' / 'release.yml'
        text = workflow_path.read_text(encoding='utf-8')
        for required_secret in (
            'ANDROID_KEYSTORE_BASE64',
            'ANDROID_KEYSTORE_PASSWORD',
            'ANDROID_KEY_ALIAS',
            'ANDROID_KEY_PASSWORD',
            'SUPABASE_URL',
            'SUPABASE_PUBLISHABLE_KEY',
        ):
            self.assertIn('secrets.' + required_secret, text)
        self.assertIn('--require-release-signing', text)
        self.assertIn('--require-windows-installer', text)
        self.assertIn('build/Pacta-windows-x64-release.zip', text)
        self.assertIn('build/Pacta-windows-x64-setup.exe', text)

    def test_windows_build_packages_portable_zip_and_invokes_iscc_for_setup_exe(self):
        import zipfile

        release_dir = subject.windows_runner_output_dir(self.repo, 'release')
        (release_dir / 'data').mkdir(parents=True)
        (release_dir / 'pacta.exe').write_bytes(b'MZ-fake-pacta')
        (release_dir / 'flutter_windows.dll').write_bytes(b'DLL-fake')
        (release_dir / 'data' / 'app.so').write_bytes(b'AOT-fake')
        (self.repo / 'pubspec.yaml').write_text('name: pacta\nversion: 0.3.0+3\n', encoding='utf-8')
        iss = self.repo / subject.DEFAULT_WINDOWS_ISS
        iss.parent.mkdir(parents=True)
        iss.write_text('; fake iss\n', encoding='utf-8')
        iscc = self.repo / 'inno' / 'ISCC.exe'
        iscc.parent.mkdir(parents=True)
        iscc.write_text('', encoding='utf-8')

        runner = FakeRunner()
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            [
                'build',
                '--target',
                'windows',
                '--release',
                '--require-windows-installer',
                '--skip-fonts',
                '--skip-pub-get',
            ],
            runner=runner,
            environ=dict(self.environ, ISCC_PATH=str(iscc)),
            out=out,
            err=err,
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        zip_path = subject.windows_portable_zip_path(self.repo, 'release')
        self.assertTrue(zip_path.is_file())
        with zipfile.ZipFile(zip_path) as archive:
            names = set(archive.namelist())
        self.assertEqual(
            {'Pacta/pacta.exe', 'Pacta/flutter_windows.dll', 'Pacta/data/app.so'},
            names,
        )
        self.assertEqual(2, len(runner.commands))
        iscc_cmd = runner.commands[1]
        self.assertEqual(str(iscc), iscc_cmd[0])
        self.assertIn('/DMyAppVersion=0.3.0', iscc_cmd)
        self.assertIn('/DMyOutputBaseFilename=Pacta-windows-x64-setup', iscc_cmd)

    def test_require_windows_installer_fails_when_iscc_missing(self):
        release_dir = subject.windows_runner_output_dir(self.repo, 'release')
        release_dir.mkdir(parents=True)
        (release_dir / 'pacta.exe').write_bytes(b'MZ')
        with unittest.mock.patch.object(subject, 'find_iscc', return_value=None):
            out, err = io.StringIO(), io.StringIO()
            code = subject.main(
                [
                    'build',
                    '--target',
                    'windows',
                    '--release',
                    '--require-windows-installer',
                    '--skip-fonts',
                    '--skip-pub-get',
                ],
                runner=FakeRunner(),
                environ=self.environ,
                out=out,
                err=err,
                repo=self.repo,
            )
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('ISCC.exe', err.getvalue())

    def test_github_secrets_exports_manifest_and_can_apply_via_gh(self):
        import base64

        keystore = self.repo / subject.DEFAULT_KEYSTORE
        keystore.parent.mkdir(parents=True, exist_ok=True)
        keystore.write_bytes(b'fake-keystore-binary')
        properties = self.repo / subject.DEFAULT_PROPERTIES
        properties.parent.mkdir(parents=True, exist_ok=True)
        properties.write_text(
            'storeFile=upload-keystore.jks\n'
            'storePassword=StorePass123456\n'
            'keyAlias=pacta-upload\n'
            'keyPassword=KeyPass654321\n',
            encoding='utf-8',
        )

        runner = FakeRunner()
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            ['github-secrets', '--apply'],
            runner=runner,
            environ=self.environ,
            out=out,
            err=err,
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_OK, code, err.getvalue())
        manifest = (self.repo / subject.DEFAULT_GITHUB_SECRETS_FILE).read_text(encoding='utf-8')
        expected_b64 = base64.b64encode(b'fake-keystore-binary').decode('ascii')
        self.assertIn('SUPABASE_URL=https://example.supabase.co\n', manifest)
        self.assertIn('SUPABASE_PUBLISHABLE_KEY=sb_publishable_demo\n', manifest)
        self.assertIn('ANDROID_KEYSTORE_BASE64=' + expected_b64 + '\n', manifest)
        self.assertIn('ANDROID_KEYSTORE_PASSWORD=StorePass123456\n', manifest)
        self.assertIn('ANDROID_KEY_ALIAS=pacta-upload\n', manifest)
        self.assertIn('ANDROID_KEY_PASSWORD=KeyPass654321\n', manifest)
        self.assertNotIn('sb_secret_never_inject', manifest)
        self.assertNotIn('StorePass123456', out.getvalue())
        self.assertEqual(6, len(runner.commands))


USAGE_MGMT_TOKEN = 'management-token-must-never-leak'
USAGE_OPAQUE_KEY = 'sb_secret_opaque_value'
USAGE_JWT_KEY = 'header.payload.signature'


class SupabaseUsageTests(unittest.TestCase):
    def setUp(self):
        self._directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._directory.cleanup)
        self.repo = Path(self._directory.name)

    def _write_env(self, body):
        (self.repo / '.env').write_text(body, encoding='utf-8')

    def _management_env(self):
        self._write_env(
            'SUPABASE_URL=https://project-ref.supabase.co\n'
            'SUPABASE_ACCESS_TOKEN=' + USAGE_MGMT_TOKEN + '\n'
            'SUPABASE_SECRET_KEY=' + USAGE_OPAQUE_KEY + '\n'
        )

    def _default_api(self, **overrides):
        api = FakeSupabaseAPI(
            overview={
                'db_bytes': 10 * 1024 * 1024,
                'public_bytes': 8 * 1024 * 1024,
                'total_users': 2,
                'mau_30d': 1,
                'storage_bytes': 4 * 1024 * 1024,
                'storage_objects': 7,
            },
            tables=[
                {
                    'table_name': 'cloud_business_snapshots',
                    'total_bytes': 6 * 1024 * 1024,
                    'table_bytes': 5 * 1024 * 1024,
                    'index_bytes': 1024 * 1024,
                    'toast_bytes': 0,
                    'live_rows': 40,
                    'has_user_id': True,
                },
                {
                    'table_name': 'profile_accounts',
                    'total_bytes': 2 * 1024 * 1024,
                    'table_bytes': 1024 * 1024,
                    'index_bytes': 1024 * 1024,
                    'toast_bytes': 0,
                    'live_rows': 3,
                    'has_user_id': True,
                },
                {
                    'table_name': 'national_focus_cards',
                    'total_bytes': 1024,
                    'table_bytes': 1024,
                    'index_bytes': 0,
                    'toast_bytes': 0,
                    'live_rows': 1,
                    'has_user_id': False,
                },
            ],
            users=[
                {
                    'user_id': 'u1',
                    'email': 'alpha@example.com',
                    'display_name': 'Alpha',
                    'last_sign_in_at': '2026-11-01T00:00:00Z',
                    'snapshot_bytes': 4 * 1024 * 1024,
                    'history_bytes': 0,
                    'history_count': 0,
                    'profile_bytes': 1024 * 1024,
                    'other_bytes': 0,
                    'storage_bytes': 3 * 1024 * 1024,
                    'storage_objects': 7,
                    'db_bytes': 5 * 1024 * 1024,
                    'total_bytes': 8 * 1024 * 1024,
                },
                {
                    'user_id': 'u2',
                    'email': 'beta@example.com',
                    'display_name': '',
                    'last_sign_in_at': '',
                    'snapshot_bytes': 1024 * 1024,
                    'history_bytes': 0,
                    'history_count': 0,
                    'profile_bytes': 0,
                    'other_bytes': 0,
                    'storage_bytes': 0,
                    'storage_objects': 0,
                    'db_bytes': 1024 * 1024,
                    'total_bytes': 1024 * 1024,
                },
            ],
        )
        for key, value in overrides.items():
            setattr(api, key, value)
        return api

    def _run(self, argv, *, api=None, environ=None):
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            argv,
            runner=FakeRunner(),
            environ={} if environ is None else environ,
            out=out,
            err=err,
            repo=self.repo,
            urlopen_fn=api,
        )
        return code, out.getvalue(), err.getvalue()

    def test_management_mode_reports_exact_quota_and_per_user_usage(self):
        self._management_env()
        api = self._default_api()
        code, out, err = self._run(['supabase-usage'], api=api)
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('Management API 精确模式', out)
        self.assertIn('project-ref', out)
        self.assertIn('alpha@example.com', out)
        self.assertIn('cloud_business_snapshots', out)
        self.assertNotIn(USAGE_MGMT_TOKEN, out + err)

        query_requests = [r for r in api.requests if r.full_url.endswith('/database/query')]
        self.assertEqual(3, len(query_requests))
        self.assertEqual(
            'Bearer ' + USAGE_MGMT_TOKEN, query_requests[0].get_header('Authorization')
        )
        breakdown_sql = json.loads(query_requests[2].data.decode('utf-8'))['query']
        self.assertIn('cloud_business_snapshots', breakdown_sql)
        self.assertIn('profile_accounts', breakdown_sql)
        self.assertNotIn('national_focus_cards', breakdown_sql)
        self.assertIn('storage.objects', breakdown_sql)
        self.assertNotIn(USAGE_MGMT_TOKEN, breakdown_sql)

    def test_json_report_is_valid_json_without_credentials(self):
        self._management_env()
        api = self._default_api()
        code, out, err = self._run(['usage', '--json'], api=api)
        self.assertEqual(subject.EXIT_OK, code, err)
        report = json.loads(out)
        self.assertEqual('management', report['source'])
        self.assertTrue(report['exact_database_size'])
        self.assertEqual(500 * 1024 * 1024, report['limits']['database_bytes'])
        self.assertEqual(2.0, report['database']['used_pct'])
        self.assertEqual(6 * 1024 * 1024, report['database']['user_data_bytes'])
        self.assertEqual(4 * 1024 * 1024, report['database']['system_bytes'])
        self.assertEqual(4 * 1024 * 1024, report['storage']['used_bytes'])
        self.assertEqual(7, report['storage']['objects'])
        self.assertEqual(1, report['mau']['used'])
        first = report['users']['breakdown'][0]
        self.assertEqual(1.6, first['share_of_free_db_pct'])
        self.assertEqual('Alpha', first['display_name'])
        for credential in (USAGE_MGMT_TOKEN, USAGE_OPAQUE_KEY):
            self.assertNotIn(credential, out + err)
        self.assertEqual([], report['notes'])

    def test_view_and_top_and_mask_email_shape_the_output(self):
        self._management_env()
        code, out, err = self._run(['quota', '--view', 'users', '--top', '1'], api=self._default_api())
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('alpha@example.com', out)
        self.assertNotIn('beta@example.com', out)
        self.assertIn('其余 1 位用户合计', out)

        code, out, err = self._run(
            ['usage', '--view', 'users', '--mask-email'], api=self._default_api()
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertIn('al***@example.com', out)
        self.assertNotIn('alpha@example.com', out)

        code, out, err = self._run(['usage', '--json', '--top', '1'], api=self._default_api())
        report = json.loads(out)
        self.assertEqual(1, len(report['users']['breakdown']))
        self.assertEqual(1, report['users']['remaining']['users'])
        self.assertEqual(1024 * 1024, report['users']['remaining']['total_bytes'])

    def test_dry_run_makes_no_http_calls(self):
        self._management_env()
        api = self._default_api()
        code, out, err = self._run(
            [
                'supabase-usage',
                '--dry-run',
                '--source',
                'service',
                '--db-limit-mb',
                '500',
                '--storage-limit-mb',
                '1024',
                '--mau-limit',
                '50000',
            ],
            api=api,
        )
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertEqual([], api.requests)
        self.assertIn('project-ref', out)
        self.assertIn('Service API 估算模式', out)
        self.assertIn('500 MB', out)
        self.assertNotIn(USAGE_MGMT_TOKEN, out + err)

    def test_service_mode_uses_apikey_only_for_opaque_secret(self):
        now = datetime.datetime.now(datetime.timezone.utc)
        self._write_env(
            'SUPABASE_URL=https://project-ref.supabase.co\n'
            'SUPABASE_SECRET_KEY=' + USAGE_OPAQUE_KEY + '\n'
        )
        api = FakeSupabaseAPI(
            service={
                'users': [
                    {
                        'id': 'u1',
                        'email': 'alpha@example.com',
                        'last_sign_in_at': (now - datetime.timedelta(days=2)).isoformat(),
                        'user_metadata': {'display_name': 'Alpha'},
                    }
                ],
                'cloud_business_snapshots': [
                    {'user_id': 'u1', 'payload': {'a': 'x' * 10}, 'row_count': 3}
                ],
                'cloud_business_snapshot_history': [
                    {'user_id': 'u1', 'payload': {'b': 'y' * 5}, 'row_count': 2}
                ],
                'profile_accounts': [
                    {
                        'user_id': 'u1',
                        'display_name': 'Alpha',
                        'avatar_bytes': '\\x' + 'ab' * 4,
                        'avatar_mime_type': 'image/png',
                    }
                ],
            }
        )
        code, out, err = self._run(['usage', '--json', '--source', 'service'], api=api)
        self.assertEqual(subject.EXIT_OK, code, err)
        self.assertTrue(api.requests)
        headers = {key.lower(): value for key, value in api.requests[0].headers.items()}
        self.assertEqual(USAGE_OPAQUE_KEY, headers['apikey'])
        self.assertNotIn('authorization', headers)

        report = json.loads(out)
        self.assertEqual('service', report['source'])
        self.assertFalse(report['exact_database_size'])
        self.assertIsNone(report['database']['system_bytes'])
        self.assertEqual(0, report['storage']['used_bytes'])
        self.assertEqual(1, report['mau']['used'])
        profile = report['users']['breakdown'][0]
        self.assertEqual(4, profile['profile_bytes'])
        self.assertEqual(2, profile['history_count'])
        self.assertGreater(profile['snapshot_bytes'], 0)
        self.assertTrue(any('SUPABASE_ACCESS_TOKEN' in note for note in report['notes']))
        self.assertNotIn(USAGE_OPAQUE_KEY, out + err)

    def test_service_mode_sends_bearer_for_legacy_jwt_secret(self):
        self._write_env(
            'SUPABASE_URL=https://project-ref.supabase.co\n'
            'SUPABASE_SERVICE_ROLE_KEY=' + USAGE_JWT_KEY + '\n'
        )
        api = FakeSupabaseAPI(service={'users': []})
        code, out, err = self._run(['usage', '--json', '--source', 'service'], api=api)
        self.assertEqual(subject.EXIT_OK, code, err)
        headers = {key.lower(): value for key, value in api.requests[0].headers.items()}
        self.assertEqual(USAGE_JWT_KEY, headers['apikey'])
        self.assertEqual('Bearer ' + USAGE_JWT_KEY, headers['authorization'])
        self.assertNotIn(USAGE_JWT_KEY, out + err)

    def test_missing_credentials_name_both_sources(self):
        self._write_env(
            'SUPABASE_URL=https://project-ref.supabase.co\n'
            'SUPABASE_PUBLISHABLE_KEY=sb_publishable_demo\n'
        )
        code, out, err = self._run(['supabase-usage'], api=FakeSupabaseAPI())
        self.assertEqual(subject.EXIT_MISSING_CONFIG, code)
        self.assertIn('SUPABASE_ACCESS_TOKEN', err)
        self.assertIn('SUPABASE_SECRET_KEY', err)

    def test_invalid_url_returns_missing_config(self):
        self._write_env(
            'SUPABASE_URL=http://insecure.example.com\n'
            'SUPABASE_ACCESS_TOKEN=' + USAGE_MGMT_TOKEN + '\n'
        )
        code, out, err = self._run(['supabase-usage'], api=FakeSupabaseAPI())
        self.assertEqual(subject.EXIT_MISSING_CONFIG, code)
        self.assertIn('SUPABASE_URL', err)
        self.assertNotIn(USAGE_MGMT_TOKEN, err)

    def test_http_error_message_is_sanitized(self):
        self._management_env()

        def failing(request, timeout=None):
            headers = {'Authorization': 'Bearer ' + USAGE_MGMT_TOKEN}
            raise urllib.error.HTTPError(request.full_url, 401, 'Unauthorized', headers, None)

        code, out, err = self._run(['supabase-usage', '--source', 'management'], api=failing)
        self.assertEqual(subject.EXIT_MISSING_CONFIG, code)
        self.assertIn('401', err)
        self.assertNotIn(USAGE_MGMT_TOKEN, out + err)
        self.assertNotIn('Bearer', out + err)

    def test_unsafe_table_name_is_rejected_before_sql_concatenation(self):
        self._management_env()
        api = self._default_api(
            tables=[
                {
                    'table_name': 'users; DROP TABLE auth.users',
                    'has_user_id': True,
                    'total_bytes': 1024,
                }
            ]
        )
        code, out, err = self._run(['supabase-usage'], api=api)
        self.assertEqual(subject.EXIT_FAILED, code)
        self.assertIn('非法表名', err)
        queries = [
            json.loads(request.data.decode('utf-8'))['query']
            for request in api.requests
            if request.data
        ]
        self.assertFalse(any('DROP TABLE' in query for query in queries))
        self.assertNotIn(USAGE_MGMT_TOKEN, out + err)

    def test_client_define_whitelist_is_unchanged(self):
        self.assertEqual(
            ('SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY'), subject.CLIENT_DEFINE_KEYS
        )
        self.assertIs(subject.handle_supabase_usage, subject.HANDLERS['supabase-usage'])
        self.assertIs(subject.handle_supabase_usage, subject.HANDLERS['usage'])
        self.assertIs(subject.handle_supabase_usage, subject.HANDLERS['quota'])

    def test_usage_credentials_never_reach_the_defines_file(self):
        self._write_env(
            'SUPABASE_URL=https://project-ref.supabase.co\n'
            'SUPABASE_PUBLISHABLE_KEY=sb_publishable_demo\n'
            'SUPABASE_ACCESS_TOKEN=' + USAGE_MGMT_TOKEN + '\n'
            'SUPABASE_SECRET_KEY=' + USAGE_OPAQUE_KEY + '\n'
        )
        runner = FakeRunner()
        out, err = io.StringIO(), io.StringIO()
        code = subject.main(
            ['build', '--target', 'apk', '--release', '--dry-run'],
            runner=runner,
            environ={},
            out=out,
            err=err,
            repo=self.repo,
        )
        self.assertEqual(subject.EXIT_OK, code, err.getvalue())
        self.assertNotIn(USAGE_MGMT_TOKEN, out.getvalue() + err.getvalue())
        self.assertNotIn(USAGE_OPAQUE_KEY, out.getvalue() + err.getvalue())
        self.assertIn('SUPABASE_ACCESS_TOKEN', out.getvalue())


if __name__ == '__main__':
    unittest.main()
