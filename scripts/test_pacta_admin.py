#!/usr/bin/env python3
"""Fully offline tests for scripts/pacta_admin.py.

Every HTTP interaction goes through an injected fake transport, so no Supabase
project, network, TTY or real administrator credential is involved. The fake
never sees a service-role key: the module is only allowed to read the public URL
and publishable/anon key.
"""

import base64
import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name('pacta_admin.py')


def load_module():
    spec = importlib.util.spec_from_file_location('pacta_admin', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules['pacta_admin'] = module
    spec.loader.exec_module(module)
    return module


MODULE = load_module()

ADMIN_ID = '11111111-1111-4111-8111-111111111111'
TARGET_ID = '22222222-2222-4222-8222-222222222222'
OTHER_ID = '33333333-3333-4333-8333-333333333333'
ADMIN_EMAIL = 'admin@example.com'
TARGET_EMAIL = 'person@example.com'
PUBLIC_KEY = 'sb_publishable_public_key'
SERVICE_SECRET = 'service-role-secret-value-that-must-never-be-used'


# --------------------------------------------------------------------------
# Fixtures
# --------------------------------------------------------------------------


def json_response(payload, status=200):
    return MODULE.HttpResponse(
        status=status,
        body=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
    )


def session_payload(
    access='access-token-value',
    refresh='refresh-token-value',
    user_id=ADMIN_ID,
    email=ADMIN_EMAIL,
    expires_in=3600,
):
    return {
        'access_token': access,
        'refresh_token': refresh,
        'expires_in': expires_in,
        'user': {'id': user_id, 'email': email},
    }


def user_row(
    user_id=TARGET_ID,
    email=TARGET_EMAIL,
    *,
    is_suspended=False,
    suspended_at=None,
    restored_at=None,
    purge_eligible_at=None,
    is_eligible_for_purge=False,
    created_at='2026-01-01T00:00:00+00:00',
):
    return {
        'user_id': user_id,
        'email': email,
        'created_at': created_at,
        'is_suspended': is_suspended,
        'suspended_at': suspended_at,
        'restored_at': restored_at,
        'purge_eligible_at': purge_eligible_at,
        'is_eligible_for_purge': is_eligible_for_purge,
    }


def make_config(**overrides):
    values = {
        'url': 'https://project.supabase.co',
        'api_key': PUBLIC_KEY,
        'api_key_name': 'SUPABASE_PUBLISHABLE_KEY',
        'source': '测试',
        'ignored_secret_keys': (),
    }
    values.update(overrides)
    return MODULE.SupabaseConfig(**values)


class Call:
    def __init__(self, method, url, headers, body):
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body

    @property
    def json(self):
        if not self.body:
            return None
        return json.loads(self.body.decode('utf-8'))


class FakeTransport:
    def __init__(self, responses=None):
        self.responses = list(responses or [])
        self.calls = []

    def request(self, method, url, headers=None, body=None):
        self.calls.append(Call(method, url, dict(headers or {}), body))
        if not self.responses:
            raise AssertionError(f'unexpected HTTP call: {method} {url}')
        response = self.responses.pop(0)
        if isinstance(response, BaseException):
            raise response
        return response

    @property
    def urls(self):
        return [call.url for call in self.calls]


class RecordingStream:
    def __init__(self, fail=False):
        self.calls = []
        self.fail = fail

    def reconfigure(self, **kwargs):
        if self.fail:
            raise ValueError('detached stream')
        self.calls.append(kwargs)


class PlainStream:
    def write(self, text):
        return len(text)

    def flush(self):
        pass


class AdminToolTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env_file = self.root / '.env'
        self.env_file.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            f'SUPABASE_PUBLISHABLE_KEY={PUBLIC_KEY}\n',
            encoding='utf-8',
        )
        self.out = io.StringIO()
        self.err = io.StringIO()
        # Never reconfigure the real test-runner streams from main().
        patcher = mock.patch.object(MODULE, 'configure_console', lambda: None)
        patcher.start()
        self.addCleanup(patcher.stop)

    def console(self, inputs=None, passwords=None):
        script = list(inputs or [])
        secrets = list(passwords or [])
        prompts = []

        def input_fn(label):
            prompts.append(label)
            if not script:
                raise EOFError
            return script.pop(0)

        def getpass_fn(label):
            prompts.append(label)
            if not secrets:
                raise AssertionError('no password scripted')
            return secrets.pop(0)

        console = MODULE.ConsoleIO(self.out, self.err, input_fn, getpass_fn)
        return console, prompts

    def client(self, responses, *, clock=None):
        transport = FakeTransport(responses)
        client = MODULE.SupabaseAdminClient(
            make_config(),
            transport,
            clock=clock or (lambda: 1000.0),
        )
        return client, transport

    def logged_in(self, responses, *, clock=None):
        transport = FakeTransport([json_response(session_payload())] + list(responses))
        client = MODULE.SupabaseAdminClient(
            make_config(),
            transport,
            clock=clock or (lambda: 1000.0),
        )
        client.login(ADMIN_EMAIL, 'admin-password')
        return client, transport

    def run_main(self, argv, responses, *, environ=None, inputs=None, passwords=None):
        transport = FakeTransport(responses)
        console_inputs = list(inputs or [])
        console_passwords = list(passwords if passwords is not None else ['admin-password'])
        prompts = []

        def input_fn(label):
            prompts.append(label)
            if not console_inputs:
                raise EOFError
            return console_inputs.pop(0)

        def getpass_fn(label):
            prompts.append(label)
            if not console_passwords:
                raise AssertionError('no password scripted')
            return console_passwords.pop(0)

        code = MODULE.main(
            argv,
            transport=transport,
            environ={} if environ is None else environ,
            out=self.out,
            err=self.err,
            input_fn=input_fn,
            getpass_fn=getpass_fn,
            clock=lambda: 1000.0,
        )
        return code, transport, prompts


# --------------------------------------------------------------------------
# Console, dotenv and configuration
# --------------------------------------------------------------------------


class ConfigureConsoleTest(unittest.TestCase):
    def test_reconfigures_stdout_and_stderr_to_utf8(self):
        stdout = RecordingStream()
        stderr = RecordingStream()
        with mock.patch.object(MODULE.sys, 'stdout', stdout), mock.patch.object(
            MODULE.sys, 'stderr', stderr
        ):
            MODULE.configure_console()
        expected = {'encoding': 'utf-8', 'errors': 'replace'}
        self.assertEqual(stdout.calls, [expected])
        self.assertEqual(stderr.calls, [expected])

    def test_later_streams_are_ignored_after_one_failure(self):
        stdout = RecordingStream(fail=True)
        stderr = RecordingStream()
        with mock.patch.object(MODULE.sys, 'stdout', stdout), mock.patch.object(
            MODULE.sys, 'stderr', stderr
        ):
            MODULE.configure_console()
        self.assertEqual(stderr.calls, [{'encoding': 'utf-8', 'errors': 'replace'}])

    def test_streams_without_reconfigure_are_tolerated(self):
        stdout = PlainStream()
        stderr = PlainStream()
        with mock.patch.object(MODULE.sys, 'stdout', stdout), mock.patch.object(
            MODULE.sys, 'stderr', stderr
        ):
            MODULE.configure_console()


