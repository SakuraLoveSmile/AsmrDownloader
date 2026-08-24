import 'dart:io';

import 'package:asmr_downloader/services/organize/audio_tag_writer.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/vtt_to_lrc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:taglib_dart/taglib_dart.dart';

/// 单个作品的整理产物校验结果（内嵌歌词/封面缺失判定）。
///
/// 缺陷判定规则（「该有但没有」才算缺陷）：
/// - 缺歌词：源目录存在该音频的同名 `.lrc`/`.vtt`（key 规则与
///   [NavidromeOrganizer.organize] 完全一致），但目标音频读不到内嵌歌词；
///   无歌词源不算缺陷。
/// - 缺封面：源目录有 `<sourceId>_cover.jpg` 或注册表 `coverUrl` 非空，
///   但目标音频读不到内嵌封面 / 目标目录缺 `cover.jpg`。
class VerifyWorkResult {
  final String sourceId;

  /// 目标作品目录是否存在（false = 整理产物不存在）
  final bool targetFound;

  /// 校验过的音频数（mp3/flac/wav）
  final int checkedAudio;

  /// 有歌词源但未内嵌歌词的音频数
  final int missingLyrics;

  /// 有封面源但未内嵌封面的音频数
  final int missingCover;

  /// 标签读取失败的音频数
  final int readErrors;

  /// 有封面源但目标目录缺 cover.jpg
  final bool coverJpgMissing;

  /// 源目录是否存在至少一个带歌词源（同名 .lrc/.vtt）的音频
  final bool hasLyricsSource;

  /// 是否存在封面源（本地 `<sourceId>_cover.jpg` 或注册表 coverUrl）
  final bool hasCoverSource;

  /// 带第三方 LIST/INFO 曲名标签（无 id3 chunk）的 wav 数：
  /// 本工具不覆盖此类文件，内嵌缺失不可修复
  final int skippedThirdParty;

  /// 人读缺陷摘要（如「3 首缺内嵌歌词」「封面未嵌入」）
  final List<String> problems;

  const VerifyWorkResult({
    required this.sourceId,
    required this.targetFound,
    required this.checkedAudio,
    required this.missingLyrics,
    required this.missingCover,
    required this.readErrors,
    required this.coverJpgMissing,
    required this.hasLyricsSource,
    required this.hasCoverSource,
    required this.skippedThirdParty,
    required this.problems,
  });

  /// 目标产物齐全、标签读取正常，且没有不可重写的第三方标签 wav。
  bool get ok =>
      targetFound &&
      missingLyrics == 0 &&
      missingCover == 0 &&
      readErrors == 0 &&
      !coverJpgMissing &&
      skippedThirdParty == 0;

  /// 是否可通过重新整理修复（重跑 organizeEntry forceWavRewrite 会重新拉
  /// 封面、重写全部音频标签；第三方标签 wav 与产物缺失不在修复范围）。
  bool get repairable =>
      targetFound && (missingLyrics > 0 || missingCover > 0 || coverJpgMissing);

  /// 校验摘要：「校验通过」或缺陷列表（如「2 首缺歌词、封面 cover.jpg 缺失」）。
  String get summary {
    if (ok) return '校验通过';
    final parts = <String>[];
    if (!targetFound) parts.add('整理产物不存在');
    if (missingLyrics > 0) parts.add('$missingLyrics 首缺歌词');
    if (missingCover > 0) parts.add('$missingCover 首封面未嵌入');
    if (coverJpgMissing) parts.add('封面 cover.jpg 缺失');
    if (readErrors > 0) parts.add('$readErrors 个标签读取失败');
    if (skippedThirdParty > 0) parts.add('$skippedThirdParty 个 wav 第三方标签不可重写');
    return parts.join('、');
  }
}

/// 整理产物校验服务：逐作品检查目标音频的内嵌歌词/封面
/// （mp3/flac 用 taglib 读取，wav 扫描 'id3 ' chunk），只读不修改文件。
class VerifyService {
  final Ref ref;
  VerifyService(this.ref);

