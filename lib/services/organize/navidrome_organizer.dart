import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/organize/audio_tag_writer.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/vtt_to_lrc.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:path/path.dart' as p;

class OrganizeResult {
  final int copied;
  final int skipped;
  final int tagWriteFailures;

  const OrganizeResult({
    required this.copied,
    required this.skipped,
    this.tagWriteFailures = 0,
  });
}

/// 专辑目录名（`<sourceId> - <cvNames> - <title>`）最大码点数
const int kMaxAlbumDirChars = 80;

/// 专辑目录名最大 UTF-8 字节数（防 emoji 等 4 字节字符突破 macOS 255 字节组件限制）
const int kMaxAlbumDirUtf8Bytes = 240;

/// circle 目录名最大码点数
const int kMaxCircleDirChars = 50;

/// circle 目录名最大 UTF-8 字节数
const int kMaxCircleDirUtf8Bytes = 150;

/// 作品在媒体库中的社团展示信息。
///
/// 简体中文版的 API `circle` 通常是翻译组，而媒体库应把日文原版社团
/// 作为主分类；翻译组只作为附加信息保留。
class ResolvedCircleNames {
  const ResolvedCircleNames({
    required this.primary,
    this.translation = '',
    this.originalResolved = false,
  });

  final String primary;
  final String translation;
  final bool originalResolved;
}

/// 将下载的作品整理成 Navidrome 媒体库结构：
/// `<targetRoot>/<circleName>/<sourceId> - <cvNames> - <title>/<sourceId>/`
/// 音轨/字幕/歌词文件扁平化复制，保留原名；封面保存为 cover.jpg（Navidrome 自动识别）。
/// 目录名过长时按字符/字节上限智能截断（保留 sourceId，尾部加 …）。
class NavidromeOrganizer {
  /// 解析整理用的社团名。
  /// 汉化版作品的 circle 是汉化组名，需要跟踪到原版（original_workno）取真实社团名。
  /// [workInfo] 当前作品的 workInfo；[fallbackCircle] 当前作品返回的 circle 名
  /// [fetchWorkInfo] 拉取作品信息（可注入 mock 便于测试）。
  ///
  /// asmr.one 的响应同时存在两套原版关联字段：当前接口通常提供
  /// `original_workno`，也会在 `other_language_editions_in_db` 中提供原版
  /// 条目。两者都处理，避免因某个 API channel/旧缓存缺字段而退回汉化组名。
  static Future<String> resolveCircleName({
    required Map<String, dynamic>? workInfo,
    required String fallbackCircle,
    required Future<Map<String, dynamic>?> Function(String id) fetchWorkInfo,
  }) async {
    final resolved = await resolveCircleNames(
      workInfo: workInfo,
      fallbackCircle: fallbackCircle,
      fetchWorkInfo: fetchWorkInfo,
    );
    return resolved.primary;
  }

  /// 解析主社团和翻译社团。
  ///
  /// [primary] 优先为日文原版社团；无法解析原版时才回退到当前作品的
  /// 社团名。原版关联成功且当前社团名不同，才返回 [translation]。
  static Future<ResolvedCircleNames> resolveCircleNames({
    required Map<String, dynamic>? workInfo,
    required String fallbackCircle,
    required Future<Map<String, dynamic>?> Function(String id) fetchWorkInfo,
  }) async {
    final fallback = fallbackCircle.trim();
    if (workInfo == null) {
      return ResolvedCircleNames(primary: fallback);
    }

    final translationInfo = _asMap(workInfo['translation_info']);
    // 原版作品直接用当前 circle
    if (_isTrue(translationInfo?['is_original'])) {
      return ResolvedCircleNames(primary: fallback, originalResolved: true);
    }

    final candidates = originalWorkCandidates(workInfo);

    // 汉化版：依次拉取候选原版，取原版 circle；单个候选失败不能阻断后续候选。
    for (final candidate in candidates) {
      try {
        final originalInfo = await fetchWorkInfo(candidate);
        final originalCircle = _circleNameFromWorkInfo(originalInfo);
        if (originalCircle.isNotEmpty) {
          Log.info('resolved original circle: $candidate -> $originalCircle');
          return ResolvedCircleNames(
            primary: originalCircle,
            translation: fallback == originalCircle ? '' : fallback,
            originalResolved: true,
          );
        }
      } catch (e) {
        Log.warning('fetch original work failed: $candidate\n' 'error: $e');
      }
    }

    return ResolvedCircleNames(primary: fallback);
  }

