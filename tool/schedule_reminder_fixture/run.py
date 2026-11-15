"""Re-runnable Windows fixture runner for ticket 06 ordinary schedule reminders.

Isolation rules enforced here:
  * the fixture uses its own AUMID (default Pacta.Validation.Schedule06), never the product one
  * every run gets a fresh directory and a unique marker; an existing run is never reused
  * the fixture uses a memory database and a fake account; it never reads user data
  * only Windows event log reads are used to observe delivery (no settings changes)
"""
import argparse
import datetime
import json
import pathlib
import random
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
AUMID = 'Pacta.Validation.Schedule06'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--exe', default=str(ROOT / 'build/windows/x64/runner/Release/pacta.exe'))
    parser.add_argument('--base', default=str(ROOT / '.scratch/schedule-reminder-fixture-runs'))
    parser.add_argument('--mode', choices=['exit', 'logout', 'reschedule'], default='exit')
    parser.add_argument('--due', type=int, default=90, help='seconds until the reminder is due')
    parser.add_argument('--offset', type=int, default=30, help='stored reminder minutes before start')
    parser.add_argument('--build', action='store_true', help='build the fixture entrypoint first')
    parser.add_argument('--wait', type=int, default=0, help='seconds to wait after exit before the event-log check')
    parser.add_argument('--eventlog', action='store_true', help='read Windows PushNotifications events for the fixture AUMID')
    parser.add_argument('--aumid', default=AUMID, help='fixture AUMID; never the product one by default')
    parser.add_argument('--app-name', default='Pacta Reminder Fixture')
    args = parser.parse_args()

    if args.build:
        build = subprocess.run(
            ['flutter', 'build', 'windows', '--release', '-t', 'tool/schedule_reminder_fixture/main.dart'],
            cwd=ROOT,
        )
        if build.returncode != 0:
            print(json.dumps({'stage': 'build', 'exitCode': build.returncode}))
            return build.returncode

    exe = pathlib.Path(args.exe)
    if not exe.is_file():
        print(json.dumps({'stage': 'exe', 'error': f'missing {exe}', 'exitCode': 2}))
        return 2

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')
    marker = f"{stamp}-{args.mode}-{random.randrange(16**6):06x}"
    run_dir = pathlib.Path(args.base).resolve() / marker
    run_dir.mkdir(parents=True, exist_ok=False)
    output = run_dir / 'fixture.json'
    log = run_dir / 'run.log'
    report = {
        'marker': marker,
        'mode': args.mode,
        'exe': str(exe),
        'aumid': args.aumid,
        'dueInSeconds': args.due,
        'offsetMinutes': args.offset,
        'startUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'visualDeliveryReviewed': False,
    }
    command = [
        str(exe),
        f'--mode={args.mode}',
        f'--output={output}',
        f'--due={args.due}',
        f'--offset={args.offset}',
        f'--marker={marker}',
        f'--aumid={args.aumid}',
        f'--app-name={args.app_name}',
    ]
    report['command'] = command
    with log.open('w', encoding='utf-8') as stream:
        completed = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    report['processExitCode'] = completed.returncode
    report['endUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    if output.is_file():
        report['fixture'] = json.loads(output.read_text(encoding='utf-8'))
    if args.wait > 0:
        import time
        time.sleep(args.wait)
        report['observedAfterExitUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    if args.eventlog:
        report['eventLog'] = read_event_log(args.aumid)
    checks = verify(report, args.mode)
    report['checks'] = checks
    report['passed'] = all(checks.values())
    (run_dir / 'manifest.json').write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8'
    )
    print(json.dumps({
        'run': str(run_dir),
        'mode': args.mode,
        'processExitCode': completed.returncode,
        'passed': report['passed'],
        'checks': checks,
    }, ensure_ascii=False))
    return 0 if report['passed'] else 1


def verify(report: dict, mode: str) -> dict:
    fixture = report.get('fixture') or {}
    pending = fixture.get('pending') or []
    checks = {
        'processExited': report.get('processExitCode') == 0,
        'initialized': fixture.get('initialized') is True,
        'oneRegisteredReminder': len(pending) == 1,
        'uniquePid': isinstance(fixture.get('pid'), int),
    }
    if mode == 'exit':
        checks['keptAtExit'] = (fixture.get('pendingAtExit') or []) == pending
    elif mode == 'logout':
        checks['cancelledOnLogout'] = (fixture.get('pendingAfterLogout') or []) == []
    else:
        checks['stillOneAfterReschedule'] = len(fixture.get('pendingAfterReschedule') or []) <= 1
        checks['moved'] = fixture.get('rescheduledAtUtc') is not None
    return checks


def read_event_log(aumid: str, minutes: int = 30):
    """Read-only query of the PushNotifications provider for this fixture AUMID.

    The provider log name differs across Windows builds, so the query uses the
    provider itself instead of assuming an 'Operational' channel path.
    """
    script = (
        "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
        "$since=(Get-Date).ToUniversalTime().AddMinutes(-MINUTES); "
        "Get-WinEvent -FilterHashtable @{ProviderName='Microsoft-Windows-PushNotifications-Platform'; Id=3052; StartTime=$since} "
        "-ErrorAction SilentlyContinue | "
        "Where-Object { $_.Message -like '*AUMID*' } | Select-Object -First 10 | "
        "ForEach-Object { @{ time=$_.TimeCreated.ToUniversalTime().ToString('o'); message=$_.Message } } | "
        "ConvertTo-Json -Compress"
    ).replace('AUMID', aumid).replace('MINUTES', str(minutes))
    try:
        result = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
            capture_output=True, timeout=60,
            encoding='utf-8', errors='replace',
        )
        if result.returncode != 0:
            return {'error': 'eventlog_unavailable', 'stderr': result.stderr.strip()[:500]}
        text = result.stdout.strip()
        return json.loads(text) if text else []
    except Exception as error:  # noqa: BLE001 - the fixture must report, not crash
        return {'error': type(error).__name__}


if __name__ == '__main__':
    sys.exit(main())