"""Isolated Start Menu shortcut probe for the ticket-06 delivery gap.

STATUS: source for review only. Nothing here has been executed by this session.
The default action prints a plan and writes nothing.

Purpose
-------
Microsoft documents a Start Menu shortcut carrying System.AppUserModel.ID as
the registration path for classic Win32 desktop toasts. The strict fixture shows
that a fresh test AUMID can be scheduled and the OS holds the toast with the
exact delivery time, while first-use scheduled delivery yields no 3052 event;
an immediate show on the same AUMID both delivers and creates
HKCU/.../Notifications/Settings/<aumid>. This probe isolates the registration
hypothesis with one disposable shortcut and never touches product identity.

Writes (only with --register)
-----------------------------
* an intent file:  <worktree>/.scratch/schedule-reminder-shortcut-probes/<token>/intent.json
* optionally creates %APPDATA%/Microsoft/Windows/Start Menu/Programs/Pacta.Test/
* one file:        .../Pacta.Test/Schedule06Probe.<token>.lnk

The intent file is written before the shortcut so a partial failure can be
cleaned precisely. The probe refuses to run unless --target is the fixture
pacta.exe built in this worktree, and unless the AUMID starts with
Pacta.Test.Schedule06Probe. It never overwrites an existing shortcut.

Cleanup
-------
--cleanup --manifest <intent.json|manifest.json> removes exactly the recorded
path after proving: the parent is the probe folder, the file name equals the
recorded Schedule06Probe name, and the current shortcut still reads back the
same AUMID and target (or the same file hash). A replaced .lnk is refused. The
probe folder is removed only when this run created it and it is now empty.

Review sequence (not executed)
------------------------------
1. python tool/schedule_reminder_fixture/shortcut_probe.py --dry-run --target build/windows/x64/runner/Release/pacta.exe
2. python ... --register --target <same> --aumid Pacta.Test.Schedule06Probe.<token> --guid <uuid4>
3. python tool/schedule_reminder_fixture/run.py --mode exit --aumid <same> --guid <same>
4. python ... --cleanup --manifest <manifest.json>
"""
import argparse
import ctypes
import datetime
import hashlib
import json
import pathlib
import sys
import uuid
from ctypes import POINTER, byref, c_void_p, c_wchar_p, wintypes

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_TARGET = ROOT / 'build/windows/x64/runner/Release/pacta.exe'
START_MENU = pathlib.Path.home() / 'AppData/Roaming/Microsoft/Windows/Start Menu/Programs'
PROBE_DIR = START_MENU / 'Pacta.Test'
PROBE_PREFIX = 'Pacta.Test.Schedule06Probe.'
LINK_PREFIX = 'Schedule06Probe.'
BASE = ROOT / '.scratch/schedule-reminder-shortcut-probes'

CLSID_SHELL_LINK = '{00021401-0000-0000-C000-000000000046}'
IID_ISHELL_LINK_W = '{000214F9-0000-0000-C000-000000000046}'
IID_IPROPERTY_STORE = '{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}'
IID_IPERSIST_FILE = '{0000010B-0000-0000-C000-000000000046}'
PKEY_APP_USER_MODEL_ID = '{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}'

VT_LPWSTR = 31
HRESULT = ctypes.c_long
S_OK = 0


class GUID(ctypes.Structure):
    _fields_ = [
        ('Data1', ctypes.c_ulong),
        ('Data2', ctypes.c_ushort),
        ('Data3', ctypes.c_ushort),
        ('Data4', ctypes.c_ubyte * 8),
    ]

    @classmethod
    def parse(cls, text):
        value = uuid.UUID(text)
        guid = cls()
        guid.Data1 = value.time_low
        guid.Data2 = value.time_mid
        guid.Data3 = value.time_hi_version
        for index, item in enumerate(value.bytes[8:]):
            guid.Data4[index] = item
        return guid


class PROPERTYKEY(ctypes.Structure):
    _fields_ = [('fmtid', GUID), ('pid', wintypes.DWORD)]


class PROPVARIANT(ctypes.Structure):
    _fields_ = [
        ('vt', ctypes.c_ushort),
        ('wReserved1', ctypes.c_ushort),
        ('wReserved2', ctypes.c_ushort),
        ('wReserved3', ctypes.c_ushort),
        ('pointer', ctypes.c_void_p),
        ('padding', ctypes.c_void_p),
    ]


def com_method(pointer, index, *argument_types):
    table = ctypes.cast(pointer, POINTER(POINTER(c_void_p))).contents
    prototype = ctypes.WINFUNCTYPE(HRESULT, c_void_p, *argument_types)
    return prototype(table[index])


