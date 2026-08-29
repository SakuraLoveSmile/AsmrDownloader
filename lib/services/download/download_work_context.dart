import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 下载开始时对作品上下文的不可变快照。
///
/// 下载中允许搜索新作品；任务收集、封面落盘、注册表写入、自动整理、
/// 自动字幕等所有后续处理一律只使用本快照，禁止再读取
/// sourceIdProvider / titleProvider / coverBytesProvider 等搜索页状态，
/// 避免下载作品 A 时搜索作品 B 导致后续步骤串到 B 的数据。
class DownloadWorkContext {
  const DownloadWorkContext({
    required this.sourceId,
    required this.title,
    required this.cvNames,
    required this.circleName,
    required this.releaseDate,
    required this.tags,
    required this.coverUrl,
    required this.coverBytes,
    required this.downloadRoot,
    required this.workDir,
  });

  final String sourceId;
  final String title;
  final List<String> cvNames;
  final String circleName;
  final String releaseDate;
  final List<String> tags;
  final String coverUrl;

  /// 快照时刻已就绪的封面字节；未就绪时为 null，按 [coverUrl] 兜底拉取
  final Uint8List? coverBytes;

  /// 下载根目录
  final String downloadRoot;

  /// 本作品的下载目录（`<downloadRoot>/<cv-title>`）
  final String workDir;

  /// 作品下载内容目录（`<workDir>/<sourceId>`）
  String get sourceDir => p.join(workDir, sourceId);
}
