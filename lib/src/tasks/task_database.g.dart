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
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    id,
    title,
    classification,
    createdAt,
    updatedAt,
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
  const LocalGoal({
    required this.userId,
    required this.id,
    required this.title,
    required this.classification,
    required this.createdAt,
    required this.updatedAt,
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
    };
  }

  LocalGoal copyWith({
    String? userId,
    String? id,
    String? title,
    String? classification,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalGoal(
    userId: userId ?? this.userId,
    id: id ?? this.id,
    title: title ?? this.title,
    classification: classification ?? this.classification,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
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
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, id, title, classification, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalGoal &&
          other.userId == this.userId &&
          other.id == this.id &&
          other.title == this.title &&
          other.classification == this.classification &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalGoalsCompanion extends UpdateCompanion<LocalGoal> {
  final Value<String> userId;
  final Value<String> id;
  final Value<String> title;
  final Value<String> classification;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalGoalsCompanion({
    this.userId = const Value.absent(),
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.classification = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalGoalsCompanion.insert({
    required String userId,
    required String id,
    required String title,
    required String classification,
    required DateTime createdAt,
    required DateTime updatedAt,
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
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (classification != null) 'classification': classification,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
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
    Value<int>? rowid,
  }) {
    return LocalGoalsCompanion(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      title: title ?? this.title,
      classification: classification ?? this.classification,
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
    id,
    goalId,
    title,
    classification,
    estimatedMinutes,
    deadline,
    isComplete,
    createdAt,
    updatedAt,
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
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalTask({
    required this.userId,
    required this.id,
    required this.goalId,
    required this.title,
    required this.classification,
    this.estimatedMinutes,
    this.deadline,
    required this.isComplete,
    required this.createdAt,
    required this.updatedAt,
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
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
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
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
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
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
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
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
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
    DateTime? createdAt,
    DateTime? updatedAt,
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
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
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
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
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
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
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
    createdAt,
    updatedAt,
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
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
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
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
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
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
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
    required DateTime createdAt,
    required DateTime updatedAt,
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
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
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
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
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
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
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
    return (StringBuffer('LocalTasksCompanion(')
          ..write('userId: $userId, ')
          ..write('id: $id, ')
          ..write('goalId: $goalId, ')
          ..write('title: $title, ')
          ..write('classification: $classification, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('deadline: $deadline, ')
          ..write('isComplete: $isComplete, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
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

abstract class _$PactaDatabase extends GeneratedDatabase {
  _$PactaDatabase(QueryExecutor e) : super(e);
  $PactaDatabaseManager get managers => $PactaDatabaseManager(this);
  late final $LocalGoalsTable localGoals = $LocalGoalsTable(this);
  late final $LocalTasksTable localTasks = $LocalTasksTable(this);
  late final $TaskSyncEntriesTable taskSyncEntries = $TaskSyncEntriesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localGoals,
    localTasks,
    taskSyncEntries,
  ];
}

typedef $$LocalGoalsTableCreateCompanionBuilder = LocalGoalsCompanion Function({
  required String userId,
  required String id,
  required String title,
  required String classification,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LocalGoalsTableUpdateCompanionBuilder = LocalGoalsCompanion Function({
  Value<String> userId,
  Value<String> id,
  Value<String> title,
  Value<String> classification,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
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
                Value<int> rowid = const Value.absent(),
              }) => LocalGoalsCompanion(
                userId: userId,
                id: id,
                title: title,
                classification: classification,
                createdAt: createdAt,
                updatedAt: updatedAt,
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
                Value<int> rowid = const Value.absent(),
              }) => LocalGoalsCompanion.insert(
                userId: userId,
                id: id,
                title: title,
                classification: classification,
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
typedef $$LocalTasksTableCreateCompanionBuilder = LocalTasksCompanion Function({
  required String userId,
  required String id,
  required String goalId,
  required String title,
  required String classification,
  Value<int?> estimatedMinutes,
  Value<DateTime?> deadline,
  Value<bool> isComplete,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LocalTasksTableUpdateCompanionBuilder = LocalTasksCompanion Function({
  Value<String> userId,
  Value<String> id,
  Value<String> goalId,
  Value<String> title,
  Value<String> classification,
  Value<int?> estimatedMinutes,
  Value<DateTime?> deadline,
  Value<bool> isComplete,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
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

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
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
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
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
                createdAt: createdAt,
                updatedAt: updatedAt,
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
                required DateTime createdAt,
                required DateTime updatedAt,
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

class $PactaDatabaseManager {
  final _$PactaDatabase _db;
  $PactaDatabaseManager(this._db);
  $$LocalGoalsTableTableManager get localGoals =>
      $$LocalGoalsTableTableManager(_db, _db.localGoals);
  $$LocalTasksTableTableManager get localTasks =>
      $$LocalTasksTableTableManager(_db, _db.localTasks);
  $$TaskSyncEntriesTableTableManager get taskSyncEntries =>
      $$TaskSyncEntriesTableTableManager(_db, _db.taskSyncEntries);
}
