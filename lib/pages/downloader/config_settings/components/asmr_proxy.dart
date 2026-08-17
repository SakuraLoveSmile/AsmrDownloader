import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/components/labeled_checkbox.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsmrProxy extends ConsumerWidget {
  const AsmrProxy({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxy = ref.watch(proxyProvider);
    return Tooltip(
      message: '检测并使用系统代理。asmr-100 需要代理，asmr-200/300 不需要，一般无需勾选',
      child: LabeledCheckbox(
        label: '启用代理',
        value: proxy != 'DIRECT',
        onChanged: ref.read(uiServiceProvider).onProxyChanged,
      ),
    );
  }
}
