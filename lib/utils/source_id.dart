/// RJ/VJ/BJ 作品编号的统一解析工具。
///
/// asmr.one 的作品编号有 RJ / VJ / BJ 三种前缀。历史上多处代码只判断
/// `startsWith('RJ')`，导致 VJ/BJ 作品在搜索入口被误当作关键字走
/// 搜索接口路径。所有「前缀 + 数字」判断统一收口到本类。
class SourceId {
  SourceId._();

  static final RegExp _prefixedPattern =
      RegExp(r'^(RJ|VJ|BJ)\d+$', caseSensitive: false);

  /// 是否为「前缀 + 数字」形式的 sourceId（忽略大小写）。
  /// 纯数字输入属于关键字搜索，不算 sourceId。
  static bool isPrefixed(String input) =>
      _prefixedPattern.hasMatch(input.trim());

  /// 规范化为大写（忽略首尾空白）；非「前缀 + 数字」形式返回 null。
  static String? normalize(String input) {
    final value = input.trim().toUpperCase();
    return _prefixedPattern.hasMatch(value) ? value : null;
  }

  /// 提取数字段（如 'RJ01234567' → '01234567'）。
  static String digits(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');
}
