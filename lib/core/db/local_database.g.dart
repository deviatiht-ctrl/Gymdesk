// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class Records extends Table with TableInfo<Records, Record> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Records(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _gymIdMeta = const VerificationMeta('gymId');
  late final GeneratedColumn<String> gymId = GeneratedColumn<String>(
    'gym_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(payload))',
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  late final GeneratedColumn<String> serverVersion = GeneratedColumn<String>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    entity,
    id,
    gymId,
    payload,
    serverVersion,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'records';
  @override
  VerificationContext validateIntegrity(
    Insertable<Record> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('gym_id')) {
      context.handle(
        _gymIdMeta,
        gymId.isAcceptableOrUnknown(data['gym_id']!, _gymIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gymIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {entity, id};
  @override
  Record map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Record(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      gymId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gym_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_version'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  Records createAlias(String alias) {
    return Records(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(entity, id)'];
  @override
  bool get dontWriteConstraints => true;
}

class Record extends DataClass implements Insertable<Record> {
  final String entity;
  final String id;
  final String gymId;
  final String payload;
  final String? serverVersion;
  final String? deletedAt;
  const Record({
    required this.entity,
    required this.id,
    required this.gymId,
    required this.payload,
    this.serverVersion,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['id'] = Variable<String>(id);
    map['gym_id'] = Variable<String>(gymId);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<String>(serverVersion);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  RecordsCompanion toCompanion(bool nullToAbsent) {
    return RecordsCompanion(
      entity: Value(entity),
      id: Value(id),
      gymId: Value(gymId),
      payload: Value(payload),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Record.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Record(
      entity: serializer.fromJson<String>(json['entity']),
      id: serializer.fromJson<String>(json['id']),
      gymId: serializer.fromJson<String>(json['gym_id']),
      payload: serializer.fromJson<String>(json['payload']),
      serverVersion: serializer.fromJson<String?>(json['server_version']),
      deletedAt: serializer.fromJson<String?>(json['deleted_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'id': serializer.toJson<String>(id),
      'gym_id': serializer.toJson<String>(gymId),
      'payload': serializer.toJson<String>(payload),
      'server_version': serializer.toJson<String?>(serverVersion),
      'deleted_at': serializer.toJson<String?>(deletedAt),
    };
  }

  Record copyWith({
    String? entity,
    String? id,
    String? gymId,
    String? payload,
    Value<String?> serverVersion = const Value.absent(),
    Value<String?> deletedAt = const Value.absent(),
  }) => Record(
    entity: entity ?? this.entity,
    id: id ?? this.id,
    gymId: gymId ?? this.gymId,
    payload: payload ?? this.payload,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Record copyWithCompanion(RecordsCompanion data) {
    return Record(
      entity: data.entity.present ? data.entity.value : this.entity,
      id: data.id.present ? data.id.value : this.id,
      gymId: data.gymId.present ? data.gymId.value : this.gymId,
      payload: data.payload.present ? data.payload.value : this.payload,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Record(')
          ..write('entity: $entity, ')
          ..write('id: $id, ')
          ..write('gymId: $gymId, ')
          ..write('payload: $payload, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(entity, id, gymId, payload, serverVersion, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Record &&
          other.entity == this.entity &&
          other.id == this.id &&
          other.gymId == this.gymId &&
          other.payload == this.payload &&
          other.serverVersion == this.serverVersion &&
          other.deletedAt == this.deletedAt);
}

class RecordsCompanion extends UpdateCompanion<Record> {
  final Value<String> entity;
  final Value<String> id;
  final Value<String> gymId;
  final Value<String> payload;
  final Value<String?> serverVersion;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const RecordsCompanion({
    this.entity = const Value.absent(),
    this.id = const Value.absent(),
    this.gymId = const Value.absent(),
    this.payload = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordsCompanion.insert({
    required String entity,
    required String id,
    required String gymId,
    required String payload,
    this.serverVersion = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entity = Value(entity),
       id = Value(id),
       gymId = Value(gymId),
       payload = Value(payload);
  static Insertable<Record> custom({
    Expression<String>? entity,
    Expression<String>? id,
    Expression<String>? gymId,
    Expression<String>? payload,
    Expression<String>? serverVersion,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (id != null) 'id': id,
      if (gymId != null) 'gym_id': gymId,
      if (payload != null) 'payload': payload,
      if (serverVersion != null) 'server_version': serverVersion,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordsCompanion copyWith({
    Value<String>? entity,
    Value<String>? id,
    Value<String>? gymId,
    Value<String>? payload,
    Value<String?>? serverVersion,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return RecordsCompanion(
      entity: entity ?? this.entity,
      id: id ?? this.id,
      gymId: gymId ?? this.gymId,
      payload: payload ?? this.payload,
      serverVersion: serverVersion ?? this.serverVersion,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (gymId.present) {
      map['gym_id'] = Variable<String>(gymId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<String>(serverVersion.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordsCompanion(')
          ..write('entity: $entity, ')
          ..write('id: $id, ')
          ..write('gymId: $gymId, ')
          ..write('payload: $payload, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Outbox extends Table with TableInfo<Outbox, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Outbox(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (operation IN (\'insert\', \'update\', \'delete\'))',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(payload))',
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  late final GeneratedColumn<String> baseVersion = GeneratedColumn<String>(
    'base_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  late final GeneratedColumn<String> changedAt = GeneratedColumn<String>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  late final GeneratedColumn<String> nextAttemptAt = GeneratedColumn<String>(
    'next_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'pending\' CHECK (status IN (\'pending\', \'synced\', \'failed\'))',
    defaultValue: const CustomExpression('\'pending\''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sequence,
    id,
    entity,
    entityId,
    operation,
    payload,
    baseVersion,
    changedAt,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_changedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sequence};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_version'],
      ),
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}changed_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  Outbox createAlias(String alias) {
    return Outbox(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final int sequence;
  final String id;
  final String entity;
  final String entityId;
  final String operation;
  final String payload;
  final String? baseVersion;
  final String changedAt;
  final String createdAt;
  final int attempts;
  final String? nextAttemptAt;
  final String? lastError;
  final String status;
  const OutboxData({
    required this.sequence,
    required this.id,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.payload,
    this.baseVersion,
    required this.changedAt,
    required this.createdAt,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sequence'] = Variable<int>(sequence);
    map['id'] = Variable<String>(id);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || baseVersion != null) {
      map['base_version'] = Variable<String>(baseVersion);
    }
    map['changed_at'] = Variable<String>(changedAt);
    map['created_at'] = Variable<String>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<String>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      sequence: Value(sequence),
      id: Value(id),
      entity: Value(entity),
      entityId: Value(entityId),
      operation: Value(operation),
      payload: Value(payload),
      baseVersion: baseVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseVersion),
      changedAt: Value(changedAt),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      status: Value(status),
    );
  }

  factory OutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      sequence: serializer.fromJson<int>(json['sequence']),
      id: serializer.fromJson<String>(json['id']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      baseVersion: serializer.fromJson<String?>(json['base_version']),
      changedAt: serializer.fromJson<String>(json['changed_at']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<String?>(json['next_attempt_at']),
      lastError: serializer.fromJson<String?>(json['last_error']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sequence': serializer.toJson<int>(sequence),
      'id': serializer.toJson<String>(id),
      'entity': serializer.toJson<String>(entity),
      'entity_id': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'base_version': serializer.toJson<String?>(baseVersion),
      'changed_at': serializer.toJson<String>(changedAt),
      'created_at': serializer.toJson<String>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'next_attempt_at': serializer.toJson<String?>(nextAttemptAt),
      'last_error': serializer.toJson<String?>(lastError),
      'status': serializer.toJson<String>(status),
    };
  }

  OutboxData copyWith({
    int? sequence,
    String? id,
    String? entity,
    String? entityId,
    String? operation,
    String? payload,
    Value<String?> baseVersion = const Value.absent(),
    String? changedAt,
    String? createdAt,
    int? attempts,
    Value<String?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    String? status,
  }) => OutboxData(
    sequence: sequence ?? this.sequence,
    id: id ?? this.id,
    entity: entity ?? this.entity,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    baseVersion: baseVersion.present ? baseVersion.value : this.baseVersion,
    changedAt: changedAt ?? this.changedAt,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    status: status ?? this.status,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      id: data.id.present ? data.id.value : this.id,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('sequence: $sequence, ')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('changedAt: $changedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sequence,
    id,
    entity,
    entityId,
    operation,
    payload,
    baseVersion,
    changedAt,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.sequence == this.sequence &&
          other.id == this.id &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.baseVersion == this.baseVersion &&
          other.changedAt == this.changedAt &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError &&
          other.status == this.status);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<int> sequence;
  final Value<String> id;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<String?> baseVersion;
  final Value<String> changedAt;
  final Value<String> createdAt;
  final Value<int> attempts;
  final Value<String?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<String> status;
  const OutboxCompanion({
    this.sequence = const Value.absent(),
    this.id = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.status = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.sequence = const Value.absent(),
    required String id,
    required String entity,
    required String entityId,
    required String operation,
    required String payload,
    this.baseVersion = const Value.absent(),
    required String changedAt,
    required String createdAt,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.status = const Value.absent(),
  }) : id = Value(id),
       entity = Value(entity),
       entityId = Value(entityId),
       operation = Value(operation),
       payload = Value(payload),
       changedAt = Value(changedAt),
       createdAt = Value(createdAt);
  static Insertable<OutboxData> custom({
    Expression<int>? sequence,
    Expression<String>? id,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? baseVersion,
    Expression<String>? changedAt,
    Expression<String>? createdAt,
    Expression<int>? attempts,
    Expression<String>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (sequence != null) 'sequence': sequence,
      if (id != null) 'id': id,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (baseVersion != null) 'base_version': baseVersion,
      if (changedAt != null) 'changed_at': changedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (status != null) 'status': status,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? sequence,
    Value<String>? id,
    Value<String>? entity,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payload,
    Value<String?>? baseVersion,
    Value<String>? changedAt,
    Value<String>? createdAt,
    Value<int>? attempts,
    Value<String?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<String>? status,
  }) {
    return OutboxCompanion(
      sequence: sequence ?? this.sequence,
      id: id ?? this.id,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      baseVersion: baseVersion ?? this.baseVersion,
      changedAt: changedAt ?? this.changedAt,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<String>(baseVersion.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<String>(changedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<String>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('sequence: $sequence, ')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('changedAt: $changedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class SyncMetadata extends Table
    with TableInfo<SyncMetadata, SyncMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SyncMetadata(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetadataData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  SyncMetadata createAlias(String alias) {
    return SyncMetadata(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class SyncMetadataData extends DataClass
    implements Insertable<SyncMetadataData> {
  final String key;
  final String value;
  const SyncMetadataData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetadataCompanion toCompanion(bool nullToAbsent) {
    return SyncMetadataCompanion(key: Value(key), value: Value(value));
  }

  factory SyncMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetadataData copyWith({String? key, String? value}) =>
      SyncMetadataData(key: key ?? this.key, value: value ?? this.value);
  SyncMetadataData copyWithCompanion(SyncMetadataCompanion data) {
    return SyncMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetadataData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncMetadataCompanion extends UpdateCompanion<SyncMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetadataCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetadataCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class NumberBlocks extends Table with TableInfo<NumberBlocks, NumberBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NumberBlocks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _prefixMeta = const VerificationMeta('prefix');
  late final GeneratedColumn<String> prefix = GeneratedColumn<String>(
    'prefix',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nextValueMeta = const VerificationMeta(
    'nextValue',
  );
  late final GeneratedColumn<int> nextValue = GeneratedColumn<int>(
    'next_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lastValueMeta = const VerificationMeta(
    'lastValue',
  );
  late final GeneratedColumn<int> lastValue = GeneratedColumn<int>(
    'last_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [id, prefix, nextValue, lastValue];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'number_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<NumberBlock> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('prefix')) {
      context.handle(
        _prefixMeta,
        prefix.isAcceptableOrUnknown(data['prefix']!, _prefixMeta),
      );
    } else if (isInserting) {
      context.missing(_prefixMeta);
    }
    if (data.containsKey('next_value')) {
      context.handle(
        _nextValueMeta,
        nextValue.isAcceptableOrUnknown(data['next_value']!, _nextValueMeta),
      );
    } else if (isInserting) {
      context.missing(_nextValueMeta);
    }
    if (data.containsKey('last_value')) {
      context.handle(
        _lastValueMeta,
        lastValue.isAcceptableOrUnknown(data['last_value']!, _lastValueMeta),
      );
    } else if (isInserting) {
      context.missing(_lastValueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NumberBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NumberBlock(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      prefix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prefix'],
      )!,
      nextValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_value'],
      )!,
      lastValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_value'],
      )!,
    );
  }

  @override
  NumberBlocks createAlias(String alias) {
    return NumberBlocks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class NumberBlock extends DataClass implements Insertable<NumberBlock> {
  final String id;
  final String prefix;
  final int nextValue;
  final int lastValue;
  const NumberBlock({
    required this.id,
    required this.prefix,
    required this.nextValue,
    required this.lastValue,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['prefix'] = Variable<String>(prefix);
    map['next_value'] = Variable<int>(nextValue);
    map['last_value'] = Variable<int>(lastValue);
    return map;
  }

  NumberBlocksCompanion toCompanion(bool nullToAbsent) {
    return NumberBlocksCompanion(
      id: Value(id),
      prefix: Value(prefix),
      nextValue: Value(nextValue),
      lastValue: Value(lastValue),
    );
  }

  factory NumberBlock.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NumberBlock(
      id: serializer.fromJson<String>(json['id']),
      prefix: serializer.fromJson<String>(json['prefix']),
      nextValue: serializer.fromJson<int>(json['next_value']),
      lastValue: serializer.fromJson<int>(json['last_value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'prefix': serializer.toJson<String>(prefix),
      'next_value': serializer.toJson<int>(nextValue),
      'last_value': serializer.toJson<int>(lastValue),
    };
  }

  NumberBlock copyWith({
    String? id,
    String? prefix,
    int? nextValue,
    int? lastValue,
  }) => NumberBlock(
    id: id ?? this.id,
    prefix: prefix ?? this.prefix,
    nextValue: nextValue ?? this.nextValue,
    lastValue: lastValue ?? this.lastValue,
  );
  NumberBlock copyWithCompanion(NumberBlocksCompanion data) {
    return NumberBlock(
      id: data.id.present ? data.id.value : this.id,
      prefix: data.prefix.present ? data.prefix.value : this.prefix,
      nextValue: data.nextValue.present ? data.nextValue.value : this.nextValue,
      lastValue: data.lastValue.present ? data.lastValue.value : this.lastValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NumberBlock(')
          ..write('id: $id, ')
          ..write('prefix: $prefix, ')
          ..write('nextValue: $nextValue, ')
          ..write('lastValue: $lastValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, prefix, nextValue, lastValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NumberBlock &&
          other.id == this.id &&
          other.prefix == this.prefix &&
          other.nextValue == this.nextValue &&
          other.lastValue == this.lastValue);
}

class NumberBlocksCompanion extends UpdateCompanion<NumberBlock> {
  final Value<String> id;
  final Value<String> prefix;
  final Value<int> nextValue;
  final Value<int> lastValue;
  final Value<int> rowid;
  const NumberBlocksCompanion({
    this.id = const Value.absent(),
    this.prefix = const Value.absent(),
    this.nextValue = const Value.absent(),
    this.lastValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NumberBlocksCompanion.insert({
    required String id,
    required String prefix,
    required int nextValue,
    required int lastValue,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       prefix = Value(prefix),
       nextValue = Value(nextValue),
       lastValue = Value(lastValue);
  static Insertable<NumberBlock> custom({
    Expression<String>? id,
    Expression<String>? prefix,
    Expression<int>? nextValue,
    Expression<int>? lastValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (prefix != null) 'prefix': prefix,
      if (nextValue != null) 'next_value': nextValue,
      if (lastValue != null) 'last_value': lastValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NumberBlocksCompanion copyWith({
    Value<String>? id,
    Value<String>? prefix,
    Value<int>? nextValue,
    Value<int>? lastValue,
    Value<int>? rowid,
  }) {
    return NumberBlocksCompanion(
      id: id ?? this.id,
      prefix: prefix ?? this.prefix,
      nextValue: nextValue ?? this.nextValue,
      lastValue: lastValue ?? this.lastValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (prefix.present) {
      map['prefix'] = Variable<String>(prefix.value);
    }
    if (nextValue.present) {
      map['next_value'] = Variable<int>(nextValue.value);
    }
    if (lastValue.present) {
      map['last_value'] = Variable<int>(lastValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NumberBlocksCompanion(')
          ..write('id: $id, ')
          ..write('prefix: $prefix, ')
          ..write('nextValue: $nextValue, ')
          ..write('lastValue: $lastValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PhotoUploads extends Table with TableInfo<PhotoUploads, PhotoUpload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PhotoUploads(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  late final GeneratedColumn<String> memberId = GeneratedColumn<String>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _objectPathMeta = const VerificationMeta(
    'objectPath',
  );
  late final GeneratedColumn<String> objectPath = GeneratedColumn<String>(
    'object_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  late final GeneratedColumn<String> nextAttemptAt = GeneratedColumn<String>(
    'next_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    memberId,
    objectPath,
    bytes,
    attempts,
    nextAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photo_uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<PhotoUpload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('object_path')) {
      context.handle(
        _objectPathMeta,
        objectPath.isAcceptableOrUnknown(data['object_path']!, _objectPathMeta),
      );
    } else if (isInserting) {
      context.missing(_objectPathMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PhotoUpload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PhotoUpload(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_id'],
      )!,
      objectPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_path'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  PhotoUploads createAlias(String alias) {
    return PhotoUploads(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PhotoUpload extends DataClass implements Insertable<PhotoUpload> {
  final String id;
  final String memberId;
  final String objectPath;
  final Uint8List bytes;
  final int attempts;
  final String? nextAttemptAt;
  final String? lastError;
  const PhotoUpload({
    required this.id,
    required this.memberId,
    required this.objectPath,
    required this.bytes,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['member_id'] = Variable<String>(memberId);
    map['object_path'] = Variable<String>(objectPath);
    map['bytes'] = Variable<Uint8List>(bytes);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<String>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PhotoUploadsCompanion toCompanion(bool nullToAbsent) {
    return PhotoUploadsCompanion(
      id: Value(id),
      memberId: Value(memberId),
      objectPath: Value(objectPath),
      bytes: Value(bytes),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PhotoUpload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PhotoUpload(
      id: serializer.fromJson<String>(json['id']),
      memberId: serializer.fromJson<String>(json['member_id']),
      objectPath: serializer.fromJson<String>(json['object_path']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<String?>(json['next_attempt_at']),
      lastError: serializer.fromJson<String?>(json['last_error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'member_id': serializer.toJson<String>(memberId),
      'object_path': serializer.toJson<String>(objectPath),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'attempts': serializer.toJson<int>(attempts),
      'next_attempt_at': serializer.toJson<String?>(nextAttemptAt),
      'last_error': serializer.toJson<String?>(lastError),
    };
  }

  PhotoUpload copyWith({
    String? id,
    String? memberId,
    String? objectPath,
    Uint8List? bytes,
    int? attempts,
    Value<String?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => PhotoUpload(
    id: id ?? this.id,
    memberId: memberId ?? this.memberId,
    objectPath: objectPath ?? this.objectPath,
    bytes: bytes ?? this.bytes,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  PhotoUpload copyWithCompanion(PhotoUploadsCompanion data) {
    return PhotoUpload(
      id: data.id.present ? data.id.value : this.id,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      objectPath: data.objectPath.present
          ? data.objectPath.value
          : this.objectPath,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhotoUpload(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('objectPath: $objectPath, ')
          ..write('bytes: $bytes, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    memberId,
    objectPath,
    $driftBlobEquality.hash(bytes),
    attempts,
    nextAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhotoUpload &&
          other.id == this.id &&
          other.memberId == this.memberId &&
          other.objectPath == this.objectPath &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class PhotoUploadsCompanion extends UpdateCompanion<PhotoUpload> {
  final Value<String> id;
  final Value<String> memberId;
  final Value<String> objectPath;
  final Value<Uint8List> bytes;
  final Value<int> attempts;
  final Value<String?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const PhotoUploadsCompanion({
    this.id = const Value.absent(),
    this.memberId = const Value.absent(),
    this.objectPath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotoUploadsCompanion.insert({
    required String id,
    required String memberId,
    required String objectPath,
    required Uint8List bytes,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       memberId = Value(memberId),
       objectPath = Value(objectPath),
       bytes = Value(bytes);
  static Insertable<PhotoUpload> custom({
    Expression<String>? id,
    Expression<String>? memberId,
    Expression<String>? objectPath,
    Expression<Uint8List>? bytes,
    Expression<int>? attempts,
    Expression<String>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (memberId != null) 'member_id': memberId,
      if (objectPath != null) 'object_path': objectPath,
      if (bytes != null) 'bytes': bytes,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotoUploadsCompanion copyWith({
    Value<String>? id,
    Value<String>? memberId,
    Value<String>? objectPath,
    Value<Uint8List>? bytes,
    Value<int>? attempts,
    Value<String?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return PhotoUploadsCompanion(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      objectPath: objectPath ?? this.objectPath,
      bytes: bytes ?? this.bytes,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<String>(memberId.value);
    }
    if (objectPath.present) {
      map['object_path'] = Variable<String>(objectPath.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<String>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotoUploadsCompanion(')
          ..write('id: $id, ')
          ..write('memberId: $memberId, ')
          ..write('objectPath: $objectPath, ')
          ..write('bytes: $bytes, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class SyncConflicts extends Table with TableInfo<SyncConflicts, SyncConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SyncConflicts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _localPayloadMeta = const VerificationMeta(
    'localPayload',
  );
  late final GeneratedColumn<String> localPayload = GeneratedColumn<String>(
    'local_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _serverPayloadMeta = const VerificationMeta(
    'serverPayload',
  );
  late final GeneratedColumn<String> serverPayload = GeneratedColumn<String>(
    'server_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _reviewedMeta = const VerificationMeta(
    'reviewed',
  );
  late final GeneratedColumn<int> reviewed = GeneratedColumn<int>(
    'reviewed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entity,
    entityId,
    localPayload,
    serverPayload,
    createdAt,
    reviewed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('local_payload')) {
      context.handle(
        _localPayloadMeta,
        localPayload.isAcceptableOrUnknown(
          data['local_payload']!,
          _localPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localPayloadMeta);
    }
    if (data.containsKey('server_payload')) {
      context.handle(
        _serverPayloadMeta,
        serverPayload.isAcceptableOrUnknown(
          data['server_payload']!,
          _serverPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverPayloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('reviewed')) {
      context.handle(
        _reviewedMeta,
        reviewed.isAcceptableOrUnknown(data['reviewed']!, _reviewedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncConflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflict(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      localPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_payload'],
      )!,
      serverPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      reviewed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reviewed'],
      )!,
    );
  }

  @override
  SyncConflicts createAlias(String alias) {
    return SyncConflicts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class SyncConflict extends DataClass implements Insertable<SyncConflict> {
  final String id;
  final String entity;
  final String entityId;
  final String localPayload;
  final String serverPayload;
  final String createdAt;
  final int reviewed;
  const SyncConflict({
    required this.id,
    required this.entity,
    required this.entityId,
    required this.localPayload,
    required this.serverPayload,
    required this.createdAt,
    required this.reviewed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['local_payload'] = Variable<String>(localPayload);
    map['server_payload'] = Variable<String>(serverPayload);
    map['created_at'] = Variable<String>(createdAt);
    map['reviewed'] = Variable<int>(reviewed);
    return map;
  }

  SyncConflictsCompanion toCompanion(bool nullToAbsent) {
    return SyncConflictsCompanion(
      id: Value(id),
      entity: Value(entity),
      entityId: Value(entityId),
      localPayload: Value(localPayload),
      serverPayload: Value(serverPayload),
      createdAt: Value(createdAt),
      reviewed: Value(reviewed),
    );
  }

  factory SyncConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflict(
      id: serializer.fromJson<String>(json['id']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      localPayload: serializer.fromJson<String>(json['local_payload']),
      serverPayload: serializer.fromJson<String>(json['server_payload']),
      createdAt: serializer.fromJson<String>(json['created_at']),
      reviewed: serializer.fromJson<int>(json['reviewed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entity': serializer.toJson<String>(entity),
      'entity_id': serializer.toJson<String>(entityId),
      'local_payload': serializer.toJson<String>(localPayload),
      'server_payload': serializer.toJson<String>(serverPayload),
      'created_at': serializer.toJson<String>(createdAt),
      'reviewed': serializer.toJson<int>(reviewed),
    };
  }

  SyncConflict copyWith({
    String? id,
    String? entity,
    String? entityId,
    String? localPayload,
    String? serverPayload,
    String? createdAt,
    int? reviewed,
  }) => SyncConflict(
    id: id ?? this.id,
    entity: entity ?? this.entity,
    entityId: entityId ?? this.entityId,
    localPayload: localPayload ?? this.localPayload,
    serverPayload: serverPayload ?? this.serverPayload,
    createdAt: createdAt ?? this.createdAt,
    reviewed: reviewed ?? this.reviewed,
  );
  SyncConflict copyWithCompanion(SyncConflictsCompanion data) {
    return SyncConflict(
      id: data.id.present ? data.id.value : this.id,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      localPayload: data.localPayload.present
          ? data.localPayload.value
          : this.localPayload,
      serverPayload: data.serverPayload.present
          ? data.serverPayload.value
          : this.serverPayload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      reviewed: data.reviewed.present ? data.reviewed.value : this.reviewed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflict(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('localPayload: $localPayload, ')
          ..write('serverPayload: $serverPayload, ')
          ..write('createdAt: $createdAt, ')
          ..write('reviewed: $reviewed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entity,
    entityId,
    localPayload,
    serverPayload,
    createdAt,
    reviewed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflict &&
          other.id == this.id &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.localPayload == this.localPayload &&
          other.serverPayload == this.serverPayload &&
          other.createdAt == this.createdAt &&
          other.reviewed == this.reviewed);
}

class SyncConflictsCompanion extends UpdateCompanion<SyncConflict> {
  final Value<String> id;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> localPayload;
  final Value<String> serverPayload;
  final Value<String> createdAt;
  final Value<int> reviewed;
  final Value<int> rowid;
  const SyncConflictsCompanion({
    this.id = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.localPayload = const Value.absent(),
    this.serverPayload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.reviewed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictsCompanion.insert({
    required String id,
    required String entity,
    required String entityId,
    required String localPayload,
    required String serverPayload,
    required String createdAt,
    this.reviewed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entity = Value(entity),
       entityId = Value(entityId),
       localPayload = Value(localPayload),
       serverPayload = Value(serverPayload),
       createdAt = Value(createdAt);
  static Insertable<SyncConflict> custom({
    Expression<String>? id,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? localPayload,
    Expression<String>? serverPayload,
    Expression<String>? createdAt,
    Expression<int>? reviewed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (localPayload != null) 'local_payload': localPayload,
      if (serverPayload != null) 'server_payload': serverPayload,
      if (createdAt != null) 'created_at': createdAt,
      if (reviewed != null) 'reviewed': reviewed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictsCompanion copyWith({
    Value<String>? id,
    Value<String>? entity,
    Value<String>? entityId,
    Value<String>? localPayload,
    Value<String>? serverPayload,
    Value<String>? createdAt,
    Value<int>? reviewed,
    Value<int>? rowid,
  }) {
    return SyncConflictsCompanion(
      id: id ?? this.id,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      localPayload: localPayload ?? this.localPayload,
      serverPayload: serverPayload ?? this.serverPayload,
      createdAt: createdAt ?? this.createdAt,
      reviewed: reviewed ?? this.reviewed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (localPayload.present) {
      map['local_payload'] = Variable<String>(localPayload.value);
    }
    if (serverPayload.present) {
      map['server_payload'] = Variable<String>(serverPayload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (reviewed.present) {
      map['reviewed'] = Variable<int>(reviewed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsCompanion(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('localPayload: $localPayload, ')
          ..write('serverPayload: $serverPayload, ')
          ..write('createdAt: $createdAt, ')
          ..write('reviewed: $reviewed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final Records records = Records(this);
  late final Index recordsTenant = Index(
    'records_tenant',
    'CREATE INDEX records_tenant ON records (gym_id, entity, deleted_at)',
  );
  late final Index membersName = Index(
    'members_name',
    'CREATE INDEX members_name ON records (entity, gym_id, json_extract(payload, \'\$.last_name\'), id)',
  );
  late final Index membersToken = Index(
    'members_token',
    'CREATE INDEX members_token ON records (entity, gym_id, json_extract(payload, \'\$.qr_token\'))',
  );
  late final Index subscriptionsMember = Index(
    'subscriptions_member',
    'CREATE INDEX subscriptions_member ON records (entity, gym_id, json_extract(payload, \'\$.member_id\'), json_extract(payload, \'\$.end_date\'))',
  );
  late final Outbox outbox = Outbox(this);
  late final Index outboxPending = Index(
    'outbox_pending',
    'CREATE INDEX outbox_pending ON outbox (status, sequence)',
  );
  late final Index outboxEntity = Index(
    'outbox_entity',
    'CREATE INDEX outbox_entity ON outbox (entity, entity_id, status)',
  );
  late final SyncMetadata syncMetadata = SyncMetadata(this);
  late final NumberBlocks numberBlocks = NumberBlocks(this);
  late final PhotoUploads photoUploads = PhotoUploads(this);
  late final SyncConflicts syncConflicts = SyncConflicts(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    records,
    recordsTenant,
    membersName,
    membersToken,
    subscriptionsMember,
    outbox,
    outboxPending,
    outboxEntity,
    syncMetadata,
    numberBlocks,
    photoUploads,
    syncConflicts,
  ];
}

typedef $RecordsCreateCompanionBuilder =
    RecordsCompanion Function({
      required String entity,
      required String id,
      required String gymId,
      required String payload,
      Value<String?> serverVersion,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $RecordsUpdateCompanionBuilder =
    RecordsCompanion Function({
      Value<String> entity,
      Value<String> id,
      Value<String> gymId,
      Value<String> payload,
      Value<String?> serverVersion,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

class $RecordsFilterComposer extends Composer<_$LocalDatabase, Records> {
  $RecordsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $RecordsOrderingComposer extends Composer<_$LocalDatabase, Records> {
  $RecordsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $RecordsAnnotationComposer extends Composer<_$LocalDatabase, Records> {
  $RecordsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gymId =>
      $composableBuilder(column: $table.gymId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $RecordsTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          Records,
          Record,
          $RecordsFilterComposer,
          $RecordsOrderingComposer,
          $RecordsAnnotationComposer,
          $RecordsCreateCompanionBuilder,
          $RecordsUpdateCompanionBuilder,
          (Record, BaseReferences<_$LocalDatabase, Records, Record>),
          Record,
          PrefetchHooks Function()
        > {
  $RecordsTableManager(_$LocalDatabase db, Records table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $RecordsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $RecordsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $RecordsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> gymId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> serverVersion = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordsCompanion(
                entity: entity,
                id: id,
                gymId: gymId,
                payload: payload,
                serverVersion: serverVersion,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                required String id,
                required String gymId,
                required String payload,
                Value<String?> serverVersion = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordsCompanion.insert(
                entity: entity,
                id: id,
                gymId: gymId,
                payload: payload,
                serverVersion: serverVersion,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Records, Record>(table),
                  BaseReferences<_$LocalDatabase, Records, Record>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $RecordsProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      Records,
      Record,
      $RecordsFilterComposer,
      $RecordsOrderingComposer,
      $RecordsAnnotationComposer,
      $RecordsCreateCompanionBuilder,
      $RecordsUpdateCompanionBuilder,
      (Record, BaseReferences<_$LocalDatabase, Records, Record>),
      Record,
      PrefetchHooks Function()
    >;
typedef $OutboxCreateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> sequence,
      required String id,
      required String entity,
      required String entityId,
      required String operation,
      required String payload,
      Value<String?> baseVersion,
      required String changedAt,
      required String createdAt,
      Value<int> attempts,
      Value<String?> nextAttemptAt,
      Value<String?> lastError,
      Value<String> status,
    });
typedef $OutboxUpdateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> sequence,
      Value<String> id,
      Value<String> entity,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payload,
      Value<String?> baseVersion,
      Value<String> changedAt,
      Value<String> createdAt,
      Value<int> attempts,
      Value<String?> nextAttemptAt,
      Value<String?> lastError,
      Value<String> status,
    });

class $OutboxFilterComposer extends Composer<_$LocalDatabase, Outbox> {
  $OutboxFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $OutboxOrderingComposer extends Composer<_$LocalDatabase, Outbox> {
  $OutboxOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $OutboxAnnotationComposer extends Composer<_$LocalDatabase, Outbox> {
  $OutboxAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $OutboxTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          Outbox,
          OutboxData,
          $OutboxFilterComposer,
          $OutboxOrderingComposer,
          $OutboxAnnotationComposer,
          $OutboxCreateCompanionBuilder,
          $OutboxUpdateCompanionBuilder,
          (OutboxData, BaseReferences<_$LocalDatabase, Outbox, OutboxData>),
          OutboxData,
          PrefetchHooks Function()
        > {
  $OutboxTableManager(_$LocalDatabase db, Outbox table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $OutboxFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $OutboxOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $OutboxAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> baseVersion = const Value.absent(),
                Value<String> changedAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String> status = const Value.absent(),
              }) => OutboxCompanion(
                sequence: sequence,
                id: id,
                entity: entity,
                entityId: entityId,
                operation: operation,
                payload: payload,
                baseVersion: baseVersion,
                changedAt: changedAt,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                required String id,
                required String entity,
                required String entityId,
                required String operation,
                required String payload,
                Value<String?> baseVersion = const Value.absent(),
                required String changedAt,
                required String createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String> status = const Value.absent(),
              }) => OutboxCompanion.insert(
                sequence: sequence,
                id: id,
                entity: entity,
                entityId: entityId,
                operation: operation,
                payload: payload,
                baseVersion: baseVersion,
                changedAt: changedAt,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Outbox, OutboxData>(table),
                  BaseReferences<_$LocalDatabase, Outbox, OutboxData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $OutboxProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      Outbox,
      OutboxData,
      $OutboxFilterComposer,
      $OutboxOrderingComposer,
      $OutboxAnnotationComposer,
      $OutboxCreateCompanionBuilder,
      $OutboxUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$LocalDatabase, Outbox, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;
typedef $SyncMetadataCreateCompanionBuilder =
    SyncMetadataCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $SyncMetadataUpdateCompanionBuilder =
    SyncMetadataCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $SyncMetadataFilterComposer
    extends Composer<_$LocalDatabase, SyncMetadata> {
  $SyncMetadataFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $SyncMetadataOrderingComposer
    extends Composer<_$LocalDatabase, SyncMetadata> {
  $SyncMetadataOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $SyncMetadataAnnotationComposer
    extends Composer<_$LocalDatabase, SyncMetadata> {
  $SyncMetadataAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $SyncMetadataTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          SyncMetadata,
          SyncMetadataData,
          $SyncMetadataFilterComposer,
          $SyncMetadataOrderingComposer,
          $SyncMetadataAnnotationComposer,
          $SyncMetadataCreateCompanionBuilder,
          $SyncMetadataUpdateCompanionBuilder,
          (
            SyncMetadataData,
            BaseReferences<_$LocalDatabase, SyncMetadata, SyncMetadataData>,
          ),
          SyncMetadataData,
          PrefetchHooks Function()
        > {
  $SyncMetadataTableManager(_$LocalDatabase db, SyncMetadata table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SyncMetadataFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SyncMetadataOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SyncMetadataAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetadataCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetadataCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SyncMetadata, SyncMetadataData>(table),
                  BaseReferences<
                    _$LocalDatabase,
                    SyncMetadata,
                    SyncMetadataData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $SyncMetadataProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      SyncMetadata,
      SyncMetadataData,
      $SyncMetadataFilterComposer,
      $SyncMetadataOrderingComposer,
      $SyncMetadataAnnotationComposer,
      $SyncMetadataCreateCompanionBuilder,
      $SyncMetadataUpdateCompanionBuilder,
      (
        SyncMetadataData,
        BaseReferences<_$LocalDatabase, SyncMetadata, SyncMetadataData>,
      ),
      SyncMetadataData,
      PrefetchHooks Function()
    >;
typedef $NumberBlocksCreateCompanionBuilder =
    NumberBlocksCompanion Function({
      required String id,
      required String prefix,
      required int nextValue,
      required int lastValue,
      Value<int> rowid,
    });
typedef $NumberBlocksUpdateCompanionBuilder =
    NumberBlocksCompanion Function({
      Value<String> id,
      Value<String> prefix,
      Value<int> nextValue,
      Value<int> lastValue,
      Value<int> rowid,
    });

class $NumberBlocksFilterComposer
    extends Composer<_$LocalDatabase, NumberBlocks> {
  $NumberBlocksFilterComposer({
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

  ColumnFilters<String> get prefix => $composableBuilder(
    column: $table.prefix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextValue => $composableBuilder(
    column: $table.nextValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastValue => $composableBuilder(
    column: $table.lastValue,
    builder: (column) => ColumnFilters(column),
  );
}

class $NumberBlocksOrderingComposer
    extends Composer<_$LocalDatabase, NumberBlocks> {
  $NumberBlocksOrderingComposer({
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

  ColumnOrderings<String> get prefix => $composableBuilder(
    column: $table.prefix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextValue => $composableBuilder(
    column: $table.nextValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastValue => $composableBuilder(
    column: $table.lastValue,
    builder: (column) => ColumnOrderings(column),
  );
}

class $NumberBlocksAnnotationComposer
    extends Composer<_$LocalDatabase, NumberBlocks> {
  $NumberBlocksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get prefix =>
      $composableBuilder(column: $table.prefix, builder: (column) => column);

  GeneratedColumn<int> get nextValue =>
      $composableBuilder(column: $table.nextValue, builder: (column) => column);

  GeneratedColumn<int> get lastValue =>
      $composableBuilder(column: $table.lastValue, builder: (column) => column);
}

class $NumberBlocksTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          NumberBlocks,
          NumberBlock,
          $NumberBlocksFilterComposer,
          $NumberBlocksOrderingComposer,
          $NumberBlocksAnnotationComposer,
          $NumberBlocksCreateCompanionBuilder,
          $NumberBlocksUpdateCompanionBuilder,
          (
            NumberBlock,
            BaseReferences<_$LocalDatabase, NumberBlocks, NumberBlock>,
          ),
          NumberBlock,
          PrefetchHooks Function()
        > {
  $NumberBlocksTableManager(_$LocalDatabase db, NumberBlocks table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $NumberBlocksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $NumberBlocksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $NumberBlocksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> prefix = const Value.absent(),
                Value<int> nextValue = const Value.absent(),
                Value<int> lastValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NumberBlocksCompanion(
                id: id,
                prefix: prefix,
                nextValue: nextValue,
                lastValue: lastValue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String prefix,
                required int nextValue,
                required int lastValue,
                Value<int> rowid = const Value.absent(),
              }) => NumberBlocksCompanion.insert(
                id: id,
                prefix: prefix,
                nextValue: nextValue,
                lastValue: lastValue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<NumberBlocks, NumberBlock>(table),
                  BaseReferences<_$LocalDatabase, NumberBlocks, NumberBlock>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $NumberBlocksProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      NumberBlocks,
      NumberBlock,
      $NumberBlocksFilterComposer,
      $NumberBlocksOrderingComposer,
      $NumberBlocksAnnotationComposer,
      $NumberBlocksCreateCompanionBuilder,
      $NumberBlocksUpdateCompanionBuilder,
      (NumberBlock, BaseReferences<_$LocalDatabase, NumberBlocks, NumberBlock>),
      NumberBlock,
      PrefetchHooks Function()
    >;
typedef $PhotoUploadsCreateCompanionBuilder =
    PhotoUploadsCompanion Function({
      required String id,
      required String memberId,
      required String objectPath,
      required Uint8List bytes,
      Value<int> attempts,
      Value<String?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $PhotoUploadsUpdateCompanionBuilder =
    PhotoUploadsCompanion Function({
      Value<String> id,
      Value<String> memberId,
      Value<String> objectPath,
      Value<Uint8List> bytes,
      Value<int> attempts,
      Value<String?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $PhotoUploadsFilterComposer
    extends Composer<_$LocalDatabase, PhotoUploads> {
  $PhotoUploadsFilterComposer({
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

  ColumnFilters<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectPath => $composableBuilder(
    column: $table.objectPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $PhotoUploadsOrderingComposer
    extends Composer<_$LocalDatabase, PhotoUploads> {
  $PhotoUploadsOrderingComposer({
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

  ColumnOrderings<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectPath => $composableBuilder(
    column: $table.objectPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $PhotoUploadsAnnotationComposer
    extends Composer<_$LocalDatabase, PhotoUploads> {
  $PhotoUploadsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get memberId =>
      $composableBuilder(column: $table.memberId, builder: (column) => column);

  GeneratedColumn<String> get objectPath => $composableBuilder(
    column: $table.objectPath,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $PhotoUploadsTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          PhotoUploads,
          PhotoUpload,
          $PhotoUploadsFilterComposer,
          $PhotoUploadsOrderingComposer,
          $PhotoUploadsAnnotationComposer,
          $PhotoUploadsCreateCompanionBuilder,
          $PhotoUploadsUpdateCompanionBuilder,
          (
            PhotoUpload,
            BaseReferences<_$LocalDatabase, PhotoUploads, PhotoUpload>,
          ),
          PhotoUpload,
          PrefetchHooks Function()
        > {
  $PhotoUploadsTableManager(_$LocalDatabase db, PhotoUploads table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PhotoUploadsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PhotoUploadsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PhotoUploadsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> memberId = const Value.absent(),
                Value<String> objectPath = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotoUploadsCompanion(
                id: id,
                memberId: memberId,
                objectPath: objectPath,
                bytes: bytes,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String memberId,
                required String objectPath,
                required Uint8List bytes,
                Value<int> attempts = const Value.absent(),
                Value<String?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhotoUploadsCompanion.insert(
                id: id,
                memberId: memberId,
                objectPath: objectPath,
                bytes: bytes,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<PhotoUploads, PhotoUpload>(table),
                  BaseReferences<_$LocalDatabase, PhotoUploads, PhotoUpload>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $PhotoUploadsProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      PhotoUploads,
      PhotoUpload,
      $PhotoUploadsFilterComposer,
      $PhotoUploadsOrderingComposer,
      $PhotoUploadsAnnotationComposer,
      $PhotoUploadsCreateCompanionBuilder,
      $PhotoUploadsUpdateCompanionBuilder,
      (PhotoUpload, BaseReferences<_$LocalDatabase, PhotoUploads, PhotoUpload>),
      PhotoUpload,
      PrefetchHooks Function()
    >;
typedef $SyncConflictsCreateCompanionBuilder =
    SyncConflictsCompanion Function({
      required String id,
      required String entity,
      required String entityId,
      required String localPayload,
      required String serverPayload,
      required String createdAt,
      Value<int> reviewed,
      Value<int> rowid,
    });
typedef $SyncConflictsUpdateCompanionBuilder =
    SyncConflictsCompanion Function({
      Value<String> id,
      Value<String> entity,
      Value<String> entityId,
      Value<String> localPayload,
      Value<String> serverPayload,
      Value<String> createdAt,
      Value<int> reviewed,
      Value<int> rowid,
    });

class $SyncConflictsFilterComposer
    extends Composer<_$LocalDatabase, SyncConflicts> {
  $SyncConflictsFilterComposer({
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

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverPayload => $composableBuilder(
    column: $table.serverPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewed => $composableBuilder(
    column: $table.reviewed,
    builder: (column) => ColumnFilters(column),
  );
}

class $SyncConflictsOrderingComposer
    extends Composer<_$LocalDatabase, SyncConflicts> {
  $SyncConflictsOrderingComposer({
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

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverPayload => $composableBuilder(
    column: $table.serverPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewed => $composableBuilder(
    column: $table.reviewed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $SyncConflictsAnnotationComposer
    extends Composer<_$LocalDatabase, SyncConflicts> {
  $SyncConflictsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverPayload => $composableBuilder(
    column: $table.serverPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get reviewed =>
      $composableBuilder(column: $table.reviewed, builder: (column) => column);
}

class $SyncConflictsTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          SyncConflicts,
          SyncConflict,
          $SyncConflictsFilterComposer,
          $SyncConflictsOrderingComposer,
          $SyncConflictsAnnotationComposer,
          $SyncConflictsCreateCompanionBuilder,
          $SyncConflictsUpdateCompanionBuilder,
          (
            SyncConflict,
            BaseReferences<_$LocalDatabase, SyncConflicts, SyncConflict>,
          ),
          SyncConflict,
          PrefetchHooks Function()
        > {
  $SyncConflictsTableManager(_$LocalDatabase db, SyncConflicts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SyncConflictsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SyncConflictsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SyncConflictsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> localPayload = const Value.absent(),
                Value<String> serverPayload = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> reviewed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion(
                id: id,
                entity: entity,
                entityId: entityId,
                localPayload: localPayload,
                serverPayload: serverPayload,
                createdAt: createdAt,
                reviewed: reviewed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entity,
                required String entityId,
                required String localPayload,
                required String serverPayload,
                required String createdAt,
                Value<int> reviewed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion.insert(
                id: id,
                entity: entity,
                entityId: entityId,
                localPayload: localPayload,
                serverPayload: serverPayload,
                createdAt: createdAt,
                reviewed: reviewed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SyncConflicts, SyncConflict>(table),
                  BaseReferences<_$LocalDatabase, SyncConflicts, SyncConflict>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $SyncConflictsProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      SyncConflicts,
      SyncConflict,
      $SyncConflictsFilterComposer,
      $SyncConflictsOrderingComposer,
      $SyncConflictsAnnotationComposer,
      $SyncConflictsCreateCompanionBuilder,
      $SyncConflictsUpdateCompanionBuilder,
      (
        SyncConflict,
        BaseReferences<_$LocalDatabase, SyncConflicts, SyncConflict>,
      ),
      SyncConflict,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $RecordsTableManager get records => $RecordsTableManager(_db, _db.records);
  $OutboxTableManager get outbox => $OutboxTableManager(_db, _db.outbox);
  $SyncMetadataTableManager get syncMetadata =>
      $SyncMetadataTableManager(_db, _db.syncMetadata);
  $NumberBlocksTableManager get numberBlocks =>
      $NumberBlocksTableManager(_db, _db.numberBlocks);
  $PhotoUploadsTableManager get photoUploads =>
      $PhotoUploadsTableManager(_db, _db.photoUploads);
  $SyncConflictsTableManager get syncConflicts =>
      $SyncConflictsTableManager(_db, _db.syncConflicts);
}
