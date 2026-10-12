import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/catalog/catalog_page.dart';
import 'package:huabu_app/features/catalog/catalog_providers.dart';
import 'package:huabu_app/features/channels/channel_providers.dart';
import 'package:huabu_app/features/channels/channels_page.dart';
import 'package:material_ui/material_ui.dart';

const _user = UserAccount(id: 'fixture-account', email: '', displayName: '测试账号', avatarUrl: '', role: 'user', status: 'active');
const _cloudModel = ImageModel(id: 'cloud-model', providerId: 'cloud', providerName: '测试平台', model: 'test-image', displayName: '测试模型', apiFormat: 'openai', capability: 'image', creditCost: 1, value: 'managed:cloud::test-image');
const _local = LocalChannel(id: 'fixture', name: '测试个人渠道', baseUrl: 'https://example.invalid', apiKey: '', apiFormat: 'openai', models: [{'name': 'local-image', 'capability': 'image'}]);
const _storageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _Api extends ApiClient {
  Object? failure;
  Completer<Json>? pending;
  int logoutCalls = 0;
  @override
  Future<Json> get(String path, {Map<String, dynamic>? query, Map<String, dynamic>? headers}) async => throw StateError('测试禁止真实接口读取');
  @override
  Future<Json> post(String path, [Object? body, Map<String, dynamic>? headers]) async {
    if (path != '/auth/logout') throw StateError('测试禁止真实业务请求');
    logoutCalls++;
    if (pending != null) return pending!.future;
    if (failure != null) throw failure!;
    return {};
  }
}

ProviderContainer _container(_Api api, {Future<List<ImageModel>> Function()? cloud, Future<List<LocalChannel>> Function()? local, bool defaultRetry = false}) {
  api.resetAccount(_user.id);
  addTearDown(api.close);
  return ProviderContainer.test(retry: defaultRetry ? null : (count, error) => null, overrides: [
    apiProvider.overrideWithValue(api),
    databaseProvider.overrideWith((ref) => throw StateError('测试禁止读取设备数据库')),
    sessionProvider.overrideWithBuild((ref, notifier) => _user),
    themeModeProvider.overrideWithBuild((ref, notifier) => ThemeMode.light),
    defaultModelProvider.overrideWithBuild((ref, notifier) async => null),
    cloudCatalogProvider.overrideWith((ref) => cloud?.call() ?? Future.value([_cloudModel])),
    localChannelsProvider.overrideWithBuild((ref, notifier) => local?.call() ?? Future.value([_local])),
  ]);
}

Future<List<ImageModel>> _catalog(ProviderContainer container) async {
  final subscription = container.listen(catalogProvider, (_, _) {});
  try { return await container.read(catalogProvider.future); }
  finally { subscription.close(); }
}

