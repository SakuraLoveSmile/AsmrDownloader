import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'package:path/path.dart' as p;

class DownloadManager {
  final Ref ref;
  DownloadManager(this.ref);

  /// 最新一轮 run() 的序号（新一轮 run 会使旧一轮让位）
  int _runSeq = 0;

  /// 当前正在执行下载循环的那一轮序号
  int _currentRunSeq = 0;

  /// 用户请求取消（cancelAllDownload 置位，run() 开始时复位）
  bool _cancelRequested = false;

  /// 本轮正在下载的所有 CancelToken（含封面），取消时统一 cancel
  final Set<CancelToken> _activeCancelTokens = {};

  /// 本轮下载失败（返回 false）的文件数
  int _failedCnt = 0;

  Future<void> run() async {
    final runSeq = ++_runSeq;
    _currentRunSeq = runSeq;
    _cancelRequested = false;
    _activeCancelTokens.clear();
    _failedCnt = 0;

    await ref.read(uiServiceProvider).resetProgress();

    // handle error

    final sourceId = ref.read(sourceIdProvider);
    if (sourceId == null) {
      Log.fatal('download failed\n' 'error: sourceId is null');
      ref.read(uiServiceProvider).showSnack('下载失败：请先搜索作品');
      return;
    }

    // 标题/目录名为空（title 降级链尚未给出保底值）时拒绝下载
    final voiceWorkPath = ref.read(voiceWorkPathProvider);
    if (p.basename(voiceWorkPath) == '-' ||
        p.equals(voiceWorkPath, ref.read(downloadPathProvider))) {
      Log.error('download failed: $sourceId\n'
          'error: voiceWorkPath is invalid, which means you have to start downloading after work info is loaded');
      ref.read(uiServiceProvider).showSnack('下载失败：请等待作品信息加载完成后再下载');
      return;
    }

    // start downloading

    ref.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;
    ref.read(currentDlNoProvider.notifier).state = 0;

    // root Folder cnt
    int rootFolderTaskCnt = 0;
    final rootFolderSnapshot = ref.read(rootFolderProvider)?.copyWith();
    if (rootFolderSnapshot == null) {
      Log.fatal(
          'download tracks failed: $sourceId\n' 'error: rootFolder is null');
      ref.read(uiServiceProvider).showSnack('下载失败：音轨列表为空，请重新搜索');
    } else {
      rootFolderTaskCnt = countTotalTask(rootFolderSnapshot);
      ref.read(totalTaskCntProvider.notifier).state = rootFolderTaskCnt;
    }

    // download cover
    if (ref.read(dlCoverProvider)) {
      ref.read(totalTaskCntProvider.notifier).state++;
      await _downloadCover(p.join(
        voiceWorkPath,
        sourceId,
        '${sourceId}_cover.jpg',
      ));
    }

    // download root folder
    if (rootFolderTaskCnt > 0) {
      await _downloadTrackItem(rootFolderSnapshot!, voiceWorkPath);
    }

    // download finished (completed / canceled / failed)

    // 新一轮 run 已经开始，或用户取消了下载：放弃收尾，避免旧流程覆盖新状态
    if (runSeq != _runSeq ||
        ref.read(dlStatusProvider) == DownloadStatus.canceled) {
      Log.info('download aborted: $sourceId');
      return;
    }

    if (_failedCnt > 0) {
      Log.error('download failed: $sourceId\n'
          'failed task count: $_failedCnt');
      ref.read(dlStatusProvider.notifier).state = DownloadStatus.failed;
      ref.read(uiServiceProvider)
          .showSnack('下载失败：$_failedCnt 个文件下载失败，可点击「重试」');
      return;
    }

    ref.read(dlStatusProvider.notifier).state = DownloadStatus.completed;

    // 写入下载注册表（批量整理的数据源）；
    // 自动整理成功后会由 organizeCurrentWork 补录 organizedAt
    await ref.read(worksIndexProvider).upsert(WorkEntry(
      sourceId: sourceId,
      dlPath: ref.read(downloadPathProvider),
      dirName: p.basename(voiceWorkPath),
      title: ref.read(titleProvider),
      cvNames: ref.read(cvLsProvider).join('&'),
      circleName: ref.read(circleNameProvider),
      releaseDate: ref.read(releaseDateProvider),
      tags: ref.read(tagLsProvider),
      coverUrl: ref.read(coverUrlProvider),
    ));
    if (Platform.isWindows) {
      await WindowsTaskbar.setFlashTaskbarAppIcon(
        mode: TaskbarFlashMode.all | TaskbarFlashMode.timernofg,
        flashCount: 5,
        timeout: const Duration(milliseconds: 500),
      );
    }

    // auto organize to navidrome
    if (ref.read(autoOrganizeProvider)) {
      await ref.read(uiServiceProvider).autoOrganize();
    }

    // auto AI subtitle translate (ChickenRice)
    if (ref.read(autoTranscribeProvider)) {
      await ref.read(uiServiceProvider).autoTranscribe(sourceId);
    }
  }

