#!/usr/bin/env python3
"""Pacta 云端管理员终端工具（Windows PowerShell 可用）。

只用公开的 Supabase URL 与 publishable/anon key，配合管理员本人邮箱与密码
登录取得用户 JWT，再调用受 RLS / RPC 保护的管理接口。工具从不读取、要求、
硬编码或打印 service_role / sb_secret_ 密钥；管理员密码只存在于当前进程内。

用法：

    python scripts/pacta_admin.py                    # 交互式数字菜单
    python scripts/pacta_admin.py users              # 查看用户生命周期
    python scripts/pacta_admin.py eligibilities      # 查看注册资格
    python scripts/pacta_admin.py grant person@example.com
    python scripts/pacta_admin.py revoke person@example.com
    python scripts/pacta_admin.py suspend person@example.com
    python scripts/pacta_admin.py restore 00000000-0000-0000-0000-000000000000
    python scripts/pacta_admin.py reset-password person@example.com
    python scripts/pacta_admin.py delete-user person@example.com --immediate

配置：

    --env-file  默认仓库根目录 .env；环境变量优先，.env 补齐缺失项。
                只读取 SUPABASE_URL、SUPABASE_PUBLISHABLE_KEY 或
                SUPABASE_ANON_KEY。成对引号会被去掉；引号内的 # 保留，
                引号外以空白开头的 # 视为行内注释。
    --email     管理员登录邮箱；省略时在终端提示输入。

退出码：0 成功；1 云端/网络错误；2 配置错误；3 权限不足或非管理员；
4 用户取消；130 终端中断。
"""

import argparse
import base64
import getpass
import json
import math
import os
import re
import sys
import time
import unicodedata
import urllib.error as urllib_error
import urllib.parse as urllib_parse
import urllib.request as urllib_request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENV_FILE = REPO_ROOT / '.env'
PASSWORD_PROMPT = '管理员密码: '

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_CONFIG = 2
EXIT_FORBIDDEN = 3
EXIT_CANCELLED = 4

API_KEY_NAMES = ('SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY')
# Names this tool must never read as credentials. They are reported, never used.
SECRET_KEY_NAMES = (
    'SUPABASE_SERVICE_ROLE_KEY',
    'SUPABASE_SECRET_KEY',
    'SUPABASE_SECRET_KEYS',
    'SUPABASE_SERVICE_KEY',
    'SB_SECRET_KEY',
)

EMAIL_PATTERN = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
UUID_PATTERN = re.compile(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    re.IGNORECASE,
)
JWT_PATTERN = re.compile(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$')

# PostgREST / GoTrue / Edge Function error payloads are data, never instructions.
SQLSTATE_HINTS = {
    '42501': '管理员权限不足，操作未执行',
    '55000': '目标用户当前不满足该操作条件',
    'PGRST301': '登录状态已失效，请重新登录',
    'PGRST202': '云端缺少所需的数据库函数，请先执行 supabase db push',
}


# --------------------------------------------------------------------------
# Errors
# --------------------------------------------------------------------------


class AdminToolError(Exception):
    """A user-facing failure with a stable process exit code."""

    exit_code = EXIT_ERROR


class ConfigError(AdminToolError):
    exit_code = EXIT_CONFIG


class AuthError(AdminToolError):
    exit_code = EXIT_FORBIDDEN


class ForbiddenError(AdminToolError):
    exit_code = EXIT_FORBIDDEN


class TransportError(AdminToolError):
    exit_code = EXIT_ERROR


class ApiError(AdminToolError):
    exit_code = EXIT_ERROR

    def __init__(self, message: str, *, status: int | None = None, code: str | None = None):
        super().__init__(message)
        self.status = status
        self.code = code


class OperationCancelled(AdminToolError):
    exit_code = EXIT_CANCELLED


# --------------------------------------------------------------------------
# Console and configuration
# --------------------------------------------------------------------------


def configure_console() -> None:
    """Switch Windows console streams to UTF-8 without failing in redirected tests."""

    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, 'reconfigure', None)
        if not callable(reconfigure):
            continue
        try:
            reconfigure(encoding='utf-8', errors='replace')
        except (ValueError, OSError):
            # A wrapped or already-detached stream is not a reason to stop.
            continue


_ENV_ESCAPES = {'n': '\n', 'r': '\r', 't': '\t', '"': '"', '\\': '\\'}


def _unquote_env_value(value: str) -> str:
    """Strip one matching quote pair and any comment outside it.

    A quoted value keeps every character including #; an unquoted value ends at
    a whitespace-preceded #. Values without a closing quote are kept verbatim
    rather than truncated.
    """

    if value[:1] in ('"', "'"):
        quote = value[0]
        characters = []
        escaped = False
        for character in value[1:]:
            if quote == '"' and escaped:
                characters.append(_ENV_ESCAPES.get(character, character))
                escaped = False
                continue
            if quote == '"' and character == '\\':
                escaped = True
                continue
            if character == quote:
                return ''.join(characters)
            characters.append(character)

    comment = re.search(r'\s#', value)
    if comment:
        value = value[: comment.start()].rstrip()
    return value


def read_env_file(path: Path | str) -> dict[str, str]:
    """Read a dotenv file without swallowing quotes or treating inline # as a comment."""

    try:
        text = Path(path).read_text(encoding='utf-8-sig')
    except FileNotFoundError as error:
        raise ConfigError(f'找不到配置文件：{path}') from error
    except OSError as error:
        raise ConfigError(f'无法读取配置文件 {path}：{error}') from error

    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[len('export '):].strip()
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        if not key:
            continue
        values[key] = _unquote_env_value(value.strip())
    return values


