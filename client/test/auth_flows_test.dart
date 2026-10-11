import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/affiliate/affiliate_providers.dart';
import 'package:huabu_app/features/auth/auth_repository.dart';
import 'package:huabu_app/features/auth/login_page.dart';
import 'package:material_ui/material_ui.dart';

const _storageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _site = SiteData(siteName: '未来画布', terms: '测试用户协议', privacy: '测试隐私政策', emailCodeLogin: false, captchaEnabled: false, emailConfigured: true, content: []);
const _program = AffiliateProgram(enabled: true, inviterGrant: 20, inviteeGrant: 10, commissionEnabled: false, commissionRateBps: 0, commissionMode: 'first');
final _user = {'id': 'fixture-account', 'email': 'creator@example.invalid', 'status': 'active', 'role': 'user', 'displayName': '测试创作者'};

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async { calls.add(options); return respond(options); }
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data, {int status = 200, bool session = false}) => ResponseBody.fromString(jsonEncode(data), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType], if (session) 'set-cookie': ['huabu_session=fixture-test-session; Path=/; HttpOnly']});
ApiClient _api(_Adapter adapter) {
  final api = ApiClient(baseUrl: 'https://example.invalid/api')..dio.httpClientAdapter = adapter;
  addTearDown(api.close);
  return api;
}
ProviderContainer _container(ApiClient api, {SiteData site = _site}) => ProviderContainer.test(retry: (_, _) => null, overrides: [
  apiProvider.overrideWithValue(api),
  databaseProvider.overrideWith((ref) => throw StateError('测试禁止读取设备数据库')),
  sessionProvider.overrideWithBuild((ref, notifier) async => null),
  themeModeProvider.overrideWithBuild((ref, notifier) => ThemeMode.light),
  siteProvider.overrideWith((ref) async => site),
  affiliateProgramProvider.overrideWith((ref) async => _program),
]);
void _storage({bool fail = false, void Function(MethodCall)? observe}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, (call) async {
    observe?.call(call);
    if (fail) throw PlatformException(code: 'fixture-storage-failure');
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, null));
}
Future<GoRouter> _show(WidgetTester tester, ApiClient api, {AuthMode mode = AuthMode.login, SiteData site = _site, String inviteCode = '', Size size = const Size(390, 844), double textScale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
  final container = _container(api, site: site);
  final router = GoRouter(initialLocation: switch (mode) { AuthMode.login => '/login', AuthMode.register => '/register', AuthMode.reset => '/forgot-password' }, routes: [
    GoRoute(path: '/login', builder: (_, state) => LoginPage(initialEmail: state.uri.queryParameters['email'] ?? '')),
    GoRoute(path: '/register', builder: (_, _) => LoginPage(mode: AuthMode.register, inviteCode: inviteCode)),
    GoRoute(path: '/forgot-password', builder: (_, _) => const LoginPage(mode: AuthMode.reset)),
    GoRoute(path: '/explore', builder: (_, _) => const Scaffold(body: Text('创作首页'))),
  ]);
  addTearDown(router.dispose);
  final theme = AppTheme.light(touch: true);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(
    theme: theme.toApproximateMaterialTheme(), locale: const Locale('zh', 'CN'), supportedLocales: FLocalizations.supportedLocales,
    localizationsDelegates: FLocalizations.localizationsDelegates, routerConfig: router,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: FTheme(data: theme, child: FToaster(child: FTooltipGroup(child: child!)))),
  )));
  await tester.pumpAndSettle();
  return router;
}
Finder _field(String hint) => find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == hint);
Future<void> _enter(WidgetTester tester, String hint, String value) async { final field = _field(hint); await tester.ensureVisible(field); await tester.enterText(field, value); }
Future<void> _press(WidgetTester tester, String label) async { final button = find.descendant(of: find.byType(FButton), matching: find.text(label)).last; await tester.ensureVisible(button); await tester.tap(button); await tester.pumpAndSettle(); }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('注册 202 邮件失败保留已创建账号与待验证状态', () async {
    final adapter = _Adapter((_) => _json({'email': 'creator@example.invalid', 'emailSent': false, 'verificationRequired': true, 'message': '测试邮件服务失败'}, status: 202));
    final result = await AuthRepository(_api(adapter)).register({'email': 'creator@example.invalid', 'password': 'fixture-password', 'acceptTerms': true, 'inviteCode': 'fixture-code'}, CancelToken());
    expect(result.emailSent, isFalse);
    expect(result.email, 'creator@example.invalid');
    expect(adapter.calls.single.path, '/auth/register');
    expect((adapter.calls.single.data as Map)['inviteCode'], 'fixture-code');
  });
  test('登录错误保留服务器 verificationRequired 标记', () async {
    final api = _api(_Adapter((_) => _json({'error': '请先完成邮箱验证', 'verificationRequired': true}, status: 403)));
    await expectLater(api.post('/auth/login', {'email': 'creator@example.invalid'}), throwsA(isA<ApiException>().having((e) => e.verificationRequired, '需验证', isTrue)));
  });
  test('邮箱验证必须保存真实会话后才激活账号', () async {
    final storage = <MethodCall>[];
    _storage(observe: storage.add);
    final api = _api(_Adapter((_) => _json(_user, session: true)));
    final container = _container(api);
    await container.read(sessionProvider.notifier).verifyEmail({'email': 'creator@example.invalid', 'code': '123456'}, cancelToken: CancelToken());
    expect(container.read(sessionProvider).asData?.value?.id, 'fixture-account');
    expect(api.accountId, 'fixture-account');
    expect(storage.single.method, 'write');
    expect(storage.single.arguments['value'], contains('huabu_session=fixture-test-session'));
  });
  test('邮箱验证没有会话 Cookie 不伪造登录成功', () async {
    _storage();
    final api = _api(_Adapter((_) => _json(_user)));
    final container = _container(api);
    await expectLater(container.read(sessionProvider.notifier).verifyEmail({'email': 'creator@example.invalid', 'code': '123456'}), throwsA(isA<ApiException>().having((e) => e.message, '会话检查', contains('没有设置登录会话'))));
    expect(container.read(sessionProvider).asData?.value, isNull);
    expect(api.accountId, isEmpty);
  });
  test('账号切换后迟到注册结果被取消', () async {
    final pending = Completer<ResponseBody>();
    final api = _api(_Adapter((_) => pending.future));
    final result = AuthRepository(api).register({'email': 'creator@example.invalid'}, CancelToken());
    final assertion = expectLater(result, throwsA(isA<ApiException>().having((e) => e.canceled, '旧结果被取消', isTrue)));
    await Future<void>.delayed(Duration.zero);
    api.resetAccount('another-fixture');
    pending.complete(_json({'email': 'creator@example.invalid', 'emailSent': true, 'verificationRequired': true, 'message': '测试发送成功'}, status: 201));
    await assertion;
  });
  test('保存验证会话期间切换账号不覆盖新账号状态', () async {
    final writing = Completer<void>(), written = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, (call) async {
      if (call.method != 'write') throw StateError('取消后不应清理其他账号的安全存储');
      writing.complete();
      await written.future;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, null));
    final api = _api(_Adapter((_) => _json(_user, session: true)));
    final container = _container(api);
    final result = container.read(sessionProvider.notifier).verifyEmail({'email': 'creator@example.invalid', 'code': '123456'});
    final assertion = expectLater(result, throwsA(isA<ApiException>().having((e) => e.canceled, '已取消', isTrue)));
    await writing.future;
    api.resetAccount('another-fixture');
    written.complete();
    await assertion;
    expect(api.accountId, 'another-fixture');
    expect(container.read(sessionProvider).asData?.value, isNull);
  });
  testWidgets('注册主动勾选协议，202 转验证并重发 register 验证码', (tester) async {
    _storage();
    final adapter = _Adapter((options) => options.path == '/auth/register' ? _json({'email': 'creator@example.invalid', 'emailSent': false, 'verificationRequired': true, 'message': '测试发送失败'}, status: 202) : _json({'message': '如符合账号条件，验证码邮件已发送'}));
    await _show(tester, _api(adapter), mode: AuthMode.register, inviteCode: 'fixture-code');
    await _enter(tester, 'name@example.com', 'creator@example.invalid');
    await _enter(tester, '设置至少 8 位密码', 'fixture-password');
    await _enter(tester, '再次输入密码', 'fixture-password');
    await _press(tester, '创建账号');
    expect(adapter.calls, isEmpty);
    expect(find.text('请阅读并勾选同意用户协议与隐私政策'), findsOneWidget);
    await tester.ensureVisible(find.byType(FCheckbox));
    await tester.tap(find.byType(FCheckbox));
    await _press(tester, '创建账号');
    expect(adapter.calls, hasLength(1));
    expect((adapter.calls.single.data as Map)['acceptTerms'], isTrue);
    expect((adapter.calls.single.data as Map)['inviteCode'], 'fixture-code');
    expect(find.text('验证你的邮箱'), findsOneWidget);
    expect(find.textContaining('账号已创建，邮件发送未完成'), findsOneWidget);
    await _press(tester, '重发验证码');
    expect(adapter.calls.last.path, '/auth/send-code');
    expect((adapter.calls.last.data as Map)['purpose'], 'register');
    expect(tester.takeException(), isNull);
  });
  testWidgets('未验证密码登录转邮箱验证，验证后进入首页', (tester) async {
    _storage();
    final adapter = _Adapter((options) => options.path == '/auth/login' ? _json({'error': '请先完成邮箱验证', 'verificationRequired': true}, status: 403) : _json(_user, session: true));
    final router = await _show(tester, _api(adapter));
    await _enter(tester, 'name@example.com', 'creator@example.invalid');
    await _enter(tester, '输入账号密码', 'fixture-password');
    await _press(tester, '开始创作');
    expect(find.text('验证你的邮箱'), findsOneWidget);
    await _enter(tester, '输入 6 位邮件验证码', '123456');
    await _press(tester, '验证邮箱并登录');
    expect(adapter.calls.last.path, '/auth/verify-email');
    expect((adapter.calls.last.data as Map).containsKey('password'), isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/explore');
    expect(find.text('创作首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('找回密码发 reset 验证码，成功返回登录且不创建会话', (tester) async {
    final storage = <MethodCall>[];
    _storage(observe: storage.add);
    final adapter = _Adapter((options) => _json({'message': options.path == '/auth/send-code' ? '请查看邮箱' : '密码已更新，请重新登录'}));
    final api = _api(adapter);
    final router = await _show(tester, api, mode: AuthMode.reset);
    await _enter(tester, 'name@example.com', 'creator@example.invalid');
    await _press(tester, '获取验证码');
    expect((adapter.calls.single.data as Map)['purpose'], 'reset');
    await _enter(tester, '输入 6 位邮件验证码', '123456');
    await _enter(tester, '设置至少 8 位密码', 'fixture-password');
    await _enter(tester, '再次输入密码', 'wrong-confirmation');
    await _press(tester, '重置密码');
    expect(adapter.calls, hasLength(1));
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    await _enter(tester, '再次输入密码', 'fixture-password');
    await _press(tester, '重置密码');
    expect(adapter.calls.last.path, '/auth/reset-password');
    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('密码已更新，请重新登录'), findsOneWidget);
    expect(api.accountId, isEmpty);
    expect(storage.single.method, 'delete');
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(tester.takeException(), isNull);
  });
  testWidgets('邮箱验证码登录保留 login 用途并使用真实会话', (tester) async {
    _storage();
    final adapter = _Adapter((options) => options.path == '/auth/send-code' ? _json({'message': '如符合账号条件，验证码邮件已发送'}) : _json(_user, session: true));
    final router = await _show(tester, _api(adapter), site: const SiteData(siteName: '未来画布', terms: '', privacy: '', emailCodeLogin: true, captchaEnabled: false, emailConfigured: true, content: []));
    await _enter(tester, 'name@example.com', 'creator@example.invalid');
    await _press(tester, '获取验证码');
    expect((adapter.calls.single.data as Map)['purpose'], 'login');
    await _enter(tester, '输入 6 位邮件验证码', '123456');
    await _press(tester, '开始创作');
    expect(adapter.calls.last.path, '/auth/login');
    expect((adapter.calls.last.data as Map)['code'], '123456');
    expect((adapter.calls.last.data as Map).containsKey('password'), isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/explore');
    expect(tester.takeException(), isNull);
  });
  testWidgets('发送重置邮件后更换并清空已消费图形验证码', (tester) async {
    var captchaReads = 0;
    final adapter = _Adapter((options) => options.path == '/auth/captcha'
      ? _json({'id': 'fixture-captcha-${++captchaReads}', 'image': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII='})
      : _json({'message': '如符合账号条件，验证码邮件已发送'}));
    await _show(tester, _api(adapter), mode: AuthMode.reset, site: const SiteData(siteName: '未来画布', terms: '', privacy: '', emailCodeLogin: false, captchaEnabled: true, emailConfigured: true, content: []));
    await _enter(tester, 'name@example.com', 'creator@example.invalid');
    await _enter(tester, '输入右侧字符', '654321');
    await _press(tester, '获取验证码');
    final sent = adapter.calls.singleWhere((call) => call.path == '/auth/send-code');
    expect((sent.data as Map)['captchaId'], 'fixture-captcha-1');
    expect((sent.data as Map)['captchaCode'], '654321');
    expect((sent.data as Map)['purpose'], 'reset');
    expect(captchaReads, 2);
    final field = tester.widget<TextField>(_field('输入右侧字符'));
    expect(field.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('邮件未配置时注册不发请求', (tester) async {
    final adapter = _Adapter((_) => throw StateError('未配置邮箱时不应请求'));
    await _show(tester, _api(adapter), mode: AuthMode.register, site: const SiteData(siteName: '未来画布', terms: '', privacy: '', emailCodeLogin: false, captchaEnabled: false, emailConfigured: false, content: []));
    expect(find.text('邮件服务尚未配置'), findsOneWidget);
    final button = tester.widget<FButton>(find.ancestor(of: find.text('创建账号'), matching: find.byType(FButton)));
    expect(button.onPress, isNull);
    expect(adapter.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final scenario in [(size: const Size(1280, 640), scale: 1.0), (size: const Size(390, 844), scale: 1.8)]) {
    testWidgets('注册布局 ${scenario.size} 字号 ${scenario.scale} 无溢出', (tester) async {
      final adapter = _Adapter((_) => throw StateError('纯布局测试不应请求'));
      await _show(tester, _api(adapter), mode: AuthMode.register, size: scenario.size, textScale: scenario.scale);
      await tester.ensureVisible(find.text('创建账号'));
      await tester.pumpAndSettle();
      expect(find.text('创建账号').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(adapter.calls, isEmpty);
    });
  }
  testWidgets('离开账号页面后不显示迟到注册成功', (tester) async {
    _storage();
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((_) => pending.future);
    final router = await _show(tester, _api(adapter), mode: AuthMode.register);
    await _enter(tester, 'name@example.com', 'creator@example.invalid');
    await _enter(tester, '设置至少 8 位密码', 'fixture-password');
    await _enter(tester, '再次输入密码', 'fixture-password');
    await tester.ensureVisible(find.byType(FCheckbox));
    await tester.tap(find.byType(FCheckbox));
    final button = find.descendant(of: find.byType(FButton), matching: find.text('创建账号')).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    router.go('/explore');
    await tester.pumpAndSettle();
    pending.complete(_json({'email': 'creator@example.invalid', 'emailSent': true, 'verificationRequired': true, 'message': '已发送'}, status: 201));
    await tester.pumpAndSettle();
    expect(find.text('创作首页'), findsOneWidget);
    expect(find.text('验证你的邮箱'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
