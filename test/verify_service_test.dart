import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/organize/audio_tag_writer.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/verify_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 最小可被 taglib_dart 解析的 mp3：ID3v2 头 + MPEG 帧标记
/// （Mp3File 仅在 >10 处找到 0xFF 0xEx 帧时解析头部 ID3 帧区）
Uint8List buildMinimalMp3() {
  return Uint8List.fromList([
    0xFF, 0xFB, 0x90, 0x00, // MPEG1 Layer3 帧头
    ...List<int>.filled(60, 0),
  ]);
}

/// 最小合法 wav（RIFF/WAVE 头，AudioTagWriter 可识别并写标签）
Uint8List _buildMinimalWav() {
  final fmt = Uint8List.fromList([
    0x01, 0x00, // PCM
    0x01, 0x00, // mono
    0x40, 0x1F, 0x00, 0x00, // 8000Hz
    0x80, 0x3E, 0x00, 0x00, // 16000B/s
    0x02, 0x00, // block align
    0x10, 0x00, // 16bit
  ]);
  final data = List<int>.filled(16, 0);
  final fmtChunk = <int>[
    ...'fmt '.codeUnits,
    ..._u32le(fmt.length),
    ...fmt,
  ];
  final dataChunk = <int>[
    ...'data'.codeUnits,
    ..._u32le(data.length),
    ...data,
  ];
  final body = Uint8List.fromList([...fmtChunk, ...dataChunk]);
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._u32le(4 + body.length),
    ...'WAVE'.codeUnits,
    ...body,
  ]);
}

