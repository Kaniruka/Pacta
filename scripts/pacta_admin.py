#!/usr/bin/env python3
"""Pacta 项目主直连终端工具（Windows PowerShell 可用）。

本工具以 Supabase 项目主（Project Owner）身份直连管理接口，不需要任何
管理员占位账号、邮箱密码登录或 app_admins 资格。配置只从进程环境变量与
仓库根目录 .env 读取 SUPABASE_URL 与 SUPABASE_SECRET_KEY（兼容旧名
SUPABASE_SERVICE_ROLE_KEY），密钥只存在于当前进程内，绝不写入日志、JSON
输出或任何文件。

Supabase 请求头规则（官方规范）：

* 新版透明密钥（例如 sb_secret_...，不是三段式 JWT）只放在 apikey 头；
  把它同时放进 Authorization: Bearer 会被网关或 GoTrue 当作无效 JWT
  拒绝（401 / Invalid JWT）。
* 旧版 service_role 密钥是三段式 JWT（key.count(".") == 2），需要同时
  发送 apikey 与 Authorization: Bearer <key>。

用法：

    python scripts/pacta_admin.py                    # 交互式数字菜单 0-11
    python scripts/pacta_admin.py users              # 用户生命周期与云端摘要
    python scripts/pacta_admin.py create-user person@example.com --nickname 小明
    python scripts/pacta_admin.py eligibilities      # 查看注册白名单
    python scripts/pacta_admin.py grant person@example.com
    python scripts/pacta_admin.py revoke person@example.com
    python scripts/pacta_admin.py suspend person@example.com
    python scripts/pacta_admin.py restore person@example.com
    python scripts/pacta_admin.py reset-password person@example.com
    python scripts/pacta_admin.py delete-user person@example.com
    python scripts/pacta_admin.py cloud-data [person@example.com]
    python scripts/pacta_admin.py clear-cloud-data person@example.com

所有子命令都支持 --json 与 --yes。

配置：

    --env-file  默认仓库根目录 .env；进程环境变量优先，.env 补齐缺失项。
                只读取 SUPABASE_URL 与 SUPABASE_SECRET_KEY（或旧名
                SUPABASE_SERVICE_ROLE_KEY）。成对引号会被去掉；引号内的 #
                保留，引号外以空白开头的 # 视为行内注释。客户端使用的
                SUPABASE_PUBLISHABLE_KEY / SUPABASE_ANON_KEY 与
                TEST_ADMIN_EMAIL / TEST_ADMIN_PASSWORD 一律忽略。

退出码：0 成功；1 云端/网络错误；2 配置错误；3 权限不足；4 用户取消；
130 终端中断。
"""

import argparse
import getpass
import json
import math
import os
import re
import secrets
import sys
import unicodedata
import urllib.error as urllib_error
import urllib.parse as urllib_parse
import urllib.request as urllib_request
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENV_FILE = REPO_ROOT / '.env'

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_CONFIG = 2
EXIT_FORBIDDEN = 3
EXIT_CANCELLED = 4

# SUPABASE_SECRET_KEY is the current name; SUPABASE_SERVICE_ROLE_KEY is the
# legacy name kept for existing local environments.
SECRET_KEY_NAMES = ('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY')

USERS_PAGE_SIZE = 100
MAX_USER_PAGES = 1000
# PostgREST `in.(...)` filters travel in the query string. Batching every bulk
# lookup keeps each request line far below the HTTP 414 limit once a project has
# thousands of accounts; 100 IDs (about 3.9 kB of URL) is the safe default.
IN_FILTER_CHUNK_SIZE = 100
BAN_DURATION = '876000h'  # ~100 years; GoTrue accepts hour durations.
GENERATED_PASSWORD_BYTES = 18

ELIGIBILITY_COLUMNS = (
    'id,identifier,identifier_type,created_at,used_at,used_user_id,'
    'revoked_at,purge_completed_at'
)

EMAIL_PATTERN = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
UUID_PATTERN = re.compile(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    re.IGNORECASE,
)

