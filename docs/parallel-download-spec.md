# 多文件并行下载 Spec

> 状态：已批准并执行完成
> 适用范围：AsmrDownloader Flutter 桌面端下载链路
> 记录：初始为 Draft，用户批准后按本文档完成实现，`flutter analyze` 与全量测试通过。

---

## 1. 背景与现状

当前下载编排位于 `lib/services/download/download_manager.dart`：

```
run()
  ├─ 校验 sourceId / voiceWorkPath
  ├─ 统计总任务数
  ├─ 下载封面（串行）
  └─ _downloadTrackItem()              // 递归遍历音轨树
        └─ _downloadFileAsset()         // 逐文件串行
              └─ MultiThreadDownloader  // 单文件内多线程分段
```

已有能力：

- `MultiThreadDownloader`：单文件内 Range 分段多线程、断点续传、Range 探测失败自动回退单线程、临时文件清理。
- 全局下载状态：`dlStatusProvider`、`processProvider`、`currentFileNameProvider`、`currentDlNoProvider`、`downloadSpeedProvider`、`downloadEtaProvider`、`totalTaskCntProvider`。
- 取消：`DownloadManager._cancelRequested` + `_activeCancelTokens` 统一 cancel。
- 配置持久化：`asmr_dl_config.json`，通过 `JsonStorage` 读写。

问题：**文件与文件之间严格串行**。每个文件内部虽然开了多线程，但音轨 A 下载完成后才开始音轨 B，整体带宽利用率受单文件服务器限速影响。

---

## 2. 目标与非目标

### 目标

1. 同一作品内，多个选中文件**同时下载**。
2. 新增可配置的「并行文件数」，持久化到 `asmr_dl_config.json`。
3. 进度条 / 速度 / 剩余时间改为**全局聚合语义**。
4. 保持现有能力不回退：断点续传、取消、Range 回退、失败统计、下载注册表、自动整理、自动转写。
5. 默认行为保守，避免连接数激增导致服务器封禁。

### 非目标（本次不做）

- 跨作品并行下载（一次仍只下载一个 sourceId）。
- `MultiThreadDownloader` 内部调度机制重构。
- 暂停 / 恢复单个任务（只保留整体取消）。
- 音轨列表逐行状态图标（作为后续增强，不在本次验收范围内）。

---

## 3. 关键决策

| 决策点 | 结论 | 理由 |
|---|---|---|
| 并行粒度 | 文件级并行：N 个 worker，每个 worker 下载一个文件 | 复用现有 `MultiThreadDownloader`，改动最小 |
| 并行文件数选项 | `[1, 2, 3, 4]`，默认 `2` | 平衡收益与服务器友好 |
| 总连接数上限 | `16` | 防止 `16 线程 × 4 文件 = 64` 连接打爆服务器 |
| 每文件实际线程数 | `max(1, min(downloadThreads, 16 ~/ 并行文件数))` | 并行后自动压低单文件线程 |
| 任务队列 | `run()` 开始时把封面 + 全部选中文件拍平为 `List<_DownloadTask>` | 顺序确定、计数准确、易测试 |
| 进度语义 | 全局**字节进度**：已完成字节 / 总字节 | 不同大小文件并行时进度真实 |
| 计数语义 | `currentDlNoProvider` 改为**已完成文件数** | 保持现有 UI 计数格式 |
| 速度/ETA | 总速度 = 各活动任务瞬时速度之和；ETA = 剩余字节 / 总速度 | 与单文件逻辑一致 |
| 失败策略 | 单文件失败不中断其他任务；全部结束后有失败则整体状态 `failed` | 与现有「重试」行为兼容 |
| 取消策略 | 复用 `_cancelRequested` + `_activeCancelTokens` | 已验证的取消路径 |
| 新依赖 | 无 | 手写极简 worker pool |

---

## 4. 详细设计

### 4.1 配置与持久化

#### `lib/common/config_providers.dart`

新增：

