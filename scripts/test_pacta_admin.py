#!/usr/bin/env python3
"""Fully offline tests for scripts/pacta_admin.py.

Every HTTP interaction goes through an injected route-based fake transport, so
no Supabase project, network, TTY, workspace .env or real project-owner secret
is involved. The tests also assert that the secret key never appears in output.
"""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
import urllib.error
import urllib.parse
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

PROJECT_URL = 'https://project.supabase.co'
SECRET_KEY = 'sb_secret_test_project_owner_key_value'
LEGACY_JWT = (
    'eyJhbGciOiJIUzI1NiJ9.'
    'eyJyb2xlIjoic2VydmljZV9yb2xlIn0.'
    'signature'
)
TARGET_ID = '22222222-2222-4222-8222-222222222222'
OTHER_ID = '33333333-3333-4333-8333-333333333333'
TARGET_EMAIL = 'person@example.com'
OTHER_EMAIL = 'other@example.com'
ELIGIBILITY_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'


# --------------------------------------------------------------------------
# Fixtures
# --------------------------------------------------------------------------


def json_response(payload, status=200):
    return MODULE.HttpResponse(
        status=status,
        body=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
    )


def ok(payload, status=200):
    return json_response(payload, status)


def empty(status=204):
    return MODULE.HttpResponse(status=status, body=b'')


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

    @property
    def path(self):
        return urllib.parse.urlsplit(self.url).path

    @property
    def query(self):
        return urllib.parse.urlsplit(self.url).query


class RouteTransport:
    """Match calls by method plus a URL substring; one or more responses."""

    def __init__(self):
        self.routes = []
        self.calls = []

    def add(self, method, contains, *responses, repeat=False):
        self.routes.append(
            {
                'method': method,
                'contains': contains,
                'responses': list(responses),
                'repeat': repeat,
            }
        )
        return self

    def request(self, method, url, headers=None, body=None):
        call = Call(method, url, dict(headers or {}), body)
        self.calls.append(call)
        for route in self.routes:
            if route['method'] != method or route['contains'] not in url:
                continue
            if route['repeat']:
                response = route['responses'][0]
            else:
                if not route['responses']:
                    continue
                response = route['responses'].pop(0)
            if isinstance(response, BaseException):
                raise response
            return response
        raise AssertionError(f'unexpected HTTP call: {method} {url}')

    @property
    def urls(self):
        return [call.url for call in self.calls]

    def urls_containing(self, text):
        return [call.url for call in self.calls if text in call.url]

    def calls_for(self, text):
        return [call for call in self.calls if text in call.url]


def user_row(user_id=TARGET_ID, email=TARGET_EMAIL, **overrides):
    values = {
        'id': user_id,
        'email': email,
        'created_at': '2026-01-01T00:00:00+00:00',
        'last_sign_in_at': '2026-01-02T00:00:00+00:00',
        'banned_until': None,
    }
    values.update(overrides)
    return values


def eligibility_row(
    identifier=TARGET_EMAIL,
    *,
    eligibility_id=ELIGIBILITY_ID,
    used_at=None,
    used_user_id=None,
    revoked_at=None,
    purge_completed_at=None,
):
    return {
        'id': eligibility_id,
        'identifier': identifier,
        'identifier_type': 'email',
        'created_at': '2026-01-01T00:00:00+00:00',
        'used_at': used_at,
        'used_user_id': used_user_id,
        'revoked_at': revoked_at,
        'purge_completed_at': purge_completed_at,
    }


def snapshot_row(
    user_id=TARGET_ID,
    *,
    revision=7,
    schema_version='3',
    row_count=120,
):
    return {
        'user_id': user_id,
        'revision': revision,
        'schema_version': schema_version,
        'device_name': 'Pixel',
        'data_updated_at': '2026-11-20T00:00:00+00:00',
        'uploaded_at': '2026-11-21T00:00:00+00:00',
        'row_count': row_count,
    }


def install_user_data(
    transport,
    users,
    *,
    eligibilities=(),
    suspensions=(),
    snapshots=(),
    history=None,
    uploads=None,
    mcp=(),
    admins=(),
    profiles=(),
):
    """Install the aggregate queries that list_users() always performs."""

    page = 1
    start = 0
    while start < len(users):
        chunk = users[start:start + MODULE.USERS_PAGE_SIZE]
        transport.add(
            'GET',
            f'/auth/v1/admin/users?page={page}',
            ok({'users': chunk}),
        )
        start += MODULE.USERS_PAGE_SIZE
        page += 1
    if not users:
        transport.add('GET', '/auth/v1/admin/users?page=1', ok({'users': []}))
    elif len(users) % MODULE.USERS_PAGE_SIZE == 0:
        transport.add(
            'GET',
            f'/auth/v1/admin/users?page={page}',
            ok({'users': []}),
        )

    transport.add(
        'GET',
        '/rest/v1/registration_eligibility?select=',
        ok(list(eligibilities)),
        repeat=True,
    )
    transport.add(
        'GET',
        '/rest/v1/user_suspension_periods?select=',
        ok(list(suspensions)),
        repeat=True,
    )
    transport.add(
        'GET',
        '/rest/v1/cloud_business_snapshots?select=',
        ok(list(snapshots)),
        repeat=True,
    )
    history_rows = [
        {'user_id': user_id}
        for user_id, count in (history or {}).items()
        for _ in range(count)
    ]
    transport.add(
        'GET',
        '/rest/v1/cloud_business_snapshot_history?select=',
        ok(history_rows),
        repeat=True,
    )
    upload_rows = [
        {'user_id': user_id}
        for user_id, count in (uploads or {}).items()
        for _ in range(count)
    ]
    transport.add(
        'GET',
        '/rest/v1/cloud_business_snapshot_upload_requests?select=',
        ok(upload_rows),
        repeat=True,
    )
    transport.add(
        'GET',
        '/rest/v1/national_focus_mcp_grants?select=',
        ok(list(mcp)),
        repeat=True,
    )
    transport.add(
        'GET',
        '/rest/v1/profile_accounts?select=',
        ok(list(profiles)),
        repeat=True,
    )
    transport.add(
        'GET',
        '/rest/v1/app_admins?select=',
        ok([{'user_id': user_id} for user_id in admins]),
        repeat=True,
    )
    return transport