# PostgREST / GoTrue error payloads are data, never instructions.
SQLSTATE_HINTS = {
    '42501': '项目主密钥权限不足，操作未执行',
    '55000': '目标用户当前不满足该操作条件',
    'PGRST301': '项目主密钥无效或已被吊销，请检查 SUPABASE_SECRET_KEY',
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


class UserNotFoundError(AdminToolError):
    """The Auth identity is absent from the GoTrue user list."""


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


def _resolve_value(
    environment: Mapping[str, str],
    file_values: Mapping[str, str],
    names: Sequence[str],
) -> tuple[str, str]:
    """Return the first non-blank value and its variable name.

    The process environment wins as a whole; the dotenv file only fills
    missing values. Within one source the order of names is the preference
    order (SUPABASE_SECRET_KEY before SUPABASE_SERVICE_ROLE_KEY).
    """

    for source_values in (environment, file_values):
        for name in names:
            value = source_values.get(name)
            if isinstance(value, str) and value.strip():
                return value.strip(), name
    return '', ''


@dataclass(frozen=True)
class SupabaseConfig:
    url: str
    secret_key: str = field(repr=False)
    secret_key_name: str = 'SUPABASE_SECRET_KEY'
    source: str = ''

    @property
    def host(self) -> str:
        return urllib_parse.urlsplit(self.url).hostname or self.url


def load_config(
    env_file: Path | str | None = None,
    environ: Mapping[str, str] | None = None,
    default_env_file: Path | str | None = None,
) -> SupabaseConfig:
    """Resolve the project URL and project-owner secret key.

    Precedence is explicit: process environment first, dotenv fills the rest.
    Only SUPABASE_URL and the project-owner secret key are read. Client
    publishable/anon keys and TEST_ADMIN_* credentials are never consulted.
    """

    environment = dict(os.environ) if environ is None else dict(environ)
    base_default = Path(default_env_file) if default_env_file is not None else DEFAULT_ENV_FILE
    explicit = env_file not in (None, '')
    path = Path(env_file) if explicit else base_default

    file_values: dict[str, str] = {}
    if explicit or path.exists():
        file_values = read_env_file(path)

    url, _ = _resolve_value(environment, file_values, ('SUPABASE_URL',))
    secret_key, secret_key_name = _resolve_value(environment, file_values, SECRET_KEY_NAMES)

    if not url or not secret_key:
        missing = []
        if not url:
            missing.append('SUPABASE_URL')
        if not secret_key:
            missing.append('SUPABASE_SECRET_KEY（兼容旧名 SUPABASE_SERVICE_ROLE_KEY）')
        raise ConfigError(
            '缺少 ' + '、'.join(missing) + '。请在仓库根目录 .env（模板见 .env.example）'
            '或进程环境变量中配置：\n'
            '  SUPABASE_URL=https://<project-ref>.supabase.co\n'
            '  SUPABASE_SECRET_KEY=<Supabase Dashboard -> Project Settings -> API Keys 中的 secret key>\n'
            '项目主 CLI 直连 Supabase 管理接口，不读取客户端 publishable/anon key，'
            '也不使用 TEST_ADMIN_* 登录信息。'
        )

    if not url.lower().startswith(('https://', 'http://')):
        raise ConfigError('SUPABASE_URL 必须是以 https:// 或 http:// 开头的完整项目地址。')
    url = url.rstrip('/')

    source = str(path) if file_values else '环境变量'
    return SupabaseConfig(
        url=url,
        secret_key=secret_key,
        secret_key_name=secret_key_name or SECRET_KEY_NAMES[0],
        source=source,
    )


# --------------------------------------------------------------------------
# HTTP transport and project-owner headers
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


def _is_jwt_token(value: str) -> bool:
    """Return True for a legacy three-part Supabase JWT.

    Supabase's new secret keys (sb_secret_...) are opaque, not JWTs. They must
    be sent only in the apikey header: putting one in Authorization: Bearer
    makes the gateway / GoTrue reject the request as an invalid JWT (401).
    Legacy service_role keys are three-part JWTs and need both headers.
    """

    if not isinstance(value, str) or not value:
        return False
    parts = value.split('.')
    return len(parts) == 3 and all(parts)


def build_auth_headers(secret_key: str) -> dict[str, str]:
    """Build the project-owner request headers for PostgREST and GoTrue."""

    headers = {
        'apikey': secret_key,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    }
    if _is_jwt_token(secret_key):
        headers['Authorization'] = f'Bearer {secret_key}'
    return headers


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


def _stringify_error_code(value: Any) -> str:
    """Render a PostgREST/GoTrue code without inventing text for booleans."""

    if isinstance(value, str):
        return value.strip()
    if value is None or isinstance(value, bool):
        return ''
    if isinstance(value, (int, float)):
        return str(value)
    return ''


def _extract_error(payload: Any) -> tuple[str, str]:
    if isinstance(payload, dict):
        # GoTrue may answer {"code": 422, "error_code": "email_exists", ...}.
        # The symbolic code is the useful one; falling back to the numeric HTTP
        # duplicate would print "422" twice in the composed message.
        code = _stringify_error_code(payload.get('error_code')) or (
            _stringify_error_code(payload.get('code'))
        )
        for key in ('message', 'error_description', 'msg', 'error', 'hint'):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return code, value.strip()
        return code, ''
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


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


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


def _in_values(values: Sequence[str]) -> str:
    """Build a PostgREST in.("a","b") filter value."""

    quoted = []
    for value in values:
        # Percent-encode everything except the characters that are safe in a
        # PostgREST quoted list. A literal + would be decoded as a space by
        # form-style parsers, so emails such as a+b@example.com must be escaped.
        escaped = urllib_parse.quote(str(value), safe='@.-_')
        quoted.append(f'"{escaped}"')
    return 'in.(' + ','.join(quoted) + ')'


def _chunks(
    values: Sequence[str],
    size: int = IN_FILTER_CHUNK_SIZE,
) -> list[list[str]]:
    """Split filter values into URL-safe batches, dropping duplicates.

    A single `in.(...)` holding every account eventually pushes the request
    line past the server limit and returns HTTP 414. Deduplication is safe
    because each batch is a per-value lookup, not an ordered list.
    """

    unique: list[str] = []
    seen: set[str] = set()
    for value in values:
        text = str(value)
        if not text or text in seen:
            continue
        seen.add(text)
        unique.append(text)
    return [unique[start:start + size] for start in range(0, len(unique), size)]


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _as_int(value: Any) -> int | None:
    """Parse a PostgREST integer that may arrive as a JSON number or text."""

    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        text = value.strip()
        if text and (text.isdigit() or (text[0] == '-' and text[1:].isdigit())):
            return int(text)
    return None


# --------------------------------------------------------------------------
# Typed server rows
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Eligibility:
    identifier: str
    identifier_type: str = 'email'
    eligibility_id: str = ''
    created_at: datetime | None = None
    used_at: datetime | None = None
    used_user_id: str = ''
    revoked_at: datetime | None = None
    purge_completed_at: datetime | None = None

    @classmethod
    def from_row(cls, row: Mapping[str, Any]) -> 'Eligibility':
        return cls(
            identifier=str(row.get('identifier') or ''),
            identifier_type=str(row.get('identifier_type') or 'email'),
            eligibility_id=str(row.get('id') or ''),
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


@dataclass(frozen=True)
class Suspension:
    suspended_at: datetime | None = None
    restored_at: datetime | None = None

    @property
    def is_active(self) -> bool:
        return self.suspended_at is not None and self.restored_at is None

    def purge_eligible_at(self) -> datetime | None:
        if not self.is_active or self.suspended_at is None:
            return None
        return self.suspended_at + timedelta(days=30)

    def status_label(self, now: datetime | None = None) -> str:
        if not self.is_active:
            return '正常'
        eligible = self.purge_eligible_at()
        if eligible is None:
            return '已停用'
        moment = now or datetime.now(timezone.utc)
        remaining = (eligible - moment).total_seconds()
        if remaining <= 0:
            return '已停用（已满 30 天可清除）'
        days = max(0, math.ceil(remaining / 86400))
        return f'已停用（剩 {days} 天可清除）'


@dataclass(frozen=True)
class CloudSnapshot:
    user_id: str = ''
    revision: int | None = None
    schema_version: str = ''
    device_name: str = ''
    data_updated_at: datetime | None = None
    uploaded_at: datetime | None = None
    row_count: int | None = None

    @classmethod
    def from_row(cls, row: Mapping[str, Any]) -> 'CloudSnapshot':
        return cls(
            user_id=str(row.get('user_id') or ''),
            revision=_as_int(row.get('revision')),
            schema_version=str(row.get('schema_version') or ''),
            device_name=str(row.get('device_name') or ''),
            data_updated_at=parse_timestamp(row.get('data_updated_at')),
            uploaded_at=parse_timestamp(row.get('uploaded_at')),
            row_count=_as_int(row.get('row_count')),
        )


@dataclass(frozen=True)
class McpGrants:
    active: int = 0
    revoked: int = 0
    expired: int = 0

    def summary(self) -> str:
        return f'有效 {self.active} / 撤销 {self.revoked} / 过期 {self.expired}'


@dataclass(frozen=True)
class UserRecord:
    user_id: str
    email: str
    created_at: datetime | None = None
    last_sign_in_at: datetime | None = None
    banned_until: datetime | None = None
    display_name: str = ''
    time_zone_id: str = ''
    eligibility: Eligibility | None = None
    suspension: Suspension | None = None
    snapshot: CloudSnapshot | None = None
    history_count: int = 0
    upload_request_count: int = 0
    mcp: McpGrants = field(default_factory=McpGrants)
    legacy_admin: bool = False

    @property
    def display_target(self) -> str:
        return self.email or self.user_id

    def status_label(self, now: datetime | None = None) -> str:
        if self.suspension is not None and self.suspension.is_active:
            return self.suspension.status_label(now)
        if self.banned_until is not None:
            moment = now or datetime.now(timezone.utc)
            if self.banned_until > moment:
                return '已封禁'
        return '正常'

    def eligibility_label(self) -> str:
        return self.eligibility.status_label() if self.eligibility is not None else '—'


# --------------------------------------------------------------------------
# Supabase project-owner client
# --------------------------------------------------------------------------


class SupabaseAdminClient:
    """Thin, testable client for GoTrue Admin and PostgREST as project owner."""

    def __init__(self, config: SupabaseConfig, transport: Any):
        self._config = config
        self._transport = transport

    @property
    def config(self) -> SupabaseConfig:
        return self._config

    def _redact(self, text: str) -> str:
        return redact(text, [self._config.secret_key])

    def _url(self, path: str) -> str:
        return f'{self._config.url}{path}'

    def _headers(self) -> dict[str, str]:
        return build_auth_headers(self._config.secret_key)

    def _send(
        self,
        method: str,
        path: str,
        body: bytes | None = None,
        *,
        headers: Mapping[str, str] | None = None,
    ) -> HttpResponse:
        merged = self._headers()
        if headers:
            merged.update(headers)
        return self._transport.request(method, self._url(path), headers=merged, body=body)

    # -- response pipeline -------------------------------------------------

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
            return AuthError(
                '项目主密钥无效或已被吊销，请检查 SUPABASE_SECRET_KEY。'
            )
        if response.status == 403:
            return ForbiddenError('项目主密钥没有执行该操作的权限。')
        code, _ = _extract_error(_safe_json(response))
        if code in SQLSTATE_HINTS and response.status not in (409, 500):
            return ApiError(
                self._redact(f'{SQLSTATE_HINTS[code]}（HTTP {response.status}）'),
                status=response.status,
                code=code,
            )
        return ApiError(
            self._compose_error(context, response),
            status=response.status,
            code=code or None,
        )

    def _expect(self, response: HttpResponse, context: str) -> Any:
        if response.status >= 400:
            raise self._api_error(response, context)
        if response.status == 204 or not response.body:
            return None
        return _decode_json(response)

    def _rest_list(self, path: str, context: str) -> list[dict[str, Any]]:
        data = self._expect(self._send('GET', path), context)
        if data is None:
            return []
        if not isinstance(data, list):
            raise ApiError(f'{context}：响应格式不正确。')
        return [row for row in data if isinstance(row, dict)]

    def _rest_single(self, path: str, context: str) -> dict[str, Any] | None:
        rows = self._rest_list(path, context)
        return rows[0] if rows else None

    def _rpc(self, name: str, payload: Mapping[str, Any], context: str) -> Any:
        response = self._send(
            'POST',
            f'/rest/v1/rpc/{name}',
            _encode_json(dict(payload)),
        )
        return self._expect(response, context)

    # -- GoTrue Admin API --------------------------------------------------

    def _list_auth_users(self) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        page = 1
        while True:
            data = self._expect(
                self._send(
                    'GET',
                    f'/auth/v1/admin/users?page={page}&per_page={USERS_PAGE_SIZE}',
                ),
                '读取用户列表失败',
            )
            page_rows = data.get('users') if isinstance(data, dict) else data
            if not isinstance(page_rows, list):
                raise ApiError('用户列表响应格式不正确。')
            rows.extend(row for row in page_rows if isinstance(row, dict))

            # GoTrue returns next_page: null on the last page; older versions
            # omit it entirely, so a short page remains the fallback signal.
            if isinstance(data, dict) and 'next_page' in data:
                next_page = data.get('next_page')
                if next_page is None:
                    break
                page = (
                    next_page
                    if isinstance(next_page, int) and next_page > page
                    else page + 1
                )
            else:
                if len(page_rows) < USERS_PAGE_SIZE:
                    break
                page += 1
            if page > MAX_USER_PAGES:
                raise ApiError('用户列表分页超过安全上限，已停止。')
        return rows

    def _update_auth_user(self, user_id: str, payload: Mapping[str, Any]) -> Any:
        quoted = urllib_parse.quote(user_id, safe='')
        return self._expect(
            self._send(
                'PUT',
                f'/auth/v1/admin/users/{quoted}',
                _encode_json(dict(payload)),
            ),
            '更新用户失败',
        )

    def _delete_auth_user(self, user_id: str) -> None:
        quoted = urllib_parse.quote(user_id, safe='')
        response = self._send('DELETE', f'/auth/v1/admin/users/{quoted}')
        if response.status == 404:
            return
        self._expect(response, '删除 Auth 身份失败')

    # -- aggregation -------------------------------------------------------

    def _eligibility_index(
        self,
        user_ids: Sequence[str],
        emails: Sequence[str],
    ) -> dict[str, Eligibility]:
        index: dict[str, Eligibility] = {}
        for column, values in (
            ('identifier', emails),
            ('used_user_id', user_ids),
        ):
            for batch in _chunks(values):
                path = (
                    f'/rest/v1/registration_eligibility'
                    f'?select={ELIGIBILITY_COLUMNS}&{column}={_in_values(batch)}'
                )
                for row in self._rest_list(path, '读取注册资格列表失败'):
                    record = Eligibility.from_row(row)
                    if record.used_user_id:
                        index[record.used_user_id.lower()] = record
                    if record.identifier:
                        index[record.identifier.lower()] = record
        return index

    def _suspension_index(self, user_ids: Sequence[str]) -> dict[str, Suspension]:
        latest: dict[str, Suspension] = {}
        for batch in _chunks(user_ids):
            path = (
                '/rest/v1/user_suspension_periods'
                '?select=user_id,suspended_at,restored_at'
                f'&user_id={_in_values(batch)}'
                '&order=suspended_at.desc'
            )
            for row in self._rest_list(path, '读取停用状态失败'):
                user_id = str(row.get('user_id') or '')
                if not user_id or user_id in latest:
                    continue
                latest[user_id] = Suspension(
                    suspended_at=parse_timestamp(row.get('suspended_at')),
                    restored_at=parse_timestamp(row.get('restored_at')),
                )
        return latest

    def _snapshot_index(self, user_ids: Sequence[str]) -> dict[str, CloudSnapshot]:
        index: dict[str, CloudSnapshot] = {}
        for batch in _chunks(user_ids):
            path = (
                '/rest/v1/cloud_business_snapshots'
                '?select=user_id,revision,schema_version:payload->>schemaVersion,'
                'device_name,data_updated_at,uploaded_at,row_count'
                f'&user_id={_in_values(batch)}'
            )
            for row in self._rest_list(path, '读取云端业务快照失败'):
                record = CloudSnapshot.from_row(row)
                if record.user_id:
                    index[record.user_id] = record
        return index

    def _count_index(self, table: str, user_ids: Sequence[str]) -> dict[str, int]:
        counts: dict[str, int] = {}
        for batch in _chunks(user_ids):
            path = f'/rest/v1/{table}?select=user_id&user_id={_in_values(batch)}'
            for row in self._rest_list(path, f'读取 {table} 失败'):
                user_id = str(row.get('user_id') or '')
                if user_id:
                    counts[user_id] = counts.get(user_id, 0) + 1
        return counts

    def _mcp_index(self, user_ids: Sequence[str]) -> dict[str, McpGrants]:
        now = datetime.now(timezone.utc)
        raw: dict[str, dict[str, int]] = {}
        for batch in _chunks(user_ids):
            path = (
                '/rest/v1/national_focus_mcp_grants'
                '?select=user_id,expires_at,revoked_at'
                f'&user_id={_in_values(batch)}'
            )
            for row in self._rest_list(path, '读取国策 MCP 授权失败'):
                user_id = str(row.get('user_id') or '')
                if not user_id:
                    continue
                counts = raw.setdefault(
                    user_id, {'active': 0, 'revoked': 0, 'expired': 0}
                )
                if row.get('revoked_at'):
                    counts['revoked'] += 1
                    continue
                expires = parse_timestamp(row.get('expires_at'))
                if expires is not None and expires <= now:
                    counts['expired'] += 1
                else:
                    counts['active'] += 1
        return {user_id: McpGrants(**counts) for user_id, counts in raw.items()}

    def _profile_index(self, user_ids: Sequence[str]) -> dict[str, dict[str, Any]]:
        index: dict[str, dict[str, Any]] = {}
        for batch in _chunks(user_ids):
            path = (
                '/rest/v1/profile_accounts'
                '?select=user_id,display_name,time_zone_id'
                f'&user_id={_in_values(batch)}'
            )
            for row in self._rest_list(path, '读取账号资料失败'):
                user_id = str(row.get('user_id') or '')
                if user_id:
                    index[user_id] = row
        return index

    def _id_set(self, table: str, user_ids: Sequence[str]) -> set[str]:
        found: set[str] = set()
        for batch in _chunks(user_ids):
            path = f'/rest/v1/{table}?select=user_id&user_id={_in_values(batch)}'
            found.update(
                str(row.get('user_id'))
                for row in self._rest_list(path, f'读取 {table} 失败')
                if row.get('user_id')
            )
        return found

    def list_users(self) -> list[UserRecord]:
        raw_users = self._list_auth_users()
        if not raw_users:
            return []

        user_ids = [str(row.get('id')) for row in raw_users if row.get('id')]
        emails = [
            str(row.get('email')).strip().lower()
            for row in raw_users
            if row.get('email')
        ]
        if not user_ids:
            return []

        eligibility = self._eligibility_index(user_ids, emails)
        suspensions = self._suspension_index(user_ids)
        snapshots = self._snapshot_index(user_ids)
        history_counts = self._count_index('cloud_business_snapshot_history', user_ids)
        upload_counts = self._count_index(
            'cloud_business_snapshot_upload_requests', user_ids
        )
        mcp = self._mcp_index(user_ids)
        profiles = self._profile_index(user_ids)
        legacy_admins = self._id_set('app_admins', user_ids)

        records: list[UserRecord] = []
        for row in raw_users:
            user_id = str(row.get('id') or '')
            if not user_id:
                continue
            email = str(row.get('email') or '').strip().lower()
            profile = profiles.get(user_id, {})
            records.append(
                UserRecord(
                    user_id=user_id,
                    email=email,
                    created_at=parse_timestamp(row.get('created_at')),
                    last_sign_in_at=parse_timestamp(row.get('last_sign_in_at')),
                    banned_until=parse_timestamp(row.get('banned_until')),
                    display_name=str(profile.get('display_name') or ''),
                    time_zone_id=str(profile.get('time_zone_id') or ''),
                    eligibility=(
                        eligibility.get(user_id)
                        or (eligibility.get(email) if email else None)
                    ),
                    suspension=suspensions.get(user_id),
                    snapshot=snapshots.get(user_id),
                    history_count=history_counts.get(user_id, 0),
                    upload_request_count=upload_counts.get(user_id, 0),
                    mcp=mcp.get(user_id, McpGrants()),
                    legacy_admin=user_id in legacy_admins,
                )
            )
        return records

    def resolve_user(self, target: str) -> UserRecord:
        text = (target or '').strip()
        if not text:
            raise AdminToolError('请输入目标用户邮箱或 UUID。')
        records = self.list_users()
        if UUID_PATTERN.match(text):
            wanted = text.lower()
            for record in records:
                if record.user_id.lower() == wanted:
                    return record
            raise UserNotFoundError(f'用户列表中找不到 UUID {text} 对应的账号。')
        wanted = text.lower()
        for record in records:
            if record.email.lower() == wanted:
                return record
        raise UserNotFoundError(f'用户列表中找不到邮箱 {text} 对应的账号。')

    # -- users -------------------------------------------------------------

    def create_user(
        self,
        email: str,
        *,
        password: str | None = None,
        nickname: str | None = None,
        ensure_eligibility: bool = True,
    ) -> dict[str, Any]:
        normalized = normalize_email(email)
        display_name = (nickname or '').strip()
        if len(display_name) > 128:
            raise AdminToolError('昵称最多 128 个字符。')

        eligibility_record = None
        if ensure_eligibility:
            eligibility_record = self.grant_eligibility(normalized)

        payload: dict[str, Any] = {'email': normalized, 'email_confirm': True}
        if password:
            payload['password'] = password
        if display_name:
            payload['user_metadata'] = {'display_name': display_name}

        data = self._expect(
            self._send('POST', '/auth/v1/admin/users', _encode_json(payload)),
            '创建用户失败',
        )
        if not isinstance(data, dict) or not isinstance(data.get('id'), str):
            raise ApiError('创建用户响应缺少用户标识。')
        user_id = data['id']

        profile = self.upsert_profile(user_id, display_name) if display_name else None
        return {
            'user_id': user_id,
            'email': normalized,
            'display_name': display_name,
            'eligibility': eligibility_record,
            'profile': profile,
        }

    def upsert_profile(self, user_id: str, display_name: str) -> dict[str, Any] | None:
        body = {
            'user_id': user_id,
            'display_name': display_name,
            'updated_at': _now_iso(),
        }
        response = self._send(
            'POST',
            '/rest/v1/profile_accounts?on_conflict=user_id',
            _encode_json(body),
            headers={'Prefer': 'resolution=merge-duplicates,return=representation'},
        )
        data = self._expect(response, '写入账号资料失败')
        if isinstance(data, list):
            return data[0] if data and isinstance(data[0], dict) else None
        return data if isinstance(data, dict) else None

    # -- registration eligibility -----------------------------------------

    def list_eligibilities(self) -> list[Eligibility]:
        path = (
            f'/rest/v1/registration_eligibility?select={ELIGIBILITY_COLUMNS}'
            '&order=created_at.desc'
        )
        return [Eligibility.from_row(row) for row in self._rest_list(path, '读取注册资格列表失败')]

    def _eligibility_lookup(self, email: str) -> dict[str, Any] | None:
        quoted = urllib_parse.quote(email, safe='')
        return self._rest_single(
            f'/rest/v1/registration_eligibility?select={ELIGIBILITY_COLUMNS}'
            f'&identifier=eq.{quoted}&identifier_type=eq.email&limit=1',
            '读取注册资格失败',
        )

    def grant_eligibility(self, email: str) -> Eligibility:
        normalized = normalize_email(email)
        existing = self._eligibility_lookup(normalized)
        if existing is None:
            response = self._send(
                'POST',
                '/rest/v1/registration_eligibility',
                _encode_json({'identifier': normalized, 'identifier_type': 'email'}),
                headers={'Prefer': 'return=representation'},
            )
            data = self._expect(response, '发放注册资格失败')
            row = data[0] if isinstance(data, list) and data else data
            if not isinstance(row, dict):
                raise ApiError('发放注册资格未返回记录。')
            return Eligibility.from_row(row)

        patch: dict[str, Any] | None = None
        if existing.get('purge_completed_at'):
            # A completed purge frees the address for a new grant.
            patch = {
                'used_at': None,
                'used_user_id': None,
                'revoked_at': None,
                'purge_completed_at': None,
            }
        elif existing.get('used_at') is None:
            # Re-granting an unused (possibly revoked) eligibility clears the
            # revocation. A consumed address keeps its used state.
            patch = {'revoked_at': None}
        if patch is None:
            return Eligibility.from_row(existing)

        quoted = urllib_parse.quote(normalized, safe='')
        response = self._send(
            'PATCH',
            f'/rest/v1/registration_eligibility?identifier=eq.{quoted}'
            '&identifier_type=eq.email',
            _encode_json(patch),
            headers={'Prefer': 'return=representation'},
        )
        data = self._expect(response, '发放注册资格失败')
        row = data[0] if isinstance(data, list) and data else data
        if not isinstance(row, dict):
            row = {**existing, **patch}
        return Eligibility.from_row(row)

    def revoke_eligibility(self, email: str) -> bool:
        normalized = normalize_email(email)
        quoted = urllib_parse.quote(normalized, safe='')
        response = self._send(
            'PATCH',
            f'/rest/v1/registration_eligibility?identifier=eq.{quoted}'
            '&identifier_type=eq.email&used_at=is.null',
            _encode_json({'revoked_at': _now_iso()}),
            headers={'Prefer': 'return=representation'},
        )
        data = self._expect(response, '撤销注册资格失败')
        return isinstance(data, list) and bool(data)

    # -- suspension, restore, password ------------------------------------

    def suspend_user(self, user_id: str) -> bool:
        active = self._rest_single(
            '/rest/v1/user_suspension_periods'
            '?select=user_id,suspended_at,restored_at'
            f'&user_id=eq.{urllib_parse.quote(user_id, safe="")}'
            '&restored_at=is.null&limit=1',
            '读取停用状态失败',
        )
        created = False
        if active is None:
            self._expect(
                self._send(
                    'POST',
                    '/rest/v1/user_suspension_periods',
                    _encode_json({'user_id': user_id, 'suspended_at': _now_iso()}),
                    headers={'Prefer': 'return=representation'},
                ),
                '停用用户失败',
            )
            created = True
        self._update_auth_user(user_id, {'ban_duration': BAN_DURATION})
        return created

    def restore_user(self, user_id: str) -> bool:
        receipt = self._get_purge_receipt(user_id)
        if receipt is not None and receipt.get('status') == 'pending':
            raise ApiError('该用户存在进行中的彻底注销回执，无法恢复。')
        response = self._send(
            'PATCH',
            '/rest/v1/user_suspension_periods'
            f'?user_id=eq.{urllib_parse.quote(user_id, safe="")}'
            '&restored_at=is.null',
            _encode_json({'restored_at': _now_iso()}),
            headers={'Prefer': 'return=representation'},
        )
        data = self._expect(response, '恢复用户失败')
        self._update_auth_user(user_id, {'ban_duration': 'none'})
        return isinstance(data, list) and bool(data)

    def reset_password(self, user_id: str, new_password: str) -> Any:
        if not 8 <= len(new_password) <= 256:
            raise AdminToolError('新密码长度必须为 8 至 256 个字符。')
        return self._update_auth_user(user_id, {'password': new_password})

    # -- explicit purge ----------------------------------------------------

    def _get_purge_receipt(self, user_id: str) -> dict[str, Any] | None:
        return self._rest_single(
            '/rest/v1/user_purge_receipts'
            '?select=user_id,status,requested_at,eligibility_id,'
            'business_data_deleted,completed_at'
            f'&user_id=eq.{urllib_parse.quote(user_id, safe="")}&limit=1',
            '读取彻底注销回执失败',
        )

    def _eligibility_id_for_user(self, user_id: str) -> str | None:
        row = self._rest_single(
            '/rest/v1/registration_eligibility?select=id'
            f'&used_user_id=eq.{urllib_parse.quote(user_id, safe="")}&limit=1',
            '读取注册资格失败',
        )
        if row is None or not row.get('id'):
            return None
        return str(row['id'])

    def _begin_pending_receipt(
        self,
        user_id: str,
        eligibility_id: str | None,
    ) -> dict[str, Any]:
        # Insert or reuse a cancelled receipt as pending. The table's
        # constraint is (status = 'completed') = (completed_at is not null);
        # a pending row therefore must keep completed_at null. user_id has no
        # auth.users foreign key on purpose, so the receipt survives deletion.
        body = {
            'user_id': user_id,
            'status': 'pending',
            'requested_at': _now_iso(),
            'requested_by': None,
            'eligibility_id': eligibility_id,
            'business_data_deleted': False,
            'completed_at': None,
        }
        response = self._send(
            'POST',
            '/rest/v1/user_purge_receipts?on_conflict=user_id',
            _encode_json(body),
            headers={'Prefer': 'resolution=merge-duplicates,return=representation'},
        )
        data = self._expect(response, '准备彻底注销回执失败')
        row = data[0] if isinstance(data, list) and data else data
        if not isinstance(row, dict):
            raise ApiError('准备彻底注销回执未返回记录。')
        return row

    @staticmethod
    def _validate_completed_receipt(receipt: Mapping[str, Any], user_id: str) -> str:
        if receipt.get('user_id') != user_id:
            raise ApiError('注销回执绑定了其他用户，未确认完成；请勿在本地删除任何数据。')
        if receipt.get('status') != 'completed':
            raise ApiError('彻底注销尚未完成，请勿在本地删除任何数据。')
        purged_at = receipt.get('purged_at') or receipt.get('completed_at')
        if not isinstance(purged_at, str) or not purged_at:
            raise ApiError('注销回执缺少完成时间，未确认完成。')
        return purged_at

    def delete_user(self, user_id: str, *, legacy_admin: bool = False) -> dict[str, Any]:
        """Permanently purge any user, including active users and old admins.

        The four-step contract is the database migration's own:
        pending receipt -> admin_delete_user_business_data -> Auth Admin
        delete -> admin_complete_user_purge. This path deliberately does not
        call admin_begin_user_purge, whose app_admins and 30-day guards would
        reject exactly the accounts a project owner must be able to remove.
        """

        receipt = self._get_purge_receipt(user_id)
        if receipt is not None and receipt.get('status') == 'completed':
            purged_at = self._validate_completed_receipt(receipt, user_id)
            return {
                'user_id': user_id,
                'status': 'completed',
                'purged_at': purged_at,
                'legacy_admin': legacy_admin,
                'receipt_created': False,
                'receipt_reused': True,
            }

        receipt_created = False
        if receipt is None or receipt.get('status') != 'pending':
            eligibility_id = self._eligibility_id_for_user(user_id)
            receipt = self._begin_pending_receipt(user_id, eligibility_id)
            receipt_created = True

        # A retried pending receipt may already have removed the business data;
        # skipping the RPC keeps the retry idempotent and avoids the function's
        # "auth identity is missing" guard after a prior Auth deletion.
        if not (
            isinstance(receipt, Mapping)
            and receipt.get('business_data_deleted') is True
        ):
            self._rpc(
                'admin_delete_user_business_data',
                {'p_user_id': user_id},
                '清除云端业务数据失败',
            )
        self._delete_auth_user(user_id)
        completed = self._rpc(
            'admin_complete_user_purge',
            {'p_user_id': user_id},
            '记录彻底注销回执失败',
        )
        if not isinstance(completed, dict):
            raise ApiError('彻底注销回执响应格式不正确，未取得已完成回执。')
        purged_at = self._validate_completed_receipt(completed, user_id)
        return {
            'user_id': user_id,
            'status': 'completed',
            'purged_at': purged_at,
            'legacy_admin': legacy_admin,
            'receipt_created': receipt_created,
            'receipt_reused': False,
        }

    # -- cloud business data ----------------------------------------------

    def clear_cloud_data(self, user_id: str) -> dict[str, int]:
        """Delete snapshot, history and upload-ledger rows only.

        The Auth identity, profile account and registration eligibility stay
        untouched.
        """

        quoted = urllib_parse.quote(user_id, safe='')
        counts: dict[str, int] = {}
        for table in (
            'cloud_business_snapshot_upload_requests',
            'cloud_business_snapshot_history',
            'cloud_business_snapshots',
        ):
            response = self._send(
                'DELETE',
                f'/rest/v1/{table}?user_id=eq.{quoted}',
                headers={'Prefer': 'return=representation'},
            )
            data = self._expect(response, f'清空 {table} 失败')
            counts[table] = len(data) if isinstance(data, list) else 0
        return counts


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


def confirm(io: ConsoleIO, label: str, assume_yes: bool = False) -> bool:
    if assume_yes:
        return True
    return io.prompt(label).strip().lower() in ('yes', 'y')


def confirm_target_deletion(
    io: ConsoleIO,
    user: UserRecord,
    assume_yes: bool = False,
) -> None:
    """Require the operator to type the target email (or UUID) verbatim."""

    if assume_yes:
        return
    expected = user.email or user.user_id
    label = '邮箱' if user.email else 'UUID'
    entered = io.prompt(f'此操作不可恢复。请逐字输入目标{label} {expected} 以确认: ')
    if entered.strip().lower() != expected.strip().lower():
        raise OperationCancelled('输入与目标不一致，彻底注销未执行。')


# --------------------------------------------------------------------------
# Renderers
# --------------------------------------------------------------------------


def filter_users(records: Sequence[UserRecord], keyword: str) -> list[UserRecord]:
    text = (keyword or '').strip().casefold()
    if not text:
        return list(records)
    matched = []
    for record in records:
        haystacks = [
            record.email.casefold(),
            record.display_name.casefold(),
            record.user_id.casefold(),
        ]
        if record.eligibility is not None:
            haystacks.append(record.eligibility.identifier.casefold())
        if any(text in haystack for haystack in haystacks):
            matched.append(record)
    return matched


def render_user_table(
    users: Sequence[UserRecord],
    now: datetime | None = None,
    tz: Any = None,
) -> list[str]:
    moment = now or datetime.now(timezone.utc)
    rows = []
    for index, user in enumerate(users, start=1):
        status = user.status_label(moment)
        if user.legacy_admin:
            status = f'{status} · 历史管理员'
        snapshot = (
            f'r{user.snapshot.revision}'
            if user.snapshot is not None and user.snapshot.revision is not None
            else '—'
        )
        rows.append(
            [
                index,
                user.email or '（无邮箱）',
                user.display_name or '—',
                status,
                user.eligibility_label(),
                snapshot,
                format_timestamp(user.last_sign_in_at, tz),
                user.user_id,
            ]
        )
    return format_table(
        ('编号', '邮箱', '昵称', '状态', '注册资格', '云快照', '最近登录', 'UUID'),
        rows,
    )


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


def render_cloud_table(records: Sequence[UserRecord], tz: Any = None) -> list[str]:
    rows = []
    for index, record in enumerate(records, start=1):
        snapshot = record.snapshot
        rows.append(
            [
                index,
                record.email or record.user_id,
                f'r{snapshot.revision}' if snapshot and snapshot.revision is not None else '—',
                snapshot.schema_version if snapshot and snapshot.schema_version else '—',
                snapshot.row_count if snapshot and snapshot.row_count is not None else '—',
                format_timestamp(snapshot.uploaded_at, tz) if snapshot else '—',
                record.history_count,
                record.upload_request_count,
                record.mcp.summary(),
                record.display_name or '—',
                record.time_zone_id or '—',
            ]
        )
    return format_table(
        (
            '编号',
            '邮箱',
            '快照',
            'Schema',
            '记录数',
            '上传时间',
            '历史版本',
            '上传队列',
            '国策 MCP',
            '昵称',
            '时区',
        ),
        rows,
    )


def summarize_users(users: Sequence[UserRecord]) -> str:
    suspended = sum(
        1
        for user in users
        if user.suspension is not None and user.suspension.is_active
    )
    legacy = sum(1 for user in users if user.legacy_admin)
    with_snapshot = sum(1 for user in users if user.snapshot is not None)
    pending = sum(
        1
        for user in users
        if user.eligibility is not None and user.eligibility.status_label() == '待使用'
    )
    return (
        f'统计：共 {len(users)} 个账号；已停用 {suspended} 个；历史管理员 {legacy} 个；'
        f'有云快照 {with_snapshot} 个；注册资格待使用 {pending} 个。'
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


def summarize_cloud(records: Sequence[UserRecord]) -> str:
    snapshots = sum(1 for record in records if record.snapshot is not None)
    history = sum(record.history_count for record in records)
    uploads = sum(record.upload_request_count for record in records)
    mcp_active = sum(record.mcp.active for record in records)
    return (
        f'统计：{len(records)} 个账号；云快照 {snapshots} 个；'
        f'历史版本 {history} 行；上传队列 {uploads} 行；国策 MCP 有效授权 {mcp_active} 条。'
    )


def _user_payload(record: UserRecord) -> dict[str, Any]:
    return {
        'user_id': record.user_id,
        'email': record.email,
        'display_name': record.display_name,
        'time_zone_id': record.time_zone_id,
        'status': record.status_label(),
        'created_at': _iso(record.created_at),
        'last_sign_in_at': _iso(record.last_sign_in_at),
        'banned_until': _iso(record.banned_until),
        'legacy_admin': record.legacy_admin,
        'eligibility': (
            {
                'identifier': record.eligibility.identifier,
                'status': record.eligibility.status_label(),
                'used_at': _iso(record.eligibility.used_at),
                'revoked_at': _iso(record.eligibility.revoked_at),
                'purge_completed_at': _iso(record.eligibility.purge_completed_at),
            }
            if record.eligibility is not None
            else None
        ),
        'suspension': (
            {
                'is_active': record.suspension.is_active,
                'suspended_at': _iso(record.suspension.suspended_at),
                'restored_at': _iso(record.suspension.restored_at),
                'purge_eligible_at': _iso(record.suspension.purge_eligible_at()),
            }
            if record.suspension is not None
            else None
        ),
        'cloud_snapshot': (
            {
                'revision': record.snapshot.revision,
                'schema_version': record.snapshot.schema_version,
                'device_name': record.snapshot.device_name,
                'row_count': record.snapshot.row_count,
                'data_updated_at': _iso(record.snapshot.data_updated_at),
                'uploaded_at': _iso(record.snapshot.uploaded_at),
            }
            if record.snapshot is not None
            else None
        ),
        'history_count': record.history_count,
        'upload_request_count': record.upload_request_count,
        'mcp_grants': {
            'active': record.mcp.active,
            'revoked': record.mcp.revoked,
            'expired': record.mcp.expired,
        },
    }


# --------------------------------------------------------------------------
# Command outcomes
# --------------------------------------------------------------------------


@dataclass
class CommandOutcome:
    command: str
    data: Any
    lines: list[str]


def command_users(client: SupabaseAdminClient, io: ConsoleIO, keyword: str = '') -> CommandOutcome:
    records = filter_users(client.list_users(), keyword)
    heading = f'云端账号 {len(records)} 个'
    if keyword.strip():
        heading += f'（过滤：{keyword.strip()}）'
    return CommandOutcome(
        'users',
        {
            'users': [_user_payload(record) for record in records],
            'summary': summarize_users(records),
        },
        [heading, *render_user_table(records), summarize_users(records)],
    )


def command_create_user(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    email: str,
    *,
    password: str | None = None,
    nickname: str | None = None,
    ensure_eligibility: bool = True,
) -> CommandOutcome:
    generated = not password
    initial_password = password or secrets.token_urlsafe(GENERATED_PASSWORD_BYTES)
    if not 8 <= len(initial_password) <= 256:
        raise AdminToolError('密码长度必须为 8 至 256 个字符。')
    result = client.create_user(
        email,
        password=initial_password,
        nickname=nickname,
        ensure_eligibility=ensure_eligibility,
    )
    lines = [f'已创建账号：{result["email"]}（UUID {result["user_id"]}）']
    eligibility = result.get('eligibility')
    if eligibility is not None:
        lines.append(f'注册资格：{eligibility.status_label()}')
    elif ensure_eligibility:
        lines.append('注册资格：未返回')
    else:
        lines.append('注册资格：已跳过（--no-eligibility）')
    if result.get('display_name'):
        lines.append(f'昵称：{result["display_name"]}')
    if generated:
        lines.append(
            f'初始密码：{initial_password}（仅本次显示，请通过安全渠道转交；'
            '不要写入仓库或日志）'
        )
    data = {
        'user_id': result['user_id'],
        'email': result['email'],
        'display_name': result.get('display_name') or '',
        'eligibility': (
            eligibility.status_label() if eligibility is not None else None
        ),
    }
    if generated:
        data['initial_password'] = initial_password
    return CommandOutcome('create-user', data, lines)


def command_eligibilities(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    keyword: str = '',
) -> CommandOutcome:
    rows = client.list_eligibilities()
    text = keyword.strip().casefold()
    if text:
        rows = [row for row in rows if text in row.identifier.casefold()]
    heading = f'注册资格 {len(rows)} 条'
    if text:
        heading += f'（过滤：{keyword.strip()}）'
    return CommandOutcome(
        'eligibilities',
        {
            'eligibilities': [
                {
                    'identifier': row.identifier,
                    'identifier_type': row.identifier_type,
                    'status': row.status_label(),
                    'created_at': _iso(row.created_at),
                    'used_at': _iso(row.used_at),
                    'used_user_id': row.used_user_id or None,
                    'revoked_at': _iso(row.revoked_at),
                    'purge_completed_at': _iso(row.purge_completed_at),
                }
                for row in rows
            ],
            'summary': summarize_eligibilities(rows),
        },
        [heading, *render_eligibility_table(rows), summarize_eligibilities(rows)],
    )


def command_grant(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    email: str,
    *,
    note: str | None = None,
) -> CommandOutcome:
    normalized = normalize_email(email)
    record = client.grant_eligibility(normalized)
    lines = [f'已发放注册资格：{normalized}（{record.status_label()}）']
    if note and note.strip():
        lines.append(f'备注：{note.strip()}（仅本机显示，不写入数据库）')
    return CommandOutcome(
        'grant',
        {
            'identifier': record.identifier,
            'status': record.status_label(),
            'note': note.strip() if note else None,
        },
        lines,
    )


def command_revoke(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    email: str,
) -> CommandOutcome:
    normalized = normalize_email(email)
    changed = client.revoke_eligibility(normalized)
    if changed:
        message = f'已撤销未使用的注册资格：{normalized}'
    else:
        message = f'没有撤销任何资格：{normalized} 不存在、已被使用或已撤销。'
    return CommandOutcome(
        'revoke',
        {'identifier': normalized, 'revoked': changed},
        [message],
    )


def command_suspend(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    target: str,
    *,
    assume_yes: bool = False,
) -> CommandOutcome:
    user = client.resolve_user(target)
    lines = [
        f'目标：{user.display_target}（UUID {user.user_id}）',
        f'当前状态：{user.status_label()}',
    ]
    if not confirm(io, '确认停用该账号？输入 yes 继续: ', assume_yes):
        raise OperationCancelled('停用操作未执行。')
    created = client.suspend_user(user.user_id)
    lines.append(
        f'已停用：{user.display_target}'
        if created
        else f'目标已处于停用状态，已刷新 Auth 封禁：{user.display_target}'
    )
    return CommandOutcome(
        'suspend',
        {
            'user_id': user.user_id,
            'email': user.email,
            'created_period': created,
            'ban_duration': BAN_DURATION,
        },
        lines,
    )


def command_restore(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    target: str,
    *,
    assume_yes: bool = False,
) -> CommandOutcome:
    user = client.resolve_user(target)
    lines = [
        f'目标：{user.display_target}（UUID {user.user_id}）',
        f'当前状态：{user.status_label()}',
    ]
    if not confirm(io, '确认恢复该账号？输入 yes 继续: ', assume_yes):
        raise OperationCancelled('恢复操作未执行。')
    changed = client.restore_user(user.user_id)
    lines.append(
        f'已恢复：{user.display_target}'
        if changed
        else f'目标没有进行中的停用期，已清除 Auth 封禁：{user.display_target}'
    )
    return CommandOutcome(
        'restore',
        {
            'user_id': user.user_id,
            'email': user.email,
            'restored_period': changed,
        },
        lines,
    )


def command_reset_password(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    target: str,
    *,
    password: str | None = None,
    assume_yes: bool = False,
) -> CommandOutcome:
    user = client.resolve_user(target)
    lines = [
        f'目标：{user.display_target}（UUID {user.user_id}）',
        f'当前状态：{user.status_label()}',
    ]
    if password is None:
        password = io.password('新密码: ')
        repeated = io.password('再次输入新密码: ')
        if password != repeated:
            raise AdminToolError('两次输入的新密码不一致，操作未执行。')
    if not 8 <= len(password) <= 256:
        raise AdminToolError('新密码长度必须为 8 至 256 个字符。')
    if not confirm(io, '已线下人工核实目标身份？输入 yes 继续: ', assume_yes):
        raise OperationCancelled('重置密码操作未执行。')
    client.reset_password(user.user_id, password)
    lines.append('密码已重置。请通过安全渠道告知用户新密码。')
    return CommandOutcome(
        'reset-password',
        {'user_id': user.user_id, 'email': user.email, 'status': 'password_reset'},
        lines,
    )


def _resume_purge_target(
    client: SupabaseAdminClient,
    target: str,
) -> tuple[UserRecord, dict[str, Any] | None]:
    """Resolve a delete target, resuming a purge whose Auth identity is gone.

    A previous run may have deleted the Auth identity and stopped before
    `admin_complete_user_purge`. The UUID still lives in
    `user_purge_receipts`, so a pending/completed receipt supplies enough
    context to finish the remaining steps. Without either an Auth user or a
    receipt the original "user not found" error stands.
    """

    try:
        return client.resolve_user(target), None
    except UserNotFoundError:
        text = (target or '').strip()
        if not UUID_PATTERN.match(text):
            raise
        # GoTrue ids are canonical lowercase UUIDs; the receipt is matched by
        # that exact value, so an uppercase CLI argument must be normalized
        # before it reaches `_validate_completed_receipt`.
        user_id = text.lower()
        receipt = client._get_purge_receipt(user_id)
        if receipt is None:
            raise
        if receipt.get('status') not in ('pending', 'completed'):
            raise
        return UserRecord(user_id=user_id, email=''), receipt


def command_delete_user(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    target: str,
    *,
    assume_yes: bool = False,
) -> CommandOutcome:
    user, recovered_receipt = _resume_purge_target(client, target)
    lines = [
        f'目标：{user.display_target}（UUID {user.user_id}）',
        (
            '当前状态：Auth 身份已删除（续跑彻底注销）'
            if recovered_receipt is not None
            else f'当前状态：{user.status_label()}'
        ),
        (
            '遗留 app_admins：有（随 Auth 身份级联删除）'
            if user.legacy_admin
            else '遗留 app_admins：无'
        ),
    ]
    if recovered_receipt is not None:
        lines.append(
            f'检测到 {recovered_receipt.get("status")} 注销回执：'
            '只补完剩余步骤，不重复已删除的数据。'
        )
    confirm_target_deletion(io, user, assume_yes)
    result = client.delete_user(user.user_id, legacy_admin=user.legacy_admin)
    if result.get('receipt_reused'):
        lines.append('已存在 completed 回执，本次未重复删除。')
    elif recovered_receipt is not None:
        lines.append(
            '步骤：补齐云端业务数据 → 确认 Auth 身份已删除 → completed 回执'
        )
    else:
        lines.append(
            '步骤：pending 回执 → 清除云端业务数据 → 删除 Auth 身份 → completed 回执'
        )
    lines.append(
        f'已完成彻底注销：{user.display_target}（purged_at={result["purged_at"]}）'
    )
    return CommandOutcome(
        'delete-user',
        {
            'user_id': user.user_id,
            'email': user.email,
            'status': result['status'],
            'purged_at': result['purged_at'],
            'legacy_admin': result.get('legacy_admin', False),
            'receipt_created': result.get('receipt_created', False),
            'receipt_reused': result.get('receipt_reused', False),
            'resumed': recovered_receipt is not None,
        },
        lines,
    )


def command_cloud_data(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    target: str = '',
) -> CommandOutcome:
    text = (target or '').strip()
    records = [client.resolve_user(text)] if text else client.list_users()
    heading = (
        f'云端业务数据：{records[0].display_target}'
        if text and records
        else f'云端业务数据：{len(records)} 个账号'
    )
    return CommandOutcome(
        'cloud-data',
        {
            'users': [_user_payload(record) for record in records],
            'summary': summarize_cloud(records),
        },
        [heading, *render_cloud_table(records), summarize_cloud(records)],
    )


def command_clear_cloud_data(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    target: str,
    *,
    assume_yes: bool = False,
) -> CommandOutcome:
    user = client.resolve_user(target)
    snapshot = user.snapshot
    lines = [
        f'目标：{user.display_target}（UUID {user.user_id}）',
        (
            f'当前云快照：r{snapshot.revision}（Schema {snapshot.schema_version or "未知"}，'
            f'{snapshot.row_count if snapshot.row_count is not None else "未知"} 行）'
            if snapshot is not None
            else '当前云快照：无'
        ),
        f'历史版本：{user.history_count} 行；上传队列：{user.upload_request_count} 行',
        '只会清空快照 / 历史 / 上传队列；Auth 身份与账号资料保持不变。',
    ]
    if not confirm(io, '确认清空该用户的云端业务数据？输入 yes 继续: ', assume_yes):
        raise OperationCancelled('清空云端业务数据未执行。')
    counts = client.clear_cloud_data(user.user_id)
    lines.append(
        '已清空：'
        f'快照 {counts.get("cloud_business_snapshots", 0)} 行、'
        f'历史 {counts.get("cloud_business_snapshot_history", 0)} 行、'
        f'上传队列 {counts.get("cloud_business_snapshot_upload_requests", 0)} 行。'
    )
    return CommandOutcome(
        'clear-cloud-data',
        {
            'user_id': user.user_id,
            'email': user.email,
            'deleted': counts,
            'auth_identity_kept': True,
        },
        lines,
    )


# --------------------------------------------------------------------------
# Interactive menu 0-11
# --------------------------------------------------------------------------


MENU_OPTIONS = (
    ('1', '查看用户列表与生命周期'),
    ('2', '新建用户（含注册资格与昵称）'),
    ('3', '查看注册资格'),
    ('4', '发放注册资格'),
    ('5', '撤销未使用注册资格'),
    ('6', '停用用户'),
    ('7', '恢复用户'),
    ('8', '重置用户密码'),
    ('9', '彻底注销用户（即时）'),
    ('10', '查看云端业务快照摘要'),
    ('11', '清空指定用户云端业务数据'),
)


def dispatch_menu(
    choice: str,
    client: SupabaseAdminClient,
    io: ConsoleIO,
    assume_yes: bool = False,
) -> CommandOutcome | None:
    if choice == '1':
        return command_users(client, io, io.prompt('关键字过滤（回车查看全部）: '))
    if choice == '2':
        email = io.prompt('新用户邮箱: ')
        password = io.password('初始密码（留空自动生成）: ')
        nickname = io.prompt('昵称（可留空）: ')
        return command_create_user(
            client,
            io,
            email,
            password=password or None,
            nickname=nickname or None,
        )
    if choice == '3':
        return command_eligibilities(client, io, io.prompt('关键字过滤（回车查看全部）: '))
    if choice == '4':
        email = io.prompt('注册邮箱: ')
        note = io.prompt('备注（可留空，仅本机显示）: ')
        return command_grant(client, io, email, note=note or None)
    if choice == '5':
        return command_revoke(client, io, io.prompt('注册邮箱: '))
    if choice == '6':
        return command_suspend(
            client, io, io.prompt('目标用户邮箱或 UUID: '), assume_yes=assume_yes
        )
    if choice == '7':
        return command_restore(
            client, io, io.prompt('目标用户邮箱或 UUID: '), assume_yes=assume_yes
        )
    if choice == '8':
        return command_reset_password(
            client, io, io.prompt('目标用户邮箱或 UUID: '), assume_yes=assume_yes
        )
    if choice == '9':
        return command_delete_user(
            client, io, io.prompt('目标用户邮箱或 UUID: '), assume_yes=assume_yes
        )
    if choice == '10':
        return command_cloud_data(client, io, io.prompt('目标用户邮箱或 UUID（回车查看全部）: '))
    if choice == '11':
        return command_clear_cloud_data(
            client, io, io.prompt('目标用户邮箱或 UUID: '), assume_yes=assume_yes
        )
    io.error('无效选项，请输入 0 至 11。')
    return None


def run_menu(
    client: SupabaseAdminClient,
    io: ConsoleIO,
    assume_yes: bool = False,
) -> None:
    io.write('')
    io.write(f'Pacta 项目主直连终端  项目主机：{client.config.host}')
    io.write('项目主直连模式 (Owner)')
    io.write(
        f'配置来源：{client.config.source}；密钥变量：{client.config.secret_key_name}'
        '（密钥值不显示）'
    )
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
            outcome = dispatch_menu(choice, client, io, assume_yes)
            if outcome is not None:
                for line in outcome.lines:
                    io.write(line)
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
        help='dotenv 文件路径（默认仓库根目录 .env；进程环境变量优先）',
    )
    common.add_argument(
        '--json',
        action='store_true',
        default=argparse.SUPPRESS,
        help='以 JSON 输出结果（错误输出到 stderr）',
    )
    common.add_argument(
        '--yes',
        action='store_true',
        default=argparse.SUPPRESS,
        help='跳过交互确认（危险操作请先确认目标）',
    )

    parser = argparse.ArgumentParser(
        parents=[common],
        description=(
            'Pacta 项目主直连终端工具。读取 SUPABASE_URL 与 SUPABASE_SECRET_KEY，'
            '不需要管理员账号登录。'
        ),
        epilog=(
            '示例：\n'
            '  python scripts/pacta_admin.py\n'
            '  python scripts/pacta_admin.py users --filter example.com\n'
            '  python scripts/pacta_admin.py create-user person@example.com --nickname 小明\n'
            '  python scripts/pacta_admin.py delete-user person@example.com --yes\n'
            '  python scripts/pacta_admin.py cloud-data person@example.com --json\n'
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    # Defaults live on the top-level parser only: parent actions are shared with
    # every subparser, so a global default would erase a value parsed before the
    # subcommand. main() reads them with getattr instead.
    parser.set_defaults(command=None)

    subparsers = parser.add_subparsers(dest='command', metavar='命令')

    users = subparsers.add_parser(
        'users',
        parents=[common],
        help='查看全量用户、生命周期与云端摘要',
    )
    users.add_argument('--filter', default='', help='按邮箱/昵称/UUID 关键字过滤')

    create = subparsers.add_parser(
        'create-user',
        parents=[common],
        help='创建用户并确保注册资格与昵称',
    )
    create.add_argument(
        'email',
        nargs='?',
        default=None,
        metavar='EMAIL',
        help='新用户邮箱（也可用 --email）',
    )
    create.add_argument('--email', dest='email_option', default=None, help='新用户邮箱（与位置参数等价）')
    create.add_argument('--password', default=None, help='初始密码（省略时自动生成）')
    create.add_argument('--nickname', default=None, help='昵称（同步写入 profile_accounts）')
    create.add_argument(
        '--no-eligibility',
        action='store_true',
        help='不确保 registration_eligibility 白名单记录',
    )

    eligibilities = subparsers.add_parser(
        'eligibilities',
        parents=[common],
        help='查看注册白名单与状态',
    )
    eligibilities.add_argument('--filter', default='', help='按邮箱关键字过滤')

    grant = subparsers.add_parser('grant', parents=[common], help='发放注册资格')
    grant.add_argument(
        'email',
        nargs='?',
        default=None,
        metavar='EMAIL',
        help='要发放的注册邮箱（也可用 --email）',
    )
    grant.add_argument('--email', dest='email_option', default=None, help='注册邮箱（与位置参数等价）')
    grant.add_argument('--note', default=None, help='操作备注（仅本机显示，不写入数据库）')

    revoke = subparsers.add_parser('revoke', parents=[common], help='撤销未使用的注册资格')
    revoke.add_argument(
        'email',
        nargs='?',
        default=None,
        metavar='EMAIL',
        help='要撤销的注册邮箱（也可用 --email）',
    )
    revoke.add_argument('--email', dest='email_option', default=None, help='注册邮箱（与位置参数等价）')

    suspend = subparsers.add_parser('suspend', parents=[common], help='停用用户')
    suspend.add_argument(
        'target',
        nargs='?',
        default=None,
        metavar='TARGET',
        help='目标用户邮箱或 UUID（也可用 --email）',
    )
    suspend.add_argument('--email', dest='email_option', default=None, help='目标用户邮箱（与位置参数等价）')

    restore = subparsers.add_parser('restore', parents=[common], help='恢复已停用用户')
    restore.add_argument(
        'target',
        nargs='?',
        default=None,
        metavar='TARGET',
        help='目标用户邮箱或 UUID（也可用 --email）',
    )
    restore.add_argument('--email', dest='email_option', default=None, help='目标用户邮箱（与位置参数等价）')

    reset = subparsers.add_parser(
        'reset-password',
        parents=[common],
        help='通过 Auth Admin 重置任意用户密码',
    )
    reset.add_argument(
        'target',
        nargs='?',
        default=None,
        metavar='TARGET',
        help='目标用户邮箱或 UUID（也可用 --email）',
    )
    reset.add_argument('--email', dest='email_option', default=None, help='目标用户邮箱（与位置参数等价）')
    reset.add_argument(
        '--password',
        default=None,
        help='新密码（省略时遮罩提示两次；--json 模式必须同时提供）',
    )

    delete = subparsers.add_parser(
        'delete-user',
        parents=[common],
        help='即时彻底注销任意用户（含活跃用户与旧管理员）',
    )
    delete.add_argument(
        'target',
        nargs='?',
        default=None,
        metavar='TARGET',
        help='目标用户邮箱或 UUID（也可用 --email）',
    )
    delete.add_argument('--email', dest='email_option', default=None, help='目标用户邮箱（与位置参数等价）')

    cloud = subparsers.add_parser(
        'cloud-data',
        parents=[common],
        help='查看云端业务快照摘要',
    )
    cloud.add_argument(
        'target',
        nargs='?',
        default='',
        metavar='TARGET',
        help='目标用户邮箱或 UUID（省略时查看全部账号；也可用 --email）',
    )
    cloud.add_argument('--email', dest='email_option', default=None, help='目标用户邮箱（与位置参数等价）')

    clear = subparsers.add_parser(
        'clear-cloud-data',
        parents=[common],
        help='仅清空指定用户的云端快照/历史/上传队列',
    )
    clear.add_argument(
        'target',
        nargs='?',
        default=None,
        metavar='TARGET',
        help='目标用户邮箱或 UUID（也可用 --email）',
    )
    clear.add_argument('--email', dest='email_option', default=None, help='目标用户邮箱（与位置参数等价）')

    return parser


def _email_argument(args: argparse.Namespace) -> str:
    """Accept either the positional EMAIL or the equivalent --email flag."""

    return (
        getattr(args, 'email_option', None)
        or getattr(args, 'email', None)
        or ''
    ).strip()


def _target_argument(args: argparse.Namespace) -> str:
    """Accept either the positional TARGET or the equivalent --email flag."""

    return (
        getattr(args, 'email_option', None)
        or getattr(args, 'target', None)
        or ''
    ).strip()


# Commands that otherwise prompt. JSON output must stay machine-readable, so
# they require an explicit --yes instead of mixing a prompt into stdout.
JSON_CONFIRM_COMMANDS = (
    'suspend',
    'restore',
    'reset-password',
    'delete-user',
    'clear-cloud-data',
)


def run_command(
    client: SupabaseAdminClient,
    args: argparse.Namespace,
    io: ConsoleIO,
) -> CommandOutcome:
    command = args.command
    assume_yes = bool(getattr(args, 'yes', False))
    json_mode = bool(getattr(args, 'json', False))
    if json_mode and command in JSON_CONFIRM_COMMANDS and not assume_yes:
        raise ConfigError('--json 模式下的危险操作必须同时提供 --yes。')
    # getpass would write its prompt to the terminal and block a machine
    # consumer, so the missing password is rejected before any I/O happens.
    if (
        json_mode
        and command == 'reset-password'
        and getattr(args, 'password', None) is None
    ):
        raise ConfigError(
            'JSON 模式下 reset-password 必须同时提供 --password 与 --yes。'
        )
    if command == 'users':
        return command_users(client, io, getattr(args, 'filter', '') or '')
    if command == 'create-user':
        return command_create_user(
            client,
            io,
            _email_argument(args),
            password=args.password,
            nickname=args.nickname,
            ensure_eligibility=not bool(args.no_eligibility),
        )
    if command == 'eligibilities':
        return command_eligibilities(client, io, getattr(args, 'filter', '') or '')
    if command == 'grant':
        return command_grant(client, io, _email_argument(args), note=args.note)
    if command == 'revoke':
        return command_revoke(client, io, _email_argument(args))
    if command == 'suspend':
        return command_suspend(
            client, io, _target_argument(args), assume_yes=assume_yes
        )
    if command == 'restore':
        return command_restore(
            client, io, _target_argument(args), assume_yes=assume_yes
        )
    if command == 'reset-password':
        return command_reset_password(
            client,
            io,
            _target_argument(args),
            password=args.password,
            assume_yes=assume_yes,
        )
    if command == 'delete-user':
        return command_delete_user(
            client, io, _target_argument(args), assume_yes=assume_yes
        )
    if command == 'cloud-data':
        return command_cloud_data(client, io, _target_argument(args))
    if command == 'clear-cloud-data':
        return command_clear_cloud_data(
            client, io, _target_argument(args), assume_yes=assume_yes
        )
    raise AdminToolError('未知命令。')


def _emit(outcome: CommandOutcome, io: ConsoleIO, json_mode: bool) -> None:
    if json_mode:
        payload = {
            'ok': True,
            'command': outcome.command,
            'data': outcome.data,
        }
        io.write(json.dumps(payload, ensure_ascii=False, default=str))
        return
    for line in outcome.lines:
        io.write(line)


def _emit_error(
    io: ConsoleIO,
    json_mode: bool,
    command: str | None,
    error: AdminToolError,
    *,
    prefix: str,
    secret: str | None,
) -> None:
    message = redact(str(error), [secret] if secret else [])
    if json_mode:
        io.error(
            json.dumps(
                {
                    'ok': False,
                    'command': command,
                    'error': {
                        'message': message,
                        'exit_code': error.exit_code,
                    },
                },
                ensure_ascii=False,
            )
        )
        return
    io.error(f'{prefix}{message}')


def main(
    argv: Sequence[str] | None = None,
    *,
    transport: Any = None,
    environ: Mapping[str, str] | None = None,
    out: Any = None,
    err: Any = None,
    input_fn: Callable[[str], str] | None = None,
    getpass_fn: Callable[[str], str] | None = None,
) -> int:
    configure_console()
    io = ConsoleIO(out, err, input_fn, getpass_fn)
    parser = build_parser()
    args = parser.parse_args(argv)
    json_mode = bool(getattr(args, 'json', False))
    command = getattr(args, 'command', None)
    config: SupabaseConfig | None = None

    try:
        config = load_config(getattr(args, 'env_file', None), environ)
        client = SupabaseAdminClient(
            config,
            transport if transport is not None else HttpTransport(),
        )

        if command is None:
            if json_mode:
                raise ConfigError(
                    '--json 需要指定子命令；交互式菜单仅支持文本输出。'
                )
            run_menu(client, io, bool(getattr(args, 'yes', False)))
            return EXIT_OK

        outcome = run_command(client, args, io)
        _emit(outcome, io, json_mode)
        return EXIT_OK
    except OperationCancelled as error:
        _emit_error(
            io,
            json_mode,
            command,
            error,
            prefix='已取消：',
            secret=config.secret_key if config is not None else None,
        )
        return error.exit_code
    except AdminToolError as error:
        _emit_error(
            io,
            json_mode,
            command,
            error,
            prefix='错误：',
            secret=config.secret_key if config is not None else None,
        )
        return error.exit_code
    except EOFError:
        _emit_error(
            io,
            json_mode,
            command,
            AdminToolError('输入结束，已退出。'),
            prefix='',
            secret=config.secret_key if config is not None else None,
        )
        return EXIT_CANCELLED
    except KeyboardInterrupt:
        _emit_error(
            io,
            json_mode,
            command,
            AdminToolError('已中断，未执行未完成的操作。'),
            prefix='',
            secret=config.secret_key if config is not None else None,
        )
        return 130


if __name__ == '__main__':
    sys.exit(main())
