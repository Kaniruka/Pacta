"""Strict, re-runnable Windows fixture for ticket 06 ordinary schedule reminders.

Isolation and validity rules enforced here:
  * every run gets its own test AUMID (Pacta.Test.*) and its own GUID; the
    product AUMID is rejected outright
  * the fixture uses a memory database and a fake account; it never reads user
    data and never changes Windows notification settings or Start Menu content
  * pass/fail requires every field below, not only the queue and delivery:
    identity (AUMID/GUID/mode/marker), the production planner's exact id, due
    instant and payload, process exit code, exit before every due time, a
    process inventory taken before the first due time, and an event-log query
    that actually tried to read this run's delivery
  * a missing field fails the run; an empty queue is never accepted as proof of
    delivery, and "no event" is never accepted as proof that something was
    queued before a logout
  * queue preservation, cancellation and OS delivery are reported separately
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import pathlib
import random
import re
import shutil
import subprocess
import sys
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROVIDER = 'Microsoft-Windows-PushNotifications-Platform'
TEST_PREFIX = 'Pacta.Test.'
PROBE_PREFIX = 'Pacta.Test.Schedule06Probe.'
BUILD_MARKER = 'schedule06-fixture-v3'
DEFAULT_EXE = ROOT / 'build/windows/x64/runner/Release/pacta.exe'
DATE_KEY = re.compile(r'^\d{4}-\d{2}-\d{2}$')
FIXTURE_SOURCES = [
    'tool/schedule_reminder_fixture/main.dart',
    'lib/main.dart',
    'lib/src/notifications/focus_notification_service.dart',
    'lib/src/notifications/schedule_reminder_plan.dart',
    'lib/src/notifications/schedule_reminder_sync.dart',
    'lib/src/notifications/windows_notification_adapter.dart',
    'windows/runner/windows_notification_bridge.cpp',
    'windows/runner/windows_notification_bridge.h',
]
ID_SPACE = range(230000, 330000)


def iso(value: datetime.datetime) -> str:
    return value.astimezone(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')


def parse_iso(value):
    if not value:
        return None
    try:
        return datetime.datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except ValueError:
        return None


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--exe', default=str(DEFAULT_EXE))
    parser.add_argument('--base', default=str(ROOT / '.scratch/schedule-reminder-fixture-runs'))
    parser.add_argument('--mode', choices=['exit', 'logout', 'reschedule', 'shell', 'cleanup'], default='exit')
    parser.add_argument('--due', type=int, default=45)
    parser.add_argument('--offset', type=int, default=30)
    parser.add_argument('--reschedule-delay', type=int, default=90)
    parser.add_argument('--aumid', default=None, help='explicit test AUMID (Pacta.Test.*) for a paired probe')
    parser.add_argument('--no-build', action='store_true', help='reuse the existing fixture binary')
    args = parser.parse_args()

    warnings = []
    build = {'performed': False}
    if not args.no_build:
        flutter = shutil.which('flutter') or shutil.which('flutter.bat')
        if not flutter:
            print(json.dumps({'stage': 'build', 'error': 'flutter executable not found', 'passed': False}))
            return 2
        started = time.time()
        completed = subprocess.run(
            [flutter, 'build', 'windows', '--release', '-t', 'tool/schedule_reminder_fixture/main.dart'],
            cwd=ROOT,
        )
        build = {'performed': True, 'exitCode': completed.returncode, 'seconds': round(time.time() - started, 1)}
        if completed.returncode != 0:
            print(json.dumps({'stage': 'build', 'build': build, 'passed': False}))
            return completed.returncode

    exe = pathlib.Path(args.exe)
    if not exe.is_file():
        print(json.dumps({'stage': 'exe', 'error': f'missing {exe}', 'passed': False}))
        return 2

    if args.aumid is not None and not args.aumid.startswith(PROBE_PREFIX):
        print(json.dumps({'stage': 'identity', 'error': f'explicit AUMID must start with {PROBE_PREFIX}', 'passed': False}))
        return 2
    token = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S') + '-' + format(random.randrange(16**6), '06x')
    aumid_source = 'explicit' if args.aumid else 'generated'
    aumid = args.aumid or f'{TEST_PREFIX}Schedule06.{token}'
    if not aumid.startswith(TEST_PREFIX):
        print(json.dumps({'stage': 'identity', 'error': 'test AUMID required', 'passed': False}))
        return 2
    run_dir = pathlib.Path(args.base).resolve() / token
    run_dir.mkdir(parents=True, exist_ok=False)
    output = run_dir / 'fixture.json'
    log_path = run_dir / 'run.log'
    run_started = datetime.datetime.now(datetime.timezone.utc)
    source_digests = {
        relative: sha256(ROOT / relative)
        for relative in FIXTURE_SOURCES
        if (ROOT / relative).is_file()
    }
    binary_newer = exe.stat().st_mtime >= max(
        (ROOT / relative).stat().st_mtime for relative in source_digests
    ) if source_digests else False
    if not build['performed']:
        if binary_newer:
            build['reusedBinaryNewerThanSources'] = True
        else:
            build['reusedBinaryNewerThanSources'] = False
            warnings.append('--no-build: the reused binary is older than a fixture source; pass/fail still holds, provenance does not')
    report = {
        'token': token,
        'mode': args.mode,
        'aumid': aumid,
        'aumidSource': aumid_source,
        'marker': token,
        'exe': str(exe),
        'exeSha256': sha256(exe),
        'exeMtimeUtc': iso(datetime.datetime.fromtimestamp(exe.stat().st_mtime, datetime.timezone.utc)),
        'build': build,
        'sourceSha256': source_digests,
        'runStartUtc': iso(run_started),
        'visualDeliveryReviewed': False,
        'acceptance': True,
        'warnings': warnings,
    }
    command = [
        str(exe),
        f'--mode={args.mode}',
        f'--output={output}',
        f'--aumid={aumid}',
        f'--due={args.due}',
        f'--offset={args.offset}',
        f'--reschedule-delay={args.reschedule_delay}',
        f'--marker={token}',
    ]
    report['command'] = command
    real_pid = None
    try:
        # The runner resolves the notification identity before Dart starts, so
        # the test identity travels in the environment. Permanent teardown is
        # additionally opted in, and only for the cleanup mode.
        environment = dict(os.environ)
        environment['PACTA_TEST_NOTIFICATION_AUMID'] = aumid
        if args.mode == 'cleanup':
            environment['PACTA_NOTIFICATION_FIXTURE_ALLOW_UNREGISTER_ALL'] = '1'
        with log_path.open('w', encoding='utf-8') as stream:
            process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT)
        real_pid = process.pid
        report['popenPid'] = real_pid
        process.wait(timeout=max(120, args.due + args.reschedule_delay + 90))
        report['processExitCode'] = process.returncode
    except subprocess.TimeoutExpired:
        report['processExitCode'] = None
        report['stage'] = 'timeout'
    except OSError as error:
        report['processExitCode'] = None
        report['stage'] = 'spawn'
        report['spawnError'] = type(error).__name__
    report['processExitedAtUtc'] = iso(datetime.datetime.now(datetime.timezone.utc))

    fixture = {}
    if output.is_file():
        try:
            fixture = json.loads(output.read_text(encoding='utf-8'))
        except json.JSONDecodeError as error:
            report['fixtureParseError'] = str(error)
    report['fixture'] = fixture
    if not isinstance(fixture, dict):
        fixture = {}
        report['fixture'] = fixture

    due = parse_iso(fixture.get('plannedDueAtUtc'))
    expected_due = parse_iso(fixture.get('dueAtUtc'))
    old_due = parse_iso(fixture.get('oldDueAtUtc'))
    new_due = parse_iso(fixture.get('newDueAtUtc'))
    targets = [value for value in [due, old_due, new_due] if value is not None]
    if not targets:
        report['checks'] = {'fixtureReportsDue': False}
        report['failures'] = ['fixtureReportsDue']
        report['passed'] = False
        report['queueVerified'] = False
        report['deliveryVerified'] = None
        write_manifest(run_dir, report)
        print(json.dumps({'run': str(run_dir), 'mode': args.mode, 'passed': False, 'failures': ['fixtureReportsDue']}))
        return 1

    # Inventory before the first due instant: the fixture process must already
    # be gone, and no process may still carry this run's AUMID.
    first_due = min(targets)
    inventory_at = first_due - datetime.timedelta(seconds=5)
    wait_seconds = (inventory_at - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
    if wait_seconds > 0:
        time.sleep(wait_seconds)
    inventory_checked = datetime.datetime.now(datetime.timezone.utc)
    report['processInventoryBeforeDue'] = inventory_checked < first_due
    report['processInventoryAtUtc'] = iso(inventory_checked)
    report['processAliveBeforeDue'] = process_alive(real_pid)
    report['processInventory'] = process_inventory(aumid)
    report['identityProbe'] = probe_identity(aumid)
    report['registrationBeforeDue'] = probe_registration(aumid)
    report['scheduledToastsBeforeDue'] = probe_scheduled_toasts(aumid)

    # Wait past the last due instant plus a delivery grace window.
    remaining = (max(targets) + datetime.timedelta(seconds=20) - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
    if remaining > 0:
        time.sleep(remaining)

    report['registrationAfterDue'] = probe_registration(aumid)
    report['scheduledToastsAfterDue'] = probe_scheduled_toasts(aumid)
    events = read_events(run_started, aumid)
    report['eventlog'] = events
    checks, details = verify(report, fixture, events, due, expected_due, old_due, new_due)
    failures = [name for name, value in checks.items() if value is not True]
    report['checks'] = checks
    report['checkDetails'] = details
    report['failures'] = failures
    report['passed'] = not failures
    report['queueVerified'] = checks.get(queue_check_name(args.mode), False)
    report['deliveryVerified'] = checks.get(
        'deliveryAtDue',
        checks.get('logoutNoDelivery', checks.get('scheduledEventObserved')),
    )
    write_manifest(run_dir, report)
    print(json.dumps({
        'run': str(run_dir),
        'mode': args.mode,
        'aumid': aumid,
        'queueVerified': report['queueVerified'],
        'deliveryVerified': report['deliveryVerified'],
        'passed': report['passed'],
        'failures': failures,
        'checks': checks,
    }, ensure_ascii=False))
    return 0 if report['passed'] else 1


def queue_check_name(mode: str) -> str:
    return {
        'exit': 'queuePreservedAtDetach',
        'shell': 'queuePreservedAcrossUnmount',
        'logout': 'logoutCancelled',
        'reschedule': 'rescheduleSingleSurvivor',
        'cleanup': 'queueEmptyAfterCleanup',
    }[mode]


def process_alive(pid: int) -> bool:
    result = subprocess.run(
        ['tasklist', '/FI', f'PID eq {pid}', '/NH'],
        capture_output=True, text=True, encoding='utf-8', errors='replace',
    )
    return str(pid) in (result.stdout or '')


def process_inventory(aumid: str):
    """Lists pacta.exe processes; only whether a command line carries this run's AUMID is kept."""
    script = (
        "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
        "$rows=@(Get-CimInstance Win32_Process -Filter \"Name='pacta.exe'\" | "
        "Select-Object ProcessId,CommandLine); "
        "$rows | ConvertTo-Json -Compress -Depth 3"
    )
    try:
        result = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
            capture_output=True, encoding='utf-8', errors='replace', timeout=60,
        )
        text = (result.stdout or '').strip()
        raw = json.loads(text) if text else []
        if isinstance(raw, dict):
            raw = [raw]
        rows = [
            {
                'pid': row.get('ProcessId'),
                'hasRunAumid': isinstance(row.get('CommandLine'), str) and aumid in row['CommandLine'],
            }
            for row in raw
        ]
        return {'ok': result.returncode == 0, 'processes': rows, 'count': len(rows)}
    except Exception as error:  # noqa: BLE001 - report, never crash
        return {'ok': False, 'error': type(error).__name__}