class Harness(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env_file = self.root / '.env'
        self.env_file.write_text(
            f'SUPABASE_URL={PROJECT_URL}\n'
            f'SUPABASE_SECRET_KEY={SECRET_KEY}\n',
            encoding='utf-8',
        )
        self.out = io.StringIO()
        self.err = io.StringIO()
        self.transport = RouteTransport()
        # Never read or reconfigure the real workspace .env or console.
        for patcher in (
            mock.patch.object(MODULE, 'configure_console', lambda: None),
            mock.patch.object(MODULE, 'DEFAULT_ENV_FILE', self.env_file),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_main(self, argv, *, environ=None, inputs=None, passwords=None):
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

        code = MODULE.main(
            argv,
            transport=self.transport,
            environ={} if environ is None else environ,
            out=self.out,
            err=self.err,
            input_fn=input_fn,
            getpass_fn=getpass_fn,
        )
        return code, prompts

    @property
    def output(self):
        return self.out.getvalue()

    @property
    def error(self):
        return self.err.getvalue()


# --------------------------------------------------------------------------
# Console, dotenv and configuration
# --------------------------------------------------------------------------


class ConfigureConsoleTest(unittest.TestCase):
    def test_reconfigures_stdout_and_stderr_to_utf8(self):
        calls = []

        class Stream:
            def reconfigure(self, **kwargs):
                calls.append(kwargs)

        with mock.patch.object(MODULE.sys, 'stdout', Stream()), mock.patch.object(
            MODULE.sys, 'stderr', Stream()
        ):
            MODULE.configure_console()
        self.assertEqual(calls, [{'encoding': 'utf-8', 'errors': 'replace'}] * 2)

    def test_streams_without_reconfigure_are_tolerated(self):
        with mock.patch.object(MODULE.sys, 'stdout', object()), mock.patch.object(
            MODULE.sys, 'stderr', object()
        ):
            MODULE.configure_console()


class EnvFileTest(Harness):
    def test_reads_quotes_exports_and_inline_hashes(self):
        path = self.root / 'sample.env'
        path.write_text(
            '# comment\n'
            '\n'
            'SUPABASE_URL="https://project.supabase.co"\n'
            "SUPABASE_SECRET_KEY='sb_secret_key'\n"
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
        self.assertEqual(values['SUPABASE_SECRET_KEY'], 'sb_secret_key')
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


class LoadConfigTest(Harness):
    def test_reads_url_and_secret_key_from_dotenv(self):
        config = MODULE.load_config(self.env_file, {})
        self.assertEqual(config.url, PROJECT_URL)
        self.assertEqual(config.host, 'project.supabase.co')
        self.assertEqual(config.secret_key, SECRET_KEY)
        self.assertEqual(config.secret_key_name, 'SUPABASE_SECRET_KEY')
        self.assertEqual(config.source, str(self.env_file))

    def test_secret_key_preferred_over_service_role_in_same_source(self):
        config = MODULE.load_config(
            self.env_file,
            {
                'SUPABASE_SERVICE_ROLE_KEY': 'legacy-value',
                'SUPABASE_SECRET_KEY': 'new-value',
            },
        )
        self.assertEqual(config.secret_key, 'new-value')
        self.assertEqual(config.secret_key_name, 'SUPABASE_SECRET_KEY')

    def test_service_role_fallback_is_used(self):
        config = MODULE.load_config(
            self.env_file,
            {'SUPABASE_SERVICE_ROLE_KEY': 'legacy-value'},
        )
        self.assertEqual(config.secret_key, 'legacy-value')
        self.assertEqual(config.secret_key_name, 'SUPABASE_SERVICE_ROLE_KEY')

    def test_environment_beats_dotenv(self):
        config = MODULE.load_config(
            self.env_file,
            {
                'SUPABASE_URL': 'https://env.supabase.co',
                'SUPABASE_SECRET_KEY': 'env-secret',
            },
        )
        self.assertEqual(config.url, 'https://env.supabase.co')
        self.assertEqual(config.secret_key, 'env-secret')
        self.assertEqual(config.source, str(self.env_file))

    def test_environment_legacy_name_beats_dotenv_secret_key(self):
        config = MODULE.load_config(
            self.env_file,
            {'SUPABASE_SERVICE_ROLE_KEY': 'env-legacy'},
        )
        self.assertEqual(config.secret_key, 'env-legacy')
        self.assertEqual(config.secret_key_name, 'SUPABASE_SERVICE_ROLE_KEY')

    def test_dotenv_fills_missing_values(self):
        config = MODULE.load_config(
            self.env_file,
            {'SUPABASE_URL': 'https://env.supabase.co'},
        )
        self.assertEqual(config.url, 'https://env.supabase.co')
        self.assertEqual(config.secret_key, SECRET_KEY)

    def test_missing_secret_key_error_is_actionable_and_hides_values(self):
        path = self.root / 'client-only.env'
        path.write_text(
            'SUPABASE_URL=https://project.supabase.co\n'
            'SUPABASE_PUBLISHABLE_KEY=sb_publishable_public\n'
            'TEST_ADMIN_EMAIL=admin@example.com\n'
            'TEST_ADMIN_PASSWORD=admin-password\n',
            encoding='utf-8',
        )
        with self.assertRaises(MODULE.ConfigError) as caught:
            MODULE.load_config(path, {})
        message = str(caught.exception)
        self.assertIn('SUPABASE_SECRET_KEY', message)
        self.assertIn('Project Settings', message)
        self.assertIn('API Keys', message)
        self.assertNotIn('sb_publishable_public', message)
        self.assertNotIn('admin-password', message)
        self.assertEqual(caught.exception.exit_code, 2)

    def test_missing_url_and_secret_lists_both(self):
        path = self.root / 'empty.env'
        path.write_text('# nothing here\n', encoding='utf-8')
        with self.assertRaises(MODULE.ConfigError) as caught:
            MODULE.load_config(path, {})
        message = str(caught.exception)
        self.assertIn('SUPABASE_URL', message)
        self.assertIn('SUPABASE_SECRET_KEY', message)

    def test_client_keys_and_test_admin_credentials_are_ignored(self):
        config = MODULE.load_config(
            self.env_file,
            {
                'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_public',
                'SUPABASE_ANON_KEY': 'legacy-anon',
                'TEST_ADMIN_EMAIL': 'admin@example.com',
                'TEST_ADMIN_PASSWORD': 'admin-password',
            },
        )
        self.assertEqual(config.secret_key, SECRET_KEY)
        self.assertNotEqual(config.secret_key, 'sb_publishable_public')
        self.assertNotEqual(config.secret_key, 'legacy-anon')

    def test_non_http_url_is_rejected(self):
        path = self.root / 'scheme.env'
        path.write_text(
            'SUPABASE_URL=ftp://project.supabase.co\n'
            f'SUPABASE_SECRET_KEY={SECRET_KEY}\n',
            encoding='utf-8',
        )
        with self.assertRaises(MODULE.ConfigError):
            MODULE.load_config(path, {})

    def test_trailing_slash_is_stripped(self):
        path = self.root / 'slash.env'
        path.write_text(
            'SUPABASE_URL="https://project.supabase.co/"\n'
            f'SUPABASE_SECRET_KEY={SECRET_KEY}\n',
            encoding='utf-8',
        )
        self.assertEqual(MODULE.load_config(path, {}).url, PROJECT_URL)

    def test_explicit_missing_env_file_is_an_error(self):
        with self.assertRaises(MODULE.ConfigError):
            MODULE.load_config(self.root / 'missing.env', {})

    def test_default_env_missing_falls_back_to_environment(self):
        config = MODULE.load_config(
            None,
            {
                'SUPABASE_URL': PROJECT_URL,
                'SUPABASE_SECRET_KEY': 'env-secret',
            },
            default_env_file=self.root / 'missing.env',
        )
        self.assertEqual(config.secret_key, 'env-secret')
        self.assertEqual(config.source, '环境变量')

    def test_config_repr_does_not_expose_secret(self):
        config = MODULE.load_config(self.env_file, {})
        self.assertNotIn(SECRET_KEY, repr(config))


# --------------------------------------------------------------------------
# Request headers
# --------------------------------------------------------------------------


class HeaderTest(Harness):
    def test_is_jwt_token(self):
        self.assertTrue(MODULE._is_jwt_token(LEGACY_JWT))
        self.assertFalse(MODULE._is_jwt_token(SECRET_KEY))
        self.assertFalse(MODULE._is_jwt_token('a..b'))
        self.assertFalse(MODULE._is_jwt_token(''))
        self.assertFalse(MODULE._is_jwt_token('one.two'))

    def test_sb_secret_key_sends_apikey_only(self):
        headers = MODULE.build_auth_headers(SECRET_KEY)
        self.assertEqual(headers['apikey'], SECRET_KEY)
        self.assertNotIn('Authorization', headers)

    def test_legacy_service_role_jwt_sends_apikey_and_bearer(self):
        headers = MODULE.build_auth_headers(LEGACY_JWT)
        self.assertEqual(headers['apikey'], LEGACY_JWT)
        self.assertEqual(headers['Authorization'], f'Bearer {LEGACY_JWT}')

    def test_client_request_uses_sb_secret_headers(self):
        self.transport.add(
            'GET',
            '/auth/v1/admin/users?page=1',
            ok({'users': []}),
        )
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        client._list_auth_users()
        headers = self.transport.calls[0].headers
        self.assertEqual(headers['apikey'], SECRET_KEY)
        self.assertNotIn('Authorization', headers)
        self.assertEqual(headers['Accept'], 'application/json')

    def test_client_request_uses_legacy_jwt_headers(self):
        self.transport.add(
            'GET',
            '/auth/v1/admin/users?page=1',
            ok({'users': []}),
        )
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=LEGACY_JWT),
            self.transport,
        )
        client._list_auth_users()
        headers = self.transport.calls[0].headers
        self.assertEqual(headers['apikey'], LEGACY_JWT)
        self.assertEqual(headers['Authorization'], f'Bearer {LEGACY_JWT}')


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
            result = MODULE.HttpTransport().request(
                'POST', 'https://example.test/x', body=b'{}'
            )
        self.assertEqual(result.status, 409)
        self.assertEqual(result.body, b'{"error":"conflict"}')

    def test_value_error_becomes_transport_error(self):
        with mock.patch(
            'urllib.request.urlopen', side_effect=ValueError('unknown url type')
        ):
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
        user = MODULE.UserRecord(user_id=TARGET_ID, email=TARGET_EMAIL)
        self.assertEqual(user.status_label(), '正常')

    def test_suspended_user_remaining_days_round_up(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        user = MODULE.UserRecord(
            user_id=TARGET_ID,
            email=TARGET_EMAIL,
            suspension=MODULE.Suspension(
                suspended_at=now.replace(day=1, hour=0),
            ),
        )
        self.assertEqual(user.status_label(now), '已停用（剩 30 天可清除）')
        self.assertEqual(
            user.status_label(now.replace(day=13, hour=12)),
            '已停用（剩 18 天可清除）',
        )

    def test_suspended_user_past_window(self):
        now = datetime(2026, 3, 1, tzinfo=timezone.utc)
        user = MODULE.UserRecord(
            user_id=TARGET_ID,
            email=TARGET_EMAIL,
            suspension=MODULE.Suspension(
                suspended_at=now.replace(month=1, day=1),
            ),
        )
        self.assertEqual(user.status_label(now), '已停用（已满 30 天可清除）')

    def test_legacy_ban_is_reported(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        user = MODULE.UserRecord(
            user_id=TARGET_ID,
            email=TARGET_EMAIL,
            banned_until=now.replace(year=2126),
        )
        self.assertEqual(user.status_label(now), '已封禁')

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

    def test_cloud_snapshot_accepts_text_integers(self):
        record = MODULE.CloudSnapshot.from_row(
            {
                'user_id': TARGET_ID,
                'revision': '7',
                'row_count': '120',
                'schema_version': '3',
                'device_name': 'Pixel',
            }
        )
        self.assertEqual(record.revision, 7)
        self.assertEqual(record.row_count, 120)
        self.assertEqual(record.schema_version, '3')

    def test_summaries_count_states(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        users = [
            MODULE.UserRecord(user_id='a', email='a@b.c'),
            MODULE.UserRecord(
                user_id='b',
                email='b@b.c',
                suspension=MODULE.Suspension(suspended_at=now),
                legacy_admin=True,
                snapshot=MODULE.CloudSnapshot(user_id='b', revision=2),
                eligibility=MODULE.Eligibility('b@b.c', 'email'),
            ),
        ]
        summary = MODULE.summarize_users(users)
        self.assertIn('共 2 个账号', summary)
        self.assertIn('已停用 1', summary)
        self.assertIn('历史管理员 1', summary)
        rows = [
            MODULE.Eligibility('a@b.c', 'email'),
            MODULE.Eligibility('b@b.c', 'email', revoked_at=now),
        ]
        self.assertIn('待使用 1', MODULE.summarize_eligibilities(rows))


# --------------------------------------------------------------------------
# Error payloads and HTTP error mapping
# --------------------------------------------------------------------------


class ErrorPayloadTest(unittest.TestCase):
    def client(self):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            RouteTransport(),
        )

    def test_prefers_string_error_code_over_numeric_code(self):
        # GoTrue answers 422 with both a numeric code and a symbolic error_code;
        # only the symbolic one identifies the failure.
        code, message = MODULE._extract_error(
            {
                'code': 422,
                'error_code': 'email_exists',
                'msg': 'User already registered',
            }
        )
        self.assertEqual(code, 'email_exists')
        self.assertEqual(message, 'User already registered')

    def test_falls_back_to_numeric_code_and_known_message_keys(self):
        self.assertEqual(
            MODULE._extract_error({'code': 55000, 'message': 'not pending'}),
            ('55000', 'not pending'),
        )
        self.assertEqual(
            MODULE._extract_error({'error_code': '   ', 'code': '42501'}),
            ('42501', ''),
        )
        self.assertEqual(MODULE._extract_error({'code': True}), ('', ''))

    def test_composed_error_does_not_repeat_the_http_status(self):
        response = json_response(
            {
                'code': 422,
                'error_code': 'email_exists',
                'msg': 'User already registered',
            },
            status=422,
        )
        message = self.client()._compose_error('创建用户失败', response)
        self.assertIn('错误码 email_exists', message)
        self.assertNotIn('错误码 422', message)
        self.assertIn('（HTTP 422）', message)

    def test_401_is_an_auth_error(self):
        response = json_response({'message': 'invalid JWT'}, status=401)
        with self.assertRaises(MODULE.AuthError) as caught:
            self.client()._expect(response, '读取用户列表失败')
        self.assertEqual(caught.exception.exit_code, MODULE.EXIT_FORBIDDEN)
        self.assertIn('SUPABASE_SECRET_KEY', str(caught.exception))

    def test_403_is_a_forbidden_error(self):
        response = json_response({'message': 'insufficient privilege'}, status=403)
        with self.assertRaises(MODULE.ForbiddenError) as caught:
            self.client()._expect(response, '读取用户列表失败')
        self.assertEqual(caught.exception.exit_code, MODULE.EXIT_FORBIDDEN)

    def test_sqlstate_hints_are_mapped_to_actionable_errors(self):
        for code, hint in MODULE.SQLSTATE_HINTS.items():
            with self.subTest(code=code):
                response = json_response(
                    {'code': code, 'message': 'server rejected the request'},
                    status=400,
                )
                with self.assertRaises(MODULE.ApiError) as caught:
                    self.client()._expect(response, '执行云端操作失败')
                self.assertEqual(caught.exception.code, code)
                self.assertIn(hint, str(caught.exception))

    def test_sqlstate_hints_do_not_mask_conflicts_or_server_errors(self):
        response = json_response({'code': '42501', 'message': 'conflict'}, status=409)
        with self.assertRaises(MODULE.ApiError) as caught:
            self.client()._expect(response, '写入失败')
        self.assertNotIn(MODULE.SQLSTATE_HINTS['42501'], str(caught.exception))
        self.assertIn('（HTTP 409）', str(caught.exception))

    def test_malformed_json_body_is_an_api_error(self):
        response = MODULE.HttpResponse(
            status=200,
            body=b'<html>bad gateway</html>',
            headers={'Content-Type': 'text/html'},
        )
        with self.assertRaises(MODULE.ApiError) as caught:
            MODULE._decode_json(response)
        self.assertEqual(caught.exception.status, 200)
        self.assertIn('无法解析', str(caught.exception))

    def test_invalid_utf8_body_is_an_api_error(self):
        response = MODULE.HttpResponse(status=200, body=b'\xff\xfe\x00')
        with self.assertRaises(MODULE.ApiError) as caught:
            MODULE._decode_json(response)
        self.assertEqual(caught.exception.status, 200)


# --------------------------------------------------------------------------
# Users
# --------------------------------------------------------------------------


class UserListTest(Harness):
    def install_two_users(self):
        install_user_data(
            self.transport,
            [user_row(), user_row(OTHER_ID, OTHER_EMAIL)],
            eligibilities=[
                eligibility_row(
                    TARGET_EMAIL,
                    used_at='2026-01-02T00:00:00+00:00',
                    used_user_id=TARGET_ID,
                )
            ],
            suspensions=[
                {
                    'user_id': OTHER_ID,
                    'suspended_at': '2026-11-01T00:00:00+00:00',
                    'restored_at': None,
                }
            ],
            snapshots=[snapshot_row()],
            history={TARGET_ID: 3},
            uploads={TARGET_ID: 1},
            mcp=[
                {
                    'user_id': TARGET_ID,
                    'expires_at': '2126-01-01T00:00:00+00:00',
                    'revoked_at': None,
                },
                {
                    'user_id': OTHER_ID,
                    'expires_at': '2126-01-01T00:00:00+00:00',
                    'revoked_at': '2026-01-01T00:00:00+00:00',
                },
            ],
            admins=[OTHER_ID],
            profiles=[
                {
                    'user_id': TARGET_ID,
                    'display_name': '小明',
                    'time_zone_id': 'Asia/Shanghai',
                }
            ],
        )

    def test_list_users_aggregates_every_source(self):
        self.install_two_users()
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        records = client.list_users()
        self.assertEqual(len(records), 2)
        first, second = records

        self.assertEqual(first.email, TARGET_EMAIL)
        self.assertEqual(first.display_name, '小明')
        self.assertEqual(first.time_zone_id, 'Asia/Shanghai')
        self.assertEqual(first.eligibility.status_label(), '已使用')
        self.assertEqual(first.snapshot.revision, 7)
        self.assertEqual(first.snapshot.schema_version, '3')
        self.assertEqual(first.snapshot.row_count, 120)
        self.assertEqual(first.history_count, 3)
        self.assertEqual(first.upload_request_count, 1)
        self.assertEqual(first.mcp.active, 1)
        self.assertFalse(first.legacy_admin)
        self.assertIn('已停用', second.status_label())
        self.assertEqual(second.mcp.revoked, 1)
        self.assertTrue(second.legacy_admin)

        self.assertTrue(self.transport.urls_containing('page=1&per_page=100'))
        self.assertTrue(self.transport.urls_containing('&identifier=in.'))
        self.assertTrue(self.transport.urls_containing('&used_user_id=in.'))
        self.assertTrue(self.transport.urls_containing('&order=suspended_at.desc'))
        self.assertTrue(self.transport.urls_containing('schema_version:payload->>schemaVersion'))

    def test_list_users_paginates_until_short_page(self):
        users = [
            user_row(f'00000000-0000-4000-8000-{index:012d}', f'u{index}@example.com')
            for index in range(MODULE.USERS_PAGE_SIZE + 1)
        ]
        install_user_data(self.transport, users)
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        records = client.list_users()
        self.assertEqual(len(records), MODULE.USERS_PAGE_SIZE + 1)
        self.assertTrue(self.transport.urls_containing('page=1'))
        self.assertTrue(self.transport.urls_containing('page=2'))

    def test_list_users_follows_next_page_marker(self):
        self.transport.add(
            'GET',
            '/auth/v1/admin/users?page=1',
            ok({'users': [user_row()], 'next_page': 2}),
        )
        self.transport.add(
            'GET',
            '/auth/v1/admin/users?page=2',
            ok({'users': [user_row(OTHER_ID, OTHER_EMAIL)], 'next_page': None}),
        )
        install_user_data(
            self.transport,
            [user_row(), user_row(OTHER_ID, OTHER_EMAIL)],
        )
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        records = client.list_users()
        self.assertEqual(len(records), 2)
        self.assertTrue(self.transport.urls_containing('page=2'))

    def test_list_users_accepts_bare_array_response(self):
        self.transport.add('GET', '/auth/v1/admin/users?page=1', ok([user_row()]))
        install_user_data(self.transport, [user_row()])
        # The bare-array route above wins; aggregate routes still follow.
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        records = client.list_users()
        self.assertEqual(len(records), 1)

    def test_rejects_malformed_user_list(self):
        self.transport.add('GET', '/auth/v1/admin/users?page=1', ok({'users': 'no'}))
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        with self.assertRaises(MODULE.ApiError):
            client.list_users()

    def test_resolve_user_by_email_is_case_insensitive(self):
        self.install_two_users()
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        self.assertEqual(client.resolve_user('  PERSON@EXAMPLE.COM ').user_id, TARGET_ID)

    def test_resolve_user_by_uuid(self):
        self.install_two_users()
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        self.assertEqual(client.resolve_user(TARGET_ID.upper()).email, TARGET_EMAIL)

    def test_resolve_user_reports_unknown_email(self):
        self.install_two_users()
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        with self.assertRaises(MODULE.AdminToolError) as caught:
            client.resolve_user('nobody@example.com')
        self.assertIn('找不到邮箱', str(caught.exception))

    def test_resolve_user_reports_unknown_uuid(self):
        self.install_two_users()
        client = MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )
        with self.assertRaises(MODULE.AdminToolError) as caught:
            client.resolve_user('99999999-9999-4999-8999-999999999999')
        self.assertIn('找不到 UUID', str(caught.exception))

    def test_filter_users_matches_email_nickname_uuid_and_eligibility(self):
        records = [
            MODULE.UserRecord(
                user_id=TARGET_ID,
                email=TARGET_EMAIL,
                display_name='小明',
            ),
            MODULE.UserRecord(user_id=OTHER_ID, email=OTHER_EMAIL),
        ]
        self.assertEqual([record.user_id for record in MODULE.filter_users(records, '小')], [TARGET_ID])
        self.assertEqual(
            [record.user_id for record in MODULE.filter_users(records, 'OTHER@')], [OTHER_ID]
        )
        self.assertEqual(
            [record.user_id for record in MODULE.filter_users(records, TARGET_ID[:8])],
            [TARGET_ID],
        )
        self.assertEqual(len(MODULE.filter_users(records, '')), 2)

    def test_render_user_table_marks_legacy_admin_and_snapshot(self):
        records = [
            MODULE.UserRecord(
                user_id=TARGET_ID,
                email=TARGET_EMAIL,
                display_name='小明',
                legacy_admin=True,
                snapshot=MODULE.CloudSnapshot(user_id=TARGET_ID, revision=7),
                eligibility=MODULE.Eligibility(TARGET_EMAIL, 'email'),
            )
        ]
        rendered = '\n'.join(MODULE.render_user_table(records))
        self.assertIn('小明', rendered)
        self.assertIn('历史管理员', rendered)
        self.assertIn('r7', rendered)
        self.assertIn('待使用', rendered)


class InFilterChunkingTest(unittest.TestCase):
    """Bulk `in.(...)` lookups must never build one oversized URL."""

    def client(self, transport):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            transport,
        )

    @staticmethod
    def batch_sizes(transport, fragment):
        sizes = []
        for call in transport.calls_for(fragment):
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(call.url).query)
            for key in ('user_id', 'identifier', 'used_user_id'):
                value = query.get(key, [''])[0]
                if not value.startswith('in.('):
                    continue
                inner = value[len('in.('):-1]
                sizes.append(len(inner.split(',')) if inner else 0)
        return sizes

    def test_list_users_batches_every_in_filter(self):
        transport = install_user_data(
            RouteTransport(),
            [
                user_row(
                    user_id=f'00000000-0000-4000-8000-{index:012d}',
                    email=f'user{index:03d}@example.com',
                )
                for index in range(150)
            ],
        )
        records = self.client(transport).list_users()
        self.assertEqual(len(records), 150)

        # 150 accounts must arrive as two batches of at most 100 per request;
        # eligibility is queried twice (identifier and used_user_id).
        for fragment, expected in (
            ('/rest/v1/user_suspension_periods?select=', [100, 50]),
            ('/rest/v1/registration_eligibility?select=', [100, 50, 100, 50]),
            ('/rest/v1/cloud_business_snapshots?select=', [100, 50]),
            ('/rest/v1/cloud_business_snapshot_history?select=', [100, 50]),
            ('/rest/v1/cloud_business_snapshot_upload_requests?select=', [100, 50]),
            ('/rest/v1/national_focus_mcp_grants?select=', [100, 50]),
            ('/rest/v1/profile_accounts?select=', [100, 50]),
            ('/rest/v1/app_admins?select=', [100, 50]),
        ):
            with self.subTest(fragment=fragment):
                self.assertEqual(self.batch_sizes(transport, fragment), expected)

        for call in transport.calls:
            if 'in.(' not in call.url:
                continue
            self.assertLess(len(call.url), 8192, call.url)

    def test_empty_user_list_sends_no_in_filter(self):
        transport = install_user_data(RouteTransport(), [])
        self.assertEqual(self.client(transport).list_users(), [])
        self.assertEqual(transport.urls_containing('in.('), [])


