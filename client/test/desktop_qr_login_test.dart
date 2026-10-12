import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/auth/desktop_qr_login.dart';
import 'package:huabu_app/features/auth/desktop_qr_repository.dart';
import 'package:huabu_app/features/auth/login_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _origin = 'https://example.invalid';
final _id = List.filled(64, 'a').join();
final _challenge = {'id': _id, 'mode': 'app', 'value': '$_origin/?app_login=$_id', 'status': 'pending', 'expiresAt': '2099-01-01T00:00:00Z'};
const _user = {'id': 'fixture-account', 'email': 'creator@example.invalid', 'displayName': '测试创作者', 'avatarUrl': '', 'role': 'user', 'status': 'active'};
const _site = SiteData(siteName: '测试站点', terms: '', privacy: '', emailCodeLogin: false, captchaEnabled: false, emailConfigured: false, content: [], appQrLogin: true);
const _storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async { calls.add(options); return respond(options); }
  @override
  void close({bool force = false}) {}
}
ResponseBody _json(Object value, {int status = 200, String? cookie}) => ResponseBody.fromString(jsonEncode(value), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType], if (cookie != null) HttpHeaders.setCookieHeader: [cookie]});
ApiClient _api(_Adapter adapter) {
  final api = ApiClient(baseUrl: '$_origin/api')..dio.httpClientAdapter = adapter;
  addTearDown(api.close);
  return api;
}
void _storageFixture({bool failWrite = false, void Function(MethodCall)? observe}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storage, (call) async {
    observe?.call(call);
    if (call.method == 'read') return null;
    if (call.method == 'write' && failWrite) throw PlatformException(code: 'Unexpected security result code', details: -128);
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storage, null));
}
ProviderContainer _container(ApiClient api, {SiteData site = _site}) => ProviderContainer.test(retry: (_, _) => null, overrides: [apiProvider.overrideWithValue(api), siteProvider.overrideWith((ref) async => site)]);
Widget _widget(ProviderContainer container, {VoidCallback? loggedIn}) {
  final theme = AppTheme.dark(touch: false);
  return UncontrolledProviderScope(container: container, child: MaterialApp(theme: theme.toApproximateMaterialTheme(), home: FTheme(data: theme, child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(24), child: DesktopQrLogin(mode: DesktopQrMode.app, onLoggedIn: loggedIn ?? () {}, onBusyChange: (_) {})))))));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('桌面挑战严格绑定站点、模式、编号和二维码内容', () {
    expect(DesktopQrChallenge.fromJson(_challenge, _origin, DesktopQrMode.app).value, _challenge['value']);
    for (final change in [{'id': 'bad'}, {'mode': 'wechat'}, {'value': 'https://other.invalid/?app_login=$_id'}, {'status': 'confirmed'}, {'expiresAt': 'unknown'}]) {
      expect(() => DesktopQrChallenge.fromJson({..._challenge, ...change}, _origin, DesktopQrMode.app), throwsA(isA<ApiException>()));
    }
  });
  test('小程序模式生成匹配微信协议的二维码', () {
    final value = DesktopQrChallenge.fromJson({..._challenge, 'mode': 'wechat', 'value': '$_origin/?wechat_login=$_id'}, _origin, DesktopQrMode.wechat);
    expect(value.mode, DesktopQrMode.wechat);
  });
  test('创建、状态查询和取消均带本站 Origin 与绑定 Cookie', () async {
    final adapter = _Adapter((request) => request.method == 'POST' ? _json(_challenge, cookie: 'huabu_qr_browser=fixture-browser; Path=/api/auth/wechat-qr; HttpOnly; Secure') : request.method == 'DELETE' ? _json({'ok': true}) : _json({'mode': 'app', 'status': 'scanned', 'expiresAt': _challenge['expiresAt']}));
    final repository = DesktopQrRepository(_api(adapter));
    final challenge = await repository.create(DesktopQrMode.app, CancelToken());
    expect(await repository.status(challenge, CancelToken()), 'scanned');
    await repository.cancel(challenge.id);
    expect(adapter.calls.first.data, {'origin': _origin, 'mode': 'app'});
    for (final call in adapter.calls) { expect(call.headers['Origin'], _origin); expect(call.headers['X-Huabu-QR-Login'], '1'); }
    expect(adapter.calls[1].headers[HttpHeaders.cookieHeader], contains('huabu_qr_browser=fixture-browser'));
    expect(adapter.calls[2].headers[HttpHeaders.cookieHeader], contains('huabu_qr_browser=fixture-browser'));
  });
  test('跨模式和未知查询结果不能触发 consume', () async {
    for (final data in [{'mode': 'wechat', 'status': 'confirmed'}, {'mode': 'app', 'status': 'success'}]) {
      final repository = DesktopQrRepository(_api(_Adapter((_) => _json({...data, 'expiresAt': _challenge['expiresAt']}))));
      await expectLater(repository.status(DesktopQrChallenge.fromJson(_challenge, _origin, DesktopQrMode.app), CancelToken()), throwsA(isA<ApiException>()));
    }
  });
  test('consume 成功后复用系统安全存储恢复真实账号', () async {
    final writes = <MethodCall>[];
    _storageFixture(observe: (call) { if (call.method == 'write') writes.add(call); });
    final adapter = _Adapter((_) => _json(_user, cookie: 'huabu_session=fixture-session; Path=/; HttpOnly; Secure'));
    final api = _api(adapter), container = _container(api);
    await container.read(sessionProvider.future);
    await container.read(sessionProvider.notifier).loginWithQr(_id, cancelToken: CancelToken());
    expect(container.read(sessionProvider).asData?.value?.id, _user['id']);
    expect(api.accountId, _user['id']);
    expect(writes.length, 1);
    expect((writes.single.arguments as Map)['value'], contains('huabu_session=fixture-session'));
    expect(adapter.calls.single.path, '/auth/wechat-qr/$_id/consume');
    expect(adapter.calls.single.headers['Origin'], _origin);
  });
  test('服务器未设置会话 Cookie 时不显示登录成功', () async {
    _storageFixture();
    final api = _api(_Adapter((_) => _json(_user))), container = _container(api);
    await container.read(sessionProvider.future);
    await expectLater(container.read(sessionProvider.notifier).loginWithQr(_id, cancelToken: CancelToken()), throwsA(isA<ApiException>()));
    expect(container.read(sessionProvider).asData?.value, isNull);
    expect(api.accountId, isEmpty);
  });
  test('安全存储拒绝授权后账号不激活、不重复写入', () async {
    var writes = 0;
    _storageFixture(failWrite: true, observe: (call) { if (call.method == 'write') writes++; });
    final api = _api(_Adapter((_) => _json(_user, cookie: 'huabu_session=fixture-session; Path=/; Secure'))), container = _container(api);
    await container.read(sessionProvider.future);
    await expectLater(container.read(sessionProvider.notifier).loginWithQr(_id, cancelToken: CancelToken()), throwsA(isA<PlatformException>()));
    expect(container.read(sessionProvider).asData?.value, isNull);
    expect(api.accountId, isEmpty);
    expect(writes, 1);
    expect(await api.cookieJar.loadForRequest(Uri.parse('$_origin/api/auth/me')), isEmpty);
  });
  test('旧 Cookie 不会被当作此次扫码返回的新会话', () async {
    _storageFixture();
    final api = _api(_Adapter((_) => _json(_user))), container = _container(api);
    await container.read(sessionProvider.future);
    await api.cookieJar.saveFromResponse(Uri.parse('$_origin/api/auth/me'), [Cookie('huabu_session', 'fixture-old-session')..path = '/']);
    await expectLater(container.read(sessionProvider.notifier).loginWithQr(_id, cancelToken: CancelToken()), throwsA(isA<ApiException>()));
    expect(container.read(sessionProvider).asData?.value, isNull);
    expect(api.accountId, isEmpty);
  });
  testWidgets('二维码每 2 秒查询，确认后只消费一次并完成会话恢复', (tester) async {
    _storageFixture();
    final adapter = _Adapter((request) => request.path.endsWith('/consume') ? _json(_user, cookie: 'huabu_session=fixture-session; Path=/; Secure') : request.method == 'POST' ? _json(_challenge, cookie: 'huabu_qr_browser=fixture; Path=/api/auth/wechat-qr; Secure') : _json({'mode': 'app', 'status': 'confirmed', 'expiresAt': _challenge['expiresAt']}));
    final api = _api(adapter), container = _container(api);
    var loggedIn = 0;
    await tester.pumpWidget(_widget(container, loggedIn: () => loggedIn++));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(adapter.calls.length, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(loggedIn, 1);
    expect(container.read(sessionProvider).asData?.value?.id, _user['id']);
    await tester.pump(const Duration(seconds: 6));
    expect(adapter.calls.where((request) => request.path.endsWith('/consume')).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('关闭扫码入口取消二维码，停止后续轮询', (tester) async {
    _storageFixture();
    final adapter = _Adapter((request) => request.method == 'POST' ? _json(_challenge) : _json({'ok': true}));
    final api = _api(adapter), container = _container(api);
    await tester.pumpWidget(_widget(container));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(adapter.calls.map((call) => call.method), ['POST', 'DELETE']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('未知消费结果明确提示且不会重复消费', (tester) async {
    _storageFixture();
    final adapter = _Adapter((request) => request.path.endsWith('/consume') ? _json({'error': '扫码登录结果未确认'}, status: 503) : request.method == 'POST' ? _json(_challenge) : request.method == 'DELETE' ? _json({'ok': true}) : _json({'mode': 'app', 'status': 'confirmed', 'expiresAt': _challenge['expiresAt']}));
    final api = _api(adapter), container = _container(api);
    await tester.pumpWidget(_widget(container));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会重复提交此二维码'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(adapter.calls.where((request) => request.path.endsWith('/consume')).length, 1);
    expect(container.read(sessionProvider).asData?.value, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('旧服务器不生成 App 二维码，窄桌面没有布局溢出', (tester) async {
    _storageFixture();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(320, 640);
      addTearDown(() { tester.view.resetDevicePixelRatio(); tester.view.resetPhysicalSize(); });
      final adapter = _Adapter((_) => throw StateError('不支持时禁止真实扫码请求'));
      final api = _api(adapter), container = _container(api, site: const SiteData(siteName: '测试站点', terms: '', privacy: '', emailCodeLogin: false, captchaEnabled: false, emailConfigured: false, content: []));
      await tester.pumpWidget(_widget(container));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前服务器尚未启用此扫码方式'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(adapter.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally { debugDefaultTargetPlatformOverride = null; }
  });
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('${platform.name} 窄窗口登录页可以扫码，切回账号立即取消挑战', (tester) async {
      _storageFixture();
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.devicePixelRatio = 1; tester.view.physicalSize = const Size(320, 640);
        addTearDown(() { tester.view.resetDevicePixelRatio(); tester.view.resetPhysicalSize(); });
        final adapter = _Adapter((request) => request.method == 'POST' ? _json(_challenge) : _json({'ok': true}));
        final api = _api(adapter), container = _container(api);
        final router = GoRouter(initialLocation: '/login', routes: [GoRoute(path: '/login', builder: (_, _) => const LoginPage()), GoRoute(path: '/explore', builder: (_, _) => const Scaffold(body: Text('创作首页')))]);
        addTearDown(router.dispose);
        final theme = AppTheme.dark(touch: false);
        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(
          theme: theme.toApproximateMaterialTheme(), routerConfig: router, locale: const Locale('zh', 'CN'), supportedLocales: FLocalizations.supportedLocales, localizationsDelegates: FLocalizations.localizationsDelegates,
          builder: (_, child) => FTheme(data: theme, child: child!),
        )));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('手机 App 扫码'));
        await tester.tap(find.text('手机 App 扫码'));
        await tester.pumpAndSettle();
        expect(find.byType(QrImageView), findsOneWidget);
        await tester.ensureVisible(find.text('账号登录'));
        await tester.tap(find.text('账号登录'));
        await tester.pumpAndSettle();
        expect(find.byType(QrImageView), findsNothing);
        expect(adapter.calls.map((call) => call.method), ['POST', 'DELETE']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally { debugDefaultTargetPlatformOverride = null; }
    });
  }
}
