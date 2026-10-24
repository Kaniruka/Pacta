#!/usr/bin/env python3
"""Provision and serve the disposable Issue 71 cloud-discovery fixture.

Run from the repository root. Management credentials are read from .env and
kept in memory. Runtime sessions are exposed only on loopback behind a random
control token; the generated Flutter control file is ACL-protected.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROJECT_STATE = ROOT / '.scratch/issue71/isolated-state.json'
PROJECT_NAME = 'Pacta issue71 disposable validation'
CONTROL_FILE = ROOT / '.dart_tool/issue71-cloud-control.json'
PORT = 30347
MIGRATION_SENTINELS = (
    'public.cloud_business_snapshots',
    'public.national_focus_mcp_requests',
)


class AcceptanceProject:
    def __init__(self, config_path):
        self.env = read_env(config_path)
        self.access_token = self.env['SUPABASE_ACCESS_TOKEN']
        self.state = json.loads(PROJECT_STATE.read_text())
        self.project = self.state['project']
        self.ref = self.project['ref']
        if self.project.get('name') != PROJECT_NAME:
            raise RuntimeError('Saved project is not the Issue 71 disposable target.')
        self.url = 'https://' + self.ref + '.supabase.co'
        self.assert_isolated_target()

    def management(self, suffix, body=None, method=None):
        payload = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            'https://api.supabase.com/v1/projects/' + self.ref + suffix,
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
            raise RuntimeError(f'Supabase Management API returned HTTP {error.code}.') from None

    def assert_isolated_target(self):
        details = self.management('')
        if details.get('name') != PROJECT_NAME:
            raise RuntimeError('Refusing to touch a project outside the Issue 71 disposable target.')

    def keys(self):
        keys = {item['name']: item['api_key'] for item in self.management('/api-keys')}
        if 'service_role' not in keys or 'anon' not in keys:
            raise RuntimeError('Disposable project does not expose expected Auth API keys.')
        return keys

    def apply_migrations_and_probe(self):
        sentinels = ', '.join(
            "to_regclass('" + name + "') as s" + str(index)
            for index, name in enumerate(MIGRATION_SENTINELS)
        )
        readiness = self.management('/database/query', {'query': 'select ' + sentinels + ';'})[0]
        present = [readiness['s' + str(index)] is not None for index in range(len(MIGRATION_SENTINELS))]
        migrations = sorted((ROOT / 'supabase/migrations').glob('*.sql'))
        if all(present):
            print('PASS required migration sentinels already exist', flush=True)
        elif any(present):
            raise RuntimeError('Disposable project has a partial migration set; refusing to reapply.')
        else:
            for path in migrations:
                sql = 'begin;\n' + path.read_text() + '\ncommit;'
                self.management('/database/query', {'query': sql})
                print('APPLIED ' + path.name.split('_', 1)[0], flush=True)

        keys = self.keys()
        admin = self.create_user(keys, 'rls-admin')
        try:
            self.management(
                '/database/query',
                {'query': "insert into public.app_admins(user_id) values ('" + admin['id'] + "');"},
            )
            self.management(
                '/database/query',
                {'query': (ROOT / 'supabase/tests/cloud_business_snapshots.sql').read_text()},
            )
            print('PASS rollback-only cloud_business_snapshots.sql (RLS/CAS)', flush=True)
        finally:
            self.delete_user(keys, admin['id'])

        self.run_live_read_probe(keys)

    def _request(self, url, body=None, headers=None, method=None):
        payload = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(url, data=payload, method=method, headers=headers or {})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    raw = response.read()
                    return json.loads(raw) if raw else None
            except urllib.error.HTTPError as error:
                if error.code >= 500 and attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                raise RuntimeError(f'Supabase Auth/Data API returned HTTP {error.code}.') from None
            except (urllib.error.URLError, TimeoutError, OSError):
                if attempt == 3:
                    raise RuntimeError('Supabase Auth/Data API did not complete after network retries.') from None
                time.sleep(2 ** attempt)

    def create_user(self, keys, purpose):
        email = 'issue71-' + purpose + '-' + uuid.uuid4().hex + '@probe.invalid'
        password = secrets.token_urlsafe(36)
        service_headers = {
            'Authorization': 'Bearer ' + keys['service_role'],
            'apikey': keys['service_role'],
            'Content-Type': 'application/json',
        }
        self.management(
            '/database/query',
            {'query': "insert into public.registration_eligibility(identifier, identifier_type) "
                      "values ('" + email + "', 'email');"},
        )
        user = None
        try:
            user = self._request(
                self.url + '/auth/v1/admin/users',
                {'email': email, 'password': password, 'email_confirm': True},
                service_headers,
                'POST',
            )
            session = self._request(
                self.url + '/auth/v1/token?grant_type=password',
                {'email': email, 'password': password},
                {'apikey': keys['anon'], 'Content-Type': 'application/json'},
                'POST',
            )
            return {
                'id': user['id'],
                'refresh_token': session['refresh_token'],
                'access_token': session['access_token'],
            }
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
                {'query': "delete from public.registration_eligibility where identifier='" + email + "';"},
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

    def rest(self, keys, user, path, body=None, method='GET'):
        return self._request(
            self.url + '/rest/v1/' + path,
            body,
            {
                'apikey': keys['anon'],
                'Authorization': 'Bearer ' + user['access_token'],
                'Content-Type': 'application/json',
                'Prefer': 'return=representation',
            },
            method,
        )

    @staticmethod
    def _payload(user_id):
        table_names = (
            'goals', 'tasks', 'focus_sessions', 'focus_nodes', 'focus_chain_records',
            'focus_appointments', 'appointment_chain_records', 'focus_precedent_rules',
            'focus_sync_sources', 'calendar_sources', 'calendar_blocks',
        )
        return {'schemaVersion': 1, 'userId': user_id, 'tables': {name: [] for name in table_names}}

    def seed_snapshot(self, user):
        payload = json.dumps(self._payload(user['id']), separators=(',', ':')).replace("'", "''")
        self.management(
            '/database/query',
            {'query': "insert into public.cloud_business_snapshots "
                      "(user_id,revision,payload,device_id,device_name,data_updated_at,row_count) values ("
                      "'" + user['id'] + "',1,'" + payload + "'::jsonb,'issue71-seed','Issue 71 fixture',now(),0);"},
        )

    def seed_legacy(self, user):
        self.management(
            '/database/query',
            {'query': "insert into public.goals(id,user_id,title,classification,created_at,updated_at) "
                      "values (gen_random_uuid(),'" + user['id'] + "','Issue 71 legacy fixture','regular',now(),now());"},
        )

    def business_digest(self, user_id):
        result = self.management(
            '/database/query',
            {'query': "select md5(coalesce((select to_jsonb(s)::text from public.cloud_business_snapshots s "
                      "where user_id='" + user_id + "'),'no-snapshot') || '|' || coalesce((select "
                      "string_agg(to_jsonb(g)::text,',' order by g.id) from public.goals g where user_id='"
                      + user_id + "'),'no-goals')) as digest;"},
        )
        return result[0]['digest']

    def run_live_read_probe(self, keys):
        users = []
        try:
            for purpose in ('probe-owner', 'probe-other', 'probe-legacy'):
                users.append(self.create_user(keys, purpose))
            owner, other, legacy = users
            self.seed_snapshot(owner)
            self.seed_legacy(legacy)
            before = {uid: self.business_digest(uid) for uid in (owner['id'], other['id'], legacy['id'])}
            owner_rows = self.rest(keys, owner, 'cloud_business_snapshots?select=revision&user_id=eq.' + owner['id'])
            other_rows = self.rest(keys, other, 'cloud_business_snapshots?select=revision&user_id=eq.' + owner['id'])
            owner_legacy = self.rest(keys, owner, 'rpc/read_legacy_business_records', {}, 'POST')
            legacy_data = self.rest(keys, legacy, 'rpc/read_legacy_business_records', {}, 'POST')
            if len(owner_rows) != 1 or owner_rows[0]['revision'] != 1:
                raise RuntimeError('Owner could not read its revision-1 snapshot.')
            if other_rows:
                raise RuntimeError('Cross-user snapshot read returned rows.')
            if owner_legacy is not None:
                raise RuntimeError('Snapshot owner unexpectedly received legacy rows.')
            if not legacy_data or not legacy_data.get('token') or not legacy_data.get('records', {}).get('goals'):
                raise RuntimeError('Legacy owner could not read its legacy business fixture.')
            after = {uid: self.business_digest(uid) for uid in (owner['id'], other['id'], legacy['id'])}
            if before != after:
                raise RuntimeError('Read-only snapshot/legacy checks changed business state.')
            print('PASS live owner read, cross-user RLS denial, old-data read, and read-only digests', flush=True)

            self.management(
                '/database/query',
                {'query': "update public.cloud_business_snapshots set revision=2,uploaded_at=now() "
                          "where user_id='" + owner['id'] + "' and revision=1;"},
            )
            revision_two = self.rest(keys, owner, 'cloud_business_snapshots?select=revision&user_id=eq.' + owner['id'])
            if len(revision_two) != 1 or revision_two[0]['revision'] != 2:
                raise RuntimeError('Snapshot revision change was not visible to its owner.')
            self.management(
                '/database/query',
                {'query': "update public.goals set title='Issue 71 legacy fixture changed' "
                          "where user_id='" + legacy['id'] + "' and title='Issue 71 legacy fixture';"},
            )
            changed_legacy = self.rest(keys, legacy, 'rpc/read_legacy_business_records', {}, 'POST')
            if changed_legacy['token'] == legacy_data['token']:
                raise RuntimeError('Legacy content change did not change its stable token.')
            print('PASS revision 1→2 and legacy content-token change', flush=True)
        finally:
            cleanup_failed = False
            for user in users:
                try:
                    self.delete_user(keys, user['id'])
                except Exception:
                    cleanup_failed = True
            if cleanup_failed:
                raise RuntimeError('One or more temporary probe users require cleanup.')
        left = self.management(
            '/database/query',
            {'query': "select count(*)::int as snapshots from public.cloud_business_snapshots where user_id in ('"
                      + owner['id'] + "','" + other['id'] + "','" + legacy['id'] + "');"},
        )[0]['snapshots']
        if left != 0:
            raise RuntimeError('Probe snapshot fixture cleanup was incomplete.')
        print('PASS temporary probe users and snapshot rows removed', flush=True)


def read_env(path):
    values = {}
    for line in path.read_text().splitlines():
        if '=' not in line or line.lstrip().startswith('#'):
            continue
        name, value = line.split('=', 1)
        values[name.strip()] = value.strip().strip('"').strip("'")
    return values


def create_project(config_path):
    env = read_env(config_path)
    token = env.get('SUPABASE_ACCESS_TOKEN')
    if not token:
        raise RuntimeError('Management token is not configured in the protected config.')
    configured_url = env.get('SUPABASE_URL', '').rstrip('/')
    hostname = urllib.parse.urlparse(configured_url).hostname
    if not hostname or not hostname.endswith('.supabase.co'):
        raise RuntimeError('Configured public Supabase URL is invalid.')
    shared_ref = hostname.split('.')[0]
    headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}

    def request(path, body=None, method=None):
        payload = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(
            'https://api.supabase.com/v1' + path,
            data=payload,
            method=method,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'Supabase Management API returned HTTP {error.code}.') from None

    if PROJECT_STATE.exists():
        raise RuntimeError('Issue 71 project state already exists; use prepare or delete-project.')
    shared_project = request('/projects/' + shared_ref)
    if shared_project.get('name') != 'Pacta':
        raise RuntimeError('Configured project is not the shared Pacta project.')
    org_id = shared_project.get('organization_id')
    if not org_id:
        raise RuntimeError('Could not identify the shared project organization.')
    orgs = request('/organizations')
    matches = [org for org in orgs if org.get('id') == org_id]
    if len(matches) != 1:
        raise RuntimeError('Shared project organization could not be uniquely identified.')
    org = matches[0]
    details = request('/organizations/' + org_id)
    if details.get('plan') != 'free':
        raise RuntimeError('Organization is not on the free plan; refusing to create a project.')
    projects = request('/organizations/' + org_id + '/projects').get('projects', [])
    if any(project.get('name') == PROJECT_NAME for project in projects):
        raise RuntimeError('An unregistered Issue 71 project already exists; refusing to adopt it.')
    if len(projects) != 1 or projects[0].get('name') != 'Pacta':
        raise RuntimeError('Project inventory changed; refusing to create a disposable project.')

    # Omitting desired_instance_size selects Supabase's smallest Nano size.
    created = request('/projects', {
        'organization_slug': org['slug'],
        'name': PROJECT_NAME,
        'db_pass': secrets.token_urlsafe(40),
        'region': 'ap-southeast-1',
    })
    project = {
        'ref': created.get('ref') or created.get('id'),
        'name': created.get('name'),
        'organization_id': org['id'],
        'region': created.get('region', 'ap-southeast-1'),
    }
    if not project['ref'] or project['name'] != PROJECT_NAME:
        raise RuntimeError('Project creation returned an unexpected project identity.')
    PROJECT_STATE.parent.mkdir(parents=True, exist_ok=True)
    old_umask = os.umask(0o077)
    try:
        with PROJECT_STATE.open('x') as state_file:
            json.dump({'project': project}, state_file)
    finally:
        os.umask(old_umask)
    print('CREATED isolated Issue 71 project', project['ref'], 'region=' + project['region'])
    print('Provisioning may continue; run prepare after ACTIVE_HEALTHY.')


def protect_with_windows_acl(path):
    windows_path = subprocess.check_output(['wslpath', '-w', str(path)], text=True).strip().replace("'", "''")
    sid = subprocess.check_output(
        ['powershell.exe', '-NoProfile', '-Command', '[Security.Principal.WindowsIdentity]::GetCurrent().User.Value'],
        text=True,
    ).strip()
    if not sid.startswith('S-1-'):
        raise RuntimeError('Could not resolve current Windows user for ACL protection.')
    result = subprocess.run(
        ['icacls.exe', windows_path, '/inheritance:r', '/grant:r', '*' + sid + ':F'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        raise RuntimeError('Could not protect control file with a Windows ACL.')


def cleanup_stale_fixtures(project):
    """Remove only abandoned Issue 71 identities in the validated target project."""
    keys = project.keys()
    users = project.management(
        '/database/query',
        {'query': "select id::text as id from auth.users "
                  "where email like 'issue71-%@probe.invalid' order by id;"},
    )
    removed = 0
    for user in users:
        project.delete_user(keys, user['id'])
        removed += 1
    project.management(
        '/database/query',
        {'query': "delete from public.registration_eligibility "
                  "where identifier like 'issue71-%@probe.invalid';"},
    )
    leftovers = project.management(
        '/database/query',
        {'query': "select (select count(*)::int from auth.users where email like "
                  "'issue71-%@probe.invalid') as users, (select count(*)::int from "
                  "public.cloud_business_snapshots s join auth.users u on u.id=s.user_id "
                  "where u.email like 'issue71-%@probe.invalid') as snapshots, "
                  "(select count(*)::int from public.goals g join auth.users u on u.id=g.user_id "
                  "where u.email like 'issue71-%@probe.invalid') as goals;"},
    )[0]
    if any(leftovers.values()):
        raise RuntimeError('Stale Issue 71 fixture cleanup did not reach zero.')
    CONTROL_FILE.unlink(missing_ok=True)
    print('CLEANUP stale Issue 71 users=' + str(removed) + ' snapshots=0 legacy_goals=0 control_file=removed')


def serve(project):
    keys = project.keys()
    sessions = {}
    users = {}
    observations = {'snapshot-inspect': 0, 'legacy-inspect': 0, 'foreground-check': 0}
    control = secrets.token_hex(32)
    server = None
    try:
        users['device'] = project.create_user(keys, 'device')
        users['other'] = project.create_user(keys, 'other')
        users['legacy'] = project.create_user(keys, 'legacy')
        project.seed_snapshot(users['device'])
        project.seed_snapshot(users['other'])
        project.seed_legacy(users['legacy'])
        sessions.update(users)
        CONTROL_FILE.parent.mkdir(parents=True, exist_ok=True)
        os.umask(0o077)
        CONTROL_FILE.write_text(json.dumps({'ISSUE71_RUNTIME_CONTROL': control}))
        protect_with_windows_acl(CONTROL_FILE)

        from http.server import BaseHTTPRequestHandler, HTTPServer

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def authorized(self):
                return self.headers.get('X-Pacta-Acceptance') == control

            def send_json(self, body, status=200):
                raw = json.dumps(body).encode()
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self):
                if not self.authorized():
                    self.send_error(403)
                    return
                parsed = urllib.parse.urlparse(self.path)
                query = urllib.parse.parse_qs(parsed.query)
                if parsed.path == '/session':
                    name = query.get('user', [''])[0]
                    if name not in sessions:
                        self.send_error(404)
                        return
                    session = sessions[name]
                    self.send_json({
                        'url': project.url,
                        'publishableKey': keys['anon'],
                        'refreshToken': session['refresh_token'],
                        'userId': session['id'],
                    })
                elif parsed.path == '/observations':
                    self.send_json({'counts': observations, 'fixtures': {
                        name: {'userId': user['id']} for name, user in users.items()
                    }})
                else:
                    self.send_error(404)

            def do_POST(self):
                if not self.authorized():
                    self.send_error(403)
                    return
                path = urllib.parse.urlparse(self.path).path
                length = int(self.headers.get('Content-Length', '0'))
                body = json.loads(self.rfile.read(length) or b'{}')
                if path == '/control/change-snapshot' and body.get('user') in ('device', 'other'):
                    user = users[body['user']]
                    changed = project.management('/database/query', {'query':
                        "update public.cloud_business_snapshots set revision=revision+1,uploaded_at=now() "
                        "where user_id='" + user['id'] + "' returning revision;"})
                    if not changed or changed[0].get('revision') != 2:
                        self.send_error(409)
                        return
                    self.send_json({'changed': True})
                elif path == '/control/change-legacy':
                    user = users['legacy']
                    changed = project.management('/database/query', {'query':
                        "update public.goals set title='Issue 71 legacy fixture changed' where user_id='"
                        + user['id'] + "' and title='Issue 71 legacy fixture' returning id;"})
                    if not changed:
                        self.send_error(409)
                        return
                    self.send_json({'changed': True})
                elif path == '/control/record' and body.get('kind') in observations:
                    observations[body['kind']] += 1
                    self.send_json({'counts': observations})
                else:
                    self.send_error(404)

        server = HTTPServer(('127.0.0.1', PORT), Handler)
        stopping = threading.Event()

        def stop_server(*_):
            if not stopping.is_set():
                stopping.set()
                threading.Thread(target=server.shutdown, daemon=True).start()

        signal.signal(signal.SIGINT, stop_server)
        signal.signal(signal.SIGTERM, stop_server)
        print('READY isolated Issue 71 cloud-discovery fixture', flush=True)
        print('CONTROL_FILE ' + str(CONTROL_FILE.relative_to(ROOT)), flush=True)
        print('ADB_REVERSE adb reverse tcp:30347 tcp:30347', flush=True)
        print('SESSIONS device(snapshot), legacy(old business rows), other(snapshot)', flush=True)
        print('MUTATIONS POST /control/change-snapshot {user:device|other}; /control/change-legacy', flush=True)
        server.serve_forever()
    finally:
        if server is not None:
            server.server_close()
        for user in users.values():
            try:
                project.delete_user(keys, user['id'])
            except Exception:
                print('WARNING temporary Auth fixture requires cleanup in the Issue 71 isolated project', flush=True)
        CONTROL_FILE.unlink(missing_ok=True)
        print('CLEANUP temporary Auth users, snapshot/legacy fixtures, and runtime control file', flush=True)


def delete_project(project):
    project.management('', method='DELETE')
    PROJECT_STATE.unlink(missing_ok=True)
    print('DELETED isolated Issue 71 project and local project state', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('create-project', 'prepare', 'cleanup-stale', 'serve', 'delete-project'))
    parser.add_argument('--config', type=Path, default=ROOT / '.env', help='Protected config; values are never printed')
    args = parser.parse_args()
    if args.action == 'create-project':
        create_project(args.config)
        return
    project = AcceptanceProject(args.config)
    if args.action == 'prepare':
        project.apply_migrations_and_probe()
    elif args.action == 'cleanup-stale':
        cleanup_stale_fixtures(project)
    elif args.action == 'serve':
        serve(project)
    else:
        delete_project(project)


if __name__ == '__main__':
    main()
