import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/web_login/web_login_page.dart';
import 'package:huabu_app/features/web_login/web_login_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

final _id = List.filled(64, 'a').join();
const _origin = 'https://example.invalid';
final _challenge = {'id': _id, 'mode': 'app', 'status': 'scanned', 'origin': _origin, 'siteName': '测试站点', 'expiresAt': '2099-01-01T00:00:00Z'};
const _user = UserAccount(id: 'fixture-account', email: 'creator@example.invalid', displayName: '测试创作者', avatarUrl: '', role: 'user', status: 'active');

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async { calls.add(options); return respond(options); }
  @override
  void close({bool force = false}) {}
}
ResponseBody _json(Object data) => ResponseBody.fromString(jsonEncode(data), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
ApiClient _api(_Adapter adapter) {
  final api = ApiClient(baseUrl: '$_origin/api')..dio.httpClientAdapter = adapter;
  api.resetAccount(_user.id);
  addTearDown(api.close);
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('本站唯一 App 登录参数可以解析', () => expect(appWebLoginId('$_origin/?app_login=$_id', '$_origin/api'), _id));
  for (final payload in [
    'https://other.invalid/?app_login=$_id', 'http://example.invalid/?app_login=$_id', '$_origin:9443/?app_login=$_id',
    '$_origin/?wechat_login=$_id', '$_origin/login?app_login=$_id', '$_origin/?app_login=$_id&extra=1',
    '$_origin/?app_login=$_id&app_login=$_id', '$_origin/?app_login=$_id#fragment', '$_origin/?app_login=${_id.toUpperCase()}',
    '$_origin/?app_login=%', 'https://name:fixture@example.invalid/?app_login=$_id', ' $_origin/?app_login=$_id',
  ]) {
    test('拒绝其他二维码协议 ${payload.replaceAll(_id, '<id>')}', () => expect(() => appWebLoginId(payload, '$_origin/api'), throwsA(isA<ApiException>())));
  }
  test('旧服务器没有实际能力标识时禁用 App 扫码', () {
    expect(SiteData.fromJson({'site': {'siteName': '测试站点'}, 'auth': {'wechatLogin': true}}).appQrLogin, isFalse);
  });
  test('预览不能把跨模式或其他站点响应显示成待确认', () {
    for (final changed in [{'mode': 'wechat'}, {'origin': 'https://other.invalid'}, {'id': 'different'}, {'status': 'pending'}]) {
      expect(() => WebLoginPreview.fromJson({..._challenge, ...changed}, id: _id, origin: _origin), throwsA(isA<ApiException>()));
    }
  });
  test('确认前核对真实能力，使用当前账号和 App 模式请求', () async {
    final adapter = _Adapter((options) => _json(options.path == '/site' ? {'site': {'siteName': '测试站点'}, 'auth': {'appQrLogin': true}} : {'status': 'confirmed'}));
    final repository = WebLoginRepository(_api(adapter));
    final preview = WebLoginPreview.fromJson(_challenge, id: _id, origin: _origin);
    final result = await repository.decide(preview, 'confirm', CancelToken(), checkCurrent: () {});
    expect(result, 'confirmed');
    expect(adapter.calls.map((request) => request.path), ['/site', '/auth/wechat-qr/$_id/decision']);
    expect(adapter.calls.last.headers['X-Huabu-QR-Mode'], 'app');
    expect(adapter.calls.last.headers['X-Account-ID'], _user.id);
    expect(adapter.calls.last.data, {'action': 'confirm'});
  });
  test('查询能力后页面或账号切换不再发送授权请求', () async {
    var current = true;
    final adapter = _Adapter((_) { current = false; return _json({'site': {'siteName': '测试站点'}, 'auth': {'appQrLogin': true}}); });
    final repository = WebLoginRepository(_api(adapter));
    await expectLater(repository.decide(WebLoginPreview.fromJson(_challenge, id: _id, origin: _origin), 'confirm', CancelToken(), checkCurrent: () {
      if (!current) throw const ApiException('页面已关闭', canceled: true);
    }), throwsA(isA<ApiException>().having((error) => error.canceled, '取消', isTrue)));
    expect(adapter.calls.length, 1);
  });
  test('服务器不支持时不发送确认请求', () async {
    final adapter = _Adapter((_) => _json({'site': {'siteName': '测试站点'}, 'auth': {}}));
    final repository = WebLoginRepository(_api(adapter));
    await expectLater(repository.decide(WebLoginPreview.fromJson(_challenge, id: _id, origin: _origin), 'confirm', CancelToken(), checkCurrent: () {}), throwsA(isA<ApiException>()));
    expect(adapter.calls.length, 1);
  });
  test('未知授权响应不能显示为成功', () async {
    final adapter = _Adapter((_) => _json({'status': 'pending'}));
    final repository = WebLoginRepository(_api(adapter));
    await expectLater(repository.decide(WebLoginPreview.fromJson(_challenge, id: _id, origin: _origin), 'reject', CancelToken(), checkCurrent: () {}), throwsA(isA<ApiException>()));
  });
  testWidgets('移动端旧服务显示不可用状态，不打开相机', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
    tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(320, 640);
    addTearDown(() { tester.view.resetDevicePixelRatio(); tester.view.resetPhysicalSize(); });
    final theme = AppTheme.dark(touch: true);
    final container = ProviderContainer.test(retry: (_, _) => null, overrides: [sessionProvider.overrideWithBuild((ref, notifier) async => _user), siteProvider.overrideWith((ref) async => const SiteData(siteName: '测试站点', terms: '', privacy: '', emailCodeLogin: false, captchaEnabled: false, emailConfigured: false, content: []))]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: theme.toApproximateMaterialTheme(), home: FTheme(data: theme, child: const Scaffold(body: WebLoginPage())))));
    await tester.pumpAndSettle();
    expect(find.text('当前服务器尚未支持 App 扫码登录'), findsOneWidget);
    expect(find.byType(MobileScanner), findsNothing);
    expect(tester.takeException(), isNull);
    } finally { debugDefaultTargetPlatformOverride = null; }
  });
}