def check(result, what):
    if result != S_OK:
        raise OSError(f'{what} failed with HRESULT {result & 0xFFFFFFFF:08X}')


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def create_shortcut(path, target, aumid):
    ole32 = ctypes.OleDLL('ole32')
    propsys = ctypes.OleDLL('propsys')
    ole32.CoInitializeEx(None, 0x2)
    shell_link = c_void_p()
    property_store = c_void_p()
    persist_file = c_void_p()
    value = PROPVARIANT()
    try:
        clsid = GUID.parse(CLSID_SHELL_LINK)
        iid = GUID.parse(IID_ISHELL_LINK_W)
        check(ole32.CoCreateInstance(byref(clsid), None, 1, byref(iid), byref(shell_link)), 'CoCreateInstance(ShellLink)')
        check(com_method(shell_link, 20, c_wchar_p)(shell_link, target), 'SetPath')
        check(com_method(shell_link, 7, c_wchar_p)(shell_link, 'Pacta ticket06 probe'), 'SetDescription')
        check(com_method(shell_link, 9, c_wchar_p)(shell_link, str(path.parent)), 'SetWorkingDirectory')

        iid_props = GUID.parse(IID_IPROPERTY_STORE)
        check(
            com_method(shell_link, 0, POINTER(GUID), POINTER(c_void_p))(shell_link, byref(iid_props), byref(property_store)),
            'QueryInterface(IPropertyStore)',
        )
        key = PROPERTYKEY()
        key.fmtid = GUID.parse(PKEY_APP_USER_MODEL_ID)
        key.pid = 5
        check(propsys.InitPropVariantFromString(c_wchar_p(aumid), byref(value)), 'InitPropVariantFromString')
        check(
            com_method(property_store, 6, POINTER(PROPERTYKEY), POINTER(PROPVARIANT))(property_store, byref(key), byref(value)),
            'IPropertyStore.SetValue',
        )
        check(com_method(property_store, 7)(property_store), 'IPropertyStore.Commit')

        iid_file = GUID.parse(IID_IPERSIST_FILE)
        check(
            com_method(shell_link, 0, POINTER(GUID), POINTER(c_void_p))(shell_link, byref(iid_file), byref(persist_file)),
            'QueryInterface(IPersistFile)',
        )
        check(com_method(persist_file, 6, c_wchar_p, wintypes.BOOL)(persist_file, str(path), True), 'IPersistFile.Save')
    finally:
        ole32.PropVariantClear(byref(value))
        for pointer in (persist_file, property_store, shell_link):
            if pointer:
                com_method(pointer, 2)(pointer)
        ole32.CoUninitialize()


def read_shortcut(path):
    ole32 = ctypes.OleDLL('ole32')
    ole32.CoInitializeEx(None, 0x2)
    shell_link = c_void_p()
    property_store = c_void_p()
    persist = c_void_p()
    value = PROPVARIANT()
    try:
        clsid = GUID.parse(CLSID_SHELL_LINK)
        iid = GUID.parse(IID_ISHELL_LINK_W)
        check(ole32.CoCreateInstance(byref(clsid), None, 1, byref(iid), byref(shell_link)), 'CoCreateInstance')
        iid_file = GUID.parse(IID_IPERSIST_FILE)
        check(
            com_method(shell_link, 0, POINTER(GUID), POINTER(c_void_p))(shell_link, byref(iid_file), byref(persist)),
            'QueryInterface(IPersistFile)',
        )
        check(com_method(persist, 5, c_wchar_p, wintypes.DWORD)(persist, str(path), 0), 'IPersistFile.Load')
        buffer = ctypes.create_unicode_buffer(32768)
        check(com_method(shell_link, 3, c_wchar_p, ctypes.c_int, c_void_p, wintypes.DWORD)(shell_link, buffer, len(buffer), None, 0), 'IShellLink.GetPath')
        target = buffer.value
        iid_props = GUID.parse(IID_IPROPERTY_STORE)
        check(
            com_method(shell_link, 0, POINTER(GUID), POINTER(c_void_p))(shell_link, byref(iid_props), byref(property_store)),
            'QueryInterface(IPropertyStore)',
        )
        key = PROPERTYKEY()
        key.fmtid = GUID.parse(PKEY_APP_USER_MODEL_ID)
        key.pid = 5
        check(
            com_method(property_store, 5, POINTER(PROPERTYKEY), POINTER(PROPVARIANT))(property_store, byref(key), byref(value)),
            'IPropertyStore.GetValue',
        )
        aumid = ctypes.wstring_at(value.pointer) if value.vt == VT_LPWSTR else None
        return {'aumid': aumid, 'target': target}
    finally:
        ole32.PropVariantClear(byref(value))
        for pointer in (persist, property_store, shell_link):
            if pointer:
                com_method(pointer, 2)(pointer)
        ole32.CoUninitialize()


