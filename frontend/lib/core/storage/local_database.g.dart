// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $CachedFilesTable extends CachedFiles
    with TableInfo<$CachedFilesTable, CachedFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAccessedAtMeta = const VerificationMeta(
    'lastAccessedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAccessedAt =
      GeneratedColumn<DateTime>(
        'last_accessed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fileName,
    sizeBytes,
    mimeType,
    localPath,
    cachedAt,
    lastAccessedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    if (data.containsKey('last_accessed_at')) {
      context.handle(
        _lastAccessedAtMeta,
        lastAccessedAt.isAcceptableOrUnknown(
          data['last_accessed_at']!,
          _lastAccessedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFile(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      fileName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}file_name'],
          )!,
      sizeBytes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}size_bytes'],
          )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      cachedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}cached_at'],
          )!,
      lastAccessedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_accessed_at'],
      ),
    );
  }

  @override
  $CachedFilesTable createAlias(String alias) {
    return $CachedFilesTable(attachedDatabase, alias);
  }
}

class CachedFile extends DataClass implements Insertable<CachedFile> {
  final String id;
  final String fileName;
  final int sizeBytes;
  final String? mimeType;
  final String? localPath;
  final DateTime cachedAt;
  final DateTime? lastAccessedAt;
  const CachedFile({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    this.mimeType,
    this.localPath,
    required this.cachedAt,
    this.lastAccessedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['file_name'] = Variable<String>(fileName);
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    if (!nullToAbsent || lastAccessedAt != null) {
      map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt);
    }
    return map;
  }

  CachedFilesCompanion toCompanion(bool nullToAbsent) {
    return CachedFilesCompanion(
      id: Value(id),
      fileName: Value(fileName),
      sizeBytes: Value(sizeBytes),
      mimeType:
          mimeType == null && nullToAbsent
              ? const Value.absent()
              : Value(mimeType),
      localPath:
          localPath == null && nullToAbsent
              ? const Value.absent()
              : Value(localPath),
      cachedAt: Value(cachedAt),
      lastAccessedAt:
          lastAccessedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(lastAccessedAt),
    );
  }

  factory CachedFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFile(
      id: serializer.fromJson<String>(json['id']),
      fileName: serializer.fromJson<String>(json['fileName']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
      lastAccessedAt: serializer.fromJson<DateTime?>(json['lastAccessedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fileName': serializer.toJson<String>(fileName),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'mimeType': serializer.toJson<String?>(mimeType),
      'localPath': serializer.toJson<String?>(localPath),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
      'lastAccessedAt': serializer.toJson<DateTime?>(lastAccessedAt),
    };
  }

  CachedFile copyWith({
    String? id,
    String? fileName,
    int? sizeBytes,
    Value<String?> mimeType = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    DateTime? cachedAt,
    Value<DateTime?> lastAccessedAt = const Value.absent(),
  }) => CachedFile(
    id: id ?? this.id,
    fileName: fileName ?? this.fileName,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    localPath: localPath.present ? localPath.value : this.localPath,
    cachedAt: cachedAt ?? this.cachedAt,
    lastAccessedAt:
        lastAccessedAt.present ? lastAccessedAt.value : this.lastAccessedAt,
  );
  CachedFile copyWithCompanion(CachedFilesCompanion data) {
    return CachedFile(
      id: data.id.present ? data.id.value : this.id,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
      lastAccessedAt:
          data.lastAccessedAt.present
              ? data.lastAccessedAt.value
              : this.lastAccessedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFile(')
          ..write('id: $id, ')
          ..write('fileName: $fileName, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('localPath: $localPath, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fileName,
    sizeBytes,
    mimeType,
    localPath,
    cachedAt,
    lastAccessedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFile &&
          other.id == this.id &&
          other.fileName == this.fileName &&
          other.sizeBytes == this.sizeBytes &&
          other.mimeType == this.mimeType &&
          other.localPath == this.localPath &&
          other.cachedAt == this.cachedAt &&
          other.lastAccessedAt == this.lastAccessedAt);
}

class CachedFilesCompanion extends UpdateCompanion<CachedFile> {
  final Value<String> id;
  final Value<String> fileName;
  final Value<int> sizeBytes;
  final Value<String?> mimeType;
  final Value<String?> localPath;
  final Value<DateTime> cachedAt;
  final Value<DateTime?> lastAccessedAt;
  final Value<int> rowid;
  const CachedFilesCompanion({
    this.id = const Value.absent(),
    this.fileName = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.localPath = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFilesCompanion.insert({
    required String id,
    required String fileName,
    required int sizeBytes,
    this.mimeType = const Value.absent(),
    this.localPath = const Value.absent(),
    required DateTime cachedAt,
    this.lastAccessedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fileName = Value(fileName),
       sizeBytes = Value(sizeBytes),
       cachedAt = Value(cachedAt);
  static Insertable<CachedFile> custom({
    Expression<String>? id,
    Expression<String>? fileName,
    Expression<int>? sizeBytes,
    Expression<String>? mimeType,
    Expression<String>? localPath,
    Expression<DateTime>? cachedAt,
    Expression<DateTime>? lastAccessedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fileName != null) 'file_name': fileName,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (mimeType != null) 'mime_type': mimeType,
      if (localPath != null) 'local_path': localPath,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (lastAccessedAt != null) 'last_accessed_at': lastAccessedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFilesCompanion copyWith({
    Value<String>? id,
    Value<String>? fileName,
    Value<int>? sizeBytes,
    Value<String?>? mimeType,
    Value<String?>? localPath,
    Value<DateTime>? cachedAt,
    Value<DateTime?>? lastAccessedAt,
    Value<int>? rowid,
  }) {
    return CachedFilesCompanion(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      localPath: localPath ?? this.localPath,
      cachedAt: cachedAt ?? this.cachedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (lastAccessedAt.present) {
      map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedFilesCompanion(')
          ..write('id: $id, ')
          ..write('fileName: $fileName, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('localPath: $localPath, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOperationsTable extends SyncOperations
    with TableInfo<$SyncOperationsTable, SyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
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
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    payload,
    status,
    retryCount,
    createdAt,
    syncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
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
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOperation(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      payload:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}payload'],
          )!,
      status:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}status'],
          )!,
      retryCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}retry_count'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
    );
  }

  @override
  $SyncOperationsTable createAlias(String alias) {
    return $SyncOperationsTable(attachedDatabase, alias);
  }
}

class SyncOperation extends DataClass implements Insertable<SyncOperation> {
  final int id;
  final String type;
  final String payload;
  final String status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? syncedAt;
  const SyncOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  SyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return SyncOperationsCompanion(
      id: Value(id),
      type: Value(type),
      payload: Value(payload),
      status: Value(status),
      retryCount: Value(retryCount),
      createdAt: Value(createdAt),
      syncedAt:
          syncedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(syncedAt),
    );
  }

  factory SyncOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOperation(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  SyncOperation copyWith({
    int? id,
    String? type,
    String? payload,
    String? status,
    int? retryCount,
    DateTime? createdAt,
    Value<DateTime?> syncedAt = const Value.absent(),
  }) => SyncOperation(
    id: id ?? this.id,
    type: type ?? this.type,
    payload: payload ?? this.payload,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt ?? this.createdAt,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
  );
  SyncOperation copyWithCompanion(SyncOperationsCompanion data) {
    return SyncOperation(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      status: data.status.present ? data.status.value : this.status,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperation(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, type, payload, status, retryCount, createdAt, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOperation &&
          other.id == this.id &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt);
}

class SyncOperationsCompanion extends UpdateCompanion<SyncOperation> {
  final Value<int> id;
  final Value<String> type;
  final Value<String> payload;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  const SyncOperationsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
  });
  SyncOperationsCompanion.insert({
    this.id = const Value.absent(),
    required String type,
    required String payload,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    required DateTime createdAt,
    this.syncedAt = const Value.absent(),
  }) : type = Value(type),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<SyncOperation> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
    });
  }

  SyncOperationsCompanion copyWith({
    Value<int>? id,
    Value<String>? type,
    Value<String>? payload,
    Value<String>? status,
    Value<int>? retryCount,
    Value<DateTime>? createdAt,
    Value<DateTime?>? syncedAt,
  }) {
    return SyncOperationsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }
}

class $CachedMediaProgressTable extends CachedMediaProgress
    with TableInfo<$CachedMediaProgressTable, CachedMediaProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMediaProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressPercentMeta = const VerificationMeta(
    'progressPercent',
  );
  @override
  late final GeneratedColumn<double> progressPercent = GeneratedColumn<double>(
    'progress_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionSecondsMeta = const VerificationMeta(
    'positionSeconds',
  );
  @override
  late final GeneratedColumn<int> positionSeconds = GeneratedColumn<int>(
    'position_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
    mediaId,
    mediaType,
    progressPercent,
    positionSeconds,
    durationSeconds,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_media_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMediaProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('progress_percent')) {
      context.handle(
        _progressPercentMeta,
        progressPercent.isAcceptableOrUnknown(
          data['progress_percent']!,
          _progressPercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_progressPercentMeta);
    }
    if (data.containsKey('position_seconds')) {
      context.handle(
        _positionSecondsMeta,
        positionSeconds.isAcceptableOrUnknown(
          data['position_seconds']!,
          _positionSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_positionSecondsMeta);
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
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  CachedMediaProgressData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMediaProgressData(
      mediaId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}media_id'],
          )!,
      mediaType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}media_type'],
          )!,
      progressPercent:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}progress_percent'],
          )!,
      positionSeconds:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}position_seconds'],
          )!,
      durationSeconds:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}duration_seconds'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $CachedMediaProgressTable createAlias(String alias) {
    return $CachedMediaProgressTable(attachedDatabase, alias);
  }
}

