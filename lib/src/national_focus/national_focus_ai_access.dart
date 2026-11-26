import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// MCP 连接授权范围。
enum NationalFocusAiScope {
  read,
  readWrite;

  String get storageValue => switch (this) {
    NationalFocusAiScope.read => 'national_focus:read',
    NationalFocusAiScope.readWrite => 'national_focus:readwrite',
  };

  String get label => switch (this) {
    NationalFocusAiScope.read => '只读',
    NationalFocusAiScope.readWrite => '读写',
  };

  String get endpointSuffix => switch (this) {
    NationalFocusAiScope.read => '/readonly',
    NationalFocusAiScope.readWrite => '/readwrite',
  };

  static NationalFocusAiScope fromStorage(String value) => switch (value) {
    'national_focus:read' => NationalFocusAiScope.read,
    'national_focus:readwrite' => NationalFocusAiScope.readWrite,
    _ => throw ArgumentError('Unknown National Focus AI scope: $value'),
  };
}

/// 常见多端 Agent 接入预设。
enum NationalFocusAgentPreset {
  antigravity,
  claudeCode,
  codex,
  dsh,
  cursor,
  genericHttp;

  String get storageValue => switch (this) {
    NationalFocusAgentPreset.antigravity => 'antigravity',
    NationalFocusAgentPreset.claudeCode => 'claude_code',
    NationalFocusAgentPreset.codex => 'codex',
    NationalFocusAgentPreset.dsh => 'dsh',
    NationalFocusAgentPreset.cursor => 'cursor',
    NationalFocusAgentPreset.genericHttp => 'generic_http',
  };

  String get label => switch (this) {
    NationalFocusAgentPreset.antigravity => 'Antigravity',
    NationalFocusAgentPreset.claudeCode => 'Claude Code',
    NationalFocusAgentPreset.codex => 'Codex',
    NationalFocusAgentPreset.dsh => 'DSH',
    NationalFocusAgentPreset.cursor => 'Cursor',
    NationalFocusAgentPreset.genericHttp => '通用 HTTP MCP',
  };

  String get defaultConnectionName => switch (this) {
    NationalFocusAgentPreset.antigravity => 'Antigravity',
    NationalFocusAgentPreset.claudeCode => 'Claude Code',
    NationalFocusAgentPreset.codex => 'Codex',
    NationalFocusAgentPreset.dsh => 'DSH',
    NationalFocusAgentPreset.cursor => 'Cursor',
    NationalFocusAgentPreset.genericHttp => 'HTTP MCP',
  };

  static NationalFocusAgentPreset? fromStorage(String? value) =>
      switch (value) {
        'antigravity' => NationalFocusAgentPreset.antigravity,
        'claude_code' => NationalFocusAgentPreset.claudeCode,
        'codex' => NationalFocusAgentPreset.codex,
        'dsh' => NationalFocusAgentPreset.dsh,
        'cursor' => NationalFocusAgentPreset.cursor,
        'generic_http' => NationalFocusAgentPreset.genericHttp,
        _ => null,
      };
}

/// 连接有效期预设；`never` 对应 `ttl == null`（永不过期）。
enum NationalFocusAiTtlPreset {
  thirtyMinutes,
  twentyFourHours,
  sevenDays,
  thirtyDays,
  never;

  String get label => switch (this) {
    NationalFocusAiTtlPreset.thirtyMinutes => '30 分钟',
    NationalFocusAiTtlPreset.twentyFourHours => '24 小时',
    NationalFocusAiTtlPreset.sevenDays => '7 天',
    NationalFocusAiTtlPreset.thirtyDays => '30 天',
    NationalFocusAiTtlPreset.never => '永不过期',
  };

  Duration? get duration => switch (this) {
    NationalFocusAiTtlPreset.thirtyMinutes => const Duration(minutes: 30),
    NationalFocusAiTtlPreset.twentyFourHours => const Duration(hours: 24),
    NationalFocusAiTtlPreset.sevenDays => const Duration(days: 7),
    NationalFocusAiTtlPreset.thirtyDays => const Duration(days: 30),
    NationalFocusAiTtlPreset.never => null,
  };
}

/// 自定义有效期的单位。
enum NationalFocusAiCustomTtlUnit {
  minutes,
  hours,
  days;

  String get label => switch (this) {
    NationalFocusAiCustomTtlUnit.minutes => '分钟',
    NationalFocusAiCustomTtlUnit.hours => '小时',
    NationalFocusAiCustomTtlUnit.days => '天',
  };

  int get secondsPerUnit => switch (this) {
    NationalFocusAiCustomTtlUnit.minutes => 60,
    NationalFocusAiCustomTtlUnit.hours => 3600,
    NationalFocusAiCustomTtlUnit.days => 86400,
  };
}