```dart
/// 同时下载的文件数（文件级并行，与单文件分段线程数独立）
const parallelDownloadOptions = [1, 2, 3, 4];

/// 所有文件并发连接数的安全上限
const maxTotalDownloadConnections = 16;

/// 当前文件级并行数
final parallelDownloadCountProvider = StateProvider<int>((ref) => 2);
```

配置 key：`parallelDownloadCount`。

#### `lib/pages/components/initialization.dart`

在 `_initProvider` 中读取：

```dart
// 并行文件数：只接受 UI 提供的可选值，非法配置回退默认 2
final savedParallel =
    (config['parallelDownloadCount'] as num?)?.toInt() ?? 2;
ref.read(parallelDownloadCountProvider.notifier).state =
    parallelDownloadOptions.contains(savedParallel) ? savedParallel : 2;
```

#### `lib/services/ui/ui_service.dart`

新增变更处理：

```dart
void onParallelDownloadCountChanged(int? value) {
  if (value == null || value == ref.read(parallelDownloadCountProvider)) return;

  ref
    ..read(parallelDownloadCountProvider.notifier).state = value
    ..read(configFileProvider).addOrUpdate({'parallelDownloadCount': value});
  Log.info('parallelDownloadCount: $value');
}
```

#### 新增 UI 组件

`lib/pages/downloader/config_settings/components/parallel_downloads_selector.dart`

- `DropdownButton<int>`，选项来自 `parallelDownloadOptions`。
- 显示文案：`并行文件数`；值为 1 时显示 `单文件`，其余显示 `N 文件`。
- Tooltip：`同时下载的文件数。并行时会自动压低单文件线程，确保总连接数不超过 16`。
- 参照 `download_threads_selector.dart` 的样式实现。

#### `lib/pages/downloader/downloader.dart`

第二行配置栏插入 `ParallelDownloadsSelector()`，位置在 `DownloadThreadsSelector()` 之后：

```dart
DlCoverCheck(),
DownloadThreadsSelector(),
ParallelDownloadsSelector(),
AsmrProxy(),
```

### 4.2 任务模型与任务拍平

在 `DownloadManager` 内部定义（不对外暴露）：

```dart
enum _DownloadTaskKind {
  /// 普通网络下载（音轨、无缓存字节时的封面）
  network,

  /// 内存字节直接写盘（coverBytesProvider 已就绪时的封面）
  memory,
}

class _DownloadTask {
  _DownloadTask({
    required this.id,
    required this.title,
    required this.savePath,
    required this.url,
    required this.size,
    required this.kind,
    this.bytes,
  });

  final String id;
  final String title;
  final String savePath;
  final String url;
  final int size;
  final _DownloadTaskKind kind;
  final List<int>? bytes; // 仅 memory 任务使用

  final CancelToken cancelToken = CancelToken();
  DownloadStatus status = DownloadStatus.notStarted;

  // ---- 进度聚合用 ----
  int receivedBytes = 0;
  int lastReceivedBytes = 0;
  double currentSpeed = 0;
  final Stopwatch stopwatch = Stopwatch();
  int finalBytes = 0; // 完成后实际计入总进度的字节数
}
```

任务收集顺序（保证与当前串行行为一致）：

1. 封面任务排第一（仅当 `dlCoverProvider == true`，见 4.6）。
2. 递归先序遍历 `rootFolder`，对 `selected == true` 的 `FileAsset` 生成任务。
3. `savePath = p.join(dirPath, getLegalWindowsName(item.title))`，逻辑与现有 `_downloadTrackItem` 完全一致。

```dart
List<_DownloadTask> _collectTasks(Folder rootFolder, String voiceWorkPath) {
  final tasks = <_DownloadTask>[];

  // 封面任务（如可用）
  final coverTask = await _buildCoverTask(voiceWorkPath);
  if (coverTask != null) tasks.add(coverTask);

  void walk(TrackItem item, String dirPath) {
    final targetPath = p.join(dirPath, getLegalWindowsName(item.title));
    if (item is Folder) {
      for (final child in item.children) {
        walk(child, targetPath);
      }
    } else if (item is FileAsset && item.selected) {
      item.savePath = targetPath;
      tasks.add(_DownloadTask(
        id: item.id,
        title: item.title,
        savePath: targetPath,
        url: item.mediaDownloadUrl,
        size: item.size,
        kind: _DownloadTaskKind.network,
      ));
    }
  }

  walk(rootFolder, voiceWorkPath);
  return tasks;
}
```

