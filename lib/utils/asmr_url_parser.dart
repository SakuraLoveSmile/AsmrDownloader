import 'dart:convert';

import 'package:asmr_downloader/utils/tool_functions.dart';

/// 从 asmr.one 网页 URL 中解析出的信息。
///
/// 网站前端 URL 格式（调研自 asmr-200.com）：
///
///     https://asmr-200.com/work/RJ01619789?path=["RJ01619789","舔耳ONLY音轨"]#work-tree
///
/// - /work/{sourceId}：作品 id（RJ/VJ/BJ + 数字）
/// - path 查询参数：URL 编码的 JSON 数组，是音轨树中的目录面包屑，
///   第一个元素是作品根目录（= sourceId），后续元素是嵌套文件夹名
/// - #work-tree：页内锚点（音轨树区块），解析时忽略
///
/// 当 work info 接口获取不到数据时，用这里的信息作为保底音乐标签。
class AsmrUrlInfo {
  /// 作品 sourceId，如 RJ01619789（大写）
  final String sourceId;

  /// 音轨树目录面包屑，如 ['RJ01619789', '舔耳ONLY音轨']
  final List<String> treePath;

  const AsmrUrlInfo({required this.sourceId, required this.treePath});
}

/// 匹配 asmr.one 系站点作品页 URL 并提取 sourceId：
/// https://asmr.one/work/RJ01619789、https://asmr-200.com/work/RJ01619789 等
///
/// 注意：域名部分必须用惰性量词 [^\s/?#]*?。
/// Dart 正则引擎对「贪婪量词回溯到空再匹配紧跟的字面量」存在缺陷
/// （如 r'[^/]+asmr' 匹配 'asmr-200.com' 失败），
/// 惰性量词从最短开始扩展，不依赖该回溯路径。
final _workUrlRegExp = RegExp(
  r'https?://[^\s/?#]*?asmr(?:-\d+)?\.(?:one|com)/work/([A-Za-z]{2}\d+)',
  caseSensitive: false,
);

/// 尝试把输入解析为 asmr.one 作品页 URL；不是则返回 null。
///
/// 解析成功时返回 sourceId（大写）与 path 参数里的目录面包屑；
/// path 参数缺失或解析失败时面包屑为空列表。
AsmrUrlInfo? parseAsmrWorkUrl(String input) {
  final text = input.trim();
  final match = _workUrlRegExp.firstMatch(text);
  if (match == null) return null;

  final sourceId = match.group(1)!.toUpperCase();
  if (!isSourceIdValid(sourceId)) return null;

  var treePath = const <String>[];
  try {
    final uri = Uri.tryParse(text);
    final pathRaw = uri?.queryParameters['path'];
    if (pathRaw != null && pathRaw.isNotEmpty) {
      final decoded = jsonDecode(pathRaw);
      if (decoded is List) {
        treePath = decoded.map((segment) => segment.toString().trim()).toList();
      }
    }
  } catch (_) {
    // path 参数非法时忽略，保底信息仍可用 sourceId
    treePath = const [];
  }

  return AsmrUrlInfo(sourceId: sourceId, treePath: treePath);
}

/// 用目录面包屑生成保底标题：去掉根节点（= sourceId）后剩余段拼接。
/// 没有子目录时返回 sourceId 本身。
String fallbackTitleFromTreePath(List<String> treePath, String sourceId) {
  final segments = treePath
      .where((segment) =>
          segment.isNotEmpty && segment.toUpperCase() != sourceId.toUpperCase())
      .toList();
  return segments.isEmpty ? sourceId : segments.join(' / ');
}
