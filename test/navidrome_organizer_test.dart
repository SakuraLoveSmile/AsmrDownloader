import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sourceDir;
  late Directory targetRoot;

  /// 模拟下载结构：
  /// sourceDir/
  /// ├── RJ12345678_cover.jpg
  /// └── 音声/
  ///     ├── e01_01_『舔耳』.wav
  ///     ├── e01_01_『舔耳』.wav.vtt
  ///     └── 特典/
  ///         └── ex01_留言.wav
  void createMockDownload() {
    final rjDir = sourceDir;
    File(p.join(rjDir.path, 'RJ12345678_cover.jpg'))
        .writeAsBytesSync(Uint8List.fromList(List.filled(100, 1)));
    final audioDir = Directory(p.join(rjDir.path, '音声'))..createSync();
    File(p.join(audioDir.path, 'e01_01_『舔耳』.wav'))
        .writeAsBytesSync(Uint8List.fromList(List.filled(1000, 2)));
    File(p.join(audioDir.path, 'e01_01_『舔耳』.wav.vtt'))
        .writeAsBytesSync(Uint8List.fromList(List.filled(50, 3)));
    final bonusDir = Directory(p.join(audioDir.path, '特典'))..createSync();
    File(p.join(bonusDir.path, 'ex01_留言.wav'))
        .writeAsBytesSync(Uint8List.fromList(List.filled(500, 4)));
    // 隐藏文件应被跳过
    File(p.join(sourceDir.path, '.DS_Store'))
        .writeAsBytesSync(Uint8List.fromList(List.filled(10, 5)));
  }

  late Directory testBase;

  setUp(() {
    final base = Directory.systemTemp.createTempSync('organize_test');
    sourceDir = Directory(p.join(base.path, '测试社团-测试标题', 'RJ12345678'))
      ..createSync(recursive: true);
    targetRoot = Directory(p.join(base.path, 'navidrome'))..createSync();
    testBase = base;
  });

  tearDown(() {
    testBase.deleteSync(recursive: true);
  });

  test('整理成 Navidrome 结构：circle/专辑/RJ号 + 扁平化 + cover.jpg', () async {
    createMockDownload();

    final result = await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '测试社团',
      sourceId: 'RJ12345678',
      cvNames: 'CV1&CV2',
      title: '测试标题',
      coverBytes: Uint8List.fromList(List.filled(80, 9)),
    );

    // 4 个有效文件 + 封面 = 5 个复制
    expect(result.copied, 4);
    expect(result.skipped, 0);

    final workDir = p.join(
      targetRoot.path,
      '测试社团',
      'RJ12345678 - CV1&CV2 - 测试标题',
      'RJ12345678',
    );

    // 封面重命名为 cover.jpg
    expect(File(p.join(workDir, 'cover.jpg')).existsSync(), true);

    // 音轨扁平化（音声/ 和 特典/ 层被拍平）
    expect(File(p.join(workDir, 'e01_01_『舔耳』.wav')).existsSync(), true);
    expect(File(p.join(workDir, 'e01_01_『舔耳』.wav.vtt')).existsSync(), true);
    expect(File(p.join(workDir, 'ex01_留言.wav')).existsSync(), true);

    // 隐藏文件被跳过
    expect(File(p.join(workDir, '.DS_Store')).existsSync(), false);
    // 下载器生成的封面不混入
    expect(File(p.join(workDir, 'RJ12345678_cover.jpg')).existsSync(), false);
  });

  test('幂等：重复整理全部跳过', () async {
    createMockDownload();

    await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '测试社团',
      sourceId: 'RJ12345678',
      cvNames: 'CV1&CV2',
      title: '测试标题',
      coverBytes: Uint8List.fromList(List.filled(80, 9)),
    );

    final result = await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '测试社团',
      sourceId: 'RJ12345678',
      cvNames: 'CV1&CV2',
      title: '测试标题',
      coverBytes: Uint8List.fromList(List.filled(80, 9)),
    );

    expect(result.copied, 0);
    expect(result.skipped, 4);
  });

  test('circle 为空时 fallback 到 CV 名', () async {
    createMockDownload();

    await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '',
      sourceId: 'RJ12345678',
      cvNames: 'CV1&CV2',
      title: '测试标题',
      coverBytes: null,
    );

    final workDir = p.join(
      targetRoot.path,
      'CV1&CV2',
      'RJ12345678 - CV1&CV2 - 测试标题',
      'RJ12345678',
    );
    expect(Directory(workDir).existsSync(), true);
  });

  test('无封面字节时不生成 cover.jpg', () async {
    createMockDownload();

    final result = await NavidromeOrganizer.organize(
      sourceDir: sourceDir.path,
      targetRoot: targetRoot.path,
      circleName: '测试社团',
      sourceId: 'RJ12345678',
      cvNames: 'CV1&CV2',
      title: '测试标题',
      coverBytes: null,
    );

    expect(result.copied, 3);

    final workDir = p.join(
      targetRoot.path,
      '测试社团',
      'RJ12345678 - CV1&CV2 - 测试标题',
      'RJ12345678',
    );
    expect(File(p.join(workDir, 'cover.jpg')).existsSync(), false);
  });

  group('resolveCircleName', () {
    // 汉化版数据结构（与 asmr API 实际返回一致）
    Map<String, dynamic> translatedWork({String circle = '汉化组'}) => {
          'title': '【简体中文版】测试',
          'circle': {'id': 999, 'name': circle},
          'translation_info': {
            'is_original': false,
            'original_workno': 'RJ01618607',
          },
          'other_language_editions_in_db': [
            {'id': 1618607, 'source_id': 'RJ01618607', 'is_original': true},
          ],
        };

    Map<String, dynamic> originalWork() => {
          'title': '【日本語】テスト',
          'circle': {'id': 35667, 'name': '空心菜館'},
          'translation_info': {'is_original': true},
          'other_language_editions_in_db': <Object>[],
        };

    test('原版作品直接用当前 circle', () async {
      final circle = await NavidromeOrganizer.resolveCircleName(
        workInfo: originalWork(),
        fallbackCircle: '空心菜館',
        fetchWorkInfo: (_) async => null,
      );
      expect(circle, '空心菜館');
    });

    test('汉化版跟踪到原版取真实社团名', () async {
      final circle = await NavidromeOrganizer.resolveCircleName(
        workInfo: translatedWork(),
        fallbackCircle: '汉化组',
        fetchWorkInfo: (id) async {
          expect(id, '1618607');
          return originalWork();
        },
      );
      expect(circle, '空心菜館');
    });

    test('原版信息获取失败时 fallback 当前 circle', () async {
      final circle = await NavidromeOrganizer.resolveCircleName(
        workInfo: translatedWork(),
        fallbackCircle: '汉化组',
        fetchWorkInfo: (_) async => null,
      );
      expect(circle, '汉化组');
    });

    test('workInfo 为 null 时 fallback', () async {
      final circle = await NavidromeOrganizer.resolveCircleName(
        workInfo: null,
        fallbackCircle: '汉化组',
        fetchWorkInfo: (_) async => null,
      );
      expect(circle, '汉化组');
    });
  });
}