def _jwt_role(token: str) -> str | None:
    if not JWT_PATTERN.match(token):
        return None
    payload = token.split('.')[1]
    padding = '=' * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload + padding).decode('utf-8')
        claims = json.loads(decoded)
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    role = claims.get('role') if isinstance(claims, dict) else None
    return role if isinstance(role, str) else None


@dataclass(frozen=True)
class SupabaseConfig:
    url: str
    api_key: str
    api_key_name: str = 'SUPABASE_PUBLISHABLE_KEY'
    source: str = ''
    ignored_secret_keys: tuple[str, ...] = ()


def load_config(
    env_file: Path | str | None = None,
    environ: Mapping[str, str] | None = None,
    default_env_file: Path | str | None = None,
) -> SupabaseConfig:
    """Resolve the public URL and publishable key.

    Precedence is explicit: process environment first, dotenv fills the rest.
    Only the public URL and publishable/anon names are read; service-role names
    are recorded as ignored and never become credentials.
    """

    environment = dict(os.environ) if environ is None else environ
    base_default = Path(default_env_file) if default_env_file is not None else DEFAULT_ENV_FILE
    explicit = env_file not in (None, '')
    path = Path(env_file) if explicit else base_default

    file_values: dict[str, str] = {}
    if explicit or path.exists():
        file_values = read_env_file(path)

    url = (environment.get('SUPABASE_URL') or file_values.get('SUPABASE_URL') or '').strip()

    # Environment variables win as a whole before the dotenv file is consulted,
    # so an environment SUPABASE_ANON_KEY still beats a file publishable key.
    api_key = ''
    api_key_name = ''
    for source_values in (environment, file_values):
        for name in API_KEY_NAMES:
            value = source_values.get(name)
            if value:
                api_key = value.strip()
                api_key_name = name
                break
        if api_key:
            break

    # Presence-only detection: the value of a service-role name is never read.
    ignored = tuple(
        name
        for name in SECRET_KEY_NAMES
        if name in environment or name in file_values
    )

    if not url or not api_key:
        missing = []
        if not url:
            missing.append('SUPABASE_URL')
        if not api_key:
            missing.append('SUPABASE_PUBLISHABLE_KEY（或 SUPABASE_ANON_KEY）')
        ignored_note = ''
        if ignored:
            ignored_note = '；已忽略 ' + '、'.join(ignored)
        raise ConfigError(
            '缺少 ' + '、'.join(missing) + ignored_note
            + '。请在 .env（模板见 .env.example）或环境变量中配置公开的 Supabase URL 与 '
            'publishable key；本工具只使用公开 URL 与 publishable/anon key，'
            '从不读取 service_role / sb_secret_ 密钥。'
        )

    if not url.lower().startswith(('https://', 'http://')):
        raise ConfigError('SUPABASE_URL 必须是以 https:// 或 http:// 开头的完整项目地址。')
    url = url.rstrip('/')

    if api_key.startswith('sb_secret_') or _jwt_role(api_key) == 'service_role':
        raise ConfigError(
            '检测到 service_role / secret key 被放在 publishable key 的位置；'
            '本工具只接受公开的 publishable/anon key，已停止。'
        )

    source = str(path) if file_values else '环境变量'
    return SupabaseConfig(
        url=url,
        api_key=api_key,
        api_key_name=api_key_name or API_KEY_NAMES[0],
        source=source,
        ignored_secret_keys=ignored,
    )


# --------------------------------------------------------------------------
# HTTP transport
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class HttpResponse:
    status: int
    body: bytes = b''
    headers: Mapping[str, str] | None = None

    def text(self) -> str:
        return self.body.decode('utf-8', 'replace')


def _describe_reason(reason: Any) -> str:
    if reason is None:
        return '未知网络错误'
    text = str(reason).strip()
    return text or reason.__class__.__name__


class HttpTransport:
    """urllib-based transport. Injected by tests; never logs headers or bodies."""

    def __init__(self, timeout: float = 30.0):
        self.timeout = timeout

    def request(
        self,
        method: str,
        url: str,
        headers: Mapping[str, str] | None = None,
        body: bytes | None = None,
    ) -> HttpResponse:
        request = urllib_request.Request(
            url,
            data=body,
            headers=dict(headers or {}),
            method=method.upper(),
        )
        try:
            response = urllib_request.urlopen(request, timeout=self.timeout)
        except urllib_error.HTTPError as error:
            try:
                payload = error.read()
            finally:
                error.close()
            return HttpResponse(status=error.code, body=payload, headers=dict(error.headers or {}))
        except urllib_error.URLError as error:
            raise TransportError(f'无法连接云端服务：{_describe_reason(error.reason)}') from error
        except (TimeoutError, OSError, ValueError) as error:
            raise TransportError(f'无法连接云端服务：{_describe_reason(error)}') from error

        try:
            status = getattr(response, 'status', None)
            if status is None:
                status = response.getcode()
            return HttpResponse(
                status=int(status),
                body=response.read(),
                headers=dict(response.headers or {}),
            )
        finally:
            close = getattr(response, 'close', None)
            if callable(close):
                close()


# --------------------------------------------------------------------------
# Payload helpers
# --------------------------------------------------------------------------


def _encode_json(payload: Any) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode('utf-8')


def _safe_json(response: HttpResponse) -> Any:
    if not response.body:
        return None
    try:
        return json.loads(response.body.decode('utf-8'))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return response.text()[:500]


def _extract_error(payload: Any) -> tuple[str, str]:
    if isinstance(payload, dict):
        raw_code = payload.get('code') or payload.get('error_code') or ''
        code = raw_code if isinstance(raw_code, str) else str(raw_code)
        for key in ('message', 'error_description', 'msg', 'error', 'hint'):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return code.strip(), value.strip()
        return code.strip(), ''
    if isinstance(payload, str):
        return '', payload.strip()[:300]
    return '', ''