### 4.3 Worker Pool

`DownloadManager` 新增字段：

```dart
int _nextTaskIndex = 0;
List<_DownloadTask> _tasks = const [];
final Set<String> _activeTaskIds = {};
final Map<String, _DownloadTask> _tasksById = {};
```

`run()` 流程改造（保持开头校验与结尾收尾不变）：

```dart
final tasks = await _collectTasks(...);
if (_cancelRequested || runSeq != _runSeq) return;

_tasks = tasks;
_nextTaskIndex = 0;
_activeTaskIds.clear();

final totalCount = tasks.length;
ref.read(totalTaskCntProvider.notifier).state = totalCount;

// 计算总字节（未知大小任务按 0 处理，进度公式见 4.4）
_totalBytes = tasks.fold(0, (sum, t) => sum + math.max(0, t.size));

final parallelCount = _effectiveParallelCount();
final workerCount = math.min(parallelCount, tasks.length);
await Future.wait([
  for (var i = 0; i < workerCount; i++) _worker(),
]);
```

Worker：

```dart
Future<void> _worker() async {
  while (true) {
    if (_cancelRequested || _runSeq != _currentRunSeq) return;

    final index = _nextTaskIndex++;
    if (index >= _tasks.length) return;

    final task = _tasks[index];
    if (_cancelRequested || _runSeq != _currentRunSeq) return;

    final ok = await _downloadTask(task);
    if (!ok) _failedCnt++;
  }
}
```

说明：

- Dart 单线程事件循环下，`_nextTaskIndex++` 与 `await` 之间的交错安全，不需要锁。
- 任务在 `await _downloadTask` 后才释放下一个索引，因此任意时刻在途文件数 ≤ workerCount。
- `workerCount = min(parallelCount, tasks.length)`，空任务列表直接走收尾流程，与现状一致。

有效并行数与每文件线程数：

```dart
int _effectiveParallelCount() {
  final configured = ref.read(parallelDownloadCountProvider);
  return parallelDownloadOptions.contains(configured) ? configured : 2;
}

int _perFileThreads() {
  final parallel = _effectiveParallelCount();
  final configuredThreads = ref.read(downloadThreadsProvider);
  final capped = maxTotalDownloadConnections ~/ parallel;
  return math.max(1, math.min(configuredThreads, capped));
}
```

`_resumableDownload` 的 `threadCount` 参数改用 `_perFileThreads()`，其余签名不变。

### 4.4 进度、速度与 ETA 聚合

`DownloadManager` 新增聚合字段：

```dart
int _completedBytes = 0;
int _totalBytes = 0;
```

#### 任务开始

```dart
_activeCancelTokens.add(task.cancelToken);
_activeTaskIds.add(task.id);
task
  ..status = DownloadStatus.downloading
  ..stopwatch.start();

_updateActiveFileNames();
```

`currentDlNoProvider` **不在开始时递增**，改为完成时递增（语义变化见 4.7）。

#### 任务进度回调

每个任务独立维护 `receivedBytes / lastReceivedBytes / stopwatch / currentSpeed`：