# --------------------------------------------------------------------------
# Registration eligibility
# --------------------------------------------------------------------------


class EligibilityTest(Harness):
    def client(self):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )

    def test_list_eligibilities_uses_expected_query(self):
        self.transport.add(
            'GET',
            '&order=created_at.desc',
            ok([eligibility_row()]),
        )
        rows = self.client().list_eligibilities()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].status_label(), '待使用')
        url = self.transport.calls[0].url
        self.assertIn('/rest/v1/registration_eligibility?select=id,identifier', url)
        self.assertIn('&order=created_at.desc', url)
        self.assertEqual(self.transport.calls[0].method, 'GET')

    def test_list_eligibilities_covers_all_statuses(self):
        self.transport.add(
            'GET',
            '&order=created_at.desc',
            ok(
                [
                    eligibility_row(),
                    eligibility_row(
                        'used@example.com',
                        used_at='2026-01-02T00:00:00+00:00',
                        used_user_id=TARGET_ID,
                    ),
                    eligibility_row(
                        'revoked@example.com',
                        revoked_at='2026-01-03T00:00:00+00:00',
                    ),
                    eligibility_row(
                        'purged@example.com',
                        purge_completed_at='2026-01-04T00:00:00+00:00',
                    ),
                ]
            ),
        )
        self.assertEqual(
            [row.status_label() for row in self.client().list_eligibilities()],
            ['待使用', '已使用', '已撤销', '已清除可重发'],
        )

    def test_grant_inserts_when_absent(self):
        self.transport.add(
            'GET',
            '&identifier=eq.',
            ok([]),
        )
        self.transport.add(
            'POST',
            '/rest/v1/registration_eligibility',
            ok([eligibility_row()], 201),
        )
        record = self.client().grant_eligibility(' Person@Example.com ')
        self.assertEqual(record.identifier, TARGET_EMAIL)
        post = self.transport.calls[-1]
        self.assertEqual(post.method, 'POST')
        self.assertEqual(
            post.json,
            {'identifier': TARGET_EMAIL, 'identifier_type': 'email'},
        )
        self.assertEqual(post.headers['Prefer'], 'return=representation')

    def test_grant_clears_revocation_for_unused_row(self):
        self.transport.add(
            'GET',
            '&identifier=eq.',
            ok([eligibility_row(revoked_at='2026-01-03T00:00:00+00:00')]),
        )
        self.transport.add(
            'PATCH',
            '/rest/v1/registration_eligibility?identifier=eq.',
            ok([eligibility_row()]),
        )
        record = self.client().grant_eligibility(TARGET_EMAIL)
        self.assertEqual(record.status_label(), '待使用')
        self.assertEqual(self.transport.calls[-1].json, {'revoked_at': None})

    def test_grant_clears_purge_completed_row(self):
        self.transport.add(
            'GET',
            '&identifier=eq.',
            ok(
                [
                    eligibility_row(
                        used_at='2026-01-02T00:00:00+00:00',
                        used_user_id=TARGET_ID,
                        purge_completed_at='2026-01-04T00:00:00+00:00',
                    )
                ]
            ),
        )
        self.transport.add(
            'PATCH',
            '/rest/v1/registration_eligibility?identifier=eq.',
            ok([eligibility_row()]),
        )
        record = self.client().grant_eligibility(TARGET_EMAIL)
        self.assertEqual(record.status_label(), '待使用')
        self.assertEqual(
            self.transport.calls[-1].json,
            {
                'used_at': None,
                'used_user_id': None,
                'revoked_at': None,
                'purge_completed_at': None,
            },
        )

    def test_grant_keeps_used_row_without_patch(self):
        self.transport.add(
            'GET',
            '&identifier=eq.',
            ok(
                [
                    eligibility_row(
                        used_at='2026-01-02T00:00:00+00:00',
                        used_user_id=TARGET_ID,
                    )
                ]
            ),
        )
        record = self.client().grant_eligibility(TARGET_EMAIL)
        self.assertEqual(record.status_label(), '已使用')
        self.assertEqual(len(self.transport.calls), 1)

    def test_grant_rejects_invalid_email_without_http(self):
        with self.assertRaises(MODULE.AdminToolError):
            self.client().grant_eligibility('not-an-email')
        self.assertEqual(self.transport.calls, [])

    def test_revoke_true_and_false(self):
        self.transport.add(
            'PATCH',
            '/rest/v1/registration_eligibility?identifier=eq.',
            ok([eligibility_row(revoked_at='2026-01-03T00:00:00+00:00')]),
            ok([]),
        )
        client = self.client()
        self.assertTrue(client.revoke_eligibility(TARGET_EMAIL))
        self.assertFalse(client.revoke_eligibility(TARGET_EMAIL))
        for call in self.transport.calls:
            self.assertIn('&used_at=is.null', call.url)
            self.assertIn('revoked_at', call.json)

    def test_command_grant_prints_note(self):
        self.transport.add('GET', '&identifier=eq.', ok([]))
        self.transport.add('POST', '/rest/v1/registration_eligibility', ok([eligibility_row()], 201))
        console = MODULE.ConsoleIO(self.out, self.err, lambda label: '', lambda label: '')
        outcome = MODULE.command_grant(
            self.client(), console, TARGET_EMAIL, note='转正'
        )
        self.assertIn('已发放注册资格', '\n'.join(outcome.lines))
        self.assertIn('转正', '\n'.join(outcome.lines))

    def test_command_revoke_messages(self):
        self.transport.add('PATCH', '/rest/v1/registration_eligibility?identifier=eq.', ok([eligibility_row()]), ok([]))
        console = MODULE.ConsoleIO(self.out, self.err, lambda label: '', lambda label: '')
        first = MODULE.command_revoke(self.client(), console, TARGET_EMAIL)
        second = MODULE.command_revoke(self.client(), console, TARGET_EMAIL)
        self.assertIn('已撤销', first.lines[0])
        self.assertIn('没有撤销任何资格', second.lines[0])


