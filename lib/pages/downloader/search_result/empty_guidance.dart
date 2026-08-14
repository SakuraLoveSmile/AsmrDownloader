import 'package:flutter/material.dart';

/// 搜索前的空状态引导：提示用户输入 sourceId 或粘贴作品页 URL
class EmptyGuidance extends StatelessWidget {
  const EmptyGuidance({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search, size: 56, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            '输入 sourceId（如 RJ01234567）\n或粘贴 asmr.one 作品页 URL 搜索',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
