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

class $LocalNationalFocusCardsTable extends LocalNationalFocusCards
    with TableInfo<$LocalNationalFocusCardsTable, LocalNationalFocusCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalNationalFocusCardsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _triggerConditionMeta = const VerificationMeta(
    'triggerCondition',
  );
  @override
  late final GeneratedColumn<String> triggerCondition = GeneratedColumn<String>(
    'trigger_condition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exceptionNotesMeta = const VerificationMeta(
    'exceptionNotes',
  );
  @override
  late final GeneratedColumn<String> exceptionNotes = GeneratedColumn<String>(
    'exception_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isInTreeMeta = const VerificationMeta(
    'isInTree',
  );
  @override
  late final GeneratedColumn<bool> isInTree = GeneratedColumn<bool>(
    'is_in_tree',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_in_tree" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('extinguished'),
  );
  static const VerificationMeta _successfulDaysMeta = const VerificationMeta(
    'successfulDays',
  );
  @override
  late final GeneratedColumn<int> successfulDays = GeneratedColumn<int>(
    'successful_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _currentConsecutiveDaysMeta =
      const VerificationMeta('currentConsecutiveDays');
  @override
  late final GeneratedColumn<int> currentConsecutiveDays = GeneratedColumn<int>(
    'current_consecutive_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bestConsecutiveDaysMeta =
      const VerificationMeta('bestConsecutiveDays');
  @override
  late final GeneratedColumn<int> bestConsecutiveDays = GeneratedColumn<int>(
    'best_consecutive_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _maintenanceCycleStartedMeta =
      const VerificationMeta('maintenanceCycleStarted');
  @override
  late final GeneratedColumn<bool> maintenanceCycleStarted =
      GeneratedColumn<bool>(
        'maintenance_cycle_started',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("maintenance_cycle_started" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
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
  static const VerificationMeta _cascadeSourceCardIdMeta =
      const VerificationMeta('cascadeSourceCardId');
  @override
  late final GeneratedColumn<String> cascadeSourceCardId =
      GeneratedColumn<String>(
        'cascade_source_card_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cascadePriorStateMeta = const VerificationMeta(
    'cascadePriorState',
  );
  @override
  late final GeneratedColumn<String> cascadePriorState =
      GeneratedColumn<String>(
        'cascade_prior_state',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
  static const VerificationMeta _activeStrengtheningLevelMeta =
      const VerificationMeta('activeStrengtheningLevel');
  @override
  late final GeneratedColumn<int> activeStrengtheningLevel =
      GeneratedColumn<int>(
        'active_strengthening_level',
        aliasedName,
        true,
        type: DriftSqlType.int,
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
    triggerCondition,
    action,
    scope,
    exceptionNotes,
    isInTree,
    parentId,
    state,
    successfulDays,
    currentConsecutiveDays,
    bestConsecutiveDays,
    maintenanceCycleStarted,
    failureReason,
    cascadeSourceCardId,
    cascadePriorState,
    reviewDisposition,
    activeStrengtheningLevel,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_national_focus_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalNationalFocusCard> instance, {
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
    if (data.containsKey('trigger_condition')) {
      context.handle(
        _triggerConditionMeta,
        triggerCondition.isAcceptableOrUnknown(
          data['trigger_condition']!,
          _triggerConditionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_triggerConditionMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('exception_notes')) {
      context.handle(
        _exceptionNotesMeta,
        exceptionNotes.isAcceptableOrUnknown(
          data['exception_notes']!,
          _exceptionNotesMeta,
        ),
      );
    }
    if (data.containsKey('is_in_tree')) {
      context.handle(
        _isInTreeMeta,
        isInTree.isAcceptableOrUnknown(data['is_in_tree']!, _isInTreeMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('successful_days')) {
      context.handle(
        _successfulDaysMeta,
        successfulDays.isAcceptableOrUnknown(
          data['successful_days']!,
          _successfulDaysMeta,
        ),
      );
    }
    if (data.containsKey('current_consecutive_days')) {
      context.handle(
        _currentConsecutiveDaysMeta,
        currentConsecutiveDays.isAcceptableOrUnknown(
          data['current_consecutive_days']!,
          _currentConsecutiveDaysMeta,
        ),
      );
    }
    if (data.containsKey('best_consecutive_days')) {
      context.handle(
        _bestConsecutiveDaysMeta,
        bestConsecutiveDays.isAcceptableOrUnknown(
          data['best_consecutive_days']!,
          _bestConsecutiveDaysMeta,
        ),
      );
    }
    if (data.containsKey('maintenance_cycle_started')) {
      context.handle(
        _maintenanceCycleStartedMeta,
        maintenanceCycleStarted.isAcceptableOrUnknown(
          data['maintenance_cycle_started']!,
          _maintenanceCycleStartedMeta,
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
    if (data.containsKey('cascade_source_card_id')) {
      context.handle(
        _cascadeSourceCardIdMeta,
        cascadeSourceCardId.isAcceptableOrUnknown(
          data['cascade_source_card_id']!,
          _cascadeSourceCardIdMeta,
        ),
      );
    }
    if (data.containsKey('cascade_prior_state')) {
      context.handle(
        _cascadePriorStateMeta,
        cascadePriorState.isAcceptableOrUnknown(
          data['cascade_prior_state']!,
          _cascadePriorStateMeta,
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
    if (data.containsKey('active_strengthening_level')) {
      context.handle(
        _activeStrengtheningLevelMeta,
        activeStrengtheningLevel.isAcceptableOrUnknown(
          data['active_strengthening_level']!,
          _activeStrengtheningLevelMeta,
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
  LocalNationalFocusCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalNationalFocusCard(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      triggerCondition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_condition'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      ),
      exceptionNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exception_notes'],
      ),
      isInTree: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_in_tree'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      successfulDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}successful_days'],
      )!,
      currentConsecutiveDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_consecutive_days'],
      )!,
      bestConsecutiveDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}best_consecutive_days'],
      )!,
      maintenanceCycleStarted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}maintenance_cycle_started'],
      )!,
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      cascadeSourceCardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cascade_source_card_id'],
      ),
      cascadePriorState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cascade_prior_state'],
      ),
      reviewDisposition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_disposition'],
      )!,
      activeStrengtheningLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active_strengthening_level'],
      ),
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
  $LocalNationalFocusCardsTable createAlias(String alias) {
    return $LocalNationalFocusCardsTable(attachedDatabase, alias);
  }
}

class LocalNationalFocusCard extends DataClass
    implements Insertable<LocalNationalFocusCard> {
  final String userId;
  final String id;
  final String triggerCondition;
  final String action;
  final String? scope;
  final String? exceptionNotes;
  final bool isInTree;
  final String? parentId;
  final String state;
  final int successfulDays;
  final int currentConsecutiveDays;
  final int bestConsecutiveDays;
  final bool maintenanceCycleStarted;
  final String? failureReason;
  final String? cascadeSourceCardId;
  final String? cascadePriorState;
  final String reviewDisposition;
  final int? activeStrengtheningLevel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalNationalFocusCard({
    required this.userId,
    required this.id,
    required this.triggerCondition,
    required this.action,
    this.scope,
    this.exceptionNotes,
    required this.isInTree,
    this.parentId,
    required this.state,
    required this.successfulDays,
    required this.currentConsecutiveDays,
    required this.bestConsecutiveDays,
    required this.maintenanceCycleStarted,
    this.failureReason,
    this.cascadeSourceCardId,
    this.cascadePriorState,
    required this.reviewDisposition,
    this.activeStrengtheningLevel,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['trigger_condition'] = Variable<String>(triggerCondition);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || scope != null) {
      map['scope'] = Variable<String>(scope);
    }
    if (!nullToAbsent || exceptionNotes != null) {
      map['exception_notes'] = Variable<String>(exceptionNotes);
    }
    map['is_in_tree'] = Variable<bool>(isInTree);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['state'] = Variable<String>(state);
    map['successful_days'] = Variable<int>(successfulDays);
    map['current_consecutive_days'] = Variable<int>(currentConsecutiveDays);
    map['best_consecutive_days'] = Variable<int>(bestConsecutiveDays);
    map['maintenance_cycle_started'] = Variable<bool>(maintenanceCycleStarted);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || cascadeSourceCardId != null) {
      map['cascade_source_card_id'] = Variable<String>(cascadeSourceCardId);
    }
    if (!nullToAbsent || cascadePriorState != null) {
      map['cascade_prior_state'] = Variable<String>(cascadePriorState);
    }
    map['review_disposition'] = Variable<String>(reviewDisposition);
    if (!nullToAbsent || activeStrengtheningLevel != null) {
      map['active_strengthening_level'] = Variable<int>(
        activeStrengtheningLevel,
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalNationalFocusCardsCompanion toCompanion(bool nullToAbsent) {
    return LocalNationalFocusCardsCompanion(
      userId: Value(userId),
      id: Value(id),
      triggerCondition: Value(triggerCondition),
      action: Value(action),
      scope: scope == null && nullToAbsent
          ? const Value.absent()
          : Value(scope),
      exceptionNotes: exceptionNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(exceptionNotes),
      isInTree: Value(isInTree),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      state: Value(state),
      successfulDays: Value(successfulDays),
      currentConsecutiveDays: Value(currentConsecutiveDays),
      bestConsecutiveDays: Value(bestConsecutiveDays),
      maintenanceCycleStarted: Value(maintenanceCycleStarted),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      cascadeSourceCardId: cascadeSourceCardId == null && nullToAbsent
          ? const Value.absent()
          : Value(cascadeSourceCardId),
      cascadePriorState: cascadePriorState == null && nullToAbsent
          ? const Value.absent()
          : Value(cascadePriorState),
      reviewDisposition: Value(reviewDisposition),
      activeStrengtheningLevel: activeStrengtheningLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(activeStrengtheningLevel),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalNationalFocusCard.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalNationalFocusCard(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      triggerCondition: serializer.fromJson<String>(json['triggerCondition']),
      action: serializer.fromJson<String>(json['action']),
      scope: serializer.fromJson<String?>(json['scope']),
      exceptionNotes: serializer.fromJson<String?>(json['exceptionNotes']),
      isInTree: serializer.fromJson<bool>(json['isInTree']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      state: serializer.fromJson<String>(json['state']),
      successfulDays: serializer.fromJson<int>(json['successfulDays']),
      currentConsecutiveDays: serializer.fromJson<int>(
        json['currentConsecutiveDays'],
      ),
      bestConsecutiveDays: serializer.fromJson<int>(
        json['bestConsecutiveDays'],
      ),
      maintenanceCycleStarted: serializer.fromJson<bool>(
        json['maintenanceCycleStarted'],
      ),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      cascadeSourceCardId: serializer.fromJson<String?>(
        json['cascadeSourceCardId'],
      ),
      cascadePriorState: serializer.fromJson<String?>(
        json['cascadePriorState'],
      ),
      reviewDisposition: serializer.fromJson<String>(json['reviewDisposition']),
      activeStrengtheningLevel: serializer.fromJson<int?>(
        json['activeStrengtheningLevel'],
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
      'triggerCondition': serializer.toJson<String>(triggerCondition),
      'action': serializer.toJson<String>(action),
      'scope': serializer.toJson<String?>(scope),
      'exceptionNotes': serializer.toJson<String?>(exceptionNotes),
      'isInTree': serializer.toJson<bool>(isInTree),
      'parentId': serializer.toJson<String?>(parentId),
      'state': serializer.toJson<String>(state),
      'successfulDays': serializer.toJson<int>(successfulDays),
      'currentConsecutiveDays': serializer.toJson<int>(currentConsecutiveDays),
      'bestConsecutiveDays': serializer.toJson<int>(bestConsecutiveDays),
      'maintenanceCycleStarted': serializer.toJson<bool>(
        maintenanceCycleStarted,
      ),
      'failureReason': serializer.toJson<String?>(failureReason),
      'cascadeSourceCardId': serializer.toJson<String?>(cascadeSourceCardId),
      'cascadePriorState': serializer.toJson<String?>(cascadePriorState),
      'reviewDisposition': serializer.toJson<String>(reviewDisposition),
      'activeStrengtheningLevel': serializer.toJson<int?>(
        activeStrengtheningLevel,
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalNationalFocusCard copyWith({
    String? userId,
    String? id,
    String? triggerCondition,
    String? action,
    Value<String?> scope = const Value.absent(),
    Value<String?> exceptionNotes = const Value.absent(),
    bool? isInTree,
    Value<String?> parentId = const Value.absent(),
    String? state,
    int? successfulDays,
    int? currentConsecutiveDays,
    int? bestConsecutiveDays,
    bool? maintenanceCycleStarted,
    Value<String?> failureReason = const Value.absent(),
    Value<String?> cascadeSourceCardId = const Value.absent(),
    Value<String?> cascadePriorState = const Value.absent(),
    String? reviewDisposition,
    Value<int?> activeStrengtheningLevel = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalNationalFocusCard(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    triggerCondition: triggerCondition ?? this.triggerCondition,
    action: action ?? this.action,
    scope: scope.present ? scope.value : this.scope,
    exceptionNotes: exceptionNotes.present
        ? exceptionNotes.value
        : this.exceptionNotes,
    isInTree: isInTree ?? this.isInTree,
    parentId: parentId.present ? parentId.value : this.parentId,
    state: state ?? this.state,
    successfulDays: successfulDays ?? this.successfulDays,
    currentConsecutiveDays:
        currentConsecutiveDays ?? this.currentConsecutiveDays,
    bestConsecutiveDays: bestConsecutiveDays ?? this.bestConsecutiveDays,
    maintenanceCycleStarted:
        maintenanceCycleStarted ?? this.maintenanceCycleStarted,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    cascadeSourceCardId: cascadeSourceCardId.present
        ? cascadeSourceCardId.value
        : this.cascadeSourceCardId,
    cascadePriorState: cascadePriorState.present
        ? cascadePriorState.value
        : this.cascadePriorState,
    reviewDisposition: reviewDisposition ?? this.reviewDisposition,
    activeStrengtheningLevel: activeStrengtheningLevel.present
        ? activeStrengtheningLevel.value
        : this.activeStrengtheningLevel,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalNationalFocusCard copyWithCompanion(
    LocalNationalFocusCardsCompanion data,
  ) {
    return LocalNationalFocusCard(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      triggerCondition: data.triggerCondition.present
          ? data.triggerCondition.value
          : this.triggerCondition,
      action: data.action.present ? data.action.value : this.action,
      scope: data.scope.present ? data.scope.value : this.scope,
      exceptionNotes: data.exceptionNotes.present
          ? data.exceptionNotes.value
          : this.exceptionNotes,
      isInTree: data.isInTree.present ? data.isInTree.value : this.isInTree,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      state: data.state.present ? data.state.value : this.state,
      successfulDays: data.successfulDays.present
          ? data.successfulDays.value
          : this.successfulDays,
      currentConsecutiveDays: data.currentConsecutiveDays.present
          ? data.currentConsecutiveDays.value
          : this.currentConsecutiveDays,
      bestConsecutiveDays: data.bestConsecutiveDays.present
          ? data.bestConsecutiveDays.value
          : this.bestConsecutiveDays,
      maintenanceCycleStarted: data.maintenanceCycleStarted.present
          ? data.maintenanceCycleStarted.value
          : this.maintenanceCycleStarted,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      cascadeSourceCardId: data.cascadeSourceCardId.present
          ? data.cascadeSourceCardId.value
          : this.cascadeSourceCardId,
      cascadePriorState: data.cascadePriorState.present
          ? data.cascadePriorState.value
          : this.cascadePriorState,
      reviewDisposition: data.reviewDisposition.present
          ? data.reviewDisposition.value
          : this.reviewDisposition,
      activeStrengtheningLevel: data.activeStrengtheningLevel.present
          ? data.activeStrengtheningLevel.value
          : this.activeStrengtheningLevel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusCard(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('triggerCondition: $triggerCondition, ')
          ..write('action: $action, ')
          ..write('scope: $scope, ')
          ..write('exceptionNotes: $exceptionNotes, ')
          ..write('isInTree: $isInTree, ')
          ..write('parentId: $parentId, ')
          ..write('state: $state, ')
          ..write('successfulDays: $successfulDays, ')
          ..write('currentConsecutiveDays: $currentConsecutiveDays, ')
          ..write('bestConsecutiveDays: $bestConsecutiveDays, ')
          ..write('maintenanceCycleStarted: $maintenanceCycleStarted, ')
          ..write('failureReason: $failureReason, ')
          ..write('cascadeSourceCardId: $cascadeSourceCardId, ')
          ..write('cascadePriorState: $cascadePriorState, ')
          ..write('reviewDisposition: $reviewDisposition, ')
          ..write('activeStrengtheningLevel: $activeStrengtheningLevel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    userId,
    id,
    triggerCondition,
    action,
    scope,
    exceptionNotes,
    isInTree,
    parentId,
    state,
    successfulDays,
    currentConsecutiveDays,
    bestConsecutiveDays,
    maintenanceCycleStarted,
    failureReason,
    cascadeSourceCardId,
    cascadePriorState,
    reviewDisposition,
    activeStrengtheningLevel,
    createdAt,
    updatedAt,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalNationalFocusCard &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.triggerCondition == this.triggerCondition &&
          other.action == this.action &&
          other.scope == this.scope &&
          other.exceptionNotes == this.exceptionNotes &&
          other.isInTree == this.isInTree &&
          other.parentId == this.parentId &&
          other.state == this.state &&
          other.successfulDays == this.successfulDays &&
          other.currentConsecutiveDays == this.currentConsecutiveDays &&
          other.bestConsecutiveDays == this.bestConsecutiveDays &&
          other.maintenanceCycleStarted == this.maintenanceCycleStarted &&
          other.failureReason == this.failureReason &&
          other.cascadeSourceCardId == this.cascadeSourceCardId &&
          other.cascadePriorState == this.cascadePriorState &&
          other.reviewDisposition == this.reviewDisposition &&
          other.activeStrengtheningLevel == this.activeStrengtheningLevel &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalNationalFocusCardsCompanion
    extends UpdateCompanion<LocalNationalFocusCard> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> triggerCondition;
  final Value<String> action;
  final Value<String?> scope;
  final Value<String?> exceptionNotes;
  final Value<bool> isInTree;
  final Value<String?> parentId;
  final Value<String> state;
  final Value<int> successfulDays;
  final Value<int> currentConsecutiveDays;
  final Value<int> bestConsecutiveDays;
  final Value<bool> maintenanceCycleStarted;
  final Value<String?> failureReason;
  final Value<String?> cascadeSourceCardId;
  final Value<String?> cascadePriorState;
  final Value<String> reviewDisposition;
  final Value<int?> activeStrengtheningLevel;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalNationalFocusCardsCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.triggerCondition = const Value.absent(),
    this.action = const Value.absent(),
    this.scope = const Value.absent(),
    this.exceptionNotes = const Value.absent(),
    this.isInTree = const Value.absent(),
    this.parentId = const Value.absent(),
    this.state = const Value.absent(),
    this.successfulDays = const Value.absent(),
    this.currentConsecutiveDays = const Value.absent(),
    this.bestConsecutiveDays = const Value.absent(),
    this.maintenanceCycleStarted = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.cascadeSourceCardId = const Value.absent(),
    this.cascadePriorState = const Value.absent(),
    this.reviewDisposition = const Value.absent(),
    this.activeStrengtheningLevel = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalNationalFocusCardsCompanion.insert({
    required String userId,
    required String id,
    required String triggerCondition,
    required String action,
    this.scope = const Value.absent(),
    this.exceptionNotes = const Value.absent(),
    this.isInTree = const Value.absent(),
    this.parentId = const Value.absent(),
    this.state = const Value.absent(),
    this.successfulDays = const Value.absent(),
    this.currentConsecutiveDays = const Value.absent(),
    this.bestConsecutiveDays = const Value.absent(),
    this.maintenanceCycleStarted = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.cascadeSourceCardId = const Value.absent(),
    this.cascadePriorState = const Value.absent(),
    this.reviewDisposition = const Value.absent(),
    this.activeStrengtheningLevel = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       triggerCondition = Value(triggerCondition),
       action = Value(action),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalNationalFocusCard> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? triggerCondition,
    Expression<String>? action,
    Expression<String>? scope,
    Expression<String>? exceptionNotes,
    Expression<bool>? isInTree,
    Expression<String>? parentId,
    Expression<String>? state,
    Expression<int>? successfulDays,
    Expression<int>? currentConsecutiveDays,
    Expression<int>? bestConsecutiveDays,
    Expression<bool>? maintenanceCycleStarted,
    Expression<String>? failureReason,
    Expression<String>? cascadeSourceCardId,
    Expression<String>? cascadePriorState,
    Expression<String>? reviewDisposition,
    Expression<int>? activeStrengtheningLevel,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (triggerCondition != null) 'trigger_condition': triggerCondition,
      if (action != null) 'action': action,
      if (scope != null) 'scope': scope,
      if (exceptionNotes != null) 'exception_notes': exceptionNotes,
      if (isInTree != null) 'is_in_tree': isInTree,
      if (parentId != null) 'parent_id': parentId,
      if (state != null) 'state': state,
      if (successfulDays != null) 'successful_days': successfulDays,
      if (currentConsecutiveDays != null)
        'current_consecutive_days': currentConsecutiveDays,
      if (bestConsecutiveDays != null)
        'best_consecutive_days': bestConsecutiveDays,
      if (maintenanceCycleStarted != null)
        'maintenance_cycle_started': maintenanceCycleStarted,
      if (failureReason != null) 'failure_reason': failureReason,
      if (cascadeSourceCardId != null)
        'cascade_source_card_id': cascadeSourceCardId,
      if (cascadePriorState != null) 'cascade_prior_state': cascadePriorState,
      if (reviewDisposition != null) 'review_disposition': reviewDisposition,
      if (activeStrengtheningLevel != null)
        'active_strengthening_level': activeStrengtheningLevel,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalNationalFocusCardsCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? triggerCondition,
    Value<String>? action,
    Value<String?>? scope,
    Value<String?>? exceptionNotes,
    Value<bool>? isInTree,
    Value<String?>? parentId,
    Value<String>? state,
    Value<int>? successfulDays,
    Value<int>? currentConsecutiveDays,
    Value<int>? bestConsecutiveDays,
    Value<bool>? maintenanceCycleStarted,
    Value<String?>? failureReason,
    Value<String?>? cascadeSourceCardId,
    Value<String?>? cascadePriorState,
    Value<String>? reviewDisposition,
    Value<int?>? activeStrengtheningLevel,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalNationalFocusCardsCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      triggerCondition: triggerCondition ?? this.triggerCondition,
      action: action ?? this.action,
      scope: scope ?? this.scope,
      exceptionNotes: exceptionNotes ?? this.exceptionNotes,
      isInTree: isInTree ?? this.isInTree,
      parentId: parentId ?? this.parentId,
      state: state ?? this.state,
      successfulDays: successfulDays ?? this.successfulDays,
      currentConsecutiveDays:
          currentConsecutiveDays ?? this.currentConsecutiveDays,
      bestConsecutiveDays: bestConsecutiveDays ?? this.bestConsecutiveDays,
      maintenanceCycleStarted:
          maintenanceCycleStarted ?? this.maintenanceCycleStarted,
      failureReason: failureReason ?? this.failureReason,
      cascadeSourceCardId: cascadeSourceCardId ?? this.cascadeSourceCardId,
      cascadePriorState: cascadePriorState ?? this.cascadePriorState,
      reviewDisposition: reviewDisposition ?? this.reviewDisposition,
      activeStrengtheningLevel:
          activeStrengtheningLevel ?? this.activeStrengtheningLevel,
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
    if (triggerCondition.present) {
      map['trigger_condition'] = Variable<String>(triggerCondition.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (exceptionNotes.present) {
      map['exception_notes'] = Variable<String>(exceptionNotes.value);
    }
    if (isInTree.present) {
      map['is_in_tree'] = Variable<bool>(isInTree.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (successfulDays.present) {
      map['successful_days'] = Variable<int>(successfulDays.value);
    }
    if (currentConsecutiveDays.present) {
      map['current_consecutive_days'] = Variable<int>(
        currentConsecutiveDays.value,
      );
    }
    if (bestConsecutiveDays.present) {
      map['best_consecutive_days'] = Variable<int>(bestConsecutiveDays.value);
    }
    if (maintenanceCycleStarted.present) {
      map['maintenance_cycle_started'] = Variable<bool>(
        maintenanceCycleStarted.value,
      );
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (cascadeSourceCardId.present) {
      map['cascade_source_card_id'] = Variable<String>(
        cascadeSourceCardId.value,
      );
    }
    if (cascadePriorState.present) {
      map['cascade_prior_state'] = Variable<String>(cascadePriorState.value);
    }
    if (reviewDisposition.present) {
      map['review_disposition'] = Variable<String>(reviewDisposition.value);
    }
    if (activeStrengtheningLevel.present) {
      map['active_strengthening_level'] = Variable<int>(
        activeStrengtheningLevel.value,
      );
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
    return (StringBuffer('LocalNationalFocusCardsCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('triggerCondition: $triggerCondition, ')
          ..write('action: $action, ')
          ..write('scope: $scope, ')
          ..write('exceptionNotes: $exceptionNotes, ')
          ..write('isInTree: $isInTree, ')
          ..write('parentId: $parentId, ')
          ..write('state: $state, ')
          ..write('successfulDays: $successfulDays, ')
          ..write('currentConsecutiveDays: $currentConsecutiveDays, ')
          ..write('bestConsecutiveDays: $bestConsecutiveDays, ')
          ..write('maintenanceCycleStarted: $maintenanceCycleStarted, ')
          ..write('failureReason: $failureReason, ')
          ..write('cascadeSourceCardId: $cascadeSourceCardId, ')
          ..write('cascadePriorState: $cascadePriorState, ')
          ..write('reviewDisposition: $reviewDisposition, ')
          ..write('activeStrengtheningLevel: $activeStrengtheningLevel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalNationalFocusStrengtheningLevelsTable
    extends LocalNationalFocusStrengtheningLevels
    with
        TableInfo<
          $LocalNationalFocusStrengtheningLevelsTable,
          LocalNationalFocusStrengtheningLevel
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalNationalFocusStrengtheningLevelsTable(
    this.attachedDatabase, [
    this._alias,
  ]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _levelNumberMeta = const VerificationMeta(
    'levelNumber',
  );
  @override
  late final GeneratedColumn<int> levelNumber = GeneratedColumn<int>(
    'level_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triggerConditionOverrideMeta =
      const VerificationMeta('triggerConditionOverride');
  @override
  late final GeneratedColumn<String> triggerConditionOverride =
      GeneratedColumn<String>(
        'trigger_condition_override',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _actionOverrideMeta = const VerificationMeta(
    'actionOverride',
  );
  @override
  late final GeneratedColumn<String> actionOverride = GeneratedColumn<String>(
    'action_override',
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
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    cardId,
    levelNumber,
    triggerConditionOverride,
    actionOverride,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_national_focus_strengthening_levels';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalNationalFocusStrengtheningLevel> instance, {
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
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('level_number')) {
      context.handle(
        _levelNumberMeta,
        levelNumber.isAcceptableOrUnknown(
          data['level_number']!,
          _levelNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_levelNumberMeta);
    }
    if (data.containsKey('trigger_condition_override')) {
      context.handle(
        _triggerConditionOverrideMeta,
        triggerConditionOverride.isAcceptableOrUnknown(
          data['trigger_condition_override']!,
          _triggerConditionOverrideMeta,
        ),
      );
    }
    if (data.containsKey('action_override')) {
      context.handle(
        _actionOverrideMeta,
        actionOverride.isAcceptableOrUnknown(
          data['action_override']!,
          _actionOverrideMeta,
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, cardId, levelNumber};
  @override
  LocalNationalFocusStrengtheningLevel map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalNationalFocusStrengtheningLevel(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      levelNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level_number'],
      )!,
      triggerConditionOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_condition_override'],
      ),
      actionOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_override'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalNationalFocusStrengtheningLevelsTable createAlias(String alias) {
    return $LocalNationalFocusStrengtheningLevelsTable(attachedDatabase, alias);
  }
}

class LocalNationalFocusStrengtheningLevel extends DataClass
    implements Insertable<LocalNationalFocusStrengtheningLevel> {
  final String userId;
  final String cardId;
  final int levelNumber;
  final String? triggerConditionOverride;
  final String? actionOverride;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalNationalFocusStrengtheningLevel({
    required this.userId,
    required this.cardId,
    required this.levelNumber,
    this.triggerConditionOverride,
    this.actionOverride,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['card_id'] = Variable<String>(cardId);
    map['level_number'] = Variable<int>(levelNumber);
    if (!nullToAbsent || triggerConditionOverride != null) {
      map['trigger_condition_override'] = Variable<String>(
        triggerConditionOverride,
      );
    }
    if (!nullToAbsent || actionOverride != null) {
      map['action_override'] = Variable<String>(actionOverride);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalNationalFocusStrengtheningLevelsCompanion toCompanion(
    bool nullToAbsent,
  ) {
    return LocalNationalFocusStrengtheningLevelsCompanion(
      userId: Value(userId),
      cardId: Value(cardId),
      levelNumber: Value(levelNumber),
      triggerConditionOverride: triggerConditionOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(triggerConditionOverride),
      actionOverride: actionOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(actionOverride),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalNationalFocusStrengtheningLevel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalNationalFocusStrengtheningLevel(
      userId: serializer.fromJson<String>(json['userId']),
      cardId: serializer.fromJson<String>(json['cardId']),
      levelNumber: serializer.fromJson<int>(json['levelNumber']),
      triggerConditionOverride: serializer.fromJson<String?>(
        json['triggerConditionOverride'],
      ),
      actionOverride: serializer.fromJson<String?>(json['actionOverride']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'cardId': serializer.toJson<String>(cardId),
      'levelNumber': serializer.toJson<int>(levelNumber),
      'triggerConditionOverride': serializer.toJson<String?>(
        triggerConditionOverride,
      ),
      'actionOverride': serializer.toJson<String?>(actionOverride),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalNationalFocusStrengtheningLevel copyWith({
    String? userId,
    String? cardId,
    int? levelNumber,
    Value<String?> triggerConditionOverride = const Value.absent(),
    Value<String?> actionOverride = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalNationalFocusStrengtheningLevel(
    userId: userId ?? this.userId,
    cardId: cardId ?? this.cardId,
    levelNumber: levelNumber ?? this.levelNumber,
    triggerConditionOverride: triggerConditionOverride.present
        ? triggerConditionOverride.value
        : this.triggerConditionOverride,
    actionOverride: actionOverride.present
        ? actionOverride.value
        : this.actionOverride,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalNationalFocusStrengtheningLevel copyWithCompanion(
    LocalNationalFocusStrengtheningLevelsCompanion data,
  ) {
    return LocalNationalFocusStrengtheningLevel(
      userId: data.userId.present ? data.userId.value : this.userId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      levelNumber: data.levelNumber.present
          ? data.levelNumber.value
          : this.levelNumber,
      triggerConditionOverride: data.triggerConditionOverride.present
          ? data.triggerConditionOverride.value
          : this.triggerConditionOverride,
      actionOverride: data.actionOverride.present
          ? data.actionOverride.value
          : this.actionOverride,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusStrengtheningLevel(')
          ..write('userId: $userId, ')
          ..write('cardId: $cardId, ')
          ..write('levelNumber: $levelNumber, ')
          ..write('triggerConditionOverride: $triggerConditionOverride, ')
          ..write('actionOverride: $actionOverride, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    cardId,
    levelNumber,
    triggerConditionOverride,
    actionOverride,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalNationalFocusStrengtheningLevel &&
          other.userId == this.userId &&
          other.cardId == this.cardId &&
          other.levelNumber == this.levelNumber &&
          other.triggerConditionOverride == this.triggerConditionOverride &&
          other.actionOverride == this.actionOverride &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalNationalFocusStrengtheningLevelsCompanion
    extends UpdateCompanion<LocalNationalFocusStrengtheningLevel> {
  final Value<String> userId;
  final Value<String> cardId;
  final Value<int> levelNumber;
  final Value<String?> triggerConditionOverride;
  final Value<String?> actionOverride;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalNationalFocusStrengtheningLevelsCompanion({
    this.userId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.levelNumber = const Value.absent(),
    this.triggerConditionOverride = const Value.absent(),
    this.actionOverride = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalNationalFocusStrengtheningLevelsCompanion.insert({
    required String userId,
    required String cardId,
    required int levelNumber,
    this.triggerConditionOverride = const Value.absent(),
    this.actionOverride = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       cardId = Value(cardId),
       levelNumber = Value(levelNumber),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalNationalFocusStrengtheningLevel> custom({
    Expression<String>? userId,
    Expression<String>? cardId,
    Expression<int>? levelNumber,
    Expression<String>? triggerConditionOverride,
    Expression<String>? actionOverride,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (cardId != null) 'card_id': cardId,
      if (levelNumber != null) 'level_number': levelNumber,
      if (triggerConditionOverride != null)
        'trigger_condition_override': triggerConditionOverride,
      if (actionOverride != null) 'action_override': actionOverride,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalNationalFocusStrengtheningLevelsCompanion copyWith({
    Value<String>? userId,
    Value<String>? cardId,
    Value<int>? levelNumber,
    Value<String?>? triggerConditionOverride,
    Value<String?>? actionOverride,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalNationalFocusStrengtheningLevelsCompanion(
      userId: userId ?? this.userId,
      cardId: cardId ?? this.cardId,
      levelNumber: levelNumber ?? this.levelNumber,
      triggerConditionOverride:
          triggerConditionOverride ?? this.triggerConditionOverride,
      actionOverride: actionOverride ?? this.actionOverride,
      createdAt: createdAt ?? this.createdAt,
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
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (levelNumber.present) {
      map['level_number'] = Variable<int>(levelNumber.value);
    }
    if (triggerConditionOverride.present) {
      map['trigger_condition_override'] = Variable<String>(
        triggerConditionOverride.value,
      );
    }
    if (actionOverride.present) {
      map['action_override'] = Variable<String>(actionOverride.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('LocalNationalFocusStrengtheningLevelsCompanion(')
          ..write('userId: $userId, ')
          ..write('cardId: $cardId, ')
          ..write('levelNumber: $levelNumber, ')
          ..write('triggerConditionOverride: $triggerConditionOverride, ')
          ..write('actionOverride: $actionOverride, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalNationalFocusRequirementVersionsTable
    extends LocalNationalFocusRequirementVersions
    with
        TableInfo<
          $LocalNationalFocusRequirementVersionsTable,
          LocalNationalFocusRequirementVersion
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalNationalFocusRequirementVersionsTable(
    this.attachedDatabase, [
    this._alias,
  ]);
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
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionNumberMeta = const VerificationMeta(
    'versionNumber',
  );
  @override
  late final GeneratedColumn<int> versionNumber = GeneratedColumn<int>(
    'version_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strengtheningLevelNumberMeta =
      const VerificationMeta('strengtheningLevelNumber');
  @override
  late final GeneratedColumn<int> strengtheningLevelNumber =
      GeneratedColumn<int>(
        'strengthening_level_number',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _effectiveTriggerConditionMeta =
      const VerificationMeta('effectiveTriggerCondition');
  @override
  late final GeneratedColumn<String> effectiveTriggerCondition =
      GeneratedColumn<String>(
        'effective_trigger_condition',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _effectiveActionMeta = const VerificationMeta(
    'effectiveAction',
  );
  @override
  late final GeneratedColumn<String> effectiveAction = GeneratedColumn<String>(
    'effective_action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exceptionNotesMeta = const VerificationMeta(
    'exceptionNotes',
  );
  @override
  late final GeneratedColumn<String> exceptionNotes = GeneratedColumn<String>(
    'exception_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effectiveFromMeta = const VerificationMeta(
    'effectiveFrom',
  );
  @override
  late final GeneratedColumn<DateTime> effectiveFrom =
      GeneratedColumn<DateTime>(
        'effective_from',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _effectiveUntilMeta = const VerificationMeta(
    'effectiveUntil',
  );
  @override
  late final GeneratedColumn<DateTime> effectiveUntil =
      GeneratedColumn<DateTime>(
        'effective_until',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    cardId,
    versionNumber,
    strengtheningLevelNumber,
    effectiveTriggerCondition,
    effectiveAction,
    scope,
    exceptionNotes,
    effectiveFrom,
    effectiveUntil,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_national_focus_requirement_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalNationalFocusRequirementVersion> instance, {
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
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('version_number')) {
      context.handle(
        _versionNumberMeta,
        versionNumber.isAcceptableOrUnknown(
          data['version_number']!,
          _versionNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionNumberMeta);
    }
    if (data.containsKey('strengthening_level_number')) {
      context.handle(
        _strengtheningLevelNumberMeta,
        strengtheningLevelNumber.isAcceptableOrUnknown(
          data['strengthening_level_number']!,
          _strengtheningLevelNumberMeta,
        ),
      );
    }
    if (data.containsKey('effective_trigger_condition')) {
      context.handle(
        _effectiveTriggerConditionMeta,
        effectiveTriggerCondition.isAcceptableOrUnknown(
          data['effective_trigger_condition']!,
          _effectiveTriggerConditionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveTriggerConditionMeta);
    }
    if (data.containsKey('effective_action')) {
      context.handle(
        _effectiveActionMeta,
        effectiveAction.isAcceptableOrUnknown(
          data['effective_action']!,
          _effectiveActionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveActionMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('exception_notes')) {
      context.handle(
        _exceptionNotesMeta,
        exceptionNotes.isAcceptableOrUnknown(
          data['exception_notes']!,
          _exceptionNotesMeta,
        ),
      );
    }
    if (data.containsKey('effective_from')) {
      context.handle(
        _effectiveFromMeta,
        effectiveFrom.isAcceptableOrUnknown(
          data['effective_from']!,
          _effectiveFromMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveFromMeta);
    }
    if (data.containsKey('effective_until')) {
      context.handle(
        _effectiveUntilMeta,
        effectiveUntil.isAcceptableOrUnknown(
          data['effective_until']!,
          _effectiveUntilMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  LocalNationalFocusRequirementVersion map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalNationalFocusRequirementVersion(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      versionNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_number'],
      )!,
      strengtheningLevelNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}strengthening_level_number'],
      ),
      effectiveTriggerCondition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_trigger_condition'],
      )!,
      effectiveAction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_action'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      ),
      exceptionNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exception_notes'],
      ),
      effectiveFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}effective_from'],
      )!,
      effectiveUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}effective_until'],
      ),
    );
  }

  @override
  $LocalNationalFocusRequirementVersionsTable createAlias(String alias) {
    return $LocalNationalFocusRequirementVersionsTable(attachedDatabase, alias);
  }
}

class LocalNationalFocusRequirementVersion extends DataClass
    implements Insertable<LocalNationalFocusRequirementVersion> {
  final String userId;
  final String id;
  final String cardId;
  final int versionNumber;
  final int? strengtheningLevelNumber;
  final String effectiveTriggerCondition;
  final String effectiveAction;
  final String? scope;
  final String? exceptionNotes;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
  const LocalNationalFocusRequirementVersion({
    required this.userId,
    required this.id,
    required this.cardId,
    required this.versionNumber,
    this.strengtheningLevelNumber,
    required this.effectiveTriggerCondition,
    required this.effectiveAction,
    this.scope,
    this.exceptionNotes,
    required this.effectiveFrom,
    this.effectiveUntil,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['card_id'] = Variable<String>(cardId);
    map['version_number'] = Variable<int>(versionNumber);
    if (!nullToAbsent || strengtheningLevelNumber != null) {
      map['strengthening_level_number'] = Variable<int>(
        strengtheningLevelNumber,
      );
    }
    map['effective_trigger_condition'] = Variable<String>(
      effectiveTriggerCondition,
    );
    map['effective_action'] = Variable<String>(effectiveAction);
    if (!nullToAbsent || scope != null) {
      map['scope'] = Variable<String>(scope);
    }
    if (!nullToAbsent || exceptionNotes != null) {
      map['exception_notes'] = Variable<String>(exceptionNotes);
    }
    map['effective_from'] = Variable<DateTime>(effectiveFrom);
    if (!nullToAbsent || effectiveUntil != null) {
      map['effective_until'] = Variable<DateTime>(effectiveUntil);
    }
    return map;
  }

  LocalNationalFocusRequirementVersionsCompanion toCompanion(
    bool nullToAbsent,
  ) {
    return LocalNationalFocusRequirementVersionsCompanion(
      userId: Value(userId),
      id: Value(id),
      cardId: Value(cardId),
      versionNumber: Value(versionNumber),
      strengtheningLevelNumber: strengtheningLevelNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(strengtheningLevelNumber),
      effectiveTriggerCondition: Value(effectiveTriggerCondition),
      effectiveAction: Value(effectiveAction),
      scope: scope == null && nullToAbsent
          ? const Value.absent()
          : Value(scope),
      exceptionNotes: exceptionNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(exceptionNotes),
      effectiveFrom: Value(effectiveFrom),
      effectiveUntil: effectiveUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveUntil),
    );
  }

  factory LocalNationalFocusRequirementVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalNationalFocusRequirementVersion(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      versionNumber: serializer.fromJson<int>(json['versionNumber']),
      strengtheningLevelNumber: serializer.fromJson<int?>(
        json['strengtheningLevelNumber'],
      ),
      effectiveTriggerCondition: serializer.fromJson<String>(
        json['effectiveTriggerCondition'],
      ),
      effectiveAction: serializer.fromJson<String>(json['effectiveAction']),
      scope: serializer.fromJson<String?>(json['scope']),
      exceptionNotes: serializer.fromJson<String?>(json['exceptionNotes']),
      effectiveFrom: serializer.fromJson<DateTime>(json['effectiveFrom']),
      effectiveUntil: serializer.fromJson<DateTime?>(json['effectiveUntil']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'cardId': serializer.toJson<String>(cardId),
      'versionNumber': serializer.toJson<int>(versionNumber),
      'strengtheningLevelNumber': serializer.toJson<int?>(
        strengtheningLevelNumber,
      ),
      'effectiveTriggerCondition': serializer.toJson<String>(
        effectiveTriggerCondition,
      ),
      'effectiveAction': serializer.toJson<String>(effectiveAction),
      'scope': serializer.toJson<String?>(scope),
      'exceptionNotes': serializer.toJson<String?>(exceptionNotes),
      'effectiveFrom': serializer.toJson<DateTime>(effectiveFrom),
      'effectiveUntil': serializer.toJson<DateTime?>(effectiveUntil),
    };
  }

  LocalNationalFocusRequirementVersion copyWith({
    String? userId,
    String? id,
    String? cardId,
    int? versionNumber,
    Value<int?> strengtheningLevelNumber = const Value.absent(),
    String? effectiveTriggerCondition,
    String? effectiveAction,
    Value<String?> scope = const Value.absent(),
    Value<String?> exceptionNotes = const Value.absent(),
    DateTime? effectiveFrom,
    Value<DateTime?> effectiveUntil = const Value.absent(),
  }) => LocalNationalFocusRequirementVersion(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    cardId: cardId ?? this.cardId,
    versionNumber: versionNumber ?? this.versionNumber,
    strengtheningLevelNumber: strengtheningLevelNumber.present
        ? strengtheningLevelNumber.value
        : this.strengtheningLevelNumber,
    effectiveTriggerCondition:
        effectiveTriggerCondition ?? this.effectiveTriggerCondition,
    effectiveAction: effectiveAction ?? this.effectiveAction,
    scope: scope.present ? scope.value : this.scope,
    exceptionNotes: exceptionNotes.present
        ? exceptionNotes.value
        : this.exceptionNotes,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    effectiveUntil: effectiveUntil.present
        ? effectiveUntil.value
        : this.effectiveUntil,
  );
  LocalNationalFocusRequirementVersion copyWithCompanion(
    LocalNationalFocusRequirementVersionsCompanion data,
  ) {
    return LocalNationalFocusRequirementVersion(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      versionNumber: data.versionNumber.present
          ? data.versionNumber.value
          : this.versionNumber,
      strengtheningLevelNumber: data.strengtheningLevelNumber.present
          ? data.strengtheningLevelNumber.value
          : this.strengtheningLevelNumber,
      effectiveTriggerCondition: data.effectiveTriggerCondition.present
          ? data.effectiveTriggerCondition.value
          : this.effectiveTriggerCondition,
      effectiveAction: data.effectiveAction.present
          ? data.effectiveAction.value
          : this.effectiveAction,
      scope: data.scope.present ? data.scope.value : this.scope,
      exceptionNotes: data.exceptionNotes.present
          ? data.exceptionNotes.value
          : this.exceptionNotes,
      effectiveFrom: data.effectiveFrom.present
          ? data.effectiveFrom.value
          : this.effectiveFrom,
      effectiveUntil: data.effectiveUntil.present
          ? data.effectiveUntil.value
          : this.effectiveUntil,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusRequirementVersion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('versionNumber: $versionNumber, ')
          ..write('strengtheningLevelNumber: $strengtheningLevelNumber, ')
          ..write('effectiveTriggerCondition: $effectiveTriggerCondition, ')
          ..write('effectiveAction: $effectiveAction, ')
          ..write('scope: $scope, ')
          ..write('exceptionNotes: $exceptionNotes, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveUntil: $effectiveUntil')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    cardId,
    versionNumber,
    strengtheningLevelNumber,
    effectiveTriggerCondition,
    effectiveAction,
    scope,
    exceptionNotes,
    effectiveFrom,
    effectiveUntil,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalNationalFocusRequirementVersion &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.versionNumber == this.versionNumber &&
          other.strengtheningLevelNumber == this.strengtheningLevelNumber &&
          other.effectiveTriggerCondition == this.effectiveTriggerCondition &&
          other.effectiveAction == this.effectiveAction &&
          other.scope == this.scope &&
          other.exceptionNotes == this.exceptionNotes &&
          other.effectiveFrom == this.effectiveFrom &&
          other.effectiveUntil == this.effectiveUntil);
}

class LocalNationalFocusRequirementVersionsCompanion
    extends UpdateCompanion<LocalNationalFocusRequirementVersion> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> cardId;
  final Value<int> versionNumber;
  final Value<int?> strengtheningLevelNumber;
  final Value<String> effectiveTriggerCondition;
  final Value<String> effectiveAction;
  final Value<String?> scope;
  final Value<String?> exceptionNotes;
  final Value<DateTime> effectiveFrom;
  final Value<DateTime?> effectiveUntil;
  final Value<int> rowid;
  const LocalNationalFocusRequirementVersionsCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.versionNumber = const Value.absent(),
    this.strengtheningLevelNumber = const Value.absent(),
    this.effectiveTriggerCondition = const Value.absent(),
    this.effectiveAction = const Value.absent(),
    this.scope = const Value.absent(),
    this.exceptionNotes = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.effectiveUntil = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalNationalFocusRequirementVersionsCompanion.insert({
    required String userId,
    required String id,
    required String cardId,
    required int versionNumber,
    this.strengtheningLevelNumber = const Value.absent(),
    required String effectiveTriggerCondition,
    required String effectiveAction,
    this.scope = const Value.absent(),
    this.exceptionNotes = const Value.absent(),
    required DateTime effectiveFrom,
    this.effectiveUntil = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       cardId = Value(cardId),
       versionNumber = Value(versionNumber),
       effectiveTriggerCondition = Value(effectiveTriggerCondition),
       effectiveAction = Value(effectiveAction),
       effectiveFrom = Value(effectiveFrom);
  static Insertable<LocalNationalFocusRequirementVersion> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? cardId,
    Expression<int>? versionNumber,
    Expression<int>? strengtheningLevelNumber,
    Expression<String>? effectiveTriggerCondition,
    Expression<String>? effectiveAction,
    Expression<String>? scope,
    Expression<String>? exceptionNotes,
    Expression<DateTime>? effectiveFrom,
    Expression<DateTime>? effectiveUntil,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (versionNumber != null) 'version_number': versionNumber,
      if (strengtheningLevelNumber != null)
        'strengthening_level_number': strengtheningLevelNumber,
      if (effectiveTriggerCondition != null)
        'effective_trigger_condition': effectiveTriggerCondition,
      if (effectiveAction != null) 'effective_action': effectiveAction,
      if (scope != null) 'scope': scope,
      if (exceptionNotes != null) 'exception_notes': exceptionNotes,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (effectiveUntil != null) 'effective_until': effectiveUntil,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalNationalFocusRequirementVersionsCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? cardId,
    Value<int>? versionNumber,
    Value<int?>? strengtheningLevelNumber,
    Value<String>? effectiveTriggerCondition,
    Value<String>? effectiveAction,
    Value<String?>? scope,
    Value<String?>? exceptionNotes,
    Value<DateTime>? effectiveFrom,
    Value<DateTime?>? effectiveUntil,
    Value<int>? rowid,
  }) {
    return LocalNationalFocusRequirementVersionsCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      versionNumber: versionNumber ?? this.versionNumber,
      strengtheningLevelNumber:
          strengtheningLevelNumber ?? this.strengtheningLevelNumber,
      effectiveTriggerCondition:
          effectiveTriggerCondition ?? this.effectiveTriggerCondition,
      effectiveAction: effectiveAction ?? this.effectiveAction,
      scope: scope ?? this.scope,
      exceptionNotes: exceptionNotes ?? this.exceptionNotes,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveUntil: effectiveUntil ?? this.effectiveUntil,
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
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (versionNumber.present) {
      map['version_number'] = Variable<int>(versionNumber.value);
    }
    if (strengtheningLevelNumber.present) {
      map['strengthening_level_number'] = Variable<int>(
        strengtheningLevelNumber.value,
      );
    }
    if (effectiveTriggerCondition.present) {
      map['effective_trigger_condition'] = Variable<String>(
        effectiveTriggerCondition.value,
      );
    }
    if (effectiveAction.present) {
      map['effective_action'] = Variable<String>(effectiveAction.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (exceptionNotes.present) {
      map['exception_notes'] = Variable<String>(exceptionNotes.value);
    }
    if (effectiveFrom.present) {
      map['effective_from'] = Variable<DateTime>(effectiveFrom.value);
    }
    if (effectiveUntil.present) {
      map['effective_until'] = Variable<DateTime>(effectiveUntil.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusRequirementVersionsCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('versionNumber: $versionNumber, ')
          ..write('strengtheningLevelNumber: $strengtheningLevelNumber, ')
          ..write('effectiveTriggerCondition: $effectiveTriggerCondition, ')
          ..write('effectiveAction: $effectiveAction, ')
          ..write('scope: $scope, ')
          ..write('exceptionNotes: $exceptionNotes, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveUntil: $effectiveUntil, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalNationalFocusMaintenanceTable extends LocalNationalFocusMaintenance
    with
        TableInfo<
          $LocalNationalFocusMaintenanceTable,
          LocalNationalFocusMaintenanceData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalNationalFocusMaintenanceTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSettledCheckpointAtMeta =
      const VerificationMeta('lastSettledCheckpointAt');
  @override
  late final GeneratedColumn<DateTime> lastSettledCheckpointAt =
      GeneratedColumn<DateTime>(
        'last_settled_checkpoint_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [userId, lastSettledCheckpointAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_national_focus_maintenance';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalNationalFocusMaintenanceData> instance, {
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
    if (data.containsKey('last_settled_checkpoint_at')) {
      context.handle(
        _lastSettledCheckpointAtMeta,
        lastSettledCheckpointAt.isAcceptableOrUnknown(
          data['last_settled_checkpoint_at']!,
          _lastSettledCheckpointAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSettledCheckpointAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  LocalNationalFocusMaintenanceData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalNationalFocusMaintenanceData(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lastSettledCheckpointAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_settled_checkpoint_at'],
      )!,
    );
  }

  @override
  $LocalNationalFocusMaintenanceTable createAlias(String alias) {
    return $LocalNationalFocusMaintenanceTable(attachedDatabase, alias);
  }
}

class LocalNationalFocusMaintenanceData extends DataClass
    implements Insertable<LocalNationalFocusMaintenanceData> {
  final String userId;
  final DateTime lastSettledCheckpointAt;
  const LocalNationalFocusMaintenanceData({
    required this.userId,
    required this.lastSettledCheckpointAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['last_settled_checkpoint_at'] = Variable<DateTime>(
      lastSettledCheckpointAt,
    );
    return map;
  }

  LocalNationalFocusMaintenanceCompanion toCompanion(bool nullToAbsent) {
    return LocalNationalFocusMaintenanceCompanion(
      userId: Value(userId),
      lastSettledCheckpointAt: Value(lastSettledCheckpointAt),
    );
  }

  factory LocalNationalFocusMaintenanceData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalNationalFocusMaintenanceData(
      userId: serializer.fromJson<String>(json['userId']),
      lastSettledCheckpointAt: serializer.fromJson<DateTime>(
        json['lastSettledCheckpointAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'lastSettledCheckpointAt': serializer.toJson<DateTime>(
        lastSettledCheckpointAt,
      ),
    };
  }

  LocalNationalFocusMaintenanceData copyWith({
    String? userId,
    DateTime? lastSettledCheckpointAt,
  }) => LocalNationalFocusMaintenanceData(
    userId: userId ?? this.userId,
    lastSettledCheckpointAt:
        lastSettledCheckpointAt ?? this.lastSettledCheckpointAt,
  );
  LocalNationalFocusMaintenanceData copyWithCompanion(
    LocalNationalFocusMaintenanceCompanion data,
  ) {
    return LocalNationalFocusMaintenanceData(
      userId: data.userId.present ? data.userId.value : this.userId,
      lastSettledCheckpointAt: data.lastSettledCheckpointAt.present
          ? data.lastSettledCheckpointAt.value
          : this.lastSettledCheckpointAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusMaintenanceData(')
          ..write('userId: $userId, ')
          ..write('lastSettledCheckpointAt: $lastSettledCheckpointAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, lastSettledCheckpointAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalNationalFocusMaintenanceData &&
          other.userId == this.userId &&
          other.lastSettledCheckpointAt == this.lastSettledCheckpointAt);
}

class LocalNationalFocusMaintenanceCompanion
    extends UpdateCompanion<LocalNationalFocusMaintenanceData> {
  final Value<String> userId;
  final Value<DateTime> lastSettledCheckpointAt;
  final Value<int> rowid;
  const LocalNationalFocusMaintenanceCompanion({
    this.userId = const Value.absent(),
    this.lastSettledCheckpointAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalNationalFocusMaintenanceCompanion.insert({
    required String userId,
    required DateTime lastSettledCheckpointAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       lastSettledCheckpointAt = Value(lastSettledCheckpointAt);
  static Insertable<LocalNationalFocusMaintenanceData> custom({
    Expression<String>? userId,
    Expression<DateTime>? lastSettledCheckpointAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (lastSettledCheckpointAt != null)
        'last_settled_checkpoint_at': lastSettledCheckpointAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalNationalFocusMaintenanceCompanion copyWith({
    Value<String>? userId,
    Value<DateTime>? lastSettledCheckpointAt,
    Value<int>? rowid,
  }) {
    return LocalNationalFocusMaintenanceCompanion(
      userId: userId ?? this.userId,
      lastSettledCheckpointAt:
          lastSettledCheckpointAt ?? this.lastSettledCheckpointAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lastSettledCheckpointAt.present) {
      map['last_settled_checkpoint_at'] = Variable<DateTime>(
        lastSettledCheckpointAt.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusMaintenanceCompanion(')
          ..write('userId: $userId, ')
          ..write('lastSettledCheckpointAt: $lastSettledCheckpointAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalNationalFocusFailuresTable extends LocalNationalFocusFailures
    with
        TableInfo<$LocalNationalFocusFailuresTable, LocalNationalFocusFailure> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalNationalFocusFailuresTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkpointAtMeta = const VerificationMeta(
    'checkpointAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkpointAt = GeneratedColumn<DateTime>(
    'checkpoint_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _causeMeta = const VerificationMeta('cause');
  @override
  late final GeneratedColumn<String> cause = GeneratedColumn<String>(
    'cause',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _sharedExplanationMeta = const VerificationMeta(
    'sharedExplanation',
  );
  @override
  late final GeneratedColumn<String> sharedExplanation =
      GeneratedColumn<String>(
        'shared_explanation',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _treeSnapshotMeta = const VerificationMeta(
    'treeSnapshot',
  );
  @override
  late final GeneratedColumn<String> treeSnapshot = GeneratedColumn<String>(
    'tree_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    batchId,
    cardId,
    checkpointAt,
    cause,
    failureReason,
    sharedExplanation,
    treeSnapshot,
    reviewDisposition,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_national_focus_failures';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalNationalFocusFailure> instance, {
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
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('checkpoint_at')) {
      context.handle(
        _checkpointAtMeta,
        checkpointAt.isAcceptableOrUnknown(
          data['checkpoint_at']!,
          _checkpointAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_checkpointAtMeta);
    }
    if (data.containsKey('cause')) {
      context.handle(
        _causeMeta,
        cause.isAcceptableOrUnknown(data['cause']!, _causeMeta),
      );
    } else if (isInserting) {
      context.missing(_causeMeta);
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
    if (data.containsKey('shared_explanation')) {
      context.handle(
        _sharedExplanationMeta,
        sharedExplanation.isAcceptableOrUnknown(
          data['shared_explanation']!,
          _sharedExplanationMeta,
        ),
      );
    }
    if (data.containsKey('tree_snapshot')) {
      context.handle(
        _treeSnapshotMeta,
        treeSnapshot.isAcceptableOrUnknown(
          data['tree_snapshot']!,
          _treeSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_treeSnapshotMeta);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, id};
  @override
  LocalNationalFocusFailure map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalNationalFocusFailure(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      checkpointAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checkpoint_at'],
      )!,
      cause: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cause'],
      )!,
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      sharedExplanation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shared_explanation'],
      ),
      treeSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tree_snapshot'],
      )!,
      reviewDisposition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_disposition'],
      )!,
    );
  }

  @override
  $LocalNationalFocusFailuresTable createAlias(String alias) {
    return $LocalNationalFocusFailuresTable(attachedDatabase, alias);
  }
}

class LocalNationalFocusFailure extends DataClass
    implements Insertable<LocalNationalFocusFailure> {
  final String userId;
  final String id;
  final String batchId;
  final String cardId;
  final DateTime checkpointAt;
  final String cause;
  final String? failureReason;
  final String? sharedExplanation;
  final String treeSnapshot;
  final String reviewDisposition;
  const LocalNationalFocusFailure({
    required this.userId,
    required this.id,
    required this.batchId,
    required this.cardId,
    required this.checkpointAt,
    required this.cause,
    this.failureReason,
    this.sharedExplanation,
    required this.treeSnapshot,
    required this.reviewDisposition,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['id'] = Variable<String>(id);
    map['batch_id'] = Variable<String>(batchId);
    map['card_id'] = Variable<String>(cardId);
    map['checkpoint_at'] = Variable<DateTime>(checkpointAt);
    map['cause'] = Variable<String>(cause);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || sharedExplanation != null) {
      map['shared_explanation'] = Variable<String>(sharedExplanation);
    }
    map['tree_snapshot'] = Variable<String>(treeSnapshot);
    map['review_disposition'] = Variable<String>(reviewDisposition);
    return map;
  }

  LocalNationalFocusFailuresCompanion toCompanion(bool nullToAbsent) {
    return LocalNationalFocusFailuresCompanion(
      userId: Value(userId),
      id: Value(id),
      batchId: Value(batchId),
      cardId: Value(cardId),
      checkpointAt: Value(checkpointAt),
      cause: Value(cause),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      sharedExplanation: sharedExplanation == null && nullToAbsent
          ? const Value.absent()
          : Value(sharedExplanation),
      treeSnapshot: Value(treeSnapshot),
      reviewDisposition: Value(reviewDisposition),
    );
  }

  factory LocalNationalFocusFailure.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalNationalFocusFailure(
      userId: serializer.fromJson<String>(json['userId']),
      id: serializer.fromJson<String>(json['id']),
      batchId: serializer.fromJson<String>(json['batchId']),
      cardId: serializer.fromJson<String>(json['cardId']),
      checkpointAt: serializer.fromJson<DateTime>(json['checkpointAt']),
      cause: serializer.fromJson<String>(json['cause']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      sharedExplanation: serializer.fromJson<String?>(
        json['sharedExplanation'],
      ),
      treeSnapshot: serializer.fromJson<String>(json['treeSnapshot']),
      reviewDisposition: serializer.fromJson<String>(json['reviewDisposition']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'id': serializer.toJson<String>(id),
      'batchId': serializer.toJson<String>(batchId),
      'cardId': serializer.toJson<String>(cardId),
      'checkpointAt': serializer.toJson<DateTime>(checkpointAt),
      'cause': serializer.toJson<String>(cause),
      'failureReason': serializer.toJson<String?>(failureReason),
      'sharedExplanation': serializer.toJson<String?>(sharedExplanation),
      'treeSnapshot': serializer.toJson<String>(treeSnapshot),
      'reviewDisposition': serializer.toJson<String>(reviewDisposition),
    };
  }

  LocalNationalFocusFailure copyWith({
    String? userId,
    String? id,
    String? batchId,
    String? cardId,
    DateTime? checkpointAt,
    String? cause,
    Value<String?> failureReason = const Value.absent(),
    Value<String?> sharedExplanation = const Value.absent(),
    String? treeSnapshot,
    String? reviewDisposition,
  }) => LocalNationalFocusFailure(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    batchId: batchId ?? this.batchId,
    cardId: cardId ?? this.cardId,
    checkpointAt: checkpointAt ?? this.checkpointAt,
    cause: cause ?? this.cause,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    sharedExplanation: sharedExplanation.present
        ? sharedExplanation.value
        : this.sharedExplanation,
    treeSnapshot: treeSnapshot ?? this.treeSnapshot,
    reviewDisposition: reviewDisposition ?? this.reviewDisposition,
  );
  LocalNationalFocusFailure copyWithCompanion(
    LocalNationalFocusFailuresCompanion data,
  ) {
    return LocalNationalFocusFailure(
      userId: data.userId.present ? data.userId.value : this.userId,
      id: data.id.present ? data.id.value : this.id,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      checkpointAt: data.checkpointAt.present
          ? data.checkpointAt.value
          : this.checkpointAt,
      cause: data.cause.present ? data.cause.value : this.cause,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      sharedExplanation: data.sharedExplanation.present
          ? data.sharedExplanation.value
          : this.sharedExplanation,
      treeSnapshot: data.treeSnapshot.present
          ? data.treeSnapshot.value
          : this.treeSnapshot,
      reviewDisposition: data.reviewDisposition.present
          ? data.reviewDisposition.value
          : this.reviewDisposition,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusFailure(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('cardId: $cardId, ')
          ..write('checkpointAt: $checkpointAt, ')
          ..write('cause: $cause, ')
          ..write('failureReason: $failureReason, ')
          ..write('sharedExplanation: $sharedExplanation, ')
          ..write('treeSnapshot: $treeSnapshot, ')
          ..write('reviewDisposition: $reviewDisposition')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    batchId,
    cardId,
    checkpointAt,
    cause,
    failureReason,
    sharedExplanation,
    treeSnapshot,
    reviewDisposition,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalNationalFocusFailure &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.batchId == this.batchId &&
          other.cardId == this.cardId &&
          other.checkpointAt == this.checkpointAt &&
          other.cause == this.cause &&
          other.failureReason == this.failureReason &&
          other.sharedExplanation == this.sharedExplanation &&
          other.treeSnapshot == this.treeSnapshot &&
          other.reviewDisposition == this.reviewDisposition);
}

class LocalNationalFocusFailuresCompanion
    extends UpdateCompanion<LocalNationalFocusFailure> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> batchId;
  final Value<String> cardId;
  final Value<DateTime> checkpointAt;
  final Value<String> cause;
  final Value<String?> failureReason;
  final Value<String?> sharedExplanation;
  final Value<String> treeSnapshot;
  final Value<String> reviewDisposition;
  final Value<int> rowid;
  const LocalNationalFocusFailuresCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.batchId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.checkpointAt = const Value.absent(),
    this.cause = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.sharedExplanation = const Value.absent(),
    this.treeSnapshot = const Value.absent(),
    this.reviewDisposition = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalNationalFocusFailuresCompanion.insert({
    required String userId,
    required String id,
    required String batchId,
    required String cardId,
    required DateTime checkpointAt,
    required String cause,
    this.failureReason = const Value.absent(),
    this.sharedExplanation = const Value.absent(),
    required String treeSnapshot,
    this.reviewDisposition = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       id = Value(id),
       batchId = Value(batchId),
       cardId = Value(cardId),
       checkpointAt = Value(checkpointAt),
       cause = Value(cause),
       treeSnapshot = Value(treeSnapshot);
  static Insertable<LocalNationalFocusFailure> custom({
    Expression<String>? userId,
    Expression<String>? id,
    Expression<String>? batchId,
    Expression<String>? cardId,
    Expression<DateTime>? checkpointAt,
    Expression<String>? cause,
    Expression<String>? failureReason,
    Expression<String>? sharedExplanation,
    Expression<String>? treeSnapshot,
    Expression<String>? reviewDisposition,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (batchId != null) 'batch_id': batchId,
      if (cardId != null) 'card_id': cardId,
      if (checkpointAt != null) 'checkpoint_at': checkpointAt,
      if (cause != null) 'cause': cause,
      if (failureReason != null) 'failure_reason': failureReason,
      if (sharedExplanation != null) 'shared_explanation': sharedExplanation,
      if (treeSnapshot != null) 'tree_snapshot': treeSnapshot,
      if (reviewDisposition != null) 'review_disposition': reviewDisposition,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalNationalFocusFailuresCompanion copyWith({
    Value<String>? userId,
    Value<String>? id,
    Value<String>? batchId,
    Value<String>? cardId,
    Value<DateTime>? checkpointAt,
    Value<String>? cause,
    Value<String?>? failureReason,
    Value<String?>? sharedExplanation,
    Value<String>? treeSnapshot,
    Value<String>? reviewDisposition,
    Value<int>? rowid,
  }) {
    return LocalNationalFocusFailuresCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      cardId: cardId ?? this.cardId,
      checkpointAt: checkpointAt ?? this.checkpointAt,
      cause: cause ?? this.cause,
      failureReason: failureReason ?? this.failureReason,
      sharedExplanation: sharedExplanation ?? this.sharedExplanation,
      treeSnapshot: treeSnapshot ?? this.treeSnapshot,
      reviewDisposition: reviewDisposition ?? this.reviewDisposition,
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
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (checkpointAt.present) {
      map['checkpoint_at'] = Variable<DateTime>(checkpointAt.value);
    }
    if (cause.present) {
      map['cause'] = Variable<String>(cause.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (sharedExplanation.present) {
      map['shared_explanation'] = Variable<String>(sharedExplanation.value);
    }
    if (treeSnapshot.present) {
      map['tree_snapshot'] = Variable<String>(treeSnapshot.value);
    }
    if (reviewDisposition.present) {
      map['review_disposition'] = Variable<String>(reviewDisposition.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalNationalFocusFailuresCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('cardId: $cardId, ')
          ..write('checkpointAt: $checkpointAt, ')
          ..write('cause: $cause, ')
          ..write('failureReason: $failureReason, ')
          ..write('sharedExplanation: $sharedExplanation, ')
          ..write('treeSnapshot: $treeSnapshot, ')
          ..write('reviewDisposition: $reviewDisposition, ')
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
  static const VerificationMeta _configurationBasisSourceIdMeta =
      const VerificationMeta('configurationBasisSourceId');
  @override
  late final GeneratedColumn<String> configurationBasisSourceId =
      GeneratedColumn<String>(
        'configuration_basis_source_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _outcomeBasisSourceIdMeta =
      const VerificationMeta('outcomeBasisSourceId');
  @override
  late final GeneratedColumn<String> outcomeBasisSourceId =
      GeneratedColumn<String>(
        'outcome_basis_source_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
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
    configurationBasisSourceId,
    outcomeBasisSourceId,
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
    if (data.containsKey('configuration_basis_source_id')) {
      context.handle(
        _configurationBasisSourceIdMeta,
        configurationBasisSourceId.isAcceptableOrUnknown(
          data['configuration_basis_source_id']!,
          _configurationBasisSourceIdMeta,
        ),
      );
    }
    if (data.containsKey('outcome_basis_source_id')) {
      context.handle(
        _outcomeBasisSourceIdMeta,
        outcomeBasisSourceId.isAcceptableOrUnknown(
          data['outcome_basis_source_id']!,
          _outcomeBasisSourceIdMeta,
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
      configurationBasisSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}configuration_basis_source_id'],
      ),
      outcomeBasisSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome_basis_source_id'],
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
  final String? configurationBasisSourceId;
  final String? outcomeBasisSourceId;
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
    this.configurationBasisSourceId,
    this.outcomeBasisSourceId,
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
    if (!nullToAbsent || configurationBasisSourceId != null) {
      map['configuration_basis_source_id'] = Variable<String>(
        configurationBasisSourceId,
      );
    }
    if (!nullToAbsent || outcomeBasisSourceId != null) {
      map['outcome_basis_source_id'] = Variable<String>(outcomeBasisSourceId);
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
      configurationBasisSourceId:
          configurationBasisSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(configurationBasisSourceId),
      outcomeBasisSourceId: outcomeBasisSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(outcomeBasisSourceId),
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
      configurationBasisSourceId: serializer.fromJson<String?>(
        json['configurationBasisSourceId'],
      ),
      outcomeBasisSourceId: serializer.fromJson<String?>(
        json['outcomeBasisSourceId'],
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
      'configurationBasisSourceId': serializer.toJson<String?>(
        configurationBasisSourceId,
      ),
      'outcomeBasisSourceId': serializer.toJson<String?>(outcomeBasisSourceId),
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
    Value<String?> configurationBasisSourceId = const Value.absent(),
    Value<String?> outcomeBasisSourceId = const Value.absent(),
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
    configurationBasisSourceId: configurationBasisSourceId.present
        ? configurationBasisSourceId.value
        : this.configurationBasisSourceId,
    outcomeBasisSourceId: outcomeBasisSourceId.present
        ? outcomeBasisSourceId.value
        : this.outcomeBasisSourceId,
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
      configurationBasisSourceId: data.configurationBasisSourceId.present
          ? data.configurationBasisSourceId.value
          : this.configurationBasisSourceId,
      outcomeBasisSourceId: data.outcomeBasisSourceId.present
          ? data.outcomeBasisSourceId.value
          : this.outcomeBasisSourceId,
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
          ..write('reviewDispositionUpdatedAt: $reviewDispositionUpdatedAt, ')
          ..write('configurationBasisSourceId: $configurationBasisSourceId, ')
          ..write('outcomeBasisSourceId: $outcomeBasisSourceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
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
    configurationBasisSourceId,
    outcomeBasisSourceId,
  ]);
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
          other.reviewDispositionUpdatedAt == this.reviewDispositionUpdatedAt &&
          other.configurationBasisSourceId == this.configurationBasisSourceId &&
          other.outcomeBasisSourceId == this.outcomeBasisSourceId);
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
  final Value<String?> configurationBasisSourceId;
  final Value<String?> outcomeBasisSourceId;
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
    this.configurationBasisSourceId = const Value.absent(),
    this.outcomeBasisSourceId = const Value.absent(),
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
    this.configurationBasisSourceId = const Value.absent(),
    this.outcomeBasisSourceId = const Value.absent(),
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
    Expression<String>? configurationBasisSourceId,
    Expression<String>? outcomeBasisSourceId,
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
      if (configurationBasisSourceId != null)
        'configuration_basis_source_id': configurationBasisSourceId,
      if (outcomeBasisSourceId != null)
        'outcome_basis_source_id': outcomeBasisSourceId,
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
    Value<String?>? configurationBasisSourceId,
    Value<String?>? outcomeBasisSourceId,
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
      configurationBasisSourceId:
          configurationBasisSourceId ?? this.configurationBasisSourceId,
      outcomeBasisSourceId: outcomeBasisSourceId ?? this.outcomeBasisSourceId,
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
    if (configurationBasisSourceId.present) {
      map['configuration_basis_source_id'] = Variable<String>(
        configurationBasisSourceId.value,
      );
    }
    if (outcomeBasisSourceId.present) {
      map['outcome_basis_source_id'] = Variable<String>(
        outcomeBasisSourceId.value,
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
          ..write('configurationBasisSourceId: $configurationBasisSourceId, ')
          ..write('outcomeBasisSourceId: $outcomeBasisSourceId, ')
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
  static const VerificationMeta _configurationBasisSourceIdMeta =
      const VerificationMeta('configurationBasisSourceId');
  @override
  late final GeneratedColumn<String> configurationBasisSourceId =
      GeneratedColumn<String>(
        'configuration_basis_source_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
    reviewDisposition,
    reviewDispositionUpdatedAt,
    configurationBasisSourceId,
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
    if (data.containsKey('configuration_basis_source_id')) {
      context.handle(
        _configurationBasisSourceIdMeta,
        configurationBasisSourceId.isAcceptableOrUnknown(
          data['configuration_basis_source_id']!,
          _configurationBasisSourceIdMeta,
        ),
      );
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
      reviewDisposition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_disposition'],
      )!,
      reviewDispositionUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}review_disposition_updated_at'],
      ),
      configurationBasisSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}configuration_basis_source_id'],
      ),
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
  final String reviewDisposition;
  final DateTime? reviewDispositionUpdatedAt;
  final String? configurationBasisSourceId;
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
    required this.reviewDisposition,
    this.reviewDispositionUpdatedAt,
    this.configurationBasisSourceId,
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
    map['review_disposition'] = Variable<String>(reviewDisposition);
    if (!nullToAbsent || reviewDispositionUpdatedAt != null) {
      map['review_disposition_updated_at'] = Variable<DateTime>(
        reviewDispositionUpdatedAt,
      );
    }
    if (!nullToAbsent || configurationBasisSourceId != null) {
      map['configuration_basis_source_id'] = Variable<String>(
        configurationBasisSourceId,
      );
    }
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
      reviewDisposition: Value(reviewDisposition),
      reviewDispositionUpdatedAt:
          reviewDispositionUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewDispositionUpdatedAt),
      configurationBasisSourceId:
          configurationBasisSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(configurationBasisSourceId),
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
      reviewDisposition: serializer.fromJson<String>(json['reviewDisposition']),
      reviewDispositionUpdatedAt: serializer.fromJson<DateTime?>(
        json['reviewDispositionUpdatedAt'],
      ),
      configurationBasisSourceId: serializer.fromJson<String?>(
        json['configurationBasisSourceId'],
      ),
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
      'reviewDisposition': serializer.toJson<String>(reviewDisposition),
      'reviewDispositionUpdatedAt': serializer.toJson<DateTime?>(
        reviewDispositionUpdatedAt,
      ),
      'configurationBasisSourceId': serializer.toJson<String?>(
        configurationBasisSourceId,
      ),
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
    String? reviewDisposition,
    Value<DateTime?> reviewDispositionUpdatedAt = const Value.absent(),
    Value<String?> configurationBasisSourceId = const Value.absent(),
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
    reviewDisposition: reviewDisposition ?? this.reviewDisposition,
    reviewDispositionUpdatedAt: reviewDispositionUpdatedAt.present
        ? reviewDispositionUpdatedAt.value
        : this.reviewDispositionUpdatedAt,
    configurationBasisSourceId: configurationBasisSourceId.present
        ? configurationBasisSourceId.value
        : this.configurationBasisSourceId,
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
      reviewDisposition: data.reviewDisposition.present
          ? data.reviewDisposition.value
          : this.reviewDisposition,
      reviewDispositionUpdatedAt: data.reviewDispositionUpdatedAt.present
          ? data.reviewDispositionUpdatedAt.value
          : this.reviewDispositionUpdatedAt,
      configurationBasisSourceId: data.configurationBasisSourceId.present
          ? data.configurationBasisSourceId.value
          : this.configurationBasisSourceId,
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
          ..write('updatedAt: $updatedAt, ')
          ..write('reviewDisposition: $reviewDisposition, ')
          ..write('reviewDispositionUpdatedAt: $reviewDispositionUpdatedAt, ')
          ..write('configurationBasisSourceId: $configurationBasisSourceId')
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
    reviewDisposition,
    reviewDispositionUpdatedAt,
    configurationBasisSourceId,
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
          other.updatedAt == this.updatedAt &&
          other.reviewDisposition == this.reviewDisposition &&
          other.reviewDispositionUpdatedAt == this.reviewDispositionUpdatedAt &&
          other.configurationBasisSourceId == this.configurationBasisSourceId);
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
  final Value<String> reviewDisposition;
  final Value<DateTime?> reviewDispositionUpdatedAt;
  final Value<String?> configurationBasisSourceId;
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
    this.reviewDisposition = const Value.absent(),
    this.reviewDispositionUpdatedAt = const Value.absent(),
    this.configurationBasisSourceId = const Value.absent(),
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
    this.reviewDisposition = const Value.absent(),
    this.reviewDispositionUpdatedAt = const Value.absent(),
    this.configurationBasisSourceId = const Value.absent(),
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
    Expression<String>? reviewDisposition,
    Expression<DateTime>? reviewDispositionUpdatedAt,
    Expression<String>? configurationBasisSourceId,
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
      if (reviewDisposition != null) 'review_disposition': reviewDisposition,
      if (reviewDispositionUpdatedAt != null)
        'review_disposition_updated_at': reviewDispositionUpdatedAt,
      if (configurationBasisSourceId != null)
        'configuration_basis_source_id': configurationBasisSourceId,
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
    Value<String>? reviewDisposition,
    Value<DateTime?>? reviewDispositionUpdatedAt,
    Value<String?>? configurationBasisSourceId,
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
      reviewDisposition: reviewDisposition ?? this.reviewDisposition,
      reviewDispositionUpdatedAt:
          reviewDispositionUpdatedAt ?? this.reviewDispositionUpdatedAt,
      configurationBasisSourceId:
          configurationBasisSourceId ?? this.configurationBasisSourceId,
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
    if (reviewDisposition.present) {
      map['review_disposition'] = Variable<String>(reviewDisposition.value);
    }
    if (reviewDispositionUpdatedAt.present) {
      map['review_disposition_updated_at'] = Variable<DateTime>(
        reviewDispositionUpdatedAt.value,
      );
    }
    if (configurationBasisSourceId.present) {
      map['configuration_basis_source_id'] = Variable<String>(
        configurationBasisSourceId.value,
      );
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
          ..write('reviewDisposition: $reviewDisposition, ')
          ..write('reviewDispositionUpdatedAt: $reviewDispositionUpdatedAt, ')
          ..write('configurationBasisSourceId: $configurationBasisSourceId, ')
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

class $FocusSourceDevicesTable extends FocusSourceDevices
    with TableInfo<$FocusSourceDevicesTable, FocusSourceDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSourceDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [userId, deviceId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_source_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusSourceDevice> instance, {
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
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  FocusSourceDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSourceDevice(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
    );
  }

  @override
  $FocusSourceDevicesTable createAlias(String alias) {
    return $FocusSourceDevicesTable(attachedDatabase, alias);
  }
}

class FocusSourceDevice extends DataClass
    implements Insertable<FocusSourceDevice> {
  final String userId;
  final String deviceId;
  const FocusSourceDevice({required this.userId, required this.deviceId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['device_id'] = Variable<String>(deviceId);
    return map;
  }

  FocusSourceDevicesCompanion toCompanion(bool nullToAbsent) {
    return FocusSourceDevicesCompanion(
      userId: Value(userId),
      deviceId: Value(deviceId),
    );
  }

  factory FocusSourceDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSourceDevice(
      userId: serializer.fromJson<String>(json['userId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'deviceId': serializer.toJson<String>(deviceId),
    };
  }

  FocusSourceDevice copyWith({String? userId, String? deviceId}) =>
      FocusSourceDevice(
        userId: userId ?? this.userId,
        deviceId: deviceId ?? this.deviceId,
      );
  FocusSourceDevice copyWithCompanion(FocusSourceDevicesCompanion data) {
    return FocusSourceDevice(
      userId: data.userId.present ? data.userId.value : this.userId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusSourceDevice(')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, deviceId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSourceDevice &&
          other.userId == this.userId &&
          other.deviceId == this.deviceId);
}

class FocusSourceDevicesCompanion extends UpdateCompanion<FocusSourceDevice> {
  final Value<String> userId;
  final Value<String> deviceId;
  final Value<int> rowid;
  const FocusSourceDevicesCompanion({
    this.userId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusSourceDevicesCompanion.insert({
    required String userId,
    required String deviceId,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       deviceId = Value(deviceId);
  static Insertable<FocusSourceDevice> custom({
    Expression<String>? userId,
    Expression<String>? deviceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (deviceId != null) 'device_id': deviceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusSourceDevicesCompanion copyWith({
    Value<String>? userId,
    Value<String>? deviceId,
    Value<int>? rowid,
  }) {
    return FocusSourceDevicesCompanion(
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusSourceDevicesCompanion(')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FocusSyncSourcesTable extends FocusSyncSources
    with TableInfo<$FocusSyncSourcesTable, FocusSyncSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSyncSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
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
  static const VerificationMeta _parentSourceIdMeta = const VerificationMeta(
    'parentSourceId',
  );
  @override
  late final GeneratedColumn<String> parentSourceId = GeneratedColumn<String>(
    'parent_source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentSourceIdsMeta = const VerificationMeta(
    'parentSourceIds',
  );
  @override
  late final GeneratedColumn<String> parentSourceIds = GeneratedColumn<String>(
    'parent_source_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
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
    sourceId,
    deviceId,
    entityType,
    entityId,
    parentSourceId,
    parentSourceIds,
    occurredAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_sync_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<FocusSyncSource> instance, {
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
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
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
    if (data.containsKey('parent_source_id')) {
      context.handle(
        _parentSourceIdMeta,
        parentSourceId.isAcceptableOrUnknown(
          data['parent_source_id']!,
          _parentSourceIdMeta,
        ),
      );
    }
    if (data.containsKey('parent_source_ids')) {
      context.handle(
        _parentSourceIdsMeta,
        parentSourceIds.isAcceptableOrUnknown(
          data['parent_source_ids']!,
          _parentSourceIdsMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {userId, sourceId};
  @override
  FocusSyncSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSyncSource(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      parentSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_source_id'],
      ),
      parentSourceIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_source_ids'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $FocusSyncSourcesTable createAlias(String alias) {
    return $FocusSyncSourcesTable(attachedDatabase, alias);
  }
}

class FocusSyncSource extends DataClass implements Insertable<FocusSyncSource> {
  final String userId;
  final String sourceId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String? parentSourceId;
  final String parentSourceIds;
  final DateTime occurredAt;
  final String payload;
  const FocusSyncSource({
    required this.userId,
    required this.sourceId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    this.parentSourceId,
    required this.parentSourceIds,
    required this.occurredAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['source_id'] = Variable<String>(sourceId);
    map['device_id'] = Variable<String>(deviceId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    if (!nullToAbsent || parentSourceId != null) {
      map['parent_source_id'] = Variable<String>(parentSourceId);
    }
    map['parent_source_ids'] = Variable<String>(parentSourceIds);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  FocusSyncSourcesCompanion toCompanion(bool nullToAbsent) {
    return FocusSyncSourcesCompanion(
      userId: Value(userId),
      sourceId: Value(sourceId),
      deviceId: Value(deviceId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      parentSourceId: parentSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentSourceId),
      parentSourceIds: Value(parentSourceIds),
      occurredAt: Value(occurredAt),
      payload: Value(payload),
    );
  }

  factory FocusSyncSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSyncSource(
      userId: serializer.fromJson<String>(json['userId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      parentSourceId: serializer.fromJson<String?>(json['parentSourceId']),
      parentSourceIds: serializer.fromJson<String>(json['parentSourceIds']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'sourceId': serializer.toJson<String>(sourceId),
      'deviceId': serializer.toJson<String>(deviceId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'parentSourceId': serializer.toJson<String?>(parentSourceId),
      'parentSourceIds': serializer.toJson<String>(parentSourceIds),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  FocusSyncSource copyWith({
    String? userId,
    String? sourceId,
    String? deviceId,
    String? entityType,
    String? entityId,
    Value<String?> parentSourceId = const Value.absent(),
    String? parentSourceIds,
    DateTime? occurredAt,
    String? payload,
  }) => FocusSyncSource(
    userId: userId ?? this.userId,
    sourceId: sourceId ?? this.sourceId,
    deviceId: deviceId ?? this.deviceId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    parentSourceId: parentSourceId.present
        ? parentSourceId.value
        : this.parentSourceId,
    parentSourceIds: parentSourceIds ?? this.parentSourceIds,
    occurredAt: occurredAt ?? this.occurredAt,
    payload: payload ?? this.payload,
  );
  FocusSyncSource copyWithCompanion(FocusSyncSourcesCompanion data) {
    return FocusSyncSource(
      userId: data.userId.present ? data.userId.value : this.userId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      parentSourceId: data.parentSourceId.present
          ? data.parentSourceId.value
          : this.parentSourceId,
      parentSourceIds: data.parentSourceIds.present
          ? data.parentSourceIds.value
          : this.parentSourceIds,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusSyncSource(')
          ..write('userId: $userId, ')
          ..write('sourceId: $sourceId, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('parentSourceId: $parentSourceId, ')
          ..write('parentSourceIds: $parentSourceIds, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    sourceId,
    deviceId,
    entityType,
    entityId,
    parentSourceId,
    parentSourceIds,
    occurredAt,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSyncSource &&
          other.userId == this.userId &&
          other.sourceId == this.sourceId &&
          other.deviceId == this.deviceId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.parentSourceId == this.parentSourceId &&
          other.parentSourceIds == this.parentSourceIds &&
          other.occurredAt == this.occurredAt &&
          other.payload == this.payload);
}

class FocusSyncSourcesCompanion extends UpdateCompanion<FocusSyncSource> {
  final Value<String> userId;
  final Value<String> sourceId;
  final Value<String> deviceId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String?> parentSourceId;
  final Value<String> parentSourceIds;
  final Value<DateTime> occurredAt;
  final Value<String> payload;
  final Value<int> rowid;
  const FocusSyncSourcesCompanion({
    this.userId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.parentSourceId = const Value.absent(),
    this.parentSourceIds = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FocusSyncSourcesCompanion.insert({
    required String userId,
    required String sourceId,
    required String deviceId,
    required String entityType,
    required String entityId,
    this.parentSourceId = const Value.absent(),
    this.parentSourceIds = const Value.absent(),
    required DateTime occurredAt,
    required String payload,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       sourceId = Value(sourceId),
       deviceId = Value(deviceId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       occurredAt = Value(occurredAt),
       payload = Value(payload);
  static Insertable<FocusSyncSource> custom({
    Expression<String>? userId,
    Expression<String>? sourceId,
    Expression<String>? deviceId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? parentSourceId,
    Expression<String>? parentSourceIds,
    Expression<DateTime>? occurredAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (sourceId != null) 'source_id': sourceId,
      if (deviceId != null) 'device_id': deviceId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (parentSourceId != null) 'parent_source_id': parentSourceId,
      if (parentSourceIds != null) 'parent_source_ids': parentSourceIds,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FocusSyncSourcesCompanion copyWith({
    Value<String>? userId,
    Value<String>? sourceId,
    Value<String>? deviceId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String?>? parentSourceId,
    Value<String>? parentSourceIds,
    Value<DateTime>? occurredAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return FocusSyncSourcesCompanion(
      userId: userId ?? this.userId,
      sourceId: sourceId ?? this.sourceId,
      deviceId: deviceId ?? this.deviceId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      parentSourceId: parentSourceId ?? this.parentSourceId,
      parentSourceIds: parentSourceIds ?? this.parentSourceIds,
      occurredAt: occurredAt ?? this.occurredAt,
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
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (parentSourceId.present) {
      map['parent_source_id'] = Variable<String>(parentSourceId.value);
    }
    if (parentSourceIds.present) {
      map['parent_source_ids'] = Variable<String>(parentSourceIds.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
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
    return (StringBuffer('FocusSyncSourcesCompanion(')
          ..write('userId: $userId, ')
          ..write('sourceId: $sourceId, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('parentSourceId: $parentSourceId, ')
          ..write('parentSourceIds: $parentSourceIds, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCalendarSourcesTable extends LocalCalendarSources
    with TableInfo<$LocalCalendarSourcesTable, LocalCalendarSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCalendarSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeZoneIdMeta = const VerificationMeta(
    'timeZoneId',
  );
  @override
  late final GeneratedColumn<String> timeZoneId = GeneratedColumn<String>(
    'time_zone_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localCalendarIdMeta = const VerificationMeta(
    'localCalendarId',
  );
  @override
  late final GeneratedColumn<String> localCalendarId = GeneratedColumn<String>(
    'local_calendar_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isSelectedMeta = const VerificationMeta(
    'isSelected',
  );
  @override
  late final GeneratedColumn<bool> isSelected = GeneratedColumn<bool>(
    'is_selected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_selected" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isStaleMeta = const VerificationMeta(
    'isStale',
  );
  @override
  late final GeneratedColumn<bool> isStale = GeneratedColumn<bool>(
    'is_stale',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_stale" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
    sourceId,
    displayName,
    timeZoneId,
    localCalendarId,
    isSelected,
    isStale,
    isDeleted,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_calendar_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCalendarSource> instance, {
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
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('time_zone_id')) {
      context.handle(
        _timeZoneIdMeta,
        timeZoneId.isAcceptableOrUnknown(
          data['time_zone_id']!,
          _timeZoneIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timeZoneIdMeta);
    }
    if (data.containsKey('local_calendar_id')) {
      context.handle(
        _localCalendarIdMeta,
        localCalendarId.isAcceptableOrUnknown(
          data['local_calendar_id']!,
          _localCalendarIdMeta,
        ),
      );
    }
    if (data.containsKey('is_selected')) {
      context.handle(
        _isSelectedMeta,
        isSelected.isAcceptableOrUnknown(data['is_selected']!, _isSelectedMeta),
      );
    }
    if (data.containsKey('is_stale')) {
      context.handle(
        _isStaleMeta,
        isStale.isAcceptableOrUnknown(data['is_stale']!, _isStaleMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
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
  Set<GeneratedColumn> get $primaryKey => {userId, sourceId};
  @override
  LocalCalendarSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCalendarSource(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      timeZoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_zone_id'],
      )!,
      localCalendarId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_calendar_id'],
      ),
      isSelected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_selected'],
      )!,
      isStale: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_stale'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalCalendarSourcesTable createAlias(String alias) {
    return $LocalCalendarSourcesTable(attachedDatabase, alias);
  }
}

class LocalCalendarSource extends DataClass
    implements Insertable<LocalCalendarSource> {
  final String userId;
  final String sourceId;
  final String displayName;
  final String timeZoneId;
  final String? localCalendarId;
  final bool isSelected;
  final bool isStale;
  final bool isDeleted;
  final DateTime updatedAt;
  const LocalCalendarSource({
    required this.userId,
    required this.sourceId,
    required this.displayName,
    required this.timeZoneId,
    this.localCalendarId,
    required this.isSelected,
    required this.isStale,
    required this.isDeleted,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['source_id'] = Variable<String>(sourceId);
    map['display_name'] = Variable<String>(displayName);
    map['time_zone_id'] = Variable<String>(timeZoneId);
    if (!nullToAbsent || localCalendarId != null) {
      map['local_calendar_id'] = Variable<String>(localCalendarId);
    }
    map['is_selected'] = Variable<bool>(isSelected);
    map['is_stale'] = Variable<bool>(isStale);
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalCalendarSourcesCompanion toCompanion(bool nullToAbsent) {
    return LocalCalendarSourcesCompanion(
      userId: Value(userId),
      sourceId: Value(sourceId),
      displayName: Value(displayName),
      timeZoneId: Value(timeZoneId),
      localCalendarId: localCalendarId == null && nullToAbsent
          ? const Value.absent()
          : Value(localCalendarId),
      isSelected: Value(isSelected),
      isStale: Value(isStale),
      isDeleted: Value(isDeleted),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalCalendarSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCalendarSource(
      userId: serializer.fromJson<String>(json['userId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      timeZoneId: serializer.fromJson<String>(json['timeZoneId']),
      localCalendarId: serializer.fromJson<String?>(json['localCalendarId']),
      isSelected: serializer.fromJson<bool>(json['isSelected']),
      isStale: serializer.fromJson<bool>(json['isStale']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'sourceId': serializer.toJson<String>(sourceId),
      'displayName': serializer.toJson<String>(displayName),
      'timeZoneId': serializer.toJson<String>(timeZoneId),
      'localCalendarId': serializer.toJson<String?>(localCalendarId),
      'isSelected': serializer.toJson<bool>(isSelected),
      'isStale': serializer.toJson<bool>(isStale),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalCalendarSource copyWith({
    String? userId,
    String? sourceId,
    String? displayName,
    String? timeZoneId,
    Value<String?> localCalendarId = const Value.absent(),
    bool? isSelected,
    bool? isStale,
    bool? isDeleted,
    DateTime? updatedAt,
  }) => LocalCalendarSource(
    userId: userId ?? this.userId,
    sourceId: sourceId ?? this.sourceId,
    displayName: displayName ?? this.displayName,
    timeZoneId: timeZoneId ?? this.timeZoneId,
    localCalendarId: localCalendarId.present
        ? localCalendarId.value
        : this.localCalendarId,
    isSelected: isSelected ?? this.isSelected,
    isStale: isStale ?? this.isStale,
    isDeleted: isDeleted ?? this.isDeleted,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalCalendarSource copyWithCompanion(LocalCalendarSourcesCompanion data) {
    return LocalCalendarSource(
      userId: data.userId.present ? data.userId.value : this.userId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      timeZoneId: data.timeZoneId.present
          ? data.timeZoneId.value
          : this.timeZoneId,
      localCalendarId: data.localCalendarId.present
          ? data.localCalendarId.value
          : this.localCalendarId,
      isSelected: data.isSelected.present
          ? data.isSelected.value
          : this.isSelected,
      isStale: data.isStale.present ? data.isStale.value : this.isStale,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCalendarSource(')
          ..write('userId: $userId, ')
          ..write('sourceId: $sourceId, ')
          ..write('displayName: $displayName, ')
          ..write('timeZoneId: $timeZoneId, ')
          ..write('localCalendarId: $localCalendarId, ')
          ..write('isSelected: $isSelected, ')
          ..write('isStale: $isStale, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    sourceId,
    displayName,
    timeZoneId,
    localCalendarId,
    isSelected,
    isStale,
    isDeleted,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCalendarSource &&
          other.userId == this.userId &&
          other.sourceId == this.sourceId &&
          other.displayName == this.displayName &&
          other.timeZoneId == this.timeZoneId &&
          other.localCalendarId == this.localCalendarId &&
          other.isSelected == this.isSelected &&
          other.isStale == this.isStale &&
          other.isDeleted == this.isDeleted &&
          other.updatedAt == this.updatedAt);
}

class LocalCalendarSourcesCompanion
    extends UpdateCompanion<LocalCalendarSource> {
  final Value<String> userId;
  final Value<String> sourceId;
  final Value<String> displayName;
  final Value<String> timeZoneId;
  final Value<String?> localCalendarId;
  final Value<bool> isSelected;
  final Value<bool> isStale;
  final Value<bool> isDeleted;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalCalendarSourcesCompanion({
    this.userId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.timeZoneId = const Value.absent(),
    this.localCalendarId = const Value.absent(),
    this.isSelected = const Value.absent(),
    this.isStale = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCalendarSourcesCompanion.insert({
    required String userId,
    required String sourceId,
    required String displayName,
    required String timeZoneId,
    this.localCalendarId = const Value.absent(),
    this.isSelected = const Value.absent(),
    this.isStale = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       sourceId = Value(sourceId),
       displayName = Value(displayName),
       timeZoneId = Value(timeZoneId),
       updatedAt = Value(updatedAt);
  static Insertable<LocalCalendarSource> custom({
    Expression<String>? userId,
    Expression<String>? sourceId,
    Expression<String>? displayName,
    Expression<String>? timeZoneId,
    Expression<String>? localCalendarId,
    Expression<bool>? isSelected,
    Expression<bool>? isStale,
    Expression<bool>? isDeleted,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (sourceId != null) 'source_id': sourceId,
      if (displayName != null) 'display_name': displayName,
      if (timeZoneId != null) 'time_zone_id': timeZoneId,
      if (localCalendarId != null) 'local_calendar_id': localCalendarId,
      if (isSelected != null) 'is_selected': isSelected,
      if (isStale != null) 'is_stale': isStale,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCalendarSourcesCompanion copyWith({
    Value<String>? userId,
    Value<String>? sourceId,
    Value<String>? displayName,
    Value<String>? timeZoneId,
    Value<String?>? localCalendarId,
    Value<bool>? isSelected,
    Value<bool>? isStale,
    Value<bool>? isDeleted,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalCalendarSourcesCompanion(
      userId: userId ?? this.userId,
      sourceId: sourceId ?? this.sourceId,
      displayName: displayName ?? this.displayName,
      timeZoneId: timeZoneId ?? this.timeZoneId,
      localCalendarId: localCalendarId ?? this.localCalendarId,
      isSelected: isSelected ?? this.isSelected,
      isStale: isStale ?? this.isStale,
      isDeleted: isDeleted ?? this.isDeleted,
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
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (timeZoneId.present) {
      map['time_zone_id'] = Variable<String>(timeZoneId.value);
    }
    if (localCalendarId.present) {
      map['local_calendar_id'] = Variable<String>(localCalendarId.value);
    }
    if (isSelected.present) {
      map['is_selected'] = Variable<bool>(isSelected.value);
    }
    if (isStale.present) {
      map['is_stale'] = Variable<bool>(isStale.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
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
    return (StringBuffer('LocalCalendarSourcesCompanion(')
          ..write('userId: $userId, ')
          ..write('sourceId: $sourceId, ')
          ..write('displayName: $displayName, ')
          ..write('timeZoneId: $timeZoneId, ')
          ..write('localCalendarId: $localCalendarId, ')
          ..write('isSelected: $isSelected, ')
          ..write('isStale: $isStale, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCalendarBlocksTable extends LocalCalendarBlocks
    with TableInfo<$LocalCalendarBlocksTable, LocalCalendarBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCalendarBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceEventIdMeta = const VerificationMeta(
    'sourceEventId',
  );
  @override
  late final GeneratedColumn<String> sourceEventId = GeneratedColumn<String>(
    'source_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurrenceIdMeta = const VerificationMeta(
    'occurrenceId',
  );
  @override
  late final GeneratedColumn<String> occurrenceId = GeneratedColumn<String>(
    'occurrence_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdentityMeta = const VerificationMeta(
    'eventIdentity',
  );
  @override
  late final GeneratedColumn<String> eventIdentity = GeneratedColumn<String>(
    'event_identity',
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
  static const VerificationMeta _startsAtMeta = const VerificationMeta(
    'startsAt',
  );
  @override
  late final GeneratedColumn<DateTime> startsAt = GeneratedColumn<DateTime>(
    'starts_at',
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
  static const VerificationMeta _allDayMeta = const VerificationMeta('allDay');
  @override
  late final GeneratedColumn<bool> allDay = GeneratedColumn<bool>(
    'all_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("all_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _allDayStartDateMeta = const VerificationMeta(
    'allDayStartDate',
  );
  @override
  late final GeneratedColumn<String> allDayStartDate = GeneratedColumn<String>(
    'all_day_start_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _allDayEndDateExclusiveMeta =
      const VerificationMeta('allDayEndDateExclusive');
  @override
  late final GeneratedColumn<String> allDayEndDateExclusive =
      GeneratedColumn<String>(
        'all_day_end_date_exclusive',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _availabilityMeta = const VerificationMeta(
    'availability',
  );
  @override
  late final GeneratedColumn<String> availability = GeneratedColumn<String>(
    'availability',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeZoneIdMeta = const VerificationMeta(
    'timeZoneId',
  );
  @override
  late final GeneratedColumn<String> timeZoneId = GeneratedColumn<String>(
    'time_zone_id',
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
    sourceId,
    sourceEventId,
    occurrenceId,
    eventIdentity,
    title,
    startsAt,
    endsAt,
    allDay,
    allDayStartDate,
    allDayEndDateExclusive,
    availability,
    timeZoneId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_calendar_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCalendarBlock> instance, {
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
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('source_event_id')) {
      context.handle(
        _sourceEventIdMeta,
        sourceEventId.isAcceptableOrUnknown(
          data['source_event_id']!,
          _sourceEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceEventIdMeta);
    }
    if (data.containsKey('occurrence_id')) {
      context.handle(
        _occurrenceIdMeta,
        occurrenceId.isAcceptableOrUnknown(
          data['occurrence_id']!,
          _occurrenceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurrenceIdMeta);
    }
    if (data.containsKey('event_identity')) {
      context.handle(
        _eventIdentityMeta,
        eventIdentity.isAcceptableOrUnknown(
          data['event_identity']!,
          _eventIdentityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_eventIdentityMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('starts_at')) {
      context.handle(
        _startsAtMeta,
        startsAt.isAcceptableOrUnknown(data['starts_at']!, _startsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startsAtMeta);
    }
    if (data.containsKey('ends_at')) {
      context.handle(
        _endsAtMeta,
        endsAt.isAcceptableOrUnknown(data['ends_at']!, _endsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMeta);
    }
    if (data.containsKey('all_day')) {
      context.handle(
        _allDayMeta,
        allDay.isAcceptableOrUnknown(data['all_day']!, _allDayMeta),
      );
    }
    if (data.containsKey('all_day_start_date')) {
      context.handle(
        _allDayStartDateMeta,
        allDayStartDate.isAcceptableOrUnknown(
          data['all_day_start_date']!,
          _allDayStartDateMeta,
        ),
      );
    }
    if (data.containsKey('all_day_end_date_exclusive')) {
      context.handle(
        _allDayEndDateExclusiveMeta,
        allDayEndDateExclusive.isAcceptableOrUnknown(
          data['all_day_end_date_exclusive']!,
          _allDayEndDateExclusiveMeta,
        ),
      );
    }
    if (data.containsKey('availability')) {
      context.handle(
        _availabilityMeta,
        availability.isAcceptableOrUnknown(
          data['availability']!,
          _availabilityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_availabilityMeta);
    }
    if (data.containsKey('time_zone_id')) {
      context.handle(
        _timeZoneIdMeta,
        timeZoneId.isAcceptableOrUnknown(
          data['time_zone_id']!,
          _timeZoneIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timeZoneIdMeta);
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
  Set<GeneratedColumn> get $primaryKey => {userId, sourceId, occurrenceId};
  @override
  LocalCalendarBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCalendarBlock(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_event_id'],
      )!,
      occurrenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_id'],
      )!,
      eventIdentity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_identity'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      startsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}starts_at'],
      )!,
      endsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ends_at'],
      )!,
      allDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}all_day'],
      )!,
      allDayStartDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}all_day_start_date'],
      ),
      allDayEndDateExclusive: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}all_day_end_date_exclusive'],
      ),
      availability: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}availability'],
      )!,
      timeZoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_zone_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalCalendarBlocksTable createAlias(String alias) {
    return $LocalCalendarBlocksTable(attachedDatabase, alias);
  }
}

class LocalCalendarBlock extends DataClass
    implements Insertable<LocalCalendarBlock> {
  final String userId;
  final String sourceId;
  final String sourceEventId;
  final String occurrenceId;
  final String eventIdentity;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? allDayStartDate;
  final String? allDayEndDateExclusive;
  final String availability;
  final String timeZoneId;
  final DateTime updatedAt;
  const LocalCalendarBlock({
    required this.userId,
    required this.sourceId,
    required this.sourceEventId,
    required this.occurrenceId,
    required this.eventIdentity,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    this.allDayStartDate,
    this.allDayEndDateExclusive,
    required this.availability,
    required this.timeZoneId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['source_id'] = Variable<String>(sourceId);
    map['source_event_id'] = Variable<String>(sourceEventId);
    map['occurrence_id'] = Variable<String>(occurrenceId);
    map['event_identity'] = Variable<String>(eventIdentity);
    map['title'] = Variable<String>(title);
    map['starts_at'] = Variable<DateTime>(startsAt);
    map['ends_at'] = Variable<DateTime>(endsAt);
    map['all_day'] = Variable<bool>(allDay);
    if (!nullToAbsent || allDayStartDate != null) {
      map['all_day_start_date'] = Variable<String>(allDayStartDate);
    }
    if (!nullToAbsent || allDayEndDateExclusive != null) {
      map['all_day_end_date_exclusive'] = Variable<String>(
        allDayEndDateExclusive,
      );
    }
    map['availability'] = Variable<String>(availability);
    map['time_zone_id'] = Variable<String>(timeZoneId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalCalendarBlocksCompanion toCompanion(bool nullToAbsent) {
    return LocalCalendarBlocksCompanion(
      userId: Value(userId),
      sourceId: Value(sourceId),
      sourceEventId: Value(sourceEventId),
      occurrenceId: Value(occurrenceId),
      eventIdentity: Value(eventIdentity),
      title: Value(title),
      startsAt: Value(startsAt),
      endsAt: Value(endsAt),
      allDay: Value(allDay),
      allDayStartDate: allDayStartDate == null && nullToAbsent
          ? const Value.absent()
          : Value(allDayStartDate),
      allDayEndDateExclusive: allDayEndDateExclusive == null && nullToAbsent
          ? const Value.absent()
          : Value(allDayEndDateExclusive),
      availability: Value(availability),
      timeZoneId: Value(timeZoneId),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalCalendarBlock.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCalendarBlock(
      userId: serializer.fromJson<String>(json['userId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceEventId: serializer.fromJson<String>(json['sourceEventId']),
      occurrenceId: serializer.fromJson<String>(json['occurrenceId']),
      eventIdentity: serializer.fromJson<String>(json['eventIdentity']),
      title: serializer.fromJson<String>(json['title']),
      startsAt: serializer.fromJson<DateTime>(json['startsAt']),
      endsAt: serializer.fromJson<DateTime>(json['endsAt']),
      allDay: serializer.fromJson<bool>(json['allDay']),
      allDayStartDate: serializer.fromJson<String?>(json['allDayStartDate']),
      allDayEndDateExclusive: serializer.fromJson<String?>(
        json['allDayEndDateExclusive'],
      ),
      availability: serializer.fromJson<String>(json['availability']),
      timeZoneId: serializer.fromJson<String>(json['timeZoneId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceEventId': serializer.toJson<String>(sourceEventId),
      'occurrenceId': serializer.toJson<String>(occurrenceId),
      'eventIdentity': serializer.toJson<String>(eventIdentity),
      'title': serializer.toJson<String>(title),
      'startsAt': serializer.toJson<DateTime>(startsAt),
      'endsAt': serializer.toJson<DateTime>(endsAt),
      'allDay': serializer.toJson<bool>(allDay),
      'allDayStartDate': serializer.toJson<String?>(allDayStartDate),
      'allDayEndDateExclusive': serializer.toJson<String?>(
        allDayEndDateExclusive,
      ),
      'availability': serializer.toJson<String>(availability),
      'timeZoneId': serializer.toJson<String>(timeZoneId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalCalendarBlock copyWith({
    String? userId,
    String? sourceId,
    String? sourceEventId,
    String? occurrenceId,
    String? eventIdentity,
    String? title,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? allDay,
    Value<String?> allDayStartDate = const Value.absent(),
    Value<String?> allDayEndDateExclusive = const Value.absent(),
    String? availability,
    String? timeZoneId,
    DateTime? updatedAt,
  }) => LocalCalendarBlock(
    userId: userId ?? this.userId,
    sourceId: sourceId ?? this.sourceId,
    sourceEventId: sourceEventId ?? this.sourceEventId,
    occurrenceId: occurrenceId ?? this.occurrenceId,
    eventIdentity: eventIdentity ?? this.eventIdentity,
    title: title ?? this.title,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    allDay: allDay ?? this.allDay,
    allDayStartDate: allDayStartDate.present
        ? allDayStartDate.value
        : this.allDayStartDate,
    allDayEndDateExclusive: allDayEndDateExclusive.present
        ? allDayEndDateExclusive.value
        : this.allDayEndDateExclusive,
    availability: availability ?? this.availability,
    timeZoneId: timeZoneId ?? this.timeZoneId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalCalendarBlock copyWithCompanion(LocalCalendarBlocksCompanion data) {
    return LocalCalendarBlock(
      userId: data.userId.present ? data.userId.value : this.userId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceEventId: data.sourceEventId.present
          ? data.sourceEventId.value
          : this.sourceEventId,
      occurrenceId: data.occurrenceId.present
          ? data.occurrenceId.value
          : this.occurrenceId,
      eventIdentity: data.eventIdentity.present
          ? data.eventIdentity.value
          : this.eventIdentity,
      title: data.title.present ? data.title.value : this.title,
      startsAt: data.startsAt.present ? data.startsAt.value : this.startsAt,
      endsAt: data.endsAt.present ? data.endsAt.value : this.endsAt,
      allDay: data.allDay.present ? data.allDay.value : this.allDay,
      allDayStartDate: data.allDayStartDate.present
          ? data.allDayStartDate.value
          : this.allDayStartDate,
      allDayEndDateExclusive: data.allDayEndDateExclusive.present
          ? data.allDayEndDateExclusive.value
          : this.allDayEndDateExclusive,
      availability: data.availability.present
          ? data.availability.value
          : this.availability,
      timeZoneId: data.timeZoneId.present
          ? data.timeZoneId.value
          : this.timeZoneId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCalendarBlock(')
          ..write('userId: $userId, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('occurrenceId: $occurrenceId, ')
          ..write('eventIdentity: $eventIdentity, ')
          ..write('title: $title, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('allDay: $allDay, ')
          ..write('allDayStartDate: $allDayStartDate, ')
          ..write('allDayEndDateExclusive: $allDayEndDateExclusive, ')
          ..write('availability: $availability, ')
          ..write('timeZoneId: $timeZoneId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    sourceId,
    sourceEventId,
    occurrenceId,
    eventIdentity,
    title,
    startsAt,
    endsAt,
    allDay,
    allDayStartDate,
    allDayEndDateExclusive,
    availability,
    timeZoneId,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCalendarBlock &&
          other.userId == this.userId &&
          other.sourceId == this.sourceId &&
          other.sourceEventId == this.sourceEventId &&
          other.occurrenceId == this.occurrenceId &&
          other.eventIdentity == this.eventIdentity &&
          other.title == this.title &&
          other.startsAt == this.startsAt &&
          other.endsAt == this.endsAt &&
          other.allDay == this.allDay &&
          other.allDayStartDate == this.allDayStartDate &&
          other.allDayEndDateExclusive == this.allDayEndDateExclusive &&
          other.availability == this.availability &&
          other.timeZoneId == this.timeZoneId &&
          other.updatedAt == this.updatedAt);
}

class LocalCalendarBlocksCompanion extends UpdateCompanion<LocalCalendarBlock> {
  final Value<String> userId;
  final Value<String> sourceId;
  final Value<String> sourceEventId;
  final Value<String> occurrenceId;
  final Value<String> eventIdentity;
  final Value<String> title;
  final Value<DateTime> startsAt;
  final Value<DateTime> endsAt;
  final Value<bool> allDay;
  final Value<String?> allDayStartDate;
  final Value<String?> allDayEndDateExclusive;
  final Value<String> availability;
  final Value<String> timeZoneId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalCalendarBlocksCompanion({
    this.userId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceEventId = const Value.absent(),
    this.occurrenceId = const Value.absent(),
    this.eventIdentity = const Value.absent(),
    this.title = const Value.absent(),
    this.startsAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.allDay = const Value.absent(),
    this.allDayStartDate = const Value.absent(),
    this.allDayEndDateExclusive = const Value.absent(),
    this.availability = const Value.absent(),
    this.timeZoneId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCalendarBlocksCompanion.insert({
    required String userId,
    required String sourceId,
    required String sourceEventId,
    required String occurrenceId,
    required String eventIdentity,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    this.allDay = const Value.absent(),
    this.allDayStartDate = const Value.absent(),
    this.allDayEndDateExclusive = const Value.absent(),
    required String availability,
    required String timeZoneId,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       sourceId = Value(sourceId),
       sourceEventId = Value(sourceEventId),
       occurrenceId = Value(occurrenceId),
       eventIdentity = Value(eventIdentity),
       title = Value(title),
       startsAt = Value(startsAt),
       endsAt = Value(endsAt),
       availability = Value(availability),
       timeZoneId = Value(timeZoneId),
       updatedAt = Value(updatedAt);
  static Insertable<LocalCalendarBlock> custom({
    Expression<String>? userId,
    Expression<String>? sourceId,
    Expression<String>? sourceEventId,
    Expression<String>? occurrenceId,
    Expression<String>? eventIdentity,
    Expression<String>? title,
    Expression<DateTime>? startsAt,
    Expression<DateTime>? endsAt,
    Expression<bool>? allDay,
    Expression<String>? allDayStartDate,
    Expression<String>? allDayEndDateExclusive,
    Expression<String>? availability,
    Expression<String>? timeZoneId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceEventId != null) 'source_event_id': sourceEventId,
      if (occurrenceId != null) 'occurrence_id': occurrenceId,
      if (eventIdentity != null) 'event_identity': eventIdentity,
      if (title != null) 'title': title,
      if (startsAt != null) 'starts_at': startsAt,
      if (endsAt != null) 'ends_at': endsAt,
      if (allDay != null) 'all_day': allDay,
      if (allDayStartDate != null) 'all_day_start_date': allDayStartDate,
      if (allDayEndDateExclusive != null)
        'all_day_end_date_exclusive': allDayEndDateExclusive,
      if (availability != null) 'availability': availability,
      if (timeZoneId != null) 'time_zone_id': timeZoneId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCalendarBlocksCompanion copyWith({
    Value<String>? userId,
    Value<String>? sourceId,
    Value<String>? sourceEventId,
    Value<String>? occurrenceId,
    Value<String>? eventIdentity,
    Value<String>? title,
    Value<DateTime>? startsAt,
    Value<DateTime>? endsAt,
    Value<bool>? allDay,
    Value<String?>? allDayStartDate,
    Value<String?>? allDayEndDateExclusive,
    Value<String>? availability,
    Value<String>? timeZoneId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalCalendarBlocksCompanion(
      userId: userId ?? this.userId,
      sourceId: sourceId ?? this.sourceId,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      occurrenceId: occurrenceId ?? this.occurrenceId,
      eventIdentity: eventIdentity ?? this.eventIdentity,
      title: title ?? this.title,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      allDay: allDay ?? this.allDay,
      allDayStartDate: allDayStartDate ?? this.allDayStartDate,
      allDayEndDateExclusive:
          allDayEndDateExclusive ?? this.allDayEndDateExclusive,
      availability: availability ?? this.availability,
      timeZoneId: timeZoneId ?? this.timeZoneId,
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
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceEventId.present) {
      map['source_event_id'] = Variable<String>(sourceEventId.value);
    }
    if (occurrenceId.present) {
      map['occurrence_id'] = Variable<String>(occurrenceId.value);
    }
    if (eventIdentity.present) {
      map['event_identity'] = Variable<String>(eventIdentity.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (startsAt.present) {
      map['starts_at'] = Variable<DateTime>(startsAt.value);
    }
    if (endsAt.present) {
      map['ends_at'] = Variable<DateTime>(endsAt.value);
    }
    if (allDay.present) {
      map['all_day'] = Variable<bool>(allDay.value);
    }
    if (allDayStartDate.present) {
      map['all_day_start_date'] = Variable<String>(allDayStartDate.value);
    }
    if (allDayEndDateExclusive.present) {
      map['all_day_end_date_exclusive'] = Variable<String>(
        allDayEndDateExclusive.value,
      );
    }
    if (availability.present) {
      map['availability'] = Variable<String>(availability.value);
    }
    if (timeZoneId.present) {
      map['time_zone_id'] = Variable<String>(timeZoneId.value);
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
    return (StringBuffer('LocalCalendarBlocksCompanion(')
          ..write('userId: $userId, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('occurrenceId: $occurrenceId, ')
          ..write('eventIdentity: $eventIdentity, ')
          ..write('title: $title, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('allDay: $allDay, ')
          ..write('allDayStartDate: $allDayStartDate, ')
          ..write('allDayEndDateExclusive: $allDayEndDateExclusive, ')
          ..write('availability: $availability, ')
          ..write('timeZoneId: $timeZoneId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalUserLifecycleStatesTable extends LocalUserLifecycleStates
    with TableInfo<$LocalUserLifecycleStatesTable, LocalUserLifecycleState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalUserLifecycleStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isSuspendedMeta = const VerificationMeta(
    'isSuspended',
  );
  @override
  late final GeneratedColumn<bool> isSuspended = GeneratedColumn<bool>(
    'is_suspended',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_suspended" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _suspendedAtMeta = const VerificationMeta(
    'suspendedAt',
  );
  @override
  late final GeneratedColumn<DateTime> suspendedAt = GeneratedColumn<DateTime>(
    'suspended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purgeEligibleAtMeta = const VerificationMeta(
    'purgeEligibleAt',
  );
  @override
  late final GeneratedColumn<DateTime> purgeEligibleAt =
      GeneratedColumn<DateTime>(
        'purge_eligible_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isEligibleForPurgeMeta =
      const VerificationMeta('isEligibleForPurge');
  @override
  late final GeneratedColumn<bool> isEligibleForPurge = GeneratedColumn<bool>(
    'is_eligible_for_purge',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_eligible_for_purge" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    isSuspended,
    suspendedAt,
    purgeEligibleAt,
    isEligibleForPurge,
    checkedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_user_lifecycle_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalUserLifecycleState> instance, {
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
    if (data.containsKey('is_suspended')) {
      context.handle(
        _isSuspendedMeta,
        isSuspended.isAcceptableOrUnknown(
          data['is_suspended']!,
          _isSuspendedMeta,
        ),
      );
    }
    if (data.containsKey('suspended_at')) {
      context.handle(
        _suspendedAtMeta,
        suspendedAt.isAcceptableOrUnknown(
          data['suspended_at']!,
          _suspendedAtMeta,
        ),
      );
    }
    if (data.containsKey('purge_eligible_at')) {
      context.handle(
        _purgeEligibleAtMeta,
        purgeEligibleAt.isAcceptableOrUnknown(
          data['purge_eligible_at']!,
          _purgeEligibleAtMeta,
        ),
      );
    }
    if (data.containsKey('is_eligible_for_purge')) {
      context.handle(
        _isEligibleForPurgeMeta,
        isEligibleForPurge.isAcceptableOrUnknown(
          data['is_eligible_for_purge']!,
          _isEligibleForPurgeMeta,
        ),
      );
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_checkedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  LocalUserLifecycleState map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalUserLifecycleState(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      isSuspended: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_suspended'],
      )!,
      suspendedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}suspended_at'],
      ),
      purgeEligibleAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}purge_eligible_at'],
      ),
      isEligibleForPurge: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_eligible_for_purge'],
      )!,
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      )!,
    );
  }

  @override
  $LocalUserLifecycleStatesTable createAlias(String alias) {
    return $LocalUserLifecycleStatesTable(attachedDatabase, alias);
  }
}

class LocalUserLifecycleState extends DataClass
    implements Insertable<LocalUserLifecycleState> {
  final String userId;
  final bool isSuspended;
  final DateTime? suspendedAt;
  final DateTime? purgeEligibleAt;
  final bool isEligibleForPurge;
  final DateTime checkedAt;
  const LocalUserLifecycleState({
    required this.userId,
    required this.isSuspended,
    this.suspendedAt,
    this.purgeEligibleAt,
    required this.isEligibleForPurge,
    required this.checkedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['is_suspended'] = Variable<bool>(isSuspended);
    if (!nullToAbsent || suspendedAt != null) {
      map['suspended_at'] = Variable<DateTime>(suspendedAt);
    }
    if (!nullToAbsent || purgeEligibleAt != null) {
      map['purge_eligible_at'] = Variable<DateTime>(purgeEligibleAt);
    }
    map['is_eligible_for_purge'] = Variable<bool>(isEligibleForPurge);
    map['checked_at'] = Variable<DateTime>(checkedAt);
    return map;
  }

  LocalUserLifecycleStatesCompanion toCompanion(bool nullToAbsent) {
    return LocalUserLifecycleStatesCompanion(
      userId: Value(userId),
      isSuspended: Value(isSuspended),
      suspendedAt: suspendedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(suspendedAt),
      purgeEligibleAt: purgeEligibleAt == null && nullToAbsent
          ? const Value.absent()
          : Value(purgeEligibleAt),
      isEligibleForPurge: Value(isEligibleForPurge),
      checkedAt: Value(checkedAt),
    );
  }

  factory LocalUserLifecycleState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalUserLifecycleState(
      userId: serializer.fromJson<String>(json['userId']),
      isSuspended: serializer.fromJson<bool>(json['isSuspended']),
      suspendedAt: serializer.fromJson<DateTime?>(json['suspendedAt']),
      purgeEligibleAt: serializer.fromJson<DateTime?>(json['purgeEligibleAt']),
      isEligibleForPurge: serializer.fromJson<bool>(json['isEligibleForPurge']),
      checkedAt: serializer.fromJson<DateTime>(json['checkedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'isSuspended': serializer.toJson<bool>(isSuspended),
      'suspendedAt': serializer.toJson<DateTime?>(suspendedAt),
      'purgeEligibleAt': serializer.toJson<DateTime?>(purgeEligibleAt),
      'isEligibleForPurge': serializer.toJson<bool>(isEligibleForPurge),
      'checkedAt': serializer.toJson<DateTime>(checkedAt),
    };
  }

  LocalUserLifecycleState copyWith({
    String? userId,
    bool? isSuspended,
    Value<DateTime?> suspendedAt = const Value.absent(),
    Value<DateTime?> purgeEligibleAt = const Value.absent(),
    bool? isEligibleForPurge,
    DateTime? checkedAt,
  }) => LocalUserLifecycleState(
    userId: userId ?? this.userId,
    isSuspended: isSuspended ?? this.isSuspended,
    suspendedAt: suspendedAt.present ? suspendedAt.value : this.suspendedAt,
    purgeEligibleAt: purgeEligibleAt.present
        ? purgeEligibleAt.value
        : this.purgeEligibleAt,
    isEligibleForPurge: isEligibleForPurge ?? this.isEligibleForPurge,
    checkedAt: checkedAt ?? this.checkedAt,
  );
  LocalUserLifecycleState copyWithCompanion(
    LocalUserLifecycleStatesCompanion data,
  ) {
    return LocalUserLifecycleState(
      userId: data.userId.present ? data.userId.value : this.userId,
      isSuspended: data.isSuspended.present
          ? data.isSuspended.value
          : this.isSuspended,
      suspendedAt: data.suspendedAt.present
          ? data.suspendedAt.value
          : this.suspendedAt,
      purgeEligibleAt: data.purgeEligibleAt.present
          ? data.purgeEligibleAt.value
          : this.purgeEligibleAt,
      isEligibleForPurge: data.isEligibleForPurge.present
          ? data.isEligibleForPurge.value
          : this.isEligibleForPurge,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalUserLifecycleState(')
          ..write('userId: $userId, ')
          ..write('isSuspended: $isSuspended, ')
          ..write('suspendedAt: $suspendedAt, ')
          ..write('purgeEligibleAt: $purgeEligibleAt, ')
          ..write('isEligibleForPurge: $isEligibleForPurge, ')
          ..write('checkedAt: $checkedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    isSuspended,
    suspendedAt,
    purgeEligibleAt,
    isEligibleForPurge,
    checkedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalUserLifecycleState &&
          other.userId == this.userId &&
          other.isSuspended == this.isSuspended &&
          other.suspendedAt == this.suspendedAt &&
          other.purgeEligibleAt == this.purgeEligibleAt &&
          other.isEligibleForPurge == this.isEligibleForPurge &&
          other.checkedAt == this.checkedAt);
}

class LocalUserLifecycleStatesCompanion
    extends UpdateCompanion<LocalUserLifecycleState> {
  final Value<String> userId;
  final Value<bool> isSuspended;
  final Value<DateTime?> suspendedAt;
  final Value<DateTime?> purgeEligibleAt;
  final Value<bool> isEligibleForPurge;
  final Value<DateTime> checkedAt;
  final Value<int> rowid;
  const LocalUserLifecycleStatesCompanion({
    this.userId = const Value.absent(),
    this.isSuspended = const Value.absent(),
    this.suspendedAt = const Value.absent(),
    this.purgeEligibleAt = const Value.absent(),
    this.isEligibleForPurge = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalUserLifecycleStatesCompanion.insert({
    required String userId,
    this.isSuspended = const Value.absent(),
    this.suspendedAt = const Value.absent(),
    this.purgeEligibleAt = const Value.absent(),
    this.isEligibleForPurge = const Value.absent(),
    required DateTime checkedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       checkedAt = Value(checkedAt);
  static Insertable<LocalUserLifecycleState> custom({
    Expression<String>? userId,
    Expression<bool>? isSuspended,
    Expression<DateTime>? suspendedAt,
    Expression<DateTime>? purgeEligibleAt,
    Expression<bool>? isEligibleForPurge,
    Expression<DateTime>? checkedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (isSuspended != null) 'is_suspended': isSuspended,
      if (suspendedAt != null) 'suspended_at': suspendedAt,
      if (purgeEligibleAt != null) 'purge_eligible_at': purgeEligibleAt,
      if (isEligibleForPurge != null)
        'is_eligible_for_purge': isEligibleForPurge,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalUserLifecycleStatesCompanion copyWith({
    Value<String>? userId,
    Value<bool>? isSuspended,
    Value<DateTime?>? suspendedAt,
    Value<DateTime?>? purgeEligibleAt,
    Value<bool>? isEligibleForPurge,
    Value<DateTime>? checkedAt,
    Value<int>? rowid,
  }) {
    return LocalUserLifecycleStatesCompanion(
      userId: userId ?? this.userId,
      isSuspended: isSuspended ?? this.isSuspended,
      suspendedAt: suspendedAt ?? this.suspendedAt,
      purgeEligibleAt: purgeEligibleAt ?? this.purgeEligibleAt,
      isEligibleForPurge: isEligibleForPurge ?? this.isEligibleForPurge,
      checkedAt: checkedAt ?? this.checkedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (isSuspended.present) {
      map['is_suspended'] = Variable<bool>(isSuspended.value);
    }
    if (suspendedAt.present) {
      map['suspended_at'] = Variable<DateTime>(suspendedAt.value);
    }
    if (purgeEligibleAt.present) {
      map['purge_eligible_at'] = Variable<DateTime>(purgeEligibleAt.value);
    }
    if (isEligibleForPurge.present) {
      map['is_eligible_for_purge'] = Variable<bool>(isEligibleForPurge.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalUserLifecycleStatesCompanion(')
          ..write('userId: $userId, ')
          ..write('isSuspended: $isSuspended, ')
          ..write('suspendedAt: $suspendedAt, ')
          ..write('purgeEligibleAt: $purgeEligibleAt, ')
          ..write('isEligibleForPurge: $isEligibleForPurge, ')
          ..write('checkedAt: $checkedAt, ')
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
  late final $LocalNationalFocusCardsTable localNationalFocusCards =
      $LocalNationalFocusCardsTable(this);
  late final $LocalNationalFocusStrengtheningLevelsTable
  localNationalFocusStrengtheningLevels =
      $LocalNationalFocusStrengtheningLevelsTable(this);
  late final $LocalNationalFocusRequirementVersionsTable
  localNationalFocusRequirementVersions =
      $LocalNationalFocusRequirementVersionsTable(this);
  late final $LocalNationalFocusMaintenanceTable localNationalFocusMaintenance =
      $LocalNationalFocusMaintenanceTable(this);
  late final $LocalNationalFocusFailuresTable localNationalFocusFailures =
      $LocalNationalFocusFailuresTable(this);
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
  late final $FocusSourceDevicesTable focusSourceDevices =
      $FocusSourceDevicesTable(this);
  late final $FocusSyncSourcesTable focusSyncSources = $FocusSyncSourcesTable(
    this,
  );
  late final $LocalCalendarSourcesTable localCalendarSources =
      $LocalCalendarSourcesTable(this);
  late final $LocalCalendarBlocksTable localCalendarBlocks =
      $LocalCalendarBlocksTable(this);
  late final $LocalUserLifecycleStatesTable localUserLifecycleStates =
      $LocalUserLifecycleStatesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localGoals,
    localTasks,
    localNationalFocusCards,
    localNationalFocusStrengtheningLevels,
    localNationalFocusRequirementVersions,
    localNationalFocusMaintenance,
    localNationalFocusFailures,
    taskSyncEntries,
    focusSessions,
    focusNodes,
    focusChainRecords,
    focusPreferences,
    focusPrecedentRules,
    focusAppointments,
    appointmentChainRecords,
    focusSourceDevices,
    focusSyncSources,
    localCalendarSources,
    localCalendarBlocks,
    localUserLifecycleStates,
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
typedef $$LocalNationalFocusCardsTableCreateCompanionBuilder =
    LocalNationalFocusCardsCompanion Function({
      required String userId,
      required String id,
      required String triggerCondition,
      required String action,
      Value<String?> scope,
      Value<String?> exceptionNotes,
      Value<bool> isInTree,
      Value<String?> parentId,
      Value<String> state,
      Value<int> successfulDays,
      Value<int> currentConsecutiveDays,
      Value<int> bestConsecutiveDays,
      Value<bool> maintenanceCycleStarted,
      Value<String?> failureReason,
      Value<String?> cascadeSourceCardId,
      Value<String?> cascadePriorState,
      Value<String> reviewDisposition,
      Value<int?> activeStrengtheningLevel,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalNationalFocusCardsTableUpdateCompanionBuilder =
    LocalNationalFocusCardsCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> triggerCondition,
      Value<String> action,
      Value<String?> scope,
      Value<String?> exceptionNotes,
      Value<bool> isInTree,
      Value<String?> parentId,
      Value<String> state,
      Value<int> successfulDays,
      Value<int> currentConsecutiveDays,
      Value<int> bestConsecutiveDays,
      Value<bool> maintenanceCycleStarted,
      Value<String?> failureReason,
      Value<String?> cascadeSourceCardId,
      Value<String?> cascadePriorState,
      Value<String> reviewDisposition,
      Value<int?> activeStrengtheningLevel,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalNationalFocusCardsTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusCardsTable> {
  $$LocalNationalFocusCardsTableFilterComposer({
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

  ColumnFilters<String> get triggerCondition => $composableBuilder(
    column: $table.triggerCondition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exceptionNotes => $composableBuilder(
    column: $table.exceptionNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isInTree => $composableBuilder(
    column: $table.isInTree,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get successfulDays => $composableBuilder(
    column: $table.successfulDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentConsecutiveDays => $composableBuilder(
    column: $table.currentConsecutiveDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bestConsecutiveDays => $composableBuilder(
    column: $table.bestConsecutiveDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get maintenanceCycleStarted => $composableBuilder(
    column: $table.maintenanceCycleStarted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cascadeSourceCardId => $composableBuilder(
    column: $table.cascadeSourceCardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cascadePriorState => $composableBuilder(
    column: $table.cascadePriorState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activeStrengtheningLevel => $composableBuilder(
    column: $table.activeStrengtheningLevel,
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

class $$LocalNationalFocusCardsTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusCardsTable> {
  $$LocalNationalFocusCardsTableOrderingComposer({
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

  ColumnOrderings<String> get triggerCondition => $composableBuilder(
    column: $table.triggerCondition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exceptionNotes => $composableBuilder(
    column: $table.exceptionNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isInTree => $composableBuilder(
    column: $table.isInTree,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get successfulDays => $composableBuilder(
    column: $table.successfulDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentConsecutiveDays => $composableBuilder(
    column: $table.currentConsecutiveDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bestConsecutiveDays => $composableBuilder(
    column: $table.bestConsecutiveDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get maintenanceCycleStarted => $composableBuilder(
    column: $table.maintenanceCycleStarted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cascadeSourceCardId => $composableBuilder(
    column: $table.cascadeSourceCardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cascadePriorState => $composableBuilder(
    column: $table.cascadePriorState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activeStrengtheningLevel => $composableBuilder(
    column: $table.activeStrengtheningLevel,
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

class $$LocalNationalFocusCardsTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusCardsTable> {
  $$LocalNationalFocusCardsTableAnnotationComposer({
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

  GeneratedColumn<String> get triggerCondition => $composableBuilder(
    column: $table.triggerCondition,
    builder: (column) => column,
  );

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get exceptionNotes => $composableBuilder(
    column: $table.exceptionNotes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isInTree =>
      $composableBuilder(column: $table.isInTree, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get successfulDays => $composableBuilder(
    column: $table.successfulDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentConsecutiveDays => $composableBuilder(
    column: $table.currentConsecutiveDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bestConsecutiveDays => $composableBuilder(
    column: $table.bestConsecutiveDays,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get maintenanceCycleStarted => $composableBuilder(
    column: $table.maintenanceCycleStarted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cascadeSourceCardId => $composableBuilder(
    column: $table.cascadeSourceCardId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cascadePriorState => $composableBuilder(
    column: $table.cascadePriorState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => column,
  );

  GeneratedColumn<int> get activeStrengtheningLevel => $composableBuilder(
    column: $table.activeStrengtheningLevel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalNationalFocusCardsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalNationalFocusCardsTable,
          LocalNationalFocusCard,
          $$LocalNationalFocusCardsTableFilterComposer,
          $$LocalNationalFocusCardsTableOrderingComposer,
          $$LocalNationalFocusCardsTableAnnotationComposer,
          $$LocalNationalFocusCardsTableCreateCompanionBuilder,
          $$LocalNationalFocusCardsTableUpdateCompanionBuilder,
          (
            LocalNationalFocusCard,
            BaseReferences<
              _$PactaDatabase,
              $LocalNationalFocusCardsTable,
              LocalNationalFocusCard
            >,
          ),
          LocalNationalFocusCard,
          PrefetchHooks Function()
        > {
  $$LocalNationalFocusCardsTableTableManager(
    _$PactaDatabase db,
    $LocalNationalFocusCardsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalNationalFocusCardsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalNationalFocusCardsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalNationalFocusCardsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> triggerCondition = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> scope = const Value.absent(),
                Value<String?> exceptionNotes = const Value.absent(),
                Value<bool> isInTree = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> successfulDays = const Value.absent(),
                Value<int> currentConsecutiveDays = const Value.absent(),
                Value<int> bestConsecutiveDays = const Value.absent(),
                Value<bool> maintenanceCycleStarted = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> cascadeSourceCardId = const Value.absent(),
                Value<String?> cascadePriorState = const Value.absent(),
                Value<String> reviewDisposition = const Value.absent(),
                Value<int?> activeStrengtheningLevel = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusCardsCompanion(
                userId: userId,
                id: id,
                triggerCondition: triggerCondition,
                action: action,
                scope: scope,
                exceptionNotes: exceptionNotes,
                isInTree: isInTree,
                parentId: parentId,
                state: state,
                successfulDays: successfulDays,
                currentConsecutiveDays: currentConsecutiveDays,
                bestConsecutiveDays: bestConsecutiveDays,
                maintenanceCycleStarted: maintenanceCycleStarted,
                failureReason: failureReason,
                cascadeSourceCardId: cascadeSourceCardId,
                cascadePriorState: cascadePriorState,
                reviewDisposition: reviewDisposition,
                activeStrengtheningLevel: activeStrengtheningLevel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String triggerCondition,
                required String action,
                Value<String?> scope = const Value.absent(),
                Value<String?> exceptionNotes = const Value.absent(),
                Value<bool> isInTree = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> successfulDays = const Value.absent(),
                Value<int> currentConsecutiveDays = const Value.absent(),
                Value<int> bestConsecutiveDays = const Value.absent(),
                Value<bool> maintenanceCycleStarted = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> cascadeSourceCardId = const Value.absent(),
                Value<String?> cascadePriorState = const Value.absent(),
                Value<String> reviewDisposition = const Value.absent(),
                Value<int?> activeStrengtheningLevel = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusCardsCompanion.insert(
                userId: userId,
                id: id,
                triggerCondition: triggerCondition,
                action: action,
                scope: scope,
                exceptionNotes: exceptionNotes,
                isInTree: isInTree,
                parentId: parentId,
                state: state,
                successfulDays: successfulDays,
                currentConsecutiveDays: currentConsecutiveDays,
                bestConsecutiveDays: bestConsecutiveDays,
                maintenanceCycleStarted: maintenanceCycleStarted,
                failureReason: failureReason,
                cascadeSourceCardId: cascadeSourceCardId,
                cascadePriorState: cascadePriorState,
                reviewDisposition: reviewDisposition,
                activeStrengtheningLevel: activeStrengtheningLevel,
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

typedef $$LocalNationalFocusCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalNationalFocusCardsTable,
      LocalNationalFocusCard,
      $$LocalNationalFocusCardsTableFilterComposer,
      $$LocalNationalFocusCardsTableOrderingComposer,
      $$LocalNationalFocusCardsTableAnnotationComposer,
      $$LocalNationalFocusCardsTableCreateCompanionBuilder,
      $$LocalNationalFocusCardsTableUpdateCompanionBuilder,
      (
        LocalNationalFocusCard,
        BaseReferences<
          _$PactaDatabase,
          $LocalNationalFocusCardsTable,
          LocalNationalFocusCard
        >,
      ),
      LocalNationalFocusCard,
      PrefetchHooks Function()
    >;
typedef $$LocalNationalFocusStrengtheningLevelsTableCreateCompanionBuilder =
    LocalNationalFocusStrengtheningLevelsCompanion Function({
      required String userId,
      required String cardId,
      required int levelNumber,
      Value<String?> triggerConditionOverride,
      Value<String?> actionOverride,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalNationalFocusStrengtheningLevelsTableUpdateCompanionBuilder =
    LocalNationalFocusStrengtheningLevelsCompanion Function({
      Value<String> userId,
      Value<String> cardId,
      Value<int> levelNumber,
      Value<String?> triggerConditionOverride,
      Value<String?> actionOverride,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalNationalFocusStrengtheningLevelsTableFilterComposer
    extends
        Composer<_$PactaDatabase, $LocalNationalFocusStrengtheningLevelsTable> {
  $$LocalNationalFocusStrengtheningLevelsTableFilterComposer({
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

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get levelNumber => $composableBuilder(
    column: $table.levelNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerConditionOverride => $composableBuilder(
    column: $table.triggerConditionOverride,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actionOverride => $composableBuilder(
    column: $table.actionOverride,
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
}

class $$LocalNationalFocusStrengtheningLevelsTableOrderingComposer
    extends
        Composer<_$PactaDatabase, $LocalNationalFocusStrengtheningLevelsTable> {
  $$LocalNationalFocusStrengtheningLevelsTableOrderingComposer({
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

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get levelNumber => $composableBuilder(
    column: $table.levelNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerConditionOverride => $composableBuilder(
    column: $table.triggerConditionOverride,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actionOverride => $composableBuilder(
    column: $table.actionOverride,
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
}

class $$LocalNationalFocusStrengtheningLevelsTableAnnotationComposer
    extends
        Composer<_$PactaDatabase, $LocalNationalFocusStrengtheningLevelsTable> {
  $$LocalNationalFocusStrengtheningLevelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<int> get levelNumber => $composableBuilder(
    column: $table.levelNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get triggerConditionOverride => $composableBuilder(
    column: $table.triggerConditionOverride,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actionOverride => $composableBuilder(
    column: $table.actionOverride,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalNationalFocusStrengtheningLevelsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalNationalFocusStrengtheningLevelsTable,
          LocalNationalFocusStrengtheningLevel,
          $$LocalNationalFocusStrengtheningLevelsTableFilterComposer,
          $$LocalNationalFocusStrengtheningLevelsTableOrderingComposer,
          $$LocalNationalFocusStrengtheningLevelsTableAnnotationComposer,
          $$LocalNationalFocusStrengtheningLevelsTableCreateCompanionBuilder,
          $$LocalNationalFocusStrengtheningLevelsTableUpdateCompanionBuilder,
          (
            LocalNationalFocusStrengtheningLevel,
            BaseReferences<
              _$PactaDatabase,
              $LocalNationalFocusStrengtheningLevelsTable,
              LocalNationalFocusStrengtheningLevel
            >,
          ),
          LocalNationalFocusStrengtheningLevel,
          PrefetchHooks Function()
        > {
  $$LocalNationalFocusStrengtheningLevelsTableTableManager(
    _$PactaDatabase db,
    $LocalNationalFocusStrengtheningLevelsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalNationalFocusStrengtheningLevelsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalNationalFocusStrengtheningLevelsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalNationalFocusStrengtheningLevelsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<int> levelNumber = const Value.absent(),
                Value<String?> triggerConditionOverride = const Value.absent(),
                Value<String?> actionOverride = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusStrengtheningLevelsCompanion(
                userId: userId,
                cardId: cardId,
                levelNumber: levelNumber,
                triggerConditionOverride: triggerConditionOverride,
                actionOverride: actionOverride,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String cardId,
                required int levelNumber,
                Value<String?> triggerConditionOverride = const Value.absent(),
                Value<String?> actionOverride = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusStrengtheningLevelsCompanion.insert(
                userId: userId,
                cardId: cardId,
                levelNumber: levelNumber,
                triggerConditionOverride: triggerConditionOverride,
                actionOverride: actionOverride,
                createdAt: createdAt,
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

typedef $$LocalNationalFocusStrengtheningLevelsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalNationalFocusStrengtheningLevelsTable,
      LocalNationalFocusStrengtheningLevel,
      $$LocalNationalFocusStrengtheningLevelsTableFilterComposer,
      $$LocalNationalFocusStrengtheningLevelsTableOrderingComposer,
      $$LocalNationalFocusStrengtheningLevelsTableAnnotationComposer,
      $$LocalNationalFocusStrengtheningLevelsTableCreateCompanionBuilder,
      $$LocalNationalFocusStrengtheningLevelsTableUpdateCompanionBuilder,
      (
        LocalNationalFocusStrengtheningLevel,
        BaseReferences<
          _$PactaDatabase,
          $LocalNationalFocusStrengtheningLevelsTable,
          LocalNationalFocusStrengtheningLevel
        >,
      ),
      LocalNationalFocusStrengtheningLevel,
      PrefetchHooks Function()
    >;
typedef $$LocalNationalFocusRequirementVersionsTableCreateCompanionBuilder =
    LocalNationalFocusRequirementVersionsCompanion Function({
      required String userId,
      required String id,
      required String cardId,
      required int versionNumber,
      Value<int?> strengtheningLevelNumber,
      required String effectiveTriggerCondition,
      required String effectiveAction,
      Value<String?> scope,
      Value<String?> exceptionNotes,
      required DateTime effectiveFrom,
      Value<DateTime?> effectiveUntil,
      Value<int> rowid,
    });
typedef $$LocalNationalFocusRequirementVersionsTableUpdateCompanionBuilder =
    LocalNationalFocusRequirementVersionsCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> cardId,
      Value<int> versionNumber,
      Value<int?> strengtheningLevelNumber,
      Value<String> effectiveTriggerCondition,
      Value<String> effectiveAction,
      Value<String?> scope,
      Value<String?> exceptionNotes,
      Value<DateTime> effectiveFrom,
      Value<DateTime?> effectiveUntil,
      Value<int> rowid,
    });

class $$LocalNationalFocusRequirementVersionsTableFilterComposer
    extends
        Composer<_$PactaDatabase, $LocalNationalFocusRequirementVersionsTable> {
  $$LocalNationalFocusRequirementVersionsTableFilterComposer({
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

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionNumber => $composableBuilder(
    column: $table.versionNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get strengtheningLevelNumber => $composableBuilder(
    column: $table.strengtheningLevelNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveTriggerCondition => $composableBuilder(
    column: $table.effectiveTriggerCondition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveAction => $composableBuilder(
    column: $table.effectiveAction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exceptionNotes => $composableBuilder(
    column: $table.exceptionNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get effectiveUntil => $composableBuilder(
    column: $table.effectiveUntil,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalNationalFocusRequirementVersionsTableOrderingComposer
    extends
        Composer<_$PactaDatabase, $LocalNationalFocusRequirementVersionsTable> {
  $$LocalNationalFocusRequirementVersionsTableOrderingComposer({
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

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionNumber => $composableBuilder(
    column: $table.versionNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get strengtheningLevelNumber => $composableBuilder(
    column: $table.strengtheningLevelNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveTriggerCondition => $composableBuilder(
    column: $table.effectiveTriggerCondition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveAction => $composableBuilder(
    column: $table.effectiveAction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exceptionNotes => $composableBuilder(
    column: $table.exceptionNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get effectiveUntil => $composableBuilder(
    column: $table.effectiveUntil,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalNationalFocusRequirementVersionsTableAnnotationComposer
    extends
        Composer<_$PactaDatabase, $LocalNationalFocusRequirementVersionsTable> {
  $$LocalNationalFocusRequirementVersionsTableAnnotationComposer({
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

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<int> get versionNumber => $composableBuilder(
    column: $table.versionNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get strengtheningLevelNumber => $composableBuilder(
    column: $table.strengtheningLevelNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveTriggerCondition => $composableBuilder(
    column: $table.effectiveTriggerCondition,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveAction => $composableBuilder(
    column: $table.effectiveAction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get exceptionNotes => $composableBuilder(
    column: $table.exceptionNotes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get effectiveUntil => $composableBuilder(
    column: $table.effectiveUntil,
    builder: (column) => column,
  );
}

class $$LocalNationalFocusRequirementVersionsTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalNationalFocusRequirementVersionsTable,
          LocalNationalFocusRequirementVersion,
          $$LocalNationalFocusRequirementVersionsTableFilterComposer,
          $$LocalNationalFocusRequirementVersionsTableOrderingComposer,
          $$LocalNationalFocusRequirementVersionsTableAnnotationComposer,
          $$LocalNationalFocusRequirementVersionsTableCreateCompanionBuilder,
          $$LocalNationalFocusRequirementVersionsTableUpdateCompanionBuilder,
          (
            LocalNationalFocusRequirementVersion,
            BaseReferences<
              _$PactaDatabase,
              $LocalNationalFocusRequirementVersionsTable,
              LocalNationalFocusRequirementVersion
            >,
          ),
          LocalNationalFocusRequirementVersion,
          PrefetchHooks Function()
        > {
  $$LocalNationalFocusRequirementVersionsTableTableManager(
    _$PactaDatabase db,
    $LocalNationalFocusRequirementVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalNationalFocusRequirementVersionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalNationalFocusRequirementVersionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalNationalFocusRequirementVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<int> versionNumber = const Value.absent(),
                Value<int?> strengtheningLevelNumber = const Value.absent(),
                Value<String> effectiveTriggerCondition = const Value.absent(),
                Value<String> effectiveAction = const Value.absent(),
                Value<String?> scope = const Value.absent(),
                Value<String?> exceptionNotes = const Value.absent(),
                Value<DateTime> effectiveFrom = const Value.absent(),
                Value<DateTime?> effectiveUntil = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusRequirementVersionsCompanion(
                userId: userId,
                id: id,
                cardId: cardId,
                versionNumber: versionNumber,
                strengtheningLevelNumber: strengtheningLevelNumber,
                effectiveTriggerCondition: effectiveTriggerCondition,
                effectiveAction: effectiveAction,
                scope: scope,
                exceptionNotes: exceptionNotes,
                effectiveFrom: effectiveFrom,
                effectiveUntil: effectiveUntil,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String cardId,
                required int versionNumber,
                Value<int?> strengtheningLevelNumber = const Value.absent(),
                required String effectiveTriggerCondition,
                required String effectiveAction,
                Value<String?> scope = const Value.absent(),
                Value<String?> exceptionNotes = const Value.absent(),
                required DateTime effectiveFrom,
                Value<DateTime?> effectiveUntil = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusRequirementVersionsCompanion.insert(
                userId: userId,
                id: id,
                cardId: cardId,
                versionNumber: versionNumber,
                strengtheningLevelNumber: strengtheningLevelNumber,
                effectiveTriggerCondition: effectiveTriggerCondition,
                effectiveAction: effectiveAction,
                scope: scope,
                exceptionNotes: exceptionNotes,
                effectiveFrom: effectiveFrom,
                effectiveUntil: effectiveUntil,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalNationalFocusRequirementVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalNationalFocusRequirementVersionsTable,
      LocalNationalFocusRequirementVersion,
      $$LocalNationalFocusRequirementVersionsTableFilterComposer,
      $$LocalNationalFocusRequirementVersionsTableOrderingComposer,
      $$LocalNationalFocusRequirementVersionsTableAnnotationComposer,
      $$LocalNationalFocusRequirementVersionsTableCreateCompanionBuilder,
      $$LocalNationalFocusRequirementVersionsTableUpdateCompanionBuilder,
      (
        LocalNationalFocusRequirementVersion,
        BaseReferences<
          _$PactaDatabase,
          $LocalNationalFocusRequirementVersionsTable,
          LocalNationalFocusRequirementVersion
        >,
      ),
      LocalNationalFocusRequirementVersion,
      PrefetchHooks Function()
    >;
typedef $$LocalNationalFocusMaintenanceTableCreateCompanionBuilder =
    LocalNationalFocusMaintenanceCompanion Function({
      required String userId,
      required DateTime lastSettledCheckpointAt,
      Value<int> rowid,
    });
typedef $$LocalNationalFocusMaintenanceTableUpdateCompanionBuilder =
    LocalNationalFocusMaintenanceCompanion Function({
      Value<String> userId,
      Value<DateTime> lastSettledCheckpointAt,
      Value<int> rowid,
    });

class $$LocalNationalFocusMaintenanceTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusMaintenanceTable> {
  $$LocalNationalFocusMaintenanceTableFilterComposer({
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

  ColumnFilters<DateTime> get lastSettledCheckpointAt => $composableBuilder(
    column: $table.lastSettledCheckpointAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalNationalFocusMaintenanceTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusMaintenanceTable> {
  $$LocalNationalFocusMaintenanceTableOrderingComposer({
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

  ColumnOrderings<DateTime> get lastSettledCheckpointAt => $composableBuilder(
    column: $table.lastSettledCheckpointAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalNationalFocusMaintenanceTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusMaintenanceTable> {
  $$LocalNationalFocusMaintenanceTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSettledCheckpointAt => $composableBuilder(
    column: $table.lastSettledCheckpointAt,
    builder: (column) => column,
  );
}

class $$LocalNationalFocusMaintenanceTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalNationalFocusMaintenanceTable,
          LocalNationalFocusMaintenanceData,
          $$LocalNationalFocusMaintenanceTableFilterComposer,
          $$LocalNationalFocusMaintenanceTableOrderingComposer,
          $$LocalNationalFocusMaintenanceTableAnnotationComposer,
          $$LocalNationalFocusMaintenanceTableCreateCompanionBuilder,
          $$LocalNationalFocusMaintenanceTableUpdateCompanionBuilder,
          (
            LocalNationalFocusMaintenanceData,
            BaseReferences<
              _$PactaDatabase,
              $LocalNationalFocusMaintenanceTable,
              LocalNationalFocusMaintenanceData
            >,
          ),
          LocalNationalFocusMaintenanceData,
          PrefetchHooks Function()
        > {
  $$LocalNationalFocusMaintenanceTableTableManager(
    _$PactaDatabase db,
    $LocalNationalFocusMaintenanceTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalNationalFocusMaintenanceTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalNationalFocusMaintenanceTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalNationalFocusMaintenanceTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<DateTime> lastSettledCheckpointAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusMaintenanceCompanion(
                userId: userId,
                lastSettledCheckpointAt: lastSettledCheckpointAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required DateTime lastSettledCheckpointAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusMaintenanceCompanion.insert(
                userId: userId,
                lastSettledCheckpointAt: lastSettledCheckpointAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalNationalFocusMaintenanceTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalNationalFocusMaintenanceTable,
      LocalNationalFocusMaintenanceData,
      $$LocalNationalFocusMaintenanceTableFilterComposer,
      $$LocalNationalFocusMaintenanceTableOrderingComposer,
      $$LocalNationalFocusMaintenanceTableAnnotationComposer,
      $$LocalNationalFocusMaintenanceTableCreateCompanionBuilder,
      $$LocalNationalFocusMaintenanceTableUpdateCompanionBuilder,
      (
        LocalNationalFocusMaintenanceData,
        BaseReferences<
          _$PactaDatabase,
          $LocalNationalFocusMaintenanceTable,
          LocalNationalFocusMaintenanceData
        >,
      ),
      LocalNationalFocusMaintenanceData,
      PrefetchHooks Function()
    >;
typedef $$LocalNationalFocusFailuresTableCreateCompanionBuilder =
    LocalNationalFocusFailuresCompanion Function({
      required String userId,
      required String id,
      required String batchId,
      required String cardId,
      required DateTime checkpointAt,
      required String cause,
      Value<String?> failureReason,
      Value<String?> sharedExplanation,
      required String treeSnapshot,
      Value<String> reviewDisposition,
      Value<int> rowid,
    });
typedef $$LocalNationalFocusFailuresTableUpdateCompanionBuilder =
    LocalNationalFocusFailuresCompanion Function({
      Value<String> userId,
      Value<String> id,
      Value<String> batchId,
      Value<String> cardId,
      Value<DateTime> checkpointAt,
      Value<String> cause,
      Value<String?> failureReason,
      Value<String?> sharedExplanation,
      Value<String> treeSnapshot,
      Value<String> reviewDisposition,
      Value<int> rowid,
    });

class $$LocalNationalFocusFailuresTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusFailuresTable> {
  $$LocalNationalFocusFailuresTableFilterComposer({
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

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkpointAt => $composableBuilder(
    column: $table.checkpointAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cause => $composableBuilder(
    column: $table.cause,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sharedExplanation => $composableBuilder(
    column: $table.sharedExplanation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get treeSnapshot => $composableBuilder(
    column: $table.treeSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalNationalFocusFailuresTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusFailuresTable> {
  $$LocalNationalFocusFailuresTableOrderingComposer({
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

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkpointAt => $composableBuilder(
    column: $table.checkpointAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cause => $composableBuilder(
    column: $table.cause,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sharedExplanation => $composableBuilder(
    column: $table.sharedExplanation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get treeSnapshot => $composableBuilder(
    column: $table.treeSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalNationalFocusFailuresTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalNationalFocusFailuresTable> {
  $$LocalNationalFocusFailuresTableAnnotationComposer({
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

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<DateTime> get checkpointAt => $composableBuilder(
    column: $table.checkpointAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cause =>
      $composableBuilder(column: $table.cause, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sharedExplanation => $composableBuilder(
    column: $table.sharedExplanation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get treeSnapshot => $composableBuilder(
    column: $table.treeSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => column,
  );
}

class $$LocalNationalFocusFailuresTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalNationalFocusFailuresTable,
          LocalNationalFocusFailure,
          $$LocalNationalFocusFailuresTableFilterComposer,
          $$LocalNationalFocusFailuresTableOrderingComposer,
          $$LocalNationalFocusFailuresTableAnnotationComposer,
          $$LocalNationalFocusFailuresTableCreateCompanionBuilder,
          $$LocalNationalFocusFailuresTableUpdateCompanionBuilder,
          (
            LocalNationalFocusFailure,
            BaseReferences<
              _$PactaDatabase,
              $LocalNationalFocusFailuresTable,
              LocalNationalFocusFailure
            >,
          ),
          LocalNationalFocusFailure,
          PrefetchHooks Function()
        > {
  $$LocalNationalFocusFailuresTableTableManager(
    _$PactaDatabase db,
    $LocalNationalFocusFailuresTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalNationalFocusFailuresTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalNationalFocusFailuresTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalNationalFocusFailuresTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<DateTime> checkpointAt = const Value.absent(),
                Value<String> cause = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> sharedExplanation = const Value.absent(),
                Value<String> treeSnapshot = const Value.absent(),
                Value<String> reviewDisposition = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusFailuresCompanion(
                userId: userId,
                id: id,
                batchId: batchId,
                cardId: cardId,
                checkpointAt: checkpointAt,
                cause: cause,
                failureReason: failureReason,
                sharedExplanation: sharedExplanation,
                treeSnapshot: treeSnapshot,
                reviewDisposition: reviewDisposition,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String id,
                required String batchId,
                required String cardId,
                required DateTime checkpointAt,
                required String cause,
                Value<String?> failureReason = const Value.absent(),
                Value<String?> sharedExplanation = const Value.absent(),
                required String treeSnapshot,
                Value<String> reviewDisposition = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalNationalFocusFailuresCompanion.insert(
                userId: userId,
                id: id,
                batchId: batchId,
                cardId: cardId,
                checkpointAt: checkpointAt,
                cause: cause,
                failureReason: failureReason,
                sharedExplanation: sharedExplanation,
                treeSnapshot: treeSnapshot,
                reviewDisposition: reviewDisposition,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalNationalFocusFailuresTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalNationalFocusFailuresTable,
      LocalNationalFocusFailure,
      $$LocalNationalFocusFailuresTableFilterComposer,
      $$LocalNationalFocusFailuresTableOrderingComposer,
      $$LocalNationalFocusFailuresTableAnnotationComposer,
      $$LocalNationalFocusFailuresTableCreateCompanionBuilder,
      $$LocalNationalFocusFailuresTableUpdateCompanionBuilder,
      (
        LocalNationalFocusFailure,
        BaseReferences<
          _$PactaDatabase,
          $LocalNationalFocusFailuresTable,
          LocalNationalFocusFailure
        >,
      ),
      LocalNationalFocusFailure,
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
      Value<String?> configurationBasisSourceId,
      Value<String?> outcomeBasisSourceId,
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
      Value<String?> configurationBasisSourceId,
      Value<String?> outcomeBasisSourceId,
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

  ColumnFilters<String> get configurationBasisSourceId => $composableBuilder(
    column: $table.configurationBasisSourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcomeBasisSourceId => $composableBuilder(
    column: $table.outcomeBasisSourceId,
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

  ColumnOrderings<String> get configurationBasisSourceId => $composableBuilder(
    column: $table.configurationBasisSourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcomeBasisSourceId => $composableBuilder(
    column: $table.outcomeBasisSourceId,
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

  GeneratedColumn<String> get configurationBasisSourceId => $composableBuilder(
    column: $table.configurationBasisSourceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outcomeBasisSourceId => $composableBuilder(
    column: $table.outcomeBasisSourceId,
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
                Value<String?> configurationBasisSourceId =
                    const Value.absent(),
                Value<String?> outcomeBasisSourceId = const Value.absent(),
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
                configurationBasisSourceId: configurationBasisSourceId,
                outcomeBasisSourceId: outcomeBasisSourceId,
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
                Value<String?> configurationBasisSourceId =
                    const Value.absent(),
                Value<String?> outcomeBasisSourceId = const Value.absent(),
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
                configurationBasisSourceId: configurationBasisSourceId,
                outcomeBasisSourceId: outcomeBasisSourceId,
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
      Value<String> reviewDisposition,
      Value<DateTime?> reviewDispositionUpdatedAt,
      Value<String?> configurationBasisSourceId,
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
      Value<String> reviewDisposition,
      Value<DateTime?> reviewDispositionUpdatedAt,
      Value<String?> configurationBasisSourceId,
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

  ColumnFilters<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reviewDispositionUpdatedAt => $composableBuilder(
    column: $table.reviewDispositionUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configurationBasisSourceId => $composableBuilder(
    column: $table.configurationBasisSourceId,
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

  ColumnOrderings<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reviewDispositionUpdatedAt =>
      $composableBuilder(
        column: $table.reviewDispositionUpdatedAt,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<String> get configurationBasisSourceId => $composableBuilder(
    column: $table.configurationBasisSourceId,
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

  GeneratedColumn<String> get reviewDisposition => $composableBuilder(
    column: $table.reviewDisposition,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get reviewDispositionUpdatedAt =>
      $composableBuilder(
        column: $table.reviewDispositionUpdatedAt,
        builder: (column) => column,
      );

  GeneratedColumn<String> get configurationBasisSourceId => $composableBuilder(
    column: $table.configurationBasisSourceId,
    builder: (column) => column,
  );
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
                Value<String> reviewDisposition = const Value.absent(),
                Value<DateTime?> reviewDispositionUpdatedAt =
                    const Value.absent(),
                Value<String?> configurationBasisSourceId =
                    const Value.absent(),
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
                reviewDisposition: reviewDisposition,
                reviewDispositionUpdatedAt: reviewDispositionUpdatedAt,
                configurationBasisSourceId: configurationBasisSourceId,
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
                Value<String> reviewDisposition = const Value.absent(),
                Value<DateTime?> reviewDispositionUpdatedAt =
                    const Value.absent(),
                Value<String?> configurationBasisSourceId =
                    const Value.absent(),
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
                reviewDisposition: reviewDisposition,
                reviewDispositionUpdatedAt: reviewDispositionUpdatedAt,
                configurationBasisSourceId: configurationBasisSourceId,
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
typedef $$FocusSourceDevicesTableCreateCompanionBuilder =
    FocusSourceDevicesCompanion Function({
      required String userId,
      required String deviceId,
      Value<int> rowid,
    });
typedef $$FocusSourceDevicesTableUpdateCompanionBuilder =
    FocusSourceDevicesCompanion Function({
      Value<String> userId,
      Value<String> deviceId,
      Value<int> rowid,
    });

class $$FocusSourceDevicesTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusSourceDevicesTable> {
  $$FocusSourceDevicesTableFilterComposer({
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

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusSourceDevicesTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusSourceDevicesTable> {
  $$FocusSourceDevicesTableOrderingComposer({
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

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusSourceDevicesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusSourceDevicesTable> {
  $$FocusSourceDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);
}

class $$FocusSourceDevicesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusSourceDevicesTable,
          FocusSourceDevice,
          $$FocusSourceDevicesTableFilterComposer,
          $$FocusSourceDevicesTableOrderingComposer,
          $$FocusSourceDevicesTableAnnotationComposer,
          $$FocusSourceDevicesTableCreateCompanionBuilder,
          $$FocusSourceDevicesTableUpdateCompanionBuilder,
          (
            FocusSourceDevice,
            BaseReferences<
              _$PactaDatabase,
              $FocusSourceDevicesTable,
              FocusSourceDevice
            >,
          ),
          FocusSourceDevice,
          PrefetchHooks Function()
        > {
  $$FocusSourceDevicesTableTableManager(
    _$PactaDatabase db,
    $FocusSourceDevicesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSourceDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSourceDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSourceDevicesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusSourceDevicesCompanion(
                userId: userId,
                deviceId: deviceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String deviceId,
                Value<int> rowid = const Value.absent(),
              }) => FocusSourceDevicesCompanion.insert(
                userId: userId,
                deviceId: deviceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FocusSourceDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusSourceDevicesTable,
      FocusSourceDevice,
      $$FocusSourceDevicesTableFilterComposer,
      $$FocusSourceDevicesTableOrderingComposer,
      $$FocusSourceDevicesTableAnnotationComposer,
      $$FocusSourceDevicesTableCreateCompanionBuilder,
      $$FocusSourceDevicesTableUpdateCompanionBuilder,
      (
        FocusSourceDevice,
        BaseReferences<
          _$PactaDatabase,
          $FocusSourceDevicesTable,
          FocusSourceDevice
        >,
      ),
      FocusSourceDevice,
      PrefetchHooks Function()
    >;
typedef $$FocusSyncSourcesTableCreateCompanionBuilder =
    FocusSyncSourcesCompanion Function({
      required String userId,
      required String sourceId,
      required String deviceId,
      required String entityType,
      required String entityId,
      Value<String?> parentSourceId,
      Value<String> parentSourceIds,
      required DateTime occurredAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$FocusSyncSourcesTableUpdateCompanionBuilder =
    FocusSyncSourcesCompanion Function({
      Value<String> userId,
      Value<String> sourceId,
      Value<String> deviceId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String?> parentSourceId,
      Value<String> parentSourceIds,
      Value<DateTime> occurredAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$FocusSyncSourcesTableFilterComposer
    extends Composer<_$PactaDatabase, $FocusSyncSourcesTable> {
  $$FocusSyncSourcesTableFilterComposer({
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

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
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

  ColumnFilters<String> get parentSourceId => $composableBuilder(
    column: $table.parentSourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentSourceIds => $composableBuilder(
    column: $table.parentSourceIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FocusSyncSourcesTableOrderingComposer
    extends Composer<_$PactaDatabase, $FocusSyncSourcesTable> {
  $$FocusSyncSourcesTableOrderingComposer({
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

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
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

  ColumnOrderings<String> get parentSourceId => $composableBuilder(
    column: $table.parentSourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentSourceIds => $composableBuilder(
    column: $table.parentSourceIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FocusSyncSourcesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $FocusSyncSourcesTable> {
  $$FocusSyncSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get parentSourceId => $composableBuilder(
    column: $table.parentSourceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentSourceIds => $composableBuilder(
    column: $table.parentSourceIds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$FocusSyncSourcesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $FocusSyncSourcesTable,
          FocusSyncSource,
          $$FocusSyncSourcesTableFilterComposer,
          $$FocusSyncSourcesTableOrderingComposer,
          $$FocusSyncSourcesTableAnnotationComposer,
          $$FocusSyncSourcesTableCreateCompanionBuilder,
          $$FocusSyncSourcesTableUpdateCompanionBuilder,
          (
            FocusSyncSource,
            BaseReferences<
              _$PactaDatabase,
              $FocusSyncSourcesTable,
              FocusSyncSource
            >,
          ),
          FocusSyncSource,
          PrefetchHooks Function()
        > {
  $$FocusSyncSourcesTableTableManager(
    _$PactaDatabase db,
    $FocusSyncSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSyncSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSyncSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSyncSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String?> parentSourceId = const Value.absent(),
                Value<String> parentSourceIds = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FocusSyncSourcesCompanion(
                userId: userId,
                sourceId: sourceId,
                deviceId: deviceId,
                entityType: entityType,
                entityId: entityId,
                parentSourceId: parentSourceId,
                parentSourceIds: parentSourceIds,
                occurredAt: occurredAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String sourceId,
                required String deviceId,
                required String entityType,
                required String entityId,
                Value<String?> parentSourceId = const Value.absent(),
                Value<String> parentSourceIds = const Value.absent(),
                required DateTime occurredAt,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => FocusSyncSourcesCompanion.insert(
                userId: userId,
                sourceId: sourceId,
                deviceId: deviceId,
                entityType: entityType,
                entityId: entityId,
                parentSourceId: parentSourceId,
                parentSourceIds: parentSourceIds,
                occurredAt: occurredAt,
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

typedef $$FocusSyncSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $FocusSyncSourcesTable,
      FocusSyncSource,
      $$FocusSyncSourcesTableFilterComposer,
      $$FocusSyncSourcesTableOrderingComposer,
      $$FocusSyncSourcesTableAnnotationComposer,
      $$FocusSyncSourcesTableCreateCompanionBuilder,
      $$FocusSyncSourcesTableUpdateCompanionBuilder,
      (
        FocusSyncSource,
        BaseReferences<
          _$PactaDatabase,
          $FocusSyncSourcesTable,
          FocusSyncSource
        >,
      ),
      FocusSyncSource,
      PrefetchHooks Function()
    >;
typedef $$LocalCalendarSourcesTableCreateCompanionBuilder =
    LocalCalendarSourcesCompanion Function({
      required String userId,
      required String sourceId,
      required String displayName,
      required String timeZoneId,
      Value<String?> localCalendarId,
      Value<bool> isSelected,
      Value<bool> isStale,
      Value<bool> isDeleted,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalCalendarSourcesTableUpdateCompanionBuilder =
    LocalCalendarSourcesCompanion Function({
      Value<String> userId,
      Value<String> sourceId,
      Value<String> displayName,
      Value<String> timeZoneId,
      Value<String?> localCalendarId,
      Value<bool> isSelected,
      Value<bool> isStale,
      Value<bool> isDeleted,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalCalendarSourcesTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalCalendarSourcesTable> {
  $$LocalCalendarSourcesTableFilterComposer({
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

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeZoneId => $composableBuilder(
    column: $table.timeZoneId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localCalendarId => $composableBuilder(
    column: $table.localCalendarId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSelected => $composableBuilder(
    column: $table.isSelected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isStale => $composableBuilder(
    column: $table.isStale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCalendarSourcesTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalCalendarSourcesTable> {
  $$LocalCalendarSourcesTableOrderingComposer({
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

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeZoneId => $composableBuilder(
    column: $table.timeZoneId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localCalendarId => $composableBuilder(
    column: $table.localCalendarId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSelected => $composableBuilder(
    column: $table.isSelected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isStale => $composableBuilder(
    column: $table.isStale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCalendarSourcesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalCalendarSourcesTable> {
  $$LocalCalendarSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeZoneId => $composableBuilder(
    column: $table.timeZoneId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localCalendarId => $composableBuilder(
    column: $table.localCalendarId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isSelected => $composableBuilder(
    column: $table.isSelected,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isStale =>
      $composableBuilder(column: $table.isStale, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalCalendarSourcesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalCalendarSourcesTable,
          LocalCalendarSource,
          $$LocalCalendarSourcesTableFilterComposer,
          $$LocalCalendarSourcesTableOrderingComposer,
          $$LocalCalendarSourcesTableAnnotationComposer,
          $$LocalCalendarSourcesTableCreateCompanionBuilder,
          $$LocalCalendarSourcesTableUpdateCompanionBuilder,
          (
            LocalCalendarSource,
            BaseReferences<
              _$PactaDatabase,
              $LocalCalendarSourcesTable,
              LocalCalendarSource
            >,
          ),
          LocalCalendarSource,
          PrefetchHooks Function()
        > {
  $$LocalCalendarSourcesTableTableManager(
    _$PactaDatabase db,
    $LocalCalendarSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCalendarSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCalendarSourcesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalCalendarSourcesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> timeZoneId = const Value.absent(),
                Value<String?> localCalendarId = const Value.absent(),
                Value<bool> isSelected = const Value.absent(),
                Value<bool> isStale = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCalendarSourcesCompanion(
                userId: userId,
                sourceId: sourceId,
                displayName: displayName,
                timeZoneId: timeZoneId,
                localCalendarId: localCalendarId,
                isSelected: isSelected,
                isStale: isStale,
                isDeleted: isDeleted,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String sourceId,
                required String displayName,
                required String timeZoneId,
                Value<String?> localCalendarId = const Value.absent(),
                Value<bool> isSelected = const Value.absent(),
                Value<bool> isStale = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalCalendarSourcesCompanion.insert(
                userId: userId,
                sourceId: sourceId,
                displayName: displayName,
                timeZoneId: timeZoneId,
                localCalendarId: localCalendarId,
                isSelected: isSelected,
                isStale: isStale,
                isDeleted: isDeleted,
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

typedef $$LocalCalendarSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalCalendarSourcesTable,
      LocalCalendarSource,
      $$LocalCalendarSourcesTableFilterComposer,
      $$LocalCalendarSourcesTableOrderingComposer,
      $$LocalCalendarSourcesTableAnnotationComposer,
      $$LocalCalendarSourcesTableCreateCompanionBuilder,
      $$LocalCalendarSourcesTableUpdateCompanionBuilder,
      (
        LocalCalendarSource,
        BaseReferences<
          _$PactaDatabase,
          $LocalCalendarSourcesTable,
          LocalCalendarSource
        >,
      ),
      LocalCalendarSource,
      PrefetchHooks Function()
    >;
typedef $$LocalCalendarBlocksTableCreateCompanionBuilder =
    LocalCalendarBlocksCompanion Function({
      required String userId,
      required String sourceId,
      required String sourceEventId,
      required String occurrenceId,
      required String eventIdentity,
      required String title,
      required DateTime startsAt,
      required DateTime endsAt,
      Value<bool> allDay,
      Value<String?> allDayStartDate,
      Value<String?> allDayEndDateExclusive,
      required String availability,
      required String timeZoneId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalCalendarBlocksTableUpdateCompanionBuilder =
    LocalCalendarBlocksCompanion Function({
      Value<String> userId,
      Value<String> sourceId,
      Value<String> sourceEventId,
      Value<String> occurrenceId,
      Value<String> eventIdentity,
      Value<String> title,
      Value<DateTime> startsAt,
      Value<DateTime> endsAt,
      Value<bool> allDay,
      Value<String?> allDayStartDate,
      Value<String?> allDayEndDateExclusive,
      Value<String> availability,
      Value<String> timeZoneId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalCalendarBlocksTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalCalendarBlocksTable> {
  $$LocalCalendarBlocksTableFilterComposer({
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

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrenceId => $composableBuilder(
    column: $table.occurrenceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventIdentity => $composableBuilder(
    column: $table.eventIdentity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startsAt => $composableBuilder(
    column: $table.startsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get allDayStartDate => $composableBuilder(
    column: $table.allDayStartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get allDayEndDateExclusive => $composableBuilder(
    column: $table.allDayEndDateExclusive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeZoneId => $composableBuilder(
    column: $table.timeZoneId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCalendarBlocksTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalCalendarBlocksTable> {
  $$LocalCalendarBlocksTableOrderingComposer({
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

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrenceId => $composableBuilder(
    column: $table.occurrenceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventIdentity => $composableBuilder(
    column: $table.eventIdentity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startsAt => $composableBuilder(
    column: $table.startsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get allDayStartDate => $composableBuilder(
    column: $table.allDayStartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get allDayEndDateExclusive => $composableBuilder(
    column: $table.allDayEndDateExclusive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeZoneId => $composableBuilder(
    column: $table.timeZoneId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCalendarBlocksTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalCalendarBlocksTable> {
  $$LocalCalendarBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurrenceId => $composableBuilder(
    column: $table.occurrenceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventIdentity => $composableBuilder(
    column: $table.eventIdentity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get startsAt =>
      $composableBuilder(column: $table.startsAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endsAt =>
      $composableBuilder(column: $table.endsAt, builder: (column) => column);

  GeneratedColumn<bool> get allDay =>
      $composableBuilder(column: $table.allDay, builder: (column) => column);

  GeneratedColumn<String> get allDayStartDate => $composableBuilder(
    column: $table.allDayStartDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get allDayEndDateExclusive => $composableBuilder(
    column: $table.allDayEndDateExclusive,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availability => $composableBuilder(
    column: $table.availability,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeZoneId => $composableBuilder(
    column: $table.timeZoneId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalCalendarBlocksTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalCalendarBlocksTable,
          LocalCalendarBlock,
          $$LocalCalendarBlocksTableFilterComposer,
          $$LocalCalendarBlocksTableOrderingComposer,
          $$LocalCalendarBlocksTableAnnotationComposer,
          $$LocalCalendarBlocksTableCreateCompanionBuilder,
          $$LocalCalendarBlocksTableUpdateCompanionBuilder,
          (
            LocalCalendarBlock,
            BaseReferences<
              _$PactaDatabase,
              $LocalCalendarBlocksTable,
              LocalCalendarBlock
            >,
          ),
          LocalCalendarBlock,
          PrefetchHooks Function()
        > {
  $$LocalCalendarBlocksTableTableManager(
    _$PactaDatabase db,
    $LocalCalendarBlocksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCalendarBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCalendarBlocksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalCalendarBlocksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceEventId = const Value.absent(),
                Value<String> occurrenceId = const Value.absent(),
                Value<String> eventIdentity = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime> startsAt = const Value.absent(),
                Value<DateTime> endsAt = const Value.absent(),
                Value<bool> allDay = const Value.absent(),
                Value<String?> allDayStartDate = const Value.absent(),
                Value<String?> allDayEndDateExclusive = const Value.absent(),
                Value<String> availability = const Value.absent(),
                Value<String> timeZoneId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCalendarBlocksCompanion(
                userId: userId,
                sourceId: sourceId,
                sourceEventId: sourceEventId,
                occurrenceId: occurrenceId,
                eventIdentity: eventIdentity,
                title: title,
                startsAt: startsAt,
                endsAt: endsAt,
                allDay: allDay,
                allDayStartDate: allDayStartDate,
                allDayEndDateExclusive: allDayEndDateExclusive,
                availability: availability,
                timeZoneId: timeZoneId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String sourceId,
                required String sourceEventId,
                required String occurrenceId,
                required String eventIdentity,
                required String title,
                required DateTime startsAt,
                required DateTime endsAt,
                Value<bool> allDay = const Value.absent(),
                Value<String?> allDayStartDate = const Value.absent(),
                Value<String?> allDayEndDateExclusive = const Value.absent(),
                required String availability,
                required String timeZoneId,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalCalendarBlocksCompanion.insert(
                userId: userId,
                sourceId: sourceId,
                sourceEventId: sourceEventId,
                occurrenceId: occurrenceId,
                eventIdentity: eventIdentity,
                title: title,
                startsAt: startsAt,
                endsAt: endsAt,
                allDay: allDay,
                allDayStartDate: allDayStartDate,
                allDayEndDateExclusive: allDayEndDateExclusive,
                availability: availability,
                timeZoneId: timeZoneId,
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

typedef $$LocalCalendarBlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalCalendarBlocksTable,
      LocalCalendarBlock,
      $$LocalCalendarBlocksTableFilterComposer,
      $$LocalCalendarBlocksTableOrderingComposer,
      $$LocalCalendarBlocksTableAnnotationComposer,
      $$LocalCalendarBlocksTableCreateCompanionBuilder,
      $$LocalCalendarBlocksTableUpdateCompanionBuilder,
      (
        LocalCalendarBlock,
        BaseReferences<
          _$PactaDatabase,
          $LocalCalendarBlocksTable,
          LocalCalendarBlock
        >,
      ),
      LocalCalendarBlock,
      PrefetchHooks Function()
    >;
typedef $$LocalUserLifecycleStatesTableCreateCompanionBuilder =
    LocalUserLifecycleStatesCompanion Function({
      required String userId,
      Value<bool> isSuspended,
      Value<DateTime?> suspendedAt,
      Value<DateTime?> purgeEligibleAt,
      Value<bool> isEligibleForPurge,
      required DateTime checkedAt,
      Value<int> rowid,
    });
typedef $$LocalUserLifecycleStatesTableUpdateCompanionBuilder =
    LocalUserLifecycleStatesCompanion Function({
      Value<String> userId,
      Value<bool> isSuspended,
      Value<DateTime?> suspendedAt,
      Value<DateTime?> purgeEligibleAt,
      Value<bool> isEligibleForPurge,
      Value<DateTime> checkedAt,
      Value<int> rowid,
    });

class $$LocalUserLifecycleStatesTableFilterComposer
    extends Composer<_$PactaDatabase, $LocalUserLifecycleStatesTable> {
  $$LocalUserLifecycleStatesTableFilterComposer({
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

  ColumnFilters<bool> get isSuspended => $composableBuilder(
    column: $table.isSuspended,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get suspendedAt => $composableBuilder(
    column: $table.suspendedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get purgeEligibleAt => $composableBuilder(
    column: $table.purgeEligibleAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEligibleForPurge => $composableBuilder(
    column: $table.isEligibleForPurge,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalUserLifecycleStatesTableOrderingComposer
    extends Composer<_$PactaDatabase, $LocalUserLifecycleStatesTable> {
  $$LocalUserLifecycleStatesTableOrderingComposer({
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

  ColumnOrderings<bool> get isSuspended => $composableBuilder(
    column: $table.isSuspended,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get suspendedAt => $composableBuilder(
    column: $table.suspendedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get purgeEligibleAt => $composableBuilder(
    column: $table.purgeEligibleAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEligibleForPurge => $composableBuilder(
    column: $table.isEligibleForPurge,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalUserLifecycleStatesTableAnnotationComposer
    extends Composer<_$PactaDatabase, $LocalUserLifecycleStatesTable> {
  $$LocalUserLifecycleStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<bool> get isSuspended => $composableBuilder(
    column: $table.isSuspended,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get suspendedAt => $composableBuilder(
    column: $table.suspendedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get purgeEligibleAt => $composableBuilder(
    column: $table.purgeEligibleAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isEligibleForPurge => $composableBuilder(
    column: $table.isEligibleForPurge,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);
}

class $$LocalUserLifecycleStatesTableTableManager
    extends
        RootTableManager<
          _$PactaDatabase,
          $LocalUserLifecycleStatesTable,
          LocalUserLifecycleState,
          $$LocalUserLifecycleStatesTableFilterComposer,
          $$LocalUserLifecycleStatesTableOrderingComposer,
          $$LocalUserLifecycleStatesTableAnnotationComposer,
          $$LocalUserLifecycleStatesTableCreateCompanionBuilder,
          $$LocalUserLifecycleStatesTableUpdateCompanionBuilder,
          (
            LocalUserLifecycleState,
            BaseReferences<
              _$PactaDatabase,
              $LocalUserLifecycleStatesTable,
              LocalUserLifecycleState
            >,
          ),
          LocalUserLifecycleState,
          PrefetchHooks Function()
        > {
  $$LocalUserLifecycleStatesTableTableManager(
    _$PactaDatabase db,
    $LocalUserLifecycleStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalUserLifecycleStatesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalUserLifecycleStatesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalUserLifecycleStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<bool> isSuspended = const Value.absent(),
                Value<DateTime?> suspendedAt = const Value.absent(),
                Value<DateTime?> purgeEligibleAt = const Value.absent(),
                Value<bool> isEligibleForPurge = const Value.absent(),
                Value<DateTime> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalUserLifecycleStatesCompanion(
                userId: userId,
                isSuspended: isSuspended,
                suspendedAt: suspendedAt,
                purgeEligibleAt: purgeEligibleAt,
                isEligibleForPurge: isEligibleForPurge,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                Value<bool> isSuspended = const Value.absent(),
                Value<DateTime?> suspendedAt = const Value.absent(),
                Value<DateTime?> purgeEligibleAt = const Value.absent(),
                Value<bool> isEligibleForPurge = const Value.absent(),
                required DateTime checkedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalUserLifecycleStatesCompanion.insert(
                userId: userId,
                isSuspended: isSuspended,
                suspendedAt: suspendedAt,
                purgeEligibleAt: purgeEligibleAt,
                isEligibleForPurge: isEligibleForPurge,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalUserLifecycleStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$PactaDatabase,
      $LocalUserLifecycleStatesTable,
      LocalUserLifecycleState,
      $$LocalUserLifecycleStatesTableFilterComposer,
      $$LocalUserLifecycleStatesTableOrderingComposer,
      $$LocalUserLifecycleStatesTableAnnotationComposer,
      $$LocalUserLifecycleStatesTableCreateCompanionBuilder,
      $$LocalUserLifecycleStatesTableUpdateCompanionBuilder,
      (
        LocalUserLifecycleState,
        BaseReferences<
          _$PactaDatabase,
          $LocalUserLifecycleStatesTable,
          LocalUserLifecycleState
        >,
      ),
      LocalUserLifecycleState,
      PrefetchHooks Function()
    >;

class $PactaDatabaseManager {
  final _$PactaDatabase _db;
  $PactaDatabaseManager(this._db);
  $$LocalGoalsTableTableManager get localGoals =>
      $$LocalGoalsTableTableManager(_db, _db.localGoals);
  $$LocalTasksTableTableManager get localTasks =>
      $$LocalTasksTableTableManager(_db, _db.localTasks);
  $$LocalNationalFocusCardsTableTableManager get localNationalFocusCards =>
      $$LocalNationalFocusCardsTableTableManager(
        _db,
        _db.localNationalFocusCards,
      );
  $$LocalNationalFocusStrengtheningLevelsTableTableManager
  get localNationalFocusStrengtheningLevels =>
      $$LocalNationalFocusStrengtheningLevelsTableTableManager(
        _db,
        _db.localNationalFocusStrengtheningLevels,
      );
  $$LocalNationalFocusRequirementVersionsTableTableManager
  get localNationalFocusRequirementVersions =>
      $$LocalNationalFocusRequirementVersionsTableTableManager(
        _db,
        _db.localNationalFocusRequirementVersions,
      );
  $$LocalNationalFocusMaintenanceTableTableManager
  get localNationalFocusMaintenance =>
      $$LocalNationalFocusMaintenanceTableTableManager(
        _db,
        _db.localNationalFocusMaintenance,
      );
  $$LocalNationalFocusFailuresTableTableManager
  get localNationalFocusFailures =>
      $$LocalNationalFocusFailuresTableTableManager(
        _db,
        _db.localNationalFocusFailures,
      );
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
  $$FocusSourceDevicesTableTableManager get focusSourceDevices =>
      $$FocusSourceDevicesTableTableManager(_db, _db.focusSourceDevices);
  $$FocusSyncSourcesTableTableManager get focusSyncSources =>
      $$FocusSyncSourcesTableTableManager(_db, _db.focusSyncSources);
  $$LocalCalendarSourcesTableTableManager get localCalendarSources =>
      $$LocalCalendarSourcesTableTableManager(_db, _db.localCalendarSources);
  $$LocalCalendarBlocksTableTableManager get localCalendarBlocks =>
      $$LocalCalendarBlocksTableTableManager(_db, _db.localCalendarBlocks);
  $$LocalUserLifecycleStatesTableTableManager get localUserLifecycleStates =>
      $$LocalUserLifecycleStatesTableTableManager(
        _db,
        _db.localUserLifecycleStates,
      );
}
