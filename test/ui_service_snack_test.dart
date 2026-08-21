import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('新提示会清理队列并自动消失', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(),
        ),
      ),
    );
    final context = tester.element(find.byType(SizedBox));

    showAppSnackBar(context, '旧提示');
    showAppSnackBar(context, '最新提示');
    await tester.pump();

    expect(find.text('旧提示'), findsNothing);
    expect(find.text('最新提示'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 3),
    );

    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('最新提示'), findsNothing);
  });
}