/// 服务端允许的最小/最大连接有效期（秒）：1 分钟 ~ 10 年（3650 天）。
const int minNationalFocusAiTtlSeconds = 60;
const int maxNationalFocusAiTtlSeconds = 315360000;

/// 解析并校验用户输入的自定义有效期；非法或越界返回 `null`。
Duration? parseCustomNationalFocusTtl(
  String raw,
  NationalFocusAiCustomTtlUnit unit,
) {
  final value = int.tryParse(raw.trim());
  if (value == null || value <= 0) return null;
  final seconds = value * unit.secondsPerUnit;
  if (seconds < minNationalFocusAiTtlSeconds ||
      seconds > maxNationalFocusAiTtlSeconds) {
    return null;
  }
  return Duration(seconds: seconds);
}

class NationalFocusAiGrant {
  const NationalFocusAiGrant({
    required this.id,
    required this.label,
    required this.scope,
    required this.tokenPrefix,
    required this.createdAt,
    this.agentPreset,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String label;
  final String? agentPreset;
  final NationalFocusAiScope scope;
  final String tokenPrefix;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(now);
  }

  bool isActiveAt(DateTime now) => revokedAt == null && !isExpiredAt(now);

  NationalFocusAiGrant copyWith({DateTime? revokedAt}) => NationalFocusAiGrant(
    id: id,
    label: label,
    agentPreset: agentPreset,
    scope: scope,
    tokenPrefix: tokenPrefix,
    createdAt: createdAt,
    expiresAt: expiresAt,
    lastUsedAt: lastUsedAt,
    revokedAt: revokedAt ?? this.revokedAt,
  );

  factory NationalFocusAiGrant.fromJson(Map<String, dynamic> json) {
    DateTime? optionalDate(String key) {
      final raw = json[key];
      return raw == null ? null : DateTime.parse(raw as String).toUtc();
    }

    return NationalFocusAiGrant(
      id: json['id'] as String,
      label: json['label'] as String,
      agentPreset: json['agent_preset'] as String?,
      scope: NationalFocusAiScope.fromStorage(json['scope'] as String),
      tokenPrefix: json['token_prefix'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      expiresAt: optionalDate('expires_at'),
      lastUsedAt: optionalDate('last_used_at'),
      revokedAt: optionalDate('revoked_at'),
    );
  }
}

class CreatedNationalFocusAiGrant {
  const CreatedNationalFocusAiGrant({required this.grant, required this.token});

  final NationalFocusAiGrant grant;
  final String token;

  factory CreatedNationalFocusAiGrant.fromJson(Map<String, dynamic> json) =>
      CreatedNationalFocusAiGrant(
        grant: NationalFocusAiGrant.fromJson(json),
        token: json['token'] as String,
      );
}

class NationalFocusAiAuditLog {
  const NationalFocusAiAuditLog({
    required this.id,
    this.grantId,
    required this.grantLabel,
    required this.toolName,
    required this.actionKind,
    required this.summary,
    this.snapshotRevision,
    required this.createdAt,
  });

  final String id;
  final String? grantId;
  final String grantLabel;
  final String toolName;
  final String actionKind;
  final String summary;
  final int? snapshotRevision;
  final DateTime createdAt;

  bool get isWrite => actionKind == 'write';

  factory NationalFocusAiAuditLog.fromJson(Map<String, dynamic> json) =>
      NationalFocusAiAuditLog(
        id: json['id'] as String,
        grantId: json['grant_id'] as String?,
        grantLabel: json['grant_label'] as String,
        toolName: json['tool_name'] as String,
        actionKind: json['action_kind'] as String,
        summary: json['summary'] as String,
        snapshotRevision: (json['snapshot_revision'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}

class NationalFocusAiAccessError implements Exception {
  const NationalFocusAiAccessError(this.code);

  final String? code;
}

/// 根据基础服务地址和授权范围派生具体的 `/mcp/readonly` 或 `/mcp/readwrite` 地址。
String nationalFocusMcpEndpointUrl(
  String baseMcpUrl,
  NationalFocusAiScope scope,
) {
  var normalized = baseMcpUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  normalized = normalized.replaceFirst(RegExp(r'/(readonly|readwrite)$'), '');
  if (!normalized.endsWith('/mcp')) {
    normalized = '$normalized/mcp';
  }
  return '$normalized${scope.endpointSuffix}';
}

/// 为指定 Agent 预设生成可直接粘贴的 MCP 配置文本。
String buildNationalFocusAgentConfig({
  required NationalFocusAgentPreset preset,
  required String endpointUrl,
  required String token,
}) {
  const encoder = JsonEncoder.withIndent('  ');
  switch (preset) {
    case NationalFocusAgentPreset.claudeCode:
      return 'claude mcp add --transport http pacta-national-focus '
          '"$endpointUrl" --header "Authorization: Bearer $token"';
    case NationalFocusAgentPreset.codex:
      return '[mcp_servers.pacta_national_focus]\n'
          'url = "$endpointUrl"\n'
          'http_headers = { "Authorization" = "Bearer $token" }';
    case NationalFocusAgentPreset.antigravity:
    case NationalFocusAgentPreset.cursor:
    case NationalFocusAgentPreset.genericHttp:
      return encoder.convert({
        'mcpServers': {
          'pacta-national-focus': {
            'url': endpointUrl,
            'headers': {'Authorization': 'Bearer $token'},
          },
        },
      });
    case NationalFocusAgentPreset.dsh:
      return encoder.convert({
        'mcpServers': {
          'pacta-national-focus': {
            'type': 'http',
            'url': endpointUrl,
            'headers': {'Authorization': 'Bearer $token'},
          },
        },
      });
  }
}

abstract interface class NationalFocusAiGrantRepository {
  Future<List<NationalFocusAiGrant>> listMyGrants();

  Future<CreatedNationalFocusAiGrant> createGrant({
    required String label,
    required NationalFocusAiScope scope,
    Duration? ttl,
    String? agentPreset,
  });

  Future<void> revokeGrant(String grantId);

  Future<void> deleteGrant(String grantId);

  Future<int> revokeAllGrants();

  Future<int> clearExpiredGrants();

  Future<List<NationalFocusAiAuditLog>> listRecentAuditLogs({int limit = 20});
}

class SupabaseNationalFocusAiGrantRepository
    implements NationalFocusAiGrantRepository {
  const SupabaseNationalFocusAiGrantRepository({
    required this.client,
    required this.userId,
  });

  final SupabaseClient client;
  final String userId;

  void _assertCurrentUser() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('当前登录用户已变化，请重新打开开放能力页。');
    }
  }

  @override
  Future<List<NationalFocusAiGrant>> listMyGrants() async {
    _assertCurrentUser();
    try {
      final result = await client.rpc('list_national_focus_mcp_grants');
      if (result is! List) throw const FormatException();
      return [
        for (final row in result)
          NationalFocusAiGrant.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }

  @override
  Future<CreatedNationalFocusAiGrant> createGrant({
    required String label,
    required NationalFocusAiScope scope,
    Duration? ttl,
    String? agentPreset,
  }) async {
    _assertCurrentUser();
    try {
      final result = await client.rpc(
        'create_national_focus_mcp_grant',
        params: {
          'p_label': label.trim(),
          'p_scope': scope.storageValue,
          'p_ttl_seconds': ttl?.inSeconds,
          'p_agent_preset': agentPreset,
        },
      );
      if (result is! Map) throw const FormatException();
      return CreatedNationalFocusAiGrant.fromJson(
        Map<String, dynamic>.from(result),
      );
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    _assertCurrentUser();
    try {
      await client.rpc(
        'revoke_national_focus_mcp_grant',
        params: {'p_grant_id': grantId},
      );
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }

  @override
  Future<void> deleteGrant(String grantId) async {
    _assertCurrentUser();
    try {
      await client.rpc(
        'delete_national_focus_mcp_grant',
        params: {'p_grant_id': grantId},
      );
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }

  @override
  Future<int> revokeAllGrants() async {
    _assertCurrentUser();
    try {
      final result = await client.rpc('revoke_all_national_focus_mcp_grants');
      if (result is num) return result.toInt();
      throw const FormatException();
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }

  @override
  Future<int> clearExpiredGrants() async {
    _assertCurrentUser();
    try {
      final result = await client.rpc(
        'clear_expired_national_focus_mcp_grants',
      );
      if (result is num) return result.toInt();
      throw const FormatException();
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }

  @override
  Future<List<NationalFocusAiAuditLog>> listRecentAuditLogs({
    int limit = 20,
  }) async {
    _assertCurrentUser();
    try {
      final result = await client.rpc(
        'list_national_focus_mcp_audit_logs',
        params: {'p_limit': limit},
      );
      if (result is! List) throw const FormatException();
      return [
        for (final row in result)
          NationalFocusAiAuditLog.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
      ];
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }
}

final nationalFocusAiGrantRepositoryFactoryProvider =
    Provider<NationalFocusAiGrantRepository Function(String userId)?>(
      (ref) => null,
    );

final nationalFocusMcpUrlProvider = Provider<String?>((ref) => null);
