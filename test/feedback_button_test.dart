import 'package:asmr_downloader/services/feedback/feedback_config.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = FeedbackServiceConfig(
    apiBase: 'https://feedback.example.com',
    appId: 'asmrdownloader',
    appName: 'AsmrDownloader',
  );

  group('buildFeedbackConfig', () {
    test('显式声明灵感球与视口截图（包默认是 tab / off）', () {
      final config = buildFeedbackConfig(
        service: service,
        pageLabel: 'downloader',
      );

      expect(config.launcherMode, FeedbackLauncherMode.orb);
      expect(config.captureMode, FeedbackCaptureMode.viewport);
      expect(config.side, FeedbackSide.right);
      expect(config.apiBase, 'https://feedback.example.com');
      expect(config.appId, 'asmrdownloader');
    });

    test('未显式传入的 appVersion / pageLabel 不上报', () {
      final config = buildFeedbackConfig(
        service: service,
        pageLabel: 'downloader',
      );

      // pageLabel 必须由宿主显式传入，组件绝不自动抓取
      expect(config.pageLabel, 'downloader');
      expect(config.appVersion, isNull);
    });

    test('launcherBottom 默认避开右下角任务浮条', () {
      final config = buildFeedbackConfig(
        service: service,
        pageLabel: 'downloader',
      );
      expect(config.launcherBottom, '30%');
    });
  });

  group('feedbackPageLabelForIndex', () {
    test('页面索引映射为粗粒度页面标识，不含路线细节', () {
      expect(feedbackPageLabelForIndex(0), 'downloader');
      expect(feedbackPageLabelForIndex(2), 'library');
      expect(feedbackPageLabelForIndex(5), 'database');
      expect(feedbackPageLabelForIndex(99), 'other');
    });
  });

  group('FeedbackBuildConfig', () {
    test('appId 与显示名有稳定的生产默认值', () {
      expect(FeedbackBuildConfig.defaultAppId, 'asmrdownloader');
      expect(FeedbackBuildConfig.defaultAppName, 'AsmrDownloader');
      expect(
        FeedbackBuildConfig.defaultApiBase,
        'https://feedback.xn--fhqths51enha.cn',
      );
    });

    test('服务地址必须是 http(s)，否则构造即断言失败', () {
      expect(
        () => buildFeedbackConfig(
          service: const FeedbackServiceConfig(
            apiBase: 'feedback.example.com',
            appId: 'asmrdownloader',
          ),
          pageLabel: 'downloader',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
