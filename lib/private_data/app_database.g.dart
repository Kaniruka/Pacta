// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedProfilesTable extends CachedProfiles
    with TableInfo<$CachedProfilesTable, CachedProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [userId, displayName, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  CachedProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProfileRow(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedProfilesTable createAlias(String alias) {
    return $CachedProfilesTable(attachedDatabase, alias);
  }
}

class CachedProfileRow extends DataClass
    implements Insertable<CachedProfileRow> {
  final String userId;
  final String? displayName;
  final DateTime updatedAt;
  const CachedProfileRow({
    required this.userId,
    this.displayName,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedProfilesCompanion toCompanion(bool nullToAbsent) {
    return CachedProfilesCompanion(
      userId: Value(userId),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProfileRow(
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String?>(displayName),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedProfileRow copyWith({
    String? userId,
    Value<String?> displayName = const Value.absent(),
    DateTime? updatedAt,
  }) => CachedProfileRow(
    userId: userId ?? this.userId,
    displayName: displayName.present ? displayName.value : this.displayName,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedProfileRow copyWithCompanion(CachedProfilesCompanion data) {
    return CachedProfileRow(
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfileRow(')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, displayName, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProfileRow &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.updatedAt == this.updatedAt);
}

class CachedProfilesCompanion extends UpdateCompanion<CachedProfileRow> {
  final Value<String> userId;
  final Value<String?> displayName;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedProfilesCompanion({
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProfilesCompanion.insert({
    required String userId,
    this.displayName = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       updatedAt = Value(updatedAt);
  static Insertable<CachedProfileRow> custom({
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProfilesCompanion copyWith({
    Value<String>? userId,
    Value<String?>? displayName,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedProfilesCompanion(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProfilesCompanion(')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedGoalsTable extends CachedGoals
    with TableInfo<$CachedGoalsTable, CachedGoalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedGoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    title,
    notes,
    createdAt,
    updatedAt,
    mutationId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_goals';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedGoalRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  CachedGoalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedGoalRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
    );
  }

  @override
  $CachedGoalsTable createAlias(String alias) {
    return $CachedGoalsTable(attachedDatabase, alias);
  }
}

class CachedGoalRow extends DataClass implements Insertable<CachedGoalRow> {
  final String id;
  final String userId;
  final String title;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String mutationId;
  const CachedGoalRow({
    required this.id,
    required this.userId,
    required this.title,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.mutationId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['mutation_id'] = Variable<String>(mutationId);
    return map;
  }

  CachedGoalsCompanion toCompanion(bool nullToAbsent) {
    return CachedGoalsCompanion(
      id: Value(id),
      userId: Value(userId),
      title: Value(title),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      mutationId: Value(mutationId),
    );
  }

  factory CachedGoalRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedGoalRow(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      mutationId: serializer.fromJson<String>(json['mutationId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'mutationId': serializer.toJson<String>(mutationId),
    };
  }

  CachedGoalRow copyWith({
    String? id,
    String? userId,
    String? title,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    String? mutationId,
  }) => CachedGoalRow(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    mutationId: mutationId ?? this.mutationId,
  );
  CachedGoalRow copyWithCompanion(CachedGoalsCompanion data) {
    return CachedGoalRow(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedGoalRow(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mutationId: $mutationId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, title, notes, createdAt, updatedAt, mutationId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedGoalRow &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.mutationId == this.mutationId);
}

class CachedGoalsCompanion extends UpdateCompanion<CachedGoalRow> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> title;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> mutationId;
  final Value<int> rowid;
  const CachedGoalsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.mutationId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedGoalsCompanion.insert({
    required String id,
    required String userId,
    required String title,
    this.notes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    required String mutationId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       mutationId = Value(mutationId);
  static Insertable<CachedGoalRow> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? mutationId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (mutationId != null) 'mutation_id': mutationId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedGoalsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? title,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? mutationId,
    Value<int>? rowid,
  }) {
    return CachedGoalsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mutationId: mutationId ?? this.mutationId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedGoalsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mutationId: $mutationId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedTasksTable extends CachedTasks
    with TableInfo<$CachedTasksTable, CachedTaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalIdMeta = const VerificationMeta('goalId');
  @override
  late final GeneratedColumn<String> goalId = GeneratedColumn<String>(
    'goal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deadlineMeta = const VerificationMeta(
    'deadline',
  );
  @override
  late final GeneratedColumn<DateTime> deadline = GeneratedColumn<DateTime>(
    'deadline',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedSecondsMeta = const VerificationMeta(
    'estimatedSeconds',
  );
  @override
  late final GeneratedColumn<int> estimatedSeconds = GeneratedColumn<int>(
    'estimated_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classificationMeta = const VerificationMeta(
    'classification',
  );
  @override
  late final GeneratedColumn<String> classification = GeneratedColumn<String>(
    'classification',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _focusProgressSecondsMeta =
      const VerificationMeta('focusProgressSeconds');
  @override
  late final GeneratedColumn<int> focusProgressSeconds = GeneratedColumn<int>(
    'focus_progress_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    goalId,
    title,
    notes,
    deadline,
    estimatedSeconds,
    classification,
    focusProgressSeconds,
    completedAt,
    createdAt,
    updatedAt,
    mutationId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedTaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('goal_id')) {
      context.handle(
        _goalIdMeta,
        goalId.isAcceptableOrUnknown(data['goal_id']!, _goalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_goalIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('deadline')) {
      context.handle(
        _deadlineMeta,
        deadline.isAcceptableOrUnknown(data['deadline']!, _deadlineMeta),
      );
    }
    if (data.containsKey('estimated_seconds')) {
      context.handle(
        _estimatedSecondsMeta,
        estimatedSeconds.isAcceptableOrUnknown(
          data['estimated_seconds']!,
          _estimatedSecondsMeta,
        ),
      );
    }
    if (data.containsKey('classification')) {
      context.handle(
        _classificationMeta,
        classification.isAcceptableOrUnknown(
          data['classification']!,
          _classificationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_classificationMeta);
    }
    if (data.containsKey('focus_progress_seconds')) {
      context.handle(
        _focusProgressSecondsMeta,
        focusProgressSeconds.isAcceptableOrUnknown(
          data['focus_progress_seconds']!,
          _focusProgressSecondsMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  CachedTaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      goalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      deadline: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deadline'],
      ),
      estimatedSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_seconds'],
      ),
      classification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification'],
      )!,
      focusProgressSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}focus_progress_seconds'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
    );
  }

  @override
  $CachedTasksTable createAlias(String alias) {
    return $CachedTasksTable(attachedDatabase, alias);
  }
}

class CachedTaskRow extends DataClass implements Insertable<CachedTaskRow> {
  final String id;
  final String userId;
  final String goalId;
  final String title;
  final String? notes;
  final DateTime? deadline;
  final int? estimatedSeconds;
  final String classification;
  final int focusProgressSeconds;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String mutationId;
  const CachedTaskRow({
    required this.id,
    required this.userId,
    required this.goalId,
    required this.title,
    this.notes,
    this.deadline,
    this.estimatedSeconds,
    required this.classification,
    required this.focusProgressSeconds,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.mutationId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['goal_id'] = Variable<String>(goalId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || deadline != null) {
      map['deadline'] = Variable<DateTime>(deadline);
    }
    if (!nullToAbsent || estimatedSeconds != null) {
      map['estimated_seconds'] = Variable<int>(estimatedSeconds);
    }
    map['classification'] = Variable<String>(classification);
    map['focus_progress_seconds'] = Variable<int>(focusProgressSeconds);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['mutation_id'] = Variable<String>(mutationId);
    return map;
  }

  CachedTasksCompanion toCompanion(bool nullToAbsent) {
    return CachedTasksCompanion(
      id: Value(id),
      userId: Value(userId),
      goalId: Value(goalId),
      title: Value(title),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      deadline: deadline == null && nullToAbsent
          ? const Value.absent()
          : Value(deadline),
      estimatedSeconds: estimatedSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedSeconds),
      classification: Value(classification),
      focusProgressSeconds: Value(focusProgressSeconds),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      mutationId: Value(mutationId),
    );
  }

  factory CachedTaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTaskRow(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      goalId: serializer.fromJson<String>(json['goalId']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String?>(json['notes']),
      deadline: serializer.fromJson<DateTime?>(json['deadline']),
      estimatedSeconds: serializer.fromJson<int?>(json['estimatedSeconds']),
      classification: serializer.fromJson<String>(json['classification']),
      focusProgressSeconds: serializer.fromJson<int>(
        json['focusProgressSeconds'],
      ),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      mutationId: serializer.fromJson<String>(json['mutationId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'goalId': serializer.toJson<String>(goalId),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String?>(notes),
      'deadline': serializer.toJson<DateTime?>(deadline),
      'estimatedSeconds': serializer.toJson<int?>(estimatedSeconds),
      'classification': serializer.toJson<String>(classification),
      'focusProgressSeconds': serializer.toJson<int>(focusProgressSeconds),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'mutationId': serializer.toJson<String>(mutationId),
    };
  }

  CachedTaskRow copyWith({
    String? id,
    String? userId,
    String? goalId,
    String? title,
    Value<String?> notes = const Value.absent(),
    Value<DateTime?> deadline = const Value.absent(),
    Value<int?> estimatedSeconds = const Value.absent(),
    String? classification,
    int? focusProgressSeconds,
    Value<DateTime?> completedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    String? mutationId,
  }) => CachedTaskRow(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    goalId: goalId ?? this.goalId,
    title: title ?? this.title,
    notes: notes.present ? notes.value : this.notes,
    deadline: deadline.present ? deadline.value : this.deadline,
    estimatedSeconds: estimatedSeconds.present
        ? estimatedSeconds.value
        : this.estimatedSeconds,
    classification: classification ?? this.classification,
    focusProgressSeconds: focusProgressSeconds ?? this.focusProgressSeconds,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    mutationId: mutationId ?? this.mutationId,
  );
  CachedTaskRow copyWithCompanion(CachedTasksCompanion data) {
    return CachedTaskRow(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      goalId: data.goalId.present ? data.goalId.value : this.goalId,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      deadline: data.deadline.present ? data.deadline.value : this.deadline,
      estimatedSeconds: data.estimatedSeconds.present
          ? data.estimatedSeconds.value
          : this.estimatedSeconds,
      classification: data.classification.present
          ? data.classification.value
          : this.classification,
      focusProgressSeconds: data.focusProgressSeconds.present
          ? data.focusProgressSeconds.value
          : this.focusProgressSeconds,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTaskRow(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('goalId: $goalId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('deadline: $deadline, ')
          ..write('estimatedSeconds: $estimatedSeconds, ')
          ..write('classification: $classification, ')
          ..write('focusProgressSeconds: $focusProgressSeconds, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mutationId: $mutationId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    goalId,
    title,
    notes,
    deadline,
    estimatedSeconds,
    classification,
    focusProgressSeconds,
    completedAt,
    createdAt,
    updatedAt,
    mutationId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTaskRow &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.goalId == this.goalId &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.deadline == this.deadline &&
          other.estimatedSeconds == this.estimatedSeconds &&
          other.classification == this.classification &&
          other.focusProgressSeconds == this.focusProgressSeconds &&
          other.completedAt == this.completedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.mutationId == this.mutationId);
}

class CachedTasksCompanion extends UpdateCompanion<CachedTaskRow> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> goalId;
  final Value<String> title;
  final Value<String?> notes;
  final Value<DateTime?> deadline;
  final Value<int?> estimatedSeconds;
  final Value<String> classification;
  final Value<int> focusProgressSeconds;
  final Value<DateTime?> completedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String> mutationId;
  final Value<int> rowid;
  const CachedTasksCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.goalId = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.deadline = const Value.absent(),
    this.estimatedSeconds = const Value.absent(),
    this.classification = const Value.absent(),
    this.focusProgressSeconds = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.mutationId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedTasksCompanion.insert({
    required String id,
    required String userId,
    required String goalId,
    required String title,
    this.notes = const Value.absent(),
    this.deadline = const Value.absent(),
    this.estimatedSeconds = const Value.absent(),
    required String classification,
    this.focusProgressSeconds = const Value.absent(),
    this.completedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    required String mutationId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       goalId = Value(goalId),
       title = Value(title),
       classification = Value(classification),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       mutationId = Value(mutationId);
  static Insertable<CachedTaskRow> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? goalId,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<DateTime>? deadline,
    Expression<int>? estimatedSeconds,
    Expression<String>? classification,
    Expression<int>? focusProgressSeconds,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? mutationId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (goalId != null) 'goal_id': goalId,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (deadline != null) 'deadline': deadline,
      if (estimatedSeconds != null) 'estimated_seconds': estimatedSeconds,
      if (classification != null) 'classification': classification,
      if (focusProgressSeconds != null)
        'focus_progress_seconds': focusProgressSeconds,
      if (completedAt != null) 'completed_at': completedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (mutationId != null) 'mutation_id': mutationId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? goalId,
    Value<String>? title,
    Value<String?>? notes,
    Value<DateTime?>? deadline,
    Value<int?>? estimatedSeconds,
    Value<String>? classification,
    Value<int>? focusProgressSeconds,
    Value<DateTime?>? completedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String>? mutationId,
    Value<int>? rowid,
  }) {
    return CachedTasksCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      goalId: goalId ?? this.goalId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      deadline: deadline ?? this.deadline,
      estimatedSeconds: estimatedSeconds ?? this.estimatedSeconds,
      classification: classification ?? this.classification,
      focusProgressSeconds: focusProgressSeconds ?? this.focusProgressSeconds,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mutationId: mutationId ?? this.mutationId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (goalId.present) {
      map['goal_id'] = Variable<String>(goalId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (deadline.present) {
      map['deadline'] = Variable<DateTime>(deadline.value);
    }
    if (estimatedSeconds.present) {
      map['estimated_seconds'] = Variable<int>(estimatedSeconds.value);
    }
    if (classification.present) {
      map['classification'] = Variable<String>(classification.value);
    }
    if (focusProgressSeconds.present) {
      map['focus_progress_seconds'] = Variable<int>(focusProgressSeconds.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTasksCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('goalId: $goalId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('deadline: $deadline, ')
          ..write('estimatedSeconds: $estimatedSeconds, ')
          ..write('classification: $classification, ')
          ..write('focusProgressSeconds: $focusProgressSeconds, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mutationId: $mutationId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoalTaskOutboxTable extends GoalTaskOutbox
    with TableInfo<$GoalTaskOutboxTable, GoalTaskOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoalTaskOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    entityType,
    entityId,
    mutationId,
    updatedAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goal_task_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<GoalTaskOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, entityType, entityId};
  @override
  GoalTaskOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GoalTaskOutboxRow(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $GoalTaskOutboxTable createAlias(String alias) {
    return $GoalTaskOutboxTable(attachedDatabase, alias);
  }
}

class GoalTaskOutboxRow extends DataClass
    implements Insertable<GoalTaskOutboxRow> {
  final String userId;
  final String entityType;
  final String entityId;
  final String mutationId;
  final DateTime updatedAt;
  final String payload;
  const GoalTaskOutboxRow({
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.mutationId,
    required this.updatedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['mutation_id'] = Variable<String>(mutationId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  GoalTaskOutboxCompanion toCompanion(bool nullToAbsent) {
    return GoalTaskOutboxCompanion(
      userId: Value(userId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      mutationId: Value(mutationId),
      updatedAt: Value(updatedAt),
      payload: Value(payload),
    );
  }

  factory GoalTaskOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GoalTaskOutboxRow(
      userId: serializer.fromJson<String>(json['userId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      mutationId: serializer.fromJson<String>(json['mutationId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'mutationId': serializer.toJson<String>(mutationId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  GoalTaskOutboxRow copyWith({
    String? userId,
    String? entityType,
    String? entityId,
    String? mutationId,
    DateTime? updatedAt,
    String? payload,
  }) => GoalTaskOutboxRow(
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    mutationId: mutationId ?? this.mutationId,
    updatedAt: updatedAt ?? this.updatedAt,
    payload: payload ?? this.payload,
  );
  GoalTaskOutboxRow copyWithCompanion(GoalTaskOutboxCompanion data) {
    return GoalTaskOutboxRow(
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GoalTaskOutboxRow(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('mutationId: $mutationId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, entityType, entityId, mutationId, updatedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoalTaskOutboxRow &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.mutationId == this.mutationId &&
          other.updatedAt == this.updatedAt &&
          other.payload == this.payload);
}

class GoalTaskOutboxCompanion extends UpdateCompanion<GoalTaskOutboxRow> {
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> mutationId;
  final Value<DateTime> updatedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const GoalTaskOutboxCompanion({
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.mutationId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoalTaskOutboxCompanion.insert({
    required String userId,
    required String entityType,
    required String entityId,
    required String mutationId,
    required DateTime updatedAt,
    required String payload,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       mutationId = Value(mutationId),
       updatedAt = Value(updatedAt),
       payload = Value(payload);
  static Insertable<GoalTaskOutboxRow> custom({
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? mutationId,
    Expression<DateTime>? updatedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (mutationId != null) 'mutation_id': mutationId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoalTaskOutboxCompanion copyWith({
    Value<String>? userId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? mutationId,
    Value<DateTime>? updatedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return GoalTaskOutboxCompanion(
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      mutationId: mutationId ?? this.mutationId,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoalTaskOutboxCompanion(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('mutationId: $mutationId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedProfilesTable cachedProfiles = $CachedProfilesTable(this);
  late final $CachedGoalsTable cachedGoals = $CachedGoalsTable(this);
  late final $CachedTasksTable cachedTasks = $CachedTasksTable(this);
  late final $GoalTaskOutboxTable goalTaskOutbox = $GoalTaskOutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedProfiles,
    cachedGoals,
    cachedTasks,
    goalTaskOutbox,
  ];
}

typedef $$CachedProfilesTableCreateCompanionBuilder =
    CachedProfilesCompanion Function({
      required String userId,
      Value<String?> displayName,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedProfilesTableUpdateCompanionBuilder =
    CachedProfilesCompanion Function({
      Value<String> userId,
      Value<String?> displayName,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedProfilesTable> {
  $$CachedProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedProfilesTable,
          CachedProfileRow,
          $$CachedProfilesTableFilterComposer,
          $$CachedProfilesTableOrderingComposer,
          $$CachedProfilesTableAnnotationComposer,
          $$CachedProfilesTableCreateCompanionBuilder,
          $$CachedProfilesTableUpdateCompanionBuilder,
          (
            CachedProfileRow,
            BaseReferences<
              _$AppDatabase,
              $CachedProfilesTable,
              CachedProfileRow
            >,
          ),
          CachedProfileRow,
          PrefetchHooks Function()
        > {
  $$CachedProfilesTableTableManager(
    _$AppDatabase db,
    $CachedProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion(
                userId: userId,
                displayName: displayName,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                Value<String?> displayName = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedProfilesCompanion.insert(
                userId: userId,
                displayName: displayName,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedProfilesTable,
      CachedProfileRow,
      $$CachedProfilesTableFilterComposer,
      $$CachedProfilesTableOrderingComposer,
      $$CachedProfilesTableAnnotationComposer,
      $$CachedProfilesTableCreateCompanionBuilder,
      $$CachedProfilesTableUpdateCompanionBuilder,
      (
        CachedProfileRow,
        BaseReferences<_$AppDatabase, $CachedProfilesTable, CachedProfileRow>,
      ),
      CachedProfileRow,
      PrefetchHooks Function()
    >;
typedef $$CachedGoalsTableCreateCompanionBuilder =
    CachedGoalsCompanion Function({
      required String id,
      required String userId,
      required String title,
      Value<String?> notes,
      required DateTime createdAt,
      required DateTime updatedAt,
      required String mutationId,
      Value<int> rowid,
    });
typedef $$CachedGoalsTableUpdateCompanionBuilder =
    CachedGoalsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> title,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> mutationId,
      Value<int> rowid,
    });

class $$CachedGoalsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedGoalsTable> {
  $$CachedGoalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedGoalsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedGoalsTable> {
  $$CachedGoalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedGoalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedGoalsTable> {
  $$CachedGoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );
}

class $$CachedGoalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedGoalsTable,
          CachedGoalRow,
          $$CachedGoalsTableFilterComposer,
          $$CachedGoalsTableOrderingComposer,
          $$CachedGoalsTableAnnotationComposer,
          $$CachedGoalsTableCreateCompanionBuilder,
          $$CachedGoalsTableUpdateCompanionBuilder,
          (
            CachedGoalRow,
            BaseReferences<_$AppDatabase, $CachedGoalsTable, CachedGoalRow>,
          ),
          CachedGoalRow,
          PrefetchHooks Function()
        > {
  $$CachedGoalsTableTableManager(_$AppDatabase db, $CachedGoalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedGoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedGoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedGoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> mutationId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedGoalsCompanion(
                id: id,
                userId: userId,
                title: title,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mutationId: mutationId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String title,
                Value<String?> notes = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                required String mutationId,
                Value<int> rowid = const Value.absent(),
              }) => CachedGoalsCompanion.insert(
                id: id,
                userId: userId,
                title: title,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mutationId: mutationId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedGoalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedGoalsTable,
      CachedGoalRow,
      $$CachedGoalsTableFilterComposer,
      $$CachedGoalsTableOrderingComposer,
      $$CachedGoalsTableAnnotationComposer,
      $$CachedGoalsTableCreateCompanionBuilder,
      $$CachedGoalsTableUpdateCompanionBuilder,
      (
        CachedGoalRow,
        BaseReferences<_$AppDatabase, $CachedGoalsTable, CachedGoalRow>,
      ),
      CachedGoalRow,
      PrefetchHooks Function()
    >;
typedef $$CachedTasksTableCreateCompanionBuilder =
    CachedTasksCompanion Function({
      required String id,
      required String userId,
      required String goalId,
      required String title,
      Value<String?> notes,
      Value<DateTime?> deadline,
      Value<int?> estimatedSeconds,
      required String classification,
      Value<int> focusProgressSeconds,
      Value<DateTime?> completedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      required String mutationId,
      Value<int> rowid,
    });
typedef $$CachedTasksTableUpdateCompanionBuilder =
    CachedTasksCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> goalId,
      Value<String> title,
      Value<String?> notes,
      Value<DateTime?> deadline,
      Value<int?> estimatedSeconds,
      Value<String> classification,
      Value<int> focusProgressSeconds,
      Value<DateTime?> completedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String> mutationId,
      Value<int> rowid,
    });

class $$CachedTasksTableFilterComposer
    extends Composer<_$AppDatabase, $CachedTasksTable> {
  $$CachedTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalId => $composableBuilder(
    column: $table.goalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedSeconds => $composableBuilder(
    column: $table.estimatedSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get focusProgressSeconds => $composableBuilder(
    column: $table.focusProgressSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedTasksTable> {
  $$CachedTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalId => $composableBuilder(
    column: $table.goalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedSeconds => $composableBuilder(
    column: $table.estimatedSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get focusProgressSeconds => $composableBuilder(
    column: $table.focusProgressSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedTasksTable> {
  $$CachedTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get goalId =>
      $composableBuilder(column: $table.goalId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get deadline =>
      $composableBuilder(column: $table.deadline, builder: (column) => column);

  GeneratedColumn<int> get estimatedSeconds => $composableBuilder(
    column: $table.estimatedSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => column,
  );

  GeneratedColumn<int> get focusProgressSeconds => $composableBuilder(
    column: $table.focusProgressSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );
}

class $$CachedTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedTasksTable,
          CachedTaskRow,
          $$CachedTasksTableFilterComposer,
          $$CachedTasksTableOrderingComposer,
          $$CachedTasksTableAnnotationComposer,
          $$CachedTasksTableCreateCompanionBuilder,
          $$CachedTasksTableUpdateCompanionBuilder,
          (
            CachedTaskRow,
            BaseReferences<_$AppDatabase, $CachedTasksTable, CachedTaskRow>,
          ),
          CachedTaskRow,
          PrefetchHooks Function()
        > {
  $$CachedTasksTableTableManager(_$AppDatabase db, $CachedTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> goalId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> deadline = const Value.absent(),
                Value<int?> estimatedSeconds = const Value.absent(),
                Value<String> classification = const Value.absent(),
                Value<int> focusProgressSeconds = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> mutationId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedTasksCompanion(
                id: id,
                userId: userId,
                goalId: goalId,
                title: title,
                notes: notes,
                deadline: deadline,
                estimatedSeconds: estimatedSeconds,
                classification: classification,
                focusProgressSeconds: focusProgressSeconds,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mutationId: mutationId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String goalId,
                required String title,
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> deadline = const Value.absent(),
                Value<int?> estimatedSeconds = const Value.absent(),
                required String classification,
                Value<int> focusProgressSeconds = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                required String mutationId,
                Value<int> rowid = const Value.absent(),
              }) => CachedTasksCompanion.insert(
                id: id,
                userId: userId,
                goalId: goalId,
                title: title,
                notes: notes,
                deadline: deadline,
                estimatedSeconds: estimatedSeconds,
                classification: classification,
                focusProgressSeconds: focusProgressSeconds,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mutationId: mutationId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedTasksTable,
      CachedTaskRow,
      $$CachedTasksTableFilterComposer,
      $$CachedTasksTableOrderingComposer,
      $$CachedTasksTableAnnotationComposer,
      $$CachedTasksTableCreateCompanionBuilder,
      $$CachedTasksTableUpdateCompanionBuilder,
      (
        CachedTaskRow,
        BaseReferences<_$AppDatabase, $CachedTasksTable, CachedTaskRow>,
      ),
      CachedTaskRow,
      PrefetchHooks Function()
    >;
typedef $$GoalTaskOutboxTableCreateCompanionBuilder =
    GoalTaskOutboxCompanion Function({
      required String userId,
      required String entityType,
      required String entityId,
      required String mutationId,
      required DateTime updatedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$GoalTaskOutboxTableUpdateCompanionBuilder =
    GoalTaskOutboxCompanion Function({
      Value<String> userId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> mutationId,
      Value<DateTime> updatedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$GoalTaskOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $GoalTaskOutboxTable> {
  $$GoalTaskOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GoalTaskOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $GoalTaskOutboxTable> {
  $$GoalTaskOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GoalTaskOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $GoalTaskOutboxTable> {
  $$GoalTaskOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$GoalTaskOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GoalTaskOutboxTable,
          GoalTaskOutboxRow,
          $$GoalTaskOutboxTableFilterComposer,
          $$GoalTaskOutboxTableOrderingComposer,
          $$GoalTaskOutboxTableAnnotationComposer,
          $$GoalTaskOutboxTableCreateCompanionBuilder,
          $$GoalTaskOutboxTableUpdateCompanionBuilder,
          (
            GoalTaskOutboxRow,
            BaseReferences<
              _$AppDatabase,
              $GoalTaskOutboxTable,
              GoalTaskOutboxRow
            >,
          ),
          GoalTaskOutboxRow,
          PrefetchHooks Function()
        > {
  $$GoalTaskOutboxTableTableManager(
    _$AppDatabase db,
    $GoalTaskOutboxTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GoalTaskOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GoalTaskOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GoalTaskOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> mutationId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GoalTaskOutboxCompanion(
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                mutationId: mutationId,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String entityType,
                required String entityId,
                required String mutationId,
                required DateTime updatedAt,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => GoalTaskOutboxCompanion.insert(
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                mutationId: mutationId,
                updatedAt: updatedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GoalTaskOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GoalTaskOutboxTable,
      GoalTaskOutboxRow,
      $$GoalTaskOutboxTableFilterComposer,
      $$GoalTaskOutboxTableOrderingComposer,
      $$GoalTaskOutboxTableAnnotationComposer,
      $$GoalTaskOutboxTableCreateCompanionBuilder,
      $$GoalTaskOutboxTableUpdateCompanionBuilder,
      (
        GoalTaskOutboxRow,
        BaseReferences<_$AppDatabase, $GoalTaskOutboxTable, GoalTaskOutboxRow>,
      ),
      GoalTaskOutboxRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedProfilesTableTableManager get cachedProfiles =>
      $$CachedProfilesTableTableManager(_db, _db.cachedProfiles);
  $$CachedGoalsTableTableManager get cachedGoals =>
      $$CachedGoalsTableTableManager(_db, _db.cachedGoals);
  $$CachedTasksTableTableManager get cachedTasks =>
      $$CachedTasksTableTableManager(_db, _db.cachedTasks);
  $$GoalTaskOutboxTableTableManager get goalTaskOutbox =>
      $$GoalTaskOutboxTableTableManager(_db, _db.goalTaskOutbox);
}
