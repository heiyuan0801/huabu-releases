import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:mime/mime.dart';

import '../models.dart';

const defaultApiBaseUrl = 'https://image.iyuns.com/api';

class ApiException implements Exception {
  const ApiException(this.message, {this.status = 0, this.canceled = false, this.verificationRequired = false});
  final String message;
  final int status;
  final bool canceled;
  final bool verificationRequired;
  @override
  String toString() => message;
}

class StorageRecord {
  const StorageRecord({required this.value, required this.revision, required this.blob});
  final Object? value;
  final String revision;
  final bool blob;
}

class ApiClient {
  ApiClient({String baseUrl = defaultApiBaseUrl, CookieJar? cookieJar}) : cookieJar = cookieJar ?? CookieJar() {
    dio = Dio(BaseOptions(baseUrl: baseUrl.replaceFirst(RegExp(r'/+$'), ''), contentType: Headers.jsonContentType));
    dio.interceptors.add(CookieManager(this.cookieJar));
  }
  late final Dio dio;
  final CookieJar cookieJar;
  String accountId = '';
  int epoch = 0;
  void Function()? onUnauthorized;
  CancelToken _scope = CancelToken();
  final _pageRequests = <CancelToken>{};
  String get baseUrl => dio.options.baseUrl;

  void resetAccount(String id) {
    _scope.cancel('账号已切换');
    for (final token in _pageRequests) { token.cancel('账号已切换'); }
    _pageRequests.clear();
    _scope = CancelToken();
    accountId = id;
    epoch++;
  }

  void assertEpoch(int value) {
    if (epoch != value) throw const ApiException('账号已切换，本次操作已取消', canceled: true);
  }

  Future<Response<dynamic>> request(String path, {String method = 'GET', Object? body, Map<String, dynamic>? query, Map<String, dynamic>? headers, ResponseType responseType = ResponseType.json, CancelToken? cancelToken}) async {
    if (Uri.parse(path).hasScheme) throw const ApiException('外部请求必须通过项目服务器代理');
    final generation = epoch;
    if (cancelToken != null) _pageRequests.add(cancelToken);
    try {
      final response = await dio.request<dynamic>(path, data: body, queryParameters: query, cancelToken: cancelToken ?? _scope, options: Options(method: method, responseType: responseType, headers: {if (accountId.isNotEmpty) 'X-Account-ID': accountId, ...?headers}, contentType: body is FormData ? Headers.multipartFormDataContentType : null));
      assertEpoch(generation);
      return response;
    } on DioException catch (error) {
      if (generation != epoch || CancelToken.isCancel(error)) throw const ApiException('操作已取消', canceled: true);
      final response = error.response;
      Object? value = response?.data;
      if (value is List<int>) value = utf8.decode(value, allowMalformed: true);
      if (value is String) {
        try { value = jsonDecode(value); } on FormatException { value = null; }
      }
      final payload = jsonObject(value);
      final upstream = payload['error'];
      final message = upstream is String ? upstream : jsonString(jsonObject(upstream)['message']);
      // 代理保留上游 401，带请求编号的响应不能使本站会话退出。
      if (response?.statusCode == 401 && accountId.isNotEmpty && response?.headers.value('X-Huabu-Request-ID') == null) onUnauthorized?.call();
      throw ApiException(message.isNotEmpty ? message : response == null ? '无法连接服务器，请检查网络后重试' : '服务器请求失败（${response.statusCode}）', status: response?.statusCode ?? 0, verificationRequired: payload['verificationRequired'] == true);
    } finally { if (cancelToken != null) _pageRequests.remove(cancelToken); }
  }

  Json _json(Response<dynamic> response) {
    var value = response.data;
    if (value is String) {
      try { value = jsonDecode(value); }
      on FormatException { throw const ApiException('接口返回了非 JSON 响应，当前客户端暂不能读取该格式，请在任务记录核对'); }
    }
    if (value is! Map) throw const ApiException('服务器返回格式异常，请稍后重试');
    return jsonObject(value);
  }

  Future<Json> get(String path, {Map<String, dynamic>? query, Map<String, dynamic>? headers}) async => _json(await request(path, query: query, headers: headers));
  Future<Json> post(String path, [Object? body, Map<String, dynamic>? headers]) async => _json(await request(path, method: 'POST', body: body, headers: headers));
  Future<Json> put(String path, Object? body, {Map<String, dynamic>? headers}) async => _json(await request(path, method: 'PUT', body: body, headers: headers));
  Future<Json> patch(String path, Object? body) async => _json(await request(path, method: 'PATCH', body: body));

  String _storagePath(String namespace, String key) => '/storage/${Uri.encodeComponent(namespace)}/${Uri.encodeComponent(key)}';
  Future<List<String>> storageKeys(String namespace) async => ((await get('/storage/${Uri.encodeComponent(namespace)}'))['keys'] as List).cast<String>();
  Future<StorageRecord?> storageRead(String namespace, String key) async {
    final response = await request(_storagePath(namespace, key), responseType: ResponseType.bytes);
    if (response.statusCode == 204) return null;
    final blob = response.headers.value('X-Storage-Blob') == '1';
    final bytes = Uint8List.fromList((response.data as List).cast<int>());
    return StorageRecord(value: blob ? bytes : jsonDecode(utf8.decode(bytes)), revision: response.headers.value('X-Storage-Revision') ?? '0', blob: blob);
  }

  Future<String> storageWrite(String namespace, String key, Object? value, {required String revision, String? mimeType}) async {
    final blob = value is Uint8List;
    final response = await request(_storagePath(namespace, key), method: 'PUT', body: blob ? Stream<List<int>>.value(value) : jsonEncode(value), headers: {'X-Storage-Revision': revision, 'X-Storage-Blob': blob ? '1' : '0', 'Content-Type': blob ? mimeType ?? 'application/octet-stream' : Headers.jsonContentType, if (blob) Headers.contentLengthHeader: value.length});
    return response.headers.value('X-Storage-Revision') ?? revision;
  }

  Future<void> storageDelete(String namespace, String key) async { await request(_storagePath(namespace, key), method: 'DELETE'); }

  Future<MediaBytes> file(String source, {Map<String, dynamic>? headers}) async {
    try {
      if (source.startsWith('data:')) {
        final data = UriData.parse(source);
        return _media(data.contentAsBytes(), data.mimeType);
      }
      final uri = Uri.parse(source);
      if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') throw const ApiException('图片地址不可用，请从服务器附件重新读取');
      final backend = Uri.parse(baseUrl);
      final local = uri.hasScheme && uri.origin == backend.origin;
      final path = uri.hasScheme ? local ? '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}' : '/proxy' : source;
      final target = path.startsWith('/api/') ? path.substring(4) : path;
      final response = await request(target, query: uri.hasScheme && !local ? {'url': source} : null, headers: headers, responseType: ResponseType.bytes);
      return _media((response.data as List).cast<int>(), (response.headers.value('Content-Type') ?? 'application/octet-stream').split(';').first);
    } on FormatException {
      throw const ApiException('图片地址或数据格式异常，请在任务记录核对');
    }
  }

  MediaBytes _media(List<int> data, String mime) {
    final bytes = Uint8List.fromList(data);
    return MediaBytes(bytes: bytes, mimeType: lookupMimeType('', headerBytes: bytes) ?? mime);
  }

  void close() {
    _scope.cancel('应用已关闭');
    for (final token in _pageRequests) { token.cancel('应用已关闭'); }
    _pageRequests.clear();
    dio.close();
  }
}