```dart
void _onTaskProgress(_DownloadTask task, int received, int total) {
  final oldReceived = task.receivedBytes;
  task.receivedBytes = received;

  final elapsedMs = task.stopwatch.elapsedMilliseconds;
  if (elapsedMs >= 500) {
    task.currentSpeed =
        (received - task.lastReceivedBytes) * 1000 / elapsedMs;
    task.lastReceivedBytes = received;
    task.stopwatch.reset();
  }

  _refreshAggregateProgress();
}

void _refreshAggregateProgress() {
  var activeReceived = 0;
  var totalSpeed = 0.0;
  for (final id in _activeTaskIds) {
    final t = _tasksById[id]!;
    activeReceived += math.min(t.receivedBytes, math.max(t.size, 0));
    totalSpeed += t.currentSpeed;
  }

  final doneBytes = _completedBytes + activeReceived;
  final progress = _totalBytes > 0
      ? (doneBytes / _totalBytes).clamp(0.0, 1.0)
      : _fallbackCountProgress();

  ref.read(processProvider.notifier).state = progress;
  ref.read(downloadSpeedProvider.notifier).state = totalSpeed;

  final remaining = math.max(0, _totalBytes - doneBytes);
  ref.read(downloadEtaProvider.notifier).state = totalSpeed > 0
      ? Duration(seconds: (remaining / totalSpeed).round())
      : Duration.zero;
}
```

进度节流：`_refreshAggregateProgress` 内部增加 100ms 节流（与 `MultiThreadDownloader` 现有策略一致），避免 UI 刷新过频。

#### 任务完成

```dart
task
  ..status = DownloadStatus.completed
  ..finalBytes = math.max(task.receivedBytes, math.max(task.size, 0));
_completedBytes += task.finalBytes;

_activeCancelTokens.remove(task.cancelToken);
_activeTaskIds.remove(task.id);

ref.read(currentDlNoProvider.notifier).state++; // 已完成文件数
_updateActiveFileNames();
_refreshAggregateProgress(force: true);

if (Platform.isWindows) {
  await WindowsTaskbar.setProgress(
      ref.read(currentDlNoProvider), ref.read(totalTaskCntProvider));
}
```

#### 任务失败

- `status = failed`，从 `_activeCancelTokens` / `_activeTaskIds` 移除。
- **不计入 `_completedBytes`**，但 `_failedCnt++`。
- 刷新聚合进度与活动文件名。

#### 未知大小任务的兜底

- 正常音轨任务 `size` 已知。
- 若存在 `size <= 0` 的网络任务（理论上只有异常数据），进度按**文件数**兜底：

```dart
double _fallbackCountProgress() {
  if (_tasks.isEmpty) return 0;
  final completed = _tasks.where((t) => t.status == DownloadStatus.completed).length;
  var activeFraction = 0.0;
  for (final id in _activeTaskIds) {
    final t = _tasksById[id]!;
    activeFraction += (t.size > 0 ? 0 : t.progress);
  }
  return ((completed + activeFraction) / _tasks.length).clamp(0.0, 1.0);
}
```

> 说明：当前数据流中 FileAsset.size 均由 tracks API 提供；此分支仅为防御性代码。

### 4.5 封面任务

保留现有「优先用已缓存字节」行为，但把封面统一成任务：

1. `coverBytesProvider` 为 `AsyncData` 且 `bytes != null`：
   - 生成 `_DownloadTaskKind.memory` 任务。
   - `size = bytes.length`，`bytes = bytes`。
   - `savePath = p.join(voiceWorkPath, sourceId, '${sourceId}_cover.jpg')`。
2. 否则调用 `api.tryGetContentLength(coverUrl)`：
   - 成功 → 生成 `_DownloadTaskKind.network` 任务（`url = coverUrl`，`size = coverSize`）。
   - 失败 → **不生成封面任务**（与现状一致，仅记 warning，不判失败）。
3. `memory` 任务的下载执行：

```dart
if (task.kind == _DownloadTaskKind.memory) {
  final file = File(task.savePath);
  await file.create(recursive: true);
  if (await file.length() != task.bytes!.length) {
    await file.writeAsBytes(task.bytes!);
  }
  return true;
}
```

### 4.6 单文件下载任务执行

将现有 `_downloadFileAsset` 改造为 `_downloadTask`：