def probe_identity(aumid: str):
    """Read-only Start Menu shortcut probe; diagnostic only, never a pass gate.

    It separates "this fresh AUMID has no shell registration" from "the broker
    never delivered" without creating, editing or deleting any shortcut.
    """
    product = 'Pacta.Desktop.Focus'
    script = (
        "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
        "$shell=New-Object -ComObject Shell.Application; "
        "$dirs=@("
        "\"$env:APPDATA\\Microsoft\\Windows\\Start Menu\\Programs\","
        "\"$env:ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\"); "
        "$checked=0; $run=0; $prod=0; $withId=0; "
        "foreach ($dir in $dirs) { "
        "if (-not (Test-Path $dir)) { continue } "
        "Get-ChildItem $dir -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object { "
        "$checked++; "
        "$item=$shell.Namespace($_.DirectoryName).ParseName($_.Name); "
        "$id=$item.ExtendedProperty('System.AppUserModel.ID'); "
        "if ($id) { $withId++ }; "
        "if ($id -eq '" + aumid + "') { $run++ }; "
        "if ($id -eq '" + product + "') { $prod++ } } }; "
        "@{ checked=$checked; withId=$withId; run=$run; product=$prod } | ConvertTo-Json -Compress"
    )
    try:
        result = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
            capture_output=True, encoding='utf-8', errors='replace', timeout=90,
        )
        text = (result.stdout or '').strip()
        parsed = json.loads(text) if text else {}
        if not isinstance(parsed, dict):
            return {'ok': False, 'error': 'unexpected probe output'}
        return {
            'ok': result.returncode == 0,
            'shortcutsChecked': parsed.get('checked'),
            'shortcutsWithAnyAumid': parsed.get('withId'),
            'shortcutsForRunAumid': parsed.get('run'),
            'shortcutsForProductAumid': parsed.get('product'),
            'note': 'read-only diagnostic; not evidence of delivery',
        }
    except Exception as error:  # noqa: BLE001
        return {'ok': False, 'error': type(error).__name__}


