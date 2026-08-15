import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsmrApiChannel extends ConsumerWidget {
  const AsmrApiChannel({super.key});

  static const List<String> _dropdownItems = [
    'asmr-100',
    'asmr-200',
    'asmr-300'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiChannel = ref.watch(apiChannelProvider);
    return Tooltip(
      message: '仅影响搜索 API。asmr-100 需代理，200/300 不需要；200/300 搜不到时可尝试 100',
      child: SizedBox(
        child: Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: DropdownMenu<String>(
            initialSelection: apiChannel,
            dropdownMenuEntries: _dropdownItems
                .map((v) => DropdownMenuEntry<String>(value: v, label: v))
                .toList(),
            onSelected: ref.read(uiServiceProvider).onApiChannelChoosed,
          ),
        ),
      ),
    );
  }
}
