import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 媒体库后台网络任务可选的请求间隔。
///
/// 该设置由媒体库统一管理，主动缓存和一键补全都会使用同一个值。
const mediaLibraryRequestIntervalOptions = <Duration>[
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 3),
  Duration(seconds: 5),
];

const mediaLibraryRequestIntervalDefault = Duration(seconds: 2);

/// 当前媒体库后台网络任务的统一请求间隔。
final mediaLibraryRequestIntervalProvider =
    StateProvider<Duration>((ref) => mediaLibraryRequestIntervalDefault);

String formatMediaLibraryRequestInterval(Duration interval) {
  final milliseconds = interval.inMilliseconds;
  if (milliseconds < 1000) return '${milliseconds}ms / 次请求';
  final seconds = milliseconds / 1000;
  final label = seconds == seconds.roundToDouble()
      ? seconds.toInt().toString()
      : seconds.toStringAsFixed(1);
  return '$label 秒 / 次请求';
}