def probe_registration(aumid: str):
    """Read-only registry view of this AUMID's notification registration.

    Names only: no values, no writes. It shows whether the plugin's initialize
    registration exists and whether the notification platform created its
    per-app settings entry (the difference observed between a cold AUMID and one
    that posted an immediate toast).
    """
    try:
        import winreg
    except ImportError:
        return {'ok': False, 'error': 'winreg unavailable'}

    def names(path: str):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_READ) as key:
                count = winreg.QueryInfoKey(key)[1]
                return sorted(winreg.EnumValue(key, index)[0] for index in range(count))
        except OSError:
            return None

    app_info = names('Software\\Classes\\AppUserModelId\\' + aumid)
    settings = names('Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings\\' + aumid)
    backup = names('Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications\\Backup\\' + aumid)
    return {
        'ok': True,
        'appUserModelIdValues': app_info,
        'notificationsSettingsValues': settings,
        'pushNotificationsBackupValues': backup,
        'hasSettingsEntry': settings is not None,
    }


def probe_scheduled_toasts(aumid: str):
    """Read-only view of the OS scheduled-toast queue for this AUMID.

    The WinRT projection returns each item's delivery time and toast XML, so the
    manifest can show what the platform actually holds without relying on the
    app's own bookkeeping. It never registers, cancels or modifies a toast.
    """
    script = (
        "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
        "[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime] | Out-Null; "
        "try { "
        "$notifier=[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('" + aumid + "'); "
        "$items=@($notifier.GetScheduledToastNotifications()); "
        "$rows=@($items | ForEach-Object { "
        "@{ id=$_.Id; delivery=$_.DeliveryTime.ToUniversalTime().ToString('o'); "
        "xmlB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($_.Content.GetXml()))) } }); "
        "@{ ok=$true; count=$items.Count; items=$rows } | ConvertTo-Json -Compress -Depth 6 "
        "} catch { @{ ok=$false; error=$_.Exception.Message } | ConvertTo-Json -Compress }"
    )
    try:
        result = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
            capture_output=True, encoding='utf-8', errors='replace', timeout=90,
        )
        text = (result.stdout or '').strip()
        if not text:
            return {'ok': False, 'error': 'empty probe output', 'stderr': (result.stderr or '').strip()[:300]}
        parsed = json.loads(text)
        if not isinstance(parsed, dict):
            return {'ok': False, 'error': 'unexpected probe output'}
        items = parsed.get('items') or []
        if isinstance(items, dict):
            items = [items]
        return {
            'ok': parsed.get('ok') is True,
            'count': parsed.get('count'),
            'items': [
                {
                    'id': item.get('id'),
                    'delivery': item.get('delivery'),
                    'xml': decode_xml(item.get('xmlB64'))[:2000],
                }
                for item in items
            ],
            'error': parsed.get('error'),
        }
    except Exception as error:  # noqa: BLE001
        return {'ok': False, 'error': type(error).__name__}