class EnvFileTest(AdminToolTestCase):
    def test_reads_quotes_exports_and_inline_hashes(self):
        path = self.root / 'sample.env'
        path.write_text(
            '# comment\n'
            '\n'
            'SUPABASE_URL="https://project.supabase.co"\n'
            "SUPABASE_PUBLISHABLE_KEY='sb_publishable_key'\n"
            'export EXTRA="value with # hash"\n'
            'EQUALS="a=b"\n'
            'COMMENTED=https://project.supabase.co # trailing note\n'
            'HASH=abc#def\n'
            'QUOTED_COMMENT="kept" # ignored\n'
            'NO_EQUALS_LINE\n',
            encoding='utf-8-sig',
        )
        values = MODULE.read_env_file(path)
        self.assertEqual(values['SUPABASE_URL'], 'https://project.supabase.co')
        self.assertEqual(values['SUPABASE_PUBLISHABLE_KEY'], 'sb_publishable_key')
        self.assertEqual(values['EXTRA'], 'value with # hash')
        self.assertEqual(values['EQUALS'], 'a=b')
        self.assertEqual(values['COMMENTED'], 'https://project.supabase.co')
        self.assertEqual(values['HASH'], 'abc#def')
        self.assertEqual(values['QUOTED_COMMENT'], 'kept')
        self.assertNotIn('NO_EQUALS_LINE', values)

    def test_double_quoted_escapes_are_decoded(self):
        path = self.root / 'escapes.env'
        path.write_text('VALUE="line1\\nline2\\t\\"quoted\\""\n', encoding='utf-8')
        self.assertEqual(MODULE.read_env_file(path)['VALUE'], 'line1\nline2\t"quoted"')

    def test_missing_file_raises_config_error(self):
        with self.assertRaises(MODULE.ConfigError):
            MODULE.read_env_file(self.root / 'missing.env')


class LoadConfigTest(AdminToolTestCase):
    def test_environment_overrides_file(self):
        config = MODULE.load_config(
            self.env_file,
            {
                'SUPABASE_URL': 'https://env.supabase.co',
                'SUPABASE_PUBLISHABLE_KEY': 'env-public-key',
            },
        )
        self.assertEqual(config.url, 'https://env.supabase.co')
        self.assertEqual(config.api_key, 'env-public-key')
        self.assertEqual(config.api_key_name, 'SUPABASE_PUBLISHABLE_KEY')

    def test_environment_anon_key_beats_file_publishable_key(self):
        config = MODULE.load_config(
            self.env_file,
            {'SUPABASE_ANON_KEY': 'env-legacy-anon'},
        )
        self.assertEqual(config.api_key, 'env-legacy-anon')
        self.assertEqual(config.api_key_name, 'SUPABASE_ANON_KEY')

    def test_dotenv_fills_missing_values(self):
        config = MODULE.load_config(self.env_file, {'SUPABASE_URL': 'https://env.supabase.co'})
        self.assertEqual(config.url, 'https://env.supabase.co')
        self.assertEqual(config.api_key, PUBLIC_KEY)

    def test_anon_key_is_accepted(self):
        path = self.root / 'anon.env'
        path.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            'SUPABASE_ANON_KEY=legacy-anon-key\n',
            encoding='utf-8',
        )
        config = MODULE.load_config(path, {})
        self.assertEqual(config.api_key, 'legacy-anon-key')
        self.assertEqual(config.api_key_name, 'SUPABASE_ANON_KEY')

    def test_default_env_missing_falls_back_to_environment(self):
        config = MODULE.load_config(
            None,
            {'SUPABASE_URL': 'https://env.supabase.co', 'SUPABASE_PUBLISHABLE_KEY': 'env-key'},
            default_env_file=self.root / 'missing.env',
        )
        self.assertEqual(config.url, 'https://env.supabase.co')
        self.assertEqual(config.source, '环境变量')

    def test_explicit_missing_env_file_is_an_error(self):
        with self.assertRaises(MODULE.ConfigError):
            MODULE.load_config(self.root / 'missing.env', {})

    def test_missing_url_and_key_gives_chinese_error(self):
        path = self.root / 'empty.env'
        path.write_text('# nothing here\n', encoding='utf-8')
        with self.assertRaises(MODULE.ConfigError) as caught:
            MODULE.load_config(path, {})
        message = str(caught.exception)
        self.assertIn('SUPABASE_URL', message)
        self.assertIn('SUPABASE_PUBLISHABLE_KEY', message)
        self.assertIn('service_role', message)
        self.assertEqual(caught.exception.exit_code, 2)

    def test_service_role_key_is_ignored_not_used(self):
        path = self.root / 'secret.env'
        path.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            f'SUPABASE_PUBLISHABLE_KEY={PUBLIC_KEY}\n'
            f'SUPABASE_SERVICE_ROLE_KEY={SERVICE_SECRET}\n',
            encoding='utf-8',
        )
        config = MODULE.load_config(path, {})
        self.assertEqual(config.api_key, PUBLIC_KEY)
        self.assertNotEqual(config.api_key, SERVICE_SECRET)
        self.assertIn('SUPABASE_SERVICE_ROLE_KEY', config.ignored_secret_keys)

    def test_service_role_key_never_fills_missing_publishable_key(self):
        path = self.root / 'secret-only.env'
        path.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            f'SUPABASE_SERVICE_ROLE_KEY={SERVICE_SECRET}\n',
            encoding='utf-8',
        )
        with self.assertRaises(MODULE.ConfigError):
            MODULE.load_config(path, {})

    def test_sb_secret_key_in_publishable_slot_is_rejected(self):
        path = self.root / 'secret-slot.env'
        path.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            'SUPABASE_PUBLISHABLE_KEY=sb_secret_forbidden\n',
            encoding='utf-8',
        )
        with self.assertRaises(MODULE.ConfigError):
            MODULE.load_config(path, {})

    def test_service_role_jwt_in_publishable_slot_is_rejected(self):
        payload = base64.urlsafe_b64encode(
            json.dumps({'role': 'service_role'}).encode('utf-8')
        ).decode('ascii').rstrip('=')
        token = f'e30.{payload}.signature'
        path = self.root / 'jwt.env'
        path.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            f'SUPABASE_PUBLISHABLE_KEY={token}\n',
            encoding='utf-8',
        )
        with self.assertRaises(MODULE.ConfigError):
            MODULE.load_config(path, {})

    def test_anon_jwt_in_publishable_slot_is_accepted(self):
        payload = base64.urlsafe_b64encode(
            json.dumps({'role': 'anon'}).encode('utf-8')
        ).decode('ascii').rstrip('=')
        token = f'e30.{payload}.signature'
        path = self.root / 'anon-jwt.env'
        path.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            f'SUPABASE_PUBLISHABLE_KEY={token}\n',
            encoding='utf-8',
        )
        self.assertEqual(MODULE.load_config(path, {}).api_key, token)

    def test_trailing_slash_is_stripped(self):
        path = self.root / 'slash.env'
        path.write_text(
            'SUPABASE_URL="https://project.supabase.co/"\n'
            f'SUPABASE_PUBLISHABLE_KEY={PUBLIC_KEY}\n',
            encoding='utf-8',
        )
        self.assertEqual(MODULE.load_config(path, {}).url, 'https://project.supabase.co')

    def test_non_http_url_is_rejected(self):
        path = self.root / 'scheme.env'
        path.write_text(
            'SUPABASE_URL=ftp://project.supabase.co\n'
            f'SUPABASE_PUBLISHABLE_KEY={PUBLIC_KEY}\n',
            encoding='utf-8',
        )
        with self.assertRaises(MODULE.ConfigError):
            MODULE.load_config(path, {})


