import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/engine/chicken_rice_engine_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// AI 翻译引擎安装状态（安装向导 UI 订阅）
final engineInstallStateProvider = StateProvider<EngineInstallState>(
    (ref) => EngineInstallState.idle);

/// 引擎安装服务（代理设置随 proxyProvider 变化重建）
final chickenRiceEngineServiceProvider =
    Provider<ChickenRiceEngineService>((ref) {
  final svc = ChickenRiceEngineService();
  svc.proxy = ref.watch(proxyProvider);
  return svc;
});
