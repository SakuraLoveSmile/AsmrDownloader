import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/cache/rate_limiter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局速率限制器：所有 API 请求共享一个间隔控制（默认 2 秒）
final rateLimiterProvider = Provider<RateLimiter>((ref) {
  return RateLimiter(minInterval: const Duration(seconds: 2));
});

final asmrApiProvider = Provider<AsmrApi>((ref) {
  return AsmrApi(rateLimiter: ref.read(rateLimiterProvider));
});
