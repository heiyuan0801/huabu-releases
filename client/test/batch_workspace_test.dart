import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/catalog/catalog_providers.dart';
import 'package:huabu_app/features/channels/channel_providers.dart';
import 'package:huabu_app/features/generation/create_page.dart';
import 'package:huabu_app/features/generation/generation_controller.dart';
import 'package:material_ui/material_ui.dart';

const _model = ImageModel(id: 'fixture', providerId: 'fixture', providerName: '隔离渠道', model: 'gpt-image-1', displayName: '测试图片模型', apiFormat: 'openai', capability: 'image', creditCost: 0, value: 'managed:fixture::gpt-image-1');
class _Session extends SessionController {
  @override
  Future<UserAccount?> build() async => const UserAccount(id: 'batch-fixture', email: '', displayName: '', avatarUrl: '', role: 'user', status: 'active');
}
class _Queue extends GenerationController {
  List<String>? submitted;
  @override
  GenerationState build() => const GenerationState();
  @override
  Future<List<BatchImageItem>> generateBatch(ImageModel model, {required List<String> prompts, required String ratio, required int count, required String quality, required bool asynchronous, ImageReference? reference}) async {
    submitted = List.of(prompts);
    return [];
  }
}

Finder _prompt(int index) => find.descendant(of: find.byKey(ValueKey('batch-prompt-$index')), matching: find.byType(EditableText));
Finder _action(String label) => find.byWidgetPredicate((widget) => widget is FButton && widget.semanticsLabel == label);
Future<void> _visibleTap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
Future<void> _write(WidgetTester tester, int index, String value) async {
  await Scrollable.ensureVisible(tester.element(_prompt(index)));
  await tester.pumpAndSettle();
  await tester.enterText(_prompt(index), value);
  await tester.pumpAndSettle();
}

void main() {
  for (final scenario in [
    (platform: TargetPlatform.macOS, size: const Size(1280, 800), dark: false),
    (platform: TargetPlatform.android, size: const Size(390, 844), dark: true),
  ]) {
    testWidgets('${scenario.platform.name} 独立批量页文字输入、追加、上移和移除保持提交顺序', (tester) async {
      debugDefaultTargetPlatformOverride = scenario.platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
      final api = ApiClient(baseUrl: 'https://fixture.invalid/api')..resetAccount('batch-fixture');
      var networkRequests = 0;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        networkRequests++;
        handler.reject(DioException(requestOptions: request, error: StateError('批量编辑测试禁止网络请求')));
      }));
      final container = ProviderContainer.test(retry: (count, error) => null, overrides: [
        apiProvider.overrideWith((ref) => api), sessionProvider.overrideWith(_Session.new),
        modelsProvider.overrideWith((ref) async => [_model]),
        catalogIssuesProvider.overrideWith((ref) => {}),
        defaultModelProvider.overrideWithBuild((ref, notifier) async => null),
        generationProvider.overrideWith(_Queue.new),
        databaseProvider.overrideWith((ref) => throw StateError('批量编辑测试禁止本地数据库')),
      ]);
      addTearDown(() { container.dispose(); api.close(); expect(networkRequests, 0); });
      final semantics = tester.ensureSemantics();
      try {
        await container.read(sessionProvider.future);
        final router = GoRouter(initialLocation: '/batch', routes: [
          GoRoute(path: '/batch', builder: (_, _) => const FScaffold(childPad: false, child: CreatePage(initialBatchMode: true))),
          GoRoute(path: '/away', builder: (_, _) => const SizedBox.shrink()),
        ]);
        addTearDown(router.dispose);
        final theme = scenario.dark ? AppTheme.dark(touch: true) : AppTheme.light(touch: false);
        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(
          routerConfig: router, theme: theme.toApproximateMaterialTheme(),
          localizationsDelegates: FLocalizations.localizationsDelegates, supportedLocales: FLocalizations.supportedLocales,
          builder: (context, child) => FTheme(data: theme, child: FToaster(child: FTooltipGroup(child: child!))),
        )));
        await tester.pumpAndSettle();
        expect(find.text('提示词清单'), findsOneWidget);
        expect(find.text('开始批量生成'), findsOneWidget);
        await _write(tester, 0, '第一项：雨夜城市');
        expect(container.read(promptDraftProvider), '第一项：雨夜城市');

        await _visibleTap(tester, find.text('添加一项提示词'));
        await _write(tester, 1, '第二项：森林晨雾');
        await _visibleTap(tester, find.text('添加一项提示词'));
        await _write(tester, 2, '第三项：玻璃花瓶');
        expect(container.read(promptDraftProvider), '第一项：雨夜城市\n第二项：森林晨雾\n第三项：玻璃花瓶');

        await _visibleTap(tester, _action('上移第 3 项'));
        expect(container.read(promptDraftProvider), '第一项：雨夜城市\n第三项：玻璃花瓶\n第二项：森林晨雾');
        expect(tester.widget<EditableText>(_prompt(1)).controller.text, '第三项：玻璃花瓶');
        await _visibleTap(tester, _action('移除第 1 项'));
        expect(container.read(promptDraftProvider), '第三项：玻璃花瓶\n第二项：森林晨雾');
        expect(tester.widget<EditableText>(_prompt(0)).controller.text, '第三项：玻璃花瓶');
        await _write(tester, 0, '第三项：玻璃花瓶，逆光');

        router.go('/away'); await tester.pumpAndSettle();
        router.go('/batch'); await tester.pumpAndSettle();
        expect(tester.widget<EditableText>(_prompt(0)).controller.text, '第三项：玻璃花瓶，逆光');
        await _visibleTap(tester, find.text('开始批量生成'));
        expect((container.read(generationProvider.notifier) as _Queue).submitted, ['第三项：玻璃花瓶，逆光', '第二项：森林晨雾']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally { semantics.dispose(); debugDefaultTargetPlatformOverride = null; }
    });
  }
}