def _decode_json(response: HttpResponse) -> Any:
    if not response.body:
        return None
    try:
        return json.loads(response.body.decode('utf-8'))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ApiError(
            f'云端返回了无法解析的响应（HTTP {response.status}）。',
            status=response.status,
        ) from error


def redact(text: str, secrets: Sequence[str]) -> str:
    for secret in secrets:
        if secret and len(secret) >= 6:
            text = text.replace(secret, '***')
    return text


def _expires_at(explicit: Any, relative: Any, now: float) -> float | None:
    if isinstance(explicit, (int, float)) and not isinstance(explicit, bool) and explicit > 0:
        return float(explicit)
    if isinstance(relative, (int, float)) and not isinstance(relative, bool) and relative > 0:
        return now + float(relative)
    return None


def parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if text.endswith('Z'):
        text = text[:-1] + '+00:00'
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def format_timestamp(value: datetime | None, tz: Any = None) -> str:
    if value is None:
        return '—'
    zone = tz or datetime.now().astimezone().tzinfo or timezone.utc
    return value.astimezone(zone).strftime('%Y-%m-%d %H:%M')


def normalize_email(value: str) -> str:
    email = (value or '').strip().lower()
    if not EMAIL_PATTERN.match(email):
        raise AdminToolError('请输入有效的邮箱地址。')
    return email


def _display_width(text: str) -> int:
    width = 0
    for character in text:
        width += 2 if unicodedata.east_asian_width(character) in ('W', 'F') else 1
    return width


def format_table(headers: Sequence[str], rows: Sequence[Sequence[Any]]) -> list[str]:
    """Render a CJK-aware aligned text table."""

    rendered_headers = [str(header) for header in headers]
    rendered_rows = [[('' if cell is None else str(cell)) for cell in row] for row in rows]
    widths = [_display_width(header) for header in rendered_headers]
    for row in rendered_rows:
        for index in range(len(rendered_headers)):
            cell = row[index] if index < len(row) else ''
            widths[index] = max(widths[index], _display_width(cell))

    def render(cells: Sequence[str]) -> str:
        padded = []
        for index, cell in enumerate(cells):
            padded.append(cell + ' ' * (widths[index] - _display_width(cell)))
        return '  '.join(padded).rstrip()

    lines = [render(rendered_headers), '  '.join('-' * width for width in widths)]
    for row in rendered_rows:
        cells = [(row[index] if index < len(row) else '') for index in range(len(rendered_headers))]
        lines.append(render(cells))
    return lines


# --------------------------------------------------------------------------
# Typed server rows
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class UserLifecycle:
    user_id: str
    email: str
    created_at: datetime | None = None
    is_suspended: bool = False
    suspended_at: datetime | None = None
    restored_at: datetime | None = None
    purge_eligible_at: datetime | None = None
    is_eligible_for_purge: bool = False

    @classmethod
    def from_row(cls, row: Mapping[str, Any]) -> 'UserLifecycle':
        return cls(
            user_id=str(row.get('user_id') or ''),
            email=str(row.get('email') or ''),
            created_at=parse_timestamp(row.get('created_at')),
            is_suspended=row.get('is_suspended') is True,
            suspended_at=parse_timestamp(row.get('suspended_at')),
            restored_at=parse_timestamp(row.get('restored_at')),
            purge_eligible_at=parse_timestamp(row.get('purge_eligible_at')),
            is_eligible_for_purge=row.get('is_eligible_for_purge') is True,
        )

    @property
    def display_name(self) -> str:
        return self.email or self.user_id

    def status_label(self, now: datetime | None = None) -> str:
        if not self.is_suspended:
            return '正常'
        if self.is_eligible_for_purge:
            return '已停用(已满30天可删)'
        if self.purge_eligible_at is None:
            return '已停用(剩30天可删)'
        moment = now or datetime.now(timezone.utc)
        remaining = (self.purge_eligible_at - moment).total_seconds()
        days = max(0, math.ceil(remaining / 86400))
        return f'已停用(剩{days}天可删)'


@dataclass(frozen=True)
class Eligibility:
    identifier: str
    identifier_type: str
    created_at: datetime | None = None
    used_at: datetime | None = None
    used_user_id: str = ''
    revoked_at: datetime | None = None
    purge_completed_at: datetime | None = None

    @classmethod
    def from_row(cls, row: Mapping[str, Any]) -> 'Eligibility':
        return cls(
            identifier=str(row.get('identifier') or ''),
            identifier_type=str(row.get('identifier_type') or ''),
            created_at=parse_timestamp(row.get('created_at')),
            used_at=parse_timestamp(row.get('used_at')),
            used_user_id=str(row.get('used_user_id') or ''),
            revoked_at=parse_timestamp(row.get('revoked_at')),
            purge_completed_at=parse_timestamp(row.get('purge_completed_at')),
        )

    def status_label(self) -> str:
        if self.purge_completed_at is not None:
            return '已清除可重发'
        if self.used_at is not None:
            return '已使用'
        if self.revoked_at is not None:
            return '已撤销'
        return '待使用'


ELIGIBILITY_QUERY = (
    '/rest/v1/registration_eligibility'
    '?select=id,identifier,identifier_type,created_at,used_at,used_user_id,revoked_at,purge_completed_at'
    '&order=created_at.desc'
)


def render_user_table(
    users: Sequence[UserLifecycle],
    now: datetime | None = None,
    tz: Any = None,
) -> list[str]:
    moment = now or datetime.now(timezone.utc)
    rows = []
    for index, user in enumerate(users, start=1):
        if user.is_suspended:
            window = f'停用 {format_timestamp(user.suspended_at, tz)}'
        elif user.restored_at is not None:
            window = f'恢复 {format_timestamp(user.restored_at, tz)}'
        else:
            window = '—'
        rows.append(
            [
                index,
                user.email or '（无邮箱）',
                user.status_label(moment),
                format_timestamp(user.created_at, tz),
                window,
                user.user_id,
            ]
        )
    return format_table(('编号', '邮箱', '状态', '创建时间', '停用/恢复时间', 'UUID'), rows)


