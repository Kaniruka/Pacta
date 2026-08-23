import 'package:flutter/foundation.dart';

@immutable
class AppUserId {
  const AppUserId(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppUserId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

abstract interface class AuthSession {
  AppUserId? get currentUser;

  Stream<AppUserId?> get userChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}