# --------------------------------------------------------------------------
# Create user
# --------------------------------------------------------------------------


class CreateUserTest(Harness):
    def client(self):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )

    def test_create_user_grants_eligibility_and_upserts_profile(self):
        self.transport.add('GET', '&identifier=eq.', ok([]))
        self.transport.add(
            'POST',
            '/rest/v1/registration_eligibility',
            ok([eligibility_row()], 201),
        )
        self.transport.add(
            'POST',
            '/auth/v1/admin/users',
            ok({'id': TARGET_ID, 'email': TARGET_EMAIL}, 201),
        )
        self.transport.add(
            'POST',
            '/rest/v1/profile_accounts?on_conflict=user_id',
            ok([{'user_id': TARGET_ID, 'display_name': '小明'}]),
        )
        console = MODULE.ConsoleIO(self.out, self.err, lambda label: '', lambda label: '')
        outcome = MODULE.command_create_user(
            self.client(),
            console,
            TARGET_EMAIL,
            password='initial-password',
            nickname=' 小明 ',
        )
        self.assertEqual(outcome.data['user_id'], TARGET_ID)
        self.assertEqual(outcome.data['display_name'], '小明')
        self.assertNotIn('initial_password', outcome.data)

        auth_call = self.transport.calls_for('/auth/v1/admin/users')[-1]
        self.assertEqual(
            auth_call.json,
            {
                'email': TARGET_EMAIL,
                'email_confirm': True,
                'password': 'initial-password',
                'user_metadata': {'display_name': '小明'},
            },
        )
        profile_call = self.transport.calls_for('/rest/v1/profile_accounts')[-1]
        self.assertEqual(profile_call.json['display_name'], '小明')
        self.assertEqual(
            profile_call.headers['Prefer'],
            'resolution=merge-duplicates,return=representation',
        )

    def test_create_user_generates_password_when_omitted(self):
        self.transport.add('GET', '&identifier=eq.', ok([]))
        self.transport.add('POST', '/rest/v1/registration_eligibility', ok([eligibility_row()], 201))
        self.transport.add('POST', '/auth/v1/admin/users', ok({'id': TARGET_ID}, 201))
        console = MODULE.ConsoleIO(self.out, self.err, lambda label: '', lambda label: '')
        outcome = MODULE.command_create_user(self.client(), console, TARGET_EMAIL)
        generated = outcome.data['initial_password']
        self.assertGreaterEqual(len(generated), 8)
        self.assertIn(generated, '\n'.join(outcome.lines))
        self.assertEqual(
            self.transport.calls_for('/auth/v1/admin/users')[-1].json['password'],
            generated,
        )

    def test_create_user_can_skip_eligibility(self):
        self.transport.add('POST', '/auth/v1/admin/users', ok({'id': TARGET_ID}, 201))
        console = MODULE.ConsoleIO(self.out, self.err, lambda label: '', lambda label: '')
        outcome = MODULE.command_create_user(
            self.client(),
            console,
            TARGET_EMAIL,
            password='initial-password',
            ensure_eligibility=False,
        )
        self.assertIn('已跳过', '\n'.join(outcome.lines))
        self.assertFalse(self.transport.urls_containing('registration_eligibility'))

    def test_create_user_rejects_long_nickname_before_http(self):
        with self.assertRaises(MODULE.AdminToolError):
            self.client().create_user(
                TARGET_EMAIL,
                password='initial-password',
                nickname='x' * 129,
            )
        self.assertEqual(self.transport.calls, [])

    def test_create_user_rejects_missing_id(self):
        self.transport.add('POST', '/auth/v1/admin/users', ok({'email': TARGET_EMAIL}, 201))
        with self.assertRaises(MODULE.ApiError):
            self.client().create_user(
                TARGET_EMAIL,
                password='initial-password',
                ensure_eligibility=False,
            )