# --------------------------------------------------------------------------
# Formatting and row models
# --------------------------------------------------------------------------


class FormattingTest(unittest.TestCase):
    def test_timestamp_parsing_and_formatting(self):
        parsed = MODULE.parse_timestamp('2026-01-02T03:04:05Z')
        self.assertEqual(parsed, datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc))
        self.assertEqual(MODULE.format_timestamp(parsed, timezone.utc), '2026-01-02 03:04')
        self.assertEqual(MODULE.format_timestamp(None), '—')
        naive = MODULE.parse_timestamp('2026-01-02T03:04:05')
        self.assertEqual(naive.tzinfo, timezone.utc)

    def test_table_aligns_wide_characters(self):
        lines = MODULE.format_table(('编号', '状态'), [[1, '正常'], [2, '已停用(剩3天可删)']])
        self.assertIn('编号', lines[0])
        self.assertIn('已停用', lines[3])
        header_prefix = lines[0][: lines[0].index('状态')]
        row_prefix = lines[2][: lines[2].index('正常')]
        self.assertEqual(
            MODULE._display_width(header_prefix), MODULE._display_width(row_prefix)
        )

    def test_active_user_status(self):
        user = MODULE.UserLifecycle(user_id=TARGET_ID, email=TARGET_EMAIL)
        self.assertEqual(user.status_label(), '正常')

    def test_suspended_user_remaining_days_round_up(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        user = MODULE.UserLifecycle(
            user_id=TARGET_ID,
            email=TARGET_EMAIL,
            is_suspended=True,
            purge_eligible_at=now.replace(day=13, hour=12),
        )
        self.assertEqual(user.status_label(now), '已停用(剩13天可删)')

    def test_eligible_user_status(self):
        user = MODULE.UserLifecycle(
            user_id=TARGET_ID,
            email=TARGET_EMAIL,
            is_suspended=True,
            is_eligible_for_purge=True,
        )
        self.assertEqual(user.status_label(), '已停用(已满30天可删)')

    def test_suspended_without_window_falls_back_to_30_days(self):
        user = MODULE.UserLifecycle(user_id=TARGET_ID, email=TARGET_EMAIL, is_suspended=True)
        self.assertEqual(user.status_label(), '已停用(剩30天可删)')

    def test_eligibility_status_precedence(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        self.assertEqual(MODULE.Eligibility('a@b.c', 'email').status_label(), '待使用')
        self.assertEqual(
            MODULE.Eligibility('a@b.c', 'email', revoked_at=now).status_label(),
            '已撤销',
        )
        self.assertEqual(
            MODULE.Eligibility('a@b.c', 'email', used_at=now, revoked_at=now).status_label(),
            '已使用',
        )
        self.assertEqual(
            MODULE.Eligibility(
                'a@b.c', 'email', used_at=now, revoked_at=now, purge_completed_at=now
            ).status_label(),
            '已清除可重发',
        )

    def test_summaries_count_states(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        users = [
            MODULE.UserLifecycle(user_id='a', email='a@b.c'),
            MODULE.UserLifecycle(
                user_id='b', email='b@b.c', is_suspended=True, is_eligible_for_purge=True
            ),
        ]
        self.assertIn('共 2 个账号', MODULE.summarize_users(users))
        rows = [
            MODULE.Eligibility('a@b.c', 'email'),
            MODULE.Eligibility('b@b.c', 'email', revoked_at=now),
        ]
        self.assertIn('待使用 1', MODULE.summarize_eligibilities(rows))


# --------------------------------------------------------------------------
# HTTP transport
# --------------------------------------------------------------------------


class HttpTransportTest(unittest.TestCase):
    def test_successful_response_is_returned(self):
        response = mock.Mock()
        response.status = 200
        response.headers = {'Content-Type': 'application/json'}
        response.read.return_value = b'{"ok":true}'
        response.close = mock.Mock()
        with mock.patch('urllib.request.urlopen', return_value=response) as urlopen:
            result = MODULE.HttpTransport().request(
                'post', 'https://example.test/x', {'apikey': 'k'}, b'{}'
            )
        self.assertEqual(result.status, 200)
        self.assertEqual(result.body, b'{"ok":true}')
        self.assertEqual(urlopen.call_args.args[0].get_method(), 'POST')
        response.close.assert_called_once()

    def test_http_error_is_returned_as_response(self):
        error = urllib.error.HTTPError(
            'https://example.test/x',
            409,
            'conflict',
            {'Content-Type': 'application/json'},
            io.BytesIO(b'{"error":"conflict"}'),
        )
        with mock.patch('urllib.request.urlopen', side_effect=error):
            result = MODULE.HttpTransport().request('POST', 'https://example.test/x', body=b'{}')
        self.assertEqual(result.status, 409)
        self.assertEqual(result.body, b'{"error":"conflict"}')

    def test_value_error_becomes_transport_error(self):
        with mock.patch('urllib.request.urlopen', side_effect=ValueError('unknown url type')):
            with self.assertRaises(MODULE.TransportError) as caught:
                MODULE.HttpTransport().request('GET', 'https://example.test/x')
        self.assertIn('unknown url type', str(caught.exception))

    def test_url_error_becomes_transport_error(self):
        with mock.patch(
            'urllib.request.urlopen', side_effect=urllib.error.URLError('dns failure')
        ):
            with self.assertRaises(MODULE.TransportError) as caught:
                MODULE.HttpTransport().request('GET', 'https://example.test/x')
        self.assertIn('dns failure', str(caught.exception))


# --------------------------------------------------------------------------
# Authentication
# --------------------------------------------------------------------------


class LoginTest(AdminToolTestCase):
    def test_login_posts_password_grant_with_apikey_only(self):
        transport = FakeTransport([json_response(session_payload())])
        client = MODULE.SupabaseAdminClient(make_config(), transport)
        client.login(' ADMIN@Example.com ', 'admin-password')
        call = transport.calls[0]
        self.assertEqual(call.method, 'POST')
        self.assertEqual(call.url, 'https://project.supabase.co/auth/v1/token?grant_type=password')
        self.assertEqual(call.headers['apikey'], PUBLIC_KEY)
        self.assertNotIn('Authorization', call.headers)
        self.assertEqual(call.json, {'email': ADMIN_EMAIL, 'password': 'admin-password'})
        self.assertEqual(client.email, ADMIN_EMAIL)
        self.assertEqual(client.user_id, ADMIN_ID)

    def test_login_rejects_invalid_credentials(self):
        transport = FakeTransport(
            [json_response({'error': 'invalid_grant', 'error_description': 'Invalid login'}, 400)]
        )
        client = MODULE.SupabaseAdminClient(make_config(), transport)
        with self.assertRaises(MODULE.AuthError) as caught:
            client.login(ADMIN_EMAIL, 'wrong')
        self.assertIn('邮箱或密码不正确', str(caught.exception))
        self.assertIsNone(client.session)

    def test_unconfirmed_email_is_explained(self):
        transport = FakeTransport(
            [
                json_response(
                    {
                        'error': 'email_not_confirmed',
                        'error_description': 'Email not confirmed',
                    },
                    400,
                )
            ]
        )
        client = MODULE.SupabaseAdminClient(make_config(), transport)
        with self.assertRaises(MODULE.AuthError) as caught:
            client.login(ADMIN_EMAIL, 'pw')
        self.assertIn('尚未确认邮箱', str(caught.exception))

    def test_login_requires_tokens_and_user(self):
        for payload in (
            {'refresh_token': 'r', 'user': {'id': ADMIN_ID}},
            {'access_token': 'a', 'user': {'id': ADMIN_ID}},
            {'access_token': 'a', 'refresh_token': 'r'},
        ):
            transport = FakeTransport([json_response(payload)])
            client = MODULE.SupabaseAdminClient(make_config(), transport)
            with self.assertRaises(MODULE.AuthError):
                client.login(ADMIN_EMAIL, 'pw')

    def test_expires_in_sets_absolute_expiry(self):
        now = 1000.0
        transport = FakeTransport([json_response(session_payload(expires_in=90))])
        client = MODULE.SupabaseAdminClient(make_config(), transport, clock=lambda: now)
        session = client.login(ADMIN_EMAIL, 'pw')
        self.assertEqual(session.expires_at, 1090.0)

    def test_expired_session_refreshes_before_request(self):
        clock = {'now': 1000.0}
        transport = FakeTransport(
            [
                json_response(session_payload(access='access-old', refresh='refresh-old')),
                json_response(session_payload(access='access-new', refresh='refresh-new')),
                json_response([user_row()]),
            ]
        )
        client = MODULE.SupabaseAdminClient(make_config(), transport, clock=lambda: clock['now'])
        client.login(ADMIN_EMAIL, 'pw')
        clock['now'] = 5000.0  # beyond expires_at 4600 minus the 30s skew
        client.list_users()
        self.assertIn('grant_type=refresh_token', transport.urls[1])
        self.assertEqual(transport.calls[1].json, {'refresh_token': 'refresh-old'})
        self.assertEqual(transport.calls[2].headers['Authorization'], 'Bearer access-new')

    def test_401_refreshes_once_and_retries_the_same_request(self):
        transport = FakeTransport(
            [
                json_response(session_payload(access='access-old', refresh='refresh-old')),
                json_response({'message': 'jwt expired'}, 401),
                json_response(session_payload(access='access-new', refresh='refresh-new')),
                json_response([user_row()]),
            ]
        )
        client = MODULE.SupabaseAdminClient(make_config(), transport, clock=lambda: 1000.0)
        client.login(ADMIN_EMAIL, 'pw')
        users = client.list_users()
        self.assertEqual(len(users), 1)
        self.assertEqual(transport.calls[1].headers['Authorization'], 'Bearer access-old')
        self.assertEqual(transport.calls[3].headers['Authorization'], 'Bearer access-new')
        self.assertEqual(transport.calls[1].body, transport.calls[3].body)

    def test_second_401_after_refresh_is_auth_error(self):
        transport = FakeTransport(
            [
                json_response(session_payload()),
                json_response({'message': 'expired'}, 401),
                json_response(session_payload(access='access-new')),
                json_response({'message': 'still expired'}, 401),
            ]
        )
        client = MODULE.SupabaseAdminClient(make_config(), transport)
        client.login(ADMIN_EMAIL, 'pw')
        with self.assertRaises(MODULE.AuthError):
            client.list_users()
        self.assertEqual(len(transport.calls), 4)

    def test_refresh_failure_is_auth_error_and_not_retried(self):
        transport = FakeTransport(
            [
                json_response(session_payload()),
                json_response({'message': 'expired'}, 401),
                json_response({'error': 'invalid_grant'}, 400),
            ]
        )
        client = MODULE.SupabaseAdminClient(make_config(), transport)
        client.login(ADMIN_EMAIL, 'pw')
        with self.assertRaises(MODULE.AuthError) as caught:
            client.list_users()
        self.assertIn('登录状态已过期', str(caught.exception))
        self.assertEqual(len(transport.calls), 3)

    def test_error_text_never_contains_tokens(self):
        transport = FakeTransport(
            [
                json_response(
                    session_payload(access='access-token-secret', refresh='refresh-token-secret')
                ),
                json_response(
                    {
                        'code': 'XX000',
                        'message': 'failed for access-token-secret and refresh-token-secret',
                    },
                    500,
                ),
            ]
        )
        client = MODULE.SupabaseAdminClient(make_config(), transport)
        client.login(ADMIN_EMAIL, 'pw')
        with self.assertRaises(MODULE.ApiError) as caught:
            client.list_users()
        message = str(caught.exception)
        self.assertNotIn('access-token-secret', message)
        self.assertNotIn('refresh-token-secret', message)
        self.assertNotIn(PUBLIC_KEY, message)
        self.assertIn('***', message)


class AdminGuardTest(AdminToolTestCase):
    def test_verify_admin_queries_exact_user(self):
        client, transport = self.logged_in([json_response([{'user_id': ADMIN_ID}])])
        self.assertTrue(client.verify_admin())
        self.assertEqual(
            transport.calls[-1].url,
            f'https://project.supabase.co/rest/v1/app_admins'
            f'?select=user_id&user_id=eq.{ADMIN_ID}',
        )

    def test_non_admin_is_rejected(self):
        client, _ = self.logged_in([json_response([])])
        with self.assertRaises(MODULE.ForbiddenError) as caught:
            client.verify_admin()
        self.assertIn('不是 Pacta 管理员', str(caught.exception))
        self.assertEqual(caught.exception.exit_code, 3)

    def test_forbidden_status_is_rejected(self):
        client, _ = self.logged_in([json_response({'message': 'denied'}, 403)])
        with self.assertRaises(MODULE.ForbiddenError):
            client.verify_admin()


# --------------------------------------------------------------------------
# Users and eligibilities
# --------------------------------------------------------------------------


class UserLifecycleCommandTest(AdminToolTestCase):
    def test_list_users_parses_rows(self):
        client, transport = self.logged_in(
            [
                json_response(
                    [
                        user_row(),
                        user_row(
                            user_id=OTHER_ID,
                            email='other@example.com',
                            is_suspended=True,
                            suspended_at='2026-01-01T00:00:00+00:00',
                            purge_eligible_at='2026-01-31T00:00:00+00:00',
                            is_eligible_for_purge=True,
                        ),
                    ]
                )
            ]
        )
        users = client.list_users()
        self.assertEqual(len(users), 2)
        self.assertEqual(users[0].status_label(datetime(2026, 1, 2, tzinfo=timezone.utc)), '正常')
        self.assertEqual(
            users[1].status_label(datetime(2026, 1, 2, tzinfo=timezone.utc)),
            '已停用(已满30天可删)',
        )
        self.assertEqual(transport.calls[-1].method, 'POST')
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/rest/v1/rpc/admin_list_user_lifecycles',
        )

    def test_show_users_prints_table_and_summary(self):
        client, _ = self.logged_in([json_response([user_row()])])
        console, _ = self.console()
        MODULE.show_users(client, console)
        output = self.out.getvalue()
        self.assertIn('编号', output)
        self.assertIn(TARGET_EMAIL, output)
        self.assertIn(TARGET_ID, output)
        self.assertIn('共 1 个账号', output)
        self.assertIn('python scripts/pacta_admin.py eligibilities', output)

    def test_resolve_user_by_email_is_case_insensitive(self):
        client, _ = self.logged_in([json_response([user_row()])])
        user = client.resolve_user('  PERSON@EXAMPLE.COM ')
        self.assertEqual(user.user_id, TARGET_ID)

    def test_resolve_user_by_uuid(self):
        client, _ = self.logged_in([json_response([user_row()])])
        user = client.resolve_user(TARGET_ID.upper())
        self.assertEqual(user.email, TARGET_EMAIL)

    def test_resolve_user_reports_unknown_email(self):
        client, _ = self.logged_in([json_response([user_row()])])
        with self.assertRaises(MODULE.AdminToolError) as caught:
            client.resolve_user('nobody@example.com')
        self.assertIn('找不到邮箱', str(caught.exception))

    def test_resolve_user_reports_unknown_uuid(self):
        client, _ = self.logged_in([json_response([user_row()])])
        with self.assertRaises(MODULE.AdminToolError) as caught:
            client.resolve_user(OTHER_ID)
        self.assertIn('找不到 UUID', str(caught.exception))


class EligibilityCommandTest(AdminToolTestCase):
    def row(self, **overrides):
        values = {
            'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'identifier': TARGET_EMAIL,
            'identifier_type': 'email',
            'created_at': '2026-01-01T00:00:00+00:00',
            'used_at': None,
            'used_user_id': None,
            'revoked_at': None,
            'purge_completed_at': None,
        }
        values.update(overrides)
        return values

    def test_list_eligibilities_uses_expected_query(self):
        client, transport = self.logged_in([json_response([self.row()])])
        rows = client.list_eligibilities()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].status_label(), '待使用')
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co'
            '/rest/v1/registration_eligibility'
            '?select=id,identifier,identifier_type,created_at,used_at,used_user_id,revoked_at,purge_completed_at'
            '&order=created_at.desc',
        )
        self.assertEqual(transport.calls[-1].method, 'GET')

    def test_list_eligibilities_covers_all_statuses(self):
        client, _ = self.logged_in(
            [
                json_response(
                    [
                        self.row(),
                        self.row(
                            identifier='used@example.com',
                            used_at='2026-01-02T00:00:00+00:00',
                            used_user_id=TARGET_ID,
                        ),
                        self.row(
                            identifier='revoked@example.com',
                            revoked_at='2026-01-03T00:00:00+00:00',
                        ),
                        self.row(
                            identifier='purged@example.com',
                            purge_completed_at='2026-01-04T00:00:00+00:00',
                        ),
                    ]
                )
            ]
        )
        self.assertEqual(
            [row.status_label() for row in client.list_eligibilities()],
            ['待使用', '已使用', '已撤销', '已清除可重发'],
        )

    def test_show_eligibilities_prints_summary(self):
        client, _ = self.logged_in([json_response([self.row()])])
        console, _ = self.console()
        MODULE.show_eligibilities(client, console)
        output = self.out.getvalue()
        self.assertIn('邮箱/标识', output)
        self.assertIn('待使用 1', output)

    def test_grant_lowercases_and_posts_rpc(self):
        client, transport = self.logged_in(
            [json_response(self.row(identifier=TARGET_EMAIL))]
        )
        record = client.grant_eligibility(' Person@Example.com ')
        self.assertEqual(record.identifier, TARGET_EMAIL)
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/rest/v1/rpc/admin_grant_registration_eligibility',
        )
        self.assertEqual(
            transport.calls[-1].json,
            {'p_identifier': TARGET_EMAIL, 'p_identifier_type': 'email'},
        )

    def test_grant_rejects_invalid_email_without_http(self):
        client, transport = self.logged_in([])
        with self.assertRaises(MODULE.AdminToolError):
            client.grant_eligibility('not-an-email')
        self.assertEqual(len(transport.calls), 1)  # login only

    def test_command_grant_prints_status(self):
        client, _ = self.logged_in([json_response(self.row())])
        console, _ = self.console()
        MODULE.command_grant(client, console, TARGET_EMAIL)
        self.assertIn('已发放注册资格', self.out.getvalue())

    def test_revoke_true_and_false(self):
        client, transport = self.logged_in([json_response(True), json_response(False)])
        self.assertTrue(client.revoke_eligibility(TARGET_EMAIL))
        self.assertFalse(client.revoke_eligibility(TARGET_EMAIL))
        self.assertEqual(
            [call.json for call in transport.calls[1:]],
            [
                {'p_identifier': TARGET_EMAIL, 'p_identifier_type': 'email'},
                {'p_identifier': TARGET_EMAIL, 'p_identifier_type': 'email'},
            ],
        )

    def test_command_revoke_messages(self):
        client, _ = self.logged_in([json_response(True)])
        console, _ = self.console()
        MODULE.command_revoke(client, console, TARGET_EMAIL)
        self.assertIn('已撤销', self.out.getvalue())

        self.out = io.StringIO()
        client, _ = self.logged_in([json_response(False)])
        console, _ = self.console()
        MODULE.command_revoke(client, console, TARGET_EMAIL)
        self.assertIn('没有撤销任何资格', self.out.getvalue())


