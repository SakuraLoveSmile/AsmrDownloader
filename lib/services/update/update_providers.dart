import 'dart:async';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:asmr_downloader/services/update/update_service.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 更新服务单例（代理/Token 随配置变化自动重建）
final updateServiceProvider = Provider<UpdateService>((ref) {
  final svc = UpdateService();
  svc.proxy = ref.watch(proxyProvider);
  svc.githubToken = ref.watch(githubTokenProvider);
  return svc;
});

/// 当前应用版本号（来自构建产物元信息，即 pubspec 的 version）
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// 启动时自动检查更新
final autoCheckUpdateProvider = StateProvider<bool>((ref) => true);

/// 更新包下载进度；null = 未在下载
final updateDownloadProgressProvider =
    StateProvider<UpdateDownloadProgress?>((ref) => null);

class UpdateDownloadProgress {
  const UpdateDownloadProgress(this.received, this.total);

  final int received;
  final int total;
}

final latestUpdateProvider =
    AsyncNotifierProvider<LatestUpdateNotifier, UpdateInfo?>(
        LatestUpdateNotifier.new);

/// 最新版本检测与下载安装编排。
class LatestUpdateNotifier extends AsyncNotifier<UpdateInfo?> {
  @override
  Future<UpdateInfo?> build() async => null;

  CancelToken? _downloadToken;
  bool _installing = false;
  String? _downloadedZipPath;

  /// 启动自动检查的最小间隔：GitHub 匿名限额 60 次/小时/IP，
  /// 共享代理出口时极易触发 403 限流，频繁检查得不偿失。
  static const _autoCheckInterval = Duration(hours: 6);

  /// 检查更新；返回 true = 发现新版本。
  /// [silent]=true 为启动自动检查：不进入 loading 态（不影响入口 UI），
  /// 失败也不对外抛错，且受 [_autoCheckInterval] 节流（间隔内不发请求，
  /// 上次结论有新版则恢复展示）。
  Future<bool> check({bool silent = false}) async {
    try {
      if (!silent) state = const AsyncLoading();
      final current = await ref.read(appVersionProvider.future);
      final cache = await _readCheckCache();

      if (silent) {
        final lastAt = cache['lastCheckAt'] as int? ?? 0;
        final withinInterval =
            DateTime.now().millisecondsSinceEpoch - lastAt <
                _autoCheckInterval.inMilliseconds;
        if (withinInterval) {
          final info = UpdateService.evaluateRelease(
              cache['releaseBody'] as String?, current);
          if (info != null) state = AsyncData(info);
          return info != null;
        }
      }

      final result = await ref.read(updateServiceProvider).checkForUpdate(
            current,
            etag: cache['etag'] as String?,
            cachedReleaseBody: cache['releaseBody'] as String?,
          );
      // 缓存 ETag/响应体/时间：下次条件请求 304 不消耗速率配额
      unawaited(_writeCheckCache(result));
      state = AsyncData(result.info);
      return result.info != null;
    } catch (e, st) {
      Log.warning('check update failed\nerror: $e');
      state = AsyncError(e, st);
      return false;
    }
  }

  /// 手动检查更新：失败/已是最新时 SnackBar 提示；返回 true = 发现新版本。
  Future<bool> manualCheck() async {
    final hasNew = await check();
    if (hasNew) return true;
    final ui = UIService(ref);
    if (state is AsyncError) {
      final error = (state as AsyncError).error;
      ui.showSnack(error is UpdateCheckException
          ? '检查更新失败：${error.message}'
          : '检查更新失败，请检查网络/代理后重试');
    } else {
      ui.showSnack('当前已是最新版本');
    }
    return false;
  }

  Future<Map<String, dynamic>> _readCheckCache() async {
    try {
      final config = await ref.read(configFileProvider).read();
      return (config['updateCheckCache'] as Map?)
              ?.cast<String, dynamic>() ??
          const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<void> _writeCheckCache(UpdateCheckResult result) {
    return ref.read(configFileProvider).addOrUpdate({
      'updateCheckCache': {
        'lastCheckAt': DateTime.now().millisecondsSinceEpoch,
        'etag': result.etag,
        'releaseBody': result.releaseBody,
      },
    });
  }

  /// 下载更新包（不安装）。返回 null = 成功（zip 已就绪，待
  /// [installUpdate]）；返回空串 = 用户取消；其余为错误信息。
  Future<String?> downloadUpdatePackage(UpdateInfo info) async {
    final svc = ref.read(updateServiceProvider);
    _downloadToken = CancelToken();
    ref.read(updateDownloadProgressProvider.notifier).state =
        const UpdateDownloadProgress(0, 0);
    try {
      final zipPath = await svc.downloadUpdate(
        info,
        cancelToken: _downloadToken,
        onProgress: (received, total) => ref
            .read(updateDownloadProgressProvider.notifier)
            .state = UpdateDownloadProgress(received, total),
      );
      ref.read(updateDownloadProgressProvider.notifier).state = null;
      if (zipPath == null) return '更新包下载失败，请重试或手动下载';
      _downloadedZipPath = zipPath;
      return null;
    } on DioException catch (e) {
      ref.read(updateDownloadProgressProvider.notifier).state = null;
      if (CancelToken.isCancel(e)) return '';
      return '更新包下载失败：${e.message}';
    } catch (e) {
      ref.read(updateDownloadProgressProvider.notifier).state = null;
      return '更新失败：$e';
    } finally {
      _downloadToken = null;
    }
  }

  /// 安装已下载的更新包：应用退出，由更新脚本接管替换与重启。
  /// 返回 null = 成功（应用即将退出）；其余为错误信息。
  Future<String?> installUpdate() async {
    final zipPath = _downloadedZipPath;
    if (zipPath == null) return '更新包未就绪，请先下载';
    if (_installing) return '正在安装中，请稍候';
    _installing = true;
    try {
      final ok = await ref.read(updateServiceProvider).applyUpdate(zipPath);
      if (!ok) return '安装脚本启动失败，请重试或手动下载';
      return null; // 应用已退出，脚本接管
    } catch (e) {
      return '更新失败：$e';
    } finally {
      _installing = false;
    }
  }

  /// 取消进行中的更新包下载
  void cancelDownload() {
    _downloadToken?.cancel('用户取消更新下载');
  }
}