# --------------------------------------------------------------------------
# Suspend, restore, reset password
# --------------------------------------------------------------------------


class LifecycleCommandTest(Harness):
    def client(self):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )

    def console(self, inputs=None, passwords=None):
        script = list(inputs or [])
        secrets = list(passwords or [])

        def input_fn(label):
            if not script:
                raise EOFError
            return script.pop(0)

        def getpass_fn(label):
            if not secrets:
                raise AssertionError('no password scripted')
            return secrets.pop(0)

        return MODULE.ConsoleIO(self.out, self.err, input_fn, getpass_fn)

    def install_user(self):
        install_user_data(self.transport, [user_row()])

    def test_suspend_creates_period_and_bans_auth_user(self):
        self.install_user()
        self.transport.add(
            'GET',
            '&restored_at=is.null&limit=1',
            ok([]),
        )
        self.transport.add(
            'POST',
            '/rest/v1/user_suspension_periods',
            ok([{'user_id': TARGET_ID}], 201),
        )
        self.transport.add(
            'PUT',
            f'/auth/v1/admin/users/{TARGET_ID}',
            ok({'id': TARGET_ID}),
        )
        console = self.console(inputs=['yes'])
        outcome = MODULE.command_suspend(self.client(), console, TARGET_EMAIL)
        self.assertTrue(outcome.data['created_period'])
        self.assertIn('已停用', '\n'.join(outcome.lines))
        put_call = self.transport.calls_for(f'/auth/v1/admin/users/{TARGET_ID}')[-1]
        self.assertEqual(put_call.method, 'PUT')
        self.assertEqual(put_call.json, {'ban_duration': MODULE.BAN_DURATION})

    def test_suspend_existing_period_only_refreshes_ban(self):
        self.transport.add(
            'GET',
            '&restored_at=is.null&limit=1',
            ok([{'user_id': TARGET_ID}]),
        )
        self.install_user()
        self.transport.add(
            'PUT',
            f'/auth/v1/admin/users/{TARGET_ID}',
            ok({'id': TARGET_ID}),
        )
        console = self.console(inputs=['y'])
        outcome = MODULE.command_suspend(self.client(), console, TARGET_EMAIL)
        self.assertFalse(outcome.data['created_period'])
        self.assertFalse(
            [
                call
                for call in self.transport.calls
                if call.method == 'POST' and 'user_suspension_periods' in call.url
            ]
        )

    def test_suspend_cancelled_does_not_call_http(self):
        self.install_user()
        console = self.console(inputs=['no'])
        with self.assertRaises(MODULE.OperationCancelled):
            MODULE.command_suspend(self.client(), console, TARGET_EMAIL)
        self.assertEqual(
            [call for call in self.transport.calls if call.method in ('POST', 'PUT')],
            [],
        )

    def test_restore_patches_period_and_unbans(self):
        self.install_user()
        self.transport.add('GET', '/rest/v1/user_purge_receipts?select=', ok([]))
        self.transport.add(
            'PATCH',
            '/rest/v1/user_suspension_periods?user_id=eq.',
            ok([{'user_id': TARGET_ID}]),
        )
        self.transport.add(
            'PUT',
            f'/auth/v1/admin/users/{TARGET_ID}',
            ok({'id': TARGET_ID}),
        )
        console = self.console(inputs=['yes'])
        outcome = MODULE.command_restore(self.client(), console, TARGET_EMAIL)
        self.assertTrue(outcome.data['restored_period'])
        self.assertEqual(
            self.transport.calls_for(f'/auth/v1/admin/users/{TARGET_ID}')[-1].json,
            {'ban_duration': 'none'},
        )

    def test_restore_refuses_pending_purge(self):
        self.install_user()
        self.transport.add(
            'GET',
            '/rest/v1/user_purge_receipts?select=',
            ok([{'user_id': TARGET_ID, 'status': 'pending'}]),
        )
        console = self.console(inputs=['yes'])
        with self.assertRaises(MODULE.ApiError) as caught:
            MODULE.command_restore(self.client(), console, TARGET_EMAIL)
        self.assertIn('进行中的彻底注销回执', str(caught.exception))
        self.assertFalse(self.transport.urls_containing('user_suspension_periods?user_id=eq.'))

    def test_reset_password_with_cli_password_skips_prompt(self):
        self.install_user()
        self.transport.add(
            'PUT',
            f'/auth/v1/admin/users/{TARGET_ID}',
            ok({'id': TARGET_ID}),
        )
        console = self.console()
        outcome = MODULE.command_reset_password(
            self.client(),
            console,
            TARGET_EMAIL,
            password='new-password-1',
            assume_yes=True,
        )
        self.assertEqual(outcome.data['status'], 'password_reset')
        self.assertEqual(
            self.transport.calls_for(f'/auth/v1/admin/users/{TARGET_ID}')[-1].json,
            {'password': 'new-password-1'},
        )

    def test_reset_password_prompts_twice_and_never_echoes(self):
        self.install_user()
        self.transport.add(
            'PUT',
            f'/auth/v1/admin/users/{TARGET_ID}',
            ok({'id': TARGET_ID}),
        )
        console = self.console(
            inputs=['yes'],
            passwords=['new-password-1', 'new-password-1'],
        )
        outcome = MODULE.command_reset_password(self.client(), console, TARGET_EMAIL)
        self.assertNotIn('new-password-1', '\n'.join(outcome.lines))
        self.assertNotIn('new-password-1', self.output)
        self.assertNotIn('new-password-1', self.error)

    def test_reset_password_mismatch_stops_before_http(self):
        self.install_user()
        console = self.console(
            inputs=[],
            passwords=['new-password-1', 'new-password-2'],
        )
        with self.assertRaises(MODULE.AdminToolError) as caught:
            MODULE.command_reset_password(self.client(), console, TARGET_EMAIL)
        self.assertIn('不一致', str(caught.exception))
        self.assertFalse(self.transport.urls_containing(f'/auth/v1/admin/users/{TARGET_ID}'))

    def test_reset_password_length_bounds(self):
        self.install_user()
        console = self.console(inputs=[], passwords=['short', 'short'])
        with self.assertRaises(MODULE.AdminToolError) as caught:
            MODULE.command_reset_password(self.client(), console, TARGET_EMAIL)
        self.assertIn('8 至 256', str(caught.exception))

    def test_reset_password_requires_manual_confirmation(self):
        self.install_user()
        console = self.console(
            inputs=['no'],
            passwords=['new-password-1', 'new-password-1'],
        )
        with self.assertRaises(MODULE.OperationCancelled):
            MODULE.command_reset_password(self.client(), console, TARGET_EMAIL)
        self.assertFalse(self.transport.urls_containing(f'/auth/v1/admin/users/{TARGET_ID}'))


# --------------------------------------------------------------------------
# Delete / purge
# --------------------------------------------------------------------------