def render_eligibility_table(
    rows: Sequence[Eligibility],
    tz: Any = None,
) -> list[str]:
    rendered = []
    for index, row in enumerate(rows, start=1):
        rendered.append(
            [
                index,
                row.identifier,
                row.identifier_type,
                row.status_label(),
                format_timestamp(row.created_at, tz),
                format_timestamp(row.used_at, tz),
                row.used_user_id or '—',
                format_timestamp(row.purge_completed_at, tz),
            ]
        )
    return format_table(
        ('编号', '邮箱/标识', '类型', '状态', '创建时间', '使用时间', '关联用户', '清除时间'),
        rendered,
    )


def summarize_users(users: Sequence[UserLifecycle]) -> str:
    suspended = sum(1 for user in users if user.is_suspended)
    eligible = sum(1 for user in users if user.is_eligible_for_purge)
    return (
        f'统计：共 {len(users)} 个账号；已停用 {suspended} 个；'
        f'已满 30 天可清除 {eligible} 个。'
    )


def summarize_eligibilities(rows: Sequence[Eligibility]) -> str:
    counts = {'待使用': 0, '已使用': 0, '已撤销': 0, '已清除可重发': 0}
    for row in rows:
        counts[row.status_label()] = counts.get(row.status_label(), 0) + 1
    return (
        f'统计：共 {len(rows)} 条注册资格；待使用 {counts["待使用"]}；'
        f'已使用 {counts["已使用"]}；已撤销 {counts["已撤销"]}；'
        f'已清除可重发 {counts["已清除可重发"]}。'
    )


# --------------------------------------------------------------------------
# Supabase client
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Session:
    access_token: str
    refresh_token: str
    user_id: str
    email: str
    expires_at: float | None = None

    def is_expiring(self, now: float, skew: float = 30.0) -> bool:
        if self.expires_at is None:
            return False
        return now >= self.expires_at - skew


