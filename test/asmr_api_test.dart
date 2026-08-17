import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dioError(DioExceptionType type, {String? message}) {
  return DioException(
    requestOptions: RequestOptions(path: '/test'),
    type: type,
    message: message,
  );
}

class _ThrowingApi extends AsmrApi {
  final DioException error;

  _ThrowingApi(this.error);

  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async {
    throw error;
  }

  @override
  Future<List<dynamic>?> getTracks(String id) async {
    throw error;
  }
}

class _MissingApi extends AsmrApi {
  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async => null;

  @override
  Future<List<dynamic>?> getTracks(String id) async => null;
}

void main() {
  test('describeLastError maps connection failures to the channel hint', () {
    final timeout = _dioError(DioExceptionType.connectionTimeout);
    final connection = _dioError(DioExceptionType.connectionError);

    expect(
      AsmrApi.describeLastError(timeout, 'asmr-200'),
      '无法连接当前 API 线路（asmr-200），请切换线路或开启代理后重试',
    );
    expect(
      AsmrApi.describeLastError(connection, 'asmr-200'),
      '无法连接当前 API 线路（asmr-200），请切换线路或开启代理后重试',
    );
    expect(
      AsmrApi.describeLastError(
        _dioError(DioExceptionType.badResponse, message: '服务器返回 500'),
        'asmr-200',
      ),
      '服务器返回 500',
    );
  });

  test('getWorkInfoOrThrow and getTracksOrThrow expose network errors',
      () async {
    final error = _dioError(DioExceptionType.connectionError);
    final api = _ThrowingApi(error)..setApiChannel('asmr-200');

    await expectLater(
      api.getWorkInfoOrThrow('123'),
      throwsA(predicate<Object>((e) =>
          e.toString().contains('无法连接当前 API 线路（asmr-200），请切换线路或开启代理后重试'))),
    );
    await expectLater(
      api.getTracksOrThrow('123'),
      throwsA(predicate<Object>((e) =>
          e.toString().contains('无法连接当前 API 线路（asmr-200），请切换线路或开启代理后重试'))),
    );
  });

  test('OrThrow keeps the null result for a missing work', () async {
    final api = _MissingApi();

    expect(await api.getWorkInfoOrThrow('missing'), isNull);
    expect(await api.getTracksOrThrow('missing'), isNull);
  });
}