```dart
Future<bool> _downloadTask(_DownloadTask task) async {
  if (_cancelRequested || _runSeq != _currentRunSeq) return false;

  task.status = DownloadStatus.downloading;
  _activeCancelTokens.add(task.cancelToken);
  _activeTaskIds.add(task.id);
  _tasksById[task.id] = task;
  task.stopwatch.start();
  _updateActiveFileNames();

  if (task.kind == _DownloadTaskKind.memory) {
    return _writeMemoryTask(task);
  }

  final ok = await _resumableDownload(
    task.url,
    task.savePath,
    task.size,
    cancelToken: task.cancelToken,
    onReceiveProgress: (received, total) => _onTaskProgress(task, received, total),
  );

  _activeCancelTokens.remove(task.cancelToken);
  _activeTaskIds.remove(task.id);

  if (ok) {
    task
      ..status = DownloadStatus.completed
      ..finalBytes = math.max(task.receivedBytes, math.max(task.size, 0));
    _completedBytes += task.finalBytes;
    ref.read(currentDlNoProvider.notifier).state++;
  } else {
    task.status = DownloadStatus.failed;
  }

  _updateActiveFileNames();
  _refreshAggregateProgress(force: true);

  if (ok && Platform.isWindows) {
    await WindowsTaskbar.setProgress(
        ref.read(currentDlNoProvider), ref.read(totalTaskCntProvider));
  }

  return ok;
}
```

约束：

- 任务执行前必须检查 `_cancelRequested || _runSeq != _currentRunSeq`，否则排队任务会在取消后继续启动。
- 完成后必须从 `_activeCancelTokens` 移除 token，防止集合无限增长。
- `_resumableDownload` 内部（`MultiThreadDownloader`）完全复用，不改其行为。

### 4.7 UI 适配

#### `progress_bar.dart`

- `LinearProgressIndicator.value` 继续读 `processProvider`（语义已变为全局进度）。
- 文件名文案改为 `activeFileNamesProvider`：

```dart
final activeFileNamesProvider = StateProvider<List<String>>((ref) => const []);
```

展示规则：

- 0 个活动文件 → 空。
- 1 个 → `文件名`。
- 2 个 → `A、B`。
- ≥3 个 → `A、B 等 3 个文件`。

`DownloadManager` 维护活动任务集合，在任务开始/结束时更新该 provider。

#### `download_count.dart`

保持读取 `currentDlNoProvider` / `totalTaskCntProvider`，显示格式不变 `$currentDl / $total`。

语义变化：`currentDlNoProvider` 现在是**已完成文件数**，不再「开始即 +1」。`download_providers.dart` 中对应注释同步更新。

#### `download_speed.dart`

无需改动；读的仍是聚合后的 `downloadSpeedProvider` / `downloadEtaProvider`。

#### `progress_percentage.dart`

无需改动；读 `processProvider`。

#### `ui_service.resetProgress()`

同步重置新增的 `activeFileNamesProvider`：

```dart
ref
  ..read(processProvider.notifier).state = 0
  ..read(currentDlNoProvider.notifier).state = 0
  ..read(totalTaskCntProvider.notifier).state = 0
  ..read(currentFileNameProvider.notifier).state = ''   // 兼容保留
  ..read(activeFileNamesProvider.notifier).state = const []
  ..read(downloadSpeedProvider.notifier).state = 0
  ..read(downloadEtaProvider.notifier).state = Duration.zero;
```

> `currentFileNameProvider` 保留并继续在单任务时写入最后一个文件名，避免无关引用断裂；新 UI 优先读 `activeFileNamesProvider`。

### 4.8 收尾流程

`run()` 在 `await Future.wait(workers)` 之后**原样保留**以下判断：

```dart
// 新一轮 run 已经开始，或用户取消了下载：放弃收尾
if (runSeq != _runSeq ||
    ref.read(dlStatusProvider) == DownloadStatus.canceled) {
  Log.info('download aborted: $sourceId');
  return;
}

if (_failedCnt > 0) { ... failed + snackbar ... }

... completed → worksIndex.upsert → invalidate library
    → WindowsTaskbar 闪烁 → autoOrganize → autoTranscribe
```

要点：

