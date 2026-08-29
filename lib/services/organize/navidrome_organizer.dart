import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/organize/audio_tag_writer.dart';
import 'package:asmr_downloader/services/transcribe/subtitle_matcher.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/vtt_to_lrc.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:path/path.dart' as p;

class OrganizeResult {
  final int copied;
  final int skipped;
  final int tagWriteFailures;

  /// 本次整理实际写入的作品目录（最内层 `<sourceId>/` 绝对路径）。
  /// 供整理服务做 staging 事务替换等后续流程使用。
  final String targetDir;

  const OrganizeResult({
    required this.copied,
    required this.skipped,
    this.tagWriteFailures = 0,
    required this.targetDir,
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
  /// 计算源文件在整理目标目录内的相对路径。
  ///
  /// [keepDirStructure] 为 true 时保留作品内子目录（disc1/disc2 等），
  /// 用 [sourceFile] 相对 [sourceDir] 的路径；为 false 时扁平化，只取 basename。
  /// 整理执行与状态检查必须使用同一规则，否则「仅整理未整理的」判断会错位。
  static String _targetSubPath(
    File sourceFile,
    String sourceDir,
    bool keepDirStructure,
  ) {
    return keepDirStructure
        ? p.relative(sourceFile.path, from: sourceDir)
        : p.basename(sourceFile.path);
  }

  /// 扁平化布局是否会发生同名覆盖：不同子目录存在相同 basename 的文件
  /// （如 disc1/01.wav 与 disc2/01.wav）。整理与 [hasExpectedFiles] 必须
  /// 使用同一判定；冲突时统一回退为保留目录结构，绝不静默覆盖。
  static bool flattenHasCollision(List<File> sourceFiles, String sourceDir) {
    final basenameCounts = <String, int>{};
    for (final file in sourceFiles) {
      final base = p.basename(file.path);
      basenameCounts[base] = (basenameCounts[base] ?? 0) + 1;
    }
    return basenameCounts.values.any((count) => count > 1);
  }

  static Future<bool> hasExpectedFiles({
    required String sourceDir,
    required String targetRoot,
    required String circleName,
    required String sourceId,
    required String cvNames,
    required String title,
    bool keepDirStructure = false,
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

    // 与 organize 相同的扁平冲突回退规则：冲突时目标布局是保留目录结构，
    // 状态检查必须按同一规则指向真实布局，否则「仅整理未整理的」会错位。
    final effectiveKeepDirStructure =
        keepDirStructure || flattenHasCollision(sourceFiles, sourceDir);

    for (final sourceFile in sourceFiles) {
      final targetFile = File(p.join(
        targetDir,
        _targetSubPath(sourceFile, sourceDir, effectiveKeepDirStructure),
      ));
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
  /// [forceWavRewrite] 强制重写 wav 标签（剥离已有 'id3 ' chunk 后重写），
  /// 供整理产物校验修复路径补齐缺失的歌词/封面；mp3/flac 本来就整体重写。
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
    bool keepDirStructure = false,
    bool forceWavRewrite = false,
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

    // 收集源目录下所有文件（跳过隐藏文件和下载器生成的 *_cover.jpg）
    final files = <File>[];
    await _collectFiles(source, files);

    // 扁平化冲突检测：不同子目录同名文件在扁平复制时会静默覆盖，
    // 冲突时自动回退为保留目录结构（hasExpectedFiles 使用同一规则）。
    var effectiveKeepDirStructure = keepDirStructure;
    if (!effectiveKeepDirStructure && flattenHasCollision(files, sourceDir)) {
      Log.warning('flatten collision detected, fallback to keep directory '
          'structure: $sourceDir');
      effectiveKeepDirStructure = true;
    }

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

    // 建立字幕匹配：统一走 [SubtitleMatcher]（相对路径优先，basename
    // 全作品唯一才回退），disc1/01.vtt 不会错误绑定 disc2/01.wav。
    // 字幕内容以文件路径为 key，由 matcher 负责音频 ↔ 字幕绑定。
    final lrcContents = <String, String>{};
    final vttContents = <String, String>{};

    Future<void> readSubtitle(File file, String suffix) async {
      final name = p.basename(file.path);
      if (!name.toLowerCase().endsWith(suffix)) return;
      try {
        final content = await file.readAsString();
        if (suffix == '.lrc') {
          lrcContents[file.path] = content;
        } else {
          final converted = vttToLrc(content);
          if (converted != null) {
            vttContents[file.path] = converted;
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

    final matcher = SubtitleMatcher(
      sourceDir: sourceDir,
      audioPaths: [
        for (final file in files)
          if (AudioTagWriter.isAudioFile(file.path)) file.path,
      ],
      subtitlePaths: [...lrcContents.keys, ...vttContents.keys],
    );

    /// 音频文件的歌词：绑定字幕中 lrc 优先于 vtt（转换结果）
    String? lyricsFor(String audioPath) {
      String? lrc;
      String? vtt;
      for (final subtitle in matcher.subtitlesFor(audioPath)) {
        final lrcText = lrcContents[subtitle];
        if (lrcText != null) {
          lrc ??= lrcText;
          continue;
        }
        final vttText = vttContents[subtitle];
        if (vttText != null) {
          vtt ??= vttText;
        }
      }
      return lrc ?? vtt;
    }

    /// 是否绑定了真实 .lrc（有真实 .lrc 时不生成 vtt 转换的侧车文件）
    bool hasRealLrc(String audioPath) => matcher
        .subtitlesFor(audioPath)
        .any((subtitle) => subtitle.toLowerCase().endsWith('.lrc'));

    // 复制（冲突回退后的 effectiveKeepDirStructure 决定布局）
    for (final file in files) {
      final rel = _targetSubPath(file, sourceDir, effectiveKeepDirStructure);
      final targetFile = File(p.join(targetDir, rel));
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
        final lyrics = lyricsFor(file.path);

        // VTT 转换出的歌词额外生成为 .lrc 侧车文件
        // （供 mp3tag 等其他工具使用；已有真实 .lrc 时跳过，避免覆盖）
        // 侧车文件跟随音频所在目录：扁平化时位于作品根，保留结构时位于
        // 音频对应的子目录。
        final realLrc = hasRealLrc(file.path);
        if (lyrics != null && !realLrc) {
          final lrcDir = p.dirname(rel);
          final lrcFile = File(p.join(targetDir, lrcDir, '$audioName.lrc'));
          final existing =
              await lrcFile.exists() ? await lrcFile.readAsString() : null;
          if (existing == lyrics) {
            skipped++;
          } else {
            await lrcFile.create(recursive: true);
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
// 内嵌歌词：同名 LRC 或 VTT 转换结果（mp3→USLT / flac→LYRICS / wav→id3 USLT）
          lyrics: lyrics,
          // 专辑封面嵌入每首歌（mp3→APIC / flac→PICTURE / wav→id3 APIC）
          coverBytes: coverBytes,
          // 发行年份（releaseDate 取前 4 位）
          year: releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null,
          // 流派（前 3 个，防止字段过长）
          genre: genres.take(3).join('; '),
          // 校验修复路径：剥离 wav 旧标签后重写，补齐缺失歌词/封面
          forceWavRewrite: forceWavRewrite,
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
      targetDir: targetDir,
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

  /// 递归扫描 [targetRoot]，找出所有 basename **精确等于** [sourceId] 的目录。
  ///
  /// 整理目标结构为：
  /// `<targetRoot>/<circle>/<sourceId> - <cv> - <title>/<sourceId>`
  /// 只需匹配最内层 `<sourceId>/` 即可定位该作品在任意旧 Circle / Album
  /// 命名下的历史整理产物。
  ///
  /// - 最大扫描深度（默认 5）防止异常嵌套目录导致的失控遍历；
  /// - 跳过隐藏目录（basename 以 `.` 开头）与 symlink（不跟随）；
  /// - 只做精确匹配，不使用前缀或模糊匹配，避免误删 `RJ1234` /
  ///   `XRJ123` / `RJ123 - title` 等相邻目录；
  /// - 返回路径统一执行 `absolute + normalize`。
  static Future<List<String>> findWorkTargetDirs({
    required String targetRoot,
    required String sourceId,
  }) async {
    final root = Directory(p.absolute(p.normalize(targetRoot)));
    if (!await root.exists()) return const [];
    final matches = <String>[];
    await _scanForSourceIdDir(root, sourceId, 0, 5, matches);
    return matches;
  }

  static Future<void> _scanForSourceIdDir(
    Directory dir,
    String sourceId,
    int depth,
    int maxDepth,
    List<String> matches,
  ) async {
    if (depth >= maxDepth) return;
    await for (final entity in dir.list()) {
      // 跳过文件与非目录实体
      if (entity is! Directory) continue;
      // 不跟随 symlink（部分平台 list 会把指向目录的 symlink 报告为 Directory，
      // 因此显式用 isLink 兜底拦截，避免误删/误扫软链目标）
      if (await FileSystemEntity.isLink(entity.path)) continue;
      final name = p.basename(entity.path);
      // 跳过隐藏目录（其下的产物也不应被扫描到）
      if (name.startsWith('.')) continue;
      if (name == sourceId) {
        // 命中作品目录：路径规范化后记录，不再深入（内部仅文件）
        matches.add(p.absolute(p.normalize(entity.path)));
        continue;
      }
      await _scanForSourceIdDir(entity, sourceId, depth + 1, maxDepth, matches);
    }
  }

  /// 删除 [targetRoot] 内 [sourceId] 的全部既有整理产物（最内层 `<sourceId>/`）。
  ///
  /// 删除前会再次确认目标路径严格位于 [targetRoot] 内，且绝不删除
  /// [targetRoot] 本身；对匹配目录执行 `delete(recursive: true)` 后，向上
  /// 清理空父目录直到 [targetRoot] 为止，遇到非空父目录立即停止。
  /// 每个删除操作记录日志，返回实际删除的作品目录数量。
  static Future<int> deleteWorkTargetDirs({
    required String targetRoot,
    required String sourceId,
  }) async {
    final root = Directory(p.absolute(p.normalize(targetRoot)));
    final dirs = await findWorkTargetDirs(
      targetRoot: targetRoot,
      sourceId: sourceId,
    );

    var deleted = 0;
    for (final dir in dirs) {
      final normalized = p.absolute(p.normalize(dir));
      // 再次确认：路径位于 targetRoot 内，且不是 targetRoot 本身
      if (p.equals(root.path, normalized)) {
        Log.warning('deleteWorkTargetDirs: refuse to delete targetRoot itself '
            '($dir)');
        continue;
      }
      if (!p.isWithin(root.path, normalized)) {
        Log.warning('deleteWorkTargetDirs: skip unsafe path $dir '
            '(not within $targetRoot)');
        continue;
      }

      final target = Directory(normalized);
      try {
        await target.delete(recursive: true);
        deleted++;
        Log.info('deleteWorkTargetDirs: deleted $normalized');
        // 向上清理空父目录到 targetRoot 为止
        await _cleanupEmptyParents(target, root);
      } catch (e) {
        Log.warning('deleteWorkTargetDirs: failed to delete $normalized\n'
            'error: $e');
      }
    }
    return deleted;
  }

  /// 删除 [dir] 后向上清理空父目录，直到 [root]（含）为止。
  /// 遇到非空父目录或父目录超出 [root] 范围立即停止。
  /// 导出为公开方法：整理服务的 staging 替换流程清理备份后复用。
  static Future<void> cleanupEmptyParentsUpTo(
    Directory dir,
    Directory root,
  ) async {
    return _cleanupEmptyParents(dir, root);
  }

  static Future<void> _cleanupEmptyParents(
    Directory dir,
    Directory root,
  ) async {
    final rootPath = p.absolute(p.normalize(root.path));
    var parent = dir.parent;
    while (true) {
      final parentPath = p.absolute(p.normalize(parent.path));
      // 到达 root 为止：绝不删除 root 本身
      if (p.equals(parentPath, rootPath)) break;
      // 安全边界：父目录不再位于 root 内时立即停止
      if (!p.isWithin(rootPath, parentPath)) break;

      final children = await parent.list().toList();
      if (children.isEmpty) {
        Log.info('deleteWorkTargetDirs: cleanup empty parent ${parent.path}');
        await parent.delete();
        parent = parent.parent;
      } else {
        // 遇到非空父目录立即停止（可能含其他作品/目录）
        break;
      }
    }
  }
}