def plan(aumid, guid, target):
    token = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S') + '-' + uuid.uuid4().hex[:6]
    aumid = aumid or (PROBE_PREFIX + token)
    guid = guid or str(uuid.uuid4())
    if not aumid.startswith(PROBE_PREFIX):
        raise SystemExit(f'refusing AUMID outside {PROBE_PREFIX}')
    uuid.UUID(guid)
    target_path = pathlib.Path(target).resolve()
    if target_path != DEFAULT_TARGET.resolve():
        raise SystemExit(f'refusing target outside the built fixture: {target_path}')
    if not target_path.is_file():
        raise SystemExit(f'missing fixture target: {target_path}')
    shortcut_name = LINK_PREFIX + token + '.lnk'
    return {
        'token': token,
        'aumid': aumid,
        'guid': guid,
        'shortcutName': shortcut_name,
        'shortcutPath': str(PROBE_DIR / shortcut_name),
        'target': str(target_path),
        'targetSha256': sha256(target_path),
        'probeDir': str(PROBE_DIR),
    }


def write_intent(details):
    BASE.mkdir(parents=True, exist_ok=True)
    run_dir = BASE / details['token']
    run_dir.mkdir(parents=True, exist_ok=False)
    intent_path = run_dir / 'intent.json'
    intent = {
        'state': 'intent',
        'createdAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'probe': details,
        'folderExistedBefore': PROBE_DIR.exists(),
        'intentPath': str(intent_path),
    }
    intent_path.write_text(json.dumps(intent, indent=2, ensure_ascii=False), encoding='utf-8')
    return intent_path, intent


def register(details):
    path = pathlib.Path(details['shortcutPath'])
    if path.exists():
        raise SystemExit(f'refusing to overwrite existing shortcut: {path}')
    folder_existed = PROBE_DIR.exists()
    intent_path, intent = write_intent(details)
    try:
        PROBE_DIR.mkdir(parents=True, exist_ok=True)
        create_shortcut(path, details['target'], details['aumid'])
        readback = read_shortcut(path)
        manifest = {
            **intent,
            'state': 'created',
            'createdAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'readback': readback,
            'matches': readback.get('aumid') == details['aumid'] and readback.get('target') == details['target'],
            'shortcutSha256': sha256(path),
            'folderCreated': not folder_existed,
        }
        manifest_path = BASE / details['token'] / 'manifest.json'
        manifest['manifestPath'] = str(manifest_path)
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
        intent_path.write_text(json.dumps({**intent, 'state': 'created', 'manifestPath': str(manifest_path)}, indent=2, ensure_ascii=False), encoding='utf-8')
        return manifest
    except Exception:
        intent['state'] = 'failed'
        intent_path.write_text(json.dumps(intent, indent=2, ensure_ascii=False), encoding='utf-8')
        raise


def cleanup(manifest_path):
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    probe = manifest.get('probe') or {}
    path = pathlib.Path(probe.get('shortcutPath', '')).resolve()
    expected_parent = PROBE_DIR.resolve()
    if path.parent != expected_parent:
        raise SystemExit(f'refusing cleanup outside {expected_parent}: {path}')
    if path.name != probe.get('shortcutName') or not path.name.startswith(LINK_PREFIX):
        raise SystemExit(f'refusing cleanup of an unrecorded shortcut name: {path.name}')
    existed = path.exists()
    verified = None
    if existed:
        current = read_shortcut(path)
        current_hash = sha256(path)
        same_identity = current.get('aumid') == probe.get('aumid') and current.get('target') == probe.get('target')
        same_hash = manifest.get('shortcutSha256') == current_hash
        if not manifest.get('shortcutSha256') and not manifest.get('readback'):
            raise SystemExit(f'refusing to delete without a recorded readback or hash: {path}')
        if not (same_identity or same_hash):
            raise SystemExit('refusing to delete a shortcut whose content changed after creation')
        verified = {'readback': current, 'identityMatch': same_identity, 'hashMatch': same_hash}
        path.unlink()
    folder_removed = False
    if (
        manifest.get('folderCreated') is True
        and PROBE_DIR.exists()
        and not any(PROBE_DIR.iterdir())
    ):
        PROBE_DIR.rmdir()
        folder_removed = True
    return {
        'removed': str(path),
        'existed': existed,
        'stillExists': path.exists(),
        'verified': verified,
        'folderCreated': manifest.get('folderCreated'),
        'folderRemoved': folder_removed,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true', help='print the plan; default action')
    parser.add_argument('--register', action='store_true', help='create the single probe shortcut')
    parser.add_argument('--cleanup', action='store_true', help='delete the shortcut recorded in a manifest')
    parser.add_argument('--manifest')
    parser.add_argument('--aumid')
    parser.add_argument('--guid')
    parser.add_argument('--target', default=str(DEFAULT_TARGET))
    args = parser.parse_args()

    if args.cleanup:
        if not args.manifest:
            raise SystemExit('--cleanup requires --manifest')
        print(json.dumps(cleanup(pathlib.Path(args.manifest)), ensure_ascii=False))
        return 0
    details = plan(args.aumid, args.guid, args.target)
    if not args.register:
        print(json.dumps({'action': 'dry-run', 'plan': details, 'writes': []}, ensure_ascii=False))
        return 0
    print(json.dumps({'action': 'register', 'manifest': register(details)}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