  /// 取消全部下载任务：置 canceled 状态并 cancel 本轮所有在途 CancelToken。
  /// 已开始的请求立即中断，尚未开始的任务会通过 [_cancelRequested] 跳过。
  void cancelAllDownload() {
    if (ref.read(dlStatusProvider) != DownloadStatus.downloading) return;

    _cancelRequested = true;
    ref.read(dlStatusProvider.notifier).state = DownloadStatus.canceled;

    for (final token in _activeCancelTokens) {
      if (!token.isCancelled) {
        token.cancel('下载已取消');
      }
    }
    Log.info('cancel all downloads');
  }

  int countTotalTask(Folder rootFolder) {
    int totalTaskCnt = 0;
    for (final child in rootFolder.children) {
      if (child is Folder) {
        totalTaskCnt += countTotalTask(child);
      } else if (child.selected) {
        totalTaskCnt++;
      }
    }
    return totalTaskCnt;
  }

  /// 下载cover
  Future<void> _downloadCover(String savePath) async {
    final coverName = p.basename(savePath);
    final coverBytesAsync = ref.read(coverBytesProvider);
    final bytes = coverBytesAsync.value;

    if (coverBytesAsync is AsyncData && bytes != null) {
      // set download start state
      ref.read(currentFileNameProvider.notifier).state = coverName;
      ref.read(processProvider.notifier).state = 0;
      ref.read(currentDlNoProvider.notifier).state++;

      try {
        // save cover
        final coverFile = File(savePath);
        if (!await coverFile.exists()) {
          await coverFile.create(recursive: true);
        }
        if ((await coverFile.length()) != bytes.length) {
          await coverFile.writeAsBytes(bytes);
        }

        // set download completed state
        ref.read(processProvider.notifier).state = 1;
        if (Platform.isWindows) {
          await WindowsTaskbar.setProgress(
              ref.read(currentDlNoProvider), ref.read(totalTaskCntProvider));
        }

        Log.info('save cover completed: $coverName' 'savePath: $savePath');
      } catch (e) {
        Log.error('save cover failed: $coverName\n'
            'error: $e');
      }
    } else {
      Log.warning('save cover failed: $coverName\n'
          'error: cover bytes is not ready');

      final coverUrl = ref.read(coverUrlProvider);
      final int? coverSize =
          await ref.read(asmrApiProvider).tryGetContentLength(coverUrl);

      if (coverSize != null) {
        FileAsset coverFileAsset = FileAsset(
          id: coverName,
          type: 'image',
          title: coverName,
          mediaStreamUrl: coverUrl,
          mediaDownloadUrl: coverUrl,
          size: coverSize,
          savePath: savePath,
        )..selected = true;
        await _downloadFileAsset(coverFileAsset);
      } else {
        Log.error('download cover failed: $coverName\n'
            'error: cover size is null');
      }
    }
  }

  Future<void> _downloadTrackItem(
      TrackItem trackItem, String targetDirPath) async {
    final targetPath = p.join(
      targetDirPath,
      getLegalWindowsName(trackItem.title),
    );
    if (trackItem is Folder) {
      for (final child in trackItem.children) {
        await _downloadTrackItem(child, targetPath);
      }
    } else if (trackItem is FileAsset) {
      if (trackItem.selected) {
        trackItem.savePath = targetPath;
        await _downloadFileAsset(trackItem);
      }
    }
  }