class DeleteUserCommandTest(Harness):
    def client(self):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )

    def console(self, inputs=None):
        script = list(inputs or [])

        def input_fn(label):
            if not script:
                raise EOFError
            return script.pop(0)

        return MODULE.ConsoleIO(self.out, self.err, input_fn, lambda label: '')

    def install_delete_flow(
        self,
        *,
        transport=None,
        users=None,
        receipt_rows=None,
        receipt_repeat=False,
        eligibility_rows=None,
        admin_ids=(),
        completed=None,
    ):
        transport = self.transport if transport is None else transport
        transport.add(
            'GET',
            '/rest/v1/registration_eligibility?select=id&used_user_id=eq.',
            ok(
                [{'id': ELIGIBILITY_ID}]
                if eligibility_rows is None
                else list(eligibility_rows)
            ),
        )
        install_user_data(
            transport,
            [user_row()] if users is None else list(users),
            admins=admin_ids,
        )
        transport.add(
            'GET',
            '/rest/v1/user_purge_receipts?select=',
            ok(list(receipt_rows or [])),
            repeat=receipt_repeat,
        )
        transport.add(
            'POST',
            '/rest/v1/user_purge_receipts?on_conflict=user_id',
            ok(
                [
                    {
                        'user_id': TARGET_ID,
                        'status': 'pending',
                        'completed_at': None,
                    }
                ]
            ),
        )
        transport.add(
            'POST',
            '/rest/v1/rpc/admin_delete_user_business_data',
            empty(204),
        )
        transport.add(
            'DELETE',
            f'/auth/v1/admin/users/{TARGET_ID}',
            empty(204),
        )
        transport.add(
            'POST',
            '/rest/v1/rpc/admin_complete_user_purge',
            ok(
                completed
                or {
                    'user_id': TARGET_ID,
                    'status': 'completed',
                    'purged_at': '2026-11-22T00:00:00+00:00',
                }
            ),
        )
        return transport

    def relevant_urls(self):
        return [
            call.url
            for call in self.transport.calls
            if 'admin_delete_user_business_data' in call.url
            or 'admin_complete_user_purge' in call.url
            or f'/auth/v1/admin/users/{TARGET_ID}' in call.url
        ]

    def test_immediate_delete_follows_four_step_contract(self):
        self.install_delete_flow()
        console = self.console(inputs=[TARGET_EMAIL])
        outcome = MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertEqual(outcome.data['status'], 'completed')
        self.assertEqual(outcome.data['purged_at'], '2026-11-22T00:00:00+00:00')
        self.assertTrue(outcome.data['receipt_created'])
        self.assertFalse(outcome.data['receipt_reused'])
        self.assertIn('已完成彻底注销', '\n'.join(outcome.lines))

        receipt_call = self.transport.calls_for(
            '/rest/v1/user_purge_receipts?on_conflict=user_id'
        )[0]
        self.assertEqual(
            receipt_call.json,
            {
                'user_id': TARGET_ID,
                'status': 'pending',
                'requested_at': receipt_call.json['requested_at'],
                'requested_by': None,
                'eligibility_id': ELIGIBILITY_ID,
                'business_data_deleted': False,
                'completed_at': None,
            },
        )
        self.assertEqual(
            receipt_call.headers['Prefer'],
            'resolution=merge-duplicates,return=representation',
        )

        urls = self.relevant_urls()
        self.assertEqual(
            urls,
            [
                f'{PROJECT_URL}/rest/v1/rpc/admin_delete_user_business_data',
                f'{PROJECT_URL}/auth/v1/admin/users/{TARGET_ID}',
                f'{PROJECT_URL}/rest/v1/rpc/admin_complete_user_purge',
            ],
        )
        self.assertEqual(
            self.transport.calls_for(
                '/rest/v1/rpc/admin_delete_user_business_data'
            )[0].json,
            {'p_user_id': TARGET_ID},
        )
        self.assertEqual(
            self.transport.calls_for(
                '/rest/v1/rpc/admin_complete_user_purge'
            )[0].json,
            {'p_user_id': TARGET_ID},
        )
        self.assertFalse(self.transport.urls_containing('admin_begin_user_purge'))

    def test_delete_legacy_admin_user_is_not_blocked(self):
        self.install_delete_flow(admin_ids=[TARGET_ID])
        console = self.console(inputs=[TARGET_EMAIL])
        outcome = MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertTrue(outcome.data['legacy_admin'])
        self.assertIn('遗留 app_admins：有', '\n'.join(outcome.lines))
        self.assertEqual(outcome.data['status'], 'completed')
        self.assertFalse(self.transport.urls_containing('admin_begin_user_purge'))

    def test_completed_receipt_short_circuits(self):
        self.install_delete_flow(
            receipt_rows=[
                {
                    'user_id': TARGET_ID,
                    'status': 'completed',
                    'completed_at': '2026-11-22T00:00:00+00:00',
                }
            ]
        )
        console = self.console(inputs=[TARGET_EMAIL])
        outcome = MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertTrue(outcome.data['receipt_reused'])
        self.assertIn('已存在 completed 回执', '\n'.join(outcome.lines))
        self.assertFalse(
            self.transport.urls_containing('/rest/v1/user_purge_receipts?on_conflict=user_id')
        )
        self.assertFalse(self.transport.urls_containing('admin_delete_user_business_data'))
        self.assertFalse(self.transport.urls_containing(f'/auth/v1/admin/users/{TARGET_ID}'))

    def test_pending_receipt_is_reused(self):
        self.install_delete_flow(
            receipt_rows=[{'user_id': TARGET_ID, 'status': 'pending'}]
        )
        console = self.console(inputs=[TARGET_EMAIL])
        outcome = MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertFalse(outcome.data['receipt_created'])
        self.assertFalse(
            self.transport.urls_containing('/rest/v1/user_purge_receipts?on_conflict=user_id')
        )
        self.assertFalse(
            self.transport.urls_containing(
                'registration_eligibility?select=id&used_user_id=eq.'
            )
        )

    def test_pending_receipt_with_deleted_business_data_skips_rpc(self):
        self.install_delete_flow(
            receipt_rows=[
                {
                    'user_id': TARGET_ID,
                    'status': 'pending',
                    'business_data_deleted': True,
                }
            ]
        )
        console = self.console(inputs=[TARGET_EMAIL])
        outcome = MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertEqual(outcome.data['status'], 'completed')
        self.assertFalse(
            self.transport.urls_containing('admin_delete_user_business_data')
        )
        self.assertTrue(
            self.transport.urls_containing(f'/auth/v1/admin/users/{TARGET_ID}')
        )

    def test_typed_confirmation_mismatch_cancels_without_purge(self):
        self.install_delete_flow()
        console = self.console(inputs=['wrong@example.com'])
        with self.assertRaises(MODULE.OperationCancelled) as caught:
            MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertIn('不一致', str(caught.exception))
        self.assertFalse(self.transport.urls_containing('user_purge_receipts'))

    def test_confirmation_is_case_insensitive_and_trimmed(self):
        self.install_delete_flow()
        console = self.console(inputs=['  PERSON@EXAMPLE.COM  '])
        outcome = MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertEqual(outcome.data['status'], 'completed')

    def test_yes_skips_typed_confirmation(self):
        self.install_delete_flow()
        console = self.console()
        outcome = MODULE.command_delete_user(
            self.client(), console, TARGET_EMAIL, assume_yes=True
        )
        self.assertEqual(outcome.data['status'], 'completed')

    def test_uuid_confirmation_when_target_has_no_email(self):
        row = user_row()
        row['email'] = None
        self.install_delete_flow(users=[row])
        console = self.console(inputs=[TARGET_ID])
        outcome = MODULE.command_delete_user(
            self.client(), console, TARGET_ID, assume_yes=False
        )
        self.assertEqual(outcome.data['user_id'], TARGET_ID)

    def test_invalid_completion_receipt_is_rejected(self):
        self.install_delete_flow(
            completed={
                'user_id': OTHER_ID,
                'status': 'completed',
                'purged_at': '2026-11-22T00:00:00+00:00',
            }
        )
        console = self.console(inputs=[TARGET_EMAIL])
        with self.assertRaises(MODULE.ApiError) as caught:
            MODULE.command_delete_user(self.client(), console, TARGET_EMAIL)
        self.assertIn('绑定了其他用户', str(caught.exception))

    def test_incomplete_completion_receipt_is_rejected(self):
        for payload in (
            {'user_id': TARGET_ID, 'status': 'pending', 'purged_at': None},
            {'user_id': TARGET_ID, 'status': 'completed', 'purged_at': None},
            ['not-an-object'],
        ):
            # Each case gets its own RouteTransport instead of re-running
            # setUp(): the fixture never leaks responses between subtests and
            # no second TemporaryDirectory or mock patch is stacked.
            with self.subTest(payload=payload):
                transport = self.install_delete_flow(
                    transport=RouteTransport(),
                    completed=payload,
                )
                client = MODULE.SupabaseAdminClient(
                    MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
                    transport,
                )
                with self.assertRaises(MODULE.AdminToolError):
                    MODULE.command_delete_user(
                        client,
                        self.console(inputs=[TARGET_EMAIL]),
                        TARGET_EMAIL,
                    )

    def install_resume_flow(self, *, receipt, transport=None):
        """A half-finished purge: no Auth users left, only the receipt row."""

        return self.install_delete_flow(
            transport=RouteTransport() if transport is None else transport,
            users=[],
            receipt_rows=[receipt],
            receipt_repeat=True,
        )

    def resume_client(self, transport):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            transport,
        )

    def test_resumes_pending_receipt_after_auth_identity_is_deleted(self):
        transport = self.install_resume_flow(
            receipt={
                'user_id': TARGET_ID,
                'status': 'pending',
                'completed_at': None,
                'business_data_deleted': True,
            }
        )
        # A retried Auth deletion is a 404 no-op, not a failure.
        transport.add('DELETE', f'/auth/v1/admin/users/{TARGET_ID}', empty(404))
        outcome = MODULE.command_delete_user(
            self.resume_client(transport),
            self.console(),
            TARGET_ID,
            assume_yes=True,
        )
        self.assertEqual(outcome.data['status'], 'completed')
        self.assertEqual(outcome.data['user_id'], TARGET_ID)
        self.assertEqual(outcome.data['email'], '')
        self.assertEqual(outcome.data['purged_at'], '2026-11-22T00:00:00+00:00')
        self.assertTrue(outcome.data['resumed'])
        self.assertFalse(outcome.data['receipt_created'])
        self.assertFalse(outcome.data['receipt_reused'])
        self.assertIn('Auth 身份已删除', '\n'.join(outcome.lines))
        self.assertEqual(
            transport.urls_containing('admin_delete_user_business_data'), []
        )
        complete_calls = transport.calls_for(
            '/rest/v1/rpc/admin_complete_user_purge'
        )
        self.assertEqual(len(complete_calls), 1)
        self.assertEqual(complete_calls[0].json, {'p_user_id': TARGET_ID})

    def test_resumes_completed_receipt_without_repeating_the_purge(self):
        transport = self.install_resume_flow(
            receipt={
                'user_id': TARGET_ID,
                'status': 'completed',
                'completed_at': '2026-11-22T00:00:00+00:00',
            }
        )
        outcome = MODULE.command_delete_user(
            self.resume_client(transport),
            self.console(),
            TARGET_ID,
            assume_yes=True,
        )
        self.assertEqual(outcome.data['status'], 'completed')
        self.assertTrue(outcome.data['receipt_reused'])
        self.assertTrue(outcome.data['resumed'])
        self.assertIn('已存在 completed 回执', '\n'.join(outcome.lines))
        self.assertEqual(
            transport.urls_containing('admin_delete_user_business_data'), []
        )
        self.assertEqual(
            transport.urls_containing('admin_complete_user_purge'), []
        )

    def test_resume_normalizes_an_uppercase_uuid(self):
        transport = self.install_resume_flow(
            receipt={
                'user_id': TARGET_ID,
                'status': 'pending',
                'completed_at': None,
                'business_data_deleted': True,
            }
        )
        transport.add('DELETE', f'/auth/v1/admin/users/{TARGET_ID}', empty(404))
        outcome = MODULE.command_delete_user(
            self.resume_client(transport),
            self.console(),
            TARGET_ID.upper(),
            assume_yes=True,
        )
        self.assertEqual(outcome.data['user_id'], TARGET_ID)
        self.assertEqual(outcome.data['status'], 'completed')

    def test_unknown_uuid_without_receipt_reports_not_found(self):
        transport = self.install_delete_flow(
            transport=RouteTransport(),
            users=[],
        )
        with self.assertRaises(MODULE.UserNotFoundError) as caught:
            MODULE.command_delete_user(
                self.resume_client(transport),
                self.console(),
                TARGET_ID,
                assume_yes=True,
            )
        self.assertIn('找不到 UUID', str(caught.exception))
        self.assertEqual(
            transport.urls_containing('admin_complete_user_purge'), []
        )

    def test_unknown_email_never_queries_purge_receipts(self):
        transport = self.install_delete_flow(
            transport=RouteTransport(),
            users=[],
        )
        with self.assertRaises(MODULE.UserNotFoundError) as caught:
            MODULE.command_delete_user(
                self.resume_client(transport),
                self.console(),
                'nobody@example.com',
                assume_yes=True,
            )
        self.assertIn('找不到邮箱', str(caught.exception))
        self.assertEqual(
            transport.urls_containing('user_purge_receipts'), []
        )