- 必须等**所有 worker** 结束再收尾，不能边下边注册。
- 并行执行不会改变 `_failedCnt` 的最终语义：仍为「本轮失败文件数」。
- 取消时，未开始任务因 `_cancelRequested` 检查被跳过，已开始任务由 token cancel 中断。

### 4.9 取消

`cancelAllDownload()` 逻辑不变：

```dart
void cancelAllDownload() {
  if (ref.read(dlStatusProvider) != DownloadStatus.downloading) return;

  _cancelRequested = true;
  ref.read(dlStatusProvider.notifier).state = DownloadStatus.canceled;

  for (final token in _activeCancelTokens) {
    if (!token.isCancelled) token.cancel('下载已取消');
  }
}
```

并行场景验证点：

- 多个 worker 同时持 token 时，for 循环会 cancel 全部。
- `MultiThreadDownloader` 内部 `cancelToken.whenCancel` 会联动取消所有分段 token。
- 部分任务完成、部分在途时，只 cancel 在途 token；已完成文件保留。

---

## 5. 涉及文件清单

| 文件 | 操作 |
|---|---|
| `lib/common/config_providers.dart` | 修改：新增 `parallelDownloadOptions` / `maxTotalDownloadConnections` / `parallelDownloadCountProvider` |
| `lib/pages/components/initialization.dart` | 修改：读取并校验 `parallelDownloadCount` 配置 |
| `lib/services/ui/ui_service.dart` | 修改：新增 `onParallelDownloadCountChanged`；`resetProgress` 重置活动文件名 |
| `lib/pages/downloader/config_settings/components/parallel_downloads_selector.dart` | 新建：并行文件数选择器 |
| `lib/pages/downloader/downloader.dart` | 修改：配置栏插入 `ParallelDownloadsSelector` |
| `lib/services/download/download_manager.dart` | 修改：任务拍平、worker pool、进度聚合、`_downloadTask`、收尾兼容 |
| `lib/services/download/download_providers.dart` | 修改：新增 `activeFileNamesProvider`；更新 `currentDlNoProvider` 语义注释 |
| `lib/pages/downloader/search_result/tracks_view/components/download_progress/progress_bar.dart` | 修改：活动文件名展示 |
| `lib/pages/downloader/search_result/tracks_view/components/download_progress/download_count.dart` | 修改：文案注释（逻辑兼容） |
| `test/parallel_download_test.dart` | 新建：并行下载核心测试 |
| `test/download_cancel_test.dart` | 修改/扩展：并行取消场景 |
| `test/download_threads_config_test.dart` | 扩展：并行数配置与线程数压缩 |

---

## 6. 测试计划

### 6.1 单元/组件测试

1. **任务拍平**
   - 给定多层 `Folder` + 部分选中 `FileAsset`，验证生成任务数、顺序、`savePath` 与旧串行逻辑一致。
   - 勾选封面时封面为第一个任务；封面字节不可得且 `tryGetContentLength` 失败时不生成封面任务。

2. **并发上限**
   - 本地 `HttpServer` 提供 4 个文件，配置并行数 2。
   - 服务器端记录同时在途请求数，验证 ≤ 2。
   - 配置并行数 1 时行为与旧串行等价。

3. **结果正确性**
   - 3 个不同大小文件并行下载，字节全部正确，目录树与文件名符合预期。
   - 已存在文件直接完成且不重复请求。

4. **进度聚合**
   - 不同大小文件并行：过程进度单调不降、范围 [0,1]，全部完成后 `processProvider == 1.0`。
   - `currentDlNoProvider` 最终等于完成任务数。
   - 速度 = 各活动任务速度之和；剩余时间按剩余字节 / 总速度计算。

5. **失败隔离**
   - 1 个 URL 404，其余成功：状态 `failed`，`_failedCnt == 1`（通过 snackbar/状态观察），成功文件存在且已注册进度。

6. **取消**
   - 下载中 `cancelAllDownload`：所有在途 token 被取消，最终状态 `canceled`。
   - 排队未开始的任务不会启动。
   - 已下载 part 文件保留，可续传。

