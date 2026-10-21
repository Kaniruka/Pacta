import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NationalFocusAiGrant {
  const NationalFocusAiGrant({
    required this.id,
    required this.clientName,
    required this.scope,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final String clientName;
  final String scope;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  bool isActiveAt(DateTime now) => revokedAt == null && expiresAt.isAfter(now);

  NationalFocusAiGrant copyWith({DateTime? revokedAt}) => NationalFocusAiGrant(
    id: id,
    clientName: clientName,
    scope: scope,
    createdAt: createdAt,
    expiresAt: expiresAt,
    revokedAt: revokedAt ?? this.revokedAt,
  );

  factory NationalFocusAiGrant.fromJson(Map<String, dynamic> json) {
    DateTime date(String key) => DateTime.parse(json[key] as String).toUtc();

    return NationalFocusAiGrant(
      id: json['id'] as String,
      clientName: json['client_name'] as String,
      scope: json['scope'] as String,
      createdAt: date('created_at'),
      expiresAt: date('expires_at'),
      revokedAt: json['revoked_at'] == null
          ? null
          : DateTime.parse(json['revoked_at'] as String).toUtc(),
    );
  }
}

class NationalFocusAiAuthorizationRequest {
  const NationalFocusAiAuthorizationRequest({
    required this.clientName,
    required this.redirectUri,
    required this.scope,
    required this.expiresAt,
  });

  final String clientName;
  final String redirectUri;
  final String scope;
  final DateTime expiresAt;

  factory NationalFocusAiAuthorizationRequest.fromJson(
    Map<String, dynamic> json,
  ) => NationalFocusAiAuthorizationRequest(
    clientName: json['client_name'] as String,
    redirectUri: json['redirect_uri'] as String,
    scope: json['scope'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
  );
}

class NationalFocusAiAccessError implements Exception {
  const NationalFocusAiAccessError(this.code);

  final String? code;
}

abstract interface class NationalFocusAiGrantRepository {
  Future<List<NationalFocusAiGrant>> listMyGrants();

  Future<NationalFocusAiAuthorizationRequest> inspectRequest(
    String requestCode,
  );

  Future<void> approveRequest(String requestCode);

  Future<void> revokeGrant(String grantId);
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
      throw StateError('当前登录用户已变化，请重新打开授权页面。');
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
  Future<NationalFocusAiAuthorizationRequest> inspectRequest(
    String requestCode,
  ) async {
    _assertCurrentUser();
    try {
      final result = await client.rpc(
        'inspect_national_focus_mcp_request',
        params: {'p_request_code': requestCode.trim()},
      );
      if (result is! Map) throw const FormatException();
      return NationalFocusAiAuthorizationRequest.fromJson(
        Map<String, dynamic>.from(result),
      );
    } on PostgrestException catch (error) {
      throw NationalFocusAiAccessError(error.code);
    }
  }

  @override
  Future<void> approveRequest(String requestCode) async {
    _assertCurrentUser();
    try {
      await client.rpc(
        'approve_national_focus_mcp_connection',
        params: {'p_request_code': requestCode.trim(), 'p_consent': true},
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
}

final nationalFocusAiGrantRepositoryFactoryProvider =
    Provider<NationalFocusAiGrantRepository Function(String userId)?>(
      (ref) => null,
    );

final nationalFocusMcpUrlProvider = Provider<String?>((ref) => null);