def decode_xml(value) -> str:
    if not isinstance(value, str) or not value:
        return ''
    try:
        return base64.b64decode(value).decode('utf-8', 'replace')
    except (ValueError, TypeError):
        return ''


def read_events(since: datetime.datetime, aumid: str):
    """Only this run's identity is retained.

    The window total is an aggregate count; per-event payloads are kept only for
    events whose message carries this run's AUMID. Events from other apps are
    never stored, so the manifest cannot be mistaken for this run's activity.
    """
    start = since.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    script = (
        "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
        "$since=[datetime]::Parse('" + start + "').ToUniversalTime(); "
        "$provider='" + PROVIDER + "'; $aumid='" + aumid + "'; "
        "$all=@(Get-WinEvent -FilterHashtable @{ProviderName=$provider; Id=3052; StartTime=$since} -ErrorAction SilentlyContinue); "
        "$match=@($all | Where-Object { $_.Message -like ('*' + $aumid + '*') } | "
        "ForEach-Object { $_.TimeCreated.ToUniversalTime().ToString('o') }); "
        "$groups=@(Get-WinEvent -FilterHashtable @{ProviderName=$provider; StartTime=$since} -ErrorAction SilentlyContinue | "
        "Where-Object { $_.Message -like ('*' + $aumid + '*') } | "
        "Group-Object Id | ForEach-Object { @{ id=$_.Name; count=$_.Count } }); "
        "@{ total=$all.Count; matching=$match; sameAumidEventIds=$groups } | ConvertTo-Json -Compress -Depth 4"
    )
    try:
        result = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
            capture_output=True, encoding='utf-8', errors='replace', timeout=180,
        )
        if result.returncode != 0:
            return {'ok': False, 'total3052InWindow': None, 'matching': [], 'stderr': (result.stderr or '').strip()[:400]}
        text = (result.stdout or '').strip()
        if not text:
            return {'ok': True, 'total3052InWindow': 0, 'matching': [], 'sameAumidEventIds': []}
        parsed = json.loads(text)
        if not isinstance(parsed, dict):
            return {'ok': False, 'total3052InWindow': None, 'matching': [], 'error': 'unexpected event output'}
        matching = parsed.get('matching') or []
        if isinstance(matching, str):
            matching = [matching]
        groups = parsed.get('sameAumidEventIds') or []
        if isinstance(groups, dict):
            groups = [groups]
        return {
            'ok': True,
            'total3052InWindow': parsed.get('total'),
            'matching': matching,
            'sameAumidEventIds': groups,
        }
    except Exception as error:  # noqa: BLE001 - report, never crash
        return {'ok': False, 'total3052InWindow': None, 'matching': [], 'error': type(error).__name__}


