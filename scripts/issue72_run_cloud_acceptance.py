#!/usr/bin/env python3
"""Run Issue 72's real cloud AppShell test with native Android Back evidence."""
import argparse
from datetime import datetime, timezone
import json
import re
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
ADB = '/mnt/c/Users/Stray/AppData/Local/Android/sdk/platform-tools/adb.exe'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=('android', 'windows'))
    parser.add_argument('--device', default='emulator-5556')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9:._-]+', args.device):
        parser.error('Device serial contains unsupported characters.')
    platform = args.platform
    log = ROOT / f'.scratch/issue72/{platform}-cloud.log'
    evidence = ROOT / f'docs/evidence/issue-72/cloud-{platform}.json'
    log.parent.mkdir(parents=True, exist_ok=True)
    evidence.parent.mkdir(parents=True, exist_ok=True)
    android = platform == 'android'
    previous = {}
    actions = []

    def adb(*command):
        result = subprocess.run([ADB, '-s', args.device, *command],
                                check=True, capture_output=True, text=True)
        return result.stdout.strip()

    def settings(name, value=None):
        return adb('shell', 'settings', 'get' if value is None else 'put',
                   'system', name, *([] if value is None else [value]))

    command = ['cmd.exe', '/c', 'flutter', 'test',
               'integration_test/issue_72_cloud_choice_test.dart',
               '-d', args.device if android else 'windows',
               '--dart-define-from-file=.dart_tool/issue72-cloud-control.json',
               '--reporter', 'expanded', '--no-uninstall']
    result = {'issue': 72, 'platform': platform,
              'startedAt': datetime.now(timezone.utc).isoformat(),
              'command': command, 'pointer': 'touch' if android else 'mouse',
              'realCloud': True, 'actions': actions}
    process = None
    native_pid_file = log.with_suffix('.native-pid')
    native_pid_file.unlink(missing_ok=True)
    try:
        if android:
            previous = {
                'accelerometer_rotation': settings('accelerometer_rotation'),
                'user_rotation': settings('user_rotation'),
                'night': adb('shell', 'cmd', 'uimode', 'night').split(':')[-1].strip(),
            }
            result['androidSettingsBefore'] = previous.copy()
            result['androidRelease'] = adb('shell', 'getprop', 'ro.build.version.release')
            settings('accelerometer_rotation', '0')
            settings('user_rotation', '0')
            adb('shell', 'cmd', 'uimode', 'night', 'no')
            adb('reverse', 'tcp:30348', 'tcp:30348')
            actions.append('portrait locked / light theme; adb reverse tcp:30348 tcp:30348')
        back_sent = False
        with log.open('w') as output:
            windows_pid_path = subprocess.check_output(
                ['wslpath', '-w', str(native_pid_file)], text=True).strip()
            # Keep the native CMD pid so an interrupted WSL runner can stop
            # exactly its own Flutter process tree, including native children.
            native_arguments = ' '.join([command[1], r'D:\Programs\UserScoop\apps\flutter\current\bin\flutter.bat', *command[3:]])
            launch = (
                "$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + "
                "[Environment]::GetEnvironmentVariable('Path','User'); "
                "$env:PATHEXT = [Environment]::GetEnvironmentVariable('PATHEXT','Machine') + ';' + "
                "[Environment]::GetEnvironmentVariable('PATHEXT','User'); "
                "$child = Start-Process -FilePath 'cmd.exe' -ArgumentList '"
                + native_arguments.replace("'", "''")
                + "' -NoNewWindow -PassThru; "
                + "[IO.File]::WriteAllText('" + windows_pid_path.replace("'", "''")
                + "', [string]$child.Id); $null = $child.Handle; $child.WaitForExit(); exit $child.ExitCode"
            )
            process = subprocess.Popen(
                ['powershell.exe', '-NoProfile', '-Command', launch], cwd=ROOT,
                stdout=output, stderr=subprocess.STDOUT)
            while process.poll() is None:
                text = log.read_text(errors='replace')
                if android and not back_sent and 'ISSUE72_WAITING_FOR_ANDROID_BACK' in text:
                    adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
                    back_sent = True
                    actions.append('adb shell input keyevent KEYCODE_BACK')
                    print('SENT actual Android KEYCODE_BACK', flush=True)
                time.sleep(.5)
        result['exitCode'] = process.returncode
        text = log.read_text(errors='replace')
        result['assertions'] = [line.strip() for line in text.splitlines()
                                if 'ISSUE72_REAL_CLOUD_PASS' in line
                                or 'ISSUE72_ANDROID_SYSTEM_BACK_DISMISSED' in line]
        result['androidBackSent'] = back_sent if android else None
        result['passed'] = process.returncode == 0 and len([
            line for line in result['assertions'] if 'ISSUE72_REAL_CLOUD_PASS' in line]) == 2
        if android:
            result['passed'] = result['passed'] and back_sent
    finally:
        cleanup_errors = []
        if process is not None and process.poll() is None:
            try:
                if native_pid_file.exists():
                    native_pid = int(native_pid_file.read_text().strip())
                    if native_pid <= 0:
                        raise RuntimeError('Invalid owned Windows process id.')
                    subprocess.run(['taskkill.exe', '/PID', str(native_pid), '/T', '/F'],
                                   check=True, capture_output=True, text=True)
            except Exception as error:
                cleanup_errors.append('owned native process termination: ' + str(error))
            try:
                process.terminate()
                process.wait(timeout=15)
            except Exception as error:
                cleanup_errors.append('owned launcher termination: ' + str(error))
        try:
            native_pid_file.unlink(missing_ok=True)
        except Exception as error:
            cleanup_errors.append('owned native PID file removal: ' + str(error))
        if android and previous:
            restore_actions = [
                ('accelerometer_rotation', lambda: settings('accelerometer_rotation', previous['accelerometer_rotation'])),
                ('user_rotation', lambda: settings('user_rotation', previous['user_rotation'])),
                ('night', lambda: adb('shell', 'cmd', 'uimode', 'night', previous['night'])),
                ('reverse', lambda: adb('reverse', '--remove', 'tcp:30348')),
            ]
            for name, restore in restore_actions:
                try:
                    restore()
                except Exception as error:
                    cleanup_errors.append(name + ': ' + str(error))
            restored = {}
            for name in ('accelerometer_rotation', 'user_rotation', 'night'):
                try:
                    restored[name] = (adb('shell', 'cmd', 'uimode', 'night').split(':')[-1].strip()
                                      if name == 'night' else settings(name))
                except Exception as error:
                    cleanup_errors.append('read restored ' + name + ': ' + str(error))
            result['androidSettingsAfter'] = restored
            result['settingsRestored'] = restored == previous
        if cleanup_errors:
            result['cleanupErrors'] = cleanup_errors
            result['passed'] = False
        result['finishedAt'] = datetime.now(timezone.utc).isoformat()
        evidence.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'platform': platform, 'exitCode': result.get('exitCode'),
                      'passed': result.get('passed', False),
                      'assertions': result.get('assertions', [])}), flush=True)
    if not result.get('passed'):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