class SupabaseAdminClient:
    """Thin, testable client for the administrator RPCs and Edge Functions."""

    def __init__(
        self,
        config: SupabaseConfig,
        transport: Any,
        *,
        clock: Callable[[], float] | None = None,
    ):
        self._config = config
        self._transport = transport
        self._clock = clock or time.time
        self._session: Session | None = None
        self._secrets: list[str] = [config.api_key]

    @property
    def config(self) -> SupabaseConfig:
        return self._config

    @property
    def session(self) -> Session | None:
        return self._session

    @property
    def user_id(self) -> str:
        if self._session is None:
            raise AuthError('请先以管理员身份登录。')
        return self._session.user_id

    @property
    def email(self) -> str:
        return self._session.email if self._session is not None else ''

    def _register_secret(self, value: str) -> None:
        if value and len(value) >= 6 and value not in self._secrets:
            self._secrets.append(value)

    def _redact(self, text: str) -> str:
        return redact(text, self._secrets)

    def _url(self, path: str) -> str:
        return f'{self._config.url}{path}'

    def _headers(self, authenticated: bool) -> dict[str, str]:
        headers = {
            'apikey': self._config.api_key,
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        }
        if authenticated:
            if self._session is None:
                raise AuthError('请先以管理员身份登录。')
            headers['Authorization'] = f'Bearer {self._session.access_token}'
        return headers

    # -- authentication ----------------------------------------------------

    def login(self, email: str, password: str) -> Session:
        normalized = (email or '').strip().lower()
        if not normalized:
            raise AuthError('请输入管理员邮箱。')
        if not password:
            raise AuthError('请输入管理员密码。')
        self._register_secret(password)

        response = self._transport.request(
            'POST',
            self._url('/auth/v1/token?grant_type=password'),
            headers=self._headers(authenticated=False),
            body=_encode_json({'email': normalized, 'password': password}),
        )
        if response.status >= 400:
            self._session = None
            raise AuthError(self._login_error_message(response))

        payload = _decode_json(response)
        self._session = self._session_from_payload(payload, normalized)
        return self._session

    def _login_error_message(self, response: HttpResponse) -> str:
        payload = _safe_json(response)
        code, message = _extract_error(payload)
        raw_codes = ''
        if isinstance(payload, dict):
            for name in ('error', 'error_code', 'code'):
                value = payload.get(name)
                if isinstance(value, str):
                    raw_codes += f' {value}'
        lowered = f'{code} {message}{raw_codes}'.lower()
        if (
            'invalid_credentials' in lowered
            or 'invalid_grant' in lowered
            or 'invalid login' in lowered
        ):
            return '管理员邮箱或密码不正确。'
        if 'email_not_confirmed' in lowered:
            return '该账号尚未确认邮箱，无法登录。'
        return self._compose_error('登录失败', response)

    def _session_from_payload(self, payload: Any, fallback_email: str) -> Session:
        if not isinstance(payload, dict):
            raise AuthError('登录响应格式不正确。')
        access = payload.get('access_token')
        refresh = payload.get('refresh_token')
        if not isinstance(access, str) or not access:
            raise AuthError('登录响应缺少访问令牌。')
        if not isinstance(refresh, str) or not refresh:
            raise AuthError('登录响应缺少刷新令牌。')
        user = payload.get('user') if isinstance(payload.get('user'), dict) else {}
        user_id = user.get('id')
        if not isinstance(user_id, str) or not user_id:
            raise AuthError('登录响应缺少用户标识。')
        self._register_secret(access)
        self._register_secret(refresh)
        return Session(
            access_token=access,
            refresh_token=refresh,
            user_id=user_id,
            email=str(user.get('email') or fallback_email).strip().lower(),
            expires_at=_expires_at(payload.get('expires_at'), payload.get('expires_in'), self._clock()),
        )

    def _refresh_session(self) -> None:
        if self._session is None or not self._session.refresh_token:
            raise AuthError('登录状态已过期，请重新登录。')
        response = self._transport.request(
            'POST',
            self._url('/auth/v1/token?grant_type=refresh_token'),
            headers=self._headers(authenticated=False),
            body=_encode_json({'refresh_token': self._session.refresh_token}),
        )
        if response.status >= 400:
            self._session = None
            raise AuthError('登录状态已过期，请重新登录。')

        payload = _decode_json(response)
        if not isinstance(payload, dict):
            raise AuthError('刷新登录状态失败，请重新登录。')
        access = payload.get('access_token')
        if not isinstance(access, str) or not access:
            raise AuthError('刷新登录状态失败，请重新登录。')
        refresh = payload.get('refresh_token')
        if not isinstance(refresh, str) or not refresh:
            refresh = self._session.refresh_token
        user = payload.get('user') if isinstance(payload.get('user'), dict) else {}
        user_id = user.get('id')
        if not isinstance(user_id, str) or not user_id:
            user_id = self._session.user_id
        expires_at = _expires_at(payload.get('expires_at'), payload.get('expires_in'), self._clock())
        self._register_secret(access)
        self._register_secret(refresh)
        self._session = Session(
            access_token=access,
            refresh_token=refresh,
            user_id=user_id,
            email=self._session.email,
            expires_at=expires_at if expires_at is not None else self._session.expires_at,
        )

    # -- request pipeline --------------------------------------------------

    def _send(
        self,
        method: str,
        path: str,
        body: bytes | None = None,
        *,
        authenticated: bool = True,
    ) -> HttpResponse:
        if (
            authenticated
            and self._session is not None
            and self._session.is_expiring(self._clock())
        ):
            self._refresh_session()

        response = self._transport.request(
            method,
            self._url(path),
            headers=self._headers(authenticated),
            body=body,
        )
        if response.status != 401 or not authenticated:
            return response
        if self._session is None:
            raise AuthError('登录状态已失效，请重新登录。')

        self._refresh_session()
        retried = self._transport.request(
            method,
            self._url(path),
            headers=self._headers(True),
            body=body,
        )
        if retried.status == 401:
            raise AuthError('登录状态已失效，请重新登录。')
        return retried

    def _compose_error(self, context: str, response: HttpResponse) -> str:
        payload = _safe_json(response)
        code, message = _extract_error(payload)
        text = context
        if message and message not in context:
            text = f'{text}：{message}'
        if code:
            text = f'{text}（错误码 {code}）'
        text = f'{text}（HTTP {response.status}）'
        return self._redact(text)

    def _api_error(self, response: HttpResponse, context: str) -> AdminToolError:
        if response.status == 401:
            return AuthError('登录状态已失效，请重新登录。')
        if response.status == 403:
            return ForbiddenError('当前账号没有执行该操作的权限。')
        code, _ = _extract_error(_safe_json(response))
        if code in SQLSTATE_HINTS and response.status not in (409, 500):
            return ApiError(self._redact(f'{SQLSTATE_HINTS[code]}（HTTP {response.status}）'), status=response.status, code=code)
        return ApiError(self._compose_error(context, response), status=response.status, code=code or None)

    def _expect(self, response: HttpResponse, context: str) -> Any:
        if response.status >= 400:
            raise self._api_error(response, context)
        if response.status == 204 or not response.body:
            return None
        return _decode_json(response)

    def _rpc(self, name: str, payload: Mapping[str, Any], context: str) -> Any:
        response = self._send(
            'POST',
            f'/rest/v1/rpc/{name}',
            _encode_json(dict(payload)),
        )
        return self._expect(response, context)

    # -- administration ----------------------------------------------------

    def verify_admin(self) -> bool:
        user_id = urllib_parse.quote(self.user_id, safe='')
        response = self._send(
            'GET',
            f'/rest/v1/app_admins?select=user_id&user_id=eq.{user_id}',
        )
        data = self._expect(response, '无法确认管理员权限')
        if not isinstance(data, list) or not data:
            raise ForbiddenError('该账号不是 Pacta 管理员，已停止所有管理操作。')
        return True

    def list_users(self) -> list[UserLifecycle]:
        data = self._rpc('admin_list_user_lifecycles', {}, '读取用户列表失败')
        if not isinstance(data, list):
            raise ApiError('用户列表响应格式不正确。')
        return [
            UserLifecycle.from_row(row)
            for row in data
            if isinstance(row, dict)
        ]

    def list_eligibilities(self) -> list[Eligibility]:
        response = self._send('GET', ELIGIBILITY_QUERY)
        data = self._expect(response, '读取注册资格列表失败')
        if not isinstance(data, list):
            raise ApiError('注册资格响应格式不正确。')
        return [
            Eligibility.from_row(row)
            for row in data
            if isinstance(row, dict)
        ]

    def grant_eligibility(self, email: str) -> Eligibility | None:
        normalized = normalize_email(email)
        data = self._rpc(
            'admin_grant_registration_eligibility',
            {'p_identifier': normalized, 'p_identifier_type': 'email'},
            '发放注册资格失败',
        )
        if isinstance(data, list):
            data = data[0] if data else None
        return Eligibility.from_row(data) if isinstance(data, dict) else None

    def revoke_eligibility(self, email: str) -> bool:
        normalized = normalize_email(email)
        data = self._rpc(
            'admin_revoke_registration_eligibility',
            {'p_identifier': normalized, 'p_identifier_type': 'email'},
            '撤销注册资格失败',
        )
        if isinstance(data, list):
            data = data[0] if data else False
        return data is True

    def resolve_user(self, target: str) -> UserLifecycle:
        text = (target or '').strip()
        if not text:
            raise AdminToolError('请输入目标用户邮箱或 UUID。')
        users = self.list_users()
        if UUID_PATTERN.match(text):
            wanted = text.lower()
            for user in users:
                if user.user_id.lower() == wanted:
                    return user
            raise AdminToolError(f'用户列表中找不到 UUID {text} 对应的账号。')
        wanted = text.lower()
        for user in users:
            if user.email.strip().lower() == wanted:
                return user
        raise AdminToolError(f'用户列表中找不到邮箱 {text} 对应的账号。')

    def is_admin_user(self, user_id: str) -> bool:
        quoted = urllib_parse.quote(user_id, safe='')
        response = self._send(
            'GET',
            f'/rest/v1/app_admins?select=user_id&user_id=eq.{quoted}',
        )
        data = self._expect(response, '无法确认目标用户的管理员身份')
        return isinstance(data, list) and bool(data)

    def ensure_purge_target_allowed(self, user: UserLifecycle) -> None:
        if user.user_id == self.user_id:
            raise ForbiddenError('不能清除当前登录的管理员账号。')
        if self.is_admin_user(user.user_id):
            raise ForbiddenError(
                '不能清除另一位管理员账号；请先通过受控流程取消其管理员身份。'
            )

    def suspend_user(self, user_id: str) -> None:
        self._rpc('admin_suspend_user', {'p_user_id': user_id}, '停用用户失败')

    def restore_user(self, user_id: str) -> None:
        self._rpc('admin_restore_user', {'p_user_id': user_id}, '恢复用户失败')

    def reset_password(self, email: str, new_password: str) -> Any:
        self._register_secret(new_password)
        response = self._send(
            'POST',
            '/functions/v1/admin-reset-user-password',
            _encode_json(
                {
                    'email': normalize_email(email),
                    'new_password': new_password,
                    'manual_verification_confirmed': True,
                }
            ),
        )
        return self._expect(response, '重置密码失败')

    def purge_user(self, user_id: str, *, immediate: bool = False) -> Mapping[str, Any]:
        response = self._send(
            'POST',
            '/functions/v1/admin-purge-user',
            _encode_json({'user_id': user_id, 'immediate': bool(immediate)}),
        )
        if response.status == 409:
            if immediate:
                raise ApiError(
                    '云端仍拒绝立即清除（HTTP 409）。请确认已执行 supabase db push'
                    '（应用 202611220001_admin_immediate_purge.sql）与 '
                    'supabase functions deploy admin-purge-user，然后重试。',
                    status=409,
                )
            raise ApiError(
                '目标用户当前不能清除（HTTP 409）。若处于测试期，可先执行 supabase db push'
                '（应用 202611220001_admin_immediate_purge.sql）与 '
                'supabase functions deploy admin-purge-user，然后加 --immediate 立即清除。',
                status=409,
            )
        result = self._expect(response, '清除用户失败')
        if not isinstance(result, dict):
            raise ApiError('清除响应格式不正确，未取得已完成回执。')
        if result.get('user_id') != user_id:
            raise ApiError('清除响应绑定了其他用户，未确认完成；请勿在本地删除任何数据。')
        if result.get('status') != 'completed':
            raise ApiError('清除尚未完成，请勿在本地删除任何数据。')
        if not isinstance(result.get('purged_at'), str) or not result['purged_at']:
            raise ApiError('清除响应缺少完成时间，未确认完成。')
        return result


