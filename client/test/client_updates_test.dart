import 'dart:async';
import 'dart:convert';

import 'package:auto_updater/auto_updater.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/updates/client_updates.dart';
import 'package:huabu_app/features/updates/update_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

Map<String, dynamic> _manifest({String version = '1.2.3', int build = 4, bool downloads = true, bool feeds = true}) => {
  'schemaVersion': 1, 'version': version, 'buildNumber': build, 'notes': '修复创作工作区并改善更新提示',
  'downloads': downloads ? {for (final platform in ['macos', 'windows', 'android', 'ios']) platform: 'https://fixture.invalid/releases/$platform'} : <String, String>{},
  'appcasts': feeds ? {'macos': 'https://fixture.invalid/appcast-macos.xml', 'windows': 'https://fixture.invalid/appcast-windows.xml'} : <String, String>{},
};
PackageInfo _installed({String version = '1.2.3', String build = '3'}) => PackageInfo(appName: '测试画布', packageName: 'fixture.app', version: version, buildNumber: build);

class _ReadOnlyAdapter implements HttpClientAdapter {
  _ReadOnlyAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.method != 'GET' || requestStream != null) throw StateError('更新测试只允许无请求体的只读 GET');
    requests.add(options);
    return respond(options);
  }
  @override
  void close({bool force = false}) {}
}