Uint8List _u32le(int v) => Uint8List.fromList(
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

void main() {
  late Directory base;
  late Directory sourceDir;
  late Directory targetRoot;
  const sourceId = 'RJ12345678';
  final cover = Uint8List.fromList(List.filled(80, 9));

  /// 构造与源目录对应的注册表条目（sourceDir = <dlPath>/<dirName>/<sourceId>）
  WorkEntry entry({
    String circle = '社团',
    String title = '标题',
    String cvNames = 'CV1',
    String coverUrl = '',
  }) =>
      WorkEntry(
        sourceId: sourceId,
        dlPath: p.join(base.path, '社团-标题'),
        dirName: '',
        title: title,
        cvNames: cvNames,
        circleName: circle,
        coverUrl: coverUrl,
      );

  setUp(() {
    base = Directory.systemTemp.createTempSync('verify_test');
    sourceDir = Directory(p.join(base.path, '社团-标题', sourceId))
      ..createSync(recursive: true);
    targetRoot = Directory(p.join(base.path, 'navidrome'))..createSync();
  });

  tearDown(() {
    base.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  /// 用与入口一致的参数执行整理（源：mp3 + 可选 lrc + 可选本地封面）
  Future<void> organize({
    bool withCover = true,
    bool withLrc = false,
    bool withVtt = false,
    bool wav = false,
  }) async {
    final ext = wav ? 'wav' : 'mp3';
    File(p.join(sourceDir.path, '01_track.$ext'))
        .writeAsBytesSync(wav ? _buildMinimalWav() : buildMinimalMp3());
    if (withVtt) {
      File(p.join(sourceDir.path, '01_track.$ext.vtt'))
          .writeAsStringSync('WEBVTT\n\n00:01.000 --> 00:02.000\n台词');
    }
    if (withLrc) {
      File(p.join(sourceDir.path, '01_track.$ext.lrc'))
          .writeAsStringSync('[00:01.00]歌词');
    }
    if (withCover) {
      File(p.join(sourceDir.path, '${sourceId}_cover.jpg'))
          .writeAsBytesSync(cover);
    }
    await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '社团',
      sourceId: sourceId,
      cvNames: 'CV1',
      title: '标题',
      coverBytes: withCover ? cover : null,
    );
  }

  Future<VerifyWorkResult> verify(
      ProviderContainer container, WorkEntry e) {
    return container
        .read(verifyServiceProvider)
        .verifyWork(e, targetRoot: targetRoot.path);
  }

  test('正常整理后校验通过（mp3 带歌词+封面）', () async {
    await organize(withLrc: true);

    final result = await verify(makeContainer(), entry());

    expect(result.targetFound, true);
    expect(result.checkedAudio, 1);
    expect(result.missingLyrics, 0);
    expect(result.missingCover, 0);
    expect(result.coverJpgMissing, false);
    expect(result.readErrors, 0);
    expect(result.hasLyricsSource, true);
    expect(result.hasCoverSource, true);
    expect(result.ok, true);
    expect(result.problems, isEmpty);
  });

  test('源有 lrc 但目标 mp3 无 USLT → 检出 missingLyrics 且可修复', () async {
    // 整理时歌词尚未生成（无 lrc）
    await organize(withLrc: false);
    // 之后才跑 AI 字幕，源目录补上 lrc，但目标音频没有内嵌歌词
    File(p.join(sourceDir.path, '01_track.mp3.lrc'))
        .writeAsStringSync('[00:01.00]歌词');

    final result = await verify(makeContainer(), entry());

    expect(result.missingLyrics, 1);
    expect(result.hasLyricsSource, true);
    expect(result.ok, false);
    expect(result.repairable, true);
    expect(result.problems, contains('1 首缺内嵌歌词'));
  });

  test('有封面源但目标无 APIC/cover.jpg → 检出 missingCover/coverJpgMissing',
        () async {
      // 源有本地封面，但整理时封面拉取失败（未提供 coverBytes）
      File(p.join(sourceDir.path, '01_track.mp3'))
          .writeAsBytesSync(buildMinimalMp3());
      File(p.join(sourceDir.path, '${sourceId}_cover.jpg'))
          .writeAsBytesSync(cover);
      await NavidromeOrganizer.organize(
        sourceDir: sourceDir.path,
        targetRoot: targetRoot.path,
        circleName: '社团',
        sourceId: sourceId,
        cvNames: 'CV1',
        title: '标题',
        coverBytes: null, // 模拟封面拉取失败
      );

      final result = await verify(makeContainer(), entry());

      expect(result.hasCoverSource, true);
      expect(result.missingCover, 1);
      expect(result.coverJpgMissing, true);
      expect(result.ok, false);
      expect(result.repairable, true);
      expect(result.problems, contains('1 首未嵌入封面'));
      expect(result.problems, contains('封面 cover.jpg 缺失'));
    });

  test('无歌词源时缺嵌入不算缺陷（hasLyricsSource=false）', () async {
    await organize(withLrc: false);

    final result = await verify(makeContainer(), entry());

    expect(result.missingLyrics, 0);
    expect(result.hasLyricsSource, false);
    expect(result.ok, true);
  });

  test('注册表 coverUrl 非空即视为封面源（即使本地无封面）', () async {
    await organize(withLrc: true);

    // 本地封面已被删除，但注册表记录在线封面 URL
    File(p.join(sourceDir.path, '${sourceId}_cover.jpg')).deleteSync();
    final result =
        await verify(makeContainer(), entry(coverUrl: 'https://x/cover.jpg'));

    expect(result.hasCoverSource, true);
    // 目标 cover.jpg 与内嵌封面都在（整理时已写入），不应误报
    expect(result.missingCover, 0);
    expect(result.coverJpgMissing, false);
    expect(result.ok, true);
  });

  test('目标目录不存在 → targetFound=false、不可修复', () async {
    final result = await verify(makeContainer(), entry());

    expect(result.targetFound, false);
    expect(result.checkedAudio, 0);
    expect(result.ok, false);
    expect(result.repairable, false);
    expect(result.problems, ['整理产物不存在：目标目录缺失']);
  });

  test('vtt 字幕源同样计入歌词源（key 规则与 organize 一致）', () async {
    await organize(withVtt: true);

    final result = await verify(makeContainer(), entry());

    expect(result.missingLyrics, 0);
    expect(result.hasLyricsSource, true);
    expect(result.ok, true);
  });

  test('第三方 LIST/INFO INAM 的 wav 缺失归为不可修复并报告', () async {
    // 源 wav 被其他工具打过 LIST/INFO 曲名标签（无 id3），整理时跳过不写
    File(p.join(sourceDir.path, '01_track.wav'))
        .writeAsBytesSync(appendChunkWav(buildListChunkWav()));
    File(p.join(sourceDir.path, '01_track.wav.lrc'))
        .writeAsStringSync('[00:01.00]歌词');
    File(p.join(sourceDir.path, '${sourceId}_cover.jpg'))
        .writeAsBytesSync(cover);

    await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '社团',
      sourceId: sourceId,
      cvNames: 'CV1',
      title: '标题',
      coverBytes: cover,
    );

    final result = await verify(makeContainer(), entry());

    expect(result.skippedThirdParty, 1);
    expect(result.missingLyrics, 0);
    expect(result.missingCover, 0);
    expect(result.ok, false); // 缺失不可修复，报告中说明
    expect(result.repairable, false);
    expect(result.problems, contains('1 个 wav 带第三方标签，无法重写'));
    expect(result.summary, contains('1 个 wav 第三方标签不可重写'));
  });

  test('wav 修复流程：源自带无歌词 id3 → forceWavRewrite 重写后校验通过', () async {
    // 源 wav 自带 id3 标签（如购买源文件已打标签，无 USLT），
    // 整理时目标尺寸与源相同，复制被跳过、写标签幂等跳过 —— 普通重整理修不好
    final srcWav = File(p.join(sourceDir.path, '01_track.wav'))
      ..writeAsBytesSync(_buildMinimalWav());
    await AudioTagWriter.writeTags(
      srcWav.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
    );
    File(p.join(sourceDir.path, '${sourceId}_cover.jpg'))
        .writeAsBytesSync(cover);
    await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '社团',
      sourceId: sourceId,
      cvNames: 'CV1',
      title: '标题',
      coverBytes: cover,
    );
    // 之后 AI 字幕生成 lrc
    File(p.join(sourceDir.path, '01_track.wav.lrc'))
        .writeAsStringSync('[00:01.00]歌词');

    final container = makeContainer();
    final e = entry();
    final organizer = container.read(organizeServiceProvider);

    // 修复前：缺歌词 + 缺封面（源自带 id3 无 USLT/APIC）
    final before = await verify(container, e);
    expect(before.missingLyrics, 1);
    expect(before.missingCover, 1);

    // 普通重新整理：复制被跳过（尺寸相同）、写标签幂等跳过 → 仍是缺陷
    await organizer.organizeEntry(
      e,
      targetRoot: targetRoot.path,
      fetchWorkInfo: false,
    );
    final afterNormal = await verify(container, e);
    expect(afterNormal.missingLyrics, 1);
    expect(afterNormal.missingCover, 1);

    // forceWavRewrite 修复：剥离旧 id3 chunk 重写 → 歌词/封面全部生效
    final outcome = await organizer.organizeEntry(
      e,
      targetRoot: targetRoot.path,
      fetchWorkInfo: false,
      forceWavRewrite: true,
    );
    final afterRepair = await verify(container, e);
    expect(afterRepair.missingLyrics, 0);
    expect(afterRepair.missingCover, 0);
    expect(afterRepair.coverJpgMissing, false);
    expect(afterRepair.ok, true);
    expect(afterRepair.repairable, false);
    expect(outcome.verifyNote, '校验通过');
  });
}

/// 构造带 LIST/INFO INAM 的 wav（第三方标签场景）
Uint8List buildListChunkWav() {
  const value = '他人标题';
  final data = [...'INAM'.codeUnits, ..._u32le(value.length), ...value.codeUnits];
  final listData = [...'INFO'.codeUnits, ...data];
  return Uint8List.fromList([
    ...'LIST'.codeUnits,
    ..._u32le(listData.length),
    ...listData,
  ]);
}

/// 在最小合法 wav 末尾追加 chunk 并重建 RIFF size
Uint8List appendChunkWav(Uint8List chunk) {
  final base = _buildMinimalWav();
  final oldSize = (base[4] |
          (base[5] << 8) |
          (base[6] << 16) |
          (base[7] << 24)) &
      0x7FFFFFFF;
  return Uint8List.fromList([
    ...base.sublist(0, 4),
    ..._u32le(oldSize + chunk.length),
    ...base.sublist(8),
    ...chunk,
  ]);
}