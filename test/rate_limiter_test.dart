import 'package:asmr_downloader/services/cache/rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首次请求立即执行，不等待', () async {
    final limiter = RateLimiter(minInterval: const Duration(seconds: 10));
    final sw = Stopwatch()..start();
    await limiter.gate(() async {});
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('连续两次请求间隔不小于 minInterval', () async {
    final limiter = RateLimiter(minInterval: const Duration(milliseconds: 300));
    final sw = Stopwatch()..start();
    await limiter.gate(() async {});
    await limiter.gate(() async {});
    sw.stop();
    // 留 10ms 时钟抖动余量（CI 慢机曾测得 299ms）
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(290));
  });

  test('距上次请求已超过 minInterval 时不额外等待', () async {
    final limiter = RateLimiter(minInterval: const Duration(milliseconds: 100));
    await limiter.gate(() async {});
    await Future.delayed(const Duration(milliseconds: 250));
    final sw = Stopwatch()..start();
    await limiter.gate(() async {});
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(150));
  });

  test('并发 gate 串行化执行且保持间隔', () async {
    final limiter = RateLimiter(minInterval: const Duration(milliseconds: 200));
    final order = <int>[];
    final sw = Stopwatch()..start();
    await Future.wait([
      limiter.gate(() async => order.add(1)),
      limiter.gate(() async => order.add(2)),
      limiter.gate(() async => order.add(3)),
    ]);
    sw.stop();
    expect(order, [1, 2, 3]);
    // 三个请求依次放行：两次等待，共 >= 400ms（留 10ms 抖动余量）
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(390));
  });

  test('request 抛错向上传播，且后续 gate 不受影响', () async {
    final limiter = RateLimiter(minInterval: const Duration(milliseconds: 100));
    await expectLater(
      limiter.gate(() async => throw Exception('boom')),
      throwsException,
    );
    await limiter.gate(() async {}); // 不抛错
  });

  test('minInterval 可运行时修改，新的间隔立即生效', () async {
    final limiter = RateLimiter(minInterval: const Duration(milliseconds: 100));
    await limiter.gate(() async {});
    // 改为 300ms
    limiter.minInterval = const Duration(milliseconds: 300);
    final sw = Stopwatch()..start();
    await limiter.gate(() async {});
    sw.stop();
    // 距上一次请求不足 300ms，因此需要等待到 300ms 以上（留 10ms 抖动余量）
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(290));
    // 还原后走默认再验证（留出时钟抖动余量，CI 慢机曾测得 49ms）
    limiter.minInterval = const Duration(milliseconds: 50);
    final sw2 = Stopwatch()..start();
    await limiter.gate(() async {});
    sw2.stop();
    expect(sw2.elapsedMilliseconds, greaterThanOrEqualTo(40));
  });
}