7. **每文件线程数压缩**
   - `parallel = 4`、`downloadThreads = 16` → 实际 `threadCount = 4`。
   - `parallel = 2`、`downloadThreads = 4` → 实际 `threadCount = 4`（不放大）。
   - `parallel = 4`、`downloadThreads = 1` → 实际 `threadCount = 1`。

8. **配置持久化**
   - `onParallelDownloadCountChanged(3)` 写内存 + config。
   - 初始化时读回 3；非法值（如 0、5、字符串）回退 2。

9. **回归**
   - `multi_thread_downloader_test.dart` 全部通过（该文件不改）。
   - 现有下载取消、速度/ETA、UI 按钮测试全部通过。

### 6.2 手工验收

- Windows/macOS 各跑一遍真实作品下载（选 4 个音轨，并行 2）。
- 观察进度条整体推进、速度显示为聚合速度、取消后 part 残留可续传。
- 下载完成后注册表、自动整理、自动转写行为与旧版一致。

---

## 7. 验收标准（Definition of Done）

- [ ] `parallelDownloadCountProvider` 默认 2，可在 UI 选择 1/2/3/4，重启后保持。
- [ ] 并行数 = N 时，同时在途文件数 ≤ N。
- [ ] 并行下载结果与串行下载逐字节一致。
- [ ] 进度条 / 百分比 / 速度 / ETA 为全局聚合值，不再被多任务互相覆盖。
- [ ] 单文件失败不阻塞其余文件，最终状态与 snackbar 符合现有规则。
- [ ] 取消后：无新任务启动、在途请求中断、状态为 `canceled`、断点文件保留。
- [ ] 每文件线程数满足「总连接数 ≤ 16」。
- [ ] 所有新旧测试通过，`flutter analyze` 无新增告警。
- [ ] `MultiThreadDownloader` 与下载注册表/自动整理/自动转写逻辑无回归。

---

## 8. 实施顺序（批准后）

1. **Commit 1**：配置 + UI 选择器 + 持久化（4.1）。
2. **Commit 2**：任务拍平 + worker pool，先保证 `parallel = 1` 时与旧行为完全一致（4.2、4.3、4.5、4.6）。
3. **Commit 3**：进度/速度/ETA 聚合 + UI 适配（4.4、4.7）。
4. **Commit 4**：测试补齐与回归修复（第 6 节）。
5. **Commit 5**（可选）：文档更新 `README.md` 的配置说明。

---

## 9. 风险与注意事项

| 风险 | 应对 |
|---|---|
| 连接数激增被服务器限制/封禁 | 总连接数上限 16；默认并行 2；Tooltip 说明 |
| 多文件同时写同一目录的临时文件 | `MultiThreadDownloader` 按 `savePath` 前缀管理，互不冲突，无需改动 |
| 进度回调高频刷新 UI | 任务级 500ms 速度采样 + 聚合器 100ms 节流 |
| `WindowsTaskbar.setProgress` 只接受整数 | 用「已完成文件数 / 总文件数」，不用字节进度 |
| 文件 size 缺失或为 0 | 防御性文件数兜底（4.4） |
| 同名音轨导致同名目标文件 | 现有串行逻辑已存在的边界问题，本次不扩大处理；可在任务拍平时记 warning（可选） |
| 旧一轮 run 与新 run 竞争 | 保留 `_runSeq` / `_currentRunSeq` 校验，所有 worker 与收尾逻辑都检查 |
| 测试中 `DownloadManager` 依赖真实 `AsmrApi` | 测试用 `ProviderContainer(overrides:)` 覆盖 `asmrApiProvider` / `rootFolderProvider` / `downloadPathProvider`，配本地 `HttpServer` |

---

## 10. 批准前检查点

批准本文档即表示接受以下默认值（均可单独调整）：

1. 并行文件数选项：`[1, 2, 3, 4]`，默认 `2`。
2. 总连接数上限：`16`。
3. 封面作为第一个任务参与并行；封面字节不可得且无法探测大小时跳过（与现状一致）。
4. 本次不做音轨列表逐行状态图标。