Widget _app(ProviderContainer container, Widget child, {double scale = 1}) {
  final theme = AppTheme.light(touch: true);
  return UncontrolledProviderScope(container: container, child: MaterialApp(
    theme: theme.toApproximateMaterialTheme(), locale: const Locale('zh', 'CN'),
    supportedLocales: FLocalizations.supportedLocales, localizationsDelegates: FLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: FTheme(data: theme, child: FToaster(child: FTooltipGroup(child: child!)))),
    home: FScaffold(child: child),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final failedCloud in [true, false]) {
    test('${failedCloud ? '平台' : '个人'}目录失败保留另一来源并暴露错误', () async {
      final container = _container(_Api(),
        cloud: failedCloud ? () async => throw const ApiException('平台目录测试失败') : null,
        local: !failedCloud ? () async => throw const ApiException('个人目录测试失败') : null,
      );
      final models = await _catalog(container);
      expect(models.map((model) => model.model), [failedCloud ? 'local-image' : 'test-image']);
      expect(container.read(catalogIssuesProvider), {failedCloud ? '平台目录' : '本机个人目录': failedCloud ? '平台目录测试失败' : '个人目录测试失败'});
    });
  }

  test('两来源失败保持失败，不返回真实空目录', () async {
    final container = _container(_Api(), cloud: () async => throw const ApiException('平台失败'), local: () async => throw const ApiException('个人失败'));
    await expectLater(_catalog(container), throwsA(isA<ApiException>().having((error) => error.message, '来源错误', allOf(contains('平台失败'), contains('个人失败')))));
    expect(container.read(catalogIssuesProvider).length, 2);
  });

  for (final status in [401, 403]) {
    test('账号状态 $status 禁止通过个人目录降级', () async {
      final container = _container(_Api(), cloud: () async => throw ApiException('账号不可用', status: status));
      await expectLater(_catalog(container), throwsA(isA<ApiException>().having((error) => error.status, '状态', status)));
    });
  }

  test('已读取目录随后账号过期不再提供旧模型', () async {
    var expired = false;
    final container = _container(_Api(), cloud: () async {
      if (expired) throw const ApiException('账号已过期', status: 401);
      return [_cloudModel];
    });
    container.listen(catalogProvider, (_, _) {});
    expect(await container.read(catalogProvider.future), hasLength(2));
    expired = true;
    container.invalidate(cloudCatalogProvider);
    await container.pump();
    await expectLater(container.read(catalogProvider.future), throwsA(isA<ApiException>().having((error) => error.status, '状态', 401)));
    expect(container.read(catalogProvider).asData, isNull);
  });

  test('目录请求取消不降级，也不提示来源读取失败', () async {
    final container = _container(_Api(), cloud: () async => throw const ApiException('测试取消', canceled: true));
    await expectLater(_catalog(container), throwsA(isA<ApiException>().having((error) => error.canceled, '已取消', true)));
    expect(container.read(catalogIssuesProvider), isEmpty);
  });

  test('目录途中切换账号忽略旧结果', () async {
    final api = _Api(), pending = Completer<List<ImageModel>>();
    final container = _container(api, cloud: () => pending.future);
    final future = _catalog(container);
    final assertion = expectLater(future, throwsA(isA<ApiException>().having((error) => error.canceled, '已取消', true)));
    await Future<void>.delayed(Duration.zero);
    api.resetAccount('another-fixture');
    pending.complete([_cloudModel]);
    await assertion;
  });

  for (final offline in [false, true]) {
    test('${offline ? '断网' : '确认'}退出仅在安全存储清理完成后退出本机', () async {
      var deleted = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method != 'delete') throw StateError('测试禁止读取密钥或写入数据');
        deleted = true;
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, null));
      final api = _Api()..failure = offline ? const ApiException('离线测试') : null;
      final container = _container(api);
      await container.read(sessionProvider.future);
      final warning = await container.read(sessionProvider.notifier).logout();
      expect(deleted, isTrue);
      expect(api.logoutCalls, 1);
      expect(container.read(sessionProvider).asData?.value, isNull);
      expect(api.accountId, isEmpty);
      expect(warning, offline ? contains('服务器注销尚未确认') : isNull);
    });
  }

  test('安全存储清理失败不伪装本机退出成功', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, (call) async {
      if (call.method != 'delete') throw StateError('测试禁止读取密钥或写入数据');
      throw PlatformException(code: 'fixture-storage-error');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, null));
    final api = _Api(), container = _container(api);
    await container.read(sessionProvider.future);
    await expectLater(container.read(sessionProvider.notifier).logout(), throwsA(isA<ApiException>().having((error) => error.message, '清理失败', contains('本机退出未完成'))));
    expect(container.read(sessionProvider).asData?.value, _user);
    expect(api.accountId, _user.id);
  });

  test('退出等待期间切换账号不得清理新会话', () async {
    var deleted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, (call) async {
      deleted = true;
      throw StateError('账号切换后不应清理安全存储');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_storageChannel, null));
    final api = _Api()..pending = Completer<Json>();
    final container = _container(api);
    final future = container.read(sessionProvider.notifier).logout();
    final assertion = expectLater(future, throwsA(isA<ApiException>().having((error) => error.canceled, '已取消', true)));
    api.resetAccount('another-fixture');
    api.pending!.complete({});
    await assertion;
    expect(deleted, isFalse);
    expect(api.accountId, 'another-fixture');
  });

  testWidgets('手机大字号模型保留完整长名称与来源失败提示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    try {
      final longName = List.filled(8, '用于验证自然换行的完整模型名称').join();
      final model = ImageModel(id: 'long', providerId: 'cloud', providerName: '测试平台', model: 'long', displayName: longName, apiFormat: 'openai', capability: 'image', creditCost: 1, value: 'managed:cloud::long');
      final container = _container(_Api(), cloud: () async => [model], local: () async => throw const ApiException('本机目录测试失败'));
      await tester.pumpWidget(_app(container, const CatalogPage(), scale: 1.8));
      await tester.pumpAndSettle();
      expect(find.text('本机个人目录读取失败'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(longName), 250, scrollable: find.byType(Scrollable).first);
      expect(find.text(longName), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('默认读取重试期间立即保留成功目录与来源失败提示', (tester) async {
    final container = _container(_Api(), defaultRetry: true, local: () async => throw const ApiException('正在重试的本机目录错误'));
    await tester.pumpWidget(_app(container, const CatalogPage()));
    await tester.pump();
    await tester.pump();
    expect(container.read(localChannelsProvider).isLoading, isTrue);
    expect(container.read(localChannelsProvider).hasError, isTrue);
    expect(container.read(catalogProvider).asData?.value, [_cloudModel]);
    expect(find.text('本机个人目录读取失败'), findsOneWidget);
    expect(find.text('测试模型'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('默认读取重试期间双来源失败显示真实失败态', (tester) async {
    final container = _container(_Api(), defaultRetry: true,
      cloud: () async => throw const ApiException('正在重试的平台错误'),
      local: () async => throw const ApiException('正在重试的本机错误'),
    );
    await tester.pumpWidget(_app(container, const CatalogPage()));
    await tester.pump();
    await tester.pump();
    expect(find.text('模型目录读取失败'), findsOneWidget);
    expect(find.textContaining('正在重试的平台错误'), findsOneWidget);
    expect(find.textContaining('正在重试的本机错误'), findsOneWidget);
    expect(find.text('还没有可用模型'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('渠道读取失败立即反馈，重新读取刷新真实目录源', (tester) async {
    var failed = true, reads = 0;
    final container = _container(_Api(), defaultRetry: true, local: () async {
      reads++;
      if (failed) throw const ApiException('渠道源读取测试失败');
      return [_local];
    });
    await tester.pumpWidget(_app(container, const ChannelsPage()));
    await tester.pump();
    await tester.pump();
    expect(find.text('个人渠道读取失败'), findsOneWidget);
    expect(find.text('渠道源读取测试失败'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('测试个人渠道'), findsOneWidget);
    expect(find.text('个人渠道读取失败'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('渠道大目录按需显示，搜索保留已有选择', (tester) async {
    final channel = LocalChannel(id: 'many', name: '测试渠道', baseUrl: 'https://example.invalid', apiKey: '', apiFormat: 'openai', models: [for (var i = 0; i < 600; i++) {'name': 'model-$i', 'capability': 'text'}]);
    final container = _container(_Api(), local: () async => [channel]);
    await tester.pumpWidget(_app(container, const ChannelsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑渠道'));
    await tester.pumpAndSettle();
    expect(find.text('model-599'), findsNothing);
    final search = find.byWidgetPredicate((widget) => widget is FTextField && widget.hint == '搜索渠道中的模型');
    await tester.ensureVisible(search);
    await tester.enterText(search, 'model-599');
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FCheckbox), matching: find.text('model-599')), findsOneWidget);
    expect(find.text('已选择 600 个模型'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