def event_times(events):
    return sorted(
        parsed
        for parsed in (parse_iso(value) for value in events.get('matching') or [])
        if parsed is not None
    )


def within(times, target, before=2, after=20):
    if target is None:
        return None
    return [
        time
        for time in times
        if target - datetime.timedelta(seconds=before) <= time <= target + datetime.timedelta(seconds=after)
    ]


def verify(report, fixture, events, due, expected_due, old_due, new_due):
    checks = {}
    details = {}

    def gate(name, condition, detail=None):
        checks[name] = bool(condition)
        if detail is not None:
            details[name] = detail

    def field(name):
        present = name in fixture and fixture[name] is not None
        gate(f'field:{name}', present)
        return fixture.get(name)

    mode = report['mode']
    gate('fixtureBuildMarker', fixture.get('fixtureBuildMarker') == BUILD_MARKER, fixture.get('fixtureBuildMarker'))
    gate('fixtureNoError', 'error' not in fixture, fixture.get('error'))
    gate('initialized', fixture.get('initialized') is True)
    gate('testAumid', str(report.get('aumid', '')).startswith(TEST_PREFIX), report.get('aumid'))
    explicit_aumid = report.get('aumidSource') == 'explicit'
    gate(
        'runAumid',
        field('aumid') == report.get('aumid')
        and str(report.get('aumid')).startswith(PROBE_PREFIX if explicit_aumid else TEST_PREFIX)
        and (explicit_aumid or str(report.get('aumid')).endswith(report.get('token', ''))),
    )
    gate('registeredAumid', fixture.get('registeredAumid') == report.get('aumid'), fixture.get('registeredAumid'))
    gate('identityFromEnvironment', fixture.get('identitySource') == 'environment', fixture.get('identitySource'))
    gate('fixtureMode', field('mode') == mode, fixture.get('mode'))
    gate('fixtureMarker', field('marker') == report.get('token'))
    gate('fixturePid', fixture.get('pid') is not None and fixture.get('pid') == report.get('popenPid'), {'fixture': fixture.get('pid'), 'popen': report.get('popenPid')})
    gate('processExitCode', report.get('processExitCode') == 0, report.get('processExitCode'))

    exit_at = parse_iso(report.get('processExitedAtUtc'))
    gate('processExitedAt', exit_at is not None)
    gate('processInventoryBeforeDue', report.get('processInventoryBeforeDue') is True)
    inventory = report.get('processInventory') or {}
    gate('processInventoryReadable', inventory.get('ok') is True)
    gate(
        'processInventoryNoRunAumid',
        inventory.get('ok') is True and not any(row.get('hasRunAumid') for row in inventory.get('processes') or []),
        inventory,
    )
    gate('processGoneBeforeDue', report.get('processAliveBeforeDue') is False)

    planned_id = field('plannedNotificationId')
    planned_payload = field('plannedPayload')
    planned_date = field('plannedDateKey')
    schedule_id = field('scheduleId')
    gate('plannedIdInNamespace', isinstance(planned_id, int) and planned_id in ID_SPACE, planned_id)
    gate('plannedDueMatchesExpected', planned_due_equals(fixture, due, expected_due), {'planned': fixture.get('plannedDueAtUtc'), 'expected': fixture.get('dueAtUtc')})
    gate('plannedPayloadOwner', payload_owner(planned_payload) == 'fixture-user', planned_payload)
    gate('plannedPayloadSchedule', payload_schedule(planned_payload) == schedule_id)
    gate('plannedPayloadDate', payload_date(planned_payload) == planned_date and DATE_KEY.match(str(planned_date or '')) is not None)

    pending = fixture.get('pending')
    gate('pendingIsList', isinstance(pending, list), pending)
    gate('queueContainsPlanned', isinstance(pending, list) and planned_id in pending, pending)

    if mode in ('exit', 'shell', 'logout', 'cleanup'):
        gate('processExitedBeforeDue', exit_at is not None and due is not None and exit_at < due, {'exit': report.get('processExitedAtUtc'), 'due': fixture.get('plannedDueAtUtc')})

    if mode == 'exit':
        detached = field('pendingAtDetach')
        detached_settled = field('pendingAfterDetachSettled')
        gate('queuePreservedAtDetach', is_list_with(detached, planned_id) and is_list_with(detached_settled, planned_id), {'detach': detached, 'settled': detached_settled})
    elif mode == 'shell':
        before = field('pendingBeforeUnmount')
        after = field('pendingAfterShellUnmount')
        after_settled = field('pendingAfterShellUnmountSettled')
        gate('queuePreservedAcrossUnmount', is_list_with(before, planned_id) and is_list_with(after, planned_id) and is_list_with(after_settled, planned_id), {'before': before, 'after': after, 'settled': after_settled})
        gate('shellMounted', fixture.get('shellMounted') is True)
        gate('shellAuthOwner', fixture.get('authUserId') == 'fixture-user', fixture.get('authUserId'))
        gate('shellServiceOwner', fixture.get('serviceOwnerUserId') == 'fixture-user', fixture.get('serviceOwnerUserId'))
        gate('shellDependenciesIsolated', shell_dependencies_isolated(fixture), fixture.get('shellDependencies'))
    elif mode == 'logout':
        before = field('pendingBeforeLogout')
        after = field('pendingAfterLogout')
        settled = field('pendingAfterLogoutSettled')
        gate('queueBeforeLogout', is_list_with(before, planned_id), before)
        gate('pendingAfterLogoutIsList', isinstance(after, list) and isinstance(settled, list), {'after': after, 'settled': settled})
        gate('logoutCancelled', after == [] and settled == [], {'after': after, 'settled': settled})
    elif mode == 'reschedule':
        moved_id = field('newPlannedNotificationId')
        moved_payload = field('newPlannedPayload')
        moved_pending = field('pendingAfterReschedule')
        moved_settled = field('pendingAfterRescheduleSettled')
        gate('processExitedBeforeOldDue', exit_at is not None and old_due is not None and exit_at < old_due, {'exit': report.get('processExitedAtUtc'), 'oldDue': fixture.get('oldDueAtUtc')})
        gate('rescheduleMovedDue', due is not None and old_due is not None and new_due is not None and new_due > old_due, {'old': fixture.get('oldDueAtUtc'), 'new': fixture.get('newDueAtUtc')})
        gate('rescheduleKeepsOffset', reschedule_offset_matches(fixture, report), {'rescheduledStartUtc': fixture.get('rescheduledStartUtc'), 'newDueAtUtc': fixture.get('newDueAtUtc')})
        gate('reschedulePayloadOwner', payload_owner(moved_payload) == 'fixture-user')
        gate('rescheduleSingleSurvivor', moved_pending == [moved_id] and moved_settled == [moved_id], {'pending': moved_pending, 'settled': moved_settled, 'id': moved_id})
        gate('rescheduleIdentityStable', moved_id == planned_id, {'old': planned_id, 'new': moved_id})

    times = event_times(events)
    gate('eventlogAvailable', events.get('ok') is True and events.get('total3052InWindow') is not None, {k: events.get(k) for k in ('total3052InWindow', 'error', 'stderr')})
    details['eventlogTotal3052InWindow'] = events.get('total3052InWindow')
    details['eventlogMatchingAumid'] = len(times)
    details['eventTimes'] = [iso(time) for time in times]
    details['sameAumidEventIds'] = events.get('sameAumidEventIds')
    details['registrationBeforeDue'] = registration_summary(report.get('registrationBeforeDue'))
    details['registrationAfterDue'] = registration_summary(report.get('registrationAfterDue'))
    details['scheduledToastsBeforeDue'] = toast_summary(report.get('scheduledToastsBeforeDue'))
    details['scheduledToastsAfterDue'] = toast_summary(report.get('scheduledToastsAfterDue'))

    if mode == 'cleanup':
        pending_after = field('pendingAfterCleanup')
        gate('cleanupUnregistered', fixture.get('unregisteredAll') is True)
        gate('queueEmptyAfterCleanup', pending_after == [], pending_after)
        gate('noDeliveryAfterCleanup', within(times, due) == [], {'due': fixture.get('plannedDueAtUtc')})
    elif mode == 'logout':
        hits = within(times, due)
        gate('logoutNoDelivery', hits == [], {'hitCount': None if hits is None else len(hits)})
    else:
        hits = within(times, due)
        gate('deliveryAtDue', hits is not None and len(hits) == 1, {'hitCount': None if hits is None else len(hits), 'due': fixture.get('plannedDueAtUtc')})
        gate('deliveryAfterExit', bool(hits) and exit_at is not None and all(time > exit_at for time in hits), {'exit': report.get('processExitedAtUtc'), 'hits': [iso(time) for time in hits or []]})
    if mode == 'reschedule':
        gap = int((new_due - old_due).total_seconds()) if old_due and new_due else 0
        old_hits = within(times, old_due, before=2, after=max(5, gap - 10))
        new_hits = within(times, new_due)
        gate('rescheduleOldNotDelivered', old_hits == [], {'hitCount': None if old_hits is None else len(old_hits)})
        gate('rescheduleNewDelivered', new_hits is not None and len(new_hits) == 1, {'hitCount': None if new_hits is None else len(new_hits), 'due': fixture.get('newDueAtUtc')})
        gate('rescheduleNewAfterExit', bool(new_hits) and exit_at is not None and all(time > exit_at for time in new_hits))
    return checks, details


