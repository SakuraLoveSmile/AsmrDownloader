import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/cache/rate_limiter.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class AsmrApi {
  final Dio _apiDio;

  DioException? _lastDioException;
  static DioException? _lastDescribedDioException;
  static String _lastApiChannel = '';

  /// 全局速率限制器：控制任意两次 API 请求间至少间隔 minInterval。
  /// 仅包裹 _requestWithRetry 内的实际网络请求，不影响下载等大流量传输。
  final RateLimiter? _rateLimiter;

  String _proxy = 'DIRECT';
  String _apiChannel = '';

  String get proxy => _proxy;

  set proxy(String proxy) {
    _proxy = proxy;
    _apiDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => proxy;
        return client;
      },
    );

    Log.info('proxy set to: $proxy');
  }

  AsmrApi({RateLimiter? rateLimiter, Dio? dio})
      : _apiDio = dio ?? Dio(),
        _rateLimiter = rateLimiter {
    _apiDio.options
      ..connectTimeout = Duration(seconds: 5)
      ..sendTimeout = Duration(seconds: 10)
      ..receiveTimeout = Duration(seconds: 15);
  }

  void setApiChannel(String apiChannel) {
    _apiChannel = apiChannel;
    _apiDio.options.baseUrl = 'https://api.$apiChannel.com/api/';

    Log.info('api channel set to: $apiChannel');
  }

  /// 将最后一次 Dio 网络错误转换为用户可读的提示。
  ///
  /// 可选参数仅供调用方直接格式化指定错误；不传时使用最近一次请求记录。
  static String describeLastError([
    DioException? error,
    String? apiChannel,
  ]) {
    final lastError = error ?? _lastDescribedDioException;
    if (lastError == null) return '未知网络错误';

    if (lastError.type == DioExceptionType.connectionTimeout ||
        lastError.type == DioExceptionType.connectionError) {
      final channel = apiChannel ?? _lastApiChannel;
      return '无法连接当前 API 线路（${channel.isEmpty ? '未知' : channel}），'
          '请切换线路或开启代理后重试';
    }

    return lastError.message?.isNotEmpty == true
        ? lastError.message!
        : lastError.toString();
  }

  /// Logs in the user and updates the authorization header.
  Future<void> login(String name, String password) async {
    try {
      final response = await _apiDio.post(
        'auth/me',
        data: {'name': name, 'password': password},
      );

      if (response.statusCode == 200) {
        final token = response.data['token'];
        _apiDio.options.headers['Authorization'] = 'Bearer $token';

        Log.info('login successfully');
      } else {
        Log.error('login failed with status code: ${response.statusCode}');
      }
    } on DioException catch (e) {
      Log.error('login failed: ${e.message}');
    } catch (e) {
      Log.error('unexpected error during login: $e');
    }
  }

  Future<Response<T>?> _requestWithRetry<T>(
    Future<Response<T>> Function() request, {
    required String method,
    required String path,
    int maxTry = 3,
  }) async {
    int tryCount = 0;
    _lastDioException = null;
    while (tryCount < maxTry) {
      try {
        tryCount++;
        // 发出请求前先过速率限制（重试同样受控，保证对网站的总请求频率可预期）
        final response = await _rateLimiter?.gate(request) ?? await request();
        Log.info('[$method] request to "$path" succeeded');
        return response;
      } on DioException catch (e) {
        _lastDioException = e;
        _lastDescribedDioException = e;
        _lastApiChannel = _apiChannel;
        Log.warning('[$method] request to "$path" failed\n'
            'current try: $tryCount\n'
            'error: $e');
        if (tryCount < maxTry) {
          await Future.delayed(Duration(seconds: 1));
        }
      } catch (e) {
        Log.error('[$method] request to "$path" failed\n'
            'current try: $tryCount\n'
            'unhandled error: $e');
        return null;
      }
    }

    Log.error('[$method] request to "$path" failed after $maxTry tries');
    return null;
  }

  Future<Response<T>?> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    int maxTry = 3,
  }) {
    return _requestWithRetry(
      () => _apiDio.get<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      ),
      method: 'GET',
      path: path,
      maxTry: maxTry,
    );
  }

  Future<Response<T>?> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
    int maxTry = 3,
  }) {
    return _requestWithRetry(
      () => _apiDio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
      method: 'POST',
      path: path,
      maxTry: maxTry,
    );
  }

  Future<Response<T>?> head<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    int maxTry = 3,
  }) {
    return _requestWithRetry(
      () => _apiDio.head<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      ),
      method: 'HEAD',
      path: path,
      maxTry: maxTry,
    );
  }

  Future<Response<dynamic>> download(
    String urlPath,
    dynamic savePath, {
    void Function(int, int)? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    Object? data,
    Options? options,
  }) {
    return _apiDio.download(
      urlPath,
      savePath,
      onReceiveProgress: onReceiveProgress,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      deleteOnError: deleteOnError,
      lengthHeader: lengthHeader,
      fileAccessMode: fileAccessMode,
      data: data,
      options: options,
    );
  }

  /// Retrieves the user's profile.
  Future<Map<String, dynamic>?> getProfile() async {
    final response = await get<Map<String, dynamic>>('auth/me');
    return response?.data;
  }

  /// Retrieves playlists with pagination and filtering.
  Future<Map<String, dynamic>?> getPlaylists({
    required int page,
    int pageSize = 12,
    String filterBy = 'all',
  }) async {
    final response = await get<Map<String, dynamic>>('playlist/get-playlists',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          'filterBy': filterBy,
        });
    return response?.data;
  }

  /// Creates a new playlist.
  Future<Map<String, dynamic>?> createPlaylist({
    required String name,
    String? description,
    int privacy = 0,
  }) async {
    final response =
        await post<Map<String, dynamic>>('playlist/create-playlist', data: {
      'name': name,
      'description': description ?? '',
      'privacy': privacy,
      'locale': 'zh-CN',
      'works': [],
    });
    return response?.data;
  }

  /// Adds works to a playlist.
  Future<Map<String, dynamic>?> addWorksToPlaylist({
    required List<String> sourceIds,
    required String plId,
  }) async {
    final response = await post<Map<String, dynamic>>(
        'playlist/add-works-to-playlist',
        data: {
          'id': plId,
          'works': sourceIds,
        });
    return response?.data;
  }

  /// Deletes a playlist.
  Future<Map<String, dynamic>?> deletePlaylist({
    required String plId,
  }) async {
    final response =
        await post<Map<String, dynamic>>('playlist/delete-playlist', data: {
      'id': plId,
    });
    return response?.data;
  }

  /// Searches for content.
  ///
  /// [content] 拼进路径作为单个路径段，必须整体 percent-encode：关键词可能是
  /// `$tag:舔耳$` / `$va:xxx$` / `$circle:xxx$` 等高级搜索语法，含中文、空格、
  /// `$`、`:` 乃至 `/`（如标签 "Cosplay/角色扮演"）。若不编码，`/` 会被按
  /// 路径分隔符拆开导致 404，未编码的中文/特殊字符也会让服务端匹配不到结果。
  Future<Map<String, dynamic>?> search({
    required String content,
    Map<String, dynamic>? params,
    int maxTry = 3,
  }) async {
    final encoded = Uri.encodeComponent(content);
    final response = await get<Map<String, dynamic>>('search/$encoded',
        queryParameters: params, maxTry: maxTry);
    return response?.data;
  }

  /// Lists works based on parameters.
  Future<Map<String, dynamic>?> listWorks({
    required Map<String, dynamic> params,
  }) async {
    final response =
        await get<Map<String, dynamic>>('works', queryParameters: params);
    return response?.data;
  }

  /// Searches by tag name.
  Future<Map<String, dynamic>?> searchByTag({
    required String tagName,
    required Map<String, dynamic> params,
  }) async {
    return await search(
      content: '\$tag:$tagName\$',
      params: params,
    );
  }

  /// Searches by VA name.
  Future<Map<String, dynamic>?> searchByVa({
    required String vaName,
    required Map<String, dynamic> params,
  }) async {
    return await search(
      content: '\$va:$vaName\$',
      params: params,
    );
  }

  Future<Map<String, dynamic>?> getWorkInfo(String id) async {
    final response = await get<Map<String, dynamic>>('work/$id');
    return response?.data;
  }

  /// 获取作品信息；网络重试耗尽时抛出可读错误，作品不存在仍返回 null。
  Future<Map<String, dynamic>?> getWorkInfoOrThrow(String id) async {
    try {
      final data = await getWorkInfo(id);
      if (data == null &&
          (_lastDioException?.type == DioExceptionType.connectionTimeout ||
              _lastDioException?.type == DioExceptionType.connectionError)) {
        throw Exception(describeLastError(_lastDioException, _apiChannel));
      }
      return data;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(describeLastError(e, _apiChannel));
      }
      rethrow;
    }
  }

  Future<List<dynamic>?> getTracks(String id) async {
    final response = await get<List<dynamic>>('tracks/$id');
    return response?.data;
  }

  /// 获取音轨；网络重试耗尽时抛出可读错误，作品不存在仍返回 null。
  Future<List<dynamic>?> getTracksOrThrow(String id) async {
    try {
      final data = await getTracks(id);
      if (data == null &&
          (_lastDioException?.type == DioExceptionType.connectionTimeout ||
              _lastDioException?.type == DioExceptionType.connectionError)) {
        throw Exception(describeLastError(_lastDioException, _apiChannel));
      }
      return data;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(describeLastError(e, _apiChannel));
      }
      rethrow;
    }
  }

  Future<int?> tryGetContentLength(String url) async {
    try {
      final response = await head(url);
      return int.parse(response!.headers.value('content-length')!);
    } catch (e) {
      Log.error('get content-length failed\n' 'url: $url\n' 'error: $e');
      return null;
    }
  }

  /// 探测文件服务器是否支持 Range 分段下载（多线程下载的前置检查）。
  /// 返回 null 表示探测本身失败（网络抖动等），由调用方按「不支持」处理。
  Future<bool?> supportsRangeDownload(String url,
      {CancelToken? cancelToken}) async {
    try {
      final response = await _apiDio.get(
        url,
        options: Options(
          headers: {'range': 'bytes=0-0'},
          responseType: ResponseType.bytes,
        ),
        cancelToken: cancelToken,
      );
      return response.statusCode == HttpStatus.partialContent;
    } on DioException catch (e) {
      Log.warning('range support probe failed\nurl: $url\nerror: $e');
      return null;
    } catch (e) {
      Log.error('range support probe failed\nurl: $url\nunhandled error: $e');
      return null;
    }
  }

  Future<Uint8List?> getCoverBytes(String url) async {
    try {
      final response = await get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response != null) {
        return Uint8List.fromList(response.data);
      } else {
        return null;
      }
    } catch (e) {
      Log.error('fetch cover image data failed.\n' 'error: $e');
      return null;
    }
  }
}
