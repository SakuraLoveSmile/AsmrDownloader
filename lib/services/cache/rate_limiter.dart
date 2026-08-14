/// 速率限制器：确保任意两次被包裹的请求之间至少间隔 [minInterval]。
/// 通过内部队列串行化并发调用（并发 gate 也会依次放行并保持间隔），
/// 用于控制对 asmr.one API 的总请求频率。
class RateLimiter {
  RateLimiter({this.minInterval = const Duration(seconds: 2)});

  /// 两次请求之间的最小间隔。运行时可变（批量缓存按用户选择临时调整，
  /// 用完后由调用方还原默认值）。
  Duration minInterval;

  DateTime? _lastRequestTime;

  /// 串行链尾：并发调用按调用顺序排队，互不重叠
  Future<void> _tail = Future.value();

  /// 在 [request] 执行前等待，保证与上一次请求的间隔 >= [minInterval]。
  /// 返回 [request] 的执行结果；[request] 抛出的异常原样向上传播。
  Future<T> gate<T>(Future<T> Function() request) {
    final result = _tail.then((_) async {
      final now = DateTime.now();
      final last = _lastRequestTime;
      if (last != null) {
        final elapsed = now.difference(last);
        if (elapsed < minInterval) {
          await Future.delayed(minInterval - elapsed);
        }
      }
      _lastRequestTime = DateTime.now();
      return await request();
    });
    // 链尾只关心时序，不吞掉调用方的错误（错误由调用方 await result 处理）
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