# --------------------------------------------------------------------------
# Suspend, restore, reset password
# --------------------------------------------------------------------------


class LifecycleCommandTest(AdminToolTestCase):
    def test_suspend_confirms_and_posts_rpc(self):
        client, transport = self.logged_in(
            [json_response([user_row()]), json_response(None, 204)]
        )
        console, prompts = self.console(inputs=['yes'])
        MODULE.command_suspend(client, console, TARGET_EMAIL)
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/rest/v1/rpc/admin_suspend_user',
        )
        self.assertEqual(transport.calls[-1].json, {'p_user_id': TARGET_ID})
        self.assertIn('确认停用', prompts[-1])
        self.assertIn('已停用', self.out.getvalue())

    def test_suspend_cancelled_does_not_call_rpc(self):
        client, transport = self.logged_in([json_response([user_row()])])
        console, _ = self.console(inputs=['no'])
        with self.assertRaises(MODULE.OperationCancelled):
            MODULE.command_suspend(client, console, TARGET_EMAIL)
        self.assertEqual(len(transport.calls), 2)  # login + list users

    def test_restore_confirms_and_posts_rpc(self):
        client, transport = self.logged_in(
            [
                json_response(
                    [
                        user_row(
                            is_suspended=True,
                            suspended_at='2026-01-01T00:00:00+00:00',
                        )
                    ]
                ),
                json_response(None, 204),
            ]
        )
        console, _ = self.console(inputs=['y'])
        MODULE.command_restore(client, console, TARGET_ID)
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/rest/v1/rpc/admin_restore_user',
        )
        self.assertEqual(transport.calls[-1].json, {'p_user_id': TARGET_ID})

    def test_reset_password_posts_edge_payload(self):
        client, transport = self.logged_in(
            [json_response([user_row()]), json_response({'status': 'password_reset'})]
        )
        console, prompts = self.console(
            inputs=['yes'], passwords=['new-password-1', 'new-password-1']
        )
        MODULE.command_reset_password(client, console, TARGET_EMAIL)
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/functions/v1/admin-reset-user-password',
        )
        self.assertEqual(
            transport.calls[-1].json,
            {
                'email': TARGET_EMAIL,
                'new_password': 'new-password-1',
                'manual_verification_confirmed': True,
            },
        )
        self.assertIn('新密码: ', prompts)
        self.assertIn('再次输入新密码: ', prompts)
        self.assertNotIn('new-password-1', self.out.getvalue())
        self.assertNotIn('new-password-1', self.err.getvalue())

    def test_reset_password_mismatch_stops_before_http(self):
        client, transport = self.logged_in([json_response([user_row()])])
        console, _ = self.console(inputs=[], passwords=['new-password-1', 'new-password-2'])
        with self.assertRaises(MODULE.AdminToolError) as caught:
            MODULE.command_reset_password(client, console, TARGET_EMAIL)
        self.assertIn('不一致', str(caught.exception))
        self.assertEqual(len(transport.calls), 2)

    def test_reset_password_length_bounds(self):
        client, transport = self.logged_in([json_response([user_row()])])
        console, _ = self.console(inputs=[], passwords=['short', 'short'])
        with self.assertRaises(MODULE.AdminToolError) as caught:
            MODULE.command_reset_password(client, console, TARGET_EMAIL)
        self.assertIn('8 至 256', str(caught.exception))
        self.assertEqual(len(transport.calls), 2)

    def test_reset_password_requires_manual_confirmation(self):
        client, transport = self.logged_in([json_response([user_row()])])
        console, _ = self.console(
            inputs=['no'], passwords=['new-password-1', 'new-password-1']
        )
        with self.assertRaises(MODULE.OperationCancelled):
            MODULE.command_reset_password(client, console, TARGET_EMAIL)
        self.assertEqual(len(transport.calls), 2)

    def test_reset_password_unknown_email(self):
        client, transport = self.logged_in([json_response([])])
        console, _ = self.console()
        with self.assertRaises(MODULE.AdminToolError) as caught:
            MODULE.command_reset_password(client, console, 'nobody@example.com')
        self.assertIn('找不到邮箱', str(caught.exception))
        self.assertEqual(len(transport.calls), 2)


