import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/providers.dart';

enum DesktopQrMode { app, wechat }

class DesktopQrChallenge {
  const DesktopQrChallenge({required this.id, required this.value, required this.mode, required this.expiresAt});
  factory DesktopQrChallenge.fromJson(Json data, String origin, DesktopQrMode mode) {
    final id = jsonString(data['id']), parameter = mode == DesktopQrMode.app ? 'app_login' : 'wechat_login';
    final expires = DateTime.tryParse(jsonString(data['expiresAt']));
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) || data['mode'] != mode.name || data['status'] != 'pending' || data['value'] != '$origin/?$parameter=$id' || expires == null) {
      throw const ApiException('二维码与当前站点或扫码方式不一致，请重新生成');
    }
    return DesktopQrChallenge(id: id, value: data['value'] as String, mode: mode, expiresAt: expires);
  }
  final String id, value;
  final DesktopQrMode mode;
  final DateTime expiresAt;
}

class DesktopQrRepository {
  const DesktopQrRepository(this.api);
  final ApiClient api;
  String get origin => Uri.parse(api.baseUrl).origin;
  Map<String, String> get headers => {'X-Huabu-QR-Login': '1', 'Origin': origin};

  Future<Json> _request(String path, CancelToken token, {String method = 'GET', Object? body}) async {
    final response = await api.request(path, method: method, body: body, headers: headers, cancelToken: token);
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! Map) throw const ApiException('扫码服务返回格式异常，请重新生成');
    return jsonObject(data);
  }

  Future<DesktopQrChallenge> create(DesktopQrMode mode, CancelToken token) async => DesktopQrChallenge.fromJson(await _request('/auth/wechat-qr', token, method: 'POST', body: {'origin': origin, 'mode': mode.name}), origin, mode);

  Future<String> status(DesktopQrChallenge challenge, CancelToken token) async {
    final data = await _request('/auth/wechat-qr/${challenge.id}', token);
    final status = jsonString(data['status']);
    if (data['mode'] != challenge.mode.name || !['pending', 'scanned', 'confirmed', 'rejected', 'consumed'].contains(status) || DateTime.tryParse(jsonString(data['expiresAt'])) == null) throw const ApiException('扫码登录状态异常，请重新生成二维码');
    return status;
  }

  Future<void> cancel(String id) async {
    if (RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) await _request('/auth/wechat-qr/$id', CancelToken(), method: 'DELETE');
  }
}