# --------------------------------------------------------------------------
# Console IO and confirmations
# --------------------------------------------------------------------------


class ConsoleIO:
    def __init__(
        self,
        out: Any = None,
        err: Any = None,
        input_fn: Callable[[str], str] | None = None,
        getpass_fn: Callable[[str], str] | None = None,
    ):
        self.out = out if out is not None else sys.stdout
        self.err = err if err is not None else sys.stderr
        self._input = input_fn if input_fn is not None else input
        self._getpass = getpass_fn if getpass_fn is not None else getpass.getpass

    def write(self, text: str = '') -> None:
        print(text, file=self.out)

    def error(self, text: str) -> None:
        print(text, file=self.err)

    def prompt(self, label: str) -> str:
        return self._input(label)

    def password(self, label: str) -> str:
        return self._getpass(label)


def confirm(io: ConsoleIO, label: str) -> bool:
    return io.prompt(label).strip().lower() in ('yes', 'y')


def confirm_target_deletion(io: ConsoleIO, user: UserLifecycle) -> None:
    """Require the operator to type the target email (or UUID) verbatim."""

    expected = user.email or user.user_id
    label = '邮箱' if user.email else 'UUID'
    entered = io.prompt(f'此操作不可恢复。请逐字输入目标{label} {expected} 以确认: ')
    if entered.strip().lower() != expected.strip().lower():
        raise OperationCancelled('输入与目标不一致，清除操作未执行。')


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def show_users(client: SupabaseAdminClient, io: ConsoleIO) -> None:
    users = client.list_users()
    io.write(f'云端账号 {len(users)} 个')
    for line in render_user_table(users):
        io.write(line)
    io.write(summarize_users(users))
    io.write('查看注册邮箱列表：python scripts/pacta_admin.py eligibilities')


def show_eligibilities(client: SupabaseAdminClient, io: ConsoleIO) -> None:
    rows = client.list_eligibilities()
    io.write(f'注册资格 {len(rows)} 条')
    for line in render_eligibility_table(rows):
        io.write(line)
    io.write(summarize_eligibilities(rows))