# --------------------------------------------------------------------------
# Delete / purge
# --------------------------------------------------------------------------


class DeleteUserCommandTest(AdminToolTestCase):
    def eligible_user(self):
        return user_row(
            is_suspended=True,
            suspended_at='2026-01-01T00:00:00+00:00',
            purge_eligible_at='2026-01-31T00:00:00+00:00',
            is_eligible_for_purge=True,
        )

    def receipt(self, user_id=TARGET_ID):
        return {'user_id': user_id, 'status': 'completed', 'purged_at': '2026-11-22T00:00:00+00:00'}

    def test_immediate_delete_posts_payload_and_verifies_receipt(self):
        client, transport = self.logged_in(
            [
                json_response([self.eligible_user()]),
                json_response([]),  # not an administrator
                json_response(self.receipt()),
            ]
        )
        console, prompts = self.console(inputs=[TARGET_EMAIL])
        MODULE.command_delete_user(
            client, console, TARGET_EMAIL, immediate=True, allow_prompt=False
        )
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/functions/v1/admin-purge-user',
        )
        self.assertEqual(
            transport.calls[-1].json,
            {'user_id': TARGET_ID, 'immediate': True},
        )
        self.assertIn('已完成永久清除', self.out.getvalue())

    def test_eligible_delete_sends_immediate_false(self):
        client, transport = self.logged_in(
            [
                json_response([self.eligible_user()]),
                json_response([]),
                json_response(self.receipt()),
            ]
        )
        console, _ = self.console(inputs=[TARGET_EMAIL])
        MODULE.command_delete_user(
            client, console, TARGET_EMAIL, immediate=False, allow_prompt=False
        )
        self.assertEqual(transport.calls[-1].json, {'user_id': TARGET_ID, 'immediate': False})

    def test_typed_confirmation_mismatch_cancels_without_purge(self):
        client, transport = self.logged_in(
            [json_response([self.eligible_user()]), json_response([])]
        )
        console, _ = self.console(inputs=['wrong@example.com'])
        with self.assertRaises(MODULE.OperationCancelled) as caught:
            MODULE.command_delete_user(
                client, console, TARGET_EMAIL, immediate=True, allow_prompt=False
            )
        self.assertEqual(len(transport.calls), 3)  # login, list, admin check
        self.assertIn('不一致', str(caught.exception))

    def test_confirmation_is_case_insensitive_and_trimmed(self):
        client, _ = self.logged_in(
            [
                json_response([self.eligible_user()]),
                json_response([]),
                json_response(self.receipt()),
            ]
        )
        console, _ = self.console(inputs=['  PERSON@EXAMPLE.COM  '])
        MODULE.command_delete_user(
            client, console, TARGET_EMAIL, immediate=True, allow_prompt=False
        )
        self.assertIn('purged_at=', self.out.getvalue())

    def test_uuid_confirmation_when_target_has_no_email(self):
        row = dict(self.eligible_user())
        row['email'] = None
        client, transport = self.logged_in(
            [json_response([row]), json_response([]), json_response(self.receipt())]
        )
        console, prompts = self.console(inputs=[TARGET_ID])
        MODULE.command_delete_user(
            client, console, TARGET_ID, immediate=True, allow_prompt=False
        )
        self.assertIn('逐字输入目标UUID', prompts[-1])
        self.assertEqual(transport.calls[-1].json, {'user_id': TARGET_ID, 'immediate': True})

    def test_self_purge_is_rejected_locally(self):
        client, transport = self.logged_in(
            [json_response([user_row(user_id=ADMIN_ID, email=ADMIN_EMAIL)])]
        )
        console, _ = self.console()
        with self.assertRaises(MODULE.ForbiddenError) as caught:
            MODULE.command_delete_user(
                client, console, ADMIN_EMAIL, immediate=True, allow_prompt=False
            )
        self.assertIn('当前登录的管理员', str(caught.exception))
        self.assertEqual(len(transport.calls), 2)

    def test_other_administrator_is_rejected_locally(self):
        client, transport = self.logged_in(
            [json_response([self.eligible_user()]), json_response([{'user_id': TARGET_ID}])]
        )
        console, _ = self.console()
        with self.assertRaises(MODULE.ForbiddenError) as caught:
            MODULE.command_delete_user(
                client, console, TARGET_EMAIL, immediate=True, allow_prompt=False
            )
        self.assertIn('另一位管理员', str(caught.exception))
        self.assertEqual(len(transport.calls), 3)

    def test_not_eligible_without_flag_explains_immediate(self):
        row = user_row(
            is_suspended=True,
            suspended_at='2026-11-20T00:00:00+00:00',
            purge_eligible_at='2026-12-20T00:00:00+00:00',
            is_eligible_for_purge=False,
        )
        client, transport = self.logged_in([json_response([row]), json_response([])])
        console, _ = self.console()
        with self.assertRaises(MODULE.AdminToolError) as caught:
            MODULE.command_delete_user(
                client, console, TARGET_EMAIL, immediate=False, allow_prompt=False
            )
        self.assertIn('--immediate', str(caught.exception))
        self.assertEqual(len(transport.calls), 3)

    def test_not_suspended_without_flag_explains_suspension(self):
        client, transport = self.logged_in(
            [json_response([user_row()]), json_response([])]
        )
        console, _ = self.console()
        with self.assertRaises(MODULE.AdminToolError) as caught:
            MODULE.command_delete_user(
                client, console, TARGET_EMAIL, immediate=False, allow_prompt=False
            )
        self.assertIn('目标当前未停用', str(caught.exception))
        self.assertEqual(len(transport.calls), 3)

    def test_menu_prompts_immediate_for_not_eligible_target(self):
        row = user_row(
            is_suspended=True,
            suspended_at='2026-11-20T00:00:00+00:00',
            purge_eligible_at='2026-12-20T00:00:00+00:00',
            is_eligible_for_purge=False,
        )
        client, transport = self.logged_in(
            [json_response([row]), json_response([]), json_response(self.receipt())]
        )
        console, prompts = self.console(inputs=['yes', TARGET_EMAIL])
        MODULE.command_delete_user(
            client, console, TARGET_EMAIL, immediate=False, allow_prompt=True
        )
        self.assertIn('测试期立即清除', prompts[0])
        self.assertEqual(transport.calls[-1].json, {'user_id': TARGET_ID, 'immediate': True})

    def test_menu_declining_immediate_cancels(self):
        row = user_row(
            is_suspended=True,
            suspended_at='2026-11-20T00:00:00+00:00',
            purge_eligible_at='2026-12-20T00:00:00+00:00',
            is_eligible_for_purge=False,
        )
        client, transport = self.logged_in([json_response([row]), json_response([])])
        console, _ = self.console(inputs=[''])
        with self.assertRaises(MODULE.OperationCancelled):
            MODULE.command_delete_user(
                client, console, TARGET_EMAIL, immediate=False, allow_prompt=True
            )
        self.assertEqual(len(transport.calls), 3)

    def test_409_without_immediate_suggests_deployment_then_flag(self):
        client, _ = self.logged_in(
            [json_response({'error': '目标用户当前不能清除。'}, 409)]
        )
        with self.assertRaises(MODULE.ApiError) as caught:
            client.purge_user(TARGET_ID, immediate=False)
        message = str(caught.exception)
        self.assertIn('supabase db push', message)
        self.assertIn('--immediate', message)

    def test_409_with_immediate_suggests_deployment(self):
        client, _ = self.logged_in(
            [json_response({'error': '目标用户当前不能清除。'}, 409)]
        )
        with self.assertRaises(MODULE.ApiError) as caught:
            client.purge_user(TARGET_ID, immediate=True)
        self.assertIn('supabase functions deploy admin-purge-user', str(caught.exception))

    def test_edge_function_error_body_is_surfaced(self):
        client, _ = self.logged_in(
            [json_response({'error': '请求参数 immediate 必须为布尔值。'}, 400)]
        )
        with self.assertRaises(MODULE.ApiError) as caught:
            client.purge_user(TARGET_ID, immediate=True)
        self.assertIn('immediate 必须为布尔值', str(caught.exception))

    def test_missing_rpc_hint_mentions_db_push(self):
        client, _ = self.logged_in(
            [
                json_response(
                    {
                        'code': 'PGRST202',
                        'message': 'Could not find the function public.admin_list_user_lifecycles',
                    },
                    404,
                )
            ]
        )
        with self.assertRaises(MODULE.ApiError) as caught:
            client.list_users()
        self.assertIn('supabase db push', str(caught.exception))

    def test_incomplete_receipt_is_rejected(self):
        for payload in (
            {'user_id': OTHER_ID, 'status': 'completed', 'purged_at': '2026-01-01T00:00:00Z'},
            {'user_id': TARGET_ID, 'status': 'pending', 'purged_at': None},
            {'user_id': TARGET_ID, 'status': 'completed', 'purged_at': None},
            ['not-an-object'],
        ):
            client, _ = self.logged_in(
                [
                    json_response([self.eligible_user()]),
                    json_response([]),
                    json_response(payload),
                ]
            )
            with self.assertRaises(MODULE.ApiError):
                client.purge_user(TARGET_ID, immediate=True)


