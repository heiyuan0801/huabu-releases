import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class WebLoginPreview {
  const WebLoginPreview({required this.id, required this.status, required this.origin, required this.siteName, required this.expiresAt});
  factory WebLoginPreview.fromJson(Json data, {required String id, required String origin}) {
    final expires = DateTime.tryParse(jsonString(data['expiresAt']));
    if (data['id'] != id || data['mode'] != 'app' || data['origin'] != origin || expires == null || !const ['scanned', 'confirmed', 'rejected', 'consumed'].contains(data['status'])) {
      throw const ApiException('网页登录请求与当前站点或扫码方式不一致，请重新扫码');
    }
    return WebLoginPreview(id: id, status: data['status'] as String, origin: origin, siteName: jsonString(data['siteName']), expiresAt: expires);
  }
  final String id, status, origin, siteName;
  final DateTime expiresAt;
  WebLoginPreview withStatus(String value) => WebLoginPreview(id: id, status: value, origin: origin, siteName: siteName, expiresAt: expiresAt);
}

String appWebLoginId(String payload, String apiBaseUrl) {
  try {
    final backend = Uri.parse(apiBaseUrl), qr = Uri.tryParse(payload);
    final id = qr?.queryParameters['app_login'] ?? '';
    if (['http', 'https'].contains(backend.scheme) && backend.host.isNotEmpty && backend.userInfo.isEmpty && RegExp(r'^[a-f0-9]{64}$').hasMatch(id) && payload == '${backend.origin}/?app_login=$id') return id;
  } on FormatException {
    // Malformed or encoded QR payloads never become network addresses.
  }
  throw const ApiException('请扫描当前站点「App 扫码登录」页面生成的二维码');
}

class WebLoginRepository {
  const WebLoginRepository(this.api);
  final ApiClient api;
  String get origin => Uri.parse(api.baseUrl).origin;

  Future<Json> _request(String path, CancelToken token, {Map<String, dynamic>? body}) async {
    final response = await api.request(path, method: body == null ? 'GET' : 'POST', body: body, headers: const {'X-Huabu-QR-Mode': 'app'}, cancelToken: token);
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! Map) throw const ApiException('网页登录服务返回格式异常，请重新读取');
    return jsonObject(data);
  }

  Future<SiteData> site(CancelToken token) async {
    final data = await _request('/site', token);
    if (data['site'] is! Map || data['auth'] is! Map) throw const ApiException('服务器登录设置格式异常，请重新读取');
    return SiteData.fromJson(data);
  }

  Future<WebLoginPreview> preview(String id, CancelToken token) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) throw const ApiException('登录二维码无效，请在网页重新生成');
    return WebLoginPreview.fromJson(await _request('/auth/wechat-qr/$id/preview', token), id: id, origin: origin);
  }

  Future<String> decide(WebLoginPreview value, String action, CancelToken token, {required void Function() checkCurrent}) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value.id) || value.origin != origin || value.status != 'scanned' || !const ['confirm', 'reject'].contains(action)) throw const ApiException('登录状态已变更，请重新读取');
    final epoch = api.epoch;
    checkCurrent();
    if (action == 'confirm') {
      final current = await site(token);
      api.assertEpoch(epoch);
      checkCurrent();
      if (!current.appQrLogin) throw const ApiException('当前服务器尚未支持 App 扫码登录，请联系管理员更新服务');
    }
    api.assertEpoch(epoch);
    checkCurrent();
    final result = await _request('/auth/wechat-qr/${value.id}/decision', token, body: {'action': action});
    if (!const ['confirmed', 'rejected'].contains(result['status'])) throw const ApiException('登录授权结果未确认，请手动查询实际状态');
    return result['status'] as String;
  }
}

final webLoginRepositoryProvider = Provider((ref) => WebLoginRepository(ref.watch(apiProvider)));