# --------------------------------------------------------------------------
# Cloud data
# --------------------------------------------------------------------------


class CloudDataTest(Harness):
    def client(self):
        return MODULE.SupabaseAdminClient(
            MODULE.SupabaseConfig(url=PROJECT_URL, secret_key=SECRET_KEY),
            self.transport,
        )

    def console(self, inputs=None):
        script = list(inputs or [])

        def input_fn(label):
            if not script:
                raise EOFError
            return script.pop(0)

        return MODULE.ConsoleIO(self.out, self.err, input_fn, lambda label: '')

    def install_cloud_data(self):
        install_user_data(
            self.transport,
            [user_row()],
            snapshots=[snapshot_row()],
            history={TARGET_ID: 3},
            uploads={TARGET_ID: 2},
            mcp=[
                {
                    'user_id': TARGET_ID,
                    'expires_at': '2126-01-01T00:00:00+00:00',
                    'revoked_at': None,
                }
            ],
            profiles=[
                {
                    'user_id': TARGET_ID,
                    'display_name': '小明',
                    'time_zone_id': 'Asia/Shanghai',
                }
            ],
        )

    def test_cloud_data_all_users_renders_summary(self):
        self.install_cloud_data()
        console = self.console()
        outcome = MODULE.command_cloud_data(self.client(), console)
        text = '\n'.join(outcome.lines)
        self.assertIn('云端业务数据：1 个账号', text)
        self.assertIn('r7', text)
        self.assertIn('Schema', text)
        self.assertIn('120', text)
        self.assertIn('有效 1', text)
        self.assertIn('历史版本 3 行', text)
        self.assertIn('上传队列 2 行', text)

    def test_cloud_data_specific_user(self):
        self.install_cloud_data()
        console = self.console()
        outcome = MODULE.command_cloud_data(self.client(), console, TARGET_EMAIL)
        self.assertIn(TARGET_EMAIL, outcome.lines[0])
        self.assertEqual(outcome.data['users'][0]['cloud_snapshot']['revision'], 7)

    def test_clear_cloud_data_deletes_three_tables_in_order(self):
        self.install_cloud_data()
        self.transport.add(
            'DELETE',
            '/rest/v1/cloud_business_snapshot_upload_requests?user_id=eq.',
            ok([{'user_id': TARGET_ID}]),
        )
        self.transport.add(
            'DELETE',
            '/rest/v1/cloud_business_snapshot_history?user_id=eq.',
            ok([{'user_id': TARGET_ID}, {'user_id': TARGET_ID}]),
        )
        self.transport.add(
            'DELETE',
            '/rest/v1/cloud_business_snapshots?user_id=eq.',
            ok([{'user_id': TARGET_ID}]),
        )
        console = self.console(inputs=['yes'])
        outcome = MODULE.command_clear_cloud_data(self.client(), console, TARGET_EMAIL)
        deletes = [call.url for call in self.transport.calls if call.method == 'DELETE']
        self.assertEqual(
            deletes,
            [
                f'{PROJECT_URL}/rest/v1/cloud_business_snapshot_upload_requests?user_id=eq.{TARGET_ID}',
                f'{PROJECT_URL}/rest/v1/cloud_business_snapshot_history?user_id=eq.{TARGET_ID}',
                f'{PROJECT_URL}/rest/v1/cloud_business_snapshots?user_id=eq.{TARGET_ID}',
            ],
        )
        self.assertTrue(outcome.data['auth_identity_kept'])
        self.assertIn('已清空', '\n'.join(outcome.lines))

    def test_clear_cloud_data_cancelled(self):
        self.install_cloud_data()
        console = self.console(inputs=['no'])
        with self.assertRaises(MODULE.OperationCancelled):
            MODULE.command_clear_cloud_data(self.client(), console, TARGET_EMAIL)
        self.assertFalse(
            [call for call in self.transport.calls if call.method == 'DELETE']
        )


# --------------------------------------------------------------------------
# Interactive menu
# --------------------------------------------------------------------------


class MenuTest(Harness):
    def test_zero_exits_and_prints_owner_banner(self):
        install_user_data(self.transport, [])
        code, _ = self.run_main([], inputs=['0'])
        self.assertEqual(code, 0)
        self.assertIn('项目主机：project.supabase.co', self.output)
        self.assertIn('项目主直连模式 (Owner)', self.output)
        self.assertIn('SUPABASE_SECRET_KEY', self.output)
        self.assertNotIn(SECRET_KEY, self.output)

    def test_unknown_choice_reports_error_then_exits(self):
        install_user_data(self.transport, [])
        code, _ = self.run_main([], inputs=['12', '0'])
        self.assertEqual(code, 0)
        self.assertIn('无效选项', self.error)

    def test_menu_lists_all_eleven_capabilities_and_zero(self):
        install_user_data(self.transport, [])
        self.run_main([], inputs=['0'])
        for number in range(1, 12):
            self.assertIn(f'  {number}. ', self.output)
        self.assertIn('  0. 退出', self.output)

    def test_create_user_flow_generates_password(self):
        self.transport.add('GET', '&identifier=eq.', ok([]))
        self.transport.add('POST', '/rest/v1/registration_eligibility', ok([eligibility_row()], 201))
        self.transport.add('POST', '/auth/v1/admin/users', ok({'id': TARGET_ID}, 201))
        self.transport.add(
            'POST',
            '/rest/v1/profile_accounts?on_conflict=user_id',
            ok([{'user_id': TARGET_ID, 'display_name': '小明'}]),
        )
        code, _ = self.run_main(
            [],
            inputs=['2', TARGET_EMAIL, '小明', '0'],
            passwords=[''],
        )
        self.assertEqual(code, 0)
        self.assertEqual(
            self.transport.calls_for('/auth/v1/admin/users')[-1].json['user_metadata'],
            {'display_name': '小明'},
        )
        self.assertIn('初始密码：', self.output)
        self.assertNotIn(SECRET_KEY, self.output)

    def test_delete_flow_prompts_target_and_completes(self):
        self.transport.add(
            'GET',
            '/rest/v1/registration_eligibility?select=id&used_user_id=eq.',
            ok([{'id': ELIGIBILITY_ID}]),
        )
        install_user_data(self.transport, [user_row()])
        self.transport.add('GET', '/rest/v1/user_purge_receipts?select=', ok([]))
        self.transport.add(
            'POST',
            '/rest/v1/user_purge_receipts?on_conflict=user_id',
            ok([{'user_id': TARGET_ID, 'status': 'pending', 'completed_at': None}]),
        )
        self.transport.add('POST', '/rest/v1/rpc/admin_delete_user_business_data', empty())
        self.transport.add('DELETE', f'/auth/v1/admin/users/{TARGET_ID}', empty())
        self.transport.add(
            'POST',
            '/rest/v1/rpc/admin_complete_user_purge',
            ok(
                {
                    'user_id': TARGET_ID,
                    'status': 'completed',
                    'purged_at': '2026-11-22T00:00:00+00:00',
                }
            ),
        )
        code, _ = self.run_main(
            [],
            inputs=['9', TARGET_EMAIL, TARGET_EMAIL, '0'],
        )
        self.assertEqual(code, 0)
        self.assertIn('已完成彻底注销', self.output)

    def test_delete_flow_declining_returns_to_menu(self):
        install_user_data(self.transport, [user_row()])
        code, _ = self.run_main(
            [],
            inputs=['9', TARGET_EMAIL, 'wrong@example.com', '0'],
        )
        self.assertEqual(code, 0)
        self.assertIn('已取消', self.error)
        self.assertFalse(self.transport.urls_containing('user_purge_receipts'))

    def test_reset_password_flow(self):
        install_user_data(self.transport, [user_row()])
        self.transport.add(
            'PUT',
            f'/auth/v1/admin/users/{TARGET_ID}',
            ok({'id': TARGET_ID}),
        )
        code, _ = self.run_main(
            [],
            inputs=['8', TARGET_EMAIL, 'yes', '0'],
            passwords=['new-password-1', 'new-password-1'],
        )
        self.assertEqual(code, 0)
        self.assertEqual(
            self.transport.calls_for(f'/auth/v1/admin/users/{TARGET_ID}')[-1].json,
            {'password': 'new-password-1'},
        )
        self.assertNotIn('new-password-1', self.output)


# --------------------------------------------------------------------------
# CLI entry point
# --------------------------------------------------------------------------


