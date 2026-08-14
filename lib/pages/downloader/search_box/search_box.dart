import 'package:asmr_downloader/common/const.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/asmr_url_parser.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchBox extends ConsumerStatefulWidget {
  const SearchBox({super.key});

  @override
  SearchBoxState createState() => SearchBoxState();
}

class SearchBoxState extends ConsumerState<SearchBox> {
  final TextEditingController _controller = TextEditingController();
  final Color _color = Colors.white70;
  String _inputText = '';
  bool _dragOver = false;

  /// 从任意文本/文件名中提取 sourceId（如 RJ01234567_01.mp3）
  static final RegExp _sourceIdInText =
      RegExp(r'(RJ|VJ|BJ)\d+', caseSensitive: false);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(
          const Duration(milliseconds: PASTE_SEARCH_DELAY_MS + 20));
      final currentSearchText = ref.read(searchTextProvider);
      if (currentSearchText != null) {
        _controller.text = currentSearchText;
        _inputText = currentSearchText;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 实时校验：合法 sourceId 或 asmr.one 作品页 URL 才视为合法输入
  bool _isValidInput(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    if (parseAsmrWorkUrl(text) != null) return true;
    return isSourceIdValid(ref.read(uiServiceProvider).normalizeInput(text));
  }

  Future<void> _searchInput(String input) async {
    final newSearchText = await ref.read(uiServiceProvider).search(input);
    if (newSearchText != null && mounted) {
      setState(() {
        _controller.text = newSearchText;
        _inputText = newSearchText;
      });
    }
  }

  /// 强制刷新：置位 forceRefresh 后失效元数据 providers，
  /// 等三个 provider 全部重算完成（期间读取到 true 跳过缓存）再复位标志。
  Future<void> _refresh() async {
    if (ref.read(sourceIdProvider) == null) {
      ref.read(uiServiceProvider).showSnack('请先搜索作品');
      return;
    }
    ref.read(forceRefreshProvider.notifier).state = true;
    ref
      ..invalidate(workInfoProvider)
      ..invalidate(rawTracksProvider)
      ..invalidate(coverBytesProvider);
    await Future.wait(
      [
        ref.read(workInfoProvider.future),
        ref.read(rawTracksProvider.future),
        ref.read(coverBytesProvider.future),
      ].map((f) => f.catchError((_) => null)),
    );
    ref.read(forceRefreshProvider.notifier).state = false;
    if (mounted) {
      ref.read(uiServiceProvider).showSnack('已强制刷新元数据');
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (ref.read(dlStatusProvider) == DownloadStatus.downloading) {
      ref.read(uiServiceProvider).showSnack('下载中无法搜索，请先取消下载');
      return;
    }

    for (final item in details.files) {
      final name = item.name.trim();
      // 1. 拖入内容本身是作品页 URL / sourceId
      if (parseAsmrWorkUrl(name) != null ||
          isSourceIdValid(ref.read(uiServiceProvider).normalizeInput(name))) {
        await _searchInput(name);
        return;
      }
      // 2. 文件名里带 sourceId（如 RJ01234567_01.mp3）
      final nameMatch = _sourceIdInText.firstMatch(name);
      if (nameMatch != null) {
        await _searchInput(nameMatch.group(0)!);
        return;
      }
      // 3. 本地文件（.url 快捷方式 / .txt 等）：读取内容再识别
      try {
        final content = (await item.readAsString()).trim();
        if (content.isEmpty) continue;
        if (parseAsmrWorkUrl(content) != null ||
            isSourceIdValid(
                ref.read(uiServiceProvider).normalizeInput(content))) {
          await _searchInput(content);
          return;
        }
        final contentMatch = _sourceIdInText.firstMatch(content);
        if (contentMatch != null) {
          await _searchInput(contentMatch.group(0)!);
          return;
        }
      } catch (_) {
        // 非本地文件（如平台直接传入的 URL），跳过内容读取
      }
    }

    ref.read(uiServiceProvider).showSnack('未识别到 sourceId 或作品页 URL');
  }

  @override
  Widget build(BuildContext context) {
    final downloading =
        ref.watch(dlStatusProvider) == DownloadStatus.downloading;
    final invalid = _inputText.isNotEmpty && !_isValidInput(_inputText);

    return DropTarget(
      enable: !downloading,
      onDragEntered: (_) {
        if (mounted) setState(() => _dragOver = true);
      },
      onDragExited: (_) {
        if (mounted) setState(() => _dragOver = false);
      },
      onDragDone: _handleDrop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 50.0,
        decoration: BoxDecoration(
          color: _dragOver
              ? Colors.pinkAccent.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _controller,
                  cursorColor: _color,
                  decoration: InputDecoration(
                    hintText: '输入sourceId或作品页URL',
                    border: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: invalid ? Colors.redAccent : Colors.white24)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: invalid ? Colors.redAccent : _color)),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: invalid ? Colors.redAccent : Colors.white24)),
                  ),
                  onChanged: (value) => setState(() => _inputText = value),
                  onSubmitted: (_) =>
                      downloading ? null : _searchInput(_inputText),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 5.0),
                child: IconButton(
                  onPressed:
                      downloading ? null : () => _searchInput(_inputText),
                  icon: Icon(Icons.search,
                      color: invalid ? Colors.redAccent : null),
                ),
              ),
              IconButton(
                onPressed: downloading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: '强制刷新（重新请求元数据并更新缓存）',
              ),
              IconButton(
                onPressed: downloading
                    ? null
                    : () async {
                        final newSearchText =
                            await ref.read(uiServiceProvider).pasteAndSearch();
                        if (newSearchText != null && mounted) {
                          setState(() {
                            _controller.text = newSearchText;
                            _inputText = newSearchText;
                          });
                        }
                      },
                icon: const Icon(Icons.content_paste_go),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