  /// 返回当前作品关联的原版候选 sourceId / 数字 id。
  ///
  /// 统一收口字段兼容逻辑，媒体库补全、整理和展示使用同一套判断，避免
  /// 某个 API channel 只提供其中一种字段时出现分类不一致。
  static List<String> originalWorkCandidates(
    Map<String, dynamic>? workInfo,
  ) {
    if (workInfo == null) return const [];

    final translationInfo = _asMap(workInfo['translation_info']);
    if (_isTrue(translationInfo?['is_original'])) return const [];
    final candidates = <String>[];
    void addCandidate(dynamic value) {
      final candidate = value?.toString().trim() ?? '';
      if (candidate.isEmpty || candidates.contains(candidate)) return;
      candidates.add(candidate);
    }

    addCandidate(workInfo['original_workno']);
    addCandidate(translationInfo?['original_workno']);

    final editions = workInfo['other_language_editions_in_db'];
    if (editions is List) {
      for (final edition in editions) {
        final e = _asMap(edition);
        if (!_isTrue(e?['is_original'])) continue;
        // source_id 比内部数字 id 更明确；两者都保留作为兼容降级。
        addCandidate(e?['source_id']);
        addCandidate(e?['id']);
      }
    }

    // 极少数响应没有 original_workno，但仍有语言版本列表；最后尝试日文原版。
    final languageEditions = workInfo['language_editions'];
    if (languageEditions is List) {
      for (final edition in languageEditions) {
        final e = _asMap(edition);
        final lang = e?['lang']?.toString().toUpperCase() ?? '';
        final label = e?['label']?.toString() ?? '';
        if (lang == 'JPN' || label.contains('日本語')) {
          addCandidate(e?['workno']);
        }
      }
    }

    return List.unmodifiable(candidates);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static bool _isTrue(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }

  static String _circleNameFromWorkInfo(Map<String, dynamic>? workInfo) {
    final circle = _asMap(workInfo?['circle']);
    final circleName = circle?['name']?.toString().trim() ?? '';
    if (circleName.isNotEmpty) return circleName;

    // 部分简化/旧接口把社团名放在作品顶层 name。
    return workInfo?['name']?.toString().trim() ?? '';
  }

  /// 生成整理目标作品目录：
  /// `<targetRoot>/<circle>/<sourceId> - <cvNames> - <title>/<sourceId>`。
  ///
  /// 整理执行与整理状态检查都必须使用同一套命名规则，避免长目录名、
  /// 非法字符或空字段导致状态检查指向错误的目录。
  static String targetDirPath({
    required String targetRoot,
    required String circleName,
    required String sourceId,
    required String cvNames,
    required String title,
  }) {
    var circleDirName = getLegalWindowsName(smartTruncate(
        circleName.isEmpty ? cvNames : circleName,
        maxChars: kMaxCircleDirChars,
        maxUtf8Bytes: kMaxCircleDirUtf8Bytes));
    if (circleDirName.isEmpty) circleDirName = sourceId;

    var albumDirName = getLegalWindowsName(smartTruncate(
        [sourceId, cvNames, title].where((s) => s.isNotEmpty).join(' - '),
        maxChars: kMaxAlbumDirChars,
        maxUtf8Bytes: kMaxAlbumDirUtf8Bytes));
    if (albumDirName.isEmpty) albumDirName = sourceId;

    return p.join(targetRoot, circleDirName, albumDirName, sourceId);
  }

  /// 检查整理器会复制的源文件是否仍全部存在于目标作品目录。
  ///
  /// 只检查文件存在性，不比较大小：整理过程中音频可能被写入标签，
  /// 导致目标文件大小与源文件不同。下载器生成的本地封面不参与普通
  /// 文件列表；若该封面存在，则目标端的 `cover.jpg` 是确定的必需产物。
  static Future<bool> hasExpectedFiles({
    required String sourceDir,
    required String targetRoot,
    required String circleName,
    required String sourceId,
    required String cvNames,
    required String title,
  }) async {
    if (targetRoot.trim().isEmpty) return false;

    final source = Directory(sourceDir);
    if (!await source.exists()) return false;

    final targetDir = targetDirPath(
      targetRoot: targetRoot,
      circleName: circleName,
      sourceId: sourceId,
      cvNames: cvNames,
      title: title,
    );
    if (!await Directory(targetDir).exists()) return false;

    final sourceFiles = <File>[];
    await _collectFiles(source, sourceFiles);
    if (sourceFiles.isEmpty) return false;

    for (final sourceFile in sourceFiles) {
      final targetFile = File(p.join(targetDir, p.basename(sourceFile.path)));
      if (!await targetFile.exists()) return false;
    }

    final localCover = File(p.join(sourceDir, '${sourceId}_cover.jpg'));
    if (await localCover.exists() &&
        !await File(p.join(targetDir, 'cover.jpg')).exists()) {
      return false;
    }
    return true;
  }

  /// [sourceDir] 下载的作品目录（`<voiceWorkPath>/<sourceId>`）
  /// [targetRoot] Navidrome 媒体库根目录
  /// [coverBytes] 封面字节，非空时保存为 `cover.jpg`
  /// [artist] 标签 artist 字段（CV 声优名）
  /// [albumArtist] 标签 albumartist 字段（CV 声优名）
  /// [releaseDate] 发行日期（如 2026-06-18），年份写入标签
  /// [genres] 流派标签列表
  ///
  /// 字幕处理：同名 .lrc 直接使用（优先）；同名 .vtt 自动转换为 LRC，
  /// 内嵌为音频歌词标签并额外生成 `<音频名>.lrc` 侧车文件。
  static Future<OrganizeResult> organize({
    required String sourceDir,
    required String targetRoot,
    required String circleName,
    required String sourceId,
    required String cvNames,
    required String title,
    Uint8List? coverBytes,
    String artist = '',
    String albumArtist = '',
    String releaseDate = '',
    List<String> genres = const [],
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      throw StateError('源目录不存在: $sourceDir');
    }

    final targetDir = targetDirPath(
      targetRoot: targetRoot,
      circleName: circleName,
      sourceId: sourceId,
      cvNames: cvNames,
      title: title,
    );

    int copied = 0;
    int skipped = 0;
    int tagWriteFailures = 0;

    // 封面：复用已获取的封面字节，保存为 Navidrome 识别的 cover.jpg
    if (coverBytes != null) {
      final coverFile = File(p.join(targetDir, 'cover.jpg'));
      if (await coverFile.exists() &&
          await coverFile.length() == coverBytes.length) {
        skipped++;
      } else {
        await coverFile.create(recursive: true);
        await coverFile.writeAsBytes(coverBytes);
        copied++;
        Log.info('organize cover: ${coverFile.path}');
      }
    }

    // 收集源目录下所有文件（跳过隐藏文件和下载器生成的 *_cover.jpg）
    final files = <File>[];
    await _collectFiles(source, files);

    // 建立歌词映射：音频引用名 → 歌词文本。
    // 字幕文件命名可能带音频扩展名（"xxx.mp3.vtt" → key "xxx.mp3"）
    // 或不带（"xxx.vtt" → key "xxx"），音频查找时两种 key 都试。
    // 优先级：同名 .lrc > 同名 .vtt 转换结果（lrc 是人工/官方字幕，优先）。
    final lrcMap = <String, String>{};
    final vttMap = <String, String>{};

    Future<void> readSubtitle(File file, String suffix) async {
      final name = p.basename(file.path);
      if (!name.toLowerCase().endsWith(suffix)) return;
      final key = name.substring(0, name.length - suffix.length);
      try {
        final content = await file.readAsString();
        if (suffix == '.lrc') {
          lrcMap[key] = content;
        } else {
          final converted = vttToLrc(content);
          if (converted != null) {
            vttMap[key] = converted;
          }
        }
      } catch (e) {
        Log.warning('read subtitle failed: ${file.path}\n' 'error: $e');
      }
    }

    for (final file in files) {
      await readSubtitle(file, '.lrc');
    }
    for (final file in files) {
      await readSubtitle(file, '.vtt');
    }

    /// 音频文件的歌词：完整名或去扩展名两种 key，lrc 优先于 vtt
    String? lyricsFor(String audioBasename) {
      final base = p.basenameWithoutExtension(audioBasename);
      return lrcMap[audioBasename] ??
          lrcMap[base] ??
          vttMap[audioBasename] ??
          vttMap[base];
    }

    // 扁平化复制到目标目录
    for (final file in files) {
      final targetFile = File(p.join(targetDir, p.basename(file.path)));
      if (await targetFile.exists() &&
          await targetFile.length() == await file.length()) {
        skipped++;
      } else {
        await targetFile.create(recursive: true);
        await file.copy(targetFile.path);
        copied++;
      }

      // 音频文件写标签（title/artist/album/albumartist/track/内嵌歌词/内嵌封面/年份/流派）
      if (AudioTagWriter.isAudioFile(targetFile.path)) {
        final audioName = p.basename(file.path);
        final base = p.basenameWithoutExtension(audioName);
        final lyrics = lyricsFor(audioName);

        // VTT 转换出的歌词额外生成为 .lrc 侧车文件
        // （供 mp3tag 等其他工具使用；已有真实 .lrc 时跳过，避免覆盖）
        final hasRealLrc =
            lrcMap.containsKey(audioName) || lrcMap.containsKey(base);
        if (lyrics != null &&
            !hasRealLrc &&
            (vttMap.containsKey(audioName) || vttMap.containsKey(base))) {
          final lrcFile = File(p.join(targetDir, '$audioName.lrc'));
          final existing =
              await lrcFile.exists() ? await lrcFile.readAsString() : null;
          if (existing == lyrics) {
            skipped++;
          } else {
            await lrcFile.writeAsString(lyrics);
            copied++;
            Log.info('organize lrc from vtt: ${lrcFile.path}');
          }
        }

        final track = _parseTrackNumber(audioName);
        final tagOk = await AudioTagWriter.writeTags(
          targetFile.path,
          title: base,
          artist: artist,
          album: title,
          albumArtist: albumArtist,
          track: track,
          // 内嵌歌词：同名 LRC 或 VTT 转换结果（wav 不支持则自动跳过）
          lyrics: lyrics,
          // 专辑封面嵌入每首歌（wav 不支持则自动跳过）
          coverBytes: coverBytes,
          // 发行年份（releaseDate 取前 4 位）
          year: releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null,
          // 流派（前 3 个，防止字段过长）
          genre: genres.take(3).join('; '),
        );
        if (!tagOk) tagWriteFailures++;
      }
    }

    Log.info('organize completed: copied $copied, skipped $skipped, '
        'tagWriteFailures $tagWriteFailures\n'
        'targetDir: $targetDir');
    return OrganizeResult(
      copied: copied,
      skipped: skipped,
      tagWriteFailures: tagWriteFailures,
    );
  }

  /// 从文件名解析 track number（如 "01 xxx.wav" → "1"），无法解析返回 null
  static String? _parseTrackNumber(String fileName) {
    final match = RegExp(r'^(\d+)').firstMatch(fileName);
    if (match == null) return null;
    return int.parse(match.group(1)!).toString();
  }

  static Future<void> _collectFiles(Directory dir, List<File> result) async {
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        await _collectFiles(entity, result);
      } else if (entity is File) {
        final name = p.basename(entity.path);
        // 跳过隐藏文件（如 .DS_Store）和下载器生成的封面
        if (name.startsWith('.') || name.endsWith('_cover.jpg')) {
          continue;
        }
        result.add(entity);
      }
    }
  }
}
