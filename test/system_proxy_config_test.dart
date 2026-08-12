import 'dart:io';

import 'package:asmr_downloader/utils/system_proxy_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemProxyConfig', () {
    test('macOS: 解析 scutil --proxy 输出为 PROXY 格式', () {
      // 该测试依赖本机系统代理配置，仅在 macOS 上执行
      if (!Platform.isMacOS) {
        markTestSkipped('仅 macOS 平台测试');
        return;
      }

      final result = Process.runSync('scutil', ['--proxy']);
      expect(result.exitCode, 0, reason: 'scutil --proxy 应成功执行');
      final stdout = result.stdout as String;

      // 代理开启时（本机 Clash 运行中）应能解析出代理地址
      if (stdout.contains('HTTPEnable : 1') ||
          stdout.contains('HTTPSEnable : 1')) {
        final proxy = SystemProxyConfig.getMacOSSystemProxy();
        expect(proxy, isNot('DIRECT'),
            reason: '系统代理已开启，应解析出代理而非 DIRECT');
        expect(proxy, matches(r'^PROXY .+:\d+; DIRECT$'),
            reason: '代理格式应为 "PROXY host:port; DIRECT"');
      } else {
        final proxy = SystemProxyConfig.getMacOSSystemProxy();
        expect(proxy, 'DIRECT', reason: '系统代理未开启，应为 DIRECT');
      }
    });
  });
}