def registration_summary(probe) -> dict:
    if not isinstance(probe, dict):
        return {'ok': False, 'error': 'missing'}
    return {
        'ok': probe.get('ok'),
        'appUserModelIdValues': probe.get('appUserModelIdValues'),
        'notificationsSettingsValues': probe.get('notificationsSettingsValues'),
        'hasSettingsEntry': probe.get('hasSettingsEntry'),
    }


def toast_matches_due(probe, due) -> bool:
    if not isinstance(probe, dict) or probe.get('ok') is not True:
        return False
    for item in probe.get('items') or []:
        delivery = parse_iso(item.get('delivery'))
        if delivery is not None and due is not None and abs((delivery - due).total_seconds()) <= 1:
            return True
    return False


def toast_summary(probe) -> dict:
    if not isinstance(probe, dict):
        return {'ok': False, 'error': 'missing'}
    items = probe.get('items') or []
    return {
        'ok': probe.get('ok'),
        'count': probe.get('count'),
        'error': probe.get('error'),
        'deliveries': [item.get('delivery') for item in items],
    }


def shell_dependencies_isolated(fixture) -> bool:
    """Omitted factories must resolve to Unavailable/null plus this run's repository."""
    dependencies = fixture.get('shellDependencies')
    if not isinstance(dependencies, dict) or len(dependencies) != 7:
        return False
    for name, value in dependencies.items():
        if not isinstance(value, str) or value.startswith('error:'):
            return False
        if name == 'scheduleRepository':
            if value != 'LocalScheduleRepository':
                return False
        elif value != 'null' and not value.startswith('Unavailable'):
            return False
    return True


