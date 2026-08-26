// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_database.dart';

// ignore_for_file: type=lint
class $LibraryWorksTable extends LibraryWorks
    with TableInfo<$LibraryWorksTable, LibraryWork> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryWorksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dlPathMeta = const VerificationMeta('dlPath');
  @override
  late final GeneratedColumn<String> dlPath = GeneratedColumn<String>(
      'dl_path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _dirNameMeta =
      const VerificationMeta('dirName');
  @override
  late final GeneratedColumn<String> dirName = GeneratedColumn<String>(
      'dir_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _cvNamesMeta =
      const VerificationMeta('cvNames');
  @override
  late final GeneratedColumn<String> cvNames = GeneratedColumn<String>(
      'cv_names', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _circleNameMeta =
      const VerificationMeta('circleName');
  @override
  late final GeneratedColumn<String> circleName = GeneratedColumn<String>(
      'circle_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _releaseDateMeta =
      const VerificationMeta('releaseDate');
  @override
  late final GeneratedColumn<String> releaseDate = GeneratedColumn<String>(
      'release_date', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _tagsJsonMeta =
      const VerificationMeta('tagsJson');
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
      'tags_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _coverUrlMeta =
      const VerificationMeta('coverUrl');
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
      'cover_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _organizedAtMeta =
      const VerificationMeta('organizedAt');
  @override
  late final GeneratedColumn<String> organizedAt = GeneratedColumn<String>(
      'organized_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceDirOverrideMeta =
      const VerificationMeta('sourceDirOverride');
  @override
  late final GeneratedColumn<String> sourceDirOverride =
      GeneratedColumn<String>('source_dir_override', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _verifyNoteMeta =
      const VerificationMeta('verifyNote');
  @override
  late final GeneratedColumn<String> verifyNote = GeneratedColumn<String>(
      'verify_note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _verifyRepairableMeta =
      const VerificationMeta('verifyRepairable');
  @override
  late final GeneratedColumn<bool> verifyRepairable = GeneratedColumn<bool>(
      'verify_repairable', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("verify_repairable" IN (0, 1))'));
  static const VerificationMeta _verifiedAtMeta =
      const VerificationMeta('verifiedAt');
  @override
  late final GeneratedColumn<DateTime> verifiedAt = GeneratedColumn<DateTime>(
      'verified_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _manuallyEditedAtMeta =
      const VerificationMeta('manuallyEditedAt');
  @override
  late final GeneratedColumn<DateTime> manuallyEditedAt =
      GeneratedColumn<DateTime>('manually_edited_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        sourceId,
        dlPath,
        dirName,
        title,
        cvNames,
        circleName,
        releaseDate,
        tagsJson,
        coverUrl,
        organizedAt,
        sourceDirOverride,
        verifyNote,
        verifyRepairable,
        verifiedAt,
        manuallyEditedAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_works';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryWork> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('dl_path')) {
      context.handle(_dlPathMeta,
          dlPath.isAcceptableOrUnknown(data['dl_path']!, _dlPathMeta));
    }
    if (data.containsKey('dir_name')) {
      context.handle(_dirNameMeta,
          dirName.isAcceptableOrUnknown(data['dir_name']!, _dirNameMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('cv_names')) {
      context.handle(_cvNamesMeta,
          cvNames.isAcceptableOrUnknown(data['cv_names']!, _cvNamesMeta));
    }
    if (data.containsKey('circle_name')) {
      context.handle(
          _circleNameMeta,
          circleName.isAcceptableOrUnknown(
              data['circle_name']!, _circleNameMeta));
    }
    if (data.containsKey('release_date')) {
      context.handle(
          _releaseDateMeta,
          releaseDate.isAcceptableOrUnknown(
              data['release_date']!, _releaseDateMeta));
    }
    if (data.containsKey('tags_json')) {
      context.handle(_tagsJsonMeta,
          tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta));
    }
    if (data.containsKey('cover_url')) {
      context.handle(_coverUrlMeta,
          coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta));
    }
    if (data.containsKey('organized_at')) {
      context.handle(
          _organizedAtMeta,
          organizedAt.isAcceptableOrUnknown(
              data['organized_at']!, _organizedAtMeta));
    }
    if (data.containsKey('source_dir_override')) {
      context.handle(
          _sourceDirOverrideMeta,
          sourceDirOverride.isAcceptableOrUnknown(
              data['source_dir_override']!, _sourceDirOverrideMeta));
    }
    if (data.containsKey('verify_note')) {
      context.handle(
          _verifyNoteMeta,
          verifyNote.isAcceptableOrUnknown(
              data['verify_note']!, _verifyNoteMeta));
    }
    if (data.containsKey('verify_repairable')) {
      context.handle(
          _verifyRepairableMeta,
          verifyRepairable.isAcceptableOrUnknown(
              data['verify_repairable']!, _verifyRepairableMeta));
    }
    if (data.containsKey('verified_at')) {
      context.handle(
          _verifiedAtMeta,
          verifiedAt.isAcceptableOrUnknown(
              data['verified_at']!, _verifiedAtMeta));
    }
    if (data.containsKey('manually_edited_at')) {
      context.handle(
          _manuallyEditedAtMeta,
          manuallyEditedAt.isAcceptableOrUnknown(
              data['manually_edited_at']!, _manuallyEditedAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  LibraryWork map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryWork(
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      dlPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}dl_path'])!,
      dirName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}dir_name'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      cvNames: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cv_names'])!,
      circleName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}circle_name'])!,
      releaseDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}release_date'])!,
      tagsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags_json'])!,
      coverUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cover_url'])!,
      organizedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}organized_at']),
      sourceDirOverride: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}source_dir_override']),
      verifyNote: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}verify_note']),
      verifyRepairable: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}verify_repairable']),
      verifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}verified_at']),
      manuallyEditedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}manually_edited_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LibraryWorksTable createAlias(String alias) {
    return $LibraryWorksTable(attachedDatabase, alias);
  }
}

class LibraryWork extends DataClass implements Insertable<LibraryWork> {
  final String sourceId;
  final String dlPath;
  final String dirName;
  final String title;
  final String cvNames;
  final String circleName;
  final String releaseDate;
  final String tagsJson;
  final String coverUrl;
  final String? organizedAt;

  /// 显式作品目录路径（扁平外部导入等无法按 {dlPath}/{dirName}/{sourceId}
  /// 重建的目录），null = 空串（按标准结构重建）。
  final String? sourceDirOverride;

  /// 最近一次校验结果摘要（如「3 首缺内嵌歌词、封面缺失」），null = 无缺陷。
  final String? verifyNote;

  /// 缺陷是否可通过重新整理修复（重跑 organizeEntry forceWavRewrite）。
  final bool? verifyRepairable;

  /// 最近一次校验时间，null = 从未校验。
  final DateTime? verifiedAt;

  /// 最近一次手动编辑元数据的时间，null = 未手动编辑过。
  ///
  /// 非 null 时整理以注册表手动值为准（标题/CV/社团/发行日期/标签），
  /// 不再被在线 workInfo 覆盖。
  final DateTime? manuallyEditedAt;
  final DateTime updatedAt;
  const LibraryWork(
      {required this.sourceId,
      required this.dlPath,
      required this.dirName,
      required this.title,
      required this.cvNames,
      required this.circleName,
      required this.releaseDate,
      required this.tagsJson,
      required this.coverUrl,
      this.organizedAt,
      this.sourceDirOverride,
      this.verifyNote,
      this.verifyRepairable,
      this.verifiedAt,
      this.manuallyEditedAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['dl_path'] = Variable<String>(dlPath);
    map['dir_name'] = Variable<String>(dirName);
    map['title'] = Variable<String>(title);
    map['cv_names'] = Variable<String>(cvNames);
    map['circle_name'] = Variable<String>(circleName);
    map['release_date'] = Variable<String>(releaseDate);
    map['tags_json'] = Variable<String>(tagsJson);
    map['cover_url'] = Variable<String>(coverUrl);
    if (!nullToAbsent || organizedAt != null) {
      map['organized_at'] = Variable<String>(organizedAt);
    }
    if (!nullToAbsent || sourceDirOverride != null) {
      map['source_dir_override'] = Variable<String>(sourceDirOverride);
    }
    if (!nullToAbsent || verifyNote != null) {
      map['verify_note'] = Variable<String>(verifyNote);
    }
    if (!nullToAbsent || verifyRepairable != null) {
      map['verify_repairable'] = Variable<bool>(verifyRepairable);
    }
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<DateTime>(verifiedAt);
    }
    if (!nullToAbsent || manuallyEditedAt != null) {
      map['manually_edited_at'] = Variable<DateTime>(manuallyEditedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LibraryWorksCompanion toCompanion(bool nullToAbsent) {
    return LibraryWorksCompanion(
      sourceId: Value(sourceId),
      dlPath: Value(dlPath),
      dirName: Value(dirName),
      title: Value(title),
      cvNames: Value(cvNames),
      circleName: Value(circleName),
      releaseDate: Value(releaseDate),
      tagsJson: Value(tagsJson),
      coverUrl: Value(coverUrl),
      organizedAt: organizedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(organizedAt),
      sourceDirOverride: sourceDirOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDirOverride),
      verifyNote: verifyNote == null && nullToAbsent
          ? const Value.absent()
          : Value(verifyNote),
      verifyRepairable: verifyRepairable == null && nullToAbsent
          ? const Value.absent()
          : Value(verifyRepairable),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
      manuallyEditedAt: manuallyEditedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(manuallyEditedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LibraryWork.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryWork(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      dlPath: serializer.fromJson<String>(json['dlPath']),
      dirName: serializer.fromJson<String>(json['dirName']),
      title: serializer.fromJson<String>(json['title']),
      cvNames: serializer.fromJson<String>(json['cvNames']),
      circleName: serializer.fromJson<String>(json['circleName']),
      releaseDate: serializer.fromJson<String>(json['releaseDate']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      coverUrl: serializer.fromJson<String>(json['coverUrl']),
      organizedAt: serializer.fromJson<String?>(json['organizedAt']),
      sourceDirOverride:
          serializer.fromJson<String?>(json['sourceDirOverride']),
      verifyNote: serializer.fromJson<String?>(json['verifyNote']),
      verifyRepairable: serializer.fromJson<bool?>(json['verifyRepairable']),
      verifiedAt: serializer.fromJson<DateTime?>(json['verifiedAt']),
      manuallyEditedAt:
          serializer.fromJson<DateTime?>(json['manuallyEditedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'dlPath': serializer.toJson<String>(dlPath),
      'dirName': serializer.toJson<String>(dirName),
      'title': serializer.toJson<String>(title),
      'cvNames': serializer.toJson<String>(cvNames),
      'circleName': serializer.toJson<String>(circleName),
      'releaseDate': serializer.toJson<String>(releaseDate),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'coverUrl': serializer.toJson<String>(coverUrl),
      'organizedAt': serializer.toJson<String?>(organizedAt),
      'sourceDirOverride': serializer.toJson<String?>(sourceDirOverride),
      'verifyNote': serializer.toJson<String?>(verifyNote),
      'verifyRepairable': serializer.toJson<bool?>(verifyRepairable),
      'verifiedAt': serializer.toJson<DateTime?>(verifiedAt),
      'manuallyEditedAt': serializer.toJson<DateTime?>(manuallyEditedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LibraryWork copyWith(
          {String? sourceId,
          String? dlPath,
          String? dirName,
          String? title,
          String? cvNames,
          String? circleName,
          String? releaseDate,
          String? tagsJson,
          String? coverUrl,
          Value<String?> organizedAt = const Value.absent(),
          Value<String?> sourceDirOverride = const Value.absent(),
          Value<String?> verifyNote = const Value.absent(),
          Value<bool?> verifyRepairable = const Value.absent(),
          Value<DateTime?> verifiedAt = const Value.absent(),
          Value<DateTime?> manuallyEditedAt = const Value.absent(),
          DateTime? updatedAt}) =>
      LibraryWork(
        sourceId: sourceId ?? this.sourceId,
        dlPath: dlPath ?? this.dlPath,
        dirName: dirName ?? this.dirName,
        title: title ?? this.title,
        cvNames: cvNames ?? this.cvNames,
        circleName: circleName ?? this.circleName,
        releaseDate: releaseDate ?? this.releaseDate,
        tagsJson: tagsJson ?? this.tagsJson,
        coverUrl: coverUrl ?? this.coverUrl,
        organizedAt: organizedAt.present ? organizedAt.value : this.organizedAt,
        sourceDirOverride: sourceDirOverride.present
            ? sourceDirOverride.value
            : this.sourceDirOverride,
        verifyNote: verifyNote.present ? verifyNote.value : this.verifyNote,
        verifyRepairable: verifyRepairable.present
            ? verifyRepairable.value
            : this.verifyRepairable,
        verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
        manuallyEditedAt: manuallyEditedAt.present
            ? manuallyEditedAt.value
            : this.manuallyEditedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LibraryWork copyWithCompanion(LibraryWorksCompanion data) {
    return LibraryWork(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      dlPath: data.dlPath.present ? data.dlPath.value : this.dlPath,
      dirName: data.dirName.present ? data.dirName.value : this.dirName,
      title: data.title.present ? data.title.value : this.title,
      cvNames: data.cvNames.present ? data.cvNames.value : this.cvNames,
      circleName:
          data.circleName.present ? data.circleName.value : this.circleName,
      releaseDate:
          data.releaseDate.present ? data.releaseDate.value : this.releaseDate,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      organizedAt:
          data.organizedAt.present ? data.organizedAt.value : this.organizedAt,
      sourceDirOverride: data.sourceDirOverride.present
          ? data.sourceDirOverride.value
          : this.sourceDirOverride,
      verifyNote:
          data.verifyNote.present ? data.verifyNote.value : this.verifyNote,
      verifyRepairable: data.verifyRepairable.present
          ? data.verifyRepairable.value
          : this.verifyRepairable,
      verifiedAt:
          data.verifiedAt.present ? data.verifiedAt.value : this.verifiedAt,
      manuallyEditedAt: data.manuallyEditedAt.present
          ? data.manuallyEditedAt.value
          : this.manuallyEditedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryWork(')
          ..write('sourceId: $sourceId, ')
          ..write('dlPath: $dlPath, ')
          ..write('dirName: $dirName, ')
          ..write('title: $title, ')
          ..write('cvNames: $cvNames, ')
          ..write('circleName: $circleName, ')
          ..write('releaseDate: $releaseDate, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('organizedAt: $organizedAt, ')
          ..write('sourceDirOverride: $sourceDirOverride, ')
          ..write('verifyNote: $verifyNote, ')
          ..write('verifyRepairable: $verifyRepairable, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('manuallyEditedAt: $manuallyEditedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      sourceId,
      dlPath,
      dirName,
      title,
      cvNames,
      circleName,
      releaseDate,
      tagsJson,
      coverUrl,
      organizedAt,
      sourceDirOverride,
      verifyNote,
      verifyRepairable,
      verifiedAt,
      manuallyEditedAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryWork &&
          other.sourceId == this.sourceId &&
          other.dlPath == this.dlPath &&
          other.dirName == this.dirName &&
          other.title == this.title &&
          other.cvNames == this.cvNames &&
          other.circleName == this.circleName &&
          other.releaseDate == this.releaseDate &&
          other.tagsJson == this.tagsJson &&
          other.coverUrl == this.coverUrl &&
          other.organizedAt == this.organizedAt &&
          other.sourceDirOverride == this.sourceDirOverride &&
          other.verifyNote == this.verifyNote &&
          other.verifyRepairable == this.verifyRepairable &&
          other.verifiedAt == this.verifiedAt &&
          other.manuallyEditedAt == this.manuallyEditedAt &&
          other.updatedAt == this.updatedAt);
}

class LibraryWorksCompanion extends UpdateCompanion<LibraryWork> {
  final Value<String> sourceId;
  final Value<String> dlPath;
  final Value<String> dirName;
  final Value<String> title;
  final Value<String> cvNames;
  final Value<String> circleName;
  final Value<String> releaseDate;
  final Value<String> tagsJson;
  final Value<String> coverUrl;
  final Value<String?> organizedAt;
  final Value<String?> sourceDirOverride;
  final Value<String?> verifyNote;
  final Value<bool?> verifyRepairable;
  final Value<DateTime?> verifiedAt;
  final Value<DateTime?> manuallyEditedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LibraryWorksCompanion({
    this.sourceId = const Value.absent(),
    this.dlPath = const Value.absent(),
    this.dirName = const Value.absent(),
    this.title = const Value.absent(),
    this.cvNames = const Value.absent(),
    this.circleName = const Value.absent(),
    this.releaseDate = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.organizedAt = const Value.absent(),
    this.sourceDirOverride = const Value.absent(),
    this.verifyNote = const Value.absent(),
    this.verifyRepairable = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.manuallyEditedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryWorksCompanion.insert({
    required String sourceId,
    this.dlPath = const Value.absent(),
    this.dirName = const Value.absent(),
    this.title = const Value.absent(),
    this.cvNames = const Value.absent(),
    this.circleName = const Value.absent(),
    this.releaseDate = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.organizedAt = const Value.absent(),
    this.sourceDirOverride = const Value.absent(),
    this.verifyNote = const Value.absent(),
    this.verifyRepairable = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.manuallyEditedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId);
  static Insertable<LibraryWork> custom({
    Expression<String>? sourceId,
    Expression<String>? dlPath,
    Expression<String>? dirName,
    Expression<String>? title,
    Expression<String>? cvNames,
    Expression<String>? circleName,
    Expression<String>? releaseDate,
    Expression<String>? tagsJson,
    Expression<String>? coverUrl,
    Expression<String>? organizedAt,
    Expression<String>? sourceDirOverride,
    Expression<String>? verifyNote,
    Expression<bool>? verifyRepairable,
    Expression<DateTime>? verifiedAt,
    Expression<DateTime>? manuallyEditedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (dlPath != null) 'dl_path': dlPath,
      if (dirName != null) 'dir_name': dirName,
      if (title != null) 'title': title,
      if (cvNames != null) 'cv_names': cvNames,
      if (circleName != null) 'circle_name': circleName,
      if (releaseDate != null) 'release_date': releaseDate,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (organizedAt != null) 'organized_at': organizedAt,
      if (sourceDirOverride != null) 'source_dir_override': sourceDirOverride,
      if (verifyNote != null) 'verify_note': verifyNote,
      if (verifyRepairable != null) 'verify_repairable': verifyRepairable,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (manuallyEditedAt != null) 'manually_edited_at': manuallyEditedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryWorksCompanion copyWith(
      {Value<String>? sourceId,
      Value<String>? dlPath,
      Value<String>? dirName,
      Value<String>? title,
      Value<String>? cvNames,
      Value<String>? circleName,
      Value<String>? releaseDate,
      Value<String>? tagsJson,
      Value<String>? coverUrl,
      Value<String?>? organizedAt,
      Value<String?>? sourceDirOverride,
      Value<String?>? verifyNote,
      Value<bool?>? verifyRepairable,
      Value<DateTime?>? verifiedAt,
      Value<DateTime?>? manuallyEditedAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LibraryWorksCompanion(
      sourceId: sourceId ?? this.sourceId,
      dlPath: dlPath ?? this.dlPath,
      dirName: dirName ?? this.dirName,
      title: title ?? this.title,
      cvNames: cvNames ?? this.cvNames,
      circleName: circleName ?? this.circleName,
      releaseDate: releaseDate ?? this.releaseDate,
      tagsJson: tagsJson ?? this.tagsJson,
      coverUrl: coverUrl ?? this.coverUrl,
      organizedAt: organizedAt ?? this.organizedAt,
      sourceDirOverride: sourceDirOverride ?? this.sourceDirOverride,
      verifyNote: verifyNote ?? this.verifyNote,
      verifyRepairable: verifyRepairable ?? this.verifyRepairable,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      manuallyEditedAt: manuallyEditedAt ?? this.manuallyEditedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (dlPath.present) {
      map['dl_path'] = Variable<String>(dlPath.value);
    }
    if (dirName.present) {
      map['dir_name'] = Variable<String>(dirName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (cvNames.present) {
      map['cv_names'] = Variable<String>(cvNames.value);
    }
    if (circleName.present) {
      map['circle_name'] = Variable<String>(circleName.value);
    }
    if (releaseDate.present) {
      map['release_date'] = Variable<String>(releaseDate.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (organizedAt.present) {
      map['organized_at'] = Variable<String>(organizedAt.value);
    }
    if (sourceDirOverride.present) {
      map['source_dir_override'] = Variable<String>(sourceDirOverride.value);
    }
    if (verifyNote.present) {
      map['verify_note'] = Variable<String>(verifyNote.value);
    }
    if (verifyRepairable.present) {
      map['verify_repairable'] = Variable<bool>(verifyRepairable.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<DateTime>(verifiedAt.value);
    }
    if (manuallyEditedAt.present) {
      map['manually_edited_at'] = Variable<DateTime>(manuallyEditedAt.value);
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
    return (StringBuffer('LibraryWorksCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('dlPath: $dlPath, ')
          ..write('dirName: $dirName, ')
          ..write('title: $title, ')
          ..write('cvNames: $cvNames, ')
          ..write('circleName: $circleName, ')
          ..write('releaseDate: $releaseDate, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('organizedAt: $organizedAt, ')
          ..write('sourceDirOverride: $sourceDirOverride, ')
          ..write('verifyNote: $verifyNote, ')
          ..write('verifyRepairable: $verifyRepairable, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('manuallyEditedAt: $manuallyEditedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaLibraryLocationsTable extends MediaLibraryLocations
    with TableInfo<$MediaLibraryLocationsTable, MediaLibraryLocation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaLibraryLocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rootPathMeta =
      const VerificationMeta('rootPath');
  @override
  late final GeneratedColumn<String> rootPath = GeneratedColumn<String>(
      'root_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _matchedPathMeta =
      const VerificationMeta('matchedPath');
  @override
  late final GeneratedColumn<String> matchedPath = GeneratedColumn<String>(
      'matched_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _depthMeta = const VerificationMeta('depth');
  @override
  late final GeneratedColumn<int> depth = GeneratedColumn<int>(
      'depth', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _scannedAtMeta =
      const VerificationMeta('scannedAt');
  @override
  late final GeneratedColumn<DateTime> scannedAt = GeneratedColumn<DateTime>(
      'scanned_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [sourceId, rootPath, matchedPath, depth, scannedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_library_locations';
  @override
  VerificationContext validateIntegrity(
      Insertable<MediaLibraryLocation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('root_path')) {
      context.handle(_rootPathMeta,
          rootPath.isAcceptableOrUnknown(data['root_path']!, _rootPathMeta));
    } else if (isInserting) {
      context.missing(_rootPathMeta);
    }
    if (data.containsKey('matched_path')) {
      context.handle(
          _matchedPathMeta,
          matchedPath.isAcceptableOrUnknown(
              data['matched_path']!, _matchedPathMeta));
    } else if (isInserting) {
      context.missing(_matchedPathMeta);
    }
    if (data.containsKey('depth')) {
      context.handle(
          _depthMeta, depth.isAcceptableOrUnknown(data['depth']!, _depthMeta));
    }
    if (data.containsKey('scanned_at')) {
      context.handle(_scannedAtMeta,
          scannedAt.isAcceptableOrUnknown(data['scanned_at']!, _scannedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId, rootPath};
  @override
  MediaLibraryLocation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaLibraryLocation(
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      rootPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}root_path'])!,
      matchedPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}matched_path'])!,
      depth: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}depth'])!,
      scannedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}scanned_at'])!,
    );
  }

  @override
  $MediaLibraryLocationsTable createAlias(String alias) {
    return $MediaLibraryLocationsTable(attachedDatabase, alias);
  }
}

class MediaLibraryLocation extends DataClass
    implements Insertable<MediaLibraryLocation> {
  final String sourceId;
  final String rootPath;
  final String matchedPath;
  final int depth;
  final DateTime scannedAt;
  const MediaLibraryLocation(
      {required this.sourceId,
      required this.rootPath,
      required this.matchedPath,
      required this.depth,
      required this.scannedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['root_path'] = Variable<String>(rootPath);
    map['matched_path'] = Variable<String>(matchedPath);
    map['depth'] = Variable<int>(depth);
    map['scanned_at'] = Variable<DateTime>(scannedAt);
    return map;
  }

  MediaLibraryLocationsCompanion toCompanion(bool nullToAbsent) {
    return MediaLibraryLocationsCompanion(
      sourceId: Value(sourceId),
      rootPath: Value(rootPath),
      matchedPath: Value(matchedPath),
      depth: Value(depth),
      scannedAt: Value(scannedAt),
    );
  }

  factory MediaLibraryLocation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaLibraryLocation(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      rootPath: serializer.fromJson<String>(json['rootPath']),
      matchedPath: serializer.fromJson<String>(json['matchedPath']),
      depth: serializer.fromJson<int>(json['depth']),
      scannedAt: serializer.fromJson<DateTime>(json['scannedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'rootPath': serializer.toJson<String>(rootPath),
      'matchedPath': serializer.toJson<String>(matchedPath),
      'depth': serializer.toJson<int>(depth),
      'scannedAt': serializer.toJson<DateTime>(scannedAt),
    };
  }

  MediaLibraryLocation copyWith(
          {String? sourceId,
          String? rootPath,
          String? matchedPath,
          int? depth,
          DateTime? scannedAt}) =>
      MediaLibraryLocation(
        sourceId: sourceId ?? this.sourceId,
        rootPath: rootPath ?? this.rootPath,
        matchedPath: matchedPath ?? this.matchedPath,
        depth: depth ?? this.depth,
        scannedAt: scannedAt ?? this.scannedAt,
      );
  MediaLibraryLocation copyWithCompanion(MediaLibraryLocationsCompanion data) {
    return MediaLibraryLocation(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      rootPath: data.rootPath.present ? data.rootPath.value : this.rootPath,
      matchedPath:
          data.matchedPath.present ? data.matchedPath.value : this.matchedPath,
      depth: data.depth.present ? data.depth.value : this.depth,
      scannedAt: data.scannedAt.present ? data.scannedAt.value : this.scannedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaLibraryLocation(')
          ..write('sourceId: $sourceId, ')
          ..write('rootPath: $rootPath, ')
          ..write('matchedPath: $matchedPath, ')
          ..write('depth: $depth, ')
          ..write('scannedAt: $scannedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceId, rootPath, matchedPath, depth, scannedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaLibraryLocation &&
          other.sourceId == this.sourceId &&
          other.rootPath == this.rootPath &&
          other.matchedPath == this.matchedPath &&
          other.depth == this.depth &&
          other.scannedAt == this.scannedAt);
}

class MediaLibraryLocationsCompanion
    extends UpdateCompanion<MediaLibraryLocation> {
  final Value<String> sourceId;
  final Value<String> rootPath;
  final Value<String> matchedPath;
  final Value<int> depth;
  final Value<DateTime> scannedAt;
  final Value<int> rowid;
  const MediaLibraryLocationsCompanion({
    this.sourceId = const Value.absent(),
    this.rootPath = const Value.absent(),
    this.matchedPath = const Value.absent(),
    this.depth = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaLibraryLocationsCompanion.insert({
    required String sourceId,
    required String rootPath,
    required String matchedPath,
    this.depth = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : sourceId = Value(sourceId),
        rootPath = Value(rootPath),
        matchedPath = Value(matchedPath);
  static Insertable<MediaLibraryLocation> custom({
    Expression<String>? sourceId,
    Expression<String>? rootPath,
    Expression<String>? matchedPath,
    Expression<int>? depth,
    Expression<DateTime>? scannedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (rootPath != null) 'root_path': rootPath,
      if (matchedPath != null) 'matched_path': matchedPath,
      if (depth != null) 'depth': depth,
      if (scannedAt != null) 'scanned_at': scannedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaLibraryLocationsCompanion copyWith(
      {Value<String>? sourceId,
      Value<String>? rootPath,
      Value<String>? matchedPath,
      Value<int>? depth,
      Value<DateTime>? scannedAt,
      Value<int>? rowid}) {
    return MediaLibraryLocationsCompanion(
      sourceId: sourceId ?? this.sourceId,
      rootPath: rootPath ?? this.rootPath,
      matchedPath: matchedPath ?? this.matchedPath,
      depth: depth ?? this.depth,
      scannedAt: scannedAt ?? this.scannedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (rootPath.present) {
      map['root_path'] = Variable<String>(rootPath.value);
    }
    if (matchedPath.present) {
      map['matched_path'] = Variable<String>(matchedPath.value);
    }
    if (depth.present) {
      map['depth'] = Variable<int>(depth.value);
    }
    if (scannedAt.present) {
      map['scanned_at'] = Variable<DateTime>(scannedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaLibraryLocationsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('rootPath: $rootPath, ')
          ..write('matchedPath: $matchedPath, ')
          ..write('depth: $depth, ')
          ..write('scannedAt: $scannedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaLibraryRootsTable extends MediaLibraryRoots
    with TableInfo<$MediaLibraryRootsTable, MediaLibraryRoot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaLibraryRootsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rootPathMeta =
      const VerificationMeta('rootPath');
  @override
  late final GeneratedColumn<String> rootPath = GeneratedColumn<String>(
      'root_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastScannedAtMeta =
      const VerificationMeta('lastScannedAt');
  @override
  late final GeneratedColumn<DateTime> lastScannedAt =
      GeneratedColumn<DateTime>('last_scanned_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [rootPath, lastScannedAt, lastError];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_library_roots';
  @override
  VerificationContext validateIntegrity(Insertable<MediaLibraryRoot> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('root_path')) {
      context.handle(_rootPathMeta,
          rootPath.isAcceptableOrUnknown(data['root_path']!, _rootPathMeta));
    } else if (isInserting) {
      context.missing(_rootPathMeta);
    }
    if (data.containsKey('last_scanned_at')) {
      context.handle(
          _lastScannedAtMeta,
          lastScannedAt.isAcceptableOrUnknown(
              data['last_scanned_at']!, _lastScannedAtMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rootPath};
  @override
  MediaLibraryRoot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaLibraryRoot(
      rootPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}root_path'])!,
      lastScannedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_scanned_at']),
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
    );
  }

  @override
  $MediaLibraryRootsTable createAlias(String alias) {
    return $MediaLibraryRootsTable(attachedDatabase, alias);
  }
}

class MediaLibraryRoot extends DataClass
    implements Insertable<MediaLibraryRoot> {
  final String rootPath;
  final DateTime? lastScannedAt;
  final String? lastError;
  const MediaLibraryRoot(
      {required this.rootPath, this.lastScannedAt, this.lastError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['root_path'] = Variable<String>(rootPath);
    if (!nullToAbsent || lastScannedAt != null) {
      map['last_scanned_at'] = Variable<DateTime>(lastScannedAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  MediaLibraryRootsCompanion toCompanion(bool nullToAbsent) {
    return MediaLibraryRootsCompanion(
      rootPath: Value(rootPath),
      lastScannedAt: lastScannedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastScannedAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory MediaLibraryRoot.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaLibraryRoot(
      rootPath: serializer.fromJson<String>(json['rootPath']),
      lastScannedAt: serializer.fromJson<DateTime?>(json['lastScannedAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rootPath': serializer.toJson<String>(rootPath),
      'lastScannedAt': serializer.toJson<DateTime?>(lastScannedAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  MediaLibraryRoot copyWith(
          {String? rootPath,
          Value<DateTime?> lastScannedAt = const Value.absent(),
          Value<String?> lastError = const Value.absent()}) =>
      MediaLibraryRoot(
        rootPath: rootPath ?? this.rootPath,
        lastScannedAt:
            lastScannedAt.present ? lastScannedAt.value : this.lastScannedAt,
        lastError: lastError.present ? lastError.value : this.lastError,
      );
  MediaLibraryRoot copyWithCompanion(MediaLibraryRootsCompanion data) {
    return MediaLibraryRoot(
      rootPath: data.rootPath.present ? data.rootPath.value : this.rootPath,
      lastScannedAt: data.lastScannedAt.present
          ? data.lastScannedAt.value
          : this.lastScannedAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaLibraryRoot(')
          ..write('rootPath: $rootPath, ')
          ..write('lastScannedAt: $lastScannedAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(rootPath, lastScannedAt, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaLibraryRoot &&
          other.rootPath == this.rootPath &&
          other.lastScannedAt == this.lastScannedAt &&
          other.lastError == this.lastError);
}

class MediaLibraryRootsCompanion extends UpdateCompanion<MediaLibraryRoot> {
  final Value<String> rootPath;
  final Value<DateTime?> lastScannedAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const MediaLibraryRootsCompanion({
    this.rootPath = const Value.absent(),
    this.lastScannedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaLibraryRootsCompanion.insert({
    required String rootPath,
    this.lastScannedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : rootPath = Value(rootPath);
  static Insertable<MediaLibraryRoot> custom({
    Expression<String>? rootPath,
    Expression<DateTime>? lastScannedAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (rootPath != null) 'root_path': rootPath,
      if (lastScannedAt != null) 'last_scanned_at': lastScannedAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaLibraryRootsCompanion copyWith(
      {Value<String>? rootPath,
      Value<DateTime?>? lastScannedAt,
      Value<String?>? lastError,
      Value<int>? rowid}) {
    return MediaLibraryRootsCompanion(
      rootPath: rootPath ?? this.rootPath,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rootPath.present) {
      map['root_path'] = Variable<String>(rootPath.value);
    }
    if (lastScannedAt.present) {
      map['last_scanned_at'] = Variable<DateTime>(lastScannedAt.value);
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
    return (StringBuffer('MediaLibraryRootsCompanion(')
          ..write('rootPath: $rootPath, ')
          ..write('lastScannedAt: $lastScannedAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryMetaTable extends LibraryMeta
    with TableInfo<$LibraryMetaTable, LibraryMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_meta';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LibraryMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryMetaData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $LibraryMetaTable createAlias(String alias) {
    return $LibraryMetaTable(attachedDatabase, alias);
  }
}

class LibraryMetaData extends DataClass implements Insertable<LibraryMetaData> {
  final String key;
  final String value;
  const LibraryMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  LibraryMetaCompanion toCompanion(bool nullToAbsent) {
    return LibraryMetaCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory LibraryMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryMetaData(
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

  LibraryMetaData copyWith({String? key, String? value}) => LibraryMetaData(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  LibraryMetaData copyWithCompanion(LibraryMetaCompanion data) {
    return LibraryMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryMetaData(')
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
      (other is LibraryMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class LibraryMetaCompanion extends UpdateCompanion<LibraryMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const LibraryMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<LibraryMetaData> custom({
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

  LibraryMetaCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return LibraryMetaCompanion(
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
    return (StringBuffer('LibraryMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LibraryDatabase extends GeneratedDatabase {
  _$LibraryDatabase(QueryExecutor e) : super(e);
  $LibraryDatabaseManager get managers => $LibraryDatabaseManager(this);
  late final $LibraryWorksTable libraryWorks = $LibraryWorksTable(this);
  late final $MediaLibraryLocationsTable mediaLibraryLocations =
      $MediaLibraryLocationsTable(this);
  late final $MediaLibraryRootsTable mediaLibraryRoots =
      $MediaLibraryRootsTable(this);
  late final $LibraryMetaTable libraryMeta = $LibraryMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [libraryWorks, mediaLibraryLocations, mediaLibraryRoots, libraryMeta];
}

typedef $$LibraryWorksTableCreateCompanionBuilder = LibraryWorksCompanion
    Function({
  required String sourceId,
  Value<String> dlPath,
  Value<String> dirName,
  Value<String> title,
  Value<String> cvNames,
  Value<String> circleName,
  Value<String> releaseDate,
  Value<String> tagsJson,
  Value<String> coverUrl,
  Value<String?> organizedAt,
  Value<String?> sourceDirOverride,
  Value<String?> verifyNote,
  Value<bool?> verifyRepairable,
  Value<DateTime?> verifiedAt,
  Value<DateTime?> manuallyEditedAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$LibraryWorksTableUpdateCompanionBuilder = LibraryWorksCompanion
    Function({
  Value<String> sourceId,
  Value<String> dlPath,
  Value<String> dirName,
  Value<String> title,
  Value<String> cvNames,
  Value<String> circleName,
  Value<String> releaseDate,
  Value<String> tagsJson,
  Value<String> coverUrl,
  Value<String?> organizedAt,
  Value<String?> sourceDirOverride,
  Value<String?> verifyNote,
  Value<bool?> verifyRepairable,
  Value<DateTime?> verifiedAt,
  Value<DateTime?> manuallyEditedAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$LibraryWorksTableFilterComposer
    extends Composer<_$LibraryDatabase, $LibraryWorksTable> {
  $$LibraryWorksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dlPath => $composableBuilder(
      column: $table.dlPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dirName => $composableBuilder(
      column: $table.dirName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cvNames => $composableBuilder(
      column: $table.cvNames, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get circleName => $composableBuilder(
      column: $table.circleName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get releaseDate => $composableBuilder(
      column: $table.releaseDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get coverUrl => $composableBuilder(
      column: $table.coverUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get organizedAt => $composableBuilder(
      column: $table.organizedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceDirOverride => $composableBuilder(
      column: $table.sourceDirOverride,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get verifyNote => $composableBuilder(
      column: $table.verifyNote, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get verifyRepairable => $composableBuilder(
      column: $table.verifyRepairable,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get verifiedAt => $composableBuilder(
      column: $table.verifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get manuallyEditedAt => $composableBuilder(
      column: $table.manuallyEditedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LibraryWorksTableOrderingComposer
    extends Composer<_$LibraryDatabase, $LibraryWorksTable> {
  $$LibraryWorksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dlPath => $composableBuilder(
      column: $table.dlPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dirName => $composableBuilder(
      column: $table.dirName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cvNames => $composableBuilder(
      column: $table.cvNames, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get circleName => $composableBuilder(
      column: $table.circleName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get releaseDate => $composableBuilder(
      column: $table.releaseDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get coverUrl => $composableBuilder(
      column: $table.coverUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get organizedAt => $composableBuilder(
      column: $table.organizedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceDirOverride => $composableBuilder(
      column: $table.sourceDirOverride,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get verifyNote => $composableBuilder(
      column: $table.verifyNote, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get verifyRepairable => $composableBuilder(
      column: $table.verifyRepairable,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get verifiedAt => $composableBuilder(
      column: $table.verifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get manuallyEditedAt => $composableBuilder(
      column: $table.manuallyEditedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LibraryWorksTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $LibraryWorksTable> {
  $$LibraryWorksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get dlPath =>
      $composableBuilder(column: $table.dlPath, builder: (column) => column);

  GeneratedColumn<String> get dirName =>
      $composableBuilder(column: $table.dirName, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get cvNames =>
      $composableBuilder(column: $table.cvNames, builder: (column) => column);

  GeneratedColumn<String> get circleName => $composableBuilder(
      column: $table.circleName, builder: (column) => column);

  GeneratedColumn<String> get releaseDate => $composableBuilder(
      column: $table.releaseDate, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get organizedAt => $composableBuilder(
      column: $table.organizedAt, builder: (column) => column);

  GeneratedColumn<String> get sourceDirOverride => $composableBuilder(
      column: $table.sourceDirOverride, builder: (column) => column);

  GeneratedColumn<String> get verifyNote => $composableBuilder(
      column: $table.verifyNote, builder: (column) => column);

  GeneratedColumn<bool> get verifyRepairable => $composableBuilder(
      column: $table.verifyRepairable, builder: (column) => column);

  GeneratedColumn<DateTime> get verifiedAt => $composableBuilder(
      column: $table.verifiedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get manuallyEditedAt => $composableBuilder(
      column: $table.manuallyEditedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LibraryWorksTableTableManager extends RootTableManager<
    _$LibraryDatabase,
    $LibraryWorksTable,
    LibraryWork,
    $$LibraryWorksTableFilterComposer,
    $$LibraryWorksTableOrderingComposer,
    $$LibraryWorksTableAnnotationComposer,
    $$LibraryWorksTableCreateCompanionBuilder,
    $$LibraryWorksTableUpdateCompanionBuilder,
    (
      LibraryWork,
      BaseReferences<_$LibraryDatabase, $LibraryWorksTable, LibraryWork>
    ),
    LibraryWork,
    PrefetchHooks Function()> {
  $$LibraryWorksTableTableManager(
      _$LibraryDatabase db, $LibraryWorksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryWorksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryWorksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryWorksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> sourceId = const Value.absent(),
            Value<String> dlPath = const Value.absent(),
            Value<String> dirName = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> cvNames = const Value.absent(),
            Value<String> circleName = const Value.absent(),
            Value<String> releaseDate = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<String> coverUrl = const Value.absent(),
            Value<String?> organizedAt = const Value.absent(),
            Value<String?> sourceDirOverride = const Value.absent(),
            Value<String?> verifyNote = const Value.absent(),
            Value<bool?> verifyRepairable = const Value.absent(),
            Value<DateTime?> verifiedAt = const Value.absent(),
            Value<DateTime?> manuallyEditedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryWorksCompanion(
            sourceId: sourceId,
            dlPath: dlPath,
            dirName: dirName,
            title: title,
            cvNames: cvNames,
            circleName: circleName,
            releaseDate: releaseDate,
            tagsJson: tagsJson,
            coverUrl: coverUrl,
            organizedAt: organizedAt,
            sourceDirOverride: sourceDirOverride,
            verifyNote: verifyNote,
            verifyRepairable: verifyRepairable,
            verifiedAt: verifiedAt,
            manuallyEditedAt: manuallyEditedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String sourceId,
            Value<String> dlPath = const Value.absent(),
            Value<String> dirName = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> cvNames = const Value.absent(),
            Value<String> circleName = const Value.absent(),
            Value<String> releaseDate = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<String> coverUrl = const Value.absent(),
            Value<String?> organizedAt = const Value.absent(),
            Value<String?> sourceDirOverride = const Value.absent(),
            Value<String?> verifyNote = const Value.absent(),
            Value<bool?> verifyRepairable = const Value.absent(),
            Value<DateTime?> verifiedAt = const Value.absent(),
            Value<DateTime?> manuallyEditedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryWorksCompanion.insert(
            sourceId: sourceId,
            dlPath: dlPath,
            dirName: dirName,
            title: title,
            cvNames: cvNames,
            circleName: circleName,
            releaseDate: releaseDate,
            tagsJson: tagsJson,
            coverUrl: coverUrl,
            organizedAt: organizedAt,
            sourceDirOverride: sourceDirOverride,
            verifyNote: verifyNote,
            verifyRepairable: verifyRepairable,
            verifiedAt: verifiedAt,
            manuallyEditedAt: manuallyEditedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LibraryWorksTableProcessedTableManager = ProcessedTableManager<
    _$LibraryDatabase,
    $LibraryWorksTable,
    LibraryWork,
    $$LibraryWorksTableFilterComposer,
    $$LibraryWorksTableOrderingComposer,
    $$LibraryWorksTableAnnotationComposer,
    $$LibraryWorksTableCreateCompanionBuilder,
    $$LibraryWorksTableUpdateCompanionBuilder,
    (
      LibraryWork,
      BaseReferences<_$LibraryDatabase, $LibraryWorksTable, LibraryWork>
    ),
    LibraryWork,
    PrefetchHooks Function()>;
typedef $$MediaLibraryLocationsTableCreateCompanionBuilder
    = MediaLibraryLocationsCompanion Function({
  required String sourceId,
  required String rootPath,
  required String matchedPath,
  Value<int> depth,
  Value<DateTime> scannedAt,
  Value<int> rowid,
});
typedef $$MediaLibraryLocationsTableUpdateCompanionBuilder
    = MediaLibraryLocationsCompanion Function({
  Value<String> sourceId,
  Value<String> rootPath,
  Value<String> matchedPath,
  Value<int> depth,
  Value<DateTime> scannedAt,
  Value<int> rowid,
});

class $$MediaLibraryLocationsTableFilterComposer
    extends Composer<_$LibraryDatabase, $MediaLibraryLocationsTable> {
  $$MediaLibraryLocationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rootPath => $composableBuilder(
      column: $table.rootPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get matchedPath => $composableBuilder(
      column: $table.matchedPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get depth => $composableBuilder(
      column: $table.depth, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get scannedAt => $composableBuilder(
      column: $table.scannedAt, builder: (column) => ColumnFilters(column));
}

class $$MediaLibraryLocationsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $MediaLibraryLocationsTable> {
  $$MediaLibraryLocationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rootPath => $composableBuilder(
      column: $table.rootPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get matchedPath => $composableBuilder(
      column: $table.matchedPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get depth => $composableBuilder(
      column: $table.depth, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get scannedAt => $composableBuilder(
      column: $table.scannedAt, builder: (column) => ColumnOrderings(column));
}

class $$MediaLibraryLocationsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $MediaLibraryLocationsTable> {
  $$MediaLibraryLocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get rootPath =>
      $composableBuilder(column: $table.rootPath, builder: (column) => column);

  GeneratedColumn<String> get matchedPath => $composableBuilder(
      column: $table.matchedPath, builder: (column) => column);

  GeneratedColumn<int> get depth =>
      $composableBuilder(column: $table.depth, builder: (column) => column);

  GeneratedColumn<DateTime> get scannedAt =>
      $composableBuilder(column: $table.scannedAt, builder: (column) => column);
}

class $$MediaLibraryLocationsTableTableManager extends RootTableManager<
    _$LibraryDatabase,
    $MediaLibraryLocationsTable,
    MediaLibraryLocation,
    $$MediaLibraryLocationsTableFilterComposer,
    $$MediaLibraryLocationsTableOrderingComposer,
    $$MediaLibraryLocationsTableAnnotationComposer,
    $$MediaLibraryLocationsTableCreateCompanionBuilder,
    $$MediaLibraryLocationsTableUpdateCompanionBuilder,
    (
      MediaLibraryLocation,
      BaseReferences<_$LibraryDatabase, $MediaLibraryLocationsTable,
          MediaLibraryLocation>
    ),
    MediaLibraryLocation,
    PrefetchHooks Function()> {
  $$MediaLibraryLocationsTableTableManager(
      _$LibraryDatabase db, $MediaLibraryLocationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaLibraryLocationsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaLibraryLocationsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaLibraryLocationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> sourceId = const Value.absent(),
            Value<String> rootPath = const Value.absent(),
            Value<String> matchedPath = const Value.absent(),
            Value<int> depth = const Value.absent(),
            Value<DateTime> scannedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaLibraryLocationsCompanion(
            sourceId: sourceId,
            rootPath: rootPath,
            matchedPath: matchedPath,
            depth: depth,
            scannedAt: scannedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String sourceId,
            required String rootPath,
            required String matchedPath,
            Value<int> depth = const Value.absent(),
            Value<DateTime> scannedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaLibraryLocationsCompanion.insert(
            sourceId: sourceId,
            rootPath: rootPath,
            matchedPath: matchedPath,
            depth: depth,
            scannedAt: scannedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MediaLibraryLocationsTableProcessedTableManager
    = ProcessedTableManager<
        _$LibraryDatabase,
        $MediaLibraryLocationsTable,
        MediaLibraryLocation,
        $$MediaLibraryLocationsTableFilterComposer,
        $$MediaLibraryLocationsTableOrderingComposer,
        $$MediaLibraryLocationsTableAnnotationComposer,
        $$MediaLibraryLocationsTableCreateCompanionBuilder,
        $$MediaLibraryLocationsTableUpdateCompanionBuilder,
        (
          MediaLibraryLocation,
          BaseReferences<_$LibraryDatabase, $MediaLibraryLocationsTable,
              MediaLibraryLocation>
        ),
        MediaLibraryLocation,
        PrefetchHooks Function()>;
typedef $$MediaLibraryRootsTableCreateCompanionBuilder
    = MediaLibraryRootsCompanion Function({
  required String rootPath,
  Value<DateTime?> lastScannedAt,
  Value<String?> lastError,
  Value<int> rowid,
});
typedef $$MediaLibraryRootsTableUpdateCompanionBuilder
    = MediaLibraryRootsCompanion Function({
  Value<String> rootPath,
  Value<DateTime?> lastScannedAt,
  Value<String?> lastError,
  Value<int> rowid,
});

class $$MediaLibraryRootsTableFilterComposer
    extends Composer<_$LibraryDatabase, $MediaLibraryRootsTable> {
  $$MediaLibraryRootsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get rootPath => $composableBuilder(
      column: $table.rootPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastScannedAt => $composableBuilder(
      column: $table.lastScannedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));
}

class $$MediaLibraryRootsTableOrderingComposer
    extends Composer<_$LibraryDatabase, $MediaLibraryRootsTable> {
  $$MediaLibraryRootsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get rootPath => $composableBuilder(
      column: $table.rootPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastScannedAt => $composableBuilder(
      column: $table.lastScannedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));
}

class $$MediaLibraryRootsTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $MediaLibraryRootsTable> {
  $$MediaLibraryRootsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get rootPath =>
      $composableBuilder(column: $table.rootPath, builder: (column) => column);

  GeneratedColumn<DateTime> get lastScannedAt => $composableBuilder(
      column: $table.lastScannedAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$MediaLibraryRootsTableTableManager extends RootTableManager<
    _$LibraryDatabase,
    $MediaLibraryRootsTable,
    MediaLibraryRoot,
    $$MediaLibraryRootsTableFilterComposer,
    $$MediaLibraryRootsTableOrderingComposer,
    $$MediaLibraryRootsTableAnnotationComposer,
    $$MediaLibraryRootsTableCreateCompanionBuilder,
    $$MediaLibraryRootsTableUpdateCompanionBuilder,
    (
      MediaLibraryRoot,
      BaseReferences<_$LibraryDatabase, $MediaLibraryRootsTable,
          MediaLibraryRoot>
    ),
    MediaLibraryRoot,
    PrefetchHooks Function()> {
  $$MediaLibraryRootsTableTableManager(
      _$LibraryDatabase db, $MediaLibraryRootsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaLibraryRootsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaLibraryRootsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaLibraryRootsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> rootPath = const Value.absent(),
            Value<DateTime?> lastScannedAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaLibraryRootsCompanion(
            rootPath: rootPath,
            lastScannedAt: lastScannedAt,
            lastError: lastError,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String rootPath,
            Value<DateTime?> lastScannedAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaLibraryRootsCompanion.insert(
            rootPath: rootPath,
            lastScannedAt: lastScannedAt,
            lastError: lastError,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MediaLibraryRootsTableProcessedTableManager = ProcessedTableManager<
    _$LibraryDatabase,
    $MediaLibraryRootsTable,
    MediaLibraryRoot,
    $$MediaLibraryRootsTableFilterComposer,
    $$MediaLibraryRootsTableOrderingComposer,
    $$MediaLibraryRootsTableAnnotationComposer,
    $$MediaLibraryRootsTableCreateCompanionBuilder,
    $$MediaLibraryRootsTableUpdateCompanionBuilder,
    (
      MediaLibraryRoot,
      BaseReferences<_$LibraryDatabase, $MediaLibraryRootsTable,
          MediaLibraryRoot>
    ),
    MediaLibraryRoot,
    PrefetchHooks Function()>;
typedef $$LibraryMetaTableCreateCompanionBuilder = LibraryMetaCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$LibraryMetaTableUpdateCompanionBuilder = LibraryMetaCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$LibraryMetaTableFilterComposer
    extends Composer<_$LibraryDatabase, $LibraryMetaTable> {
  $$LibraryMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$LibraryMetaTableOrderingComposer
    extends Composer<_$LibraryDatabase, $LibraryMetaTable> {
  $$LibraryMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$LibraryMetaTableAnnotationComposer
    extends Composer<_$LibraryDatabase, $LibraryMetaTable> {
  $$LibraryMetaTableAnnotationComposer({
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

class $$LibraryMetaTableTableManager extends RootTableManager<
    _$LibraryDatabase,
    $LibraryMetaTable,
    LibraryMetaData,
    $$LibraryMetaTableFilterComposer,
    $$LibraryMetaTableOrderingComposer,
    $$LibraryMetaTableAnnotationComposer,
    $$LibraryMetaTableCreateCompanionBuilder,
    $$LibraryMetaTableUpdateCompanionBuilder,
    (
      LibraryMetaData,
      BaseReferences<_$LibraryDatabase, $LibraryMetaTable, LibraryMetaData>
    ),
    LibraryMetaData,
    PrefetchHooks Function()> {
  $$LibraryMetaTableTableManager(_$LibraryDatabase db, $LibraryMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryMetaCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryMetaCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LibraryMetaTableProcessedTableManager = ProcessedTableManager<
    _$LibraryDatabase,
    $LibraryMetaTable,
    LibraryMetaData,
    $$LibraryMetaTableFilterComposer,
    $$LibraryMetaTableOrderingComposer,
    $$LibraryMetaTableAnnotationComposer,
    $$LibraryMetaTableCreateCompanionBuilder,
    $$LibraryMetaTableUpdateCompanionBuilder,
    (
      LibraryMetaData,
      BaseReferences<_$LibraryDatabase, $LibraryMetaTable, LibraryMetaData>
    ),
    LibraryMetaData,
    PrefetchHooks Function()>;

class $LibraryDatabaseManager {
  final _$LibraryDatabase _db;
  $LibraryDatabaseManager(this._db);
  $$LibraryWorksTableTableManager get libraryWorks =>
      $$LibraryWorksTableTableManager(_db, _db.libraryWorks);
  $$MediaLibraryLocationsTableTableManager get mediaLibraryLocations =>
      $$MediaLibraryLocationsTableTableManager(_db, _db.mediaLibraryLocations);
  $$MediaLibraryRootsTableTableManager get mediaLibraryRoots =>
      $$MediaLibraryRootsTableTableManager(_db, _db.mediaLibraryRoots);
  $$LibraryMetaTableTableManager get libraryMeta =>
      $$LibraryMetaTableTableManager(_db, _db.libraryMeta);
}