# --------------------------------------------------------------------------
# CLI entry point
# --------------------------------------------------------------------------


class MainTest(AdminToolTestCase):
    def default_responses(self):
        return [
            json_response(session_payload()),
            json_response([{'user_id': ADMIN_ID}]),
            json_response([user_row()]),
        ]

    def test_help_exits_zero(self):
        with contextlib.redirect_stdout(self.out):
            with self.assertRaises(SystemExit) as caught:
                MODULE.main(['--help'], transport=FakeTransport())
        self.assertEqual(caught.exception.code, 0)
        self.assertIn('delete-user', self.out.getvalue())

    def test_users_command_succeeds(self):
        code, transport, prompts = self.run_main(
            ['--env-file', str(self.env_file), '--email', ADMIN_EMAIL, 'users'],
            self.default_responses(),
        )
        self.assertEqual(code, 0)
        self.assertIn(TARGET_EMAIL, self.out.getvalue())
        self.assertIn('已登录管理员', self.out.getvalue())
        self.assertEqual(prompts, ['管理员密码: '])
        self.assertEqual(len(transport.calls), 3)

    def test_email_option_after_subcommand(self):
        code, _, _ = self.run_main(
            ['users', '--env-file', str(self.env_file), '--email', ADMIN_EMAIL],
            self.default_responses(),
        )
        self.assertEqual(code, 0)

    def test_email_prompt_when_option_missing(self):
        code, _, prompts = self.run_main(
            ['--env-file', str(self.env_file), 'users'],
            self.default_responses(),
            inputs=[ADMIN_EMAIL],
        )
        self.assertEqual(code, 0)
        self.assertEqual(prompts[0], '管理员邮箱: ')
        self.assertEqual(prompts[1], '管理员密码: ')

    def test_non_admin_exits_three_before_any_admin_rpc(self):
        responses = [
            json_response(session_payload()),
            json_response([]),
            json_response([user_row()]),
        ]
        code, transport, _ = self.run_main(
            ['--env-file', str(self.env_file), '--email', ADMIN_EMAIL, 'users'],
            responses,
        )
        self.assertEqual(code, 3)
        self.assertEqual(len(transport.calls), 2)
        self.assertIn('不是 Pacta 管理员', self.err.getvalue())

    def test_missing_config_exits_two_without_http(self):
        empty = self.root / 'empty.env'
        empty.write_text('# no values\n', encoding='utf-8')
        code, transport, _ = self.run_main(
            ['--env-file', str(empty), '--email', ADMIN_EMAIL, 'users'],
            [],
            environ={},
        )
        self.assertEqual(code, 2)
        self.assertEqual(len(transport.calls), 0)
        self.assertIn('缺少', self.err.getvalue())

    def test_default_env_missing_uses_environment(self):
        with mock.patch.object(MODULE, 'DEFAULT_ENV_FILE', self.root / 'missing.env'):
            code, _, _ = self.run_main(
                ['--email', ADMIN_EMAIL, 'users'],
                self.default_responses(),
                environ={
                    'SUPABASE_URL': 'https://project.supabase.co',
                    'SUPABASE_PUBLISHABLE_KEY': PUBLIC_KEY,
                },
            )
        self.assertEqual(code, 0)

    def test_service_role_is_ignored_and_not_printed(self):
        env = self.root / 'with-secret.env'
        env.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            f'SUPABASE_PUBLISHABLE_KEY={PUBLIC_KEY}\n'
            f'SUPABASE_SERVICE_ROLE_KEY={SERVICE_SECRET}\n',
            encoding='utf-8',
        )
        code, transport, _ = self.run_main(
            ['--env-file', str(env), '--email', ADMIN_EMAIL, 'users'],
            self.default_responses(),
        )
        self.assertEqual(code, 0)
        output = self.out.getvalue() + self.err.getvalue()
        self.assertIn('SUPABASE_SERVICE_ROLE_KEY', output)
        self.assertNotIn(SERVICE_SECRET, output)
        for call in transport.calls:
            self.assertNotIn(SERVICE_SECRET, json.dumps(call.headers))
            self.assertNotIn(SERVICE_SECRET, (call.body or b'').decode('utf-8', 'replace'))

    def test_network_error_exits_one(self):
        code, _, _ = self.run_main(
            ['--env-file', str(self.env_file), '--email', ADMIN_EMAIL, 'users'],
            [MODULE.TransportError('无法连接云端服务：dns failure')],
        )
        self.assertEqual(code, 1)
        self.assertIn('无法连接云端服务', self.err.getvalue())

    def test_keyboard_interrupt_exits_130(self):
        def interrupted(label):
            raise KeyboardInterrupt

        transport = FakeTransport([])
        code = MODULE.main(
            ['--env-file', str(self.env_file), 'users'],
            transport=transport,
            environ={},
            out=self.out,
            err=self.err,
            input_fn=interrupted,
            getpass_fn=lambda label: 'pw',
        )
        self.assertEqual(code, 130)

    def test_grant_command_calls_rpc(self):
        responses = [
            json_response(session_payload()),
            json_response([{'user_id': ADMIN_ID}]),
            json_response(
                {
                    'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                    'identifier': TARGET_EMAIL,
                    'identifier_type': 'email',
                    'created_at': '2026-01-01T00:00:00+00:00',
                    'used_at': None,
                    'used_user_id': None,
                    'revoked_at': None,
                    'purge_completed_at': None,
                }
            ),
        ]
        code, transport, _ = self.run_main(
            [
                '--env-file',
                str(self.env_file),
                '--email',
                ADMIN_EMAIL,
                'grant',
                'Person@Example.com',
            ],
            responses,
        )
        self.assertEqual(code, 0)
        self.assertEqual(transport.calls[-1].json['p_identifier'], TARGET_EMAIL)
        self.assertIn('已发放注册资格', self.out.getvalue())

    def test_delete_user_command_requires_typed_email(self):
        responses = [
            json_response(session_payload()),
            json_response([{'user_id': ADMIN_ID}]),
            json_response(
                [
                    user_row(
                        is_suspended=True,
                        suspended_at='2026-01-01T00:00:00+00:00',
                        purge_eligible_at='2026-01-31T00:00:00+00:00',
                        is_eligible_for_purge=True,
                    )
                ]
            ),
            json_response([]),
            json_response(
                {
                    'user_id': TARGET_ID,
                    'status': 'completed',
                    'purged_at': '2026-11-22T00:00:00+00:00',
                }
            ),
        ]
        code, transport, prompts = self.run_main(
            [
                '--env-file',
                str(self.env_file),
                '--email',
                ADMIN_EMAIL,
                'delete-user',
                TARGET_EMAIL,
                '--immediate',
            ],
            responses,
            inputs=[TARGET_EMAIL],
        )
        self.assertEqual(code, 0)
        self.assertEqual(transport.calls[-1].json, {'user_id': TARGET_ID, 'immediate': True})
        self.assertIn('逐字输入目标邮箱', prompts[-1])

    def test_delete_user_wrong_typed_email_exits_cancelled(self):
        responses = [
            json_response(session_payload()),
            json_response([{'user_id': ADMIN_ID}]),
            json_response(
                [
                    user_row(
                        is_suspended=True,
                        purge_eligible_at='2026-01-31T00:00:00+00:00',
                        is_eligible_for_purge=True,
                    )
                ]
            ),
            json_response([]),
        ]
        code, transport, _ = self.run_main(
            [
                '--env-file',
                str(self.env_file),
                '--email',
                ADMIN_EMAIL,
                'delete-user',
                TARGET_EMAIL,
                '--immediate',
            ],
            responses,
            inputs=['wrong@example.com'],
        )
        self.assertEqual(code, 4)
        self.assertEqual(len(transport.calls), 4)
        self.assertIn('已取消', self.err.getvalue())