class CachedMediaProgressData extends DataClass
    implements Insertable<CachedMediaProgressData> {
  final String mediaId;
  final String mediaType;
  final double progressPercent;
  final int positionSeconds;
  final int durationSeconds;
  final DateTime updatedAt;
  const CachedMediaProgressData({
    required this.mediaId,
    required this.mediaType,
    required this.progressPercent,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['media_type'] = Variable<String>(mediaType);
    map['progress_percent'] = Variable<double>(progressPercent);
    map['position_seconds'] = Variable<int>(positionSeconds);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedMediaProgressCompanion toCompanion(bool nullToAbsent) {
    return CachedMediaProgressCompanion(
      mediaId: Value(mediaId),
      mediaType: Value(mediaType),
      progressPercent: Value(progressPercent),
      positionSeconds: Value(positionSeconds),
      durationSeconds: Value(durationSeconds),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedMediaProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMediaProgressData(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      progressPercent: serializer.fromJson<double>(json['progressPercent']),
      positionSeconds: serializer.fromJson<int>(json['positionSeconds']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'mediaType': serializer.toJson<String>(mediaType),
      'progressPercent': serializer.toJson<double>(progressPercent),
      'positionSeconds': serializer.toJson<int>(positionSeconds),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedMediaProgressData copyWith({
    String? mediaId,
    String? mediaType,
    double? progressPercent,
    int? positionSeconds,
    int? durationSeconds,
    DateTime? updatedAt,
  }) => CachedMediaProgressData(
    mediaId: mediaId ?? this.mediaId,
    mediaType: mediaType ?? this.mediaType,
    progressPercent: progressPercent ?? this.progressPercent,
    positionSeconds: positionSeconds ?? this.positionSeconds,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedMediaProgressData copyWithCompanion(CachedMediaProgressCompanion data) {
    return CachedMediaProgressData(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      progressPercent:
          data.progressPercent.present
              ? data.progressPercent.value
              : this.progressPercent,
      positionSeconds:
          data.positionSeconds.present
              ? data.positionSeconds.value
              : this.positionSeconds,
      durationSeconds:
          data.durationSeconds.present
              ? data.durationSeconds.value
              : this.durationSeconds,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMediaProgressData(')
          ..write('mediaId: $mediaId, ')
          ..write('mediaType: $mediaType, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('positionSeconds: $positionSeconds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mediaId,
    mediaType,
    progressPercent,
    positionSeconds,
    durationSeconds,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMediaProgressData &&
          other.mediaId == this.mediaId &&
          other.mediaType == this.mediaType &&
          other.progressPercent == this.progressPercent &&
          other.positionSeconds == this.positionSeconds &&
          other.durationSeconds == this.durationSeconds &&
          other.updatedAt == this.updatedAt);
}

class CachedMediaProgressCompanion
    extends UpdateCompanion<CachedMediaProgressData> {
  final Value<String> mediaId;
  final Value<String> mediaType;
  final Value<double> progressPercent;
  final Value<int> positionSeconds;
  final Value<int> durationSeconds;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedMediaProgressCompanion({
    this.mediaId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.progressPercent = const Value.absent(),
    this.positionSeconds = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMediaProgressCompanion.insert({
    required String mediaId,
    required String mediaType,
    required double progressPercent,
    required int positionSeconds,
    required int durationSeconds,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       mediaType = Value(mediaType),
       progressPercent = Value(progressPercent),
       positionSeconds = Value(positionSeconds),
       durationSeconds = Value(durationSeconds),
       updatedAt = Value(updatedAt);
  static Insertable<CachedMediaProgressData> custom({
    Expression<String>? mediaId,
    Expression<String>? mediaType,
    Expression<double>? progressPercent,
    Expression<int>? positionSeconds,
    Expression<int>? durationSeconds,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (mediaType != null) 'media_type': mediaType,
      if (progressPercent != null) 'progress_percent': progressPercent,
      if (positionSeconds != null) 'position_seconds': positionSeconds,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMediaProgressCompanion copyWith({
    Value<String>? mediaId,
    Value<String>? mediaType,
    Value<double>? progressPercent,
    Value<int>? positionSeconds,
    Value<int>? durationSeconds,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedMediaProgressCompanion(
      mediaId: mediaId ?? this.mediaId,
      mediaType: mediaType ?? this.mediaType,
      progressPercent: progressPercent ?? this.progressPercent,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (progressPercent.present) {
      map['progress_percent'] = Variable<double>(progressPercent.value);
    }
    if (positionSeconds.present) {
      map['position_seconds'] = Variable<int>(positionSeconds.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
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
    return (StringBuffer('CachedMediaProgressCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('mediaType: $mediaType, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('positionSeconds: $positionSeconds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderProgressTable extends CachedReaderProgress
    with TableInfo<$CachedReaderProgressTable, CachedReaderProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterProgressMeta = const VerificationMeta(
    'chapterProgress',
  );
  @override
  late final GeneratedColumn<double> chapterProgress = GeneratedColumn<double>(
    'chapter_progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('scroll'),
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<String> pageId = GeneratedColumn<String>(
    'page_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageIndexMeta = const VerificationMeta(
    'pageIndex',
  );
  @override
  late final GeneratedColumn<int> pageIndex = GeneratedColumn<int>(
    'page_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageFingerprintMeta = const VerificationMeta(
    'pageFingerprint',
  );
  @override
  late final GeneratedColumn<String> pageFingerprint = GeneratedColumn<String>(
    'page_fingerprint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourcePageIndexMeta = const VerificationMeta(
    'sourcePageIndex',
  );
  @override
  late final GeneratedColumn<int> sourcePageIndex = GeneratedColumn<int>(
    'source_page_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _catalogKeyMeta = const VerificationMeta(
    'catalogKey',
  );
  @override
  late final GeneratedColumn<String> catalogKey = GeneratedColumn<String>(
    'catalog_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _manifestVersionMeta = const VerificationMeta(
    'manifestVersion',
  );
  @override
  late final GeneratedColumn<int> manifestVersion = GeneratedColumn<int>(
    'manifest_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _intraPageOffsetMeta = const VerificationMeta(
    'intraPageOffset',
  );
  @override
  late final GeneratedColumn<double> intraPageOffset = GeneratedColumn<double>(
    'intra_page_offset',
    aliasedName,
    true,
    type: DriftSqlType.double,
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
    itemId,
    chapterId,
    charOffset,
    chapterProgress,
    mode,
    pageId,
    pageIndex,
    pageFingerprint,
    sourceId,
    sourcePageIndex,
    catalogKey,
    manifestVersion,
    intraPageOffset,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    }
    if (data.containsKey('chapter_progress')) {
      context.handle(
        _chapterProgressMeta,
        chapterProgress.isAcceptableOrUnknown(
          data['chapter_progress']!,
          _chapterProgressMeta,
        ),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    }
    if (data.containsKey('page_index')) {
      context.handle(
        _pageIndexMeta,
        pageIndex.isAcceptableOrUnknown(data['page_index']!, _pageIndexMeta),
      );
    }
    if (data.containsKey('page_fingerprint')) {
      context.handle(
        _pageFingerprintMeta,
        pageFingerprint.isAcceptableOrUnknown(
          data['page_fingerprint']!,
          _pageFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('source_page_index')) {
      context.handle(
        _sourcePageIndexMeta,
        sourcePageIndex.isAcceptableOrUnknown(
          data['source_page_index']!,
          _sourcePageIndexMeta,
        ),
      );
    }
    if (data.containsKey('catalog_key')) {
      context.handle(
        _catalogKeyMeta,
        catalogKey.isAcceptableOrUnknown(data['catalog_key']!, _catalogKeyMeta),
      );
    }
    if (data.containsKey('manifest_version')) {
      context.handle(
        _manifestVersionMeta,
        manifestVersion.isAcceptableOrUnknown(
          data['manifest_version']!,
          _manifestVersionMeta,
        ),
      );
    }
    if (data.containsKey('intra_page_offset')) {
      context.handle(
        _intraPageOffsetMeta,
        intraPageOffset.isAcceptableOrUnknown(
          data['intra_page_offset']!,
          _intraPageOffsetMeta,
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
  Set<GeneratedColumn> get $primaryKey => {itemId, chapterId};
  @override
  CachedReaderProgressData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderProgressData(
      itemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}item_id'],
          )!,
      chapterId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}chapter_id'],
          )!,
      charOffset:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}char_offset'],
          )!,
      chapterProgress:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}chapter_progress'],
          )!,
      mode:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}mode'],
          )!,
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_id'],
      ),
      pageIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_index'],
      ),
      pageFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_fingerprint'],
      ),
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      sourcePageIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_page_index'],
      ),
      catalogKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catalog_key'],
      ),
      manifestVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}manifest_version'],
      ),
      intraPageOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}intra_page_offset'],
      ),
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $CachedReaderProgressTable createAlias(String alias) {
    return $CachedReaderProgressTable(attachedDatabase, alias);
  }
}

class CachedReaderProgressData extends DataClass
    implements Insertable<CachedReaderProgressData> {
  final String itemId;
  final String chapterId;
  final int charOffset;
  final double chapterProgress;
  final String mode;
  final String? pageId;
  final int? pageIndex;
  final String? pageFingerprint;
  final String? sourceId;
  final int? sourcePageIndex;
  final String? catalogKey;
  final int? manifestVersion;
  final double? intraPageOffset;
  final DateTime updatedAt;
  const CachedReaderProgressData({
    required this.itemId,
    required this.chapterId,
    required this.charOffset,
    required this.chapterProgress,
    required this.mode,
    this.pageId,
    this.pageIndex,
    this.pageFingerprint,
    this.sourceId,
    this.sourcePageIndex,
    this.catalogKey,
    this.manifestVersion,
    this.intraPageOffset,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['chapter_id'] = Variable<String>(chapterId);
    map['char_offset'] = Variable<int>(charOffset);
    map['chapter_progress'] = Variable<double>(chapterProgress);
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || pageId != null) {
      map['page_id'] = Variable<String>(pageId);
    }
    if (!nullToAbsent || pageIndex != null) {
      map['page_index'] = Variable<int>(pageIndex);
    }
    if (!nullToAbsent || pageFingerprint != null) {
      map['page_fingerprint'] = Variable<String>(pageFingerprint);
    }
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || sourcePageIndex != null) {
      map['source_page_index'] = Variable<int>(sourcePageIndex);
    }
    if (!nullToAbsent || catalogKey != null) {
      map['catalog_key'] = Variable<String>(catalogKey);
    }
    if (!nullToAbsent || manifestVersion != null) {
      map['manifest_version'] = Variable<int>(manifestVersion);
    }
    if (!nullToAbsent || intraPageOffset != null) {
      map['intra_page_offset'] = Variable<double>(intraPageOffset);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedReaderProgressCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderProgressCompanion(
      itemId: Value(itemId),
      chapterId: Value(chapterId),
      charOffset: Value(charOffset),
      chapterProgress: Value(chapterProgress),
      mode: Value(mode),
      pageId:
          pageId == null && nullToAbsent ? const Value.absent() : Value(pageId),
      pageIndex:
          pageIndex == null && nullToAbsent
              ? const Value.absent()
              : Value(pageIndex),
      pageFingerprint:
          pageFingerprint == null && nullToAbsent
              ? const Value.absent()
              : Value(pageFingerprint),
      sourceId:
          sourceId == null && nullToAbsent
              ? const Value.absent()
              : Value(sourceId),
      sourcePageIndex:
          sourcePageIndex == null && nullToAbsent
              ? const Value.absent()
              : Value(sourcePageIndex),
      catalogKey:
          catalogKey == null && nullToAbsent
              ? const Value.absent()
              : Value(catalogKey),
      manifestVersion:
          manifestVersion == null && nullToAbsent
              ? const Value.absent()
              : Value(manifestVersion),
      intraPageOffset:
          intraPageOffset == null && nullToAbsent
              ? const Value.absent()
              : Value(intraPageOffset),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedReaderProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderProgressData(
      itemId: serializer.fromJson<String>(json['itemId']),
      chapterId: serializer.fromJson<String>(json['chapterId']),
      charOffset: serializer.fromJson<int>(json['charOffset']),
      chapterProgress: serializer.fromJson<double>(json['chapterProgress']),
      mode: serializer.fromJson<String>(json['mode']),
      pageId: serializer.fromJson<String?>(json['pageId']),
      pageIndex: serializer.fromJson<int?>(json['pageIndex']),
      pageFingerprint: serializer.fromJson<String?>(json['pageFingerprint']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      sourcePageIndex: serializer.fromJson<int?>(json['sourcePageIndex']),
      catalogKey: serializer.fromJson<String?>(json['catalogKey']),
      manifestVersion: serializer.fromJson<int?>(json['manifestVersion']),
      intraPageOffset: serializer.fromJson<double?>(json['intraPageOffset']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'chapterId': serializer.toJson<String>(chapterId),
      'charOffset': serializer.toJson<int>(charOffset),
      'chapterProgress': serializer.toJson<double>(chapterProgress),
      'mode': serializer.toJson<String>(mode),
      'pageId': serializer.toJson<String?>(pageId),
      'pageIndex': serializer.toJson<int?>(pageIndex),
      'pageFingerprint': serializer.toJson<String?>(pageFingerprint),
      'sourceId': serializer.toJson<String?>(sourceId),
      'sourcePageIndex': serializer.toJson<int?>(sourcePageIndex),
      'catalogKey': serializer.toJson<String?>(catalogKey),
      'manifestVersion': serializer.toJson<int?>(manifestVersion),
      'intraPageOffset': serializer.toJson<double?>(intraPageOffset),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedReaderProgressData copyWith({
    String? itemId,
    String? chapterId,
    int? charOffset,
    double? chapterProgress,
    String? mode,
    Value<String?> pageId = const Value.absent(),
    Value<int?> pageIndex = const Value.absent(),
    Value<String?> pageFingerprint = const Value.absent(),
    Value<String?> sourceId = const Value.absent(),
    Value<int?> sourcePageIndex = const Value.absent(),
    Value<String?> catalogKey = const Value.absent(),
    Value<int?> manifestVersion = const Value.absent(),
    Value<double?> intraPageOffset = const Value.absent(),
    DateTime? updatedAt,
  }) => CachedReaderProgressData(
    itemId: itemId ?? this.itemId,
    chapterId: chapterId ?? this.chapterId,
    charOffset: charOffset ?? this.charOffset,
    chapterProgress: chapterProgress ?? this.chapterProgress,
    mode: mode ?? this.mode,
    pageId: pageId.present ? pageId.value : this.pageId,
    pageIndex: pageIndex.present ? pageIndex.value : this.pageIndex,
    pageFingerprint:
        pageFingerprint.present ? pageFingerprint.value : this.pageFingerprint,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    sourcePageIndex:
        sourcePageIndex.present ? sourcePageIndex.value : this.sourcePageIndex,
    catalogKey: catalogKey.present ? catalogKey.value : this.catalogKey,
    manifestVersion:
        manifestVersion.present ? manifestVersion.value : this.manifestVersion,
    intraPageOffset:
        intraPageOffset.present ? intraPageOffset.value : this.intraPageOffset,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedReaderProgressData copyWithCompanion(
    CachedReaderProgressCompanion data,
  ) {
    return CachedReaderProgressData(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      charOffset:
          data.charOffset.present ? data.charOffset.value : this.charOffset,
      chapterProgress:
          data.chapterProgress.present
              ? data.chapterProgress.value
              : this.chapterProgress,
      mode: data.mode.present ? data.mode.value : this.mode,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      pageIndex: data.pageIndex.present ? data.pageIndex.value : this.pageIndex,
      pageFingerprint:
          data.pageFingerprint.present
              ? data.pageFingerprint.value
              : this.pageFingerprint,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourcePageIndex:
          data.sourcePageIndex.present
              ? data.sourcePageIndex.value
              : this.sourcePageIndex,
      catalogKey:
          data.catalogKey.present ? data.catalogKey.value : this.catalogKey,
      manifestVersion:
          data.manifestVersion.present
              ? data.manifestVersion.value
              : this.manifestVersion,
      intraPageOffset:
          data.intraPageOffset.present
              ? data.intraPageOffset.value
              : this.intraPageOffset,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderProgressData(')
          ..write('itemId: $itemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('charOffset: $charOffset, ')
          ..write('chapterProgress: $chapterProgress, ')
          ..write('mode: $mode, ')
          ..write('pageId: $pageId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('pageFingerprint: $pageFingerprint, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourcePageIndex: $sourcePageIndex, ')
          ..write('catalogKey: $catalogKey, ')
          ..write('manifestVersion: $manifestVersion, ')
          ..write('intraPageOffset: $intraPageOffset, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    itemId,
    chapterId,
    charOffset,
    chapterProgress,
    mode,
    pageId,
    pageIndex,
    pageFingerprint,
    sourceId,
    sourcePageIndex,
    catalogKey,
    manifestVersion,
    intraPageOffset,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderProgressData &&
          other.itemId == this.itemId &&
          other.chapterId == this.chapterId &&
          other.charOffset == this.charOffset &&
          other.chapterProgress == this.chapterProgress &&
          other.mode == this.mode &&
          other.pageId == this.pageId &&
          other.pageIndex == this.pageIndex &&
          other.pageFingerprint == this.pageFingerprint &&
          other.sourceId == this.sourceId &&
          other.sourcePageIndex == this.sourcePageIndex &&
          other.catalogKey == this.catalogKey &&
          other.manifestVersion == this.manifestVersion &&
          other.intraPageOffset == this.intraPageOffset &&
          other.updatedAt == this.updatedAt);
}

class CachedReaderProgressCompanion
    extends UpdateCompanion<CachedReaderProgressData> {
  final Value<String> itemId;
  final Value<String> chapterId;
  final Value<int> charOffset;
  final Value<double> chapterProgress;
  final Value<String> mode;
  final Value<String?> pageId;
  final Value<int?> pageIndex;
  final Value<String?> pageFingerprint;
  final Value<String?> sourceId;
  final Value<int?> sourcePageIndex;
  final Value<String?> catalogKey;
  final Value<int?> manifestVersion;
  final Value<double?> intraPageOffset;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedReaderProgressCompanion({
    this.itemId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.chapterProgress = const Value.absent(),
    this.mode = const Value.absent(),
    this.pageId = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.pageFingerprint = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourcePageIndex = const Value.absent(),
    this.catalogKey = const Value.absent(),
    this.manifestVersion = const Value.absent(),
    this.intraPageOffset = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderProgressCompanion.insert({
    required String itemId,
    this.chapterId = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.chapterProgress = const Value.absent(),
    this.mode = const Value.absent(),
    this.pageId = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.pageFingerprint = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourcePageIndex = const Value.absent(),
    this.catalogKey = const Value.absent(),
    this.manifestVersion = const Value.absent(),
    this.intraPageOffset = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       updatedAt = Value(updatedAt);
  static Insertable<CachedReaderProgressData> custom({
    Expression<String>? itemId,
    Expression<String>? chapterId,
    Expression<int>? charOffset,
    Expression<double>? chapterProgress,
    Expression<String>? mode,
    Expression<String>? pageId,
    Expression<int>? pageIndex,
    Expression<String>? pageFingerprint,
    Expression<String>? sourceId,
    Expression<int>? sourcePageIndex,
    Expression<String>? catalogKey,
    Expression<int>? manifestVersion,
    Expression<double>? intraPageOffset,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (charOffset != null) 'char_offset': charOffset,
      if (chapterProgress != null) 'chapter_progress': chapterProgress,
      if (mode != null) 'mode': mode,
      if (pageId != null) 'page_id': pageId,
      if (pageIndex != null) 'page_index': pageIndex,
      if (pageFingerprint != null) 'page_fingerprint': pageFingerprint,
      if (sourceId != null) 'source_id': sourceId,
      if (sourcePageIndex != null) 'source_page_index': sourcePageIndex,
      if (catalogKey != null) 'catalog_key': catalogKey,
      if (manifestVersion != null) 'manifest_version': manifestVersion,
      if (intraPageOffset != null) 'intra_page_offset': intraPageOffset,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderProgressCompanion copyWith({
    Value<String>? itemId,
    Value<String>? chapterId,
    Value<int>? charOffset,
    Value<double>? chapterProgress,
    Value<String>? mode,
    Value<String?>? pageId,
    Value<int?>? pageIndex,
    Value<String?>? pageFingerprint,
    Value<String?>? sourceId,
    Value<int?>? sourcePageIndex,
    Value<String?>? catalogKey,
    Value<int?>? manifestVersion,
    Value<double?>? intraPageOffset,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedReaderProgressCompanion(
      itemId: itemId ?? this.itemId,
      chapterId: chapterId ?? this.chapterId,
      charOffset: charOffset ?? this.charOffset,
      chapterProgress: chapterProgress ?? this.chapterProgress,
      mode: mode ?? this.mode,
      pageId: pageId ?? this.pageId,
      pageIndex: pageIndex ?? this.pageIndex,
      pageFingerprint: pageFingerprint ?? this.pageFingerprint,
      sourceId: sourceId ?? this.sourceId,
      sourcePageIndex: sourcePageIndex ?? this.sourcePageIndex,
      catalogKey: catalogKey ?? this.catalogKey,
      manifestVersion: manifestVersion ?? this.manifestVersion,
      intraPageOffset: intraPageOffset ?? this.intraPageOffset,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (chapterProgress.present) {
      map['chapter_progress'] = Variable<double>(chapterProgress.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<String>(pageId.value);
    }
    if (pageIndex.present) {
      map['page_index'] = Variable<int>(pageIndex.value);
    }
    if (pageFingerprint.present) {
      map['page_fingerprint'] = Variable<String>(pageFingerprint.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourcePageIndex.present) {
      map['source_page_index'] = Variable<int>(sourcePageIndex.value);
    }
    if (catalogKey.present) {
      map['catalog_key'] = Variable<String>(catalogKey.value);
    }
    if (manifestVersion.present) {
      map['manifest_version'] = Variable<int>(manifestVersion.value);
    }
    if (intraPageOffset.present) {
      map['intra_page_offset'] = Variable<double>(intraPageOffset.value);
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
    return (StringBuffer('CachedReaderProgressCompanion(')
          ..write('itemId: $itemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('charOffset: $charOffset, ')
          ..write('chapterProgress: $chapterProgress, ')
          ..write('mode: $mode, ')
          ..write('pageId: $pageId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('pageFingerprint: $pageFingerprint, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourcePageIndex: $sourcePageIndex, ')
          ..write('catalogKey: $catalogKey, ')
          ..write('manifestVersion: $manifestVersion, ')
          ..write('intraPageOffset: $intraPageOffset, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderBookmarksTable extends CachedReaderBookmarks
    with TableInfo<$CachedReaderBookmarksTable, CachedReaderBookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderBookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readerItemIdMeta = const VerificationMeta(
    'readerItemId',
  );
  @override
  late final GeneratedColumn<String> readerItemId = GeneratedColumn<String>(
    'reader_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _progressPercentMeta = const VerificationMeta(
    'progressPercent',
  );
  @override
  late final GeneratedColumn<double> progressPercent = GeneratedColumn<double>(
    'progress_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    readerItemId,
    charOffset,
    progressPercent,
    note,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderBookmark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('reader_item_id')) {
      context.handle(
        _readerItemIdMeta,
        readerItemId.isAcceptableOrUnknown(
          data['reader_item_id']!,
          _readerItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_readerItemIdMeta);
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    }
    if (data.containsKey('progress_percent')) {
      context.handle(
        _progressPercentMeta,
        progressPercent.isAcceptableOrUnknown(
          data['progress_percent']!,
          _progressPercentMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedReaderBookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderBookmark(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      readerItemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}reader_item_id'],
          )!,
      charOffset:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}char_offset'],
          )!,
      progressPercent:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}progress_percent'],
          )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $CachedReaderBookmarksTable createAlias(String alias) {
    return $CachedReaderBookmarksTable(attachedDatabase, alias);
  }
}

class CachedReaderBookmark extends DataClass
    implements Insertable<CachedReaderBookmark> {
  final String id;
  final String readerItemId;
  final int charOffset;
  final double progressPercent;
  final String? note;
  final DateTime createdAt;
  const CachedReaderBookmark({
    required this.id,
    required this.readerItemId,
    required this.charOffset,
    required this.progressPercent,
    this.note,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['reader_item_id'] = Variable<String>(readerItemId);
    map['char_offset'] = Variable<int>(charOffset);
    map['progress_percent'] = Variable<double>(progressPercent);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CachedReaderBookmarksCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderBookmarksCompanion(
      id: Value(id),
      readerItemId: Value(readerItemId),
      charOffset: Value(charOffset),
      progressPercent: Value(progressPercent),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory CachedReaderBookmark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderBookmark(
      id: serializer.fromJson<String>(json['id']),
      readerItemId: serializer.fromJson<String>(json['readerItemId']),
      charOffset: serializer.fromJson<int>(json['charOffset']),
      progressPercent: serializer.fromJson<double>(json['progressPercent']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'readerItemId': serializer.toJson<String>(readerItemId),
      'charOffset': serializer.toJson<int>(charOffset),
      'progressPercent': serializer.toJson<double>(progressPercent),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CachedReaderBookmark copyWith({
    String? id,
    String? readerItemId,
    int? charOffset,
    double? progressPercent,
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
  }) => CachedReaderBookmark(
    id: id ?? this.id,
    readerItemId: readerItemId ?? this.readerItemId,
    charOffset: charOffset ?? this.charOffset,
    progressPercent: progressPercent ?? this.progressPercent,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
  );
  CachedReaderBookmark copyWithCompanion(CachedReaderBookmarksCompanion data) {
    return CachedReaderBookmark(
      id: data.id.present ? data.id.value : this.id,
      readerItemId:
          data.readerItemId.present
              ? data.readerItemId.value
              : this.readerItemId,
      charOffset:
          data.charOffset.present ? data.charOffset.value : this.charOffset,
      progressPercent:
          data.progressPercent.present
              ? data.progressPercent.value
              : this.progressPercent,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderBookmark(')
          ..write('id: $id, ')
          ..write('readerItemId: $readerItemId, ')
          ..write('charOffset: $charOffset, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    readerItemId,
    charOffset,
    progressPercent,
    note,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderBookmark &&
          other.id == this.id &&
          other.readerItemId == this.readerItemId &&
          other.charOffset == this.charOffset &&
          other.progressPercent == this.progressPercent &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class CachedReaderBookmarksCompanion
    extends UpdateCompanion<CachedReaderBookmark> {
  final Value<String> id;
  final Value<String> readerItemId;
  final Value<int> charOffset;
  final Value<double> progressPercent;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CachedReaderBookmarksCompanion({
    this.id = const Value.absent(),
    this.readerItemId = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.progressPercent = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderBookmarksCompanion.insert({
    required String id,
    required String readerItemId,
    this.charOffset = const Value.absent(),
    this.progressPercent = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       readerItemId = Value(readerItemId),
       createdAt = Value(createdAt);
  static Insertable<CachedReaderBookmark> custom({
    Expression<String>? id,
    Expression<String>? readerItemId,
    Expression<int>? charOffset,
    Expression<double>? progressPercent,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (readerItemId != null) 'reader_item_id': readerItemId,
      if (charOffset != null) 'char_offset': charOffset,
      if (progressPercent != null) 'progress_percent': progressPercent,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderBookmarksCompanion copyWith({
    Value<String>? id,
    Value<String>? readerItemId,
    Value<int>? charOffset,
    Value<double>? progressPercent,
    Value<String?>? note,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CachedReaderBookmarksCompanion(
      id: id ?? this.id,
      readerItemId: readerItemId ?? this.readerItemId,
      charOffset: charOffset ?? this.charOffset,
      progressPercent: progressPercent ?? this.progressPercent,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (readerItemId.present) {
      map['reader_item_id'] = Variable<String>(readerItemId.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (progressPercent.present) {
      map['progress_percent'] = Variable<double>(progressPercent.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderBookmarksCompanion(')
          ..write('id: $id, ')
          ..write('readerItemId: $readerItemId, ')
          ..write('charOffset: $charOffset, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderAnnotationsTable extends CachedReaderAnnotations
    with TableInfo<$CachedReaderAnnotationsTable, CachedReaderAnnotation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderAnnotationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readerItemIdMeta = const VerificationMeta(
    'readerItemId',
  );
  @override
  late final GeneratedColumn<String> readerItemId = GeneratedColumn<String>(
    'reader_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startOffsetMeta = const VerificationMeta(
    'startOffset',
  );
  @override
  late final GeneratedColumn<int> startOffset = GeneratedColumn<int>(
    'start_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endOffsetMeta = const VerificationMeta(
    'endOffset',
  );
  @override
  late final GeneratedColumn<int> endOffset = GeneratedColumn<int>(
    'end_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _highlightTextMeta = const VerificationMeta(
    'highlightText',
  );
  @override
  late final GeneratedColumn<String> highlightText = GeneratedColumn<String>(
    'highlight_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#FFEB3B'),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    readerItemId,
    chapterId,
    startOffset,
    endOffset,
    highlightText,
    note,
    color,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_annotations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderAnnotation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('reader_item_id')) {
      context.handle(
        _readerItemIdMeta,
        readerItemId.isAcceptableOrUnknown(
          data['reader_item_id']!,
          _readerItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_readerItemIdMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    }
    if (data.containsKey('start_offset')) {
      context.handle(
        _startOffsetMeta,
        startOffset.isAcceptableOrUnknown(
          data['start_offset']!,
          _startOffsetMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startOffsetMeta);
    }
    if (data.containsKey('end_offset')) {
      context.handle(
        _endOffsetMeta,
        endOffset.isAcceptableOrUnknown(data['end_offset']!, _endOffsetMeta),
      );
    } else if (isInserting) {
      context.missing(_endOffsetMeta);
    }
    if (data.containsKey('highlight_text')) {
      context.handle(
        _highlightTextMeta,
        highlightText.isAcceptableOrUnknown(
          data['highlight_text']!,
          _highlightTextMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedReaderAnnotation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderAnnotation(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      readerItemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}reader_item_id'],
          )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      ),
      startOffset:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}start_offset'],
          )!,
      endOffset:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}end_offset'],
          )!,
      highlightText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}highlight_text'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      color:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}color'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $CachedReaderAnnotationsTable createAlias(String alias) {
    return $CachedReaderAnnotationsTable(attachedDatabase, alias);
  }
}

class CachedReaderAnnotation extends DataClass
    implements Insertable<CachedReaderAnnotation> {
  final String id;
  final String readerItemId;
  final String? chapterId;
  final int startOffset;
  final int endOffset;
  final String? highlightText;
  final String? note;
  final String color;
  final DateTime createdAt;
  const CachedReaderAnnotation({
    required this.id,
    required this.readerItemId,
    this.chapterId,
    required this.startOffset,
    required this.endOffset,
    this.highlightText,
    this.note,
    required this.color,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['reader_item_id'] = Variable<String>(readerItemId);
    if (!nullToAbsent || chapterId != null) {
      map['chapter_id'] = Variable<String>(chapterId);
    }
    map['start_offset'] = Variable<int>(startOffset);
    map['end_offset'] = Variable<int>(endOffset);
    if (!nullToAbsent || highlightText != null) {
      map['highlight_text'] = Variable<String>(highlightText);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['color'] = Variable<String>(color);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CachedReaderAnnotationsCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderAnnotationsCompanion(
      id: Value(id),
      readerItemId: Value(readerItemId),
      chapterId:
          chapterId == null && nullToAbsent
              ? const Value.absent()
              : Value(chapterId),
      startOffset: Value(startOffset),
      endOffset: Value(endOffset),
      highlightText:
          highlightText == null && nullToAbsent
              ? const Value.absent()
              : Value(highlightText),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      color: Value(color),
      createdAt: Value(createdAt),
    );
  }

  factory CachedReaderAnnotation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderAnnotation(
      id: serializer.fromJson<String>(json['id']),
      readerItemId: serializer.fromJson<String>(json['readerItemId']),
      chapterId: serializer.fromJson<String?>(json['chapterId']),
      startOffset: serializer.fromJson<int>(json['startOffset']),
      endOffset: serializer.fromJson<int>(json['endOffset']),
      highlightText: serializer.fromJson<String?>(json['highlightText']),
      note: serializer.fromJson<String?>(json['note']),
      color: serializer.fromJson<String>(json['color']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'readerItemId': serializer.toJson<String>(readerItemId),
      'chapterId': serializer.toJson<String?>(chapterId),
      'startOffset': serializer.toJson<int>(startOffset),
      'endOffset': serializer.toJson<int>(endOffset),
      'highlightText': serializer.toJson<String?>(highlightText),
      'note': serializer.toJson<String?>(note),
      'color': serializer.toJson<String>(color),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CachedReaderAnnotation copyWith({
    String? id,
    String? readerItemId,
    Value<String?> chapterId = const Value.absent(),
    int? startOffset,
    int? endOffset,
    Value<String?> highlightText = const Value.absent(),
    Value<String?> note = const Value.absent(),
    String? color,
    DateTime? createdAt,
  }) => CachedReaderAnnotation(
    id: id ?? this.id,
    readerItemId: readerItemId ?? this.readerItemId,
    chapterId: chapterId.present ? chapterId.value : this.chapterId,
    startOffset: startOffset ?? this.startOffset,
    endOffset: endOffset ?? this.endOffset,
    highlightText:
        highlightText.present ? highlightText.value : this.highlightText,
    note: note.present ? note.value : this.note,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
  );
  CachedReaderAnnotation copyWithCompanion(
    CachedReaderAnnotationsCompanion data,
  ) {
    return CachedReaderAnnotation(
      id: data.id.present ? data.id.value : this.id,
      readerItemId:
          data.readerItemId.present
              ? data.readerItemId.value
              : this.readerItemId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      startOffset:
          data.startOffset.present ? data.startOffset.value : this.startOffset,
      endOffset: data.endOffset.present ? data.endOffset.value : this.endOffset,
      highlightText:
          data.highlightText.present
              ? data.highlightText.value
              : this.highlightText,
      note: data.note.present ? data.note.value : this.note,
      color: data.color.present ? data.color.value : this.color,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderAnnotation(')
          ..write('id: $id, ')
          ..write('readerItemId: $readerItemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('startOffset: $startOffset, ')
          ..write('endOffset: $endOffset, ')
          ..write('highlightText: $highlightText, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    readerItemId,
    chapterId,
    startOffset,
    endOffset,
    highlightText,
    note,
    color,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderAnnotation &&
          other.id == this.id &&
          other.readerItemId == this.readerItemId &&
          other.chapterId == this.chapterId &&
          other.startOffset == this.startOffset &&
          other.endOffset == this.endOffset &&
          other.highlightText == this.highlightText &&
          other.note == this.note &&
          other.color == this.color &&
          other.createdAt == this.createdAt);
}

class CachedReaderAnnotationsCompanion
    extends UpdateCompanion<CachedReaderAnnotation> {
  final Value<String> id;
  final Value<String> readerItemId;
  final Value<String?> chapterId;
  final Value<int> startOffset;
  final Value<int> endOffset;
  final Value<String?> highlightText;
  final Value<String?> note;
  final Value<String> color;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CachedReaderAnnotationsCompanion({
    this.id = const Value.absent(),
    this.readerItemId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.startOffset = const Value.absent(),
    this.endOffset = const Value.absent(),
    this.highlightText = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderAnnotationsCompanion.insert({
    required String id,
    required String readerItemId,
    this.chapterId = const Value.absent(),
    required int startOffset,
    required int endOffset,
    this.highlightText = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       readerItemId = Value(readerItemId),
       startOffset = Value(startOffset),
       endOffset = Value(endOffset),
       createdAt = Value(createdAt);
  static Insertable<CachedReaderAnnotation> custom({
    Expression<String>? id,
    Expression<String>? readerItemId,
    Expression<String>? chapterId,
    Expression<int>? startOffset,
    Expression<int>? endOffset,
    Expression<String>? highlightText,
    Expression<String>? note,
    Expression<String>? color,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (readerItemId != null) 'reader_item_id': readerItemId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (startOffset != null) 'start_offset': startOffset,
      if (endOffset != null) 'end_offset': endOffset,
      if (highlightText != null) 'highlight_text': highlightText,
      if (note != null) 'note': note,
      if (color != null) 'color': color,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderAnnotationsCompanion copyWith({
    Value<String>? id,
    Value<String>? readerItemId,
    Value<String?>? chapterId,
    Value<int>? startOffset,
    Value<int>? endOffset,
    Value<String?>? highlightText,
    Value<String?>? note,
    Value<String>? color,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CachedReaderAnnotationsCompanion(
      id: id ?? this.id,
      readerItemId: readerItemId ?? this.readerItemId,
      chapterId: chapterId ?? this.chapterId,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      highlightText: highlightText ?? this.highlightText,
      note: note ?? this.note,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (readerItemId.present) {
      map['reader_item_id'] = Variable<String>(readerItemId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (startOffset.present) {
      map['start_offset'] = Variable<int>(startOffset.value);
    }
    if (endOffset.present) {
      map['end_offset'] = Variable<int>(endOffset.value);
    }
    if (highlightText.present) {
      map['highlight_text'] = Variable<String>(highlightText.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderAnnotationsCompanion(')
          ..write('id: $id, ')
          ..write('readerItemId: $readerItemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('startOffset: $startOffset, ')
          ..write('endOffset: $endOffset, ')
          ..write('highlightText: $highlightText, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderNotesTable extends CachedReaderNotes
    with TableInfo<$CachedReaderNotesTable, CachedReaderNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readerItemIdMeta = const VerificationMeta(
    'readerItemId',
  );
  @override
  late final GeneratedColumn<String> readerItemId = GeneratedColumn<String>(
    'reader_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    readerItemId,
    charOffset,
    title,
    content,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('reader_item_id')) {
      context.handle(
        _readerItemIdMeta,
        readerItemId.isAcceptableOrUnknown(
          data['reader_item_id']!,
          _readerItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_readerItemIdMeta);
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedReaderNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderNote(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      readerItemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}reader_item_id'],
          )!,
      charOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_offset'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      content:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}content'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $CachedReaderNotesTable createAlias(String alias) {
    return $CachedReaderNotesTable(attachedDatabase, alias);
  }
}

class CachedReaderNote extends DataClass
    implements Insertable<CachedReaderNote> {
  final String id;
  final String readerItemId;
  final int? charOffset;
  final String? title;
  final String content;
  final DateTime createdAt;
  const CachedReaderNote({
    required this.id,
    required this.readerItemId,
    this.charOffset,
    this.title,
    required this.content,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['reader_item_id'] = Variable<String>(readerItemId);
    if (!nullToAbsent || charOffset != null) {
      map['char_offset'] = Variable<int>(charOffset);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CachedReaderNotesCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderNotesCompanion(
      id: Value(id),
      readerItemId: Value(readerItemId),
      charOffset:
          charOffset == null && nullToAbsent
              ? const Value.absent()
              : Value(charOffset),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      content: Value(content),
      createdAt: Value(createdAt),
    );
  }

  factory CachedReaderNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderNote(
      id: serializer.fromJson<String>(json['id']),
      readerItemId: serializer.fromJson<String>(json['readerItemId']),
      charOffset: serializer.fromJson<int?>(json['charOffset']),
      title: serializer.fromJson<String?>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'readerItemId': serializer.toJson<String>(readerItemId),
      'charOffset': serializer.toJson<int?>(charOffset),
      'title': serializer.toJson<String?>(title),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CachedReaderNote copyWith({
    String? id,
    String? readerItemId,
    Value<int?> charOffset = const Value.absent(),
    Value<String?> title = const Value.absent(),
    String? content,
    DateTime? createdAt,
  }) => CachedReaderNote(
    id: id ?? this.id,
    readerItemId: readerItemId ?? this.readerItemId,
    charOffset: charOffset.present ? charOffset.value : this.charOffset,
    title: title.present ? title.value : this.title,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
  );
  CachedReaderNote copyWithCompanion(CachedReaderNotesCompanion data) {
    return CachedReaderNote(
      id: data.id.present ? data.id.value : this.id,
      readerItemId:
          data.readerItemId.present
              ? data.readerItemId.value
              : this.readerItemId,
      charOffset:
          data.charOffset.present ? data.charOffset.value : this.charOffset,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderNote(')
          ..write('id: $id, ')
          ..write('readerItemId: $readerItemId, ')
          ..write('charOffset: $charOffset, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, readerItemId, charOffset, title, content, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderNote &&
          other.id == this.id &&
          other.readerItemId == this.readerItemId &&
          other.charOffset == this.charOffset &&
          other.title == this.title &&
          other.content == this.content &&
          other.createdAt == this.createdAt);
}

class CachedReaderNotesCompanion extends UpdateCompanion<CachedReaderNote> {
  final Value<String> id;
  final Value<String> readerItemId;
  final Value<int?> charOffset;
  final Value<String?> title;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CachedReaderNotesCompanion({
    this.id = const Value.absent(),
    this.readerItemId = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderNotesCompanion.insert({
    required String id,
    required String readerItemId,
    this.charOffset = const Value.absent(),
    this.title = const Value.absent(),
    required String content,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       readerItemId = Value(readerItemId),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<CachedReaderNote> custom({
    Expression<String>? id,
    Expression<String>? readerItemId,
    Expression<int>? charOffset,
    Expression<String>? title,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (readerItemId != null) 'reader_item_id': readerItemId,
      if (charOffset != null) 'char_offset': charOffset,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? readerItemId,
    Value<int?>? charOffset,
    Value<String?>? title,
    Value<String>? content,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CachedReaderNotesCompanion(
      id: id ?? this.id,
      readerItemId: readerItemId ?? this.readerItemId,
      charOffset: charOffset ?? this.charOffset,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (readerItemId.present) {
      map['reader_item_id'] = Variable<String>(readerItemId.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderNotesCompanion(')
          ..write('id: $id, ')
          ..write('readerItemId: $readerItemId, ')
          ..write('charOffset: $charOffset, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderBooksTable extends CachedReaderBooks
    with TableInfo<$CachedReaderBooksTable, CachedReaderBook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderBooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publisherMeta = const VerificationMeta(
    'publisher',
  );
  @override
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chaptersJsonMeta = const VerificationMeta(
    'chaptersJson',
  );
  @override
  late final GeneratedColumn<String> chaptersJson = GeneratedColumn<String>(
    'chapters_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _totalCharsMeta = const VerificationMeta(
    'totalChars',
  );
  @override
  late final GeneratedColumn<int> totalChars = GeneratedColumn<int>(
    'total_chars',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _itemTypeMeta = const VerificationMeta(
    'itemType',
  );
  @override
  late final GeneratedColumn<String> itemType = GeneratedColumn<String>(
    'item_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('EPUB'),
  );
  static const VerificationMeta _cacheVersionMeta = const VerificationMeta(
    'cacheVersion',
  );
  @override
  late final GeneratedColumn<String> cacheVersion = GeneratedColumn<String>(
    'cache_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    itemId,
    title,
    author,
    description,
    publisher,
    language,
    chaptersJson,
    totalChars,
    itemType,
    cacheVersion,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_books';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderBook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('publisher')) {
      context.handle(
        _publisherMeta,
        publisher.isAcceptableOrUnknown(data['publisher']!, _publisherMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('chapters_json')) {
      context.handle(
        _chaptersJsonMeta,
        chaptersJson.isAcceptableOrUnknown(
          data['chapters_json']!,
          _chaptersJsonMeta,
        ),
      );
    }
    if (data.containsKey('total_chars')) {
      context.handle(
        _totalCharsMeta,
        totalChars.isAcceptableOrUnknown(data['total_chars']!, _totalCharsMeta),
      );
    }
    if (data.containsKey('item_type')) {
      context.handle(
        _itemTypeMeta,
        itemType.isAcceptableOrUnknown(data['item_type']!, _itemTypeMeta),
      );
    }
    if (data.containsKey('cache_version')) {
      context.handle(
        _cacheVersionMeta,
        cacheVersion.isAcceptableOrUnknown(
          data['cache_version']!,
          _cacheVersionMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId};
  @override
  CachedReaderBook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderBook(
      itemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}item_id'],
          )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      chaptersJson:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}chapters_json'],
          )!,
      totalChars:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}total_chars'],
          )!,
      itemType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}item_type'],
          )!,
      cacheVersion:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}cache_version'],
          )!,
      cachedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}cached_at'],
          )!,
    );
  }

  @override
  $CachedReaderBooksTable createAlias(String alias) {
    return $CachedReaderBooksTable(attachedDatabase, alias);
  }
}

class CachedReaderBook extends DataClass
    implements Insertable<CachedReaderBook> {
  /// 书籍条目 ID（主键）
  final String itemId;

  /// 书籍标题
  final String? title;

  /// 作者
  final String? author;

  /// 简介
  final String? description;

  /// 出版社
  final String? publisher;

  /// 语言
  final String? language;

  /// 章节列表 JSON（List<Map>，含 number/title/charCount/contentPath）
  final String chaptersJson;

  /// 总字符数
  final int totalChars;

  /// 文件类型（EPUB/TXT/PDF）
  final String itemType;

  /// 缓存版本指纹（条目 updatedAt）。
  ///
  /// 服务端重新解析会更新条目 updatedAt；版本不符时丢弃元数据与章节
  /// 切片缓存，避免 TXT 字符偏移变化后继续命中错位的旧章节内容。
  final String cacheVersion;

  /// 缓存创建时间
  final DateTime cachedAt;
  const CachedReaderBook({
    required this.itemId,
    this.title,
    this.author,
    this.description,
    this.publisher,
    this.language,
    required this.chaptersJson,
    required this.totalChars,
    required this.itemType,
    required this.cacheVersion,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || publisher != null) {
      map['publisher'] = Variable<String>(publisher);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    map['chapters_json'] = Variable<String>(chaptersJson);
    map['total_chars'] = Variable<int>(totalChars);
    map['item_type'] = Variable<String>(itemType);
    map['cache_version'] = Variable<String>(cacheVersion);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedReaderBooksCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderBooksCompanion(
      itemId: Value(itemId),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      author:
          author == null && nullToAbsent ? const Value.absent() : Value(author),
      description:
          description == null && nullToAbsent
              ? const Value.absent()
              : Value(description),
      publisher:
          publisher == null && nullToAbsent
              ? const Value.absent()
              : Value(publisher),
      language:
          language == null && nullToAbsent
              ? const Value.absent()
              : Value(language),
      chaptersJson: Value(chaptersJson),
      totalChars: Value(totalChars),
      itemType: Value(itemType),
      cacheVersion: Value(cacheVersion),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedReaderBook.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderBook(
      itemId: serializer.fromJson<String>(json['itemId']),
      title: serializer.fromJson<String?>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      description: serializer.fromJson<String?>(json['description']),
      publisher: serializer.fromJson<String?>(json['publisher']),
      language: serializer.fromJson<String?>(json['language']),
      chaptersJson: serializer.fromJson<String>(json['chaptersJson']),
      totalChars: serializer.fromJson<int>(json['totalChars']),
      itemType: serializer.fromJson<String>(json['itemType']),
      cacheVersion: serializer.fromJson<String>(json['cacheVersion']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'title': serializer.toJson<String?>(title),
      'author': serializer.toJson<String?>(author),
      'description': serializer.toJson<String?>(description),
      'publisher': serializer.toJson<String?>(publisher),
      'language': serializer.toJson<String?>(language),
      'chaptersJson': serializer.toJson<String>(chaptersJson),
      'totalChars': serializer.toJson<int>(totalChars),
      'itemType': serializer.toJson<String>(itemType),
      'cacheVersion': serializer.toJson<String>(cacheVersion),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedReaderBook copyWith({
    String? itemId,
    Value<String?> title = const Value.absent(),
    Value<String?> author = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> publisher = const Value.absent(),
    Value<String?> language = const Value.absent(),
    String? chaptersJson,
    int? totalChars,
    String? itemType,
    String? cacheVersion,
    DateTime? cachedAt,
  }) => CachedReaderBook(
    itemId: itemId ?? this.itemId,
    title: title.present ? title.value : this.title,
    author: author.present ? author.value : this.author,
    description: description.present ? description.value : this.description,
    publisher: publisher.present ? publisher.value : this.publisher,
    language: language.present ? language.value : this.language,
    chaptersJson: chaptersJson ?? this.chaptersJson,
    totalChars: totalChars ?? this.totalChars,
    itemType: itemType ?? this.itemType,
    cacheVersion: cacheVersion ?? this.cacheVersion,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedReaderBook copyWithCompanion(CachedReaderBooksCompanion data) {
    return CachedReaderBook(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      description:
          data.description.present ? data.description.value : this.description,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      language: data.language.present ? data.language.value : this.language,
      chaptersJson:
          data.chaptersJson.present
              ? data.chaptersJson.value
              : this.chaptersJson,
      totalChars:
          data.totalChars.present ? data.totalChars.value : this.totalChars,
      itemType: data.itemType.present ? data.itemType.value : this.itemType,
      cacheVersion:
          data.cacheVersion.present
              ? data.cacheVersion.value
              : this.cacheVersion,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderBook(')
          ..write('itemId: $itemId, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('publisher: $publisher, ')
          ..write('language: $language, ')
          ..write('chaptersJson: $chaptersJson, ')
          ..write('totalChars: $totalChars, ')
          ..write('itemType: $itemType, ')
          ..write('cacheVersion: $cacheVersion, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    itemId,
    title,
    author,
    description,
    publisher,
    language,
    chaptersJson,
    totalChars,
    itemType,
    cacheVersion,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderBook &&
          other.itemId == this.itemId &&
          other.title == this.title &&
          other.author == this.author &&
          other.description == this.description &&
          other.publisher == this.publisher &&
          other.language == this.language &&
          other.chaptersJson == this.chaptersJson &&
          other.totalChars == this.totalChars &&
          other.itemType == this.itemType &&
          other.cacheVersion == this.cacheVersion &&
          other.cachedAt == this.cachedAt);
}

class CachedReaderBooksCompanion extends UpdateCompanion<CachedReaderBook> {
  final Value<String> itemId;
  final Value<String?> title;
  final Value<String?> author;
  final Value<String?> description;
  final Value<String?> publisher;
  final Value<String?> language;
  final Value<String> chaptersJson;
  final Value<int> totalChars;
  final Value<String> itemType;
  final Value<String> cacheVersion;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedReaderBooksCompanion({
    this.itemId = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.publisher = const Value.absent(),
    this.language = const Value.absent(),
    this.chaptersJson = const Value.absent(),
    this.totalChars = const Value.absent(),
    this.itemType = const Value.absent(),
    this.cacheVersion = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderBooksCompanion.insert({
    required String itemId,
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.publisher = const Value.absent(),
    this.language = const Value.absent(),
    this.chaptersJson = const Value.absent(),
    this.totalChars = const Value.absent(),
    this.itemType = const Value.absent(),
    this.cacheVersion = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       cachedAt = Value(cachedAt);
  static Insertable<CachedReaderBook> custom({
    Expression<String>? itemId,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? description,
    Expression<String>? publisher,
    Expression<String>? language,
    Expression<String>? chaptersJson,
    Expression<int>? totalChars,
    Expression<String>? itemType,
    Expression<String>? cacheVersion,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (description != null) 'description': description,
      if (publisher != null) 'publisher': publisher,
      if (language != null) 'language': language,
      if (chaptersJson != null) 'chapters_json': chaptersJson,
      if (totalChars != null) 'total_chars': totalChars,
      if (itemType != null) 'item_type': itemType,
      if (cacheVersion != null) 'cache_version': cacheVersion,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderBooksCompanion copyWith({
    Value<String>? itemId,
    Value<String?>? title,
    Value<String?>? author,
    Value<String?>? description,
    Value<String?>? publisher,
    Value<String?>? language,
    Value<String>? chaptersJson,
    Value<int>? totalChars,
    Value<String>? itemType,
    Value<String>? cacheVersion,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedReaderBooksCompanion(
      itemId: itemId ?? this.itemId,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      publisher: publisher ?? this.publisher,
      language: language ?? this.language,
      chaptersJson: chaptersJson ?? this.chaptersJson,
      totalChars: totalChars ?? this.totalChars,
      itemType: itemType ?? this.itemType,
      cacheVersion: cacheVersion ?? this.cacheVersion,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (chaptersJson.present) {
      map['chapters_json'] = Variable<String>(chaptersJson.value);
    }
    if (totalChars.present) {
      map['total_chars'] = Variable<int>(totalChars.value);
    }
    if (itemType.present) {
      map['item_type'] = Variable<String>(itemType.value);
    }
    if (cacheVersion.present) {
      map['cache_version'] = Variable<String>(cacheVersion.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderBooksCompanion(')
          ..write('itemId: $itemId, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('publisher: $publisher, ')
          ..write('language: $language, ')
          ..write('chaptersJson: $chaptersJson, ')
          ..write('totalChars: $totalChars, ')
          ..write('itemType: $itemType, ')
          ..write('cacheVersion: $cacheVersion, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderChaptersTable extends CachedReaderChapters
    with TableInfo<$CachedReaderChaptersTable, CachedReaderChapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentPathMeta = const VerificationMeta(
    'contentPath',
  );
  @override
  late final GeneratedColumn<String> contentPath = GeneratedColumn<String>(
    'content_path',
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
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _chapterNumberMeta = const VerificationMeta(
    'chapterNumber',
  );
  @override
  late final GeneratedColumn<int> chapterNumber = GeneratedColumn<int>(
    'chapter_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charCountMeta = const VerificationMeta(
    'charCount',
  );
  @override
  late final GeneratedColumn<int> charCount = GeneratedColumn<int>(
    'char_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _processedHtmlMeta = const VerificationMeta(
    'processedHtml',
  );
  @override
  late final GeneratedColumn<String> processedHtml = GeneratedColumn<String>(
    'processed_html',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    itemId,
    contentPath,
    title,
    chapterNumber,
    charCount,
    processedHtml,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderChapter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('content_path')) {
      context.handle(
        _contentPathMeta,
        contentPath.isAcceptableOrUnknown(
          data['content_path']!,
          _contentPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentPathMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('chapter_number')) {
      context.handle(
        _chapterNumberMeta,
        chapterNumber.isAcceptableOrUnknown(
          data['chapter_number']!,
          _chapterNumberMeta,
        ),
      );
    }
    if (data.containsKey('char_count')) {
      context.handle(
        _charCountMeta,
        charCount.isAcceptableOrUnknown(data['char_count']!, _charCountMeta),
      );
    }
    if (data.containsKey('processed_html')) {
      context.handle(
        _processedHtmlMeta,
        processedHtml.isAcceptableOrUnknown(
          data['processed_html']!,
          _processedHtmlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_processedHtmlMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId, contentPath};
  @override
  CachedReaderChapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderChapter(
      itemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}item_id'],
          )!,
      contentPath:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}content_path'],
          )!,
      title:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      chapterNumber:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}chapter_number'],
          )!,
      charCount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}char_count'],
          )!,
      processedHtml:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}processed_html'],
          )!,
      cachedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}cached_at'],
          )!,
    );
  }

  @override
  $CachedReaderChaptersTable createAlias(String alias) {
    return $CachedReaderChaptersTable(attachedDatabase, alias);
  }
}

class CachedReaderChapter extends DataClass
    implements Insertable<CachedReaderChapter> {
  /// 书籍条目 ID
  final String itemId;

  /// 章节内容路径（EPUB 内部路径，如 OEBPS/chapter1.xhtml）
  final String contentPath;

  /// 章节标题
  final String title;

  /// 章节序号
  final int chapterNumber;

  /// 原始 XHTML 字符数
  final int charCount;

  /// 预处理后的 HTML 内容（已提取 body、图片已转 base64）
  final String processedHtml;

  /// 缓存创建时间
  final DateTime cachedAt;
  const CachedReaderChapter({
    required this.itemId,
    required this.contentPath,
    required this.title,
    required this.chapterNumber,
    required this.charCount,
    required this.processedHtml,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['content_path'] = Variable<String>(contentPath);
    map['title'] = Variable<String>(title);
    map['chapter_number'] = Variable<int>(chapterNumber);
    map['char_count'] = Variable<int>(charCount);
    map['processed_html'] = Variable<String>(processedHtml);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedReaderChaptersCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderChaptersCompanion(
      itemId: Value(itemId),
      contentPath: Value(contentPath),
      title: Value(title),
      chapterNumber: Value(chapterNumber),
      charCount: Value(charCount),
      processedHtml: Value(processedHtml),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedReaderChapter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderChapter(
      itemId: serializer.fromJson<String>(json['itemId']),
      contentPath: serializer.fromJson<String>(json['contentPath']),
      title: serializer.fromJson<String>(json['title']),
      chapterNumber: serializer.fromJson<int>(json['chapterNumber']),
      charCount: serializer.fromJson<int>(json['charCount']),
      processedHtml: serializer.fromJson<String>(json['processedHtml']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'contentPath': serializer.toJson<String>(contentPath),
      'title': serializer.toJson<String>(title),
      'chapterNumber': serializer.toJson<int>(chapterNumber),
      'charCount': serializer.toJson<int>(charCount),
      'processedHtml': serializer.toJson<String>(processedHtml),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedReaderChapter copyWith({
    String? itemId,
    String? contentPath,
    String? title,
    int? chapterNumber,
    int? charCount,
    String? processedHtml,
    DateTime? cachedAt,
  }) => CachedReaderChapter(
    itemId: itemId ?? this.itemId,
    contentPath: contentPath ?? this.contentPath,
    title: title ?? this.title,
    chapterNumber: chapterNumber ?? this.chapterNumber,
    charCount: charCount ?? this.charCount,
    processedHtml: processedHtml ?? this.processedHtml,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedReaderChapter copyWithCompanion(CachedReaderChaptersCompanion data) {
    return CachedReaderChapter(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      contentPath:
          data.contentPath.present ? data.contentPath.value : this.contentPath,
      title: data.title.present ? data.title.value : this.title,
      chapterNumber:
          data.chapterNumber.present
              ? data.chapterNumber.value
              : this.chapterNumber,
      charCount: data.charCount.present ? data.charCount.value : this.charCount,
      processedHtml:
          data.processedHtml.present
              ? data.processedHtml.value
              : this.processedHtml,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderChapter(')
          ..write('itemId: $itemId, ')
          ..write('contentPath: $contentPath, ')
          ..write('title: $title, ')
          ..write('chapterNumber: $chapterNumber, ')
          ..write('charCount: $charCount, ')
          ..write('processedHtml: $processedHtml, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    itemId,
    contentPath,
    title,
    chapterNumber,
    charCount,
    processedHtml,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderChapter &&
          other.itemId == this.itemId &&
          other.contentPath == this.contentPath &&
          other.title == this.title &&
          other.chapterNumber == this.chapterNumber &&
          other.charCount == this.charCount &&
          other.processedHtml == this.processedHtml &&
          other.cachedAt == this.cachedAt);
}

class CachedReaderChaptersCompanion
    extends UpdateCompanion<CachedReaderChapter> {
  final Value<String> itemId;
  final Value<String> contentPath;
  final Value<String> title;
  final Value<int> chapterNumber;
  final Value<int> charCount;
  final Value<String> processedHtml;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedReaderChaptersCompanion({
    this.itemId = const Value.absent(),
    this.contentPath = const Value.absent(),
    this.title = const Value.absent(),
    this.chapterNumber = const Value.absent(),
    this.charCount = const Value.absent(),
    this.processedHtml = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderChaptersCompanion.insert({
    required String itemId,
    required String contentPath,
    this.title = const Value.absent(),
    this.chapterNumber = const Value.absent(),
    this.charCount = const Value.absent(),
    required String processedHtml,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       contentPath = Value(contentPath),
       processedHtml = Value(processedHtml),
       cachedAt = Value(cachedAt);
  static Insertable<CachedReaderChapter> custom({
    Expression<String>? itemId,
    Expression<String>? contentPath,
    Expression<String>? title,
    Expression<int>? chapterNumber,
    Expression<int>? charCount,
    Expression<String>? processedHtml,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (contentPath != null) 'content_path': contentPath,
      if (title != null) 'title': title,
      if (chapterNumber != null) 'chapter_number': chapterNumber,
      if (charCount != null) 'char_count': charCount,
      if (processedHtml != null) 'processed_html': processedHtml,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderChaptersCompanion copyWith({
    Value<String>? itemId,
    Value<String>? contentPath,
    Value<String>? title,
    Value<int>? chapterNumber,
    Value<int>? charCount,
    Value<String>? processedHtml,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedReaderChaptersCompanion(
      itemId: itemId ?? this.itemId,
      contentPath: contentPath ?? this.contentPath,
      title: title ?? this.title,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      charCount: charCount ?? this.charCount,
      processedHtml: processedHtml ?? this.processedHtml,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (contentPath.present) {
      map['content_path'] = Variable<String>(contentPath.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (chapterNumber.present) {
      map['chapter_number'] = Variable<int>(chapterNumber.value);
    }
    if (charCount.present) {
      map['char_count'] = Variable<int>(charCount.value);
    }
    if (processedHtml.present) {
      map['processed_html'] = Variable<String>(processedHtml.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderChaptersCompanion(')
          ..write('itemId: $itemId, ')
          ..write('contentPath: $contentPath, ')
          ..write('title: $title, ')
          ..write('chapterNumber: $chapterNumber, ')
          ..write('charCount: $charCount, ')
          ..write('processedHtml: $processedHtml, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderBookDetailsTable extends CachedReaderBookDetails
    with TableInfo<$CachedReaderBookDetailsTable, CachedReaderBookDetail> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderBookDetailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailJsonMeta = const VerificationMeta(
    'detailJson',
  );
  @override
  late final GeneratedColumn<String> detailJson = GeneratedColumn<String>(
    'detail_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [itemId, detailJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_book_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderBookDetail> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('detail_json')) {
      context.handle(
        _detailJsonMeta,
        detailJson.isAcceptableOrUnknown(data['detail_json']!, _detailJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_detailJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId};
  @override
  CachedReaderBookDetail map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderBookDetail(
      itemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}item_id'],
          )!,
      detailJson:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}detail_json'],
          )!,
      cachedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}cached_at'],
          )!,
    );
  }

  @override
  $CachedReaderBookDetailsTable createAlias(String alias) {
    return $CachedReaderBookDetailsTable(attachedDatabase, alias);
  }
}

class CachedReaderBookDetail extends DataClass
    implements Insertable<CachedReaderBookDetail> {
  /// 书籍条目 ID（主键）
  final String itemId;

  /// 完整的 ReaderItemDetail JSON
  final String detailJson;

  /// 缓存创建时间
  final DateTime cachedAt;
  const CachedReaderBookDetail({
    required this.itemId,
    required this.detailJson,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['detail_json'] = Variable<String>(detailJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedReaderBookDetailsCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderBookDetailsCompanion(
      itemId: Value(itemId),
      detailJson: Value(detailJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedReaderBookDetail.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderBookDetail(
      itemId: serializer.fromJson<String>(json['itemId']),
      detailJson: serializer.fromJson<String>(json['detailJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'detailJson': serializer.toJson<String>(detailJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedReaderBookDetail copyWith({
    String? itemId,
    String? detailJson,
    DateTime? cachedAt,
  }) => CachedReaderBookDetail(
    itemId: itemId ?? this.itemId,
    detailJson: detailJson ?? this.detailJson,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedReaderBookDetail copyWithCompanion(
    CachedReaderBookDetailsCompanion data,
  ) {
    return CachedReaderBookDetail(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      detailJson:
          data.detailJson.present ? data.detailJson.value : this.detailJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderBookDetail(')
          ..write('itemId: $itemId, ')
          ..write('detailJson: $detailJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(itemId, detailJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderBookDetail &&
          other.itemId == this.itemId &&
          other.detailJson == this.detailJson &&
          other.cachedAt == this.cachedAt);
}

class CachedReaderBookDetailsCompanion
    extends UpdateCompanion<CachedReaderBookDetail> {
  final Value<String> itemId;
  final Value<String> detailJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CachedReaderBookDetailsCompanion({
    this.itemId = const Value.absent(),
    this.detailJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderBookDetailsCompanion.insert({
    required String itemId,
    required String detailJson,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       detailJson = Value(detailJson),
       cachedAt = Value(cachedAt);
  static Insertable<CachedReaderBookDetail> custom({
    Expression<String>? itemId,
    Expression<String>? detailJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (detailJson != null) 'detail_json': detailJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderBookDetailsCompanion copyWith({
    Value<String>? itemId,
    Value<String>? detailJson,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedReaderBookDetailsCompanion(
      itemId: itemId ?? this.itemId,
      detailJson: detailJson ?? this.detailJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (detailJson.present) {
      map['detail_json'] = Variable<String>(detailJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderBookDetailsCompanion(')
          ..write('itemId: $itemId, ')
          ..write('detailJson: $detailJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedReaderImagesTable extends CachedReaderImages
    with TableInfo<$CachedReaderImagesTable, CachedReaderImage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedReaderImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('image/png'),
  );
  static const VerificationMeta _storageKeyMeta = const VerificationMeta(
    'storageKey',
  );
  @override
  late final GeneratedColumn<String> storageKey = GeneratedColumn<String>(
    'storage_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptionVersionMeta = const VerificationMeta(
    'encryptionVersion',
  );
  @override
  late final GeneratedColumn<int> encryptionVersion = GeneratedColumn<int>(
    'encryption_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAccessedAtMeta = const VerificationMeta(
    'lastAccessedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAccessedAt =
      GeneratedColumn<DateTime>(
        'last_accessed_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    itemId,
    imagePath,
    mimeType,
    storageKey,
    sizeBytes,
    encryptionVersion,
    cachedAt,
    lastAccessedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_reader_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedReaderImage> instance, {
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
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    } else if (isInserting) {
      context.missing(_imagePathMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('storage_key')) {
      context.handle(
        _storageKeyMeta,
        storageKey.isAcceptableOrUnknown(data['storage_key']!, _storageKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_storageKeyMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('encryption_version')) {
      context.handle(
        _encryptionVersionMeta,
        encryptionVersion.isAcceptableOrUnknown(
          data['encryption_version']!,
          _encryptionVersionMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    if (data.containsKey('last_accessed_at')) {
      context.handle(
        _lastAccessedAtMeta,
        lastAccessedAt.isAcceptableOrUnknown(
          data['last_accessed_at']!,
          _lastAccessedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, itemId, imagePath};
  @override
  CachedReaderImage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReaderImage(
      userId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}user_id'],
          )!,
      itemId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}item_id'],
          )!,
      imagePath:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}image_path'],
          )!,
      mimeType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}mime_type'],
          )!,
      storageKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}storage_key'],
          )!,
      sizeBytes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}size_bytes'],
          )!,
      encryptionVersion:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}encryption_version'],
          )!,
      cachedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}cached_at'],
          )!,
      lastAccessedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}last_accessed_at'],
          )!,
    );
  }

  @override
  $CachedReaderImagesTable createAlias(String alias) {
    return $CachedReaderImagesTable(attachedDatabase, alias);
  }
}

class CachedReaderImage extends DataClass
    implements Insertable<CachedReaderImage> {
  /// 缓存所属用户 ID。
  final String userId;

  /// 阅读条目 ID。
  final String itemId;

  /// 图片在原始阅读文件中的路径。
  final String imagePath;

  /// 图片 MIME 类型。
  final String mimeType;

  /// 加密文件的稳定存储键。
  final String storageKey;

  /// 图片明文字节数。
  final int sizeBytes;

  /// 加密信封版本。
  final int encryptionVersion;

  /// 缓存创建时间。
  final DateTime cachedAt;

  /// 最近访问时间。
  final DateTime lastAccessedAt;
  const CachedReaderImage({
    required this.userId,
    required this.itemId,
    required this.imagePath,
    required this.mimeType,
    required this.storageKey,
    required this.sizeBytes,
    required this.encryptionVersion,
    required this.cachedAt,
    required this.lastAccessedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['item_id'] = Variable<String>(itemId);
    map['image_path'] = Variable<String>(imagePath);
    map['mime_type'] = Variable<String>(mimeType);
    map['storage_key'] = Variable<String>(storageKey);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['encryption_version'] = Variable<int>(encryptionVersion);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt);
    return map;
  }

  CachedReaderImagesCompanion toCompanion(bool nullToAbsent) {
    return CachedReaderImagesCompanion(
      userId: Value(userId),
      itemId: Value(itemId),
      imagePath: Value(imagePath),
      mimeType: Value(mimeType),
      storageKey: Value(storageKey),
      sizeBytes: Value(sizeBytes),
      encryptionVersion: Value(encryptionVersion),
      cachedAt: Value(cachedAt),
      lastAccessedAt: Value(lastAccessedAt),
    );
  }

  factory CachedReaderImage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReaderImage(
      userId: serializer.fromJson<String>(json['userId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      imagePath: serializer.fromJson<String>(json['imagePath']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      storageKey: serializer.fromJson<String>(json['storageKey']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      encryptionVersion: serializer.fromJson<int>(json['encryptionVersion']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
      lastAccessedAt: serializer.fromJson<DateTime>(json['lastAccessedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'itemId': serializer.toJson<String>(itemId),
      'imagePath': serializer.toJson<String>(imagePath),
      'mimeType': serializer.toJson<String>(mimeType),
      'storageKey': serializer.toJson<String>(storageKey),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'encryptionVersion': serializer.toJson<int>(encryptionVersion),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
      'lastAccessedAt': serializer.toJson<DateTime>(lastAccessedAt),
    };
  }

  CachedReaderImage copyWith({
    String? userId,
    String? itemId,
    String? imagePath,
    String? mimeType,
    String? storageKey,
    int? sizeBytes,
    int? encryptionVersion,
    DateTime? cachedAt,
    DateTime? lastAccessedAt,
  }) => CachedReaderImage(
    userId: userId ?? this.userId,
    itemId: itemId ?? this.itemId,
    imagePath: imagePath ?? this.imagePath,
    mimeType: mimeType ?? this.mimeType,
    storageKey: storageKey ?? this.storageKey,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    encryptionVersion: encryptionVersion ?? this.encryptionVersion,
    cachedAt: cachedAt ?? this.cachedAt,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
  );
  CachedReaderImage copyWithCompanion(CachedReaderImagesCompanion data) {
    return CachedReaderImage(
      userId: data.userId.present ? data.userId.value : this.userId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      storageKey:
          data.storageKey.present ? data.storageKey.value : this.storageKey,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      encryptionVersion:
          data.encryptionVersion.present
              ? data.encryptionVersion.value
              : this.encryptionVersion,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
      lastAccessedAt:
          data.lastAccessedAt.present
              ? data.lastAccessedAt.value
              : this.lastAccessedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderImage(')
          ..write('userId: $userId, ')
          ..write('itemId: $itemId, ')
          ..write('imagePath: $imagePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('storageKey: $storageKey, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    itemId,
    imagePath,
    mimeType,
    storageKey,
    sizeBytes,
    encryptionVersion,
    cachedAt,
    lastAccessedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReaderImage &&
          other.userId == this.userId &&
          other.itemId == this.itemId &&
          other.imagePath == this.imagePath &&
          other.mimeType == this.mimeType &&
          other.storageKey == this.storageKey &&
          other.sizeBytes == this.sizeBytes &&
          other.encryptionVersion == this.encryptionVersion &&
          other.cachedAt == this.cachedAt &&
          other.lastAccessedAt == this.lastAccessedAt);
}

class CachedReaderImagesCompanion extends UpdateCompanion<CachedReaderImage> {
  final Value<String> userId;
  final Value<String> itemId;
  final Value<String> imagePath;
  final Value<String> mimeType;
  final Value<String> storageKey;
  final Value<int> sizeBytes;
  final Value<int> encryptionVersion;
  final Value<DateTime> cachedAt;
  final Value<DateTime> lastAccessedAt;
  final Value<int> rowid;
  const CachedReaderImagesCompanion({
    this.userId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.storageKey = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.encryptionVersion = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReaderImagesCompanion.insert({
    required String userId,
    required String itemId,
    required String imagePath,
    this.mimeType = const Value.absent(),
    required String storageKey,
    required int sizeBytes,
    this.encryptionVersion = const Value.absent(),
    required DateTime cachedAt,
    required DateTime lastAccessedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       itemId = Value(itemId),
       imagePath = Value(imagePath),
       storageKey = Value(storageKey),
       sizeBytes = Value(sizeBytes),
       cachedAt = Value(cachedAt),
       lastAccessedAt = Value(lastAccessedAt);
  static Insertable<CachedReaderImage> custom({
    Expression<String>? userId,
    Expression<String>? itemId,
    Expression<String>? imagePath,
    Expression<String>? mimeType,
    Expression<String>? storageKey,
    Expression<int>? sizeBytes,
    Expression<int>? encryptionVersion,
    Expression<DateTime>? cachedAt,
    Expression<DateTime>? lastAccessedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (itemId != null) 'item_id': itemId,
      if (imagePath != null) 'image_path': imagePath,
      if (mimeType != null) 'mime_type': mimeType,
      if (storageKey != null) 'storage_key': storageKey,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (encryptionVersion != null) 'encryption_version': encryptionVersion,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (lastAccessedAt != null) 'last_accessed_at': lastAccessedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReaderImagesCompanion copyWith({
    Value<String>? userId,
    Value<String>? itemId,
    Value<String>? imagePath,
    Value<String>? mimeType,
    Value<String>? storageKey,
    Value<int>? sizeBytes,
    Value<int>? encryptionVersion,
    Value<DateTime>? cachedAt,
    Value<DateTime>? lastAccessedAt,
    Value<int>? rowid,
  }) {
    return CachedReaderImagesCompanion(
      userId: userId ?? this.userId,
      itemId: itemId ?? this.itemId,
      imagePath: imagePath ?? this.imagePath,
      mimeType: mimeType ?? this.mimeType,
      storageKey: storageKey ?? this.storageKey,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
      cachedAt: cachedAt ?? this.cachedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (storageKey.present) {
      map['storage_key'] = Variable<String>(storageKey.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (encryptionVersion.present) {
      map['encryption_version'] = Variable<int>(encryptionVersion.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (lastAccessedAt.present) {
      map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReaderImagesCompanion(')
          ..write('userId: $userId, ')
          ..write('itemId: $itemId, ')
          ..write('imagePath: $imagePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('storageKey: $storageKey, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppBackdropAssetsTable extends AppBackdropAssets
    with TableInfo<$AppBackdropAssetsTable, AppBackdropAssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppBackdropAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
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
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDirectoryMeta = const VerificationMeta(
    'sourceDirectory',
  );
  @override
  late final GeneratedColumn<String> sourceDirectory = GeneratedColumn<String>(
    'source_directory',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _missingMeta = const VerificationMeta(
    'missing',
  );
  @override
  late final GeneratedColumn<bool> missing = GeneratedColumn<bool>(
    'missing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("missing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('READY'),
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
    id,
    path,
    title,
    mediaType,
    sourceType,
    sourceDirectory,
    fileSize,
    modifiedAt,
    width,
    height,
    durationMs,
    thumbnailPath,
    missing,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_backdrop_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppBackdropAssetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('source_directory')) {
      context.handle(
        _sourceDirectoryMeta,
        sourceDirectory.isAcceptableOrUnknown(
          data['source_directory']!,
          _sourceDirectoryMeta,
        ),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('missing')) {
      context.handle(
        _missingMeta,
        missing.isAcceptableOrUnknown(data['missing']!, _missingMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppBackdropAssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppBackdropAssetRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      path:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}path'],
          )!,
      title:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      mediaType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}media_type'],
          )!,
      sourceType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source_type'],
          )!,
      sourceDirectory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_directory'],
      ),
      fileSize:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}file_size'],
          )!,
      modifiedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}modified_at'],
          )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      missing:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}missing'],
          )!,
      status:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}status'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $AppBackdropAssetsTable createAlias(String alias) {
    return $AppBackdropAssetsTable(attachedDatabase, alias);
  }
}

class AppBackdropAssetRow extends DataClass
    implements Insertable<AppBackdropAssetRow> {
  /// 本机背景素材 ID。
  final String id;

  /// 本机文件绝对路径。
  final String path;

  /// 展示名称。
  final String title;

  /// 媒体类型：image、gif、video。
  final String mediaType;

  /// 来源类型：file、directory。
  final String sourceType;

  /// 来源目录路径。
  final String? sourceDirectory;

  /// 文件大小，单位字节。
  final int fileSize;

  /// 文件最后修改时间。
  final DateTime modifiedAt;

  /// 图片或视频宽度，尚未解析时为空。
  final int? width;

  /// 图片或视频高度，尚未解析时为空。
  final int? height;

  /// 视频时长，单位毫秒，非视频为空。
  final int? durationMs;

  /// 本机缩略图缓存路径。
  final String? thumbnailPath;

  /// 文件是否已缺失。
  final bool missing;

  /// 服务端生命周期状态：READY / PROCESSING / FAILED；内置素材恒为 READY。
  final String status;

  /// 创建时间。
  final DateTime createdAt;

  /// 更新时间。
  final DateTime updatedAt;
  const AppBackdropAssetRow({
    required this.id,
    required this.path,
    required this.title,
    required this.mediaType,
    required this.sourceType,
    this.sourceDirectory,
    required this.fileSize,
    required this.modifiedAt,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnailPath,
    required this.missing,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['path'] = Variable<String>(path);
    map['title'] = Variable<String>(title);
    map['media_type'] = Variable<String>(mediaType);
    map['source_type'] = Variable<String>(sourceType);
    if (!nullToAbsent || sourceDirectory != null) {
      map['source_directory'] = Variable<String>(sourceDirectory);
    }
    map['file_size'] = Variable<int>(fileSize);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['missing'] = Variable<bool>(missing);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppBackdropAssetsCompanion toCompanion(bool nullToAbsent) {
    return AppBackdropAssetsCompanion(
      id: Value(id),
      path: Value(path),
      title: Value(title),
      mediaType: Value(mediaType),
      sourceType: Value(sourceType),
      sourceDirectory:
          sourceDirectory == null && nullToAbsent
              ? const Value.absent()
              : Value(sourceDirectory),
      fileSize: Value(fileSize),
      modifiedAt: Value(modifiedAt),
      width:
          width == null && nullToAbsent ? const Value.absent() : Value(width),
      height:
          height == null && nullToAbsent ? const Value.absent() : Value(height),
      durationMs:
          durationMs == null && nullToAbsent
              ? const Value.absent()
              : Value(durationMs),
      thumbnailPath:
          thumbnailPath == null && nullToAbsent
              ? const Value.absent()
              : Value(thumbnailPath),
      missing: Value(missing),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppBackdropAssetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppBackdropAssetRow(
      id: serializer.fromJson<String>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      title: serializer.fromJson<String>(json['title']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      sourceDirectory: serializer.fromJson<String?>(json['sourceDirectory']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      missing: serializer.fromJson<bool>(json['missing']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'path': serializer.toJson<String>(path),
      'title': serializer.toJson<String>(title),
      'mediaType': serializer.toJson<String>(mediaType),
      'sourceType': serializer.toJson<String>(sourceType),
      'sourceDirectory': serializer.toJson<String?>(sourceDirectory),
      'fileSize': serializer.toJson<int>(fileSize),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'missing': serializer.toJson<bool>(missing),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppBackdropAssetRow copyWith({
    String? id,
    String? path,
    String? title,
    String? mediaType,
    String? sourceType,
    Value<String?> sourceDirectory = const Value.absent(),
    int? fileSize,
    DateTime? modifiedAt,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    bool? missing,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AppBackdropAssetRow(
    id: id ?? this.id,
    path: path ?? this.path,
    title: title ?? this.title,
    mediaType: mediaType ?? this.mediaType,
    sourceType: sourceType ?? this.sourceType,
    sourceDirectory:
        sourceDirectory.present ? sourceDirectory.value : this.sourceDirectory,
    fileSize: fileSize ?? this.fileSize,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    thumbnailPath:
        thumbnailPath.present ? thumbnailPath.value : this.thumbnailPath,
    missing: missing ?? this.missing,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppBackdropAssetRow copyWithCompanion(AppBackdropAssetsCompanion data) {
    return AppBackdropAssetRow(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      title: data.title.present ? data.title.value : this.title,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      sourceType:
          data.sourceType.present ? data.sourceType.value : this.sourceType,
      sourceDirectory:
          data.sourceDirectory.present
              ? data.sourceDirectory.value
              : this.sourceDirectory,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      thumbnailPath:
          data.thumbnailPath.present
              ? data.thumbnailPath.value
              : this.thumbnailPath,
      missing: data.missing.present ? data.missing.value : this.missing,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppBackdropAssetRow(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('mediaType: $mediaType, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceDirectory: $sourceDirectory, ')
          ..write('fileSize: $fileSize, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('missing: $missing, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    path,
    title,
    mediaType,
    sourceType,
    sourceDirectory,
    fileSize,
    modifiedAt,
    width,
    height,
    durationMs,
    thumbnailPath,
    missing,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppBackdropAssetRow &&
          other.id == this.id &&
          other.path == this.path &&
          other.title == this.title &&
          other.mediaType == this.mediaType &&
          other.sourceType == this.sourceType &&
          other.sourceDirectory == this.sourceDirectory &&
          other.fileSize == this.fileSize &&
          other.modifiedAt == this.modifiedAt &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.thumbnailPath == this.thumbnailPath &&
          other.missing == this.missing &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AppBackdropAssetsCompanion extends UpdateCompanion<AppBackdropAssetRow> {
  final Value<String> id;
  final Value<String> path;
  final Value<String> title;
  final Value<String> mediaType;
  final Value<String> sourceType;
  final Value<String?> sourceDirectory;
  final Value<int> fileSize;
  final Value<DateTime> modifiedAt;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> durationMs;
  final Value<String?> thumbnailPath;
  final Value<bool> missing;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppBackdropAssetsCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.title = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceDirectory = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.missing = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppBackdropAssetsCompanion.insert({
    required String id,
    required String path,
    required String title,
    required String mediaType,
    required String sourceType,
    this.sourceDirectory = const Value.absent(),
    this.fileSize = const Value.absent(),
    required DateTime modifiedAt,
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.missing = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       path = Value(path),
       title = Value(title),
       mediaType = Value(mediaType),
       sourceType = Value(sourceType),
       modifiedAt = Value(modifiedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AppBackdropAssetRow> custom({
    Expression<String>? id,
    Expression<String>? path,
    Expression<String>? title,
    Expression<String>? mediaType,
    Expression<String>? sourceType,
    Expression<String>? sourceDirectory,
    Expression<int>? fileSize,
    Expression<DateTime>? modifiedAt,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<String>? thumbnailPath,
    Expression<bool>? missing,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (title != null) 'title': title,
      if (mediaType != null) 'media_type': mediaType,
      if (sourceType != null) 'source_type': sourceType,
      if (sourceDirectory != null) 'source_directory': sourceDirectory,
      if (fileSize != null) 'file_size': fileSize,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (missing != null) 'missing': missing,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppBackdropAssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? path,
    Value<String>? title,
    Value<String>? mediaType,
    Value<String>? sourceType,
    Value<String?>? sourceDirectory,
    Value<int>? fileSize,
    Value<DateTime>? modifiedAt,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? durationMs,
    Value<String?>? thumbnailPath,
    Value<bool>? missing,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppBackdropAssetsCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      sourceType: sourceType ?? this.sourceType,
      sourceDirectory: sourceDirectory ?? this.sourceDirectory,
      fileSize: fileSize ?? this.fileSize,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      missing: missing ?? this.missing,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (sourceDirectory.present) {
      map['source_directory'] = Variable<String>(sourceDirectory.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (missing.present) {
      map['missing'] = Variable<bool>(missing.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
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
    return (StringBuffer('AppBackdropAssetsCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('mediaType: $mediaType, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceDirectory: $sourceDirectory, ')
          ..write('fileSize: $fileSize, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('missing: $missing, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppBackdropSettingsTableTable extends AppBackdropSettingsTable
    with TableInfo<$AppBackdropSettingsTableTable, AppBackdropSettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppBackdropSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _selectedBackdropIdMeta =
      const VerificationMeta('selectedBackdropId');
  @override
  late final GeneratedColumn<String> selectedBackdropId =
      GeneratedColumn<String>(
        'selected_backdrop_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _separateDeviceBackdropsMeta =
      const VerificationMeta('separateDeviceBackdrops');
  @override
  late final GeneratedColumn<bool> separateDeviceBackdrops =
      GeneratedColumn<bool>(
        'separate_device_backdrops',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("separate_device_backdrops" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _desktopBackdropIdMeta = const VerificationMeta(
    'desktopBackdropId',
  );
  @override
  late final GeneratedColumn<String> desktopBackdropId =
      GeneratedColumn<String>(
        'desktop_backdrop_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _mobileBackdropIdMeta = const VerificationMeta(
    'mobileBackdropId',
  );
  @override
  late final GeneratedColumn<String> mobileBackdropId = GeneratedColumn<String>(
    'mobile_backdrop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fitMeta = const VerificationMeta('fit');
  @override
  late final GeneratedColumn<String> fit = GeneratedColumn<String>(
    'fit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cover'),
  );
  static const VerificationMeta _alignmentMeta = const VerificationMeta(
    'alignment',
  );
  @override
  late final GeneratedColumn<String> alignment = GeneratedColumn<String>(
    'alignment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('center'),
  );
  static const VerificationMeta _dimAmountMeta = const VerificationMeta(
    'dimAmount',
  );
  @override
  late final GeneratedColumn<double> dimAmount = GeneratedColumn<double>(
    'dim_amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.16),
  );
  static const VerificationMeta _blurAmountMeta = const VerificationMeta(
    'blurAmount',
  );
  @override
  late final GeneratedColumn<double> blurAmount = GeneratedColumn<double>(
    'blur_amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _videoMutedMeta = const VerificationMeta(
    'videoMuted',
  );
  @override
  late final GeneratedColumn<bool> videoMuted = GeneratedColumn<bool>(
    'video_muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("video_muted" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
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
    id,
    enabled,
    selectedBackdropId,
    separateDeviceBackdrops,
    desktopBackdropId,
    mobileBackdropId,
    fit,
    alignment,
    dimAmount,
    blurAmount,
    videoMuted,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_backdrop_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppBackdropSettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('selected_backdrop_id')) {
      context.handle(
        _selectedBackdropIdMeta,
        selectedBackdropId.isAcceptableOrUnknown(
          data['selected_backdrop_id']!,
          _selectedBackdropIdMeta,
        ),
      );
    }
    if (data.containsKey('separate_device_backdrops')) {
      context.handle(
        _separateDeviceBackdropsMeta,
        separateDeviceBackdrops.isAcceptableOrUnknown(
          data['separate_device_backdrops']!,
          _separateDeviceBackdropsMeta,
        ),
      );
    }
    if (data.containsKey('desktop_backdrop_id')) {
      context.handle(
        _desktopBackdropIdMeta,
        desktopBackdropId.isAcceptableOrUnknown(
          data['desktop_backdrop_id']!,
          _desktopBackdropIdMeta,
        ),
      );
    }
    if (data.containsKey('mobile_backdrop_id')) {
      context.handle(
        _mobileBackdropIdMeta,
        mobileBackdropId.isAcceptableOrUnknown(
          data['mobile_backdrop_id']!,
          _mobileBackdropIdMeta,
        ),
      );
    }
    if (data.containsKey('fit')) {
      context.handle(
        _fitMeta,
        fit.isAcceptableOrUnknown(data['fit']!, _fitMeta),
      );
    }
    if (data.containsKey('alignment')) {
      context.handle(
        _alignmentMeta,
        alignment.isAcceptableOrUnknown(data['alignment']!, _alignmentMeta),
      );
    }
    if (data.containsKey('dim_amount')) {
      context.handle(
        _dimAmountMeta,
        dimAmount.isAcceptableOrUnknown(data['dim_amount']!, _dimAmountMeta),
      );
    }
    if (data.containsKey('blur_amount')) {
      context.handle(
        _blurAmountMeta,
        blurAmount.isAcceptableOrUnknown(data['blur_amount']!, _blurAmountMeta),
      );
    }
    if (data.containsKey('video_muted')) {
      context.handle(
        _videoMutedMeta,
        videoMuted.isAcceptableOrUnknown(data['video_muted']!, _videoMutedMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppBackdropSettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppBackdropSettingRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      enabled:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}enabled'],
          )!,
      selectedBackdropId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_backdrop_id'],
      ),
      separateDeviceBackdrops:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}separate_device_backdrops'],
          )!,
      desktopBackdropId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}desktop_backdrop_id'],
      ),
      mobileBackdropId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mobile_backdrop_id'],
      ),
      fit:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}fit'],
          )!,
      alignment:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}alignment'],
          )!,
      dimAmount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}dim_amount'],
          )!,
      blurAmount:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}blur_amount'],
          )!,
      videoMuted:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}video_muted'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $AppBackdropSettingsTableTable createAlias(String alias) {
    return $AppBackdropSettingsTableTable(attachedDatabase, alias);
  }
}

class AppBackdropSettingRow extends DataClass
    implements Insertable<AppBackdropSettingRow> {
  /// 设置作用域，当前固定为 application。
  final String id;

  /// 是否启用本机背景。
  final bool enabled;

  /// 当前选中的本机背景素材 ID。
  final String? selectedBackdropId;

  /// 桌面端和移动端是否分别使用独立背景选择。
  final bool separateDeviceBackdrops;

  /// 桌面端选中的本机背景素材 ID。
  final String? desktopBackdropId;

  /// 移动端选中的本机背景素材 ID。
  final String? mobileBackdropId;

  /// 背景适配方式：cover、contain、fill。
  final String fit;

  /// cover/fill 对齐：top、center、bottom。
  final String alignment;

  /// 背景暗化强度。
  final double dimAmount;

  /// 背景模糊强度。
  final double blurAmount;

  /// 视频背景是否静音。
  final bool videoMuted;

  /// 更新时间。
  final DateTime updatedAt;
  const AppBackdropSettingRow({
    required this.id,
    required this.enabled,
    this.selectedBackdropId,
    required this.separateDeviceBackdrops,
    this.desktopBackdropId,
    this.mobileBackdropId,
    required this.fit,
    required this.alignment,
    required this.dimAmount,
    required this.blurAmount,
    required this.videoMuted,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || selectedBackdropId != null) {
      map['selected_backdrop_id'] = Variable<String>(selectedBackdropId);
    }
    map['separate_device_backdrops'] = Variable<bool>(separateDeviceBackdrops);
    if (!nullToAbsent || desktopBackdropId != null) {
      map['desktop_backdrop_id'] = Variable<String>(desktopBackdropId);
    }
    if (!nullToAbsent || mobileBackdropId != null) {
      map['mobile_backdrop_id'] = Variable<String>(mobileBackdropId);
    }
    map['fit'] = Variable<String>(fit);
    map['alignment'] = Variable<String>(alignment);
    map['dim_amount'] = Variable<double>(dimAmount);
    map['blur_amount'] = Variable<double>(blurAmount);
    map['video_muted'] = Variable<bool>(videoMuted);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppBackdropSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return AppBackdropSettingsTableCompanion(
      id: Value(id),
      enabled: Value(enabled),
      selectedBackdropId:
          selectedBackdropId == null && nullToAbsent
              ? const Value.absent()
              : Value(selectedBackdropId),
      separateDeviceBackdrops: Value(separateDeviceBackdrops),
      desktopBackdropId:
          desktopBackdropId == null && nullToAbsent
              ? const Value.absent()
              : Value(desktopBackdropId),
      mobileBackdropId:
          mobileBackdropId == null && nullToAbsent
              ? const Value.absent()
              : Value(mobileBackdropId),
      fit: Value(fit),
      alignment: Value(alignment),
      dimAmount: Value(dimAmount),
      blurAmount: Value(blurAmount),
      videoMuted: Value(videoMuted),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppBackdropSettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppBackdropSettingRow(
      id: serializer.fromJson<String>(json['id']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      selectedBackdropId: serializer.fromJson<String?>(
        json['selectedBackdropId'],
      ),
      separateDeviceBackdrops: serializer.fromJson<bool>(
        json['separateDeviceBackdrops'],
      ),
      desktopBackdropId: serializer.fromJson<String?>(
        json['desktopBackdropId'],
      ),
      mobileBackdropId: serializer.fromJson<String?>(json['mobileBackdropId']),
      fit: serializer.fromJson<String>(json['fit']),
      alignment: serializer.fromJson<String>(json['alignment']),
      dimAmount: serializer.fromJson<double>(json['dimAmount']),
      blurAmount: serializer.fromJson<double>(json['blurAmount']),
      videoMuted: serializer.fromJson<bool>(json['videoMuted']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'enabled': serializer.toJson<bool>(enabled),
      'selectedBackdropId': serializer.toJson<String?>(selectedBackdropId),
      'separateDeviceBackdrops': serializer.toJson<bool>(
        separateDeviceBackdrops,
      ),
      'desktopBackdropId': serializer.toJson<String?>(desktopBackdropId),
      'mobileBackdropId': serializer.toJson<String?>(mobileBackdropId),
      'fit': serializer.toJson<String>(fit),
      'alignment': serializer.toJson<String>(alignment),
      'dimAmount': serializer.toJson<double>(dimAmount),
      'blurAmount': serializer.toJson<double>(blurAmount),
      'videoMuted': serializer.toJson<bool>(videoMuted),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppBackdropSettingRow copyWith({
    String? id,
    bool? enabled,
    Value<String?> selectedBackdropId = const Value.absent(),
    bool? separateDeviceBackdrops,
    Value<String?> desktopBackdropId = const Value.absent(),
    Value<String?> mobileBackdropId = const Value.absent(),
    String? fit,
    String? alignment,
    double? dimAmount,
    double? blurAmount,
    bool? videoMuted,
    DateTime? updatedAt,
  }) => AppBackdropSettingRow(
    id: id ?? this.id,
    enabled: enabled ?? this.enabled,
    selectedBackdropId:
        selectedBackdropId.present
            ? selectedBackdropId.value
            : this.selectedBackdropId,
    separateDeviceBackdrops:
        separateDeviceBackdrops ?? this.separateDeviceBackdrops,
    desktopBackdropId:
        desktopBackdropId.present
            ? desktopBackdropId.value
            : this.desktopBackdropId,
    mobileBackdropId:
        mobileBackdropId.present
            ? mobileBackdropId.value
            : this.mobileBackdropId,
    fit: fit ?? this.fit,
    alignment: alignment ?? this.alignment,
    dimAmount: dimAmount ?? this.dimAmount,
    blurAmount: blurAmount ?? this.blurAmount,
    videoMuted: videoMuted ?? this.videoMuted,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppBackdropSettingRow copyWithCompanion(
    AppBackdropSettingsTableCompanion data,
  ) {
    return AppBackdropSettingRow(
      id: data.id.present ? data.id.value : this.id,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      selectedBackdropId:
          data.selectedBackdropId.present
              ? data.selectedBackdropId.value
              : this.selectedBackdropId,
      separateDeviceBackdrops:
          data.separateDeviceBackdrops.present
              ? data.separateDeviceBackdrops.value
              : this.separateDeviceBackdrops,
      desktopBackdropId:
          data.desktopBackdropId.present
              ? data.desktopBackdropId.value
              : this.desktopBackdropId,
      mobileBackdropId:
          data.mobileBackdropId.present
              ? data.mobileBackdropId.value
              : this.mobileBackdropId,
      fit: data.fit.present ? data.fit.value : this.fit,
      alignment: data.alignment.present ? data.alignment.value : this.alignment,
      dimAmount: data.dimAmount.present ? data.dimAmount.value : this.dimAmount,
      blurAmount:
          data.blurAmount.present ? data.blurAmount.value : this.blurAmount,
      videoMuted:
          data.videoMuted.present ? data.videoMuted.value : this.videoMuted,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppBackdropSettingRow(')
          ..write('id: $id, ')
          ..write('enabled: $enabled, ')
          ..write('selectedBackdropId: $selectedBackdropId, ')
          ..write('separateDeviceBackdrops: $separateDeviceBackdrops, ')
          ..write('desktopBackdropId: $desktopBackdropId, ')
          ..write('mobileBackdropId: $mobileBackdropId, ')
          ..write('fit: $fit, ')
          ..write('alignment: $alignment, ')
          ..write('dimAmount: $dimAmount, ')
          ..write('blurAmount: $blurAmount, ')
          ..write('videoMuted: $videoMuted, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    enabled,
    selectedBackdropId,
    separateDeviceBackdrops,
    desktopBackdropId,
    mobileBackdropId,
    fit,
    alignment,
    dimAmount,
    blurAmount,
    videoMuted,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppBackdropSettingRow &&
          other.id == this.id &&
          other.enabled == this.enabled &&
          other.selectedBackdropId == this.selectedBackdropId &&
          other.separateDeviceBackdrops == this.separateDeviceBackdrops &&
          other.desktopBackdropId == this.desktopBackdropId &&
          other.mobileBackdropId == this.mobileBackdropId &&
          other.fit == this.fit &&
          other.alignment == this.alignment &&
          other.dimAmount == this.dimAmount &&
          other.blurAmount == this.blurAmount &&
          other.videoMuted == this.videoMuted &&
          other.updatedAt == this.updatedAt);
}

class AppBackdropSettingsTableCompanion
    extends UpdateCompanion<AppBackdropSettingRow> {
  final Value<String> id;
  final Value<bool> enabled;
  final Value<String?> selectedBackdropId;
  final Value<bool> separateDeviceBackdrops;
  final Value<String?> desktopBackdropId;
  final Value<String?> mobileBackdropId;
  final Value<String> fit;
  final Value<String> alignment;
  final Value<double> dimAmount;
  final Value<double> blurAmount;
  final Value<bool> videoMuted;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppBackdropSettingsTableCompanion({
    this.id = const Value.absent(),
    this.enabled = const Value.absent(),
    this.selectedBackdropId = const Value.absent(),
    this.separateDeviceBackdrops = const Value.absent(),
    this.desktopBackdropId = const Value.absent(),
    this.mobileBackdropId = const Value.absent(),
    this.fit = const Value.absent(),
    this.alignment = const Value.absent(),
    this.dimAmount = const Value.absent(),
    this.blurAmount = const Value.absent(),
    this.videoMuted = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppBackdropSettingsTableCompanion.insert({
    required String id,
    this.enabled = const Value.absent(),
    this.selectedBackdropId = const Value.absent(),
    this.separateDeviceBackdrops = const Value.absent(),
    this.desktopBackdropId = const Value.absent(),
    this.mobileBackdropId = const Value.absent(),
    this.fit = const Value.absent(),
    this.alignment = const Value.absent(),
    this.dimAmount = const Value.absent(),
    this.blurAmount = const Value.absent(),
    this.videoMuted = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt);
  static Insertable<AppBackdropSettingRow> custom({
    Expression<String>? id,
    Expression<bool>? enabled,
    Expression<String>? selectedBackdropId,
    Expression<bool>? separateDeviceBackdrops,
    Expression<String>? desktopBackdropId,
    Expression<String>? mobileBackdropId,
    Expression<String>? fit,
    Expression<String>? alignment,
    Expression<double>? dimAmount,
    Expression<double>? blurAmount,
    Expression<bool>? videoMuted,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (enabled != null) 'enabled': enabled,
      if (selectedBackdropId != null)
        'selected_backdrop_id': selectedBackdropId,
      if (separateDeviceBackdrops != null)
        'separate_device_backdrops': separateDeviceBackdrops,
      if (desktopBackdropId != null) 'desktop_backdrop_id': desktopBackdropId,
      if (mobileBackdropId != null) 'mobile_backdrop_id': mobileBackdropId,
      if (fit != null) 'fit': fit,
      if (alignment != null) 'alignment': alignment,
      if (dimAmount != null) 'dim_amount': dimAmount,
      if (blurAmount != null) 'blur_amount': blurAmount,
      if (videoMuted != null) 'video_muted': videoMuted,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppBackdropSettingsTableCompanion copyWith({
    Value<String>? id,
    Value<bool>? enabled,
    Value<String?>? selectedBackdropId,
    Value<bool>? separateDeviceBackdrops,
    Value<String?>? desktopBackdropId,
    Value<String?>? mobileBackdropId,
    Value<String>? fit,
    Value<String>? alignment,
    Value<double>? dimAmount,
    Value<double>? blurAmount,
    Value<bool>? videoMuted,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppBackdropSettingsTableCompanion(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      selectedBackdropId: selectedBackdropId ?? this.selectedBackdropId,
      separateDeviceBackdrops:
          separateDeviceBackdrops ?? this.separateDeviceBackdrops,
      desktopBackdropId: desktopBackdropId ?? this.desktopBackdropId,
      mobileBackdropId: mobileBackdropId ?? this.mobileBackdropId,
      fit: fit ?? this.fit,
      alignment: alignment ?? this.alignment,
      dimAmount: dimAmount ?? this.dimAmount,
      blurAmount: blurAmount ?? this.blurAmount,
      videoMuted: videoMuted ?? this.videoMuted,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (selectedBackdropId.present) {
      map['selected_backdrop_id'] = Variable<String>(selectedBackdropId.value);
    }
    if (separateDeviceBackdrops.present) {
      map['separate_device_backdrops'] = Variable<bool>(
        separateDeviceBackdrops.value,
      );
    }
    if (desktopBackdropId.present) {
      map['desktop_backdrop_id'] = Variable<String>(desktopBackdropId.value);
    }
    if (mobileBackdropId.present) {
      map['mobile_backdrop_id'] = Variable<String>(mobileBackdropId.value);
    }
    if (fit.present) {
      map['fit'] = Variable<String>(fit.value);
    }
    if (alignment.present) {
      map['alignment'] = Variable<String>(alignment.value);
    }
    if (dimAmount.present) {
      map['dim_amount'] = Variable<double>(dimAmount.value);
    }
    if (blurAmount.present) {
      map['blur_amount'] = Variable<double>(blurAmount.value);
    }
    if (videoMuted.present) {
      map['video_muted'] = Variable<bool>(videoMuted.value);
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
    return (StringBuffer('AppBackdropSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('enabled: $enabled, ')
          ..write('selectedBackdropId: $selectedBackdropId, ')
          ..write('separateDeviceBackdrops: $separateDeviceBackdrops, ')
          ..write('desktopBackdropId: $desktopBackdropId, ')
          ..write('mobileBackdropId: $mobileBackdropId, ')
          ..write('fit: $fit, ')
          ..write('alignment: $alignment, ')
          ..write('dimAmount: $dimAmount, ')
          ..write('blurAmount: $blurAmount, ')
          ..write('videoMuted: $videoMuted, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncClientStatesTable extends SyncClientStates
    with TableInfo<$SyncClientStatesTable, SyncClientState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncClientStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverKeyMeta = const VerificationMeta(
    'serverKey',
  );
  @override
  late final GeneratedColumn<String> serverKey = GeneratedColumn<String>(
    'server_key',
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
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<int> cursor = GeneratedColumn<int>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverKey,
    userId,
    cursor,
    schemaVersion,
    lastSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_client_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncClientState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_key')) {
      context.handle(
        _serverKeyMeta,
        serverKey.isAcceptableOrUnknown(data['server_key']!, _serverKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_serverKeyMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverKey, userId};
  @override
  SyncClientState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncClientState(
      serverKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}server_key'],
          )!,
      userId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}user_id'],
          )!,
      cursor:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}cursor'],
          )!,
      schemaVersion:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}schema_version'],
          )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
    );
  }

  @override
  $SyncClientStatesTable createAlias(String alias) {
    return $SyncClientStatesTable(attachedDatabase, alias);
  }
}

class SyncClientState extends DataClass implements Insertable<SyncClientState> {
  final String serverKey;
  final String userId;
  final int cursor;
  final int schemaVersion;
  final DateTime? lastSyncAt;
  const SyncClientState({
    required this.serverKey,
    required this.userId,
    required this.cursor,
    required this.schemaVersion,
    this.lastSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_key'] = Variable<String>(serverKey);
    map['user_id'] = Variable<String>(userId);
    map['cursor'] = Variable<int>(cursor);
    map['schema_version'] = Variable<int>(schemaVersion);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    return map;
  }

  SyncClientStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncClientStatesCompanion(
      serverKey: Value(serverKey),
      userId: Value(userId),
      cursor: Value(cursor),
      schemaVersion: Value(schemaVersion),
      lastSyncAt:
          lastSyncAt == null && nullToAbsent
              ? const Value.absent()
              : Value(lastSyncAt),
    );
  }

  factory SyncClientState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncClientState(
      serverKey: serializer.fromJson<String>(json['serverKey']),
      userId: serializer.fromJson<String>(json['userId']),
      cursor: serializer.fromJson<int>(json['cursor']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverKey': serializer.toJson<String>(serverKey),
      'userId': serializer.toJson<String>(userId),
      'cursor': serializer.toJson<int>(cursor),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
    };
  }

  SyncClientState copyWith({
    String? serverKey,
    String? userId,
    int? cursor,
    int? schemaVersion,
    Value<DateTime?> lastSyncAt = const Value.absent(),
  }) => SyncClientState(
    serverKey: serverKey ?? this.serverKey,
    userId: userId ?? this.userId,
    cursor: cursor ?? this.cursor,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
  );
  SyncClientState copyWithCompanion(SyncClientStatesCompanion data) {
    return SyncClientState(
      serverKey: data.serverKey.present ? data.serverKey.value : this.serverKey,
      userId: data.userId.present ? data.userId.value : this.userId,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      schemaVersion:
          data.schemaVersion.present
              ? data.schemaVersion.value
              : this.schemaVersion,
      lastSyncAt:
          data.lastSyncAt.present ? data.lastSyncAt.value : this.lastSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncClientState(')
          ..write('serverKey: $serverKey, ')
          ..write('userId: $userId, ')
          ..write('cursor: $cursor, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(serverKey, userId, cursor, schemaVersion, lastSyncAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncClientState &&
          other.serverKey == this.serverKey &&
          other.userId == this.userId &&
          other.cursor == this.cursor &&
          other.schemaVersion == this.schemaVersion &&
          other.lastSyncAt == this.lastSyncAt);
}

class SyncClientStatesCompanion extends UpdateCompanion<SyncClientState> {
  final Value<String> serverKey;
  final Value<String> userId;
  final Value<int> cursor;
  final Value<int> schemaVersion;
  final Value<DateTime?> lastSyncAt;
  final Value<int> rowid;
  const SyncClientStatesCompanion({
    this.serverKey = const Value.absent(),
    this.userId = const Value.absent(),
    this.cursor = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncClientStatesCompanion.insert({
    required String serverKey,
    required String userId,
    this.cursor = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : serverKey = Value(serverKey),
       userId = Value(userId);
  static Insertable<SyncClientState> custom({
    Expression<String>? serverKey,
    Expression<String>? userId,
    Expression<int>? cursor,
    Expression<int>? schemaVersion,
    Expression<DateTime>? lastSyncAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverKey != null) 'server_key': serverKey,
      if (userId != null) 'user_id': userId,
      if (cursor != null) 'cursor': cursor,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncClientStatesCompanion copyWith({
    Value<String>? serverKey,
    Value<String>? userId,
    Value<int>? cursor,
    Value<int>? schemaVersion,
    Value<DateTime?>? lastSyncAt,
    Value<int>? rowid,
  }) {
    return SyncClientStatesCompanion(
      serverKey: serverKey ?? this.serverKey,
      userId: userId ?? this.userId,
      cursor: cursor ?? this.cursor,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverKey.present) {
      map['server_key'] = Variable<String>(serverKey.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<int>(cursor.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncClientStatesCompanion(')
          ..write('serverKey: $serverKey, ')
          ..write('userId: $userId, ')
          ..write('cursor: $cursor, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncPendingInvalidationsTable extends SyncPendingInvalidations
    with TableInfo<$SyncPendingInvalidationsTable, SyncPendingInvalidation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPendingInvalidationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverKeyMeta = const VerificationMeta(
    'serverKey',
  );
  @override
  late final GeneratedColumn<String> serverKey = GeneratedColumn<String>(
    'server_key',
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
  static const VerificationMeta _invalidationKeyMeta = const VerificationMeta(
    'invalidationKey',
  );
  @override
  late final GeneratedColumn<String> invalidationKey = GeneratedColumn<String>(
    'invalidation_key',
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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resourceTypeMeta = const VerificationMeta(
    'resourceType',
  );
  @override
  late final GeneratedColumn<String> resourceType = GeneratedColumn<String>(
    'resource_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resourceIdMeta = const VerificationMeta(
    'resourceId',
  );
  @override
  late final GeneratedColumn<String> resourceId = GeneratedColumn<String>(
    'resource_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  @override
  List<GeneratedColumn> get $columns => [
    serverKey,
    userId,
    invalidationKey,
    scope,
    resourceType,
    resourceId,
    revision,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pending_invalidations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncPendingInvalidation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_key')) {
      context.handle(
        _serverKeyMeta,
        serverKey.isAcceptableOrUnknown(data['server_key']!, _serverKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_serverKeyMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('invalidation_key')) {
      context.handle(
        _invalidationKeyMeta,
        invalidationKey.isAcceptableOrUnknown(
          data['invalidation_key']!,
          _invalidationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_invalidationKeyMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('resource_type')) {
      context.handle(
        _resourceTypeMeta,
        resourceType.isAcceptableOrUnknown(
          data['resource_type']!,
          _resourceTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resourceTypeMeta);
    }
    if (data.containsKey('resource_id')) {
      context.handle(
        _resourceIdMeta,
        resourceId.isAcceptableOrUnknown(data['resource_id']!, _resourceIdMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverKey, userId, invalidationKey};
  @override
  SyncPendingInvalidation map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPendingInvalidation(
      serverKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}server_key'],
          )!,
      userId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}user_id'],
          )!,
      invalidationKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}invalidation_key'],
          )!,
      scope:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}scope'],
          )!,
      resourceType:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}resource_type'],
          )!,
      resourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_id'],
      ),
      revision:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}revision'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $SyncPendingInvalidationsTable createAlias(String alias) {
    return $SyncPendingInvalidationsTable(attachedDatabase, alias);
  }
}

class SyncPendingInvalidation extends DataClass
    implements Insertable<SyncPendingInvalidation> {
  final String serverKey;
  final String userId;
  final String invalidationKey;
  final String scope;
  final String resourceType;
  final String? resourceId;
  final int revision;
  final DateTime createdAt;
  const SyncPendingInvalidation({
    required this.serverKey,
    required this.userId,
    required this.invalidationKey,
    required this.scope,
    required this.resourceType,
    this.resourceId,
    required this.revision,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_key'] = Variable<String>(serverKey);
    map['user_id'] = Variable<String>(userId);
    map['invalidation_key'] = Variable<String>(invalidationKey);
    map['scope'] = Variable<String>(scope);
    map['resource_type'] = Variable<String>(resourceType);
    if (!nullToAbsent || resourceId != null) {
      map['resource_id'] = Variable<String>(resourceId);
    }
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncPendingInvalidationsCompanion toCompanion(bool nullToAbsent) {
    return SyncPendingInvalidationsCompanion(
      serverKey: Value(serverKey),
      userId: Value(userId),
      invalidationKey: Value(invalidationKey),
      scope: Value(scope),
      resourceType: Value(resourceType),
      resourceId:
          resourceId == null && nullToAbsent
              ? const Value.absent()
              : Value(resourceId),
      revision: Value(revision),
      createdAt: Value(createdAt),
    );
  }

  factory SyncPendingInvalidation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPendingInvalidation(
      serverKey: serializer.fromJson<String>(json['serverKey']),
      userId: serializer.fromJson<String>(json['userId']),
      invalidationKey: serializer.fromJson<String>(json['invalidationKey']),
      scope: serializer.fromJson<String>(json['scope']),
      resourceType: serializer.fromJson<String>(json['resourceType']),
      resourceId: serializer.fromJson<String?>(json['resourceId']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverKey': serializer.toJson<String>(serverKey),
      'userId': serializer.toJson<String>(userId),
      'invalidationKey': serializer.toJson<String>(invalidationKey),
      'scope': serializer.toJson<String>(scope),
      'resourceType': serializer.toJson<String>(resourceType),
      'resourceId': serializer.toJson<String?>(resourceId),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncPendingInvalidation copyWith({
    String? serverKey,
    String? userId,
    String? invalidationKey,
    String? scope,
    String? resourceType,
    Value<String?> resourceId = const Value.absent(),
    int? revision,
    DateTime? createdAt,
  }) => SyncPendingInvalidation(
    serverKey: serverKey ?? this.serverKey,
    userId: userId ?? this.userId,
    invalidationKey: invalidationKey ?? this.invalidationKey,
    scope: scope ?? this.scope,
    resourceType: resourceType ?? this.resourceType,
    resourceId: resourceId.present ? resourceId.value : this.resourceId,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncPendingInvalidation copyWithCompanion(
    SyncPendingInvalidationsCompanion data,
  ) {
    return SyncPendingInvalidation(
      serverKey: data.serverKey.present ? data.serverKey.value : this.serverKey,
      userId: data.userId.present ? data.userId.value : this.userId,
      invalidationKey:
          data.invalidationKey.present
              ? data.invalidationKey.value
              : this.invalidationKey,
      scope: data.scope.present ? data.scope.value : this.scope,
      resourceType:
          data.resourceType.present
              ? data.resourceType.value
              : this.resourceType,
      resourceId:
          data.resourceId.present ? data.resourceId.value : this.resourceId,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPendingInvalidation(')
          ..write('serverKey: $serverKey, ')
          ..write('userId: $userId, ')
          ..write('invalidationKey: $invalidationKey, ')
          ..write('scope: $scope, ')
          ..write('resourceType: $resourceType, ')
          ..write('resourceId: $resourceId, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    serverKey,
    userId,
    invalidationKey,
    scope,
    resourceType,
    resourceId,
    revision,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPendingInvalidation &&
          other.serverKey == this.serverKey &&
          other.userId == this.userId &&
          other.invalidationKey == this.invalidationKey &&
          other.scope == this.scope &&
          other.resourceType == this.resourceType &&
          other.resourceId == this.resourceId &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt);
}

class SyncPendingInvalidationsCompanion
    extends UpdateCompanion<SyncPendingInvalidation> {
  final Value<String> serverKey;
  final Value<String> userId;
  final Value<String> invalidationKey;
  final Value<String> scope;
  final Value<String> resourceType;
  final Value<String?> resourceId;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SyncPendingInvalidationsCompanion({
    this.serverKey = const Value.absent(),
    this.userId = const Value.absent(),
    this.invalidationKey = const Value.absent(),
    this.scope = const Value.absent(),
    this.resourceType = const Value.absent(),
    this.resourceId = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncPendingInvalidationsCompanion.insert({
    required String serverKey,
    required String userId,
    required String invalidationKey,
    required String scope,
    required String resourceType,
    this.resourceId = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : serverKey = Value(serverKey),
       userId = Value(userId),
       invalidationKey = Value(invalidationKey),
       scope = Value(scope),
       resourceType = Value(resourceType),
       createdAt = Value(createdAt);
  static Insertable<SyncPendingInvalidation> custom({
    Expression<String>? serverKey,
    Expression<String>? userId,
    Expression<String>? invalidationKey,
    Expression<String>? scope,
    Expression<String>? resourceType,
    Expression<String>? resourceId,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverKey != null) 'server_key': serverKey,
      if (userId != null) 'user_id': userId,
      if (invalidationKey != null) 'invalidation_key': invalidationKey,
      if (scope != null) 'scope': scope,
      if (resourceType != null) 'resource_type': resourceType,
      if (resourceId != null) 'resource_id': resourceId,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncPendingInvalidationsCompanion copyWith({
    Value<String>? serverKey,
    Value<String>? userId,
    Value<String>? invalidationKey,
    Value<String>? scope,
    Value<String>? resourceType,
    Value<String?>? resourceId,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SyncPendingInvalidationsCompanion(
      serverKey: serverKey ?? this.serverKey,
      userId: userId ?? this.userId,
      invalidationKey: invalidationKey ?? this.invalidationKey,
      scope: scope ?? this.scope,
      resourceType: resourceType ?? this.resourceType,
      resourceId: resourceId ?? this.resourceId,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverKey.present) {
      map['server_key'] = Variable<String>(serverKey.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (invalidationKey.present) {
      map['invalidation_key'] = Variable<String>(invalidationKey.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (resourceType.present) {
      map['resource_type'] = Variable<String>(resourceType.value);
    }
    if (resourceId.present) {
      map['resource_id'] = Variable<String>(resourceId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPendingInvalidationsCompanion(')
          ..write('serverKey: $serverKey, ')
          ..write('userId: $userId, ')
          ..write('invalidationKey: $invalidationKey, ')
          ..write('scope: $scope, ')
          ..write('resourceType: $resourceType, ')
          ..write('resourceId: $resourceId, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncProcessedEventsTable extends SyncProcessedEvents
    with TableInfo<$SyncProcessedEventsTable, SyncProcessedEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncProcessedEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverKeyMeta = const VerificationMeta(
    'serverKey',
  );
  @override
  late final GeneratedColumn<String> serverKey = GeneratedColumn<String>(
    'server_key',
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
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceNoMeta = const VerificationMeta(
    'sequenceNo',
  );
  @override
  late final GeneratedColumn<int> sequenceNo = GeneratedColumn<int>(
    'sequence_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _processedAtMeta = const VerificationMeta(
    'processedAt',
  );
  @override
  late final GeneratedColumn<DateTime> processedAt = GeneratedColumn<DateTime>(
    'processed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverKey,
    userId,
    eventId,
    sequenceNo,
    processedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_processed_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncProcessedEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_key')) {
      context.handle(
        _serverKeyMeta,
        serverKey.isAcceptableOrUnknown(data['server_key']!, _serverKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_serverKeyMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('sequence_no')) {
      context.handle(
        _sequenceNoMeta,
        sequenceNo.isAcceptableOrUnknown(data['sequence_no']!, _sequenceNoMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceNoMeta);
    }
    if (data.containsKey('processed_at')) {
      context.handle(
        _processedAtMeta,
        processedAt.isAcceptableOrUnknown(
          data['processed_at']!,
          _processedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_processedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverKey, userId, eventId};
  @override
  SyncProcessedEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncProcessedEvent(
      serverKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}server_key'],
          )!,
      userId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}user_id'],
          )!,
      eventId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}event_id'],
          )!,
      sequenceNo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}sequence_no'],
          )!,
      processedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}processed_at'],
          )!,
    );
  }

  @override
  $SyncProcessedEventsTable createAlias(String alias) {
    return $SyncProcessedEventsTable(attachedDatabase, alias);
  }
}

class SyncProcessedEvent extends DataClass
    implements Insertable<SyncProcessedEvent> {
  final String serverKey;
  final String userId;
  final String eventId;
  final int sequenceNo;
  final DateTime processedAt;
  const SyncProcessedEvent({
    required this.serverKey,
    required this.userId,
    required this.eventId,
    required this.sequenceNo,
    required this.processedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_key'] = Variable<String>(serverKey);
    map['user_id'] = Variable<String>(userId);
    map['event_id'] = Variable<String>(eventId);
    map['sequence_no'] = Variable<int>(sequenceNo);
    map['processed_at'] = Variable<DateTime>(processedAt);
    return map;
  }

  SyncProcessedEventsCompanion toCompanion(bool nullToAbsent) {
    return SyncProcessedEventsCompanion(
      serverKey: Value(serverKey),
      userId: Value(userId),
      eventId: Value(eventId),
      sequenceNo: Value(sequenceNo),
      processedAt: Value(processedAt),
    );
  }

  factory SyncProcessedEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncProcessedEvent(
      serverKey: serializer.fromJson<String>(json['serverKey']),
      userId: serializer.fromJson<String>(json['userId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      sequenceNo: serializer.fromJson<int>(json['sequenceNo']),
      processedAt: serializer.fromJson<DateTime>(json['processedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverKey': serializer.toJson<String>(serverKey),
      'userId': serializer.toJson<String>(userId),
      'eventId': serializer.toJson<String>(eventId),
      'sequenceNo': serializer.toJson<int>(sequenceNo),
      'processedAt': serializer.toJson<DateTime>(processedAt),
    };
  }

  SyncProcessedEvent copyWith({
    String? serverKey,
    String? userId,
    String? eventId,
    int? sequenceNo,
    DateTime? processedAt,
  }) => SyncProcessedEvent(
    serverKey: serverKey ?? this.serverKey,
    userId: userId ?? this.userId,
    eventId: eventId ?? this.eventId,
    sequenceNo: sequenceNo ?? this.sequenceNo,
    processedAt: processedAt ?? this.processedAt,
  );
  SyncProcessedEvent copyWithCompanion(SyncProcessedEventsCompanion data) {
    return SyncProcessedEvent(
      serverKey: data.serverKey.present ? data.serverKey.value : this.serverKey,
      userId: data.userId.present ? data.userId.value : this.userId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      sequenceNo:
          data.sequenceNo.present ? data.sequenceNo.value : this.sequenceNo,
      processedAt:
          data.processedAt.present ? data.processedAt.value : this.processedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncProcessedEvent(')
          ..write('serverKey: $serverKey, ')
          ..write('userId: $userId, ')
          ..write('eventId: $eventId, ')
          ..write('sequenceNo: $sequenceNo, ')
          ..write('processedAt: $processedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(serverKey, userId, eventId, sequenceNo, processedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncProcessedEvent &&
          other.serverKey == this.serverKey &&
          other.userId == this.userId &&
          other.eventId == this.eventId &&
          other.sequenceNo == this.sequenceNo &&
          other.processedAt == this.processedAt);
}

class SyncProcessedEventsCompanion extends UpdateCompanion<SyncProcessedEvent> {
  final Value<String> serverKey;
  final Value<String> userId;
  final Value<String> eventId;
  final Value<int> sequenceNo;
  final Value<DateTime> processedAt;
  final Value<int> rowid;
  const SyncProcessedEventsCompanion({
    this.serverKey = const Value.absent(),
    this.userId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.sequenceNo = const Value.absent(),
    this.processedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncProcessedEventsCompanion.insert({
    required String serverKey,
    required String userId,
    required String eventId,
    required int sequenceNo,
    required DateTime processedAt,
    this.rowid = const Value.absent(),
  }) : serverKey = Value(serverKey),
       userId = Value(userId),
       eventId = Value(eventId),
       sequenceNo = Value(sequenceNo),
       processedAt = Value(processedAt);
  static Insertable<SyncProcessedEvent> custom({
    Expression<String>? serverKey,
    Expression<String>? userId,
    Expression<String>? eventId,
    Expression<int>? sequenceNo,
    Expression<DateTime>? processedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverKey != null) 'server_key': serverKey,
      if (userId != null) 'user_id': userId,
      if (eventId != null) 'event_id': eventId,
      if (sequenceNo != null) 'sequence_no': sequenceNo,
      if (processedAt != null) 'processed_at': processedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncProcessedEventsCompanion copyWith({
    Value<String>? serverKey,
    Value<String>? userId,
    Value<String>? eventId,
    Value<int>? sequenceNo,
    Value<DateTime>? processedAt,
    Value<int>? rowid,
  }) {
    return SyncProcessedEventsCompanion(
      serverKey: serverKey ?? this.serverKey,
      userId: userId ?? this.userId,
      eventId: eventId ?? this.eventId,
      sequenceNo: sequenceNo ?? this.sequenceNo,
      processedAt: processedAt ?? this.processedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverKey.present) {
      map['server_key'] = Variable<String>(serverKey.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (sequenceNo.present) {
      map['sequence_no'] = Variable<int>(sequenceNo.value);
    }
    if (processedAt.present) {
      map['processed_at'] = Variable<DateTime>(processedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncProcessedEventsCompanion(')
          ..write('serverKey: $serverKey, ')
          ..write('userId: $userId, ')
          ..write('eventId: $eventId, ')
          ..write('sequenceNo: $sequenceNo, ')
          ..write('processedAt: $processedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $CachedFilesTable cachedFiles = $CachedFilesTable(this);
  late final $SyncOperationsTable syncOperations = $SyncOperationsTable(this);
  late final $CachedMediaProgressTable cachedMediaProgress =
      $CachedMediaProgressTable(this);
  late final $CachedReaderProgressTable cachedReaderProgress =
      $CachedReaderProgressTable(this);
  late final $CachedReaderBookmarksTable cachedReaderBookmarks =
      $CachedReaderBookmarksTable(this);
  late final $CachedReaderAnnotationsTable cachedReaderAnnotations =
      $CachedReaderAnnotationsTable(this);
  late final $CachedReaderNotesTable cachedReaderNotes =
      $CachedReaderNotesTable(this);
  late final $CachedReaderBooksTable cachedReaderBooks =
      $CachedReaderBooksTable(this);
  late final $CachedReaderChaptersTable cachedReaderChapters =
      $CachedReaderChaptersTable(this);
  late final $CachedReaderBookDetailsTable cachedReaderBookDetails =
      $CachedReaderBookDetailsTable(this);
  late final $CachedReaderImagesTable cachedReaderImages =
      $CachedReaderImagesTable(this);
  late final $AppBackdropAssetsTable appBackdropAssets =
      $AppBackdropAssetsTable(this);
  late final $AppBackdropSettingsTableTable appBackdropSettingsTable =
      $AppBackdropSettingsTableTable(this);
  late final $SyncClientStatesTable syncClientStates = $SyncClientStatesTable(
    this,
  );
  late final $SyncPendingInvalidationsTable syncPendingInvalidations =
      $SyncPendingInvalidationsTable(this);
  late final $SyncProcessedEventsTable syncProcessedEvents =
      $SyncProcessedEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedFiles,
    syncOperations,
    cachedMediaProgress,
    cachedReaderProgress,
    cachedReaderBookmarks,
    cachedReaderAnnotations,
    cachedReaderNotes,
    cachedReaderBooks,
    cachedReaderChapters,
    cachedReaderBookDetails,
    cachedReaderImages,
    appBackdropAssets,
    appBackdropSettingsTable,
    syncClientStates,
    syncPendingInvalidations,
    syncProcessedEvents,
  ];
}

typedef $$CachedFilesTableCreateCompanionBuilder =
    CachedFilesCompanion Function({
      required String id,
      required String fileName,
      required int sizeBytes,
      Value<String?> mimeType,
      Value<String?> localPath,
      required DateTime cachedAt,
      Value<DateTime?> lastAccessedAt,
      Value<int> rowid,
    });
typedef $$CachedFilesTableUpdateCompanionBuilder =
    CachedFilesCompanion Function({
      Value<String> id,
      Value<String> fileName,
      Value<int> sizeBytes,
      Value<String?> mimeType,
      Value<String?> localPath,
      Value<DateTime> cachedAt,
      Value<DateTime?> lastAccessedAt,
      Value<int> rowid,
    });

class $$CachedFilesTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedFilesTable> {
  $$CachedFilesTableFilterComposer({
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

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFilesTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedFilesTable> {
  $$CachedFilesTableOrderingComposer({
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

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFilesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedFilesTable> {
  $$CachedFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => column,
  );
}

class $$CachedFilesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedFilesTable,
          CachedFile,
          $$CachedFilesTableFilterComposer,
          $$CachedFilesTableOrderingComposer,
          $$CachedFilesTableAnnotationComposer,
          $$CachedFilesTableCreateCompanionBuilder,
          $$CachedFilesTableUpdateCompanionBuilder,
          (
            CachedFile,
            BaseReferences<_$LocalDatabase, $CachedFilesTable, CachedFile>,
          ),
          CachedFile,
          PrefetchHooks Function()
        > {
  $$CachedFilesTableTableManager(_$LocalDatabase db, $CachedFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$CachedFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$CachedFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<DateTime?> lastAccessedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFilesCompanion(
                id: id,
                fileName: fileName,
                sizeBytes: sizeBytes,
                mimeType: mimeType,
                localPath: localPath,
                cachedAt: cachedAt,
                lastAccessedAt: lastAccessedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fileName,
                required int sizeBytes,
                Value<String?> mimeType = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                required DateTime cachedAt,
                Value<DateTime?> lastAccessedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFilesCompanion.insert(
                id: id,
                fileName: fileName,
                sizeBytes: sizeBytes,
                mimeType: mimeType,
                localPath: localPath,
                cachedAt: cachedAt,
                lastAccessedAt: lastAccessedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedFilesTable,
      CachedFile,
      $$CachedFilesTableFilterComposer,
      $$CachedFilesTableOrderingComposer,
      $$CachedFilesTableAnnotationComposer,
      $$CachedFilesTableCreateCompanionBuilder,
      $$CachedFilesTableUpdateCompanionBuilder,
      (
        CachedFile,
        BaseReferences<_$LocalDatabase, $CachedFilesTable, CachedFile>,
      ),
      CachedFile,
      PrefetchHooks Function()
    >;
typedef $$SyncOperationsTableCreateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<int> id,
      required String type,
      required String payload,
      Value<String> status,
      Value<int> retryCount,
      required DateTime createdAt,
      Value<DateTime?> syncedAt,
    });
typedef $$SyncOperationsTableUpdateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<int> id,
      Value<String> type,
      Value<String> payload,
      Value<String> status,
      Value<int> retryCount,
      Value<DateTime> createdAt,
      Value<DateTime?> syncedAt,
    });

class $$SyncOperationsTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOperationsTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOperationsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$SyncOperationsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SyncOperationsTable,
          SyncOperation,
          $$SyncOperationsTableFilterComposer,
          $$SyncOperationsTableOrderingComposer,
          $$SyncOperationsTableAnnotationComposer,
          $$SyncOperationsTableCreateCompanionBuilder,
          $$SyncOperationsTableUpdateCompanionBuilder,
          (
            SyncOperation,
            BaseReferences<
              _$LocalDatabase,
              $SyncOperationsTable,
              SyncOperation
            >,
          ),
          SyncOperation,
          PrefetchHooks Function()
        > {
  $$SyncOperationsTableTableManager(
    _$LocalDatabase db,
    $SyncOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SyncOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$SyncOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$SyncOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
              }) => SyncOperationsCompanion(
                id: id,
                type: type,
                payload: payload,
                status: status,
                retryCount: retryCount,
                createdAt: createdAt,
                syncedAt: syncedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String type,
                required String payload,
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> syncedAt = const Value.absent(),
              }) => SyncOperationsCompanion.insert(
                id: id,
                type: type,
                payload: payload,
                status: status,
                retryCount: retryCount,
                createdAt: createdAt,
                syncedAt: syncedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SyncOperationsTable,
      SyncOperation,
      $$SyncOperationsTableFilterComposer,
      $$SyncOperationsTableOrderingComposer,
      $$SyncOperationsTableAnnotationComposer,
      $$SyncOperationsTableCreateCompanionBuilder,
      $$SyncOperationsTableUpdateCompanionBuilder,
      (
        SyncOperation,
        BaseReferences<_$LocalDatabase, $SyncOperationsTable, SyncOperation>,
      ),
      SyncOperation,
      PrefetchHooks Function()
    >;
typedef $$CachedMediaProgressTableCreateCompanionBuilder =
    CachedMediaProgressCompanion Function({
      required String mediaId,
      required String mediaType,
      required double progressPercent,
      required int positionSeconds,
      required int durationSeconds,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedMediaProgressTableUpdateCompanionBuilder =
    CachedMediaProgressCompanion Function({
      Value<String> mediaId,
      Value<String> mediaType,
      Value<double> progressPercent,
      Value<int> positionSeconds,
      Value<int> durationSeconds,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedMediaProgressTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedMediaProgressTable> {
  $$CachedMediaProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionSeconds => $composableBuilder(
    column: $table.positionSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMediaProgressTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedMediaProgressTable> {
  $$CachedMediaProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionSeconds => $composableBuilder(
    column: $table.positionSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMediaProgressTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedMediaProgressTable> {
  $$CachedMediaProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionSeconds => $composableBuilder(
    column: $table.positionSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedMediaProgressTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedMediaProgressTable,
          CachedMediaProgressData,
          $$CachedMediaProgressTableFilterComposer,
          $$CachedMediaProgressTableOrderingComposer,
          $$CachedMediaProgressTableAnnotationComposer,
          $$CachedMediaProgressTableCreateCompanionBuilder,
          $$CachedMediaProgressTableUpdateCompanionBuilder,
          (
            CachedMediaProgressData,
            BaseReferences<
              _$LocalDatabase,
              $CachedMediaProgressTable,
              CachedMediaProgressData
            >,
          ),
          CachedMediaProgressData,
          PrefetchHooks Function()
        > {
  $$CachedMediaProgressTableTableManager(
    _$LocalDatabase db,
    $CachedMediaProgressTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedMediaProgressTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedMediaProgressTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedMediaProgressTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<double> progressPercent = const Value.absent(),
                Value<int> positionSeconds = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMediaProgressCompanion(
                mediaId: mediaId,
                mediaType: mediaType,
                progressPercent: progressPercent,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                required String mediaType,
                required double progressPercent,
                required int positionSeconds,
                required int durationSeconds,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedMediaProgressCompanion.insert(
                mediaId: mediaId,
                mediaType: mediaType,
                progressPercent: progressPercent,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMediaProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedMediaProgressTable,
      CachedMediaProgressData,
      $$CachedMediaProgressTableFilterComposer,
      $$CachedMediaProgressTableOrderingComposer,
      $$CachedMediaProgressTableAnnotationComposer,
      $$CachedMediaProgressTableCreateCompanionBuilder,
      $$CachedMediaProgressTableUpdateCompanionBuilder,
      (
        CachedMediaProgressData,
        BaseReferences<
          _$LocalDatabase,
          $CachedMediaProgressTable,
          CachedMediaProgressData
        >,
      ),
      CachedMediaProgressData,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderProgressTableCreateCompanionBuilder =
    CachedReaderProgressCompanion Function({
      required String itemId,
      Value<String> chapterId,
      Value<int> charOffset,
      Value<double> chapterProgress,
      Value<String> mode,
      Value<String?> pageId,
      Value<int?> pageIndex,
      Value<String?> pageFingerprint,
      Value<String?> sourceId,
      Value<int?> sourcePageIndex,
      Value<String?> catalogKey,
      Value<int?> manifestVersion,
      Value<double?> intraPageOffset,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedReaderProgressTableUpdateCompanionBuilder =
    CachedReaderProgressCompanion Function({
      Value<String> itemId,
      Value<String> chapterId,
      Value<int> charOffset,
      Value<double> chapterProgress,
      Value<String> mode,
      Value<String?> pageId,
      Value<int?> pageIndex,
      Value<String?> pageFingerprint,
      Value<String?> sourceId,
      Value<int?> sourcePageIndex,
      Value<String?> catalogKey,
      Value<int?> manifestVersion,
      Value<double?> intraPageOffset,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedReaderProgressTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderProgressTable> {
  $$CachedReaderProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get chapterProgress => $composableBuilder(
    column: $table.chapterProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageIndex => $composableBuilder(
    column: $table.pageIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageFingerprint => $composableBuilder(
    column: $table.pageFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourcePageIndex => $composableBuilder(
    column: $table.sourcePageIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get catalogKey => $composableBuilder(
    column: $table.catalogKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get manifestVersion => $composableBuilder(
    column: $table.manifestVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get intraPageOffset => $composableBuilder(
    column: $table.intraPageOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderProgressTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderProgressTable> {
  $$CachedReaderProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get chapterProgress => $composableBuilder(
    column: $table.chapterProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageIndex => $composableBuilder(
    column: $table.pageIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageFingerprint => $composableBuilder(
    column: $table.pageFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourcePageIndex => $composableBuilder(
    column: $table.sourcePageIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get catalogKey => $composableBuilder(
    column: $table.catalogKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get manifestVersion => $composableBuilder(
    column: $table.manifestVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get intraPageOffset => $composableBuilder(
    column: $table.intraPageOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderProgressTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderProgressTable> {
  $$CachedReaderProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<double> get chapterProgress => $composableBuilder(
    column: $table.chapterProgress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => column);

  GeneratedColumn<String> get pageFingerprint => $composableBuilder(
    column: $table.pageFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get sourcePageIndex => $composableBuilder(
    column: $table.sourcePageIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get catalogKey => $composableBuilder(
    column: $table.catalogKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get manifestVersion => $composableBuilder(
    column: $table.manifestVersion,
    builder: (column) => column,
  );

  GeneratedColumn<double> get intraPageOffset => $composableBuilder(
    column: $table.intraPageOffset,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedReaderProgressTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderProgressTable,
          CachedReaderProgressData,
          $$CachedReaderProgressTableFilterComposer,
          $$CachedReaderProgressTableOrderingComposer,
          $$CachedReaderProgressTableAnnotationComposer,
          $$CachedReaderProgressTableCreateCompanionBuilder,
          $$CachedReaderProgressTableUpdateCompanionBuilder,
          (
            CachedReaderProgressData,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderProgressTable,
              CachedReaderProgressData
            >,
          ),
          CachedReaderProgressData,
          PrefetchHooks Function()
        > {
  $$CachedReaderProgressTableTableManager(
    _$LocalDatabase db,
    $CachedReaderProgressTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderProgressTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderProgressTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderProgressTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<double> chapterProgress = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                Value<int?> pageIndex = const Value.absent(),
                Value<String?> pageFingerprint = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<int?> sourcePageIndex = const Value.absent(),
                Value<String?> catalogKey = const Value.absent(),
                Value<int?> manifestVersion = const Value.absent(),
                Value<double?> intraPageOffset = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderProgressCompanion(
                itemId: itemId,
                chapterId: chapterId,
                charOffset: charOffset,
                chapterProgress: chapterProgress,
                mode: mode,
                pageId: pageId,
                pageIndex: pageIndex,
                pageFingerprint: pageFingerprint,
                sourceId: sourceId,
                sourcePageIndex: sourcePageIndex,
                catalogKey: catalogKey,
                manifestVersion: manifestVersion,
                intraPageOffset: intraPageOffset,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                Value<String> chapterId = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<double> chapterProgress = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                Value<int?> pageIndex = const Value.absent(),
                Value<String?> pageFingerprint = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<int?> sourcePageIndex = const Value.absent(),
                Value<String?> catalogKey = const Value.absent(),
                Value<int?> manifestVersion = const Value.absent(),
                Value<double?> intraPageOffset = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderProgressCompanion.insert(
                itemId: itemId,
                chapterId: chapterId,
                charOffset: charOffset,
                chapterProgress: chapterProgress,
                mode: mode,
                pageId: pageId,
                pageIndex: pageIndex,
                pageFingerprint: pageFingerprint,
                sourceId: sourceId,
                sourcePageIndex: sourcePageIndex,
                catalogKey: catalogKey,
                manifestVersion: manifestVersion,
                intraPageOffset: intraPageOffset,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderProgressTable,
      CachedReaderProgressData,
      $$CachedReaderProgressTableFilterComposer,
      $$CachedReaderProgressTableOrderingComposer,
      $$CachedReaderProgressTableAnnotationComposer,
      $$CachedReaderProgressTableCreateCompanionBuilder,
      $$CachedReaderProgressTableUpdateCompanionBuilder,
      (
        CachedReaderProgressData,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderProgressTable,
          CachedReaderProgressData
        >,
      ),
      CachedReaderProgressData,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderBookmarksTableCreateCompanionBuilder =
    CachedReaderBookmarksCompanion Function({
      required String id,
      required String readerItemId,
      Value<int> charOffset,
      Value<double> progressPercent,
      Value<String?> note,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$CachedReaderBookmarksTableUpdateCompanionBuilder =
    CachedReaderBookmarksCompanion Function({
      Value<String> id,
      Value<String> readerItemId,
      Value<int> charOffset,
      Value<double> progressPercent,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$CachedReaderBookmarksTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderBookmarksTable> {
  $$CachedReaderBookmarksTableFilterComposer({
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

  ColumnFilters<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderBookmarksTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderBookmarksTable> {
  $$CachedReaderBookmarksTableOrderingComposer({
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

  ColumnOrderings<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderBookmarksTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderBookmarksTable> {
  $$CachedReaderBookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CachedReaderBookmarksTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderBookmarksTable,
          CachedReaderBookmark,
          $$CachedReaderBookmarksTableFilterComposer,
          $$CachedReaderBookmarksTableOrderingComposer,
          $$CachedReaderBookmarksTableAnnotationComposer,
          $$CachedReaderBookmarksTableCreateCompanionBuilder,
          $$CachedReaderBookmarksTableUpdateCompanionBuilder,
          (
            CachedReaderBookmark,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderBookmarksTable,
              CachedReaderBookmark
            >,
          ),
          CachedReaderBookmark,
          PrefetchHooks Function()
        > {
  $$CachedReaderBookmarksTableTableManager(
    _$LocalDatabase db,
    $CachedReaderBookmarksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderBookmarksTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderBookmarksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderBookmarksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> readerItemId = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<double> progressPercent = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderBookmarksCompanion(
                id: id,
                readerItemId: readerItemId,
                charOffset: charOffset,
                progressPercent: progressPercent,
                note: note,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String readerItemId,
                Value<int> charOffset = const Value.absent(),
                Value<double> progressPercent = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderBookmarksCompanion.insert(
                id: id,
                readerItemId: readerItemId,
                charOffset: charOffset,
                progressPercent: progressPercent,
                note: note,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderBookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderBookmarksTable,
      CachedReaderBookmark,
      $$CachedReaderBookmarksTableFilterComposer,
      $$CachedReaderBookmarksTableOrderingComposer,
      $$CachedReaderBookmarksTableAnnotationComposer,
      $$CachedReaderBookmarksTableCreateCompanionBuilder,
      $$CachedReaderBookmarksTableUpdateCompanionBuilder,
      (
        CachedReaderBookmark,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderBookmarksTable,
          CachedReaderBookmark
        >,
      ),
      CachedReaderBookmark,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderAnnotationsTableCreateCompanionBuilder =
    CachedReaderAnnotationsCompanion Function({
      required String id,
      required String readerItemId,
      Value<String?> chapterId,
      required int startOffset,
      required int endOffset,
      Value<String?> highlightText,
      Value<String?> note,
      Value<String> color,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$CachedReaderAnnotationsTableUpdateCompanionBuilder =
    CachedReaderAnnotationsCompanion Function({
      Value<String> id,
      Value<String> readerItemId,
      Value<String?> chapterId,
      Value<int> startOffset,
      Value<int> endOffset,
      Value<String?> highlightText,
      Value<String?> note,
      Value<String> color,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$CachedReaderAnnotationsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderAnnotationsTable> {
  $$CachedReaderAnnotationsTableFilterComposer({
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

  ColumnFilters<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startOffset => $composableBuilder(
    column: $table.startOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endOffset => $composableBuilder(
    column: $table.endOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get highlightText => $composableBuilder(
    column: $table.highlightText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderAnnotationsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderAnnotationsTable> {
  $$CachedReaderAnnotationsTableOrderingComposer({
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

  ColumnOrderings<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startOffset => $composableBuilder(
    column: $table.startOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endOffset => $composableBuilder(
    column: $table.endOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get highlightText => $composableBuilder(
    column: $table.highlightText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderAnnotationsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderAnnotationsTable> {
  $$CachedReaderAnnotationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<int> get startOffset => $composableBuilder(
    column: $table.startOffset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endOffset =>
      $composableBuilder(column: $table.endOffset, builder: (column) => column);

  GeneratedColumn<String> get highlightText => $composableBuilder(
    column: $table.highlightText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CachedReaderAnnotationsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderAnnotationsTable,
          CachedReaderAnnotation,
          $$CachedReaderAnnotationsTableFilterComposer,
          $$CachedReaderAnnotationsTableOrderingComposer,
          $$CachedReaderAnnotationsTableAnnotationComposer,
          $$CachedReaderAnnotationsTableCreateCompanionBuilder,
          $$CachedReaderAnnotationsTableUpdateCompanionBuilder,
          (
            CachedReaderAnnotation,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderAnnotationsTable,
              CachedReaderAnnotation
            >,
          ),
          CachedReaderAnnotation,
          PrefetchHooks Function()
        > {
  $$CachedReaderAnnotationsTableTableManager(
    _$LocalDatabase db,
    $CachedReaderAnnotationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderAnnotationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderAnnotationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderAnnotationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> readerItemId = const Value.absent(),
                Value<String?> chapterId = const Value.absent(),
                Value<int> startOffset = const Value.absent(),
                Value<int> endOffset = const Value.absent(),
                Value<String?> highlightText = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderAnnotationsCompanion(
                id: id,
                readerItemId: readerItemId,
                chapterId: chapterId,
                startOffset: startOffset,
                endOffset: endOffset,
                highlightText: highlightText,
                note: note,
                color: color,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String readerItemId,
                Value<String?> chapterId = const Value.absent(),
                required int startOffset,
                required int endOffset,
                Value<String?> highlightText = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> color = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderAnnotationsCompanion.insert(
                id: id,
                readerItemId: readerItemId,
                chapterId: chapterId,
                startOffset: startOffset,
                endOffset: endOffset,
                highlightText: highlightText,
                note: note,
                color: color,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderAnnotationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderAnnotationsTable,
      CachedReaderAnnotation,
      $$CachedReaderAnnotationsTableFilterComposer,
      $$CachedReaderAnnotationsTableOrderingComposer,
      $$CachedReaderAnnotationsTableAnnotationComposer,
      $$CachedReaderAnnotationsTableCreateCompanionBuilder,
      $$CachedReaderAnnotationsTableUpdateCompanionBuilder,
      (
        CachedReaderAnnotation,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderAnnotationsTable,
          CachedReaderAnnotation
        >,
      ),
      CachedReaderAnnotation,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderNotesTableCreateCompanionBuilder =
    CachedReaderNotesCompanion Function({
      required String id,
      required String readerItemId,
      Value<int?> charOffset,
      Value<String?> title,
      required String content,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$CachedReaderNotesTableUpdateCompanionBuilder =
    CachedReaderNotesCompanion Function({
      Value<String> id,
      Value<String> readerItemId,
      Value<int?> charOffset,
      Value<String?> title,
      Value<String> content,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$CachedReaderNotesTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderNotesTable> {
  $$CachedReaderNotesTableFilterComposer({
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

  ColumnFilters<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderNotesTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderNotesTable> {
  $$CachedReaderNotesTableOrderingComposer({
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

  ColumnOrderings<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderNotesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderNotesTable> {
  $$CachedReaderNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get readerItemId => $composableBuilder(
    column: $table.readerItemId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CachedReaderNotesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderNotesTable,
          CachedReaderNote,
          $$CachedReaderNotesTableFilterComposer,
          $$CachedReaderNotesTableOrderingComposer,
          $$CachedReaderNotesTableAnnotationComposer,
          $$CachedReaderNotesTableCreateCompanionBuilder,
          $$CachedReaderNotesTableUpdateCompanionBuilder,
          (
            CachedReaderNote,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderNotesTable,
              CachedReaderNote
            >,
          ),
          CachedReaderNote,
          PrefetchHooks Function()
        > {
  $$CachedReaderNotesTableTableManager(
    _$LocalDatabase db,
    $CachedReaderNotesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderNotesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderNotesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderNotesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> readerItemId = const Value.absent(),
                Value<int?> charOffset = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderNotesCompanion(
                id: id,
                readerItemId: readerItemId,
                charOffset: charOffset,
                title: title,
                content: content,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String readerItemId,
                Value<int?> charOffset = const Value.absent(),
                Value<String?> title = const Value.absent(),
                required String content,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderNotesCompanion.insert(
                id: id,
                readerItemId: readerItemId,
                charOffset: charOffset,
                title: title,
                content: content,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderNotesTable,
      CachedReaderNote,
      $$CachedReaderNotesTableFilterComposer,
      $$CachedReaderNotesTableOrderingComposer,
      $$CachedReaderNotesTableAnnotationComposer,
      $$CachedReaderNotesTableCreateCompanionBuilder,
      $$CachedReaderNotesTableUpdateCompanionBuilder,
      (
        CachedReaderNote,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderNotesTable,
          CachedReaderNote
        >,
      ),
      CachedReaderNote,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderBooksTableCreateCompanionBuilder =
    CachedReaderBooksCompanion Function({
      required String itemId,
      Value<String?> title,
      Value<String?> author,
      Value<String?> description,
      Value<String?> publisher,
      Value<String?> language,
      Value<String> chaptersJson,
      Value<int> totalChars,
      Value<String> itemType,
      Value<String> cacheVersion,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedReaderBooksTableUpdateCompanionBuilder =
    CachedReaderBooksCompanion Function({
      Value<String> itemId,
      Value<String?> title,
      Value<String?> author,
      Value<String?> description,
      Value<String?> publisher,
      Value<String?> language,
      Value<String> chaptersJson,
      Value<int> totalChars,
      Value<String> itemType,
      Value<String> cacheVersion,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedReaderBooksTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderBooksTable> {
  $$CachedReaderBooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chaptersJson => $composableBuilder(
    column: $table.chaptersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalChars => $composableBuilder(
    column: $table.totalChars,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheVersion => $composableBuilder(
    column: $table.cacheVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderBooksTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderBooksTable> {
  $$CachedReaderBooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chaptersJson => $composableBuilder(
    column: $table.chaptersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalChars => $composableBuilder(
    column: $table.totalChars,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheVersion => $composableBuilder(
    column: $table.cacheVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderBooksTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderBooksTable> {
  $$CachedReaderBooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publisher =>
      $composableBuilder(column: $table.publisher, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get chaptersJson => $composableBuilder(
    column: $table.chaptersJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalChars => $composableBuilder(
    column: $table.totalChars,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemType =>
      $composableBuilder(column: $table.itemType, builder: (column) => column);

  GeneratedColumn<String> get cacheVersion => $composableBuilder(
    column: $table.cacheVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedReaderBooksTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderBooksTable,
          CachedReaderBook,
          $$CachedReaderBooksTableFilterComposer,
          $$CachedReaderBooksTableOrderingComposer,
          $$CachedReaderBooksTableAnnotationComposer,
          $$CachedReaderBooksTableCreateCompanionBuilder,
          $$CachedReaderBooksTableUpdateCompanionBuilder,
          (
            CachedReaderBook,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderBooksTable,
              CachedReaderBook
            >,
          ),
          CachedReaderBook,
          PrefetchHooks Function()
        > {
  $$CachedReaderBooksTableTableManager(
    _$LocalDatabase db,
    $CachedReaderBooksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderBooksTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderBooksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderBooksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String> chaptersJson = const Value.absent(),
                Value<int> totalChars = const Value.absent(),
                Value<String> itemType = const Value.absent(),
                Value<String> cacheVersion = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderBooksCompanion(
                itemId: itemId,
                title: title,
                author: author,
                description: description,
                publisher: publisher,
                language: language,
                chaptersJson: chaptersJson,
                totalChars: totalChars,
                itemType: itemType,
                cacheVersion: cacheVersion,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                Value<String?> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String> chaptersJson = const Value.absent(),
                Value<int> totalChars = const Value.absent(),
                Value<String> itemType = const Value.absent(),
                Value<String> cacheVersion = const Value.absent(),
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderBooksCompanion.insert(
                itemId: itemId,
                title: title,
                author: author,
                description: description,
                publisher: publisher,
                language: language,
                chaptersJson: chaptersJson,
                totalChars: totalChars,
                itemType: itemType,
                cacheVersion: cacheVersion,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderBooksTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderBooksTable,
      CachedReaderBook,
      $$CachedReaderBooksTableFilterComposer,
      $$CachedReaderBooksTableOrderingComposer,
      $$CachedReaderBooksTableAnnotationComposer,
      $$CachedReaderBooksTableCreateCompanionBuilder,
      $$CachedReaderBooksTableUpdateCompanionBuilder,
      (
        CachedReaderBook,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderBooksTable,
          CachedReaderBook
        >,
      ),
      CachedReaderBook,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderChaptersTableCreateCompanionBuilder =
    CachedReaderChaptersCompanion Function({
      required String itemId,
      required String contentPath,
      Value<String> title,
      Value<int> chapterNumber,
      Value<int> charCount,
      required String processedHtml,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedReaderChaptersTableUpdateCompanionBuilder =
    CachedReaderChaptersCompanion Function({
      Value<String> itemId,
      Value<String> contentPath,
      Value<String> title,
      Value<int> chapterNumber,
      Value<int> charCount,
      Value<String> processedHtml,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedReaderChaptersTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderChaptersTable> {
  $$CachedReaderChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterNumber => $composableBuilder(
    column: $table.chapterNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charCount => $composableBuilder(
    column: $table.charCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processedHtml => $composableBuilder(
    column: $table.processedHtml,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderChaptersTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderChaptersTable> {
  $$CachedReaderChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterNumber => $composableBuilder(
    column: $table.chapterNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charCount => $composableBuilder(
    column: $table.charCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processedHtml => $composableBuilder(
    column: $table.processedHtml,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderChaptersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderChaptersTable> {
  $$CachedReaderChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get contentPath => $composableBuilder(
    column: $table.contentPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get chapterNumber => $composableBuilder(
    column: $table.chapterNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get charCount =>
      $composableBuilder(column: $table.charCount, builder: (column) => column);

  GeneratedColumn<String> get processedHtml => $composableBuilder(
    column: $table.processedHtml,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedReaderChaptersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderChaptersTable,
          CachedReaderChapter,
          $$CachedReaderChaptersTableFilterComposer,
          $$CachedReaderChaptersTableOrderingComposer,
          $$CachedReaderChaptersTableAnnotationComposer,
          $$CachedReaderChaptersTableCreateCompanionBuilder,
          $$CachedReaderChaptersTableUpdateCompanionBuilder,
          (
            CachedReaderChapter,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderChaptersTable,
              CachedReaderChapter
            >,
          ),
          CachedReaderChapter,
          PrefetchHooks Function()
        > {
  $$CachedReaderChaptersTableTableManager(
    _$LocalDatabase db,
    $CachedReaderChaptersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderChaptersTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderChaptersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderChaptersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<String> contentPath = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> chapterNumber = const Value.absent(),
                Value<int> charCount = const Value.absent(),
                Value<String> processedHtml = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderChaptersCompanion(
                itemId: itemId,
                contentPath: contentPath,
                title: title,
                chapterNumber: chapterNumber,
                charCount: charCount,
                processedHtml: processedHtml,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                required String contentPath,
                Value<String> title = const Value.absent(),
                Value<int> chapterNumber = const Value.absent(),
                Value<int> charCount = const Value.absent(),
                required String processedHtml,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderChaptersCompanion.insert(
                itemId: itemId,
                contentPath: contentPath,
                title: title,
                chapterNumber: chapterNumber,
                charCount: charCount,
                processedHtml: processedHtml,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderChaptersTable,
      CachedReaderChapter,
      $$CachedReaderChaptersTableFilterComposer,
      $$CachedReaderChaptersTableOrderingComposer,
      $$CachedReaderChaptersTableAnnotationComposer,
      $$CachedReaderChaptersTableCreateCompanionBuilder,
      $$CachedReaderChaptersTableUpdateCompanionBuilder,
      (
        CachedReaderChapter,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderChaptersTable,
          CachedReaderChapter
        >,
      ),
      CachedReaderChapter,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderBookDetailsTableCreateCompanionBuilder =
    CachedReaderBookDetailsCompanion Function({
      required String itemId,
      required String detailJson,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$CachedReaderBookDetailsTableUpdateCompanionBuilder =
    CachedReaderBookDetailsCompanion Function({
      Value<String> itemId,
      Value<String> detailJson,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$CachedReaderBookDetailsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderBookDetailsTable> {
  $$CachedReaderBookDetailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderBookDetailsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderBookDetailsTable> {
  $$CachedReaderBookDetailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderBookDetailsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderBookDetailsTable> {
  $$CachedReaderBookDetailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get detailJson => $composableBuilder(
    column: $table.detailJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedReaderBookDetailsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderBookDetailsTable,
          CachedReaderBookDetail,
          $$CachedReaderBookDetailsTableFilterComposer,
          $$CachedReaderBookDetailsTableOrderingComposer,
          $$CachedReaderBookDetailsTableAnnotationComposer,
          $$CachedReaderBookDetailsTableCreateCompanionBuilder,
          $$CachedReaderBookDetailsTableUpdateCompanionBuilder,
          (
            CachedReaderBookDetail,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderBookDetailsTable,
              CachedReaderBookDetail
            >,
          ),
          CachedReaderBookDetail,
          PrefetchHooks Function()
        > {
  $$CachedReaderBookDetailsTableTableManager(
    _$LocalDatabase db,
    $CachedReaderBookDetailsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderBookDetailsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderBookDetailsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderBookDetailsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<String> detailJson = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderBookDetailsCompanion(
                itemId: itemId,
                detailJson: detailJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                required String detailJson,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderBookDetailsCompanion.insert(
                itemId: itemId,
                detailJson: detailJson,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderBookDetailsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderBookDetailsTable,
      CachedReaderBookDetail,
      $$CachedReaderBookDetailsTableFilterComposer,
      $$CachedReaderBookDetailsTableOrderingComposer,
      $$CachedReaderBookDetailsTableAnnotationComposer,
      $$CachedReaderBookDetailsTableCreateCompanionBuilder,
      $$CachedReaderBookDetailsTableUpdateCompanionBuilder,
      (
        CachedReaderBookDetail,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderBookDetailsTable,
          CachedReaderBookDetail
        >,
      ),
      CachedReaderBookDetail,
      PrefetchHooks Function()
    >;
typedef $$CachedReaderImagesTableCreateCompanionBuilder =
    CachedReaderImagesCompanion Function({
      required String userId,
      required String itemId,
      required String imagePath,
      Value<String> mimeType,
      required String storageKey,
      required int sizeBytes,
      Value<int> encryptionVersion,
      required DateTime cachedAt,
      required DateTime lastAccessedAt,
      Value<int> rowid,
    });
typedef $$CachedReaderImagesTableUpdateCompanionBuilder =
    CachedReaderImagesCompanion Function({
      Value<String> userId,
      Value<String> itemId,
      Value<String> imagePath,
      Value<String> mimeType,
      Value<String> storageKey,
      Value<int> sizeBytes,
      Value<int> encryptionVersion,
      Value<DateTime> cachedAt,
      Value<DateTime> lastAccessedAt,
      Value<int> rowid,
    });

class $$CachedReaderImagesTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedReaderImagesTable> {
  $$CachedReaderImagesTableFilterComposer({
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

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedReaderImagesTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedReaderImagesTable> {
  $$CachedReaderImagesTableOrderingComposer({
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

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedReaderImagesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedReaderImagesTable> {
  $$CachedReaderImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => column,
  );
}

class $$CachedReaderImagesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedReaderImagesTable,
          CachedReaderImage,
          $$CachedReaderImagesTableFilterComposer,
          $$CachedReaderImagesTableOrderingComposer,
          $$CachedReaderImagesTableAnnotationComposer,
          $$CachedReaderImagesTableCreateCompanionBuilder,
          $$CachedReaderImagesTableUpdateCompanionBuilder,
          (
            CachedReaderImage,
            BaseReferences<
              _$LocalDatabase,
              $CachedReaderImagesTable,
              CachedReaderImage
            >,
          ),
          CachedReaderImage,
          PrefetchHooks Function()
        > {
  $$CachedReaderImagesTableTableManager(
    _$LocalDatabase db,
    $CachedReaderImagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CachedReaderImagesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$CachedReaderImagesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$CachedReaderImagesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> imagePath = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> storageKey = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> encryptionVersion = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<DateTime> lastAccessedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderImagesCompanion(
                userId: userId,
                itemId: itemId,
                imagePath: imagePath,
                mimeType: mimeType,
                storageKey: storageKey,
                sizeBytes: sizeBytes,
                encryptionVersion: encryptionVersion,
                cachedAt: cachedAt,
                lastAccessedAt: lastAccessedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String itemId,
                required String imagePath,
                Value<String> mimeType = const Value.absent(),
                required String storageKey,
                required int sizeBytes,
                Value<int> encryptionVersion = const Value.absent(),
                required DateTime cachedAt,
                required DateTime lastAccessedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedReaderImagesCompanion.insert(
                userId: userId,
                itemId: itemId,
                imagePath: imagePath,
                mimeType: mimeType,
                storageKey: storageKey,
                sizeBytes: sizeBytes,
                encryptionVersion: encryptionVersion,
                cachedAt: cachedAt,
                lastAccessedAt: lastAccessedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedReaderImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedReaderImagesTable,
      CachedReaderImage,
      $$CachedReaderImagesTableFilterComposer,
      $$CachedReaderImagesTableOrderingComposer,
      $$CachedReaderImagesTableAnnotationComposer,
      $$CachedReaderImagesTableCreateCompanionBuilder,
      $$CachedReaderImagesTableUpdateCompanionBuilder,
      (
        CachedReaderImage,
        BaseReferences<
          _$LocalDatabase,
          $CachedReaderImagesTable,
          CachedReaderImage
        >,
      ),
      CachedReaderImage,
      PrefetchHooks Function()
    >;
typedef $$AppBackdropAssetsTableCreateCompanionBuilder =
    AppBackdropAssetsCompanion Function({
      required String id,
      required String path,
      required String title,
      required String mediaType,
      required String sourceType,
      Value<String?> sourceDirectory,
      Value<int> fileSize,
      required DateTime modifiedAt,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String?> thumbnailPath,
      Value<bool> missing,
      Value<String> status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppBackdropAssetsTableUpdateCompanionBuilder =
    AppBackdropAssetsCompanion Function({
      Value<String> id,
      Value<String> path,
      Value<String> title,
      Value<String> mediaType,
      Value<String> sourceType,
      Value<String?> sourceDirectory,
      Value<int> fileSize,
      Value<DateTime> modifiedAt,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String?> thumbnailPath,
      Value<bool> missing,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppBackdropAssetsTableFilterComposer
    extends Composer<_$LocalDatabase, $AppBackdropAssetsTable> {
  $$AppBackdropAssetsTableFilterComposer({
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

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDirectory => $composableBuilder(
    column: $table.sourceDirectory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
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

class $$AppBackdropAssetsTableOrderingComposer
    extends Composer<_$LocalDatabase, $AppBackdropAssetsTable> {
  $$AppBackdropAssetsTableOrderingComposer({
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

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDirectory => $composableBuilder(
    column: $table.sourceDirectory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get missing => $composableBuilder(
    column: $table.missing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
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

class $$AppBackdropAssetsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $AppBackdropAssetsTable> {
  $$AppBackdropAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceDirectory => $composableBuilder(
    column: $table.sourceDirectory,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get missing =>
      $composableBuilder(column: $table.missing, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppBackdropAssetsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $AppBackdropAssetsTable,
          AppBackdropAssetRow,
          $$AppBackdropAssetsTableFilterComposer,
          $$AppBackdropAssetsTableOrderingComposer,
          $$AppBackdropAssetsTableAnnotationComposer,
          $$AppBackdropAssetsTableCreateCompanionBuilder,
          $$AppBackdropAssetsTableUpdateCompanionBuilder,
          (
            AppBackdropAssetRow,
            BaseReferences<
              _$LocalDatabase,
              $AppBackdropAssetsTable,
              AppBackdropAssetRow
            >,
          ),
          AppBackdropAssetRow,
          PrefetchHooks Function()
        > {
  $$AppBackdropAssetsTableTableManager(
    _$LocalDatabase db,
    $AppBackdropAssetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AppBackdropAssetsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$AppBackdropAssetsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$AppBackdropAssetsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<String?> sourceDirectory = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<bool> missing = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppBackdropAssetsCompanion(
                id: id,
                path: path,
                title: title,
                mediaType: mediaType,
                sourceType: sourceType,
                sourceDirectory: sourceDirectory,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                width: width,
                height: height,
                durationMs: durationMs,
                thumbnailPath: thumbnailPath,
                missing: missing,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String path,
                required String title,
                required String mediaType,
                required String sourceType,
                Value<String?> sourceDirectory = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                required DateTime modifiedAt,
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<bool> missing = const Value.absent(),
                Value<String> status = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppBackdropAssetsCompanion.insert(
                id: id,
                path: path,
                title: title,
                mediaType: mediaType,
                sourceType: sourceType,
                sourceDirectory: sourceDirectory,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                width: width,
                height: height,
                durationMs: durationMs,
                thumbnailPath: thumbnailPath,
                missing: missing,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppBackdropAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $AppBackdropAssetsTable,
      AppBackdropAssetRow,
      $$AppBackdropAssetsTableFilterComposer,
      $$AppBackdropAssetsTableOrderingComposer,
      $$AppBackdropAssetsTableAnnotationComposer,
      $$AppBackdropAssetsTableCreateCompanionBuilder,
      $$AppBackdropAssetsTableUpdateCompanionBuilder,
      (
        AppBackdropAssetRow,
        BaseReferences<
          _$LocalDatabase,
          $AppBackdropAssetsTable,
          AppBackdropAssetRow
        >,
      ),
      AppBackdropAssetRow,
      PrefetchHooks Function()
    >;
typedef $$AppBackdropSettingsTableTableCreateCompanionBuilder =
    AppBackdropSettingsTableCompanion Function({
      required String id,
      Value<bool> enabled,
      Value<String?> selectedBackdropId,
      Value<bool> separateDeviceBackdrops,
      Value<String?> desktopBackdropId,
      Value<String?> mobileBackdropId,
      Value<String> fit,
      Value<String> alignment,
      Value<double> dimAmount,
      Value<double> blurAmount,
      Value<bool> videoMuted,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppBackdropSettingsTableTableUpdateCompanionBuilder =
    AppBackdropSettingsTableCompanion Function({
      Value<String> id,
      Value<bool> enabled,
      Value<String?> selectedBackdropId,
      Value<bool> separateDeviceBackdrops,
      Value<String?> desktopBackdropId,
      Value<String?> mobileBackdropId,
      Value<String> fit,
      Value<String> alignment,
      Value<double> dimAmount,
      Value<double> blurAmount,
      Value<bool> videoMuted,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppBackdropSettingsTableTableFilterComposer
    extends Composer<_$LocalDatabase, $AppBackdropSettingsTableTable> {
  $$AppBackdropSettingsTableTableFilterComposer({
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

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectedBackdropId => $composableBuilder(
    column: $table.selectedBackdropId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get separateDeviceBackdrops => $composableBuilder(
    column: $table.separateDeviceBackdrops,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get desktopBackdropId => $composableBuilder(
    column: $table.desktopBackdropId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mobileBackdropId => $composableBuilder(
    column: $table.mobileBackdropId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fit => $composableBuilder(
    column: $table.fit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alignment => $composableBuilder(
    column: $table.alignment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get dimAmount => $composableBuilder(
    column: $table.dimAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get blurAmount => $composableBuilder(
    column: $table.blurAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get videoMuted => $composableBuilder(
    column: $table.videoMuted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppBackdropSettingsTableTableOrderingComposer
    extends Composer<_$LocalDatabase, $AppBackdropSettingsTableTable> {
  $$AppBackdropSettingsTableTableOrderingComposer({
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

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectedBackdropId => $composableBuilder(
    column: $table.selectedBackdropId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get separateDeviceBackdrops => $composableBuilder(
    column: $table.separateDeviceBackdrops,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get desktopBackdropId => $composableBuilder(
    column: $table.desktopBackdropId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mobileBackdropId => $composableBuilder(
    column: $table.mobileBackdropId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fit => $composableBuilder(
    column: $table.fit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alignment => $composableBuilder(
    column: $table.alignment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get dimAmount => $composableBuilder(
    column: $table.dimAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get blurAmount => $composableBuilder(
    column: $table.blurAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get videoMuted => $composableBuilder(
    column: $table.videoMuted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppBackdropSettingsTableTableAnnotationComposer
    extends Composer<_$LocalDatabase, $AppBackdropSettingsTableTable> {
  $$AppBackdropSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get selectedBackdropId => $composableBuilder(
    column: $table.selectedBackdropId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get separateDeviceBackdrops => $composableBuilder(
    column: $table.separateDeviceBackdrops,
    builder: (column) => column,
  );

  GeneratedColumn<String> get desktopBackdropId => $composableBuilder(
    column: $table.desktopBackdropId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mobileBackdropId => $composableBuilder(
    column: $table.mobileBackdropId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fit =>
      $composableBuilder(column: $table.fit, builder: (column) => column);

  GeneratedColumn<String> get alignment =>
      $composableBuilder(column: $table.alignment, builder: (column) => column);

  GeneratedColumn<double> get dimAmount =>
      $composableBuilder(column: $table.dimAmount, builder: (column) => column);

  GeneratedColumn<double> get blurAmount => $composableBuilder(
    column: $table.blurAmount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get videoMuted => $composableBuilder(
    column: $table.videoMuted,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppBackdropSettingsTableTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $AppBackdropSettingsTableTable,
          AppBackdropSettingRow,
          $$AppBackdropSettingsTableTableFilterComposer,
          $$AppBackdropSettingsTableTableOrderingComposer,
          $$AppBackdropSettingsTableTableAnnotationComposer,
          $$AppBackdropSettingsTableTableCreateCompanionBuilder,
          $$AppBackdropSettingsTableTableUpdateCompanionBuilder,
          (
            AppBackdropSettingRow,
            BaseReferences<
              _$LocalDatabase,
              $AppBackdropSettingsTableTable,
              AppBackdropSettingRow
            >,
          ),
          AppBackdropSettingRow,
          PrefetchHooks Function()
        > {
  $$AppBackdropSettingsTableTableTableManager(
    _$LocalDatabase db,
    $AppBackdropSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$AppBackdropSettingsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$AppBackdropSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$AppBackdropSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String?> selectedBackdropId = const Value.absent(),
                Value<bool> separateDeviceBackdrops = const Value.absent(),
                Value<String?> desktopBackdropId = const Value.absent(),
                Value<String?> mobileBackdropId = const Value.absent(),
                Value<String> fit = const Value.absent(),
                Value<String> alignment = const Value.absent(),
                Value<double> dimAmount = const Value.absent(),
                Value<double> blurAmount = const Value.absent(),
                Value<bool> videoMuted = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppBackdropSettingsTableCompanion(
                id: id,
                enabled: enabled,
                selectedBackdropId: selectedBackdropId,
                separateDeviceBackdrops: separateDeviceBackdrops,
                desktopBackdropId: desktopBackdropId,
                mobileBackdropId: mobileBackdropId,
                fit: fit,
                alignment: alignment,
                dimAmount: dimAmount,
                blurAmount: blurAmount,
                videoMuted: videoMuted,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<bool> enabled = const Value.absent(),
                Value<String?> selectedBackdropId = const Value.absent(),
                Value<bool> separateDeviceBackdrops = const Value.absent(),
                Value<String?> desktopBackdropId = const Value.absent(),
                Value<String?> mobileBackdropId = const Value.absent(),
                Value<String> fit = const Value.absent(),
                Value<String> alignment = const Value.absent(),
                Value<double> dimAmount = const Value.absent(),
                Value<double> blurAmount = const Value.absent(),
                Value<bool> videoMuted = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppBackdropSettingsTableCompanion.insert(
                id: id,
                enabled: enabled,
                selectedBackdropId: selectedBackdropId,
                separateDeviceBackdrops: separateDeviceBackdrops,
                desktopBackdropId: desktopBackdropId,
                mobileBackdropId: mobileBackdropId,
                fit: fit,
                alignment: alignment,
                dimAmount: dimAmount,
                blurAmount: blurAmount,
                videoMuted: videoMuted,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppBackdropSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $AppBackdropSettingsTableTable,
      AppBackdropSettingRow,
      $$AppBackdropSettingsTableTableFilterComposer,
      $$AppBackdropSettingsTableTableOrderingComposer,
      $$AppBackdropSettingsTableTableAnnotationComposer,
      $$AppBackdropSettingsTableTableCreateCompanionBuilder,
      $$AppBackdropSettingsTableTableUpdateCompanionBuilder,
      (
        AppBackdropSettingRow,
        BaseReferences<
          _$LocalDatabase,
          $AppBackdropSettingsTableTable,
          AppBackdropSettingRow
        >,
      ),
      AppBackdropSettingRow,
      PrefetchHooks Function()
    >;
typedef $$SyncClientStatesTableCreateCompanionBuilder =
    SyncClientStatesCompanion Function({
      required String serverKey,
      required String userId,
      Value<int> cursor,
      Value<int> schemaVersion,
      Value<DateTime?> lastSyncAt,
      Value<int> rowid,
    });
typedef $$SyncClientStatesTableUpdateCompanionBuilder =
    SyncClientStatesCompanion Function({
      Value<String> serverKey,
      Value<String> userId,
      Value<int> cursor,
      Value<int> schemaVersion,
      Value<DateTime?> lastSyncAt,
      Value<int> rowid,
    });

class $$SyncClientStatesTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncClientStatesTable> {
  $$SyncClientStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serverKey => $composableBuilder(
    column: $table.serverKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncClientStatesTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncClientStatesTable> {
  $$SyncClientStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serverKey => $composableBuilder(
    column: $table.serverKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncClientStatesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncClientStatesTable> {
  $$SyncClientStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serverKey =>
      $composableBuilder(column: $table.serverKey, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );
}

class $$SyncClientStatesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SyncClientStatesTable,
          SyncClientState,
          $$SyncClientStatesTableFilterComposer,
          $$SyncClientStatesTableOrderingComposer,
          $$SyncClientStatesTableAnnotationComposer,
          $$SyncClientStatesTableCreateCompanionBuilder,
          $$SyncClientStatesTableUpdateCompanionBuilder,
          (
            SyncClientState,
            BaseReferences<
              _$LocalDatabase,
              $SyncClientStatesTable,
              SyncClientState
            >,
          ),
          SyncClientState,
          PrefetchHooks Function()
        > {
  $$SyncClientStatesTableTableManager(
    _$LocalDatabase db,
    $SyncClientStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$SyncClientStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$SyncClientStatesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$SyncClientStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> serverKey = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> cursor = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncClientStatesCompanion(
                serverKey: serverKey,
                userId: userId,
                cursor: cursor,
                schemaVersion: schemaVersion,
                lastSyncAt: lastSyncAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serverKey,
                required String userId,
                Value<int> cursor = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncClientStatesCompanion.insert(
                serverKey: serverKey,
                userId: userId,
                cursor: cursor,
                schemaVersion: schemaVersion,
                lastSyncAt: lastSyncAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncClientStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SyncClientStatesTable,
      SyncClientState,
      $$SyncClientStatesTableFilterComposer,
      $$SyncClientStatesTableOrderingComposer,
      $$SyncClientStatesTableAnnotationComposer,
      $$SyncClientStatesTableCreateCompanionBuilder,
      $$SyncClientStatesTableUpdateCompanionBuilder,
      (
        SyncClientState,
        BaseReferences<
          _$LocalDatabase,
          $SyncClientStatesTable,
          SyncClientState
        >,
      ),
      SyncClientState,
      PrefetchHooks Function()
    >;
typedef $$SyncPendingInvalidationsTableCreateCompanionBuilder =
    SyncPendingInvalidationsCompanion Function({
      required String serverKey,
      required String userId,
      required String invalidationKey,
      required String scope,
      required String resourceType,
      Value<String?> resourceId,
      Value<int> revision,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$SyncPendingInvalidationsTableUpdateCompanionBuilder =
    SyncPendingInvalidationsCompanion Function({
      Value<String> serverKey,
      Value<String> userId,
      Value<String> invalidationKey,
      Value<String> scope,
      Value<String> resourceType,
      Value<String?> resourceId,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SyncPendingInvalidationsTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncPendingInvalidationsTable> {
  $$SyncPendingInvalidationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serverKey => $composableBuilder(
    column: $table.serverKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invalidationKey => $composableBuilder(
    column: $table.invalidationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceType => $composableBuilder(
    column: $table.resourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncPendingInvalidationsTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncPendingInvalidationsTable> {
  $$SyncPendingInvalidationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serverKey => $composableBuilder(
    column: $table.serverKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invalidationKey => $composableBuilder(
    column: $table.invalidationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceType => $composableBuilder(
    column: $table.resourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncPendingInvalidationsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncPendingInvalidationsTable> {
  $$SyncPendingInvalidationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serverKey =>
      $composableBuilder(column: $table.serverKey, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get invalidationKey => $composableBuilder(
    column: $table.invalidationKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get resourceType => $composableBuilder(
    column: $table.resourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resourceId => $composableBuilder(
    column: $table.resourceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncPendingInvalidationsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SyncPendingInvalidationsTable,
          SyncPendingInvalidation,
          $$SyncPendingInvalidationsTableFilterComposer,
          $$SyncPendingInvalidationsTableOrderingComposer,
          $$SyncPendingInvalidationsTableAnnotationComposer,
          $$SyncPendingInvalidationsTableCreateCompanionBuilder,
          $$SyncPendingInvalidationsTableUpdateCompanionBuilder,
          (
            SyncPendingInvalidation,
            BaseReferences<
              _$LocalDatabase,
              $SyncPendingInvalidationsTable,
              SyncPendingInvalidation
            >,
          ),
          SyncPendingInvalidation,
          PrefetchHooks Function()
        > {
  $$SyncPendingInvalidationsTableTableManager(
    _$LocalDatabase db,
    $SyncPendingInvalidationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SyncPendingInvalidationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$SyncPendingInvalidationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$SyncPendingInvalidationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> serverKey = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> invalidationKey = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String> resourceType = const Value.absent(),
                Value<String?> resourceId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncPendingInvalidationsCompanion(
                serverKey: serverKey,
                userId: userId,
                invalidationKey: invalidationKey,
                scope: scope,
                resourceType: resourceType,
                resourceId: resourceId,
                revision: revision,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serverKey,
                required String userId,
                required String invalidationKey,
                required String scope,
                required String resourceType,
                Value<String?> resourceId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncPendingInvalidationsCompanion.insert(
                serverKey: serverKey,
                userId: userId,
                invalidationKey: invalidationKey,
                scope: scope,
                resourceType: resourceType,
                resourceId: resourceId,
                revision: revision,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncPendingInvalidationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SyncPendingInvalidationsTable,
      SyncPendingInvalidation,
      $$SyncPendingInvalidationsTableFilterComposer,
      $$SyncPendingInvalidationsTableOrderingComposer,
      $$SyncPendingInvalidationsTableAnnotationComposer,
      $$SyncPendingInvalidationsTableCreateCompanionBuilder,
      $$SyncPendingInvalidationsTableUpdateCompanionBuilder,
      (
        SyncPendingInvalidation,
        BaseReferences<
          _$LocalDatabase,
          $SyncPendingInvalidationsTable,
          SyncPendingInvalidation
        >,
      ),
      SyncPendingInvalidation,
      PrefetchHooks Function()
    >;
typedef $$SyncProcessedEventsTableCreateCompanionBuilder =
    SyncProcessedEventsCompanion Function({
      required String serverKey,
      required String userId,
      required String eventId,
      required int sequenceNo,
      required DateTime processedAt,
      Value<int> rowid,
    });
typedef $$SyncProcessedEventsTableUpdateCompanionBuilder =
    SyncProcessedEventsCompanion Function({
      Value<String> serverKey,
      Value<String> userId,
      Value<String> eventId,
      Value<int> sequenceNo,
      Value<DateTime> processedAt,
      Value<int> rowid,
    });

class $$SyncProcessedEventsTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncProcessedEventsTable> {
  $$SyncProcessedEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serverKey => $composableBuilder(
    column: $table.serverKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequenceNo => $composableBuilder(
    column: $table.sequenceNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncProcessedEventsTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncProcessedEventsTable> {
  $$SyncProcessedEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serverKey => $composableBuilder(
    column: $table.serverKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequenceNo => $composableBuilder(
    column: $table.sequenceNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncProcessedEventsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncProcessedEventsTable> {
  $$SyncProcessedEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serverKey =>
      $composableBuilder(column: $table.serverKey, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<int> get sequenceNo => $composableBuilder(
    column: $table.sequenceNo,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get processedAt => $composableBuilder(
    column: $table.processedAt,
    builder: (column) => column,
  );
}

class $$SyncProcessedEventsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SyncProcessedEventsTable,
          SyncProcessedEvent,
          $$SyncProcessedEventsTableFilterComposer,
          $$SyncProcessedEventsTableOrderingComposer,
          $$SyncProcessedEventsTableAnnotationComposer,
          $$SyncProcessedEventsTableCreateCompanionBuilder,
          $$SyncProcessedEventsTableUpdateCompanionBuilder,
          (
            SyncProcessedEvent,
            BaseReferences<
              _$LocalDatabase,
              $SyncProcessedEventsTable,
              SyncProcessedEvent
            >,
          ),
          SyncProcessedEvent,
          PrefetchHooks Function()
        > {
  $$SyncProcessedEventsTableTableManager(
    _$LocalDatabase db,
    $SyncProcessedEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$SyncProcessedEventsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$SyncProcessedEventsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$SyncProcessedEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> serverKey = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<int> sequenceNo = const Value.absent(),
                Value<DateTime> processedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncProcessedEventsCompanion(
                serverKey: serverKey,
                userId: userId,
                eventId: eventId,
                sequenceNo: sequenceNo,
                processedAt: processedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serverKey,
                required String userId,
                required String eventId,
                required int sequenceNo,
                required DateTime processedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncProcessedEventsCompanion.insert(
                serverKey: serverKey,
                userId: userId,
                eventId: eventId,
                sequenceNo: sequenceNo,
                processedAt: processedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncProcessedEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SyncProcessedEventsTable,
      SyncProcessedEvent,
      $$SyncProcessedEventsTableFilterComposer,
      $$SyncProcessedEventsTableOrderingComposer,
      $$SyncProcessedEventsTableAnnotationComposer,
      $$SyncProcessedEventsTableCreateCompanionBuilder,
      $$SyncProcessedEventsTableUpdateCompanionBuilder,
      (
        SyncProcessedEvent,
        BaseReferences<
          _$LocalDatabase,
          $SyncProcessedEventsTable,
          SyncProcessedEvent
        >,
      ),
      SyncProcessedEvent,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$CachedFilesTableTableManager get cachedFiles =>
      $$CachedFilesTableTableManager(_db, _db.cachedFiles);
  $$SyncOperationsTableTableManager get syncOperations =>
      $$SyncOperationsTableTableManager(_db, _db.syncOperations);
  $$CachedMediaProgressTableTableManager get cachedMediaProgress =>
      $$CachedMediaProgressTableTableManager(_db, _db.cachedMediaProgress);
  $$CachedReaderProgressTableTableManager get cachedReaderProgress =>
      $$CachedReaderProgressTableTableManager(_db, _db.cachedReaderProgress);
  $$CachedReaderBookmarksTableTableManager get cachedReaderBookmarks =>
      $$CachedReaderBookmarksTableTableManager(_db, _db.cachedReaderBookmarks);
  $$CachedReaderAnnotationsTableTableManager get cachedReaderAnnotations =>
      $$CachedReaderAnnotationsTableTableManager(
        _db,
        _db.cachedReaderAnnotations,
      );
  $$CachedReaderNotesTableTableManager get cachedReaderNotes =>
      $$CachedReaderNotesTableTableManager(_db, _db.cachedReaderNotes);
  $$CachedReaderBooksTableTableManager get cachedReaderBooks =>
      $$CachedReaderBooksTableTableManager(_db, _db.cachedReaderBooks);
  $$CachedReaderChaptersTableTableManager get cachedReaderChapters =>
      $$CachedReaderChaptersTableTableManager(_db, _db.cachedReaderChapters);
  $$CachedReaderBookDetailsTableTableManager get cachedReaderBookDetails =>
      $$CachedReaderBookDetailsTableTableManager(
        _db,
        _db.cachedReaderBookDetails,
      );
  $$CachedReaderImagesTableTableManager get cachedReaderImages =>
      $$CachedReaderImagesTableTableManager(_db, _db.cachedReaderImages);
  $$AppBackdropAssetsTableTableManager get appBackdropAssets =>
      $$AppBackdropAssetsTableTableManager(_db, _db.appBackdropAssets);
  $$AppBackdropSettingsTableTableTableManager get appBackdropSettingsTable =>
      $$AppBackdropSettingsTableTableTableManager(
        _db,
        _db.appBackdropSettingsTable,
      );
  $$SyncClientStatesTableTableManager get syncClientStates =>
      $$SyncClientStatesTableTableManager(_db, _db.syncClientStates);
  $$SyncPendingInvalidationsTableTableManager get syncPendingInvalidations =>
      $$SyncPendingInvalidationsTableTableManager(
        _db,
        _db.syncPendingInvalidations,
      );
  $$SyncProcessedEventsTableTableManager get syncProcessedEvents =>
      $$SyncProcessedEventsTableTableManager(_db, _db.syncProcessedEvents);
}