class MainTest(Harness):
    def test_help_exits_zero_and_lists_commands(self):
        with contextlib.redirect_stdout(self.out):
            with self.assertRaises(SystemExit) as caught:
                MODULE.main(['--help'], transport=self.transport)
        self.assertEqual(caught.exception.code, 0)
        for command in (
            'users',
            'create-user',
            'eligibilities',
            'grant',
            'revoke',
            'suspend',
            'restore',
            'reset-password',
            'delete-user',
            'cloud-data',
            'clear-cloud-data',
        ):
            self.assertIn(command, self.output)
        self.assertEqual(self.transport.calls, [])

    def test_users_command_succeeds_and_never_reads_login(self):
        install_user_data(self.transport, [user_row()])
        code, prompts = self.run_main(['users'])
        self.assertEqual(code, 0)
        self.assertEqual(prompts, [])
        self.assertIn(TARGET_EMAIL, self.output)
        self.assertNotIn('管理员邮箱', self.output)
        self.assertNotIn('管理员密码', self.output)
        self.assertFalse(self.transport.urls_containing('/auth/v1/token'))

    def test_env_file_option_after_subcommand(self):
        install_user_data(self.transport, [user_row()])
        code, _ = self.run_main(['users', '--env-file', str(self.env_file)])
        self.assertEqual(code, 0)

    def test_equality_flags_are_accepted_for_email_targets(self):
        self.transport.add('GET', '&identifier=eq.', ok([]))
        self.transport.add(
            'POST',
            '/rest/v1/registration_eligibility',
            ok([eligibility_row()], 201),
        )
        self.transport.add(
            'POST',
            '/auth/v1/admin/users',
            ok({'id': TARGET_ID}, 201),
        )
        code, _ = self.run_main(
            [
                'create-user',
                '--email',
                TARGET_EMAIL,
                '--password',
                'initial-password',
                '--no-eligibility',
            ]
        )
        self.assertEqual(code, 0)
        self.assertEqual(
            self.transport.calls_for('/auth/v1/admin/users')[-1].json['email'],
            TARGET_EMAIL,
        )
        self.assertEqual(
            self.transport.calls_for('/rest/v1/registration_eligibility'), []
        )

    def test_missing_config_exits_two_without_http(self):
        empty = self.root / 'empty.env'
        empty.write_text('# no values\n', encoding='utf-8')
        code, _ = self.run_main(
            ['--env-file', str(empty), 'users'],
            environ={},
        )
        self.assertEqual(code, 2)
        self.assertEqual(self.transport.calls, [])
        self.assertIn('SUPABASE_SECRET_KEY', self.error)

    def test_default_env_missing_uses_environment(self):
        with mock.patch.object(MODULE, 'DEFAULT_ENV_FILE', self.root / 'missing.env'):
            install_user_data(self.transport, [user_row()])
            code, _ = self.run_main(
                ['users'],
                environ={
                    'SUPABASE_URL': PROJECT_URL,
                    'SUPABASE_SECRET_KEY': SECRET_KEY,
                },
            )
        self.assertEqual(code, 0)

    def test_secret_key_is_never_printed_or_sent_as_bearer(self):
        install_user_data(self.transport, [user_row()])
        code, _ = self.run_main(['users'])
        self.assertEqual(code, 0)
        output = self.output + self.error
        self.assertNotIn(SECRET_KEY, output)
        for call in self.transport.calls:
            self.assertEqual(call.headers['apikey'], SECRET_KEY)
            self.assertNotIn('Authorization', call.headers)
            self.assertNotIn('Bearer', ' '.join(call.headers.values()))

    def test_cloud_error_redacts_secret(self):
        self.transport.add(
            'GET',
            '/auth/v1/admin/users?page=1',
            ok({'message': f'failed for {SECRET_KEY}'}, 500),
        )
        code, _ = self.run_main(['users'])
        self.assertEqual(code, 1)
        self.assertNotIn(SECRET_KEY, self.error)
        self.assertIn('***', self.error)

    def test_network_error_exits_one(self):
        self.transport.add(
            'GET',
            '/auth/v1/admin/users?page=1',
            MODULE.TransportError('无法连接云端服务：dns failure'),
        )
        code, _ = self.run_main(['users'])
        self.assertEqual(code, 1)
        self.assertIn('无法连接云端服务', self.error)

    def test_keyboard_interrupt_exits_130(self):
        install_user_data(self.transport, [user_row()])

        def interrupted(label):
            raise KeyboardInterrupt

        code = MODULE.main(
            ['suspend', TARGET_EMAIL],
            transport=self.transport,
            environ={},
            out=self.out,
            err=self.err,
            input_fn=interrupted,
            getpass_fn=lambda label: '',
        )
        self.assertEqual(code, 130)
        self.assertIn('已中断', self.error)

    def test_grant_command_calls_rest_and_prints_status(self):
        self.transport.add('GET', '&identifier=eq.', ok([]))
        self.transport.add(
            'POST',
            '/rest/v1/registration_eligibility',
            ok([eligibility_row()], 201),
        )
        code, _ = self.run_main(['grant', 'Person@Example.com'])
        self.assertEqual(code, 0)
        self.assertEqual(
            self.transport.calls_for('/rest/v1/registration_eligibility')[-1].json[
                'identifier'
            ],
            TARGET_EMAIL,
        )
        self.assertIn('已发放注册资格', self.output)

    def test_delete_user_command_requires_typed_email(self):
        self.transport.add(
            'GET',
            '/rest/v1/registration_eligibility?select=id&used_user_id=eq.',
            ok([{'id': ELIGIBILITY_ID}]),
        )
        install_user_data(self.transport, [user_row()])
        self.transport.add('GET', '/rest/v1/user_purge_receipts?select=', ok([]))
        self.transport.add(
            'POST',
            '/rest/v1/user_purge_receipts?on_conflict=user_id',
            ok([{'user_id': TARGET_ID, 'status': 'pending', 'completed_at': None}]),
        )
        self.transport.add('POST', '/rest/v1/rpc/admin_delete_user_business_data', empty())
        self.transport.add('DELETE', f'/auth/v1/admin/users/{TARGET_ID}', empty())
        self.transport.add(
            'POST',
            '/rest/v1/rpc/admin_complete_user_purge',
            ok(
                {
                    'user_id': TARGET_ID,
                    'status': 'completed',
                    'purged_at': '2026-11-22T00:00:00+00:00',
                }
            ),
        )
        code, prompts = self.run_main(
            ['delete-user', TARGET_EMAIL],
            inputs=[TARGET_EMAIL],
        )
        self.assertEqual(code, 0)
        self.assertIn('逐字输入目标邮箱', prompts[-1])
        self.assertEqual(
            self.transport.calls_for('/rest/v1/rpc/admin_complete_user_purge')[0].json,
            {'p_user_id': TARGET_ID},
        )

    def test_delete_user_yes_skips_prompt(self):
        self.transport.add(
            'GET',
            '/rest/v1/registration_eligibility?select=id&used_user_id=eq.',
            ok([{'id': ELIGIBILITY_ID}]),
        )
        install_user_data(self.transport, [user_row()])
        self.transport.add('GET', '/rest/v1/user_purge_receipts?select=', ok([]))
        self.transport.add(
            'POST',
            '/rest/v1/user_purge_receipts?on_conflict=user_id',
            ok([{'user_id': TARGET_ID, 'status': 'pending', 'completed_at': None}]),
        )
        self.transport.add('POST', '/rest/v1/rpc/admin_delete_user_business_data', empty())
        self.transport.add('DELETE', f'/auth/v1/admin/users/{TARGET_ID}', empty())
        self.transport.add(
            'POST',
            '/rest/v1/rpc/admin_complete_user_purge',
            ok(
                {
                    'user_id': TARGET_ID,
                    'status': 'completed',
                    'purged_at': '2026-11-22T00:00:00+00:00',
                }
            ),
        )
        code, prompts = self.run_main(
            ['delete-user', TARGET_EMAIL, '--yes'],
        )
        self.assertEqual(code, 0)
        self.assertEqual(prompts, [])

    def test_delete_user_wrong_typed_email_exits_cancelled(self):
        install_user_data(self.transport, [user_row()])
        code, _ = self.run_main(
            ['delete-user', TARGET_EMAIL],
            inputs=['wrong@example.com'],
        )
        self.assertEqual(code, 4)
        self.assertIn('已取消', self.error)
        self.assertFalse(self.transport.urls_containing('user_purge_receipts'))

    def test_json_output_is_valid_and_hides_secret(self):
        install_user_data(self.transport, [user_row()])
        code, _ = self.run_main(['users', '--json'])
        self.assertEqual(code, 0)
        payload = json.loads(self.output)
        self.assertTrue(payload['ok'])
        self.assertEqual(payload['command'], 'users')
        self.assertEqual(len(payload['data']['users']), 1)
        self.assertEqual(payload['data']['users'][0]['email'], TARGET_EMAIL)
        self.assertNotIn(SECRET_KEY, self.output + self.error)

    def test_json_dangerous_command_requires_yes(self):
        install_user_data(self.transport, [user_row()])
        code, _ = self.run_main(['delete-user', TARGET_EMAIL, '--json'])
        self.assertEqual(code, 2)
        payload = json.loads(self.error)
        self.assertFalse(payload['ok'])
        self.assertIn('--yes', payload['error']['message'])
        self.assertFalse(self.transport.urls_containing('user_purge_receipts'))

    def test_json_reset_password_without_password_never_prompts(self):
        install_user_data(self.transport, [user_row()])
        code, prompts = self.run_main(
            ['reset-password', TARGET_EMAIL, '--yes', '--json'],
        )
        self.assertEqual(code, MODULE.EXIT_CONFIG)
        payload = json.loads(self.error)
        self.assertFalse(payload['ok'])
        self.assertEqual(payload['command'], 'reset-password')
        self.assertIn('--password', payload['error']['message'])
        self.assertIn('--yes', payload['error']['message'])
        # No password prompt (getpass) and no HTTP: the failure is pre-flight.
        self.assertEqual(prompts, [])
        self.assertEqual(self.transport.calls, [])
        self.assertEqual(self.output, '')

    def test_auth_failure_exits_forbidden_without_leaking_secret(self):
        self.transport.add(
            'GET',
            '/auth/v1/admin/users?page=1',
            json_response({'message': 'invalid JWT'}, status=401),
        )
        code, _ = self.run_main(['users'])
        self.assertEqual(code, MODULE.EXIT_FORBIDDEN)
        self.assertIn('SUPABASE_SECRET_KEY', self.error)
        self.assertNotIn(SECRET_KEY, self.output + self.error)

    def test_json_error_goes_to_stderr_without_secret(self):
        install_user_data(self.transport, [])
        code, _ = self.run_main(
            [
                'reset-password',
                'nobody@example.com',
                '--password',
                'new-password-1',
                '--yes',
                '--json',
            ],
        )
        self.assertEqual(code, 1)
        payload = json.loads(self.error)
        self.assertFalse(payload['ok'])
        self.assertEqual(payload['command'], 'reset-password')
        self.assertIn('找不到邮箱', payload['error']['message'])
        self.assertNotIn(SECRET_KEY, self.error)
        self.assertEqual(self.output, '')

    def test_clear_cloud_data_json(self):
        install_user_data(
            self.transport,
            [user_row()],
            snapshots=[snapshot_row()],
        )
        for table in (
            'cloud_business_snapshot_upload_requests',
            'cloud_business_snapshot_history',
            'cloud_business_snapshots',
        ):
            self.transport.add(
                'DELETE',
                f'/rest/v1/{table}?user_id=eq.',
                ok([{'user_id': TARGET_ID}]),
            )
        code, _ = self.run_main(
            ['clear-cloud-data', TARGET_EMAIL, '--yes', '--json'],
        )
        self.assertEqual(code, 0)
        payload = json.loads(self.output)
        self.assertEqual(payload['command'], 'clear-cloud-data')
        self.assertTrue(payload['data']['auth_identity_kept'])
        self.assertNotIn(SECRET_KEY, self.output + self.error)


if __name__ == '__main__':
    unittest.main()