def command_grant(client: SupabaseAdminClient, io: ConsoleIO, email: str) -> None:
    normalized = normalize_email(email)
    record = client.grant_eligibility(normalized)
    status = record.status_label() if record is not None else '已提交'
    io.write(f'已发放注册资格：{normalized}（{status}）')


def command_revoke(client: SupabaseAdminClient, io: ConsoleIO, email: str) -> None:
    normalized = normalize_email(email)
    changed = client.revoke_eligibility(normalized)
    if changed:
        io.write(f'已撤销未使用的注册资格：{normalized}')
    else:
        io.write(f'没有撤销任何资格：{normalized} 不存在、已被使用或已撤销。')


def command_suspend(client: SupabaseAdminClient, io: ConsoleIO, target: str) -> None:
    user = client.resolve_user(target)
    io.write(f'目标：{user.display_name}（UUID {user.user_id}）')
    io.write(f'当前状态：{user.status_label()}')
    if not confirm(io, '确认停用该账号？输入 yes 继续: '):
        raise OperationCancelled('停用操作未执行。')
    client.suspend_user(user.user_id)
    io.write(f'已停用：{user.display_name}')


def command_restore(client: SupabaseAdminClient, io: ConsoleIO, target: str) -> None:
    user = client.resolve_user(target)
    io.write(f'目标：{user.display_name}（UUID {user.user_id}）')
    io.write(f'当前状态：{user.status_label()}')
    if not confirm(io, '确认恢复该账号？输入 yes 继续: '):
        raise OperationCancelled('恢复操作未执行。')
    client.restore_user(user.user_id)
    io.write(f'已恢复：{user.display_name}')


def command_reset_password(client: SupabaseAdminClient, io: ConsoleIO, email: str) -> None:
    normalized = normalize_email(email)
    user = client.resolve_user(normalized)
    io.write(f'目标：{user.display_name}（UUID {user.user_id}）')
    io.write(f'当前状态：{user.status_label()}')
    password = io.password('新密码: ')
    repeated = io.password('再次输入新密码: ')
    if password != repeated:
        raise AdminToolError('两次输入的新密码不一致，操作未执行。')
    if not 8 <= len(password) <= 256:
        raise AdminToolError('新密码长度必须为 8 至 256 个字符。')
    if not confirm(io, '已线下人工核实目标身份？输入 yes 继续: '):
        raise OperationCancelled('重置密码操作未执行。')
    client.reset_password(normalized, password)
    io.write('密码已重置。请通过安全渠道告知用户新密码。')


def command_delete_user(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    target: str,
    *,
    immediate: bool = False,
    allow_prompt: bool = True,
) -> None:
    user = client.resolve_user(target)
    client.ensure_purge_target_allowed(user)
    moment = datetime.now(timezone.utc)
    io.write(f'目标：{user.display_name}（UUID {user.user_id}）')
    io.write(f'当前状态：{user.status_label(moment)}')

    if not user.is_eligible_for_purge and not immediate:
        if not allow_prompt:
            if user.purge_eligible_at is not None:
                wait = f'（{format_timestamp(user.purge_eligible_at)} 后可清除）'
            elif user.is_suspended:
                wait = '（停用时间缺失，无法计算可清除时间）'
            else:
                wait = '（目标当前未停用，需先停用并等待 30 天）'
            raise AdminToolError(
                '目标用户尚未满足 30 天停用等待' + wait + '。'
                '测试期可加 --immediate 立即清除。'
            )
        answer = io.prompt(
            '目标未满足 30 天停用等待条件，是否使用测试期立即清除（immediate=true）？'
            '输入 yes 使用，直接回车取消: '
        )
        if answer.strip().lower() not in ('yes', 'y'):
            raise OperationCancelled(
                '清除操作未执行；目标可按规则等待，或使用 --immediate 在测试期立即清除。'
            )
        immediate = True

    io.write(f'将永久清除该账号（immediate={str(immediate).lower()}）。')
    confirm_target_deletion(io, user)
    result = client.purge_user(user.user_id, immediate=immediate)
    purged_at = result.get('purged_at')
    io.write(f'已完成永久清除：{user.display_name}（purged_at={purged_at}）')


# --------------------------------------------------------------------------
# Interactive menu
# --------------------------------------------------------------------------


MENU_OPTIONS = (
    ('1', '查看用户列表'),
    ('2', '查看注册资格'),
    ('3', '发放注册资格'),
    ('4', '撤销未用注册资格'),
    ('5', '停用用户'),
    ('6', '恢复用户'),
    ('7', '重置用户密码'),
    ('8', '删除/永久清除用户'),
)


def dispatch_menu(choice: str, client: SupabaseAdminClient, io: ConsoleIO) -> None:
    if choice == '1':
        show_users(client, io)
    elif choice == '2':
        show_eligibilities(client, io)
    elif choice == '3':
        command_grant(client, io, io.prompt('注册邮箱: '))
    elif choice == '4':
        command_revoke(client, io, io.prompt('注册邮箱: '))
    elif choice == '5':
        command_suspend(client, io, io.prompt('目标用户邮箱或 UUID: '))
    elif choice == '6':
        command_restore(client, io, io.prompt('目标用户邮箱或 UUID: '))
    elif choice == '7':
        command_reset_password(client, io, io.prompt('目标用户邮箱: '))
    elif choice == '8':
        command_delete_user(
            client,
            io,
            io.prompt('目标用户邮箱或 UUID: '),
            allow_prompt=True,
        )
    else:
        io.error('无效选项，请输入 0 至 8。')