# --------------------------------------------------------------------------
# Interactive menu
# --------------------------------------------------------------------------


class MenuTest(AdminToolTestCase):
    def menu_responses(self, *extra):
        return [json_response(session_payload()), json_response([{'user_id': ADMIN_ID}])] + list(extra)

    def run_menu(self, inputs, responses, passwords=None):
        return self.run_main(
            ['--env-file', str(self.env_file), '--email', ADMIN_EMAIL],
            responses,
            inputs=inputs,
            passwords=passwords if passwords is not None else ['admin-password'],
        )

    def test_zero_exits_zero(self):
        code, transport, _ = self.run_menu(['0'], self.menu_responses())
        self.assertEqual(code, 0)
        self.assertEqual(len(transport.calls), 2)
        self.assertIn('Pacta 云端管理', self.out.getvalue())

    def test_unknown_choice_reports_error_then_exits(self):
        code, _, _ = self.run_menu(['9', '0'], self.menu_responses())
        self.assertEqual(code, 0)
        self.assertIn('无效选项', self.err.getvalue())

    def test_grant_flow(self):
        responses = self.menu_responses(
            json_response(
                {
                    'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                    'identifier': TARGET_EMAIL,
                    'identifier_type': 'email',
                    'created_at': '2026-01-01T00:00:00+00:00',
                    'used_at': None,
                    'used_user_id': None,
                    'revoked_at': None,
                    'purge_completed_at': None,
                }
            )
        )
        code, transport, _ = self.run_menu(['3', TARGET_EMAIL, '0'], responses)
        self.assertEqual(code, 0)
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/rest/v1/rpc/admin_grant_registration_eligibility',
        )

    def test_delete_flow_prompts_immediate_and_typed_email(self):
        responses = self.menu_responses(
            json_response(
                [
                    user_row(
                        is_suspended=True,
                        suspended_at='2026-11-20T00:00:00+00:00',
                        purge_eligible_at='2026-12-20T00:00:00+00:00',
                        is_eligible_for_purge=False,
                    )
                ]
            ),
            json_response([]),
            json_response(
                {
                    'user_id': TARGET_ID,
                    'status': 'completed',
                    'purged_at': '2026-11-22T00:00:00+00:00',
                }
            ),
        )
        code, transport, _ = self.run_menu(
            ['8', TARGET_EMAIL, 'yes', TARGET_EMAIL, '0'], responses
        )
        self.assertEqual(code, 0)
        self.assertEqual(transport.calls[-1].json, {'user_id': TARGET_ID, 'immediate': True})
        self.assertIn('已完成永久清除', self.out.getvalue())

    def test_delete_flow_declining_immediate_stays_in_menu(self):
        responses = self.menu_responses(
            json_response(
                [
                    user_row(
                        is_suspended=True,
                        purge_eligible_at='2026-12-20T00:00:00+00:00',
                        is_eligible_for_purge=False,
                    )
                ]
            ),
            json_response([]),
        )
        code, transport, _ = self.run_menu(['8', TARGET_EMAIL, '', '0'], responses)
        self.assertEqual(code, 0)
        self.assertEqual(len(transport.calls), 4)
        self.assertIn('已取消', self.err.getvalue())

    def test_reset_password_flow(self):
        responses = self.menu_responses(
            json_response([user_row()]),
            json_response({'status': 'password_reset'}),
        )
        code, transport, _ = self.run_menu(
            ['7', TARGET_EMAIL, 'yes', '0'],
            responses,
            passwords=['admin-password', 'new-password-1', 'new-password-1'],
        )
        self.assertEqual(code, 0)
        self.assertEqual(
            transport.calls[-1].url,
            'https://project.supabase.co/functions/v1/admin-reset-user-password',
        )


if __name__ == '__main__':
    unittest.main()