  /// 校验单个作品的整理产物。
  /// 目标目录用 [NavidromeOrganizer.targetDirPath]（与 isOrganized
  /// 同一命名规则），递归遍历目标目录音频文件。
  Future<VerifyWorkResult> verifyWork(
    WorkEntry entry, {
    required String targetRoot,
    bool keepDirStructure = false,
  }) async {
    final targetDir = NavidromeOrganizer.targetDirPath(
      targetRoot: targetRoot,
      circleName: entry.circleName,
      sourceId: entry.sourceId,
      cvNames: entry.cvNames,
      title: entry.title,
    );

    if (!Directory(targetDir).existsSync()) {
      return VerifyWorkResult(
        sourceId: entry.sourceId,
        targetFound: false,
        checkedAudio: 0,
        missingLyrics: 0,
        missingCover: 0,
        readErrors: 0,
        coverJpgMissing: false,
        hasLyricsSource: false,
        hasCoverSource: false,
        skippedThirdParty: 0,
        problems: const ['整理产物不存在：目标目录缺失'],
      );
    }

    // 源目录歌词 key（与 NavidromeOrganizer.organize 的 lrcMap/vttMap 完全一致：
    // 带扩展名与不带扩展名两种 key；.vtt 仅计入可成功转换的）
    final lrcKeys = <String>{};
    final vttKeys = <String>{};
    final sourceDir = Directory(entry.sourceDir);
    if (sourceDir.existsSync()) {
      final files = <File>[];
      await _collectFiles(sourceDir, files);
      for (final file in files) {
        final name = p.basename(file.path);
        final lower = name.toLowerCase();
        if (lower.endsWith('.lrc')) {
          lrcKeys.add(name.substring(0, name.length - 4));
        } else if (lower.endsWith('.vtt')) {
          final key = name.substring(0, name.length - 4);
          try {
            if (vttToLrc(await file.readAsString()) != null) {
              vttKeys.add(key);
            }
          } catch (e) {
            Log.warning('verify: read vtt failed: ${file.path}\n' 'error: $e');
          }
        }
      }
    }

    // 封面源：下载器落盘的本地封面，或注册表记录的在离线封面 URL
    final hasCoverSource = entry.coverUrl.trim().isNotEmpty ||
        File(p.join(entry.sourceDir, '${entry.sourceId}_cover.jpg'))
            .existsSync();

    var checkedAudio = 0;
    var missingLyrics = 0;
    var missingCover = 0;
    var readErrors = 0;
    var skippedThirdParty = 0;
    var hasLyricsSource = false;

    final targetFiles = <File>[];
    await _collectFiles(Directory(targetDir), targetFiles);
    for (final file in targetFiles) {
      if (!AudioTagWriter.isAudioFile(file.path)) continue;
      checkedAudio++;
      final name = p.basename(file.path);
      final base = p.basenameWithoutExtension(name);
      final hasLrc = lrcKeys.contains(name) ||
          lrcKeys.contains(base) ||
          vttKeys.contains(name) ||
          vttKeys.contains(base);
      if (hasLrc) hasLyricsSource = true;

      // 第三方 LIST/INFO 曲名标签（无 id3 chunk）的 wav：本工具不重写，
      // 内嵌缺失归为不可修复（只用报告说明，不计入可修复缺陷）。
      if (file.path.toLowerCase().endsWith('.wav') &&
          await AudioTagWriter.isThirdPartyTaggedWav(file.path)) {
        if (hasLrc || hasCoverSource) skippedThirdParty++;
        continue;
      }

      try {
        final embed = await _readEmbedded(file.path);
        if (hasLrc && !embed.lyrics) missingLyrics++;
        if (hasCoverSource && !embed.cover) missingCover++;
      } catch (e) {
        // 单个文件读取失败不中断校验，计入 readErrors
        readErrors++;
        Log.warning('verify: read tags failed: ${file.path}\n' 'error: $e');
      }
    }

    final coverJpgMissing =
        hasCoverSource && !File(p.join(targetDir, 'cover.jpg')).existsSync();

    final problems = <String>[];
    if (missingLyrics > 0) problems.add('$missingLyrics 首缺内嵌歌词');
    if (missingCover > 0) problems.add('$missingCover 首未嵌入封面');
    if (coverJpgMissing) problems.add('封面 cover.jpg 缺失');
    if (readErrors > 0) problems.add('$readErrors 个音频标签读取失败');
    if (skippedThirdParty > 0) {
      problems.add('$skippedThirdParty 个 wav 带第三方标签，无法重写');
    }

    return VerifyWorkResult(
      sourceId: entry.sourceId,
      targetFound: true,
      checkedAudio: checkedAudio,
      missingLyrics: missingLyrics,
      missingCover: missingCover,
      readErrors: readErrors,
      coverJpgMissing: coverJpgMissing,
      hasLyricsSource: hasLyricsSource,
      hasCoverSource: hasCoverSource,
      skippedThirdParty: skippedThirdParty,
      problems: problems,
    );
  }

  /// 读取单个音频的内嵌歌词/封面状态；wav 走 id3 chunk 扫描，mp3/flac 用 taglib。
  static Future<({bool lyrics, bool cover})> _readEmbedded(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return AudioTagWriter.readWavEmbed(path);
    final bytes = await File(path).readAsBytes();
    final format = lower.endsWith('.flac') ? Format.flac : Format.mp3;
    final audio = AudioFile(bytes, format);
    final lyric = audio.getLyric();
    final cover = audio.getCover();
    return (
      lyrics: lyric != null && lyric.trim().isNotEmpty,
      cover: cover != null && cover.isNotEmpty,
    );
  }

  /// 递归收集文件（跳过隐藏文件与下载器生成的 *_cover.jpg，与整理器一致）。
  static Future<void> _collectFiles(Directory dir, List<File> result) async {
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        await _collectFiles(entity, result);
      } else if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') || name.endsWith('_cover.jpg')) continue;
        result.add(entity);
      }
    }
  }
}