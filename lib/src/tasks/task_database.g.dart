// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_database.dart';

// ignore_for_file: type=lint
class $LocalGoalsTable extends LocalGoals
    with TableInfo<$LocalGoalsTable, LocalGoal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalGoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    title,
    classification,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_goals';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalGoal> instance, {
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
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
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
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  LocalGoal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalGoal(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      classification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalGoalsTable createAlias(String alias) {
    return $LocalGoalsTable(attachedDatabase, alias);
  }
}

class LocalGoal extends DataClass implements Insertable<LocalGoal> {
  final String userId;
  final String id;
  final String title;
  final String classification;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalGoal({
    required this.userId,
    required this.id,
    required this.title,
    required this.classification,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['classification'] = Variable<String>(classification);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalGoalsCompanion toCompanion(bool nullToAbsent) {
    return LocalGoalsCompanion(
      userId: Value(userId),
      id: Value(id),
      title: Value(title),
      classification: Value(classification),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalGoal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalGoal(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      classification: serializer.fromJson<String>(json['classification']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'classification': serializer.toJson<String>(classification),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalGoal copyWith({
    String? userId,
    String? id,
    String? title,
    String? classification,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalGoal(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    title: title ?? this.title,
    classification: classification ?? this.classification,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalGoal copyWithCompanion(LocalGoalsCompanion data) {
    return LocalGoal(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      classification: data.classification.present
          ? data.classification.value
          : this.classification,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalGoal(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('classification: $classification, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    title,
    classification,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalGoal &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.title == this.title &&
          other.classification == this.classification &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalGoalsCompanion extends UpdateCompanion<LocalGoal> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> title;
  final Value<String> classification;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalGoalsCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.classification = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalGoalsCompanion.insert({
    required String userId,
    required String id,
    required String title,
    required String classification,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       title = Value(title),
       classification = Value(classification),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalGoal> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? classification,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (classification != null) 'classification': classification,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalGoalsCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? title,
    Value<String>? classification,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalGoalsCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      title: title ?? this.title,
      classification: classification ?? this.classification,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (classification.present) {
      map['classification'] = Variable<String>(classification.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalGoalsCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('classification: $classification, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTasksTable extends LocalTasks
    with TableInfo<$LocalTasksTable, LocalTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _estimatedMinutesMeta = const VerificationMeta(
    'estimatedMinutes',
  );
  @override
  late final GeneratedColumn<int> estimatedMinutes = GeneratedColumn<int>(
    'estimated_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _isCompleteMeta = const VerificationMeta(
    'isComplete',
  );
  @override
  late final GeneratedColumn<bool> isComplete = GeneratedColumn<bool>(
    'is_complete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_complete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    goalId,
    title,
    classification,
    estimatedMinutes,
    deadline,
    isComplete,
    focusProgressSeconds,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTask> instance, {
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
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
    if (data.containsKey('estimated_minutes')) {
      context.handle(
        _estimatedMinutesMeta,
        estimatedMinutes.isAcceptableOrUnknown(
          data['estimated_minutes']!,
          _estimatedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('deadline')) {
      context.handle(
        _deadlineMeta,
        deadline.isAcceptableOrUnknown(data['deadline']!, _deadlineMeta),
      );
    }
    if (data.containsKey('is_complete')) {
      context.handle(
        _isCompleteMeta,
        isComplete.isAcceptableOrUnknown(data['is_complete']!, _isCompleteMeta),
      );
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
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  LocalTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTask(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      goalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      classification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification'],
      )!,
      estimatedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_minutes'],
      ),
      deadline: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deadline'],
      ),
      isComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_complete'],
      )!,
      focusProgressSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}focus_progress_seconds'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalTasksTable createAlias(String alias) {
    return $LocalTasksTable(attachedDatabase, alias);
  }
}

class LocalTask extends DataClass implements Insertable<LocalTask> {
  final String userId;
  final String id;
  final String goalId;
  final String title;
  final String classification;
  final int? estimatedMinutes;
  final DateTime? deadline;
  final bool isComplete;
  final int focusProgressSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalTask({
    required this.userId,
    required this.id,
    required this.goalId,
    required this.title,
    required this.classification,
    this.estimatedMinutes,
    this.deadline,
    required this.isComplete,
    required this.focusProgressSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['goal_id'] = Variable<String>(goalId);
    map['title'] = Variable<String>(title);
    map['classification'] = Variable<String>(classification);
    if (!nullToAbsent || estimatedMinutes != null) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes);
    }
    if (!nullToAbsent || deadline != null) {
      map['deadline'] = Variable<DateTime>(deadline);
    }
    map['is_complete'] = Variable<bool>(isComplete);
    map['focus_progress_seconds'] = Variable<int>(focusProgressSeconds);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalTasksCompanion toCompanion(bool nullToAbsent) {
    return LocalTasksCompanion(
      userId: Value(userId),
      id: Value(id),
      goalId: Value(goalId),
      title: Value(title),
      classification: Value(classification),
      estimatedMinutes: estimatedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedMinutes),
      deadline: deadline == null && nullToAbsent
          ? const Value.absent()
          : Value(deadline),
      isComplete: Value(isComplete),
      focusProgressSeconds: Value(focusProgressSeconds),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTask(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      goalId: serializer.fromJson<String>(json['goalId']),
      title: serializer.fromJson<String>(json['title']),
      classification: serializer.fromJson<String>(json['classification']),
      estimatedMinutes: serializer.fromJson<int?>(json['estimatedMinutes']),
      deadline: serializer.fromJson<DateTime?>(json['deadline']),
      isComplete: serializer.fromJson<bool>(json['isComplete']),
      focusProgressSeconds: serializer.fromJson<int>(
        json['focusProgressSeconds'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'goalId': serializer.toJson<String>(goalId),
      'title': serializer.toJson<String>(title),
      'classification': serializer.toJson<String>(classification),
      'estimatedMinutes': serializer.toJson<int?>(estimatedMinutes),
      'deadline': serializer.toJson<DateTime?>(deadline),
      'isComplete': serializer.toJson<bool>(isComplete),
      'focusProgressSeconds': serializer.toJson<int>(focusProgressSeconds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalTask copyWith({
    String? userId,
    String? id,
    String? goalId,
    String? title,
    String? classification,
    Value<int?> estimatedMinutes = const Value.absent(),
    Value<DateTime?> deadline = const Value.absent(),
    bool? isComplete,
    int? focusProgressSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalTask(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    goalId: goalId ?? this.goalId,
    title: title ?? this.title,
    classification: classification ?? this.classification,
    estimatedMinutes: estimatedMinutes.present
        ? estimatedMinutes.value
        : this.estimatedMinutes,
    deadline: deadline.present ? deadline.value : this.deadline,
    isComplete: isComplete ?? this.isComplete,
    focusProgressSeconds: focusProgressSeconds ?? this.focusProgressSeconds,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalTask copyWithCompanion(LocalTasksCompanion data) {
    return LocalTask(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      goalId: data.goalId.present ? data.goalId.value : this.goalId,
      title: data.title.present ? data.title.value : this.title,
      classification: data.classification.present
          ? data.classification.value
          : this.classification,
      estimatedMinutes: data.estimatedMinutes.present
          ? data.estimatedMinutes.value
          : this.estimatedMinutes,
      deadline: data.deadline.present ? data.deadline.value : this.deadline,
      isComplete: data.isComplete.present
          ? data.isComplete.value
          : this.isComplete,
      focusProgressSeconds: data.focusProgressSeconds.present
          ? data.focusProgressSeconds.value
          : this.focusProgressSeconds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTask(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('goalId: $goalId, ')
          ..write('title: $title, ')
          ..write('classification: $classification, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('deadline: $deadline, ')
          ..write('isComplete: $isComplete, ')
          ..write('focusProgressSeconds: $focusProgressSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    goalId,
    title,
    classification,
    estimatedMinutes,
    deadline,
    isComplete,
    focusProgressSeconds,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTask &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.goalId == this.goalId &&
          other.title == this.title &&
          other.classification == this.classification &&
          other.estimatedMinutes == this.estimatedMinutes &&
          other.deadline == this.deadline &&
          other.isComplete == this.isComplete &&
          other.focusProgressSeconds == this.focusProgressSeconds &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalTasksCompanion extends UpdateCompanion<LocalTask> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> goalId;
  final Value<String> title;
  final Value<String> classification;
  final Value<int?> estimatedMinutes;
  final Value<DateTime?> deadline;
  final Value<bool> isComplete;
  final Value<int> focusProgressSeconds;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalTasksCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.goalId = const Value.absent(),
    this.title = const Value.absent(),
    this.classification = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.deadline = const Value.absent(),
    this.isComplete = const Value.absent(),
    this.focusProgressSeconds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTasksCompanion.insert({
    required String userId,
    required String id,
    required String goalId,
    required String title,
    required String classification,
    this.estimatedMinutes = const Value.absent(),
    this.deadline = const Value.absent(),
    this.isComplete = const Value.absent(),
    this.focusProgressSeconds = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       goalId = Value(goalId),
       title = Value(title),
       classification = Value(classification),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalTask> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? goalId,
    Expression<String>? title,
    Expression<String>? classification,
    Expression<int>? estimatedMinutes,
    Expression<DateTime>? deadline,
    Expression<bool>? isComplete,
    Expression<int>? focusProgressSeconds,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (goalId != null) 'goal_id': goalId,
      if (title != null) 'title': title,
      if (classification != null) 'classification': classification,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (deadline != null) 'deadline': deadline,
      if (isComplete != null) 'is_complete': isComplete,
      if (focusProgressSeconds != null)
        'focus_progress_seconds': focusProgressSeconds,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTasksCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? goalId,
    Value<String>? title,
    Value<String>? classification,
    Value<int?>? estimatedMinutes,
    Value<DateTime?>? deadline,
    Value<bool>? isComplete,
    Value<int>? focusProgressSeconds,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalTasksCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      goalId: goalId ?? this.goalId,
      title: title ?? this.title,
      classification: classification ?? this.classification,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      deadline: deadline ?? this.deadline,
      isComplete: isComplete ?? this.isComplete,
      focusProgressSeconds: focusProgressSeconds ?? this.focusProgressSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (goalId.present) {
      map['goal_id'] = Variable<String>(goalId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (classification.present) {
      map['classification'] = Variable<String>(classification.value);
    }
    if (estimatedMinutes.present) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes.value);
    }
    if (deadline.present) {
      map['deadline'] = Variable<DateTime>(deadline.value);
    }
    if (isComplete.present) {
      map['is_complete'] = Variable<bool>(isComplete.value);
    }
    if (focusProgressSeconds.present) {
      map['focus_progress_seconds'] = Variable<int>(focusProgressSeconds.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTasksCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('goalId: $goalId, ')
          ..write('title: $title, ')
          ..write('classification: $classification, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('deadline: $deadline, ')
          ..write('isComplete: $isComplete, ')
          ..write('focusProgressSeconds: $focusProgressSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskSyncEntriesTable extends TaskSyncEntries
    with TableInfo<$TaskSyncEntriesTable, TaskSyncEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskSyncEntriesTable(this.attachedDatabase, [this._alias]);
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
  List<GeneratedColumn> get $columns => [
    userId,
    entityType,
    entityId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_sync_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskSyncEntry> instance, {
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
  Set<GeneratedColumn> get $primaryKey => {userId, entityType, entityId};
  @override
  TaskSyncEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskSyncEntry(
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
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TaskSyncEntriesTable createAlias(String alias) {
    return $TaskSyncEntriesTable(attachedDatabase, alias);
  }
}

class TaskSyncEntry extends DataClass implements Insertable<TaskSyncEntry> {
  final String userId;
  final String entityType;
  final String entityId;
  final DateTime updatedAt;
  const TaskSyncEntry({
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TaskSyncEntriesCompanion toCompanion(bool nullToAbsent) {
    return TaskSyncEntriesCompanion(
      userId: Value(userId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      updatedAt: Value(updatedAt),
    );
  }

  factory TaskSyncEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskSyncEntry(
      userId: serializer.fromJson<String>(json['userId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TaskSyncEntry copyWith({
    String? userId,
    String? entityType,
    String? entityId,
    DateTime? updatedAt,
  }) => TaskSyncEntry(
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TaskSyncEntry copyWithCompanion(TaskSyncEntriesCompanion data) {
    return TaskSyncEntry(
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskSyncEntry(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, entityType, entityId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskSyncEntry &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.updatedAt == this.updatedAt);
}

class TaskSyncEntriesCompanion extends UpdateCompanion<TaskSyncEntry> {
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TaskSyncEntriesCompanion({
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskSyncEntriesCompanion.insert({
    required String userId,
    required String entityType,
    required String entityId,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       updatedAt = Value(updatedAt);
  static Insertable<TaskSyncEntry> custom({
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskSyncEntriesCompanion copyWith({
    Value<String>? userId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TaskSyncEntriesCompanion(
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
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
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
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
    return (StringBuffer('TaskSyncEntriesCompanion(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusSessionsTable extends FocusSessions
    with TableInfo<$FocusSessionsTable, FocusSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appointmentIdMeta = const VerificationMeta(
    'appointmentId',
  );
  @override
  late final GeneratedColumn<String> appointmentId = GeneratedColumn<String>(
    'appointment_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMeta = const VerificationMeta('endsAt');
  @override
  late final GeneratedColumn<DateTime> endsAt = GeneratedColumn<DateTime>(
    'ends_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _effectiveSecondsMeta = const VerificationMeta(
    'effectiveSeconds',
  );
  @override
  late final GeneratedColumn<int> effectiveSeconds = GeneratedColumn<int>(
    'effective_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completionTypeMeta = const VerificationMeta(
    'completionType',
  );
  @override
  late final GeneratedColumn<String> completionType = GeneratedColumn<String>(
    'completion_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('countdown'),
  );
  static const VerificationMeta _completionRuleTextMeta =
      const VerificationMeta('completionRuleText');
  @override
  late final GeneratedColumn<String> completionRuleText =
      GeneratedColumn<String>(
        'completion_rule_text',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _pausedAtMeta = const VerificationMeta(
    'pausedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pausedAt = GeneratedColumn<DateTime>(
    'paused_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pausedSecondsMeta = const VerificationMeta(
    'pausedSeconds',
  );
  @override
  late final GeneratedColumn<int> pausedSeconds = GeneratedColumn<int>(
    'paused_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pauseRuleTextMeta = const VerificationMeta(
    'pauseRuleText',
  );
  @override
  late final GeneratedColumn<String> pauseRuleText = GeneratedColumn<String>(
    'pause_rule_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effectiveIntervalsMeta =
      const VerificationMeta('effectiveIntervals');
  @override
  late final GeneratedColumn<String> effectiveIntervals =
      GeneratedColumn<String>(
        'effective_intervals',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _reviewDispositionMeta = const VerificationMeta(
    'reviewDisposition',
  );
  @override
  late final GeneratedColumn<String> reviewDisposition =
      GeneratedColumn<String>(
        'review_disposition',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('accepted'),
      );
  static const VerificationMeta _reviewDispositionUpdatedAtMeta =
      const VerificationMeta('reviewDispositionUpdatedAt');
  @override
  late final GeneratedColumn<DateTime> reviewDispositionUpdatedAt =
      GeneratedColumn<DateTime>(
        'review_disposition_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    appointmentId,
    taskId,
    mode,
    durationSeconds,
    startedAt,
    endsAt,
    status,
    completedAt,
    effectiveSeconds,
    completionType,
    completionRuleText,
    pausedAt,
    pausedSeconds,
    pauseRuleText,
    failureReason,
    effectiveIntervals,
    reviewDisposition,
    reviewDispositionUpdatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusSession> instance, {
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
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('appointment_id')) {
      context.handle(
        _appointmentIdMeta,
        appointmentId.isAcceptableOrUnknown(
          data['appointment_id']!,
          _appointmentIdMeta,
        ),
      );
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ends_at')) {
      context.handle(
        _endsAtMeta,
        endsAt.isAcceptableOrUnknown(data['ends_at']!, _endsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
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
    if (data.containsKey('effective_seconds')) {
      context.handle(
        _effectiveSecondsMeta,
        effectiveSeconds.isAcceptableOrUnknown(
          data['effective_seconds']!,
          _effectiveSecondsMeta,
        ),
      );
    }
    if (data.containsKey('completion_type')) {
      context.handle(
        _completionTypeMeta,
        completionType.isAcceptableOrUnknown(
          data['completion_type']!,
          _completionTypeMeta,
        ),
      );
    }
    if (data.containsKey('completion_rule_text')) {
      context.handle(
        _completionRuleTextMeta,
        completionRuleText.isAcceptableOrUnknown(
          data['completion_rule_text']!,
          _completionRuleTextMeta,
        ),
      );
    }
    if (data.containsKey('paused_at')) {
      context.handle(
        _pausedAtMeta,
        pausedAt.isAcceptableOrUnknown(data['paused_at']!, _pausedAtMeta),
      );
    }
    if (data.containsKey('paused_seconds')) {
      context.handle(
        _pausedSecondsMeta,
        pausedSeconds.isAcceptableOrUnknown(
          data['paused_seconds']!,
          _pausedSecondsMeta,
        ),
      );
    }
    if (data.containsKey('pause_rule_text')) {
      context.handle(
        _pauseRuleTextMeta,
        pauseRuleText.isAcceptableOrUnknown(
          data['pause_rule_text']!,
          _pauseRuleTextMeta,
        ),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('effective_intervals')) {
      context.handle(
        _effectiveIntervalsMeta,
        effectiveIntervals.isAcceptableOrUnknown(
          data['effective_intervals']!,
          _effectiveIntervalsMeta,
        ),
      );
    }
    if (data.containsKey('review_disposition')) {
      context.handle(
        _reviewDispositionMeta,
        reviewDisposition.isAcceptableOrUnknown(
          data['review_disposition']!,
          _reviewDispositionMeta,
        ),
      );
    }
    if (data.containsKey('review_disposition_updated_at')) {
      context.handle(
        _reviewDispositionUpdatedAtMeta,
        reviewDispositionUpdatedAt.isAcceptableOrUnknown(
          data['review_disposition_updated_at']!,
          _reviewDispositionUpdatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  FocusSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSession(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      appointmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}appointment_id'],
      ),
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ends_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      effectiveSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}effective_seconds'],
      )!,
      completionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completion_type'],
      )!,
      completionRuleText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completion_rule_text'],
      ),
      pausedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paused_at'],
      ),
      pausedSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paused_seconds'],
      )!,
      pauseRuleText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pause_rule_text'],
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      effectiveIntervals: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_intervals'],
      )!,
      reviewDisposition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_disposition'],
      )!,
      reviewDispositionUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}review_disposition_updated_at'],
      ),
    );
  }

  @override
  $FocusSessionsTable createAlias(String alias) {
    return $FocusSessionsTable(attachedDatabase, alias);
  }
}

class FocusSession extends DataClass implements Insertable<FocusSession> {
  final String userId;
  final String id;
  final String? appointmentId;
  final String taskId;
  final String mode;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime endsAt;
  final String status;
  final DateTime? completedAt;
  final int effectiveSeconds;
  final String completionType;
  final String? completionRuleText;
  final DateTime? pausedAt;
  final int pausedSeconds;
  final String? pauseRuleText;
  final String? failureReason;
  final String effectiveIntervals;
  final String reviewDisposition;
  final DateTime? reviewDispositionUpdatedAt;
  const FocusSession({
    required this.userId,
    required this.id,
    this.appointmentId,
    required this.taskId,
    required this.mode,
    required this.durationSeconds,
    required this.startedAt,
    required this.endsAt,
    required this.status,
    this.completedAt,
    required this.effectiveSeconds,
    required this.completionType,
    this.completionRuleText,
    this.pausedAt,
    required this.pausedSeconds,
    this.pauseRuleText,
    this.failureReason,
    required this.effectiveIntervals,
    required this.reviewDisposition,
    this.reviewDispositionUpdatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || appointmentId != null) {
      map['appointment_id'] = Variable<String>(appointmentId);
    }
    map['task_id'] = Variable<String>(taskId);
    map['mode'] = Variable<String>(mode);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['ends_at'] = Variable<DateTime>(endsAt);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['effective_seconds'] = Variable<int>(effectiveSeconds);
    map['completion_type'] = Variable<String>(completionType);
    if (!nullToAbsent || completionRuleText != null) {
      map['completion_rule_text'] = Variable<String>(completionRuleText);
    }
    if (!nullToAbsent || pausedAt != null) {
      map['paused_at'] = Variable<DateTime>(pausedAt);
    }
    map['paused_seconds'] = Variable<int>(pausedSeconds);
    if (!nullToAbsent || pauseRuleText != null) {
      map['pause_rule_text'] = Variable<String>(pauseRuleText);
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    map['effective_intervals'] = Variable<String>(effectiveIntervals);
    map['review_disposition'] = Variable<String>(reviewDisposition);
    if (!nullToAbsent || reviewDispositionUpdatedAt != null) {
      map['review_disposition_updated_at'] = Variable<DateTime>(
        reviewDispositionUpdatedAt,
      );
    }
    return map;
  }

  FocusSessionsCompanion toCompanion(bool nullToAbsent) {
    return FocusSessionsCompanion(
      userId: Value(userId),
      id: Value(id),
      appointmentId: appointmentId == null && nullToAbsent
          ? const Value.absent()
          : Value(appointmentId),
      taskId: Value(taskId),
      mode: Value(mode),
      durationSeconds: Value(durationSeconds),
      startedAt: Value(startedAt),
      endsAt: Value(endsAt),
      status: Value(status),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      effectiveSeconds: Value(effectiveSeconds),
      completionType: Value(completionType),
      completionRuleText: completionRuleText == null && nullToAbsent
          ? const Value.absent()
          : Value(completionRuleText),
      pausedAt: pausedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pausedAt),
      pausedSeconds: Value(pausedSeconds),
      pauseRuleText: pauseRuleText == null && nullToAbsent
          ? const Value.absent()
          : Value(pauseRuleText),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      effectiveIntervals: Value(effectiveIntervals),
      reviewDisposition: Value(reviewDisposition),
      reviewDispositionUpdatedAt:
          reviewDispositionUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewDispositionUpdatedAt),
    );
  }

  factory FocusSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSession(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      appointmentId: serializer.fromJson<String?>(json['appointmentId']),
      taskId: serializer.fromJson<String>(json['taskId']),
      mode: serializer.fromJson<String>(json['mode']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endsAt: serializer.fromJson<DateTime>(json['endsAt']),
      status: serializer.fromJson<String>(json['status']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      effectiveSeconds: serializer.fromJson<int>(json['effectiveSeconds']),
      completionType: serializer.fromJson<String>(json['completionType']),
      completionRuleText: serializer.fromJson<String?>(
        json['completionRuleText'],
      ),
      pausedAt: serializer.fromJson<DateTime?>(json['pausedAt']),
      pausedSeconds: serializer.fromJson<int>(json['pausedSeconds']),
      pauseRuleText: serializer.fromJson<String?>(json['pauseRuleText']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      effectiveIntervals: serializer.fromJson<String>(
        json['effectiveIntervals'],
      ),
      reviewDisposition: serializer.fromJson<String>(json['reviewDisposition']),
      reviewDispositionUpdatedAt: serializer.fromJson<DateTime?>(
        json['reviewDispositionUpdatedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'appointmentId': serializer.toJson<String?>(appointmentId),
      'taskId': serializer.toJson<String>(taskId),
      'mode': serializer.toJson<String>(mode),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endsAt': serializer.toJson<DateTime>(endsAt),
      'status': serializer.toJson<String>(status),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'effectiveSeconds': serializer.toJson<int>(effectiveSeconds),
      'completionType': serializer.toJson<String>(completionType),
      'completionRuleText': serializer.toJson<String?>(completionRuleText),
      'pausedAt': serializer.toJson<DateTime?>(pausedAt),
      'pausedSeconds': serializer.toJson<int>(pausedSeconds),
      'pauseRuleText': serializer.toJson<String?>(pauseRuleText),
      'failureReason': serializer.toJson<String?>(failureReason),
      'effectiveIntervals': serializer.toJson<String>(effectiveIntervals),
      'reviewDisposition': serializer.toJson<String>(reviewDisposition),
      'reviewDispositionUpdatedAt': serializer.toJson<DateTime?>(
        reviewDispositionUpdatedAt,
      ),
    };
  }

  FocusSession copyWith({
    String? userId,
    String? id,
    Value<String?> appointmentId = const Value.absent(),
    String? taskId,
    String? mode,
    int? durationSeconds,
    DateTime? startedAt,
    DateTime? endsAt,
    String? status,
    Value<DateTime?> completedAt = const Value.absent(),
    int? effectiveSeconds,
    String? completionType,
    Value<String?> completionRuleText = const Value.absent(),
    Value<DateTime?> pausedAt = const Value.absent(),
    int? pausedSeconds,
    Value<String?> pauseRuleText = const Value.absent(),
    Value<String?> failureReason = const Value.absent(),
    String? effectiveIntervals,
    String? reviewDisposition,
    Value<DateTime?> reviewDispositionUpdatedAt = const Value.absent(),
  }) => FocusSession(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    appointmentId: appointmentId.present
        ? appointmentId.value
        : this.appointmentId,
    taskId: taskId ?? this.taskId,
    mode: mode ?? this.mode,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    startedAt: startedAt ?? this.startedAt,
    endsAt: endsAt ?? this.endsAt,
    status: status ?? this.status,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    effectiveSeconds: effectiveSeconds ?? this.effectiveSeconds,
    completionType: completionType ?? this.completionType,
    completionRuleText: completionRuleText.present
        ? completionRuleText.value
        : this.completionRuleText,
    pausedAt: pausedAt.present ? pausedAt.value : this.pausedAt,
    pausedSeconds: pausedSeconds ?? this.pausedSeconds,
    pauseRuleText: pauseRuleText.present
        ? pauseRuleText.value
        : this.pauseRuleText,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    effectiveIntervals: effectiveIntervals ?? this.effectiveIntervals,
    reviewDisposition: reviewDisposition ?? this.reviewDisposition,
    reviewDispositionUpdatedAt: reviewDispositionUpdatedAt.present
        ? reviewDispositionUpdatedAt.value
        : this.reviewDispositionUpdatedAt,
  );
  FocusSession copyWithCompanion(FocusSessionsCompanion data) {
    return FocusSession(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      appointmentId: data.appointmentId.present
          ? data.appointmentId.value
          : this.appointmentId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      mode: data.mode.present ? data.mode.value : this.mode,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endsAt: data.endsAt.present ? data.endsAt.value : this.endsAt,
      status: data.status.present ? data.status.value : this.status,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      effectiveSeconds: data.effectiveSeconds.present
          ? data.effectiveSeconds.value
          : this.effectiveSeconds,
      completionType: data.completionType.present
          ? data.completionType.value
          : this.completionType,
      completionRuleText: data.completionRuleText.present
          ? data.completionRuleText.value
          : this.completionRuleText,
      pausedAt: data.pausedAt.present ? data.pausedAt.value : this.pausedAt,
      pausedSeconds: data.pausedSeconds.present
          ? data.pausedSeconds.value
          : this.pausedSeconds,
      pauseRuleText: data.pauseRuleText.present
          ? data.pauseRuleText.value
          : this.pauseRuleText,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      effectiveIntervals: data.effectiveIntervals.present
          ? data.effectiveIntervals.value
          : this.effectiveIntervals,
      reviewDisposition: data.reviewDisposition.present
          ? data.reviewDisposition.value
          : this.reviewDisposition,
      reviewDispositionUpdatedAt: data.reviewDispositionUpdatedAt.present
          ? data.reviewDispositionUpdatedAt.value
          : this.reviewDispositionUpdatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusSession(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('appointmentId: $appointmentId, ')
          ..write('taskId: $taskId, ')
          ..write('mode: $mode, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('startedAt: $startedAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('status: $status, ')
          ..write('completedAt: $completedAt, ')
          ..write('effectiveSeconds: $effectiveSeconds, ')
          ..write('completionType: $completionType, ')
          ..write('completionRuleText: $completionRuleText, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('pausedSeconds: $pausedSeconds, ')
          ..write('pauseRuleText: $pauseRuleText, ')
          ..write('failureReason: $failureReason, ')
          ..write('effectiveIntervals: $effectiveIntervals, ')
          ..write('reviewDisposition: $reviewDisposition, ')
          ..write('reviewDispositionUpdatedAt: $reviewDispositionUpdatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    appointmentId,
    taskId,
    mode,
    durationSeconds,
    startedAt,
    endsAt,
    status,
    completedAt,
    effectiveSeconds,
    completionType,
    completionRuleText,
    pausedAt,
    pausedSeconds,
    pauseRuleText,
    failureReason,
    effectiveIntervals,
    reviewDisposition,
    reviewDispositionUpdatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSession &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.appointmentId == this.appointmentId &&
          other.taskId == this.taskId &&
          other.mode == this.mode &&
          other.durationSeconds == this.durationSeconds &&
          other.startedAt == this.startedAt &&
          other.endsAt == this.endsAt &&
          other.status == this.status &&
          other.completedAt == this.completedAt &&
          other.effectiveSeconds == this.effectiveSeconds &&
          other.completionType == this.completionType &&
          other.completionRuleText == this.completionRuleText &&
          other.pausedAt == this.pausedAt &&
          other.pausedSeconds == this.pausedSeconds &&
          other.pauseRuleText == this.pauseRuleText &&
          other.failureReason == this.failureReason &&
          other.effectiveIntervals == this.effectiveIntervals &&
          other.reviewDisposition == this.reviewDisposition &&
          other.reviewDispositionUpdatedAt == this.reviewDispositionUpdatedAt);
}

class FocusSessionsCompanion extends UpdateCompanion<FocusSession> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String?> appointmentId;
  final Value<String> taskId;
  final Value<String> mode;
  final Value<int> durationSeconds;
  final Value<DateTime> startedAt;
  final Value<DateTime> endsAt;
  final Value<String> status;
  final Value<DateTime?> completedAt;
  final Value<int> effectiveSeconds;
  final Value<String> completionType;
  final Value<String?> completionRuleText;
  final Value<DateTime?> pausedAt;
  final Value<int> pausedSeconds;
  final Value<String?> pauseRuleText;
  final Value<String?> failureReason;
  final Value<String> effectiveIntervals;
  final Value<String> reviewDisposition;
  final Value<DateTime?> reviewDispositionUpdatedAt;
  final Value<int> rowid;
  const FocusSessionsCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.appointmentId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.mode = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.status = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.effectiveSeconds = const Value.absent(),
    this.completionType = const Value.absent(),
    this.completionRuleText = const Value.absent(),
    this.pausedAt = const Value.absent(),
    this.pausedSeconds = const Value.absent(),
    this.pauseRuleText = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.effectiveIntervals = const Value.absent(),
    this.reviewDisposition = const Value.absent(),
    this.reviewDispositionUpdatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusSessionsCompanion.insert({
    required String userId,
    required String id,
    this.appointmentId = const Value.absent(),
    required String taskId,
    required String mode,
    required int durationSeconds,
    required DateTime startedAt,
    required DateTime endsAt,
    required String status,
    this.completedAt = const Value.absent(),
    this.effectiveSeconds = const Value.absent(),
    this.completionType = const Value.absent(),
    this.completionRuleText = const Value.absent(),
    this.pausedAt = const Value.absent(),
    this.pausedSeconds = const Value.absent(),
    this.pauseRuleText = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.effectiveIntervals = const Value.absent(),
    this.reviewDisposition = const Value.absent(),
    this.reviewDispositionUpdatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       taskId = Value(taskId),
       mode = Value(mode),
       durationSeconds = Value(durationSeconds),
       startedAt = Value(startedAt),
       endsAt = Value(endsAt),
       status = Value(status);
  static Insertable<FocusSession> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? appointmentId,
    Expression<String>? taskId,
    Expression<String>? mode,
    Expression<int>? durationSeconds,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endsAt,
    Expression<String>? status,
    Expression<DateTime>? completedAt,
    Expression<int>? effectiveSeconds,
    Expression<String>? completionType,
    Expression<String>? completionRuleText,
    Expression<DateTime>? pausedAt,
    Expression<int>? pausedSeconds,
    Expression<String>? pauseRuleText,
    Expression<String>? failureReason,
    Expression<String>? effectiveIntervals,
    Expression<String>? reviewDisposition,
    Expression<DateTime>? reviewDispositionUpdatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (appointmentId != null) 'appointment_id': appointmentId,
      if (taskId != null) 'task_id': taskId,
      if (mode != null) 'mode': mode,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (startedAt != null) 'started_at': startedAt,
      if (endsAt != null) 'ends_at': endsAt,
      if (status != null) 'status': status,
      if (completedAt != null) 'completed_at': completedAt,
      if (effectiveSeconds != null) 'effective_seconds': effectiveSeconds,
      if (completionType != null) 'completion_type': completionType,
      if (completionRuleText != null)
        'completion_rule_text': completionRuleText,
      if (pausedAt != null) 'paused_at': pausedAt,
      if (pausedSeconds != null) 'paused_seconds': pausedSeconds,
      if (pauseRuleText != null) 'pause_rule_text': pauseRuleText,
      if (failureReason != null) 'failure_reason': failureReason,
      if (effectiveIntervals != null) 'effective_intervals': effectiveIntervals,
      if (reviewDisposition != null) 'review_disposition': reviewDisposition,
      if (reviewDispositionUpdatedAt != null)
        'review_disposition_updated_at': reviewDispositionUpdatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusSessionsCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String?>? appointmentId,
    Value<String>? taskId,
    Value<String>? mode,
    Value<int>? durationSeconds,
    Value<DateTime>? startedAt,
    Value<DateTime>? endsAt,
    Value<String>? status,
    Value<DateTime?>? completedAt,
    Value<int>? effectiveSeconds,
    Value<String>? completionType,
    Value<String?>? completionRuleText,
    Value<DateTime?>? pausedAt,
    Value<int>? pausedSeconds,
    Value<String?>? pauseRuleText,
    Value<String?>? failureReason,
    Value<String>? effectiveIntervals,
    Value<String>? reviewDisposition,
    Value<DateTime?>? reviewDispositionUpdatedAt,
    Value<int>? rowid,
  }) {
    return FocusSessionsCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      appointmentId: appointmentId ?? this.appointmentId,
      taskId: taskId ?? this.taskId,
      mode: mode ?? this.mode,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      startedAt: startedAt ?? this.startedAt,
      endsAt: endsAt ?? this.endsAt,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      effectiveSeconds: effectiveSeconds ?? this.effectiveSeconds,
      completionType: completionType ?? this.completionType,
      completionRuleText: completionRuleText ?? this.completionRuleText,
      pausedAt: pausedAt ?? this.pausedAt,
      pausedSeconds: pausedSeconds ?? this.pausedSeconds,
      pauseRuleText: pauseRuleText ?? this.pauseRuleText,
      failureReason: failureReason ?? this.failureReason,
      effectiveIntervals: effectiveIntervals ?? this.effectiveIntervals,
      reviewDisposition: reviewDisposition ?? this.reviewDisposition,
      reviewDispositionUpdatedAt:
          reviewDispositionUpdatedAt ?? this.reviewDispositionUpdatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (appointmentId.present) {
      map['appointment_id'] = Variable<String>(appointmentId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endsAt.present) {
      map['ends_at'] = Variable<DateTime>(endsAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (effectiveSeconds.present) {
      map['effective_seconds'] = Variable<int>(effectiveSeconds.value);
    }
    if (completionType.present) {
      map['completion_type'] = Variable<String>(completionType.value);
    }
    if (completionRuleText.present) {
      map['completion_rule_text'] = Variable<String>(completionRuleText.value);
    }
    if (pausedAt.present) {
      map['paused_at'] = Variable<DateTime>(pausedAt.value);
    }
    if (pausedSeconds.present) {
      map['paused_seconds'] = Variable<int>(pausedSeconds.value);
    }
    if (pauseRuleText.present) {
      map['pause_rule_text'] = Variable<String>(pauseRuleText.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (effectiveIntervals.present) {
      map['effective_intervals'] = Variable<String>(effectiveIntervals.value);
    }
    if (reviewDisposition.present) {
      map['review_disposition'] = Variable<String>(reviewDisposition.value);
    }
    if (reviewDispositionUpdatedAt.present) {
      map['review_disposition_updated_at'] = Variable<DateTime>(
        reviewDispositionUpdatedAt.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusSessionsCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('appointmentId: $appointmentId, ')
          ..write('taskId: $taskId, ')
          ..write('mode: $mode, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('startedAt: $startedAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('status: $status, ')
          ..write('completedAt: $completedAt, ')
          ..write('effectiveSeconds: $effectiveSeconds, ')
          ..write('completionType: $completionType, ')
          ..write('completionRuleText: $completionRuleText, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('pausedSeconds: $pausedSeconds, ')
          ..write('pauseRuleText: $pauseRuleText, ')
          ..write('failureReason: $failureReason, ')
          ..write('effectiveIntervals: $effectiveIntervals, ')
          ..write('reviewDisposition: $reviewDisposition, ')
          ..write('reviewDispositionUpdatedAt: $reviewDispositionUpdatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusNodesTable extends FocusNodes
    with TableInfo<$FocusNodesTable, FocusNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _effectiveSecondsMeta = const VerificationMeta(
    'effectiveSeconds',
  );
  @override
  late final GeneratedColumn<int> effectiveSeconds = GeneratedColumn<int>(
    'effective_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    sessionId,
    taskId,
    mode,
    createdAt,
    effectiveSeconds,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusNode> instance, {
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
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('effective_seconds')) {
      context.handle(
        _effectiveSecondsMeta,
        effectiveSeconds.isAcceptableOrUnknown(
          data['effective_seconds']!,
          _effectiveSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveSecondsMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  FocusNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusNode(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      effectiveSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}effective_seconds'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $FocusNodesTable createAlias(String alias) {
    return $FocusNodesTable(attachedDatabase, alias);
  }
}

class FocusNode extends DataClass implements Insertable<FocusNode> {
  final String userId;
  final String id;
  final String sessionId;
  final String taskId;
  final String mode;
  final DateTime createdAt;
  final int effectiveSeconds;
  final String? note;
  const FocusNode({
    required this.userId,
    required this.id,
    required this.sessionId,
    required this.taskId,
    required this.mode,
    required this.createdAt,
    required this.effectiveSeconds,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['task_id'] = Variable<String>(taskId);
    map['mode'] = Variable<String>(mode);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['effective_seconds'] = Variable<int>(effectiveSeconds);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  FocusNodesCompanion toCompanion(bool nullToAbsent) {
    return FocusNodesCompanion(
      userId: Value(userId),
      id: Value(id),
      sessionId: Value(sessionId),
      taskId: Value(taskId),
      mode: Value(mode),
      createdAt: Value(createdAt),
      effectiveSeconds: Value(effectiveSeconds),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory FocusNode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusNode(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      taskId: serializer.fromJson<String>(json['taskId']),
      mode: serializer.fromJson<String>(json['mode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      effectiveSeconds: serializer.fromJson<int>(json['effectiveSeconds']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'taskId': serializer.toJson<String>(taskId),
      'mode': serializer.toJson<String>(mode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'effectiveSeconds': serializer.toJson<int>(effectiveSeconds),
      'note': serializer.toJson<String?>(note),
    };
  }

  FocusNode copyWith({
    String? userId,
    String? id,
    String? sessionId,
    String? taskId,
    String? mode,
    DateTime? createdAt,
    int? effectiveSeconds,
    Value<String?> note = const Value.absent(),
  }) => FocusNode(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    taskId: taskId ?? this.taskId,
    mode: mode ?? this.mode,
    createdAt: createdAt ?? this.createdAt,
    effectiveSeconds: effectiveSeconds ?? this.effectiveSeconds,
    note: note.present ? note.value : this.note,
  );
  FocusNode copyWithCompanion(FocusNodesCompanion data) {
    return FocusNode(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      mode: data.mode.present ? data.mode.value : this.mode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      effectiveSeconds: data.effectiveSeconds.present
          ? data.effectiveSeconds.value
          : this.effectiveSeconds,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusNode(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('taskId: $taskId, ')
          ..write('mode: $mode, ')
          ..write('createdAt: $createdAt, ')
          ..write('effectiveSeconds: $effectiveSeconds, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    sessionId,
    taskId,
    mode,
    createdAt,
    effectiveSeconds,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusNode &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.taskId == this.taskId &&
          other.mode == this.mode &&
          other.createdAt == this.createdAt &&
          other.effectiveSeconds == this.effectiveSeconds &&
          other.note == this.note);
}

class FocusNodesCompanion extends UpdateCompanion<FocusNode> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> taskId;
  final Value<String> mode;
  final Value<DateTime> createdAt;
  final Value<int> effectiveSeconds;
  final Value<String?> note;
  final Value<int> rowid;
  const FocusNodesCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.mode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.effectiveSeconds = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusNodesCompanion.insert({
    required String userId,
    required String id,
    required String sessionId,
    required String taskId,
    required String mode,
    required DateTime createdAt,
    required int effectiveSeconds,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       sessionId = Value(sessionId),
       taskId = Value(taskId),
       mode = Value(mode),
       createdAt = Value(createdAt),
       effectiveSeconds = Value(effectiveSeconds);
  static Insertable<FocusNode> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? taskId,
    Expression<String>? mode,
    Expression<DateTime>? createdAt,
    Expression<int>? effectiveSeconds,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (taskId != null) 'task_id': taskId,
      if (mode != null) 'mode': mode,
      if (createdAt != null) 'created_at': createdAt,
      if (effectiveSeconds != null) 'effective_seconds': effectiveSeconds,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusNodesCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? taskId,
    Value<String>? mode,
    Value<DateTime>? createdAt,
    Value<int>? effectiveSeconds,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return FocusNodesCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      taskId: taskId ?? this.taskId,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
      effectiveSeconds: effectiveSeconds ?? this.effectiveSeconds,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (effectiveSeconds.present) {
      map['effective_seconds'] = Variable<int>(effectiveSeconds.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusNodesCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('taskId: $taskId, ')
          ..write('mode: $mode, ')
          ..write('createdAt: $createdAt, ')
          ..write('effectiveSeconds: $effectiveSeconds, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusChainRecordsTable extends FocusChainRecords
    with TableInfo<$FocusChainRecordsTable, FocusChainRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusChainRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentConsecutiveMeta =
      const VerificationMeta('currentConsecutive');
  @override
  late final GeneratedColumn<int> currentConsecutive = GeneratedColumn<int>(
    'current_consecutive',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bestConsecutiveMeta = const VerificationMeta(
    'bestConsecutive',
  );
  @override
  late final GeneratedColumn<int> bestConsecutive = GeneratedColumn<int>(
    'best_consecutive',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  List<GeneratedColumn> get $columns => [
    userId,
    mode,
    currentConsecutive,
    bestConsecutive,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_chain_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusChainRecord> instance, {
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
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('current_consecutive')) {
      context.handle(
        _currentConsecutiveMeta,
        currentConsecutive.isAcceptableOrUnknown(
          data['current_consecutive']!,
          _currentConsecutiveMeta,
        ),
      );
    }
    if (data.containsKey('best_consecutive')) {
      context.handle(
        _bestConsecutiveMeta,
        bestConsecutive.isAcceptableOrUnknown(
          data['best_consecutive']!,
          _bestConsecutiveMeta,
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
  Set<GeneratedColumn> get $primaryKey => {userId, mode};
  @override
  FocusChainRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusChainRecord(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      currentConsecutive: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_consecutive'],
      )!,
      bestConsecutive: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}best_consecutive'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FocusChainRecordsTable createAlias(String alias) {
    return $FocusChainRecordsTable(attachedDatabase, alias);
  }
}

class FocusChainRecord extends DataClass
    implements Insertable<FocusChainRecord> {
  final String userId;
  final String mode;
  final int currentConsecutive;
  final int bestConsecutive;
  final DateTime updatedAt;
  const FocusChainRecord({
    required this.userId,
    required this.mode,
    required this.currentConsecutive,
    required this.bestConsecutive,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['mode'] = Variable<String>(mode);
    map['current_consecutive'] = Variable<int>(currentConsecutive);
    map['best_consecutive'] = Variable<int>(bestConsecutive);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FocusChainRecordsCompanion toCompanion(bool nullToAbsent) {
    return FocusChainRecordsCompanion(
      userId: Value(userId),
      mode: Value(mode),
      currentConsecutive: Value(currentConsecutive),
      bestConsecutive: Value(bestConsecutive),
      updatedAt: Value(updatedAt),
    );
  }

  factory FocusChainRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusChainRecord(
      userId: serializer.fromJson<String>(json['userId']),
      mode: serializer.fromJson<String>(json['mode']),
      currentConsecutive: serializer.fromJson<int>(json['currentConsecutive']),
      bestConsecutive: serializer.fromJson<int>(json['bestConsecutive']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'mode': serializer.toJson<String>(mode),
      'currentConsecutive': serializer.toJson<int>(currentConsecutive),
      'bestConsecutive': serializer.toJson<int>(bestConsecutive),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FocusChainRecord copyWith({
    String? userId,
    String? mode,
    int? currentConsecutive,
    int? bestConsecutive,
    DateTime? updatedAt,
  }) => FocusChainRecord(
    userId: userId ?? this.userId,
    mode: mode ?? this.mode,
    currentConsecutive: currentConsecutive ?? this.currentConsecutive,
    bestConsecutive: bestConsecutive ?? this.bestConsecutive,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FocusChainRecord copyWithCompanion(FocusChainRecordsCompanion data) {
    return FocusChainRecord(
      userId: data.userId.present ? data.userId.value : this.userId,
      mode: data.mode.present ? data.mode.value : this.mode,
      currentConsecutive: data.currentConsecutive.present
          ? data.currentConsecutive.value
          : this.currentConsecutive,
      bestConsecutive: data.bestConsecutive.present
          ? data.bestConsecutive.value
          : this.bestConsecutive,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusChainRecord(')
          ..write('userId: $userId, ')
          ..write('mode: $mode, ')
          ..write('currentConsecutive: $currentConsecutive, ')
          ..write('bestConsecutive: $bestConsecutive, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, mode, currentConsecutive, bestConsecutive, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusChainRecord &&
          other.userId == this.userId &&
          other.mode == this.mode &&
          other.currentConsecutive == this.currentConsecutive &&
          other.bestConsecutive == this.bestConsecutive &&
          other.updatedAt == this.updatedAt);
}

class FocusChainRecordsCompanion extends UpdateCompanion<FocusChainRecord> {
  final Value<String> userId;
  final Value<String> mode;
  final Value<int> currentConsecutive;
  final Value<int> bestConsecutive;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FocusChainRecordsCompanion({
    this.userId = const Value.absent(),
    this.mode = const Value.absent(),
    this.currentConsecutive = const Value.absent(),
    this.bestConsecutive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusChainRecordsCompanion.insert({
    required String userId,
    required String mode,
    this.currentConsecutive = const Value.absent(),
    this.bestConsecutive = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       mode = Value(mode),
       updatedAt = Value(updatedAt);
  static Insertable<FocusChainRecord> custom({
    Expression<String>? userId,
    Expression<String>? mode,
    Expression<int>? currentConsecutive,
    Expression<int>? bestConsecutive,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (mode != null) 'mode': mode,
      if (currentConsecutive != null) 'current_consecutive': currentConsecutive,
      if (bestConsecutive != null) 'best_consecutive': bestConsecutive,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusChainRecordsCompanion copyWith({
    Value<String>? userId,
    Value<String>? mode,
    Value<int>? currentConsecutive,
    Value<int>? bestConsecutive,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FocusChainRecordsCompanion(
      userId: userId ?? this.userId,
      mode: mode ?? this.mode,
      currentConsecutive: currentConsecutive ?? this.currentConsecutive,
      bestConsecutive: bestConsecutive ?? this.bestConsecutive,
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
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (currentConsecutive.present) {
      map['current_consecutive'] = Variable<int>(currentConsecutive.value);
    }
    if (bestConsecutive.present) {
      map['best_consecutive'] = Variable<int>(bestConsecutive.value);
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
    return (StringBuffer('FocusChainRecordsCompanion(')
          ..write('userId: $userId, ')
          ..write('mode: $mode, ')
          ..write('currentConsecutive: $currentConsecutive, ')
          ..write('bestConsecutive: $bestConsecutive, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusPreferencesTable extends FocusPreferences
    with TableInfo<$FocusPreferencesTable, FocusPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastModeMeta = const VerificationMeta(
    'lastMode',
  );
  @override
  late final GeneratedColumn<String> lastMode = GeneratedColumn<String>(
    'last_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayTimeZoneIdMeta = const VerificationMeta(
    'displayTimeZoneId',
  );
  @override
  late final GeneratedColumn<String> displayTimeZoneId =
      GeneratedColumn<String>(
        'display_time_zone_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [userId, lastMode, displayTimeZoneId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusPreference> instance, {
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
    if (data.containsKey('last_mode')) {
      context.handle(
        _lastModeMeta,
        lastMode.isAcceptableOrUnknown(data['last_mode']!, _lastModeMeta),
      );
    } else if (isInserting) {
      context.missing(_lastModeMeta);
    }
    if (data.containsKey('display_time_zone_id')) {
      context.handle(
        _displayTimeZoneIdMeta,
        displayTimeZoneId.isAcceptableOrUnknown(
          data['display_time_zone_id']!,
          _displayTimeZoneIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  FocusPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusPreference(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lastMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_mode'],
      )!,
      displayTimeZoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_time_zone_id'],
      ),
    );
  }

  @override
  $FocusPreferencesTable createAlias(String alias) {
    return $FocusPreferencesTable(attachedDatabase, alias);
  }
}

class FocusPreference extends DataClass implements Insertable<FocusPreference> {
  final String userId;
  final String lastMode;
  final String? displayTimeZoneId;
  const FocusPreference({
    required this.userId,
    required this.lastMode,
    this.displayTimeZoneId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['last_mode'] = Variable<String>(lastMode);
    if (!nullToAbsent || displayTimeZoneId != null) {
      map['display_time_zone_id'] = Variable<String>(displayTimeZoneId);
    }
    return map;
  }

  FocusPreferencesCompanion toCompanion(bool nullToAbsent) {
    return FocusPreferencesCompanion(
      userId: Value(userId),
      lastMode: Value(lastMode),
      displayTimeZoneId: displayTimeZoneId == null && nullToAbsent
          ? const Value.absent()
          : Value(displayTimeZoneId),
    );
  }

  factory FocusPreference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusPreference(
      userId: serializer.fromJson<String>(json['userId']),
      lastMode: serializer.fromJson<String>(json['lastMode']),
      displayTimeZoneId: serializer.fromJson<String?>(
        json['displayTimeZoneId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'lastMode': serializer.toJson<String>(lastMode),
      'displayTimeZoneId': serializer.toJson<String?>(displayTimeZoneId),
    };
  }

  FocusPreference copyWith({
    String? userId,
    String? lastMode,
    Value<String?> displayTimeZoneId = const Value.absent(),
  }) => FocusPreference(
    userId: userId ?? this.userId,
    lastMode: lastMode ?? this.lastMode,
    displayTimeZoneId: displayTimeZoneId.present
        ? displayTimeZoneId.value
        : this.displayTimeZoneId,
  );
  FocusPreference copyWithCompanion(FocusPreferencesCompanion data) {
    return FocusPreference(
      userId: data.userId.present ? data.userId.value : this.userId,
      lastMode: data.lastMode.present ? data.lastMode.value : this.lastMode,
      displayTimeZoneId: data.displayTimeZoneId.present
          ? data.displayTimeZoneId.value
          : this.displayTimeZoneId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusPreference(')
          ..write('userId: $userId, ')
          ..write('lastMode: $lastMode, ')
          ..write('displayTimeZoneId: $displayTimeZoneId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, lastMode, displayTimeZoneId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusPreference &&
          other.userId == this.userId &&
          other.lastMode == this.lastMode &&
          other.displayTimeZoneId == this.displayTimeZoneId);
}

class FocusPreferencesCompanion extends UpdateCompanion<FocusPreference> {
  final Value<String> userId;
  final Value<String> lastMode;
  final Value<String?> displayTimeZoneId;
  final Value<int> rowid;
  const FocusPreferencesCompanion({
    this.userId = const Value.absent(),
    this.lastMode = const Value.absent(),
    this.displayTimeZoneId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusPreferencesCompanion.insert({
    required String userId,
    required String lastMode,
    this.displayTimeZoneId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       lastMode = Value(lastMode);
  static Insertable<FocusPreference> custom({
    Expression<String>? userId,
    Expression<String>? lastMode,
    Expression<String>? displayTimeZoneId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (lastMode != null) 'last_mode': lastMode,
      if (displayTimeZoneId != null) 'display_time_zone_id': displayTimeZoneId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusPreferencesCompanion copyWith({
    Value<String>? userId,
    Value<String>? lastMode,
    Value<String?>? displayTimeZoneId,
    Value<int>? rowid,
  }) {
    return FocusPreferencesCompanion(
      userId: userId ?? this.userId,
      lastMode: lastMode ?? this.lastMode,
      displayTimeZoneId: displayTimeZoneId ?? this.displayTimeZoneId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lastMode.present) {
      map['last_mode'] = Variable<String>(lastMode.value);
    }
    if (displayTimeZoneId.present) {
      map['display_time_zone_id'] = Variable<String>(displayTimeZoneId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusPreferencesCompanion(')
          ..write('userId: $userId, ')
          ..write('lastMode: $lastMode, ')
          ..write('displayTimeZoneId: $displayTimeZoneId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusPrecedentRulesTable extends FocusPrecedentRules
    with TableInfo<$FocusPrecedentRulesTable, FocusPrecedentRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusPrecedentRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ruleTextMeta = const VerificationMeta(
    'ruleText',
  );
  @override
  late final GeneratedColumn<String> ruleText = GeneratedColumn<String>(
    'rule_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    ruleText,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_precedent_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusPrecedentRule> instance, {
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
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('rule_text')) {
      context.handle(
        _ruleTextMeta,
        ruleText.isAcceptableOrUnknown(data['rule_text']!, _ruleTextMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleTextMeta);
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
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  FocusPrecedentRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusPrecedentRule(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ruleText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_text'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $FocusPrecedentRulesTable createAlias(String alias) {
    return $FocusPrecedentRulesTable(attachedDatabase, alias);
  }
}

class FocusPrecedentRule extends DataClass
    implements Insertable<FocusPrecedentRule> {
  final String userId;
  final String id;
  final String ruleText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const FocusPrecedentRule({
    required this.userId,
    required this.id,
    required this.ruleText,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['rule_text'] = Variable<String>(ruleText);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  FocusPrecedentRulesCompanion toCompanion(bool nullToAbsent) {
    return FocusPrecedentRulesCompanion(
      userId: Value(userId),
      id: Value(id),
      ruleText: Value(ruleText),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory FocusPrecedentRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusPrecedentRule(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      ruleText: serializer.fromJson<String>(json['ruleText']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'ruleText': serializer.toJson<String>(ruleText),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  FocusPrecedentRule copyWith({
    String? userId,
    String? id,
    String? ruleText,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => FocusPrecedentRule(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    ruleText: ruleText ?? this.ruleText,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  FocusPrecedentRule copyWithCompanion(FocusPrecedentRulesCompanion data) {
    return FocusPrecedentRule(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      ruleText: data.ruleText.present ? data.ruleText.value : this.ruleText,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusPrecedentRule(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('ruleText: $ruleText, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, id, ruleText, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusPrecedentRule &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.ruleText == this.ruleText &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class FocusPrecedentRulesCompanion extends UpdateCompanion<FocusPrecedentRule> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> ruleText;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const FocusPrecedentRulesCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.ruleText = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusPrecedentRulesCompanion.insert({
    required String userId,
    required String id,
    required String ruleText,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       ruleText = Value(ruleText),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<FocusPrecedentRule> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? ruleText,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (ruleText != null) 'rule_text': ruleText,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusPrecedentRulesCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? ruleText,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return FocusPrecedentRulesCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      ruleText: ruleText ?? this.ruleText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ruleText.present) {
      map['rule_text'] = Variable<String>(ruleText.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusPrecedentRulesCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('ruleText: $ruleText, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusAppointmentsTable extends FocusAppointments
    with TableInfo<$FocusAppointmentsTable, FocusAppointment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusAppointmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMeta = const VerificationMeta('endsAt');
  @override
  late final GeneratedColumn<DateTime> endsAt = GeneratedColumn<DateTime>(
    'ends_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _settledAtMeta = const VerificationMeta(
    'settledAt',
  );
  @override
  late final GeneratedColumn<DateTime> settledAt = GeneratedColumn<DateTime>(
    'settled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
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
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    taskId,
    mode,
    durationSeconds,
    startedAt,
    endsAt,
    status,
    settledAt,
    sessionId,
    failureReason,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_appointments';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusAppointment> instance, {
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
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ends_at')) {
      context.handle(
        _endsAtMeta,
        endsAt.isAcceptableOrUnknown(data['ends_at']!, _endsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('settled_at')) {
      context.handle(
        _settledAtMeta,
        settledAt.isAcceptableOrUnknown(data['settled_at']!, _settledAtMeta),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
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
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  FocusAppointment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusAppointment(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ends_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      settledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}settled_at'],
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FocusAppointmentsTable createAlias(String alias) {
    return $FocusAppointmentsTable(attachedDatabase, alias);
  }
}

class FocusAppointment extends DataClass
    implements Insertable<FocusAppointment> {
  final String userId;
  final String id;
  final String taskId;
  final String mode;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime endsAt;
  final String status;
  final DateTime? settledAt;
  final String? sessionId;
  final String? failureReason;
  final DateTime updatedAt;
  const FocusAppointment({
    required this.userId,
    required this.id,
    required this.taskId,
    required this.mode,
    required this.durationSeconds,
    required this.startedAt,
    required this.endsAt,
    required this.status,
    this.settledAt,
    this.sessionId,
    this.failureReason,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['mode'] = Variable<String>(mode);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['ends_at'] = Variable<DateTime>(endsAt);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || settledAt != null) {
      map['settled_at'] = Variable<DateTime>(settledAt);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FocusAppointmentsCompanion toCompanion(bool nullToAbsent) {
    return FocusAppointmentsCompanion(
      userId: Value(userId),
      id: Value(id),
      taskId: Value(taskId),
      mode: Value(mode),
      durationSeconds: Value(durationSeconds),
      startedAt: Value(startedAt),
      endsAt: Value(endsAt),
      status: Value(status),
      settledAt: settledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(settledAt),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      updatedAt: Value(updatedAt),
    );
  }

  factory FocusAppointment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusAppointment(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      mode: serializer.fromJson<String>(json['mode']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endsAt: serializer.fromJson<DateTime>(json['endsAt']),
      status: serializer.fromJson<String>(json['status']),
      settledAt: serializer.fromJson<DateTime?>(json['settledAt']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'mode': serializer.toJson<String>(mode),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endsAt': serializer.toJson<DateTime>(endsAt),
      'status': serializer.toJson<String>(status),
      'settledAt': serializer.toJson<DateTime?>(settledAt),
      'sessionId': serializer.toJson<String?>(sessionId),
      'failureReason': serializer.toJson<String?>(failureReason),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FocusAppointment copyWith({
    String? userId,
    String? id,
    String? taskId,
    String? mode,
    int? durationSeconds,
    DateTime? startedAt,
    DateTime? endsAt,
    String? status,
    Value<DateTime?> settledAt = const Value.absent(),
    Value<String?> sessionId = const Value.absent(),
    Value<String?> failureReason = const Value.absent(),
    DateTime? updatedAt,
  }) => FocusAppointment(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    mode: mode ?? this.mode,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    startedAt: startedAt ?? this.startedAt,
    endsAt: endsAt ?? this.endsAt,
    status: status ?? this.status,
    settledAt: settledAt.present ? settledAt.value : this.settledAt,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FocusAppointment copyWithCompanion(FocusAppointmentsCompanion data) {
    return FocusAppointment(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      mode: data.mode.present ? data.mode.value : this.mode,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endsAt: data.endsAt.present ? data.endsAt.value : this.endsAt,
      status: data.status.present ? data.status.value : this.status,
      settledAt: data.settledAt.present ? data.settledAt.value : this.settledAt,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusAppointment(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('mode: $mode, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('startedAt: $startedAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('status: $status, ')
          ..write('settledAt: $settledAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('failureReason: $failureReason, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    taskId,
    mode,
    durationSeconds,
    startedAt,
    endsAt,
    status,
    settledAt,
    sessionId,
    failureReason,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusAppointment &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.mode == this.mode &&
          other.durationSeconds == this.durationSeconds &&
          other.startedAt == this.startedAt &&
          other.endsAt == this.endsAt &&
          other.status == this.status &&
          other.settledAt == this.settledAt &&
          other.sessionId == this.sessionId &&
          other.failureReason == this.failureReason &&
          other.updatedAt == this.updatedAt);
}

class FocusAppointmentsCompanion extends UpdateCompanion<FocusAppointment> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> mode;
  final Value<int> durationSeconds;
  final Value<DateTime> startedAt;
  final Value<DateTime> endsAt;
  final Value<String> status;
  final Value<DateTime?> settledAt;
  final Value<String?> sessionId;
  final Value<String?> failureReason;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FocusAppointmentsCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.mode = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.status = const Value.absent(),
    this.settledAt = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusAppointmentsCompanion.insert({
    required String userId,
    required String id,
    required String taskId,
    required String mode,
    required int durationSeconds,
    required DateTime startedAt,
    required DateTime endsAt,
    required String status,
    this.settledAt = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.failureReason = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       taskId = Value(taskId),
       mode = Value(mode),
       durationSeconds = Value(durationSeconds),
       startedAt = Value(startedAt),
       endsAt = Value(endsAt),
       status = Value(status),
       updatedAt = Value(updatedAt);
  static Insertable<FocusAppointment> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? mode,
    Expression<int>? durationSeconds,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endsAt,
    Expression<String>? status,
    Expression<DateTime>? settledAt,
    Expression<String>? sessionId,
    Expression<String>? failureReason,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (mode != null) 'mode': mode,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (startedAt != null) 'started_at': startedAt,
      if (endsAt != null) 'ends_at': endsAt,
      if (status != null) 'status': status,
      if (settledAt != null) 'settled_at': settledAt,
      if (sessionId != null) 'session_id': sessionId,
      if (failureReason != null) 'failure_reason': failureReason,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusAppointmentsCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? mode,
    Value<int>? durationSeconds,
    Value<DateTime>? startedAt,
    Value<DateTime>? endsAt,
    Value<String>? status,
    Value<DateTime?>? settledAt,
    Value<String?>? sessionId,
    Value<String?>? failureReason,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FocusAppointmentsCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      mode: mode ?? this.mode,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      startedAt: startedAt ?? this.startedAt,
      endsAt: endsAt ?? this.endsAt,
      status: status ?? this.status,
      settledAt: settledAt ?? this.settledAt,
      sessionId: sessionId ?? this.sessionId,
      failureReason: failureReason ?? this.failureReason,
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
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endsAt.present) {
      map['ends_at'] = Variable<DateTime>(endsAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (settledAt.present) {
      map['settled_at'] = Variable<DateTime>(settledAt.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
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
    return (StringBuffer('FocusAppointmentsCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('mode: $mode, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('startedAt: $startedAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('status: $status, ')
          ..write('settledAt: $settledAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('failureReason: $failureReason, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppointmentChainRecordsTable extends AppointmentChainRecords
    with TableInfo<$AppointmentChainRecordsTable, AppointmentChainRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppointmentChainRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentConsecutiveMeta =
      const VerificationMeta('currentConsecutive');
  @override
  late final GeneratedColumn<int> currentConsecutive = GeneratedColumn<int>(
    'current_consecutive',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bestConsecutiveMeta = const VerificationMeta(
    'bestConsecutive',
  );
  @override
  late final GeneratedColumn<int> bestConsecutive = GeneratedColumn<int>(
    'best_consecutive',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  List<GeneratedColumn> get $columns => [
    userId,
    currentConsecutive,
    bestConsecutive,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'appointment_chain_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppointmentChainRecord> instance, {
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
    if (data.containsKey('current_consecutive')) {
      context.handle(
        _currentConsecutiveMeta,
        currentConsecutive.isAcceptableOrUnknown(
          data['current_consecutive']!,
          _currentConsecutiveMeta,
        ),
      );
    }
    if (data.containsKey('best_consecutive')) {
      context.handle(
        _bestConsecutiveMeta,
        bestConsecutive.isAcceptableOrUnknown(
          data['best_consecutive']!,
          _bestConsecutiveMeta,
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
  AppointmentChainRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppointmentChainRecord(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      currentConsecutive: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_consecutive'],
      )!,
      bestConsecutive: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}best_consecutive'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppointmentChainRecordsTable createAlias(String alias) {
    return $AppointmentChainRecordsTable(attachedDatabase, alias);
  }
}

class AppointmentChainRecord extends DataClass
    implements Insertable<AppointmentChainRecord> {
  final String userId;
  final int currentConsecutive;
  final int bestConsecutive;
  final DateTime updatedAt;
  const AppointmentChainRecord({
    required this.userId,
    required this.currentConsecutive,
    required this.bestConsecutive,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['current_consecutive'] = Variable<int>(currentConsecutive);
    map['best_consecutive'] = Variable<int>(bestConsecutive);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppointmentChainRecordsCompanion toCompanion(bool nullToAbsent) {
    return AppointmentChainRecordsCompanion(
      userId: Value(userId),
      currentConsecutive: Value(currentConsecutive),
      bestConsecutive: Value(bestConsecutive),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppointmentChainRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppointmentChainRecord(
      userId: serializer.fromJson<String>(json['userId']),
      currentConsecutive: serializer.fromJson<int>(json['currentConsecutive']),
      bestConsecutive: serializer.fromJson<int>(json['bestConsecutive']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'currentConsecutive': serializer.toJson<int>(currentConsecutive),
      'bestConsecutive': serializer.toJson<int>(bestConsecutive),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppointmentChainRecord copyWith({
    String? userId,
    int? currentConsecutive,
    int? bestConsecutive,
    DateTime? updatedAt,
  }) => AppointmentChainRecord(
    userId: userId ?? this.userId,
    currentConsecutive: currentConsecutive ?? this.currentConsecutive,
    bestConsecutive: bestConsecutive ?? this.bestConsecutive,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppointmentChainRecord copyWithCompanion(
    AppointmentChainRecordsCompanion data,
  ) {
    return AppointmentChainRecord(
      userId: data.userId.present ? data.userId.value : this.userId,
      currentConsecutive: data.currentConsecutive.present
          ? data.currentConsecutive.value
          : this.currentConsecutive,
      bestConsecutive: data.bestConsecutive.present
          ? data.bestConsecutive.value
          : this.bestConsecutive,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppointmentChainRecord(')
          ..write('userId: $userId, ')
          ..write('currentConsecutive: $currentConsecutive, ')
          ..write('bestConsecutive: $bestConsecutive, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, currentConsecutive, bestConsecutive, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppointmentChainRecord &&
          other.userId == this.userId &&
          other.currentConsecutive == this.currentConsecutive &&
          other.bestConsecutive == this.bestConsecutive &&
          other.updatedAt == this.updatedAt);
}

class AppointmentChainRecordsCompanion
    extends UpdateCompanion<AppointmentChainRecord> {
  final Value<String> userId;
  final Value<int> currentConsecutive;
  final Value<int> bestConsecutive;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppointmentChainRecordsCompanion({
    this.userId = const Value.absent(),
    this.currentConsecutive = const Value.absent(),
    this.bestConsecutive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppointmentChainRecordsCompanion.insert({
    required String userId,
    this.currentConsecutive = const Value.absent(),
    this.bestConsecutive = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       updatedAt = Value(updatedAt);
  static Insertable<AppointmentChainRecord> custom({
    Expression<String>? userId,
    Expression<int>? currentConsecutive,
    Expression<int>? bestConsecutive,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (currentConsecutive != null) 'current_consecutive': currentConsecutive,
      if (bestConsecutive != null) 'best_consecutive': bestConsecutive,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppointmentChainRecordsCompanion copyWith({
    Value<String>? userId,
    Value<int>? currentConsecutive,
    Value<int>? bestConsecutive,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppointmentChainRecordsCompanion(
      userId: userId ?? this.userId,
      currentConsecutive: currentConsecutive ?? this.currentConsecutive,
      bestConsecutive: bestConsecutive ?? this.bestConsecutive,
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
    if (currentConsecutive.present) {
      map['current_consecutive'] = Variable<int>(currentConsecutive.value);
    }
    if (bestConsecutive.present) {
      map['best_consecutive'] = Variable<int>(bestConsecutive.value);
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
    return (StringBuffer('AppointmentChainRecordsCompanion(')
          ..write('userId: $userId, ')
          ..write('currentConsecutive: $currentConsecutive, ')
          ..write('bestConsecutive: $bestConsecutive, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$PactaDatabase extends GeneratedDatabase {
  _$PactaDatabase(QueryExecutor e) : super(e);
  $PactaDatabaseManager get managers => $PactaDatabaseManager(this);
  late final $LocalGoalsTable localGoals = $LocalGoalsTable(this);
  late final $LocalTasksTable localTasks = $LocalTasksTable(this);
  late final $TaskSyncEntriesTable taskSyncEntries = $TaskSyncEntriesTable(
    this,
  );
  late final $FocusSessionsTable focusSessions = $FocusSessionsTable(this);
  late final $FocusNodesTable focusNodes = $FocusNodesTable(this);
  late final $FocusChainRecordsTable focusChainRecords =
      $FocusChainRecordsTable(this);
  late final $FocusPreferencesTable focusPreferences = $FocusPreferencesTable(
    this,
  );
  late final $FocusPrecedentRulesTable focusPrecedentRules =
      $FocusPrecedentRulesTable(this);
  late final $FocusAppointmentsTable focusAppointments =
      $FocusAppointmentsTable(this);
  late final $AppointmentChainRecordsTable appointmentChainRecords =
      $AppointmentChainRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localGoals,
    localTasks,
    taskSyncEntries,
    focusSessions,
    focusNodes,
    focusChainRecords,
    focusPreferences,
    focusPrecedentRules,
    focusAppointments,
    appointmentChainRecords,
  ];
}

typedef $$LocalGoalsTableCreateCompanionBuilder =
    LocalGoalsCompanion Function({
      required String userId,
      required String id,
      required String title,
      required String classification,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalGoalsTableUpdateCompanionBuilder =
    LocalGoalsCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> title,
      Value<String> classification,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalGoalsTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalGoalsTable> {
  $$LocalGoalsTableFilterComposer({
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

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classification => $composableBuilder(
    column: $table.classification,
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

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalGoalsTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalGoalsTable> {
  $$LocalGoalsTableOrderingComposer({
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

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classification => $composableBuilder(
    column: $table.classification,
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

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalGoalsTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalGoalsTable> {
  $$LocalGoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalGoalsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalGoalsTable,
          LocalGoal,
          $$LocalGoalsTableFilterComposer,
          $$LocalGoalsTableOrderingComposer,
          $$LocalGoalsTableAnnotationComposer,
          $$LocalGoalsTableCreateCompanionBuilder,
          $$LocalGoalsTableUpdateCompanionBuilder,
          (
            LocalGoal,
            BaseReferences<_$PactaDatabase, $LocalGoalsTable, LocalGoal>,
          ),
          LocalGoal,
          PrefetchHooks Function()
        > {
  $$LocalGoalsTableTableManager(_$PactaDatabase db, $LocalGoalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalGoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalGoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalGoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> classification = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalGoalsCompanion(
                userId: userId,
                id: id,
                title: title,
                classification: classification,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String title,
                required String classification,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalGoalsCompanion.insert(
                userId: userId,
                id: id,
                title: title,
                classification: classification,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalGoalsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalGoalsTable,
      LocalGoal,
      $$LocalGoalsTableFilterComposer,
      $$LocalGoalsTableOrderingComposer,
      $$LocalGoalsTableAnnotationComposer,
      $$LocalGoalsTableCreateCompanionBuilder,
      $$LocalGoalsTableUpdateCompanionBuilder,
      (LocalGoal, BaseReferences<_$PactaDatabase, $LocalGoalsTable, LocalGoal>),
      LocalGoal,
      PrefetchHooks Function()
    >;
typedef $$LocalTasksTableCreateCompanionBuilder =
    LocalTasksCompanion Function({
      required String userId,
      required String id,
      required String goalId,
      required String title,
      required String classification,
      Value<int?> estimatedMinutes,
      Value<DateTime?> deadline,
      Value<bool> isComplete,
      Value<int> focusProgressSeconds,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalTasksTableUpdateCompanionBuilder =
    LocalTasksCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> goalId,
      Value<String> title,
      Value<String> classification,
      Value<int?> estimatedMinutes,
      Value<DateTime?> deadline,
      Value<bool> isComplete,
      Value<int> focusProgressSeconds,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalTasksTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalTasksTable> {
  $$LocalTasksTableFilterComposer({
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

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
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

  ColumnFilters<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get focusProgressSeconds => $composableBuilder(
    column: $table.focusProgressSeconds,
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

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTasksTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalTasksTable> {
  $$LocalTasksTableOrderingComposer({
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

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
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

  ColumnOrderings<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get focusProgressSeconds => $composableBuilder(
    column: $table.focusProgressSeconds,
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

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTasksTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalTasksTable> {
  $$LocalTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get goalId =>
      $composableBuilder(column: $table.goalId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deadline =>
      $composableBuilder(column: $table.deadline, builder: (column) => column);

  GeneratedColumn<bool> get isComplete => $composableBuilder(
    column: $table.isComplete,
    builder: (column) => column,
  );

  GeneratedColumn<int> get focusProgressSeconds => $composableBuilder(
    column: $table.focusProgressSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalTasksTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalTasksTable,
          LocalTask,
          $$LocalTasksTableFilterComposer,
          $$LocalTasksTableOrderingComposer,
          $$LocalTasksTableAnnotationComposer,
          $$LocalTasksTableCreateCompanionBuilder,
          $$LocalTasksTableUpdateCompanionBuilder,
          (
            LocalTask,
            BaseReferences<_$PactaDatabase, $LocalTasksTable, LocalTask>,
          ),
          LocalTask,
          PrefetchHooks Function()
        > {
  $$LocalTasksTableTableManager(_$PactaDatabase db, $LocalTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> goalId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> classification = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<DateTime?> deadline = const Value.absent(),
                Value<bool> isComplete = const Value.absent(),
                Value<int> focusProgressSeconds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion(
                userId: userId,
                id: id,
                goalId: goalId,
                title: title,
                classification: classification,
                estimatedMinutes: estimatedMinutes,
                deadline: deadline,
                isComplete: isComplete,
                focusProgressSeconds: focusProgressSeconds,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String goalId,
                required String title,
                required String classification,
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<DateTime?> deadline = const Value.absent(),
                Value<bool> isComplete = const Value.absent(),
                Value<int> focusProgressSeconds = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion.insert(
                userId: userId,
                id: id,
                goalId: goalId,
                title: title,
                classification: classification,
                estimatedMinutes: estimatedMinutes,
                deadline: deadline,
                isComplete: isComplete,
                focusProgressSeconds: focusProgressSeconds,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalTasksTable,
      LocalTask,
      $$LocalTasksTableFilterComposer,
      $$LocalTasksTableOrderingComposer,
      $$LocalTasksTableAnnotationComposer,
      $$LocalTasksTableCreateCompanionBuilder,
      $$LocalTasksTableUpdateCompanionBuilder,
      (LocalTask, BaseReferences<_$PactaDatabase, $LocalTasksTable, LocalTask>),
      LocalTask,
      PrefetchHooks Function()
    >;
typedef $$TaskSyncEntriesTableCreateCompanionBuilder =
    TaskSyncEntriesCompanion Function({
      required String userId,
      required String entityType,
      required String entityId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TaskSyncEntriesTableUpdateCompanionBuilder =
    TaskSyncEntriesCompanion Function({
      Value<String> userId,
      Value<String> entityType,
      Value<String> entityId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$TaskSyncEntriesTableFilterComposer
    extends Composer<_$PactaDatabase, $TaskSyncEntriesTable> {
  $$TaskSyncEntriesTableFilterComposer({
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

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskSyncEntriesTableOrderingComposer
    extends Composer<_$PactaDatabase, $TaskSyncEntriesTable> {
  $$TaskSyncEntriesTableOrderingComposer({
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

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskSyncEntriesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $TaskSyncEntriesTable> {
  $$TaskSyncEntriesTableAnnotationComposer({
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

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TaskSyncEntriesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $TaskSyncEntriesTable,
          TaskSyncEntry,
          $$TaskSyncEntriesTableFilterComposer,
          $$TaskSyncEntriesTableOrderingComposer,
          $$TaskSyncEntriesTableAnnotationComposer,
          $$TaskSyncEntriesTableCreateCompanionBuilder,
          $$TaskSyncEntriesTableUpdateCompanionBuilder,
          (
            TaskSyncEntry,
            BaseReferences<
              _$PactaDatabase,
              $TaskSyncEntriesTable,
              TaskSyncEntry
            >,
          ),
          TaskSyncEntry,
          PrefetchHooks Function()
        > {
  $$TaskSyncEntriesTableTableManager(
    _$PactaDatabase db,
    $TaskSyncEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskSyncEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskSyncEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskSyncEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskSyncEntriesCompanion(
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String entityType,
                required String entityId,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TaskSyncEntriesCompanion.insert(
                userId: userId,
                entityType: entityType,
                entityId: entityId,
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

typedef $$TaskSyncEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $TaskSyncEntriesTable,
      TaskSyncEntry,
      $$TaskSyncEntriesTableFilterComposer,
      $$TaskSyncEntriesTableOrderingComposer,
      $$TaskSyncEntriesTableAnnotationComposer,
      $$TaskSyncEntriesTableCreateCompanionBuilder,
      $$TaskSyncEntriesTableUpdateCompanionBuilder,
      (
        TaskSyncEntry,
        BaseReferences<_$PactaDatabase, $TaskSyncEntriesTable, TaskSyncEntry>,
      ),
      TaskSyncEntry,
      PrefetchHooks Function()
    >;
typedef $$FocusSessionsTableCreateCompanionBuilder =
    FocusSessionsCompanion Function({
      required String userId,
      required String id,
      Value<String?> appointmentId,
      required String taskId,
      required String mode,
      required int durationSeconds,
      required DateTime startedAt,
      required DateTime endsAt,
      required String status,
      Value<DateTime?> completedAt,
      Value<int> effectiveSeconds,
      Value<String> completionType,
      Value<String?> completionRuleText,
      Value<DateTime?> pausedAt,
      Value<int> pausedSeconds,
      Value<String?> pauseRuleText,
      Value<String?> failureReason,
      Value<String> effectiveIntervals,
      Value<String> reviewDisposition,
      Value<DateTime?> reviewDispositionUpdatedAt,
      Value<int> rowid,
    });
typedef $$FocusSessionsTableUpdateCompanionBuilder =
    FocusSessionsCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String?> appointmentId,
      Value<String> taskId,
      Value<String> mode,
      Value<int> durationSeconds,
      Value<DateTime> startedAt,
      Value<DateTime> endsAt,
      Value<String> status,
      Value<DateTime?> completedAt,
      Value<int> effectiveSeconds,
      Value<String> completionType,
      Value<String?> completionRuleText,
      Value<DateTime?> pausedAt,
      Value<int> pausedSeconds,
      Value<String?> pauseRuleText,
      Value<String?> failureReason,
      Value<String> effectiveIntervals,
      Value<String> reviewDisposition,
      Value<DateTime?> reviewDispositionUpdatedAt,
      Value<int> rowid,
    });

class $$FocusSessionsTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableFilterComposer({
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

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appointmentId => $composableBuilder(
    column: $table.appointmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get completionType => $composableBuilder(
    column: $table.completionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get completionRuleText => $composableBuilder(
    column: $table.completionRuleText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pausedAt => $composableBuilder(
    column: $table.pausedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pausedSeconds => $composableBuilder(
    column: $table.pausedSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pauseRuleText => $composableBuilder(
    column: $table.pauseRuleText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveIntervals => $composableBuilder(
    column: $table.effectiveIntervals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reviewDispositionUpdatedAt => $composableBuilder(
    column: $table.reviewDispositionUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusSessionsTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableOrderingComposer({
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

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appointmentId => $composableBuilder(
    column: $table.appointmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get completionType => $composableBuilder(
    column: $table.completionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get completionRuleText => $composableBuilder(
    column: $table.completionRuleText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pausedAt => $composableBuilder(
    column: $table.pausedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pausedSeconds => $composableBuilder(
    column: $table.pausedSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pauseRuleText => $composableBuilder(
    column: $table.pauseRuleText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveIntervals => $composableBuilder(
    column: $table.effectiveIntervals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reviewDispositionUpdatedAt =>
      $composableBuilder(
        column: $table.reviewDispositionUpdatedAt,
        builder: (column) => ColumnOrderings(column),
      );
}

class $$FocusSessionsTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get appointmentId => $composableBuilder(
    column: $table.appointmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endsAt =>
      $composableBuilder(column: $table.endsAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get completionType => $composableBuilder(
    column: $table.completionType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get completionRuleText => $composableBuilder(
    column: $table.completionRuleText,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get pausedAt =>
      $composableBuilder(column: $table.pausedAt, builder: (column) => column);

  GeneratedColumn<int> get pausedSeconds => $composableBuilder(
    column: $table.pausedSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pauseRuleText => $composableBuilder(
    column: $table.pauseRuleText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveIntervals => $composableBuilder(
    column: $table.effectiveIntervals,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get reviewDispositionUpdatedAt =>
      $composableBuilder(
        column: $table.reviewDispositionUpdatedAt,
        builder: (column) => column,
      );
}

class $$FocusSessionsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusSessionsTable,
          FocusSession,
          $$FocusSessionsTableFilterComposer,
          $$FocusSessionsTableOrderingComposer,
          $$FocusSessionsTableAnnotationComposer,
          $$FocusSessionsTableCreateCompanionBuilder,
          $$FocusSessionsTableUpdateCompanionBuilder,
          (
            FocusSession,
            BaseReferences<_$PactaDatabase, $FocusSessionsTable, FocusSession>,
          ),
          FocusSession,
          PrefetchHooks Function()
        > {
  $$FocusSessionsTableTableManager(
    _$PactaDatabase db,
    $FocusSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> appointmentId = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime> endsAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> effectiveSeconds = const Value.absent(),
                Value<String> completionType = const Value.absent(),
                Value<String?> completionRuleText = const Value.absent(),
                Value<DateTime?> pausedAt = const Value.absent(),
                Value<int> pausedSeconds = const Value.absent(),
                Value<String?> pauseRuleText = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String> effectiveIntervals = const Value.absent(),
                Value<String> reviewDisposition = const Value.absent(),
                Value<DateTime?> reviewDispositionUpdatedAt =
                    const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusSessionsCompanion(
                userId: userId,
                id: id,
                appointmentId: appointmentId,
                taskId: taskId,
                mode: mode,
                durationSeconds: durationSeconds,
                startedAt: startedAt,
                endsAt: endsAt,
                status: status,
                completedAt: completedAt,
                effectiveSeconds: effectiveSeconds,
                completionType: completionType,
                completionRuleText: completionRuleText,
                pausedAt: pausedAt,
                pausedSeconds: pausedSeconds,
                pauseRuleText: pauseRuleText,
                failureReason: failureReason,
                effectiveIntervals: effectiveIntervals,
                reviewDisposition: reviewDisposition,
                reviewDispositionUpdatedAt: reviewDispositionUpdatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                Value<String?> appointmentId = const Value.absent(),
                required String taskId,
                required String mode,
                required int durationSeconds,
                required DateTime startedAt,
                required DateTime endsAt,
                required String status,
                Value<DateTime?> completedAt = const Value.absent(),
                Value<int> effectiveSeconds = const Value.absent(),
                Value<String> completionType = const Value.absent(),
                Value<String?> completionRuleText = const Value.absent(),
                Value<DateTime?> pausedAt = const Value.absent(),
                Value<int> pausedSeconds = const Value.absent(),
                Value<String?> pauseRuleText = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String> effectiveIntervals = const Value.absent(),
                Value<String> reviewDisposition = const Value.absent(),
                Value<DateTime?> reviewDispositionUpdatedAt =
                    const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusSessionsCompanion.insert(
                userId: userId,
                id: id,
                appointmentId: appointmentId,
                taskId: taskId,
                mode: mode,
                durationSeconds: durationSeconds,
                startedAt: startedAt,
                endsAt: endsAt,
                status: status,
                completedAt: completedAt,
                effectiveSeconds: effectiveSeconds,
                completionType: completionType,
                completionRuleText: completionRuleText,
                pausedAt: pausedAt,
                pausedSeconds: pausedSeconds,
                pauseRuleText: pauseRuleText,
                failureReason: failureReason,
                effectiveIntervals: effectiveIntervals,
                reviewDisposition: reviewDisposition,
                reviewDispositionUpdatedAt: reviewDispositionUpdatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FocusSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusSessionsTable,
      FocusSession,
      $$FocusSessionsTableFilterComposer,
      $$FocusSessionsTableOrderingComposer,
      $$FocusSessionsTableAnnotationComposer,
      $$FocusSessionsTableCreateCompanionBuilder,
      $$FocusSessionsTableUpdateCompanionBuilder,
      (
        FocusSession,
        BaseReferences<_$PactaDatabase, $FocusSessionsTable, FocusSession>,
      ),
      FocusSession,
      PrefetchHooks Function()
    >;
typedef $$FocusNodesTableCreateCompanionBuilder =
    FocusNodesCompanion Function({
      required String userId,
      required String id,
      required String sessionId,
      required String taskId,
      required String mode,
      required DateTime createdAt,
      required int effectiveSeconds,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$FocusNodesTableUpdateCompanionBuilder =
    FocusNodesCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> sessionId,
      Value<String> taskId,
      Value<String> mode,
      Value<DateTime> createdAt,
      Value<int> effectiveSeconds,
      Value<String?> note,
      Value<int> rowid,
    });

class $$FocusNodesTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusNodesTable> {
  $$FocusNodesTableFilterComposer({
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

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusNodesTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusNodesTable> {
  $$FocusNodesTableOrderingComposer({
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

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusNodesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusNodesTable> {
  $$FocusNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get effectiveSeconds => $composableBuilder(
    column: $table.effectiveSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$FocusNodesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusNodesTable,
          FocusNode,
          $$FocusNodesTableFilterComposer,
          $$FocusNodesTableOrderingComposer,
          $$FocusNodesTableAnnotationComposer,
          $$FocusNodesTableCreateCompanionBuilder,
          $$FocusNodesTableUpdateCompanionBuilder,
          (
            FocusNode,
            BaseReferences<_$PactaDatabase, $FocusNodesTable, FocusNode>,
          ),
          FocusNode,
          PrefetchHooks Function()
        > {
  $$FocusNodesTableTableManager(_$PactaDatabase db, $FocusNodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> effectiveSeconds = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusNodesCompanion(
                userId: userId,
                id: id,
                sessionId: sessionId,
                taskId: taskId,
                mode: mode,
                createdAt: createdAt,
                effectiveSeconds: effectiveSeconds,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String sessionId,
                required String taskId,
                required String mode,
                required DateTime createdAt,
                required int effectiveSeconds,
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusNodesCompanion.insert(
                userId: userId,
                id: id,
                sessionId: sessionId,
                taskId: taskId,
                mode: mode,
                createdAt: createdAt,
                effectiveSeconds: effectiveSeconds,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FocusNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusNodesTable,
      FocusNode,
      $$FocusNodesTableFilterComposer,
      $$FocusNodesTableOrderingComposer,
      $$FocusNodesTableAnnotationComposer,
      $$FocusNodesTableCreateCompanionBuilder,
      $$FocusNodesTableUpdateCompanionBuilder,
      (FocusNode, BaseReferences<_$PactaDatabase, $FocusNodesTable, FocusNode>),
      FocusNode,
      PrefetchHooks Function()
    >;
typedef $$FocusChainRecordsTableCreateCompanionBuilder =
    FocusChainRecordsCompanion Function({
      required String userId,
      required String mode,
      Value<int> currentConsecutive,
      Value<int> bestConsecutive,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$FocusChainRecordsTableUpdateCompanionBuilder =
    FocusChainRecordsCompanion Function({
      Value<String> userId,
      Value<String> mode,
      Value<int> currentConsecutive,
      Value<int> bestConsecutive,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$FocusChainRecordsTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusChainRecordsTable> {
  $$FocusChainRecordsTableFilterComposer({
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

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentConsecutive => $composableBuilder(
    column: $table.currentConsecutive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bestConsecutive => $composableBuilder(
    column: $table.bestConsecutive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusChainRecordsTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusChainRecordsTable> {
  $$FocusChainRecordsTableOrderingComposer({
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

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentConsecutive => $composableBuilder(
    column: $table.currentConsecutive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bestConsecutive => $composableBuilder(
    column: $table.bestConsecutive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusChainRecordsTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusChainRecordsTable> {
  $$FocusChainRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get currentConsecutive => $composableBuilder(
    column: $table.currentConsecutive,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bestConsecutive => $composableBuilder(
    column: $table.bestConsecutive,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FocusChainRecordsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusChainRecordsTable,
          FocusChainRecord,
          $$FocusChainRecordsTableFilterComposer,
          $$FocusChainRecordsTableOrderingComposer,
          $$FocusChainRecordsTableAnnotationComposer,
          $$FocusChainRecordsTableCreateCompanionBuilder,
          $$FocusChainRecordsTableUpdateCompanionBuilder,
          (
            FocusChainRecord,
            BaseReferences<
              _$PactaDatabase,
              $FocusChainRecordsTable,
              FocusChainRecord
            >,
          ),
          FocusChainRecord,
          PrefetchHooks Function()
        > {
  $$FocusChainRecordsTableTableManager(
    _$PactaDatabase db,
    $FocusChainRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusChainRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusChainRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusChainRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> currentConsecutive = const Value.absent(),
                Value<int> bestConsecutive = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusChainRecordsCompanion(
                userId: userId,
                mode: mode,
                currentConsecutive: currentConsecutive,
                bestConsecutive: bestConsecutive,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String mode,
                Value<int> currentConsecutive = const Value.absent(),
                Value<int> bestConsecutive = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FocusChainRecordsCompanion.insert(
                userId: userId,
                mode: mode,
                currentConsecutive: currentConsecutive,
                bestConsecutive: bestConsecutive,
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

typedef $$FocusChainRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusChainRecordsTable,
      FocusChainRecord,
      $$FocusChainRecordsTableFilterComposer,
      $$FocusChainRecordsTableOrderingComposer,
      $$FocusChainRecordsTableAnnotationComposer,
      $$FocusChainRecordsTableCreateCompanionBuilder,
      $$FocusChainRecordsTableUpdateCompanionBuilder,
      (
        FocusChainRecord,
        BaseReferences<
          _$PactaDatabase,
          $FocusChainRecordsTable,
          FocusChainRecord
        >,
      ),
      FocusChainRecord,
      PrefetchHooks Function()
    >;
typedef $$FocusPreferencesTableCreateCompanionBuilder =
    FocusPreferencesCompanion Function({
      required String userId,
      required String lastMode,
      Value<String?> displayTimeZoneId,
      Value<int> rowid,
    });
typedef $$FocusPreferencesTableUpdateCompanionBuilder =
    FocusPreferencesCompanion Function({
      Value<String> userId,
      Value<String> lastMode,
      Value<String?> displayTimeZoneId,
      Value<int> rowid,
    });

class $$FocusPreferencesTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusPreferencesTable> {
  $$FocusPreferencesTableFilterComposer({
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

  ColumnFilters<String> get lastMode => $composableBuilder(
    column: $table.lastMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayTimeZoneId => $composableBuilder(
    column: $table.displayTimeZoneId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusPreferencesTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusPreferencesTable> {
  $$FocusPreferencesTableOrderingComposer({
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

  ColumnOrderings<String> get lastMode => $composableBuilder(
    column: $table.lastMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayTimeZoneId => $composableBuilder(
    column: $table.displayTimeZoneId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusPreferencesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusPreferencesTable> {
  $$FocusPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lastMode =>
      $composableBuilder(column: $table.lastMode, builder: (column) => column);

  GeneratedColumn<String> get displayTimeZoneId => $composableBuilder(
    column: $table.displayTimeZoneId,
    builder: (column) => column,
  );
}

class $$FocusPreferencesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusPreferencesTable,
          FocusPreference,
          $$FocusPreferencesTableFilterComposer,
          $$FocusPreferencesTableOrderingComposer,
          $$FocusPreferencesTableAnnotationComposer,
          $$FocusPreferencesTableCreateCompanionBuilder,
          $$FocusPreferencesTableUpdateCompanionBuilder,
          (
            FocusPreference,
            BaseReferences<
              _$PactaDatabase,
              $FocusPreferencesTable,
              FocusPreference
            >,
          ),
          FocusPreference,
          PrefetchHooks Function()
        > {
  $$FocusPreferencesTableTableManager(
    _$PactaDatabase db,
    $FocusPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> lastMode = const Value.absent(),
                Value<String?> displayTimeZoneId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusPreferencesCompanion(
                userId: userId,
                lastMode: lastMode,
                displayTimeZoneId: displayTimeZoneId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String lastMode,
                Value<String?> displayTimeZoneId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusPreferencesCompanion.insert(
                userId: userId,
                lastMode: lastMode,
                displayTimeZoneId: displayTimeZoneId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FocusPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusPreferencesTable,
      FocusPreference,
      $$FocusPreferencesTableFilterComposer,
      $$FocusPreferencesTableOrderingComposer,
      $$FocusPreferencesTableAnnotationComposer,
      $$FocusPreferencesTableCreateCompanionBuilder,
      $$FocusPreferencesTableUpdateCompanionBuilder,
      (
        FocusPreference,
        BaseReferences<
          _$PactaDatabase,
          $FocusPreferencesTable,
          FocusPreference
        >,
      ),
      FocusPreference,
      PrefetchHooks Function()
    >;
typedef $$FocusPrecedentRulesTableCreateCompanionBuilder =
    FocusPrecedentRulesCompanion Function({
      required String userId,
      required String id,
      required String ruleText,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$FocusPrecedentRulesTableUpdateCompanionBuilder =
    FocusPrecedentRulesCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> ruleText,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$FocusPrecedentRulesTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusPrecedentRulesTable> {
  $$FocusPrecedentRulesTableFilterComposer({
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

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruleText => $composableBuilder(
    column: $table.ruleText,
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

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusPrecedentRulesTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusPrecedentRulesTable> {
  $$FocusPrecedentRulesTableOrderingComposer({
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

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleText => $composableBuilder(
    column: $table.ruleText,
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

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusPrecedentRulesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusPrecedentRulesTable> {
  $$FocusPrecedentRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ruleText =>
      $composableBuilder(column: $table.ruleText, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$FocusPrecedentRulesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusPrecedentRulesTable,
          FocusPrecedentRule,
          $$FocusPrecedentRulesTableFilterComposer,
          $$FocusPrecedentRulesTableOrderingComposer,
          $$FocusPrecedentRulesTableAnnotationComposer,
          $$FocusPrecedentRulesTableCreateCompanionBuilder,
          $$FocusPrecedentRulesTableUpdateCompanionBuilder,
          (
            FocusPrecedentRule,
            BaseReferences<
              _$PactaDatabase,
              $FocusPrecedentRulesTable,
              FocusPrecedentRule
            >,
          ),
          FocusPrecedentRule,
          PrefetchHooks Function()
        > {
  $$FocusPrecedentRulesTableTableManager(
    _$PactaDatabase db,
    $FocusPrecedentRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusPrecedentRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusPrecedentRulesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$FocusPrecedentRulesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> ruleText = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusPrecedentRulesCompanion(
                userId: userId,
                id: id,
                ruleText: ruleText,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String ruleText,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusPrecedentRulesCompanion.insert(
                userId: userId,
                id: id,
                ruleText: ruleText,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FocusPrecedentRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusPrecedentRulesTable,
      FocusPrecedentRule,
      $$FocusPrecedentRulesTableFilterComposer,
      $$FocusPrecedentRulesTableOrderingComposer,
      $$FocusPrecedentRulesTableAnnotationComposer,
      $$FocusPrecedentRulesTableCreateCompanionBuilder,
      $$FocusPrecedentRulesTableUpdateCompanionBuilder,
      (
        FocusPrecedentRule,
        BaseReferences<
          _$PactaDatabase,
          $FocusPrecedentRulesTable,
          FocusPrecedentRule
        >,
      ),
      FocusPrecedentRule,
      PrefetchHooks Function()
    >;
typedef $$FocusAppointmentsTableCreateCompanionBuilder =
    FocusAppointmentsCompanion Function({
      required String userId,
      required String id,
      required String taskId,
      required String mode,
      required int durationSeconds,
      required DateTime startedAt,
      required DateTime endsAt,
      required String status,
      Value<DateTime?> settledAt,
      Value<String?> sessionId,
      Value<String?> failureReason,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$FocusAppointmentsTableUpdateCompanionBuilder =
    FocusAppointmentsCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> taskId,
      Value<String> mode,
      Value<int> durationSeconds,
      Value<DateTime> startedAt,
      Value<DateTime> endsAt,
      Value<String> status,
      Value<DateTime?> settledAt,
      Value<String?> sessionId,
      Value<String?> failureReason,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$FocusAppointmentsTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusAppointmentsTable> {
  $$FocusAppointmentsTableFilterComposer({
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

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get settledAt => $composableBuilder(
    column: $table.settledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusAppointmentsTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusAppointmentsTable> {
  $$FocusAppointmentsTableOrderingComposer({
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

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get settledAt => $composableBuilder(
    column: $table.settledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusAppointmentsTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusAppointmentsTable> {
  $$FocusAppointmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endsAt =>
      $composableBuilder(column: $table.endsAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get settledAt =>
      $composableBuilder(column: $table.settledAt, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FocusAppointmentsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusAppointmentsTable,
          FocusAppointment,
          $$FocusAppointmentsTableFilterComposer,
          $$FocusAppointmentsTableOrderingComposer,
          $$FocusAppointmentsTableAnnotationComposer,
          $$FocusAppointmentsTableCreateCompanionBuilder,
          $$FocusAppointmentsTableUpdateCompanionBuilder,
          (
            FocusAppointment,
            BaseReferences<
              _$PactaDatabase,
              $FocusAppointmentsTable,
              FocusAppointment
            >,
          ),
          FocusAppointment,
          PrefetchHooks Function()
        > {
  $$FocusAppointmentsTableTableManager(
    _$PactaDatabase db,
    $FocusAppointmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusAppointmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusAppointmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusAppointmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime> endsAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> settledAt = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusAppointmentsCompanion(
                userId: userId,
                id: id,
                taskId: taskId,
                mode: mode,
                durationSeconds: durationSeconds,
                startedAt: startedAt,
                endsAt: endsAt,
                status: status,
                settledAt: settledAt,
                sessionId: sessionId,
                failureReason: failureReason,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String taskId,
                required String mode,
                required int durationSeconds,
                required DateTime startedAt,
                required DateTime endsAt,
                required String status,
                Value<DateTime?> settledAt = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FocusAppointmentsCompanion.insert(
                userId: userId,
                id: id,
                taskId: taskId,
                mode: mode,
                durationSeconds: durationSeconds,
                startedAt: startedAt,
                endsAt: endsAt,
                status: status,
                settledAt: settledAt,
                sessionId: sessionId,
                failureReason: failureReason,
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

typedef $$FocusAppointmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusAppointmentsTable,
      FocusAppointment,
      $$FocusAppointmentsTableFilterComposer,
      $$FocusAppointmentsTableOrderingComposer,
      $$FocusAppointmentsTableAnnotationComposer,
      $$FocusAppointmentsTableCreateCompanionBuilder,
      $$FocusAppointmentsTableUpdateCompanionBuilder,
      (
        FocusAppointment,
        BaseReferences<
          _$PactaDatabase,
          $FocusAppointmentsTable,
          FocusAppointment
        >,
      ),
      FocusAppointment,
      PrefetchHooks Function()
    >;
typedef $$AppointmentChainRecordsTableCreateCompanionBuilder =
    AppointmentChainRecordsCompanion Function({
      required String userId,
      Value<int> currentConsecutive,
      Value<int> bestConsecutive,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppointmentChainRecordsTableUpdateCompanionBuilder =
    AppointmentChainRecordsCompanion Function({
      Value<String> userId,
      Value<int> currentConsecutive,
      Value<int> bestConsecutive,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppointmentChainRecordsTableFilterComposer
    extends Composer<_$PactaDatabase, $AppointmentChainRecordsTable> {
  $$AppointmentChainRecordsTableFilterComposer({
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

  ColumnFilters<int> get currentConsecutive => $composableBuilder(
    column: $table.currentConsecutive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bestConsecutive => $composableBuilder(
    column: $table.bestConsecutive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppointmentChainRecordsTableOrderingComposer
    extends Composer<_$PactaDatabase, $AppointmentChainRecordsTable> {
  $$AppointmentChainRecordsTableOrderingComposer({
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

  ColumnOrderings<int> get currentConsecutive => $composableBuilder(
    column: $table.currentConsecutive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bestConsecutive => $composableBuilder(
    column: $table.bestConsecutive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppointmentChainRecordsTableAnnotationComposer
    extends Composer<_$PactaDatabase, $AppointmentChainRecordsTable> {
  $$AppointmentChainRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get currentConsecutive => $composableBuilder(
    column: $table.currentConsecutive,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bestConsecutive => $composableBuilder(
    column: $table.bestConsecutive,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppointmentChainRecordsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $AppointmentChainRecordsTable,
          AppointmentChainRecord,
          $$AppointmentChainRecordsTableFilterComposer,
          $$AppointmentChainRecordsTableOrderingComposer,
          $$AppointmentChainRecordsTableAnnotationComposer,
          $$AppointmentChainRecordsTableCreateCompanionBuilder,
          $$AppointmentChainRecordsTableUpdateCompanionBuilder,
          (
            AppointmentChainRecord,
            BaseReferences<
              _$PactaDatabase,
              $AppointmentChainRecordsTable,
              AppointmentChainRecord
            >,
          ),
          AppointmentChainRecord,
          PrefetchHooks Function()
        > {
  $$AppointmentChainRecordsTableTableManager(
    _$PactaDatabase db,
    $AppointmentChainRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppointmentChainRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AppointmentChainRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AppointmentChainRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<int> currentConsecutive = const Value.absent(),
                Value<int> bestConsecutive = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppointmentChainRecordsCompanion(
                userId: userId,
                currentConsecutive: currentConsecutive,
                bestConsecutive: bestConsecutive,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                Value<int> currentConsecutive = const Value.absent(),
                Value<int> bestConsecutive = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppointmentChainRecordsCompanion.insert(
                userId: userId,
                currentConsecutive: currentConsecutive,
                bestConsecutive: bestConsecutive,
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

typedef $$AppointmentChainRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $AppointmentChainRecordsTable,
      AppointmentChainRecord,
      $$AppointmentChainRecordsTableFilterComposer,
      $$AppointmentChainRecordsTableOrderingComposer,
      $$AppointmentChainRecordsTableAnnotationComposer,
      $$AppointmentChainRecordsTableCreateCompanionBuilder,
      $$AppointmentChainRecordsTableUpdateCompanionBuilder,
      (
        AppointmentChainRecord,
        BaseReferences<
          _$PactaDatabase,
          $AppointmentChainRecordsTable,
          AppointmentChainRecord
        >,
      ),
      AppointmentChainRecord,
      PrefetchHooks Function()
    >;

class $PactaDatabaseManager {
  final _$PactaDatabase _db;
  $PactaDatabaseManager(this._db);
  $$LocalGoalsTableTableManager get localGoals =>
      $$LocalGoalsTableTableManager(_db, _db.localGoals);
  $$LocalTasksTableTableManager get localTasks =>
      $$LocalTasksTableTableManager(_db, _db.localTasks);
  $$TaskSyncEntriesTableTableManager get taskSyncEntries =>
      $$TaskSyncEntriesTableTableManager(_db, _db.taskSyncEntries);
  $$FocusSessionsTableTableManager get focusSessions =>
      $$FocusSessionsTableTableManager(_db, _db.focusSessions);
  $$FocusNodesTableTableManager get focusNodes =>
      $$FocusNodesTableTableManager(_db, _db.focusNodes);
  $$FocusChainRecordsTableTableManager get focusChainRecords =>
      $$FocusChainRecordsTableTableManager(_db, _db.focusChainRecords);
  $$FocusPreferencesTableTableManager get focusPreferences =>
      $$FocusPreferencesTableTableManager(_db, _db.focusPreferences);
  $$FocusPrecedentRulesTableTableManager get focusPrecedentRules =>
      $$FocusPrecedentRulesTableTableManager(_db, _db.focusPrecedentRules);
  $$FocusAppointmentsTableTableManager get focusAppointments =>
      $$FocusAppointmentsTableTableManager(_db, _db.focusAppointments);
  $$AppointmentChainRecordsTableTableManager get appointmentChainRecords =>
      $$AppointmentChainRecordsTableTableManager(
        _db,
        _db.appointmentChainRecords,
      );
}
