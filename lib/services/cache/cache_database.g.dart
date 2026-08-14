// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $WorkInfoEntriesTable extends WorkInfoEntries
    with TableInfo<$WorkInfoEntriesTable, WorkInfoEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkInfoEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _workInfoJsonMeta =
      const VerificationMeta('workInfoJson');
  @override
  late final GeneratedColumn<String> workInfoJson = GeneratedColumn<String>(
      'work_info_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [sourceId, workInfoJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_info_entries';
  @override
  VerificationContext validateIntegrity(Insertable<WorkInfoEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('work_info_json')) {
      context.handle(
          _workInfoJsonMeta,
          workInfoJson.isAcceptableOrUnknown(
              data['work_info_json']!, _workInfoJsonMeta));
    } else if (isInserting) {
      context.missing(_workInfoJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  WorkInfoEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkInfoEntry(
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      workInfoJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}work_info_json'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $WorkInfoEntriesTable createAlias(String alias) {
    return $WorkInfoEntriesTable(attachedDatabase, alias);
  }
}

class WorkInfoEntry extends DataClass implements Insertable<WorkInfoEntry> {
  /// 主键：作品 sourceId，如 "RJ01619789"
  final String sourceId;

  /// 原始 API JSON 响应
  final String workInfoJson;
  final DateTime cachedAt;
  const WorkInfoEntry(
      {required this.sourceId,
      required this.workInfoJson,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['work_info_json'] = Variable<String>(workInfoJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  WorkInfoEntriesCompanion toCompanion(bool nullToAbsent) {
    return WorkInfoEntriesCompanion(
      sourceId: Value(sourceId),
      workInfoJson: Value(workInfoJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory WorkInfoEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkInfoEntry(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      workInfoJson: serializer.fromJson<String>(json['workInfoJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'workInfoJson': serializer.toJson<String>(workInfoJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  WorkInfoEntry copyWith(
          {String? sourceId, String? workInfoJson, DateTime? cachedAt}) =>
      WorkInfoEntry(
        sourceId: sourceId ?? this.sourceId,
        workInfoJson: workInfoJson ?? this.workInfoJson,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  WorkInfoEntry copyWithCompanion(WorkInfoEntriesCompanion data) {
    return WorkInfoEntry(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      workInfoJson: data.workInfoJson.present
          ? data.workInfoJson.value
          : this.workInfoJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkInfoEntry(')
          ..write('sourceId: $sourceId, ')
          ..write('workInfoJson: $workInfoJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, workInfoJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkInfoEntry &&
          other.sourceId == this.sourceId &&
          other.workInfoJson == this.workInfoJson &&
          other.cachedAt == this.cachedAt);
}

class WorkInfoEntriesCompanion extends UpdateCompanion<WorkInfoEntry> {
  final Value<String> sourceId;
  final Value<String> workInfoJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const WorkInfoEntriesCompanion({
    this.sourceId = const Value.absent(),
    this.workInfoJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkInfoEntriesCompanion.insert({
    required String sourceId,
    required String workInfoJson,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : sourceId = Value(sourceId),
        workInfoJson = Value(workInfoJson);
  static Insertable<WorkInfoEntry> custom({
    Expression<String>? sourceId,
    Expression<String>? workInfoJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (workInfoJson != null) 'work_info_json': workInfoJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkInfoEntriesCompanion copyWith(
      {Value<String>? sourceId,
      Value<String>? workInfoJson,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return WorkInfoEntriesCompanion(
      sourceId: sourceId ?? this.sourceId,
      workInfoJson: workInfoJson ?? this.workInfoJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (workInfoJson.present) {
      map['work_info_json'] = Variable<String>(workInfoJson.value);
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
    return (StringBuffer('WorkInfoEntriesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('workInfoJson: $workInfoJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TracksEntriesTable extends TracksEntries
    with TableInfo<$TracksEntriesTable, TracksEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tracksJsonMeta =
      const VerificationMeta('tracksJson');
  @override
  late final GeneratedColumn<String> tracksJson = GeneratedColumn<String>(
      'tracks_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [sourceId, tracksJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks_entries';
  @override
  VerificationContext validateIntegrity(Insertable<TracksEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('tracks_json')) {
      context.handle(
          _tracksJsonMeta,
          tracksJson.isAcceptableOrUnknown(
              data['tracks_json']!, _tracksJsonMeta));
    } else if (isInserting) {
      context.missing(_tracksJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  TracksEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TracksEntry(
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      tracksJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tracks_json'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $TracksEntriesTable createAlias(String alias) {
    return $TracksEntriesTable(attachedDatabase, alias);
  }
}

class TracksEntry extends DataClass implements Insertable<TracksEntry> {
  final String sourceId;

  /// 原始 API JSON 响应
  final String tracksJson;
  final DateTime cachedAt;
  const TracksEntry(
      {required this.sourceId,
      required this.tracksJson,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['tracks_json'] = Variable<String>(tracksJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  TracksEntriesCompanion toCompanion(bool nullToAbsent) {
    return TracksEntriesCompanion(
      sourceId: Value(sourceId),
      tracksJson: Value(tracksJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory TracksEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TracksEntry(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      tracksJson: serializer.fromJson<String>(json['tracksJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'tracksJson': serializer.toJson<String>(tracksJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  TracksEntry copyWith(
          {String? sourceId, String? tracksJson, DateTime? cachedAt}) =>
      TracksEntry(
        sourceId: sourceId ?? this.sourceId,
        tracksJson: tracksJson ?? this.tracksJson,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  TracksEntry copyWithCompanion(TracksEntriesCompanion data) {
    return TracksEntry(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      tracksJson:
          data.tracksJson.present ? data.tracksJson.value : this.tracksJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TracksEntry(')
          ..write('sourceId: $sourceId, ')
          ..write('tracksJson: $tracksJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, tracksJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TracksEntry &&
          other.sourceId == this.sourceId &&
          other.tracksJson == this.tracksJson &&
          other.cachedAt == this.cachedAt);
}

class TracksEntriesCompanion extends UpdateCompanion<TracksEntry> {
  final Value<String> sourceId;
  final Value<String> tracksJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const TracksEntriesCompanion({
    this.sourceId = const Value.absent(),
    this.tracksJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksEntriesCompanion.insert({
    required String sourceId,
    required String tracksJson,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : sourceId = Value(sourceId),
        tracksJson = Value(tracksJson);
  static Insertable<TracksEntry> custom({
    Expression<String>? sourceId,
    Expression<String>? tracksJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (tracksJson != null) 'tracks_json': tracksJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksEntriesCompanion copyWith(
      {Value<String>? sourceId,
      Value<String>? tracksJson,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return TracksEntriesCompanion(
      sourceId: sourceId ?? this.sourceId,
      tracksJson: tracksJson ?? this.tracksJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (tracksJson.present) {
      map['tracks_json'] = Variable<String>(tracksJson.value);
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
    return (StringBuffer('TracksEntriesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('tracksJson: $tracksJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CoverEntriesTable extends CoverEntries
    with TableInfo<$CoverEntriesTable, CoverEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoverEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _coverBytesMeta =
      const VerificationMeta('coverBytes');
  @override
  late final GeneratedColumn<Uint8List> coverBytes = GeneratedColumn<Uint8List>(
      'cover_bytes', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [sourceId, coverBytes, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cover_entries';
  @override
  VerificationContext validateIntegrity(Insertable<CoverEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('cover_bytes')) {
      context.handle(
          _coverBytesMeta,
          coverBytes.isAcceptableOrUnknown(
              data['cover_bytes']!, _coverBytesMeta));
    } else if (isInserting) {
      context.missing(_coverBytesMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  CoverEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoverEntry(
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      coverBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}cover_bytes'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CoverEntriesTable createAlias(String alias) {
    return $CoverEntriesTable(attachedDatabase, alias);
  }
}

class CoverEntry extends DataClass implements Insertable<CoverEntry> {
  final String sourceId;

  /// 封面图片二进制（BLOB）
  final Uint8List coverBytes;
  final DateTime cachedAt;
  const CoverEntry(
      {required this.sourceId,
      required this.coverBytes,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['cover_bytes'] = Variable<Uint8List>(coverBytes);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CoverEntriesCompanion toCompanion(bool nullToAbsent) {
    return CoverEntriesCompanion(
      sourceId: Value(sourceId),
      coverBytes: Value(coverBytes),
      cachedAt: Value(cachedAt),
    );
  }

  factory CoverEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoverEntry(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      coverBytes: serializer.fromJson<Uint8List>(json['coverBytes']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'coverBytes': serializer.toJson<Uint8List>(coverBytes),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CoverEntry copyWith(
          {String? sourceId, Uint8List? coverBytes, DateTime? cachedAt}) =>
      CoverEntry(
        sourceId: sourceId ?? this.sourceId,
        coverBytes: coverBytes ?? this.coverBytes,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CoverEntry copyWithCompanion(CoverEntriesCompanion data) {
    return CoverEntry(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      coverBytes:
          data.coverBytes.present ? data.coverBytes.value : this.coverBytes,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoverEntry(')
          ..write('sourceId: $sourceId, ')
          ..write('coverBytes: $coverBytes, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceId, $driftBlobEquality.hash(coverBytes), cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoverEntry &&
          other.sourceId == this.sourceId &&
          $driftBlobEquality.equals(other.coverBytes, this.coverBytes) &&
          other.cachedAt == this.cachedAt);
}

class CoverEntriesCompanion extends UpdateCompanion<CoverEntry> {
  final Value<String> sourceId;
  final Value<Uint8List> coverBytes;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const CoverEntriesCompanion({
    this.sourceId = const Value.absent(),
    this.coverBytes = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CoverEntriesCompanion.insert({
    required String sourceId,
    required Uint8List coverBytes,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : sourceId = Value(sourceId),
        coverBytes = Value(coverBytes);
  static Insertable<CoverEntry> custom({
    Expression<String>? sourceId,
    Expression<Uint8List>? coverBytes,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (coverBytes != null) 'cover_bytes': coverBytes,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CoverEntriesCompanion copyWith(
      {Value<String>? sourceId,
      Value<Uint8List>? coverBytes,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return CoverEntriesCompanion(
      sourceId: sourceId ?? this.sourceId,
      coverBytes: coverBytes ?? this.coverBytes,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (coverBytes.present) {
      map['cover_bytes'] = Variable<Uint8List>(coverBytes.value);
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
    return (StringBuffer('CoverEntriesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('coverBytes: $coverBytes, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $WorkInfoEntriesTable workInfoEntries =
      $WorkInfoEntriesTable(this);
  late final $TracksEntriesTable tracksEntries = $TracksEntriesTable(this);
  late final $CoverEntriesTable coverEntries = $CoverEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [workInfoEntries, tracksEntries, coverEntries];
}

typedef $$WorkInfoEntriesTableCreateCompanionBuilder = WorkInfoEntriesCompanion
    Function({
  required String sourceId,
  required String workInfoJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});
typedef $$WorkInfoEntriesTableUpdateCompanionBuilder = WorkInfoEntriesCompanion
    Function({
  Value<String> sourceId,
  Value<String> workInfoJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$WorkInfoEntriesTableFilterComposer
    extends Composer<_$CacheDatabase, $WorkInfoEntriesTable> {
  $$WorkInfoEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get workInfoJson => $composableBuilder(
      column: $table.workInfoJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$WorkInfoEntriesTableOrderingComposer
    extends Composer<_$CacheDatabase, $WorkInfoEntriesTable> {
  $$WorkInfoEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get workInfoJson => $composableBuilder(
      column: $table.workInfoJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$WorkInfoEntriesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $WorkInfoEntriesTable> {
  $$WorkInfoEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get workInfoJson => $composableBuilder(
      column: $table.workInfoJson, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$WorkInfoEntriesTableTableManager extends RootTableManager<
    _$CacheDatabase,
    $WorkInfoEntriesTable,
    WorkInfoEntry,
    $$WorkInfoEntriesTableFilterComposer,
    $$WorkInfoEntriesTableOrderingComposer,
    $$WorkInfoEntriesTableAnnotationComposer,
    $$WorkInfoEntriesTableCreateCompanionBuilder,
    $$WorkInfoEntriesTableUpdateCompanionBuilder,
    (
      WorkInfoEntry,
      BaseReferences<_$CacheDatabase, $WorkInfoEntriesTable, WorkInfoEntry>
    ),
    WorkInfoEntry,
    PrefetchHooks Function()> {
  $$WorkInfoEntriesTableTableManager(
      _$CacheDatabase db, $WorkInfoEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkInfoEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkInfoEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkInfoEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> sourceId = const Value.absent(),
            Value<String> workInfoJson = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WorkInfoEntriesCompanion(
            sourceId: sourceId,
            workInfoJson: workInfoJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String sourceId,
            required String workInfoJson,
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WorkInfoEntriesCompanion.insert(
            sourceId: sourceId,
            workInfoJson: workInfoJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WorkInfoEntriesTableProcessedTableManager = ProcessedTableManager<
    _$CacheDatabase,
    $WorkInfoEntriesTable,
    WorkInfoEntry,
    $$WorkInfoEntriesTableFilterComposer,
    $$WorkInfoEntriesTableOrderingComposer,
    $$WorkInfoEntriesTableAnnotationComposer,
    $$WorkInfoEntriesTableCreateCompanionBuilder,
    $$WorkInfoEntriesTableUpdateCompanionBuilder,
    (
      WorkInfoEntry,
      BaseReferences<_$CacheDatabase, $WorkInfoEntriesTable, WorkInfoEntry>
    ),
    WorkInfoEntry,
    PrefetchHooks Function()>;
typedef $$TracksEntriesTableCreateCompanionBuilder = TracksEntriesCompanion
    Function({
  required String sourceId,
  required String tracksJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});
typedef $$TracksEntriesTableUpdateCompanionBuilder = TracksEntriesCompanion
    Function({
  Value<String> sourceId,
  Value<String> tracksJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$TracksEntriesTableFilterComposer
    extends Composer<_$CacheDatabase, $TracksEntriesTable> {
  $$TracksEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tracksJson => $composableBuilder(
      column: $table.tracksJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$TracksEntriesTableOrderingComposer
    extends Composer<_$CacheDatabase, $TracksEntriesTable> {
  $$TracksEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tracksJson => $composableBuilder(
      column: $table.tracksJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$TracksEntriesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $TracksEntriesTable> {
  $$TracksEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get tracksJson => $composableBuilder(
      column: $table.tracksJson, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$TracksEntriesTableTableManager extends RootTableManager<
    _$CacheDatabase,
    $TracksEntriesTable,
    TracksEntry,
    $$TracksEntriesTableFilterComposer,
    $$TracksEntriesTableOrderingComposer,
    $$TracksEntriesTableAnnotationComposer,
    $$TracksEntriesTableCreateCompanionBuilder,
    $$TracksEntriesTableUpdateCompanionBuilder,
    (
      TracksEntry,
      BaseReferences<_$CacheDatabase, $TracksEntriesTable, TracksEntry>
    ),
    TracksEntry,
    PrefetchHooks Function()> {
  $$TracksEntriesTableTableManager(
      _$CacheDatabase db, $TracksEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> sourceId = const Value.absent(),
            Value<String> tracksJson = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TracksEntriesCompanion(
            sourceId: sourceId,
            tracksJson: tracksJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String sourceId,
            required String tracksJson,
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TracksEntriesCompanion.insert(
            sourceId: sourceId,
            tracksJson: tracksJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TracksEntriesTableProcessedTableManager = ProcessedTableManager<
    _$CacheDatabase,
    $TracksEntriesTable,
    TracksEntry,
    $$TracksEntriesTableFilterComposer,
    $$TracksEntriesTableOrderingComposer,
    $$TracksEntriesTableAnnotationComposer,
    $$TracksEntriesTableCreateCompanionBuilder,
    $$TracksEntriesTableUpdateCompanionBuilder,
    (
      TracksEntry,
      BaseReferences<_$CacheDatabase, $TracksEntriesTable, TracksEntry>
    ),
    TracksEntry,
    PrefetchHooks Function()>;
typedef $$CoverEntriesTableCreateCompanionBuilder = CoverEntriesCompanion
    Function({
  required String sourceId,
  required Uint8List coverBytes,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});
typedef $$CoverEntriesTableUpdateCompanionBuilder = CoverEntriesCompanion
    Function({
  Value<String> sourceId,
  Value<Uint8List> coverBytes,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$CoverEntriesTableFilterComposer
    extends Composer<_$CacheDatabase, $CoverEntriesTable> {
  $$CoverEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get coverBytes => $composableBuilder(
      column: $table.coverBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CoverEntriesTableOrderingComposer
    extends Composer<_$CacheDatabase, $CoverEntriesTable> {
  $$CoverEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get coverBytes => $composableBuilder(
      column: $table.coverBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CoverEntriesTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CoverEntriesTable> {
  $$CoverEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<Uint8List> get coverBytes => $composableBuilder(
      column: $table.coverBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CoverEntriesTableTableManager extends RootTableManager<
    _$CacheDatabase,
    $CoverEntriesTable,
    CoverEntry,
    $$CoverEntriesTableFilterComposer,
    $$CoverEntriesTableOrderingComposer,
    $$CoverEntriesTableAnnotationComposer,
    $$CoverEntriesTableCreateCompanionBuilder,
    $$CoverEntriesTableUpdateCompanionBuilder,
    (
      CoverEntry,
      BaseReferences<_$CacheDatabase, $CoverEntriesTable, CoverEntry>
    ),
    CoverEntry,
    PrefetchHooks Function()> {
  $$CoverEntriesTableTableManager(_$CacheDatabase db, $CoverEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoverEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoverEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoverEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> sourceId = const Value.absent(),
            Value<Uint8List> coverBytes = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CoverEntriesCompanion(
            sourceId: sourceId,
            coverBytes: coverBytes,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String sourceId,
            required Uint8List coverBytes,
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CoverEntriesCompanion.insert(
            sourceId: sourceId,
            coverBytes: coverBytes,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CoverEntriesTableProcessedTableManager = ProcessedTableManager<
    _$CacheDatabase,
    $CoverEntriesTable,
    CoverEntry,
    $$CoverEntriesTableFilterComposer,
    $$CoverEntriesTableOrderingComposer,
    $$CoverEntriesTableAnnotationComposer,
    $$CoverEntriesTableCreateCompanionBuilder,
    $$CoverEntriesTableUpdateCompanionBuilder,
    (
      CoverEntry,
      BaseReferences<_$CacheDatabase, $CoverEntriesTable, CoverEntry>
    ),
    CoverEntry,
    PrefetchHooks Function()>;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$WorkInfoEntriesTableTableManager get workInfoEntries =>
      $$WorkInfoEntriesTableTableManager(_db, _db.workInfoEntries);
  $$TracksEntriesTableTableManager get tracksEntries =>
      $$TracksEntriesTableTableManager(_db, _db.tracksEntries);
  $$CoverEntriesTableTableManager get coverEntries =>
      $$CoverEntriesTableTableManager(_db, _db.coverEntries);
}
