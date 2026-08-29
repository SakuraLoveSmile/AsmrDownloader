import 'dart:math' as math;

import 'package:dio/dio.dart';

/// 单个下载请求的最大重试次数（首次请求之外）。
/// 超过后判定为持续故障，终止下载并保留断点供用户手动重试。
const int maxDownloadRetries = 5;

/// 永久性 HTTP 错误：重试不可能成功，应立即失败。
const Set<int> permanentDownloadStatusCodes = {400, 401, 403, 404, 410};

/// 判断 DioException 是否为永久性失败（重试无意义）。
/// 416 由调用方结合本地断点状态单独解释（可能是「已下载完成」）。
bool isPermanentDownloadFailure(DioException e) {
  final code = e.response?.statusCode;
  return code != null && permanentDownloadStatusCodes.contains(code);
}

/// 计算第 [attempt] 次失败后的重试延迟：指数退避（基础间隔的
/// 1x/2x/4x/8x/16x）；429 优先遵循 Retry-After 响应头（上限 60 秒）。
Duration downloadRetryDelay(DioException e, int attempt, Duration baseDelay) {
  var delay = baseDelay * (1 << math.min(attempt - 1, 4));
  if (e.response?.statusCode == 429) {
    final retryAfter =
        int.tryParse(e.response?.headers.value('retry-after') ?? '');
    if (retryAfter != null && retryAfter > 0) {
      delay = Duration(seconds: math.min(retryAfter, 60));
    }
  }
  return delay;
}
