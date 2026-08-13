import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/utils/log.dart';
import 'package:path/path.dart' as p;

/// 下载作品注册表条目。
/// 记录本应用下载过的作品及其元数据，供批量整理使用；
/// 不存放在下载目录（避免污染用户文件），统一存应用数据目录。
class WorkEntry {
  /// 作品 sourceId，如 RJ01619789
  final String sourceId;

  /// 下载根目录（downloadPath）
  final String dlPath;

  /// 作品目录名（如 cv-标题），与 [dlPath] 拼出下载目录
  final String dirName;

  /// 作品标题（下载时刻获取，整理时作为降级兜底）
  final String title;

  /// CV 名单，& 连接
  final String cvNames;

  /// 社团名
  final String circleName;

  /// 发行日期
  final String releaseDate;

  /// 流派标签
  final List<String> tags;

  /// 封面 URL
  final String coverUrl;

  /// 最近一次整理完成时间（ISO 8601），null = 未整理过
  final String? organizedAt;

  const WorkEntry({
    required this.sourceId,
    required this.dlPath,
    required this.dirName,
    required this.title,
    required this.cvNames,
    this.circleName = '',
    this.releaseDate = '',
    this.tags = const [],
    this.coverUrl = '',
    this.organizedAt,
  });

  /// 下载目录：{dlPath}/{dirName}/{sourceId}
  String get sourceDir => p.join(dlPath, dirName, sourceId);

  WorkEntry copyWith({
    String? dlPath,
    String? dirName,
    String? organizedAt,
    bool clearOrganizedAt = false,
  }) {
    return WorkEntry(
      sourceId: sourceId,
      dlPath: dlPath ?? this.dlPath,
      dirName: dirName ?? this.dirName,
      title: title,
      cvNames: cvNames,
      circleName: circleName,
      releaseDate: releaseDate,
      tags: tags,
      coverUrl: coverUrl,
      organizedAt: clearOrganizedAt ? null : (organizedAt ?? this.organizedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'dlPath': dlPath,
    'dirName': dirName,
    'title': title,
    'cvNames': cvNames,
    'circleName': circleName,
    'releaseDate': releaseDate,
    'tags': tags,
    'coverUrl': coverUrl,
    'organizedAt': organizedAt,
  };

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
    sourceId: json['sourceId']?.toString() ?? '',
    dlPath: json['dlPath']?.toString() ?? '',
    dirName: json['dirName']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    cvNames: json['cvNames']?.toString() ?? '',
    circleName: json['circleName']?.toString() ?? '',
    releaseDate: json['releaseDate']?.toString() ?? '',
    tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    coverUrl: json['coverUrl']?.toString() ?? '',
    organizedAt: json['organizedAt']?.toString(),
  );
}

/// 下载作品注册表：记录本应用下载过的作品及元数据。
/// 存储为 JSON 文件：{sourceId: entryJson}
class WorksIndex {
  final String filePath;

  WorksIndex({required this.filePath});

  Future<Map<String, dynamic>> _readRaw() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return {};
      final decoded = json.decode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (e) {
      Log.warning('read works index failed: $filePath\n' 'error: $e');
      return {};
    }
  }

  Future<void> _writeRaw(Map<String, dynamic> data) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(json.encode(data));
    } catch (e) {
      Log.error('write works index failed: $filePath\n' 'error: $e');
    }
  }

  /// 全部条目
  Future<List<WorkEntry>> list() async {
    final raw = await _readRaw();
    return raw.values
        .whereType<Map<String, dynamic>>()
        .map(WorkEntry.fromJson)
        .where((e) => e.sourceId.isNotEmpty)
        .toList();
  }

  Future<WorkEntry?> get(String sourceId) async {
    final raw = await _readRaw();
    final json = raw[sourceId];
    if (json is! Map<String, dynamic>) return null;
    return WorkEntry.fromJson(json);
  }

  /// 新增或更新条目
  Future<void> upsert(WorkEntry entry) async {
    final raw = await _readRaw();
    raw[entry.sourceId] = entry.toJson();
    await _writeRaw(raw);
  }

  /// 删除条目
  Future<void> remove(String sourceId) async {
    final raw = await _readRaw();
    if (raw.remove(sourceId) != null) {
      await _writeRaw(raw);
    }
  }

  /// 记录整理完成时间
  Future<void> markOrganized(String sourceId, {DateTime? time}) async {
    final entry = await get(sourceId);
    if (entry == null) return;
    await upsert(entry.copyWith(
        organizedAt: (time ?? DateTime.now()).toIso8601String()));
  }

  /// 下载目录已不存在的条目
  Future<List<WorkEntry>> listMissing() async {
    final entries = await list();
    return entries.where((e) => !Directory(e.sourceDir).existsSync()).toList();
  }

  /// 清理下载目录已不存在的条目，返回清理数量
  Future<int> cleanMissing() async {
    final missing = await listMissing();
    for (final entry in missing) {
      await remove(entry.sourceId);
    }
    return missing.length;
  }
}