def is_uuid4(value: str) -> bool:
    try:
        return str(uuid.UUID(value)) == value and uuid.UUID(value).version == 4
    except ValueError:
        return False


def planned_due_equals(fixture, due, expected_due) -> bool:
    return due is not None and expected_due is not None and due == expected_due


def reschedule_offset_matches(fixture, report) -> bool:
    moved_start = parse_iso(fixture.get('rescheduledStartUtc'))
    new_due = parse_iso(fixture.get('newDueAtUtc'))
    offset = parse_offset_minutes(report)
    if moved_start is None or new_due is None or offset is None:
        return False
    return moved_start - new_due == datetime.timedelta(minutes=offset)


def parse_offset_minutes(report):
    command = report.get('command') or []
    for item in command:
        if item.startswith('--offset='):
            try:
                return int(item.split('=', 1)[1])
            except ValueError:
                return None
    return None


def is_list_with(value, item) -> bool:
    return isinstance(value, list) and item in value


def payload_owner(payload):
    return payload_part(payload, 0)


def payload_schedule(payload):
    return payload_part(payload, 1)


def payload_date(payload):
    return payload_part(payload, 2)


def payload_part(payload, index: int):
    if not isinstance(payload, str) or not payload.startswith('schedule-reminder:'):
        return None
    body = payload[len('schedule-reminder:'):]
    parts = body.split(':')
    if len(parts) != 3:
        return None
    return parts[index]


def write_manifest(run_dir: pathlib.Path, report: dict) -> None:
    (run_dir / 'manifest.json').write_text(
        json.dumps(report, indent=2, ensure_ascii=False, default=str), encoding='utf-8'
    )


if __name__ == '__main__':
    sys.exit(main())
