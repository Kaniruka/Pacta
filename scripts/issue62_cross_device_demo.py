#!/usr/bin/env python3
"""Real Android + installed desktop Codex acceptance bridge.

Run in WSL from the repository root. Requires protected .env containing public
Supabase configuration and SUPABASE_ACCESS_TOKEN. Creates/deletes only its own
random user and OAuth client. Never logs credentials. It does not provision an
isolated Supabase project: use an explicitly selected disposable target project.
Run Flutter separately using the public control JSON reported on startup.
"""
import argparse
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import queue
import secrets
import signal
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]


def request(url, body=None, headers=None, method=None, redirect=True):
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args):
            return None
    data = body if isinstance(body, bytes) else None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    opener = urllib.request.build_opener() if redirect else urllib.request.build_opener(NoRedirect)
    try:
        response = opener.open(req, timeout=90)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    result = json.loads(raw) if raw and 'json' in response.headers.get('Content-Type', '') else raw.decode()
    if response.status >= 400:
        raise RuntimeError(f'HTTP {response.status}: {str(result)[:140]}')
    return result, dict(response.headers), response.status


class Codex:
    def __init__(self, url, token, executable):
        self.url, self.token, self.executable = url, token, executable
        self.home = tempfile.TemporaryDirectory(prefix='pacta-issue62-codex-')
        os.chmod(self.home.name, 0o700)
        Path(self.home.name, 'config.toml').write_text(
            '[mcp_servers.pacta_demo]\nurl = ' + json.dumps(url) +
            '\nbearer_token_env_var = "PACTA_DEMO_DELEGATE"\n')
        runtime = os.environ.copy()
        runtime.update(CODEX_HOME=self.home.name, PACTA_DEMO_DELEGATE=token)
        self.proc = subprocess.Popen([executable, 'app-server'], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     text=True, env=runtime, cwd='/tmp')
        self.inbox = queue.Queue()
        self.counter = 0
        threading.Thread(target=self._read, daemon=True).start()
        try:
            self.rpc('initialize', {'clientInfo': {'name': 'pacta-issue62-demo', 'version': '1'},
                                    'capabilities': {'experimentalApi': True}})
            self.proc.stdin.write('{"method":"initialized"}\n')
            self.proc.stdin.flush()
            self.thread = self.rpc('thread/start', {'cwd': '/tmp', 'ephemeral': True})['thread']['id']
            self.rpc('mcpServerStatus/list', {})
        except BaseException:
            self.close()
            raise

    def _read(self):
        for line in self.proc.stdout:
            try:
                self.inbox.put(json.loads(line))
            except ValueError:
                pass

    def rpc(self, method, params):
        self.counter += 1
        ident = self.counter
        self.proc.stdin.write(json.dumps({'id': ident, 'method': method, 'params': params}) + '\n')
        self.proc.stdin.flush()
        deadline = time.time() + 90
        while time.time() < deadline:
            msg = self.inbox.get(timeout=max(.01, deadline - time.time()))
            if msg.get('id') == ident:
                if 'error' in msg:
                    raise RuntimeError(str(msg['error']))
                return msg['result']
        raise TimeoutError(method)

    def tool(self, name, arguments):
        for attempt in range(3):
            try:
                return self.rpc('mcpServer/tool/call', {'threadId': self.thread, 'server': 'pacta_demo',
                                                       'tool': name, 'arguments': arguments})
            except RuntimeError as error:
                if attempt == 2 or 'Transport send error' not in str(error):
                    raise
                # Retry only transport failures of read-only tools at the same revision.
                time.sleep(1)

    def analyze(self, output):
        # The current protected Codex authentication remains in its normal home.
        # Only this single MCP and its temporary read delegate are configured.
        output.parent.mkdir(parents=True, exist_ok=True)
        pending_output = output.with_name(output.name + '.pending')
        pending_output.unlink(missing_ok=True)
        runtime = os.environ.copy()
        runtime['PACTA_DEMO_DELEGATE'] = self.token
        skill = (ROOT / 'skills/pacta-national-focus-analysis/SKILL.md').read_text()
        contract = (ROOT / 'skills/pacta-national-focus-analysis/references/contract.md').read_text()
        prompt = (skill + '\n' + contract + '\nApply the skill above. '
                  'Use only pacta_demo MCP for data; never run shell commands or read environment/config files. '
                  'Read current metadata, tree, library, every failure page and frozen detail for the latest '
                  'snapshot. Review the structure/rule clarity and perform a failure retrospective in Chinese. '
                  'Cite IDs, revision, upload time/source device and rule versions. Separate original reasons '
                  'from later reflection and suggestions. State history limits. This is a disposable synthetic '
                  'user whose snapshot was manually uploaded by the real native App. Do not write business data.')
        command = [self.executable, 'exec', '--ignore-user-config', '--ephemeral',
                   '--skip-git-repo-check', '-s', 'read-only', '-C', str(ROOT),
                   '-c', 'mcp_servers.pacta_demo.url=' + json.dumps(self.url),
                   '-c', 'mcp_servers.pacta_demo.bearer_token_env_var="PACTA_DEMO_DELEGATE"',
                   '--json', '-o', str(pending_output), '-']
        with open('/tmp/pacta-issue62-model.jsonl', 'w') as log, open('/tmp/pacta-issue62-model.stderr', 'w') as err:
            result = subprocess.run(command, input=prompt, text=True, env=runtime, stdout=log, stderr=err, timeout=360)
        if result.returncode != 0 or not pending_output.exists():
            pending_output.unlink(missing_ok=True)
            raise AssertionError('Real Codex analysis failed; previous successful report preserved')
        items = [json.loads(line) for line in Path('/tmp/pacta-issue62-model.jsonl').read_text().splitlines()]
        calls = [item['item'] for item in items if item.get('type') == 'item.completed'
                 and item.get('item', {}).get('type') == 'mcp_tool_call']
        required = {'get_snapshot_metadata', 'get_national_focus_tree', 'get_national_focus_library',
                    'list_national_focus_failures', 'get_national_focus_failure'}
        def available(call):
            result = call.get('result') or {}
            data = result.get('structured_content') or {}
            metadata = data.get('metadata', data)
            return (call['status'] == 'completed' and not call.get('error')
                    and not result.get('isError') and not result.get('is_error')
                    and metadata.get('status') == 'available')
        assert required.issubset({call['tool'] for call in calls if available(call)}), 'Incomplete real model MCP reads'
        trace = [{'tool': call['tool'], 'arguments': call['arguments'], 'status': call['status'],
                  'error': call.get('error'),
                  'structured_content': (call.get('result') or {}).get('structured_content')}
                 for call in calls]
        pending_output.replace(output)
        output.with_suffix('.tools.json').write_text(json.dumps(trace, ensure_ascii=False, indent=2))

    def close(self):
        try:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=10)
        finally:
            self.home.cleanup()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=ROOT / '.env', help='Protected target configuration; never printed')
    parser.add_argument('--port', type=int, default=30348)
    parser.add_argument('--codex', default='/mnt/c/Users/Stray/.codex/bin/wsl/f19bbb73214bc62a/codex')
    parser.add_argument('--analysis-output', default='docs/evidence/issue62-codex-analysis.md')
    parser.add_argument('--skip-analysis', action='store_true', help='Run native/service checks only; does not claim a model run')
    parser.add_argument('--android-device', help='Opt in to temporary Wi-Fi/mobile interruption on this test emulator')
    parser.add_argument('--evidence', default='.scratch/issue62/cross-device-evidence.json')
    args = parser.parse_args()
    def stop(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    os.umask(0o077)
    env = {}
    for line in args.config.read_text().splitlines():
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            env[key.strip()] = value.strip().strip('\"').strip("'")
    url = env['SUPABASE_URL'].rstrip('/')
    ref = urllib.parse.urlparse(url).hostname.split('.')[0]
    def management(path, body=None):
        return request('https://api.supabase.com/v1/projects/' + ref + path, body,
                       {'Authorization': 'Bearer ' + env['SUPABASE_ACCESS_TOKEN'],
                        'Content-Type': 'application/json'})[0]
    service_key = next(key['api_key'] for key in management('/api-keys') if key['name'] == 'service_role')
    admin_headers = {'Authorization': 'Bearer ' + service_key, 'apikey': service_key,
                     'Content-Type': 'application/json'}
    anon_headers = {'apikey': env['SUPABASE_PUBLISHABLE_KEY'], 'Content-Type': 'application/json'}
    uid = None
    client_id = None
    codex = None
    watchdog = None
    network_state = []
    def adb(*command):
        executable = '/mnt/c/Users/Stray/AppData/Local/Android/sdk/platform-tools/adb.exe'
        return subprocess.check_output([executable, '-s', args.android_device, 'shell', *command], text=True).strip()
    def restore_network():
        for service, enabled in network_state:
            adb('svc', service, 'enable' if enabled else 'disable')
        network_state.clear()
    def business_digest():
        rows = management('/database/query', {'query':
            "select md5(to_jsonb(snapshot)::text) as digest from public.cloud_business_snapshots snapshot where user_id='" + uid + "';"})
        return rows[0]['digest']
    evidence = {'project_isolation': 'random identity in configured project; no claim of isolated project',
                'checks': {}, 'stages': []}
    path = ROOT / args.evidence
    path.parent.mkdir(parents=True, exist_ok=True)
    control_path = ROOT / '.dart_tool/issue62-demo-control.json'
    try:
        email = 'issue62-' + uuid.uuid4().hex + '@probe.invalid'
        password = secrets.token_urlsafe(30)
        # Grant eligibility only to this unique disposable identity.
        management('/database/query', {'query': "insert into public.registration_eligibility(identifier,identifier_type) values ('" + email + "','email');"})
        user = request(url + '/auth/v1/admin/users', {'email': email, 'password': password,
                       'email_confirm': True}, admin_headers)[0]
        uid = user['id']
        session = request(url + '/auth/v1/token?grant_type=password',
                          {'email': email, 'password': password}, anon_headers)[0]
        issuer = url + '/functions/v1/national-focus-mcp'
        resource = issuer + '/mcp'
        redirect = 'http://127.0.0.1:30349/callback'
        client_id = request(issuer + '/register', {'client_name': 'Issue62 desktop Codex',
                            'redirect_uris': [redirect]}, {'Content-Type': 'application/json'})[0]['client_id']
        verifier = secrets.token_urlsafe(48)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
        query = urllib.parse.urlencode({'client_id': client_id, 'redirect_uri': redirect,
                'response_type': 'code', 'scope': 'national_focus:read', 'resource': resource,
                'code_challenge_method': 'S256', 'code_challenge': challenge, 'state': secrets.token_hex(16)})
        auth_location = request(issuer + '/authorize?' + query, redirect=False)[1]['Location']
        request_code = urllib.parse.parse_qs(urllib.parse.urlparse(auth_location).query)['request'][0]
        control = secrets.token_hex(32)
        control_path.write_text(json.dumps({'PACTA_DEMO_CONTROL': control, 'PACTA_DEMO_PORT': str(args.port),
                                           'PACTA_DEMO_ANDROID_NETWORK_TEST': bool(args.android_device)}))
        os.chmod(control_path, 0o600)

        def capture(revision):
            metadata = codex.tool('get_snapshot_metadata', {'expected_revision': revision})
            tree = codex.tool('get_national_focus_tree', {'expected_revision': revision})
            library = codex.tool('get_national_focus_library', {'expected_revision': revision})
            from datetime import datetime, timezone, timedelta
            day = (datetime.now(timezone.utc) + timedelta(hours=4)).strftime('%Y-%m-%d')
            history = codex.tool('list_national_focus_failures', {'expected_revision': revision,
                      'start_date': day, 'end_date': day, 'limit': 100})
            events = history['structuredContent']['events']
            assert events, 'Android production repository did not produce a failure'
            detail = codex.tool('get_national_focus_failure', {'expected_revision': revision,
                                'event_id': events[0]['id']})
            return {'metadata': metadata, 'tree': tree, 'library': library, 'history': history, 'detail': detail}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                nonlocal codex
                if self.headers.get('X-Pacta-Acceptance') != control:
                    self.send_error(403)
                    return
                stage = self.path.strip('/')
                try:
                    response = {}
                    if stage == 'session':
                        response = {'url': url, 'publishableKey': env['SUPABASE_PUBLISHABLE_KEY'],
                                    'refreshToken': session['refresh_token']}
                    elif stage == 'uploaded':
                        response = {'requestCode': request_code}
                    elif stage == 'approved':
                        location = request(auth_location, redirect=False)[1]['Location']
                        code = urllib.parse.parse_qs(urllib.parse.urlparse(location).query)['code'][0]
                        token = request(issuer + '/token', urllib.parse.urlencode({
                            'grant_type': 'authorization_code', 'code': code, 'client_id': client_id,
                            'redirect_uri': redirect, 'resource': resource,
                            'code_verifier': verifier}).encode(),
                            {'Content-Type': 'application/x-www-form-urlencoded'})[0]['access_token']
                        evidence['checks']['real_dcr_pkce_and_app_consent'] = True
                        codex = Codex(resource, token, args.codex)
                        evidence['revision1'] = capture(1)
                        if args.skip_analysis:
                            evidence['model_analysis_skipped'] = True
                        else:
                            codex.analyze(ROOT / args.analysis_output)
                            evidence['checks']['actual_model_structure_analysis_and_failure_retrospective'] = True
                        evidence['checks']['actual_codex_read_native_snapshot_and_frozen_failure'] = True
                    elif stage == 'local-edit':
                        result = codex.tool('get_national_focus_tree', {'expected_revision': 1})
                        assert 'local-only revised' not in json.dumps(result)
                        assert 'Issue62 bedtime reading' in json.dumps(result)
                        evidence['checks']['phone_unuploaded_edit_invisible'] = True
                        evidence['before_read_recovery_digest'] = business_digest()
                    elif stage == 'offline':
                        if not args.android_device:
                            raise ValueError('Android network testing was not enabled')
                        # Record both states before mutating either, then restore in finally.
                        for setting, service in [('wifi_on', 'wifi'), ('mobile_data', 'data')]:
                            current = adb('settings', 'get', 'global', setting)
                            if current not in ('0', '1'):
                                raise ValueError('Cannot determine original emulator network state')
                            network_state.append((service, current == '1'))
                        for service, _ in network_state:
                            adb('svc', service, 'disable')
                    elif stage == 'online':
                        restore_network()
                    elif stage == 'recovered':
                        for _ in range(3):
                            reread = codex.tool('get_national_focus_tree', {'expected_revision': 1})
                            assert not reread.get('isError') and reread['structuredContent']['metadata']['status'] == 'available'
                        assert business_digest() == evidence['before_read_recovery_digest'], 'Recovery or repeated reads changed business snapshot'
                        evidence['checks']['native_network_failure_recovery_and_repeated_reads_preserve_snapshot'] = True
                    elif stage == 'reuploaded':
                        evidence['revision2'] = capture(2)
                        assert 'local-only revised' in json.dumps(evidence['revision2']['tree'])
                        stale = codex.tool('get_national_focus_tree', {'expected_revision': 1})
                        assert stale.get('isError') and 'snapshot_changed' in json.dumps(stale)
                        evidence['stale_revision'] = stale
                        evidence['checks']['second_manual_upload_visible_and_version_change_detected'] = True
                    elif stage == 'revoked':
                        refusals = {}
                        for name, arguments in [('get_snapshot_metadata', {}),
                            ('get_national_focus_tree', {'expected_revision': 2}),
                            ('get_national_focus_library', {'expected_revision': 2}),
                            ('get_national_focus_card', {'expected_revision': 2, 'card_id': 'any-card'}),
                            ('get_national_focus_failure', {'expected_revision': 2, 'event_id': 'any-event'}),
                            ('list_national_focus_failures', {'expected_revision': 2,
                             'start_date': '2026-10-01', 'end_date': '2026-10-31'})]:
                            try:
                                result = codex.tool(name, arguments)
                                assert result.get('isError') and 'Authentication required' in json.dumps(result)
                                refusals[name] = 'Authentication required'
                            except RuntimeError as error:
                                assert 'Auth required' in str(error), str(error)
                                refusals[name] = 'Auth required'
                        for method in ['initialize', 'tools/list']:
                            try:
                                request(resource, {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': {}},
                                        {'Authorization': 'Bearer ' + codex.token, 'Content-Type': 'application/json'})
                                raise AssertionError('Revoked protocol request succeeded')
                            except RuntimeError as error:
                                assert 'HTTP 401' in str(error)
                                refusals[method] = 'HTTP 401'
                        evidence['revoked_tool_refusals'] = refusals
                        evidence['checks']['app_revoke_refuses_followup_tools'] = True
                    else:
                        raise ValueError('Unknown stage')
                    evidence['stages'].append(stage)
                    path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
                    print('PASS stage ' + stage, flush=True)
                    body = json.dumps(response).encode()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    if stage == 'revoked':
                        threading.Thread(target=server.shutdown, daemon=True).start()
                except Exception as error:
                    evidence['failure_stage'] = stage
                    evidence['failure_type'] = type(error).__name__
                    path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
                    print('FAIL stage ' + stage + ': ' + type(error).__name__, flush=True)
                    self.send_error(500, 'Acceptance stage failed; inspect protected local diagnostics')
                    threading.Thread(target=server.shutdown, daemon=True).start()
                    Path('/tmp/pacta-issue62-private-error.txt').write_text(repr(error))
                    os.chmod('/tmp/pacta-issue62-private-error.txt', 0o600)
                    # Report only local fixture data, never URLs with OAuth codes.
                    if isinstance(error, AssertionError):
                        print(str(error), flush=True)
        server = http.server.HTTPServer(('127.0.0.1', args.port), Handler)
        print('READY .dart_tool/issue62-demo-control.json; adb reverse tcp:' + str(args.port) +
              ' tcp:' + str(args.port), flush=True)
        watchdog = threading.Timer(900, server.shutdown)
        watchdog.daemon = True
        watchdog.start()
        server.serve_forever()
        assert evidence['checks'].get('app_revoke_refuses_followup_tools'), 'Demo incomplete'
    finally:
        # A second interrupt must not abort credential/fixture cleanup.
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if watchdog:
            watchdog.cancel()
        cleanup_errors = []
        def clean(label, action):
            try:
                action()
            except Exception:
                cleanup_errors.append(label)
        if network_state:
            clean('original emulator network state', restore_network)
        if codex:
            clean('codex process', codex.close)
        if uid:
            clean('temporary auth user', lambda: request(
                url + '/auth/v1/admin/users/' + uid, headers=admin_headers, method='DELETE'))
        if client_id:
            clean('temporary OAuth client', lambda: management('/database/query', {'query':
                "delete from public.national_focus_mcp_requests where client_id='" + client_id +
                "'; delete from public.national_focus_mcp_clients where id='" + client_id + "';"}))
        if 'email' in locals():
            clean('temporary eligibility', lambda: management('/database/query', {'query':
                "delete from public.registration_eligibility where identifier='" + email + "';"}))
        clean('runtime control file', lambda: control_path.unlink(missing_ok=True))
        evidence['temporary_identity_removed'] = not cleanup_errors
        evidence['cleanup_errors'] = cleanup_errors
        path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
        print('Cleanup complete; evidence: ' + str(path.relative_to(ROOT)), flush=True)
        if cleanup_errors:
            raise RuntimeError('Temporary resource cleanup failed: ' + ', '.join(cleanup_errors))


if __name__ == '__main__':
    main()