Widget _app(ProviderContainer container, Widget child, {double scale = 1}) {
  final theme = AppTheme.light(touch: true);
  return UncontrolledProviderScope(container: container, child: MaterialApp(
    theme: theme.toApproximateMaterialTheme(), locale: const Locale('zh', 'CN'),
    supportedLocales: FLocalizations.supportedLocales, localizationsDelegates: FLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: FTheme(data: theme, child: FToaster(child: FTooltipGroup(child: child!)))),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

ProviderContainer _container({ClientRelease? release, bool ready = false, Future<ClientRelease?> Function()? load}) => ProviderContainer.test(overrides: [
  packageInfoProvider.overrideWith((ref) async => _installed()),
  clientReleaseProvider.overrideWith((ref) => load?.call() ?? Future.value(release)),
  nativeUpdateReadyProvider.overrideWith((ref) async => ready),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('发布清单仅解析已发布的真实平台 HTTPS 地址', () async {
    final adapter = _ReadOnlyAdapter((request) => ResponseBody.fromString(jsonEncode(_manifest()), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]}));
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final container = ProviderContainer.test(overrides: [clientReleaseDioProvider.overrideWithValue(dio)]);
    final release = (await container.read(clientReleaseProvider.future))!;
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.uri.toString(), updateManifestUrl);
    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
    expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
    expect(release.downloads.keys, ['macos', 'windows', 'android', 'ios']);
    expect(release.appcasts.keys, ['macos', 'windows']);
    expect(release.newerThan(_installed()), isTrue);
  });

  test('发行资产为二进制MIME时仍使用标准JSON解析清单', () async {
    final dio = Dio()..httpClientAdapter = _ReadOnlyAdapter((request) => ResponseBody.fromString(jsonEncode(_manifest()), 200, headers: {Headers.contentTypeHeader: ['application/octet-stream']}));
    addTearDown(() => dio.close(force: true));
    final container = ProviderContainer.test(overrides: [clientReleaseDioProvider.overrideWithValue(dio)]);
    expect((await container.read(clientReleaseProvider.future))!.version.toString(), '1.2.3');
  });

  test('公开发行渠道404保留错误且不重试或冒充最新版本', () async {
    final adapter = _ReadOnlyAdapter((request) => ResponseBody.fromString('{"message":"Not Found"}', 404, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]}));
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final container = ProviderContainer.test(overrides: [clientReleaseDioProvider.overrideWithValue(dio)]);
    await expectLater(container.read(clientReleaseProvider.future), throwsA(isA<DioException>().having((error) => error.response?.statusCode, '404', 404)));
    await container.pump();
    expect(adapter.requests, hasLength(1));
    expect(container.read(clientReleaseProvider).hasError, isTrue);
    expect(container.read(clientReleaseProvider).asData, isNull);
  });

  test('发布清单跳转到HTTP或带凭据地址时拒绝采用内容', () async {
    for (final finalUri in ['http://fixture.invalid/flutter-release.json', 'https://user:secret@fixture.invalid/flutter-release.json']) {
      final adapter = _ReadOnlyAdapter((request) => ResponseBody.fromString(jsonEncode(_manifest()), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]})..redirects = [RedirectRecord(302, 'GET', Uri.parse(finalUri))]);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final container = ProviderContainer.test(overrides: [clientReleaseDioProvider.overrideWithValue(dio)]);
      await expectLater(container.read(clientReleaseProvider.future), throwsFormatException);
      expect(container.read(clientReleaseProvider).asData, isNull);
    }
  });

  test('未发布平台可缺省但必须有明确的清单版本与地址映射', () {
    final release = ClientRelease.fromJson(_manifest(downloads: false, feeds: false));
    expect(release.downloads, isEmpty);
    expect(release.appcasts, isEmpty);
    for (final invalid in [null, [], <String, dynamic>{}, {..._manifest(), 'schemaVersion': 2}, {..._manifest(), 'buildNumber': '4'}, {..._manifest(), 'buildNumber': 4.0}, {..._manifest(), 'buildNumber': 0}, {..._manifest(), 'version': 'not-a-version'}, {..._manifest(), 'notes': null}, {..._manifest(), 'downloads': []}, {..._manifest(), 'appcasts': null}, {..._manifest(), 'downloads': {'linux': 'https://fixture.invalid/linux'}}, {..._manifest(), 'downloads': {'macos': 123}}]) {
      expect(() => ClientRelease.fromJson(invalid), throwsFormatException, reason: '$invalid');
    }
  });

  test('清单中的下载及更新源拒绝 HTTP、凭据与片段', () {
    for (final url in ['http://fixture.invalid/file', 'file:///tmp/update.zip', 'javascript:alert(1)', '/relative', 'https:///missing-host', 'https://user:secret@fixture.invalid/file', 'https://fixture.invalid/file#fragment']) {
      expect(() => releaseUri(url), throwsFormatException, reason: url);
      for (final field in ['downloads', 'appcasts']) {
        expect(() => ClientRelease.fromJson({..._manifest(), field: {'macos': url}}), throwsFormatException, reason: '$field $url');
      }
    }
  });

  for (final sample in [
    (version: '1.2.4', build: 1, installedVersion: '1.2.3', installedBuild: '100', newer: true),
    (version: '1.2.3', build: 4, installedVersion: '1.2.3', installedBuild: '3', newer: true),
    (version: '1.2.3', build: 4, installedVersion: '1.2.3', installedBuild: '4', newer: false),
    (version: '1.2.3', build: 4, installedVersion: '1.2.3', installedBuild: '5', newer: false),
    (version: '1.2.2', build: 100, installedVersion: '1.2.3', installedBuild: '1', newer: false),
    (version: '1.2.3', build: 4, installedVersion: '1.2.3-beta.1', installedBuild: '100', newer: true),
    (version: '1.2.3-beta.1', build: 4, installedVersion: '1.2.3', installedBuild: '1', newer: false),
    (version: '1.2.3', build: 4, installedVersion: '1.2.3', installedBuild: '', newer: false),
  ]) {
    test('版本 ${sample.version}+${sample.build} 与 ${sample.installedVersion}+${sample.installedBuild} 比较', () {
      expect(ClientRelease.fromJson(_manifest(version: sample.version, build: sample.build)).newerThan(_installed(version: sample.installedVersion, build: sample.installedBuild)), sample.newer);
    });
  }

  test('没有签名公钥时不启动原生更新器', () async {
    final container = _container();
    await container.read(nativeUpdateProvider.notifier).start(Uri.parse('https://fixture.invalid/appcast.xml'));
    expect(container.read(nativeUpdateProvider).error, isTrue);
    expect(container.read(nativeUpdateProvider).message, contains('尚未配置更新签名'));
  });

  test('原生更新按检查、下载与准备安装事件提示，不声明安装成功', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const updater = MethodChannel('dev.leanflutter.plugins/auto_updater');
    const events = MethodChannel('dev.leanflutter.plugins/auto_updater_event');
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(events, (call) async => null);
    messenger.setMockMethodCallHandler(updater, (call) async { calls.add(call); return null; });
    addTearDown(() {
      messenger.setMockMethodCallHandler(events, null);
      messenger.setMockMethodCallHandler(updater, null);
    });
    final container = _container(ready: true), controller = container.read(nativeUpdateProvider.notifier);
    await controller.start(Uri.parse('https://fixture.invalid/appcast.xml'));
    expect(calls.map((call) => call.method), ['setFeedURL', 'checkForUpdates']);
    expect(calls.last.arguments, {'inBackground': false});
    controller.onUpdaterCheckingForUpdate(null);
    expect(container.read(nativeUpdateProvider).message, contains('正在检查版本'));
    controller.onUpdaterUpdateAvailable(null);
    expect(container.read(nativeUpdateProvider).message, contains('确认下载安装'));
    controller.onUpdaterUpdateDownloaded(null);
    expect(container.read(nativeUpdateProvider).message, contains('已下载'));
    expect(container.read(nativeUpdateProvider).message, isNot(contains('安装成功')));
    controller.onUpdaterBeforeQuitForUpdate(null);
    expect(container.read(nativeUpdateProvider).message, contains('已准备安装'));
    expect(container.read(nativeUpdateProvider).message, isNot(contains('正在退出')));
    controller.onUpdaterError(UpdaterError('测试签名失败'));
    expect(container.read(nativeUpdateProvider).error, isTrue);
    expect(container.read(nativeUpdateProvider).message, '测试签名失败');
    controller.onUpdaterUpdateNotAvailable(null);
    expect(container.read(nativeUpdateProvider).message, contains('未发现适用于本机的新版本'));
  });

  test('移动平台不会探测或启动桌面原生更新器', () async {
    var calls = 0;
    const channel = MethodChannel('chat.weilai.huabu/window');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async { calls++; return true; });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    try {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer.test();
        expect(await container.read(nativeUpdateReadyProvider.future), isFalse);
      }
      expect(calls, 0);
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('桌面具备签名公钥与真实feed时才显示更新并安装', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final container = _container(release: ClientRelease.fromJson(_manifest()), ready: true);
      await tester.pumpWidget(_app(container, const SoftwareUpdateCard()));
      await tester.pumpAndSettle();
      expect(find.text('更新并安装'), findsOneWidget);
      expect(find.text('下载新版本'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('头像更新入口仅对确认的新版本显示红点', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      for (final build in [2, 3, 4]) {
        final container = _container(release: ClientRelease.fromJson(_manifest(build: build)));
        await tester.pumpWidget(_app(container, const SoftwareUpdateButton()));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('software-update-dot')), build > 3 ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('头像更新按钮主动重查并展示日志，不直接启动安装器', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var reads = 0, nativeCalls = 0;
    const updater = MethodChannel('dev.leanflutter.plugins/auto_updater');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(updater, (_) async { nativeCalls++; return null; });
    addTearDown(() => messenger.setMockMethodCallHandler(updater, null));
    try {
      final manifest = _manifest()..['notes'] = '## 创作体验\n\n- 修复创作工作区并改善更新提示';
      final container = _container(ready: true, load: () async { reads++; return ClientRelease.fromJson(manifest); });
      await tester.pumpWidget(_app(container, const SoftwareUpdateButton()));
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tester.tap(find.byIcon(FLucideIcons.download));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.byType(FDialog), findsOneWidget);
      expect(find.text('当前版本 1.2.3 · 3'), findsOneWidget);
      expect(find.text('更新日志 · 1.2.3'), findsOneWidget);
      expect(find.text('创作体验', findRichText: true), findsOneWidget);
      expect(find.text('修复创作工作区并改善更新提示', findRichText: true), findsOneWidget);
      expect(find.text('查看历史更新日志'), findsOneWidget);
      expect(find.text('更新并安装'), findsOneWidget);
      expect(nativeCalls, 0);
      expect(container.read(nativeUpdateProvider).message, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(FLucideIcons.x));
      await tester.pumpAndSettle();
      expect(find.byType(FDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('窄桌面大字号下更新弹窗和提醒均可等待签名状态', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, 620);
    final readiness = Completer<bool>();
    final container = ProviderContainer.test(overrides: [
      packageInfoProvider.overrideWith((ref) async => _installed()),
      clientReleaseProvider.overrideWith((ref) async => ClientRelease.fromJson(_manifest())),
      nativeUpdateReadyProvider.overrideWith((ref) => readiness.future),
    ]);
    try {
      await tester.pumpWidget(_app(container, const Column(children: [UpdateNotice(), SoftwareUpdateButton()]), scale: 1.8));
      await tester.pump();
      expect(find.text('正在确认更新方式…'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(SoftwareUpdateButton), matching: find.byIcon(FLucideIcons.download)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FDialog), findsOneWidget);
      expect(find.text('正在确认更新方式…'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      readiness.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('更新并安装'), findsNWidgets(2));
      expect(find.text('查看历史更新日志'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(FLucideIcons.x));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      if (!readiness.isCompleted) readiness.complete(false);
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets('${platform.name} 更新控件大字号响应式与签名降级', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      try {
        final container = _container(release: ClientRelease.fromJson(_manifest()));
        await tester.pumpWidget(_app(container, const Column(spacing: 12, children: [UpdateNotice(), SoftwareUpdateCard(), ReleaseDownloads()]), scale: 1.8));
        await tester.pumpAndSettle();
        expect(find.text('发现新版本'), findsOneWidget);
        expect(find.text('最新版本 1.2.3 · 4'), findsOneWidget);
        expect(find.text(platform == TargetPlatform.iOS ? '前往安装渠道更新' : '下载新版本'), findsNWidgets(2));
        expect(find.text('更新并安装'), findsNothing);
        expect(find.text('macOS'), findsOneWidget);
        expect(find.text('Windows'), findsOneWidget);
        expect(find.text('Android'), findsOneWidget);
        expect(find.text('iOS'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('稍后提醒'));
        await tester.pumpAndSettle();
        expect(find.text('AI Studio 1.2.3 已发布'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }

  testWidgets('没有发布与读取失败分别展示，不冒充最新版本', (tester) async {
    final container = _container();
    await tester.pumpWidget(_app(container, const Column(children: [SoftwareUpdateCard(), ReleaseDownloads()])));
    await tester.pumpAndSettle();
    expect(find.text('正式更新渠道尚未配置。'), findsOneWidget);
    expect(find.textContaining('正式安装包尚未发布'), findsOneWidget);
    expect(find.text('当前版本已是该发布渠道的最新版本'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final failed = _container(load: () async => throw DioException(requestOptions: RequestOptions(path: 'https://fixture.invalid/flutter-release.json'), type: DioExceptionType.badResponse, response: Response(requestOptions: RequestOptions(), statusCode: 404)));
    await tester.pumpWidget(_app(failed, const Column(children: [SoftwareUpdateCard(), ReleaseDownloads()])));
    await tester.pumpAndSettle();
    expect(find.text('更新信息读取失败'), findsOneWidget);
    expect(find.text('软件下载信息读取失败'), findsOneWidget);
    expect(find.textContaining('尚未确认最新版本'), findsOneWidget);
    expect(find.text('当前版本已是该发布渠道的最新版本'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('更新读取中展示加载状态并能重试失败的发布信息', (tester) async {
    final pending = Completer<ClientRelease?>();
    var calls = 0;
    final container = _container(load: () {
      calls++;
      if (calls == 1) return pending.future;
      return Future.value(ClientRelease.fromJson(_manifest()));
    });
    await tester.pumpWidget(_app(container, const Column(children: [SoftwareUpdateCard(), ReleaseDownloads()])));
    await tester.pump();
    expect(find.text('正在检查更新…'), findsOneWidget);
    expect(find.text('正在读取软件下载地址'), findsOneWidget);
    pending.completeError(StateError('本地断网测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('最新版本 1.2.3 · 4'), findsOneWidget);
    expect(find.text('软件更新信息读取失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
