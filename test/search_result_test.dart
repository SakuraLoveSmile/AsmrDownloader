import 'package:asmr_downloader/pages/downloader/search_result/empty_guidance.dart';
import 'package:asmr_downloader/pages/downloader/search_result/search_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('搜索前下载中心只显示一份全宽引导', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [SearchResult()],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(EmptyGuidance), findsOneWidget);
    expect(find.text('开始搜索一个作品'), findsOneWidget);
    expect(find.text('输入 sourceId（如 RJ01234567）或粘贴 asmr.one 作品页 URL'),
        findsOneWidget);
  });
}
