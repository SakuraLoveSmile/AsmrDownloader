import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// 反馈服务的编译期配置，通过 `--dart-define` 覆盖。
///
/// * `FEEDBACK_ENABLED` — 总开关。未设置时：release/profile 构建启用，
///   debug 构建与 `flutter test` 关闭，避免日常调试与既有 widget 测试
///   被动带上灵感球。
/// * `FEEDBACK_API_BASE` — Feedback 服务地址（默认生产地址）。
/// * `FEEDBACK_APP_ID` — 本应用在 Feedback 服务里的软件标识。
/// * `FEEDBACK_APP_NAME` — 随提交上报的显示名；服务端仅在管理员尚未
///   设置名称时采用。
///
/// 客户端只读取这四个值，不持有任何 AI / Kaneo / 管理端密钥；登录后的
/// 令牌由组件按「apiBase + appId」独立存储，与下载器自身凭据隔离。
class FeedbackBuildConfig {
  const FeedbackBuildConfig._();

  /// 生产 Feedback 服务地址（IDN 域名的 punycode 形式）。
  static const String defaultApiBase = 'https://feedback.xn--fhqths51enha.cn';

  /// 本应用在 Feedback 服务里的 appId（首次提交后服务端自动发现）。
  static const String defaultAppId = 'asmrdownloader';

  /// 随提交上报的应用显示名。
  static const String defaultAppName = 'AsmrDownloader';

  static const String _enabledRaw = String.fromEnvironment('FEEDBACK_ENABLED');
  static const String _apiBaseRaw = String.fromEnvironment('FEEDBACK_API_BASE');
  static const String _appIdRaw = String.fromEnvironment('FEEDBACK_APP_ID');
  static const String _appNameRaw = String.fromEnvironment('FEEDBACK_APP_NAME');

  /// 反馈层是否挂载。官方构建默认开启，debug / 测试默认关闭。
  static bool get enabled {
    if (_enabledRaw.isEmpty) return !kDebugMode;
    return _enabledRaw == 'true' || _enabledRaw == '1';
  }

  static String get apiBase =>
      _apiBaseRaw.isEmpty ? defaultApiBase : _apiBaseRaw;

  static String get appId => _appIdRaw.isEmpty ? defaultAppId : _appIdRaw;

  static String get appName =>
      _appNameRaw.isEmpty ? defaultAppName : _appNameRaw;
}

/// 交给 [FeedbackWidget] 的服务身份。[null] 表示反馈层关闭。
class FeedbackServiceConfig {
  const FeedbackServiceConfig({
    required this.apiBase,
    required this.appId,
    this.appName,
  });

  final String apiBase;
  final String appId;

  /// 随提交上报的显示名（可选）。
  final String? appName;
}

/// 解析运行时服务身份；测试可 override 以隔离地址或强制关闭。
FeedbackServiceConfig? resolveFeedbackServiceConfig() {
  if (!FeedbackBuildConfig.enabled) return null;
  return FeedbackServiceConfig(
    apiBase: FeedbackBuildConfig.apiBase,
    appId: FeedbackBuildConfig.appId,
    appName: FeedbackBuildConfig.appName,
  );
}

/// 页面索引 → 粗粒度页面标识。
///
/// 只上报分类名，不上报路由、搜索词或路径——反馈元数据不带用户内容。
String feedbackPageLabelForIndex(int index) => switch (index) {
      0 => 'downloader',
      1 => 'download-list',
      2 => 'library',
      3 => 'media-library',
      4 => 'background-tasks',
      5 => 'database',
      _ => 'other',
    };

/// 构建不可变的 [FeedbackConfig]。
///
/// 固定选择：右侧灵感球、呼出即截取当前应用视口、靠右 30% 的初始位置
/// 避开右下角全局任务浮条。主题由调用方跟随应用 themeMode 传入。
FeedbackConfig buildFeedbackConfig({
  required FeedbackServiceConfig service,
  required String pageLabel,
  String? appVersion,
  FeedbackThemeMode theme = FeedbackThemeMode.system,
  String launcherBottom = '30%',
  FeedbackLogProvider? logProvider,
}) {
  return FeedbackConfig(
    service.apiBase,
    service.appId,
    appName: service.appName,
    appVersion: appVersion,
    pageLabel: pageLabel,
    side: FeedbackSide.right,
    theme: theme,
    // 包默认是 tab / off，必须显式声明才有灵感球与自动截图。
    launcherMode: FeedbackLauncherMode.orb,
    captureMode: FeedbackCaptureMode.viewport,
    launcherBottom: launcherBottom,
    logProvider: logProvider,
  );
}
