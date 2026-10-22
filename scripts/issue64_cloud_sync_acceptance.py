#!/usr/bin/env python3
"""Prepare and serve isolated Issue 64 cloud-sync acceptance sessions.

Run from WSL at the repository root. The target is restricted to the disposable
Issue 64 project in .scratch/issue62/isolated-state.json. Management credentials
stay in .env and in memory; the generated Flutter control file is ACL-protected
for the current Windows user and is removed when the server exits.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import threading
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROJECT_STATE = ROOT / '.scratch/issue62/isolated-state.json'
PROJECT_NAME = 'Pacta issue64 disposable validation'
CONTROL_FILE = ROOT / '.dart_tool/issue64-cloud-control.json'
PORT = 30347


class AcceptanceProject:
    def __init__(self, config_path):
        self.env = self._read_env(config_path)
        self.access_token = self.env['SUPABASE_ACCESS_TOKEN']
        self.state = json.loads(PROJECT_STATE.read_text())
        self.project = self.state['project']
        self.ref = self.project['id']
        if self.project.get('name') != PROJECT_NAME:
            raise RuntimeError('The saved Supabase project is not the Issue 64 disposable target.')
        self.url = 'https://' + self.ref + '.supabase.co'
        self._assert_isolated_target()

    @staticmethod
    def _read_env(path):
        values = {}
        for line in path.read_text().splitlines():
            if '=' not in line or line.lstrip().startswith('#'):
                continue
            name, value = line.split('=', 1)
            values[name.strip()] = value.strip().strip('"').strip("'")
        return values

    def management(self, suffix, body=None, method=None):
        path = '/projects/' + self.ref + suffix
        payload = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            'https://api.supabase.com/v1' + path,
            data=payload,
            method=method,
            headers={
                'Authorization': 'Bearer ' + self.access_token,
                'Content-Type': 'application/json',
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raise RuntimeError(
                f'Supabase Management API returned HTTP {error.code}.'
            ) from None

    def _assert_isolated_target(self):
        details = self.management('')
        if details.get('name') != PROJECT_NAME:
            raise RuntimeError('Refusing to modify a project outside the Issue 64 disposable target.')

    def keys(self):
        keys = {item['name']: item['api_key'] for item in self.management('/api-keys')}
        if 'service_role' not in keys or 'anon' not in keys:
            raise RuntimeError('The isolated project does not expose the expected Auth API keys.')
        return keys

    def apply_migrations_and_check_rls(self):
        readiness = self.management(
            '/database/query',
            {
                'query': "select to_regclass('public.cloud_business_snapshots') as snapshots, "
                "to_regclass('public.national_focus_mcp_requests') as latest_schema;"
            },
        )[0]
        has_snapshot_schema = readiness['snapshots'] is not None
        has_latest_schema = readiness['latest_schema'] is not None
        if has_snapshot_schema and has_latest_schema:
            print('PASS required migrations are already applied', flush=True)
        elif has_snapshot_schema or has_latest_schema:
            raise RuntimeError('The isolated project has a partial migration set; refusing to reapply it.')
        else:
            for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
                sql = 'begin;\n' + path.read_text() + '\ncommit;'
                self.management('/database/query', {'query': sql})
                print('APPLIED ' + path.name.split('_', 1)[0], flush=True)

        keys = self.keys()
        admin = self.create_user(keys, 'rls')
        try:
            self.management(
                '/database/query',
                {'query': "insert into public.app_admins(user_id) values ('" + admin['id'] + "');"},
            )
            self.management(
                '/database/query',
                {'query': (ROOT / 'supabase/tests/cloud_business_snapshots.sql').read_text()},
            )
            print('PASS cloud_business_snapshots.sql rollback RLS/CAS probe', flush=True)
        finally:
            self.delete_user(keys, admin['id'])

    @staticmethod
    def _request(url, body=None, headers=None, method=None):
        payload = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            url,
            data=payload,
            method=method,
            headers=headers or {},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'Supabase Auth API returned HTTP {error.code}.') from None

    def create_user(self, keys, purpose):
        email = 'issue64-' + purpose + '-' + uuid.uuid4().hex + '@probe.invalid'
        password = secrets.token_urlsafe(36)
        service_headers = {
            'Authorization': 'Bearer ' + keys['service_role'],
            'apikey': keys['service_role'],
            'Content-Type': 'application/json',
        }
        self.management(
            '/database/query',
            {
                'query': "insert into public.registration_eligibility(identifier, identifier_type) "
                "values ('" + email + "', 'email');"
            },
        )
        user = None
        try:
            user = self._request(
                self.url + '/auth/v1/admin/users',
                {'email': email, 'password': password, 'email_confirm': True},
                service_headers,
                'POST',
            )
            anon_headers = {'apikey': keys['anon'], 'Content-Type': 'application/json'}
            session = self._request(
                self.url + '/auth/v1/token?grant_type=password',
                {'email': email, 'password': password},
                anon_headers,
                'POST',
            )
            return {'id': user['id'], 'refresh_token': session['refresh_token']}
        except Exception:
            if user is not None:
                try:
                    self.delete_user(keys, user['id'])
                except Exception:
                    pass
            raise
        finally:
            self.management(
                '/database/query',
                {
                    'query': "delete from public.registration_eligibility where identifier='"
                    + email
                    + "';"
                },
            )

    def delete_user(self, keys, user_id):
        self._request(
            self.url + '/auth/v1/admin/users/' + user_id,
            headers={
                'Authorization': 'Bearer ' + keys['service_role'],
                'apikey': keys['service_role'],
            },
            method='DELETE',
        )


def protect_with_windows_acl(path):
    windows_path = subprocess.check_output(
        ['wslpath', '-w', str(path)], text=True
    ).strip().replace("'", "''")
    sid = subprocess.check_output(
        [
            'powershell.exe',
            '-NoProfile',
            '-Command',
            '[Security.Principal.WindowsIdentity]::GetCurrent().User.Value',
        ],
        text=True,
    ).strip()
    if not sid.startswith('S-1-'):
        raise RuntimeError('Could not resolve the current Windows user for ACL protection.')
    result = subprocess.run(
        ['icacls.exe', windows_path, '/inheritance:r', '/grant:r', '*' + sid + ':F'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        raise RuntimeError('Could not protect the test control file with a Windows ACL.')


def serve(project):
    keys = project.keys()
    sessions = {}
    control = secrets.token_hex(32)
    server = None
    try:
        sessions['device'] = project.create_user(keys, 'device')
        sessions['concurrency'] = project.create_user(keys, 'concurrency')
        CONTROL_FILE.parent.mkdir(parents=True, exist_ok=True)
        os.umask(0o077)
        CONTROL_FILE.write_text(json.dumps({'MANUAL_SYNC_RUNTIME_CONTROL': control}))
        protect_with_windows_acl(CONTROL_FILE)

        from http.server import BaseHTTPRequestHandler, HTTPServer

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                if self.headers.get('X-Pacta-Acceptance') != control:
                    self.send_error(403)
                    return
                parsed = urllib.parse.urlparse(self.path)
                user = urllib.parse.parse_qs(parsed.query).get('user', [''])[0]
                if parsed.path != '/session' or user not in sessions:
                    self.send_error(404)
                    return
                session = sessions[user]
                body = json.dumps(
                    {
                        'url': project.url,
                        'publishableKey': keys['anon'],
                        'refreshToken': session['refresh_token'],
                        'userId': session['id'],
                    }
                ).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        server = HTTPServer(('127.0.0.1', PORT), Handler)
        stopping = threading.Event()

        def stop_server(*_):
            if not stopping.is_set():
                stopping.set()
                threading.Thread(target=server.shutdown, daemon=True).start()

        signal.signal(signal.SIGINT, stop_server)
        signal.signal(signal.SIGTERM, stop_server)
        print('READY isolated cloud sync test service', flush=True)
        print('CONTROL_FILE ' + str(CONTROL_FILE.relative_to(ROOT)), flush=True)
        print('ADB_REVERSE adb reverse tcp:30347 tcp:30347', flush=True)
        print('PHASES android-upload, windows-roundtrip, android-download, windows-conflict', flush=True)
        server.serve_forever()
    finally:
        if server is not None:
            server.server_close()
        for session in sessions.values():
            try:
                project.delete_user(keys, session['id'])
            except Exception:
                print('WARNING a temporary Auth user needs manual cleanup in the isolated project', flush=True)
        CONTROL_FILE.unlink(missing_ok=True)
        print('CLEANUP temporary Auth users and runtime control file', flush=True)


def delete_project(project):
    project.management('', method='DELETE')
    PROJECT_STATE.unlink(missing_ok=True)
    print('DELETED isolated Issue 64 project and local project state', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'serve', 'delete-project'))
    parser.add_argument('--config', type=Path, default=ROOT / '.env')
    args = parser.parse_args()
    project = AcceptanceProject(args.config)
    if args.action == 'prepare':
        project.apply_migrations_and_check_rls()
    elif args.action == 'serve':
        serve(project)
    else:
        delete_project(project)


if __name__ == '__main__':
    main()