  // 开始下载任务
  /// need to specify task.savePath otherwise it will be empty
  Future<void> _downloadFileAsset(FileAsset task) async {
    // 已取消或已有新一轮下载开始时，跳过排队中的任务
    if (_cancelRequested || _runSeq != _currentRunSeq) return;
    _activeCancelTokens.add(task.cancelToken);

    ref.read(currentFileNameProvider.notifier).state = task.title;
    ref.read(processProvider.notifier).state = 0;
    ref.read(currentDlNoProvider.notifier).state++;

    // 重置速度/剩余时间
    ref
      ..read(downloadSpeedProvider.notifier).state = 0
      ..read(downloadEtaProvider.notifier).state = Duration.zero;

    var lastBytes = 0;
    final stopwatch = Stopwatch()..start();
    final dlFlag = await _resumableDownload(
      task.mediaDownloadUrl,
      task.savePath,
      task.size,
      cancelToken: task.cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final progress = received / total;
          // task.progress = progress;
          ref.read(processProvider.notifier).state = progress;

          // 每 500ms 用增量计算一次下载速度，避免累计误差
          final elapsedMs = stopwatch.elapsedMilliseconds;
          if (elapsedMs >= 500) {
            final speed = (received - lastBytes) * 1000 / elapsedMs;
            ref.read(downloadSpeedProvider.notifier).state = speed;
            lastBytes = received;
            stopwatch.reset();
          }

          // 剩余时间 = 剩余字节 / 当前速度
          final speedNow = ref.read(downloadSpeedProvider);
          if (speedNow > 0) {
            final remainingSeconds = ((total - received) / speedNow).round();
            ref.read(downloadEtaProvider.notifier).state =
                Duration(seconds: remainingSeconds);
          }
        }
      },
    );

    if (dlFlag) {
      // 如果文件已存在，不会调用onReceiveProgress，需要手动设置进度

      // task.status = DownloadStatus.completed;
      // task.progress = 1;

      ref.read(processProvider.notifier).state = 1;
      ref
        ..read(downloadSpeedProvider.notifier).state = 0
        ..read(downloadEtaProvider.notifier).state = Duration.zero;
      if (Platform.isWindows) {
        await WindowsTaskbar.setProgress(
            ref.read(currentDlNoProvider), ref.read(totalTaskCntProvider));
      }
    } else {
      _failedCnt++;
    }
  }

  Future<void> mergeFile(File file, File tmpFile) async {
    if (await tmpFile.exists()) {
      await file.writeAsBytes(
        await tmpFile.readAsBytes(),
        mode: FileMode.append,
      );
      await tmpFile.delete();
    }
  }

  Future<bool> _resumableDownload(
    String url,
    String savePath,
    int fileSize, {
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final fileName = p.basename(savePath);
    final file = File(savePath);

    final downloadingPath = '$savePath.downloading';
    final downloadingFile = File(downloadingPath);

    final tmpSavePath = '$savePath.downloading.part';
    final tmpFile = File(tmpSavePath);

    // 本地已经下载的文件大小
    int downloadedBytes = 0;
    int tmpFileLen = 0;

    while (true) {
      try {
        // 取消后不再继续重试/开始新请求
        if (_cancelRequested || cancelToken?.isCancelled == true) {
          Log.warning('download canceled: $fileName');
          return false;
        }

        if (await file.exists()) {
          Log.info('file already downloaded: $fileName\n'
              'savePath: $savePath');
          return true;
        }

        if (await downloadingFile.exists()) {
          downloadedBytes = await downloadingFile.length();
        }

        if (await tmpFile.exists()) {
          tmpFileLen = await tmpFile.length();
          if (tmpFileLen > 0 && tmpFileLen + downloadedBytes <= fileSize) {
            downloadedBytes += tmpFileLen;
            await mergeFile(downloadingFile, tmpFile);
          } else {
            await tmpFile.delete();
          }
        }

        if (downloadedBytes < fileSize) {
          if (downloadedBytes == 0) {
            Log.info('start downloading: $fileName\n'
                'fileSize: ${getSizeString(fileSize)}\n'
                'url: $url\n'
                'savePath: $savePath');
            await ref.read(asmrApiProvider).download(
                  url,
                  downloadingPath,
                  cancelToken: cancelToken,
                  deleteOnError: false,
                  onReceiveProgress: onReceiveProgress,
                );
          } else {
            Log.info('resume downloading: $fileName\n'
                'downloadedSize: ${getSizeString(downloadedBytes)}, fileSize: ${getSizeString(fileSize)}\n'
                'url: $url\n'
                'savePath: $savePath');
            await ref.read(asmrApiProvider).download(
              url,
              tmpSavePath,
              cancelToken: cancelToken,
              deleteOnError: false,
              onReceiveProgress: (received, total) {
                onReceiveProgress!(received + downloadedBytes, fileSize);
              },
              options: Options(
                  headers: {'range': 'bytes=$downloadedBytes-$fileSize'}),
            );
          }
        } else if (downloadedBytes == fileSize) {
          if (downloadedBytes == 0) {
            await file.create();
          } else {
            await downloadingFile.rename(savePath);
          }

          Log.info('download completed: $fileName');
          return true;
        } else {
          // downloadedBytes > fileSize

          Log.error('download failed: $fileName\n'
              'error: downloadedBytes > fileSize');
          return false;
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          Log.warning('download canceled: $fileName\n' 'error: $e');
          return false;
        }

        if (e.response?.statusCode == 416) {
          Log.error('download failed: $fileName\n'
              'statusCode = 416, range incorrect\n'
              'error: $e');
          return false;
        }

        Log.warning('download failed: $fileName\n' 'error: $e');
        await Future.delayed(Duration(seconds: 3));
      } catch (e) {
        Log.error('download failed: $fileName\n' 'unhandled error: $e');
        return false;
      } finally {
        await mergeFile(downloadingFile, tmpFile);
      }
    }
  }

  // 取消下载任务
  void cancelDownload(FileAsset task) {
    if (!task.cancelToken.isCancelled) {
      task.cancelToken.cancel('下载已取消');
    }
  }
}