def run_menu(client: SupabaseAdminClient, io: ConsoleIO) -> None:
    while True:
        io.write('')
        io.write('Pacta 云端管理')
        for key, label in MENU_OPTIONS:
            io.write(f'  {key}. {label}')
        io.write('  0. 退出')
        try:
            choice = io.prompt('请选择操作: ').strip()
        except EOFError:
            io.write('')
            return
        if choice in ('0', 'q', 'quit', 'exit'):
            return
        try:
            dispatch_menu(choice, client, io)
        except OperationCancelled as error:
            io.error(f'已取消：{error}')
        except AdminToolError as error:
            io.error(f'错误：{error}')


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        '--env-file',
        default=argparse.SUPPRESS,
        help='dotenv 文件路径（默认仓库根目录 .env；环境变量优先）',
    )
    common.add_argument(
        '--email',
        default=argparse.SUPPRESS,
        help='管理员登录邮箱（省略时交互输入）',
    )

    parser = argparse.ArgumentParser(
        parents=[common],
        description='Pacta 云端管理员终端工具。只使用公开 URL 与 publishable/anon key。',
        epilog=(
            '示例：\n'
            '  python scripts/pacta_admin.py\n'
            '  python scripts/pacta_admin.py users\n'
            '  python scripts/pacta_admin.py grant person@example.com\n'
            '  python scripts/pacta_admin.py delete-user person@example.com --immediate\n'
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    # Keep env_file/email on argparse.SUPPRESS: parent actions are shared with
    # every subparser, so a global default here would erase a value parsed
    # before the subcommand. main() reads them with getattr instead.
    parser.set_defaults(command=None, immediate=False)

    subparsers = parser.add_subparsers(dest='command', metavar='命令')
    subparsers.add_parser(
        'users',
        parents=[common],
        help='查看用户列表与生命周期状态',
    )
    subparsers.add_parser(
        'eligibilities',
        parents=[common],
        help='查看注册资格与状态',
    )

    grant = subparsers.add_parser('grant', parents=[common], help='发放注册资格')
    grant.add_argument('email_target', metavar='EMAIL', help='要发放的注册邮箱')

    revoke = subparsers.add_parser('revoke', parents=[common], help='撤销未使用的注册资格')
    revoke.add_argument('email_target', metavar='EMAIL', help='要撤销的注册邮箱')

    suspend = subparsers.add_parser('suspend', parents=[common], help='停用用户')
    suspend.add_argument('target', metavar='TARGET', help='目标用户邮箱或 UUID')

    restore = subparsers.add_parser('restore', parents=[common], help='恢复用户')
    restore.add_argument('target', metavar='TARGET', help='目标用户邮箱或 UUID')

    reset = subparsers.add_parser(
        'reset-password',
        parents=[common],
        help='重置用户密码（需线下人工核实）',
    )
    reset.add_argument('email_target', metavar='EMAIL', help='目标用户邮箱')

    delete = subparsers.add_parser(
        'delete-user',
        parents=[common],
        help='永久清除用户（测试期可 --immediate）',
    )
    delete.add_argument('target', metavar='TARGET', help='目标用户邮箱或 UUID')
    delete.add_argument(
        '--immediate',
        action='store_true',
        help=(
            '测试期立即清除，跳过 30 天停用等待'
            '（需先 supabase db push 并执行 supabase functions deploy admin-purge-user）'
        ),
    )
    return parser


def run_command(
    client: SupabaseAdminClient,
    args: argparse.Namespace,
    io: ConsoleIO,
) -> None:
    command = args.command
    if command == 'users':
        show_users(client, io)
    elif command == 'eligibilities':
        show_eligibilities(client, io)
    elif command == 'grant':
        command_grant(client, io, args.email_target)
    elif command == 'revoke':
        command_revoke(client, io, args.email_target)
    elif command == 'suspend':
        command_suspend(client, io, args.target)
    elif command == 'restore':
        command_restore(client, io, args.target)
    elif command == 'reset-password':
        command_reset_password(client, io, args.email_target)
    elif command == 'delete-user':
        command_delete_user(
            client,
            io,
            args.target,
            immediate=bool(getattr(args, 'immediate', False)),
            allow_prompt=False,
        )
    else:
        raise AdminToolError('未知命令。')


def main(
    argv: Sequence[str] | None = None,
    *,
    transport: Any = None,
    environ: Mapping[str, str] | None = None,
    out: Any = None,
    err: Any = None,
    input_fn: Callable[[str], str] | None = None,
    getpass_fn: Callable[[str], str] | None = None,
    clock: Callable[[], float] | None = None,
) -> int:
    configure_console()
    io = ConsoleIO(out, err, input_fn, getpass_fn)
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        config = load_config(getattr(args, 'env_file', None), environ)
        if config.ignored_secret_keys:
            io.write(
                '提示：已忽略配置中的 '
                + '、'.join(config.ignored_secret_keys)
                + '；本工具只使用公开 URL 与 publishable/anon key。'
            )

        client = SupabaseAdminClient(
            config,
            transport if transport is not None else HttpTransport(),
            clock=clock,
        )

        email = getattr(args, 'email', '') or ''
        if not email:
            email = io.prompt('管理员邮箱: ').strip()
        if not email:
            raise AdminToolError('请输入管理员邮箱。')
        password = io.password(PASSWORD_PROMPT)
        client.login(email, password)
        client.verify_admin()
        io.write(f'已登录管理员：{client.email}（配置来源：{config.source}）')

        if args.command is None:
            run_menu(client, io)
        else:
            run_command(client, args, io)
        return EXIT_OK
    except OperationCancelled as error:
        io.error(f'已取消：{error}')
        return error.exit_code
    except AdminToolError as error:
        io.error(f'错误：{error}')
        return error.exit_code
    except EOFError:
        io.error('输入结束，已退出。')
        return EXIT_CANCELLED
    except KeyboardInterrupt:
        io.error('已中断，未执行未完成的操作。')
        return 130


if __name__ == '__main__':
    sys.exit(main())
