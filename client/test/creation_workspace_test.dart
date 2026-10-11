import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/core/widgets.dart';
import 'package:huabu_app/features/catalog/catalog_providers.dart';
import 'package:huabu_app/features/channels/channel_providers.dart';
import 'package:huabu_app/features/generation/create_draft.dart';
import 'package:huabu_app/features/generation/create_page.dart';
import 'package:huabu_app/features/generation/generation_controller.dart';
import 'package:huabu_app/features/generation/generation_service.dart';
import 'package:huabu_app/features/video/video_controller.dart';
import 'package:huabu_app/features/video/video_draft.dart';
import 'package:huabu_app/features/video/video_page.dart';
import 'package:huabu_app/features/video/video_service.dart';
import 'package:material_ui/material_ui.dart';

const _accountA = UserAccount(id: 'account-a', email: '', displayName: 'A', avatarUrl: '', role: 'user', status: 'active');
const _accountB = UserAccount(id: 'account-b', email: '', displayName: 'B', avatarUrl: '', role: 'user', status: 'active');

class _Session extends SessionController {
  @override
  Future<UserAccount?> build() async => _accountA;
  void switchAccount(UserAccount? account) {
    ref.read(apiProvider).resetAccount(account?.id ?? '');
    state = AsyncData(account);
  }
}

ImageModel _model(String name, {String format = 'openai', String capability = 'image'}) => ImageModel(id: name, providerId: 'fixture', providerName: '测试渠道', model: name, displayName: name, apiFormat: format, capability: capability, creditCost: 7, value: 'managed:fixture::$name');
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');

ProviderContainer _container({List<ImageModel>? models, GenerationState imageState = const GenerationState(), Map<String, String> issues = const {}}) {
  var requests = 0, databaseReads = 0;
  final api = ApiClient(baseUrl: 'https://example.invalid/api')..resetAccount(_accountA.id);
  api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    requests++;
    handler.reject(DioException(requestOptions: request, error: StateError('隔离测试禁止网络请求')));
  }));
  addTearDown(() { expect(requests, 0); expect(databaseReads, 0); });
  final catalog = models ?? [_model('gpt-image-1.5')];
  return ProviderContainer.test(overrides: [
    apiProvider.overrideWith((ref) { ref.onDispose(api.close); return api; }),
    databaseProvider.overrideWith((ref) { databaseReads++; throw StateError('隔离测试禁止本地数据库'); }),
    sessionProvider.overrideWith(_Session.new),
    catalogProvider.overrideWith((ref) async => catalog),
    catalogIssuesProvider.overrideWith((ref) => issues),
    modelsProvider.overrideWith((ref) async => catalog.where((model) => model.capability == 'image').toList()),
    defaultModelProvider.overrideWithBuild((ref, notifier) async => null),
    generationProvider.overrideWithBuild((ref, notifier) => imageState),
    videoGenerationProvider.overrideWithBuild((ref, notifier) => const VideoState()),
    videoWorksProvider.overrideWith((ref) async => []),
    imageProvider.overrideWith((ref, source) async => MediaBytes(bytes: _png, mimeType: 'image/png')),
    imageSizeProvider.overrideWith((ref, source) async => const ui.Size(1, 1)),
  ]);
}

Future<GoRouter> _pump(WidgetTester tester, ProviderContainer container, {bool video = false, TargetPlatform platform = TargetPlatform.macOS, Size size = const Size(1100, 720)}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() { debugDefaultTargetPlatformOverride = null; tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
  final router = GoRouter(initialLocation: video ? '/video' : '/create', routes: [
    GoRoute(path: '/create', builder: (_, _) => const FScaffold(child: CreatePage())),
    GoRoute(path: '/video', builder: (_, _) => const FScaffold(child: VideoPage())),
    GoRoute(path: '/away', builder: (_, _) => const SizedBox.shrink()),
    GoRoute(path: '/work', builder: (_, state) => FScaffold(child: Text('详情：${(state.extra as Artwork).id}'))),
  ]);
  addTearDown(router.dispose);
  final theme = AppTheme.light(touch: platform == TargetPlatform.iOS || platform == TargetPlatform.android);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(
    theme: theme.toApproximateMaterialTheme(), routerConfig: router,
    localizationsDelegates: FLocalizations.localizationsDelegates, supportedLocales: FLocalizations.supportedLocales,
    builder: (context, child) => FTheme(data: theme, child: FToaster(child: FTooltipGroup(child: child!))),
  )));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return router;
}

void main() {
  test('编辑草稿跨页保留，账号切换清空提示词、参数与参考素材', () async {
    final container = _container();
    await container.read(sessionProvider.future);
    final imageSubscription = container.listen(imageDraftProvider, (_, _) {});
    final videoSubscription = container.listen(videoDraftProvider, (_, _) {});
    final bytes = Uint8List.fromList([1, 2, 3]);
    final image = ImageReference(bytes: bytes, mimeType: 'image/png', filename: 'reference.png');
    final video = VideoReference(kind: 'video', name: 'reference.mp4', media: MediaBytes(bytes: bytes, mimeType: 'video/mp4'));
    container.read(promptDraftProvider.notifier).setPrompt('图片草稿');
    container.read(imageDraftProvider.notifier).setDraft(ImageDraft(modelId: 'image-model', ratio: '9:16', quality: 'high', count: '4', imageMode: true, reference: image));
    container.read(videoDraftProvider.notifier).setDraft(VideoDraft(prompt: '视频草稿', modelId: 'video-model', seconds: '10', mode: 'edit', references: [video]));
    imageSubscription.close(); videoSubscription.close();
    await container.pump();
    expect(container.read(imageDraftProvider).reference, same(image));
    expect(container.read(imageDraftProvider).count, '4');
    expect(container.read(videoDraftProvider).references.single, same(video));
    expect(container.read(videoDraftProvider).prompt, '视频草稿');
    expect(container.read(promptDraftProvider), '图片草稿');
    (container.read(sessionProvider.notifier) as _Session).switchAccount(_accountB);
    await container.pump();
    expect(container.read(imageDraftProvider).reference, isNull);
    expect(container.read(imageDraftProvider).count, '1');
    expect(container.read(videoDraftProvider).prompt, isEmpty);
    expect(container.read(videoDraftProvider).references, isEmpty);
    expect(container.read(promptDraftProvider), isEmpty);
  });

  test('图片参数依据现有协议隐藏无效字段', () {
    expect(imageParameters(_model('muse-image')).quality, isFalse);
    expect(imageParameters(_model('muse-image')).asynchronous, isFalse);
    final grok = imageParameters(_model('grok-imagine-image'));
    expect(grok.ratio, isFalse); expect(grok.quality, isFalse); expect(grok.singleImageEdit, isTrue);
    expect(imageParameters(_model('gemini-2.5-flash-image', format: 'gemini')).quality, isFalse);
    expect(imageParameters(_model('gemini-3-pro-image', format: 'gemini')).qualityAsSize, isTrue);
    expect(imageParameters(_model('firefly-image')).supported, isFalse);
  });

  test('视频参考素材依协议与创作方式显示', () {
    expect(videoReferenceSupported('grok', 'generate', 'image'), isTrue);
    expect(videoReferenceSupported('grok', 'generate', 'video'), isFalse);
    expect(videoReferenceSupported('grok', 'edit', 'image'), isFalse);
    expect(videoReferenceSupported('grok', 'edit', 'video'), isTrue);
    expect(videoReferenceSupported('openai', 'generate', 'audio'), isFalse);
    expect(videoReferenceSupported('seedance', 'generate', 'audio'), isTrue);
    expect(videoReferenceSupported('', 'generate', 'image'), isFalse);
  });

  testWidgets('桌面图片操作区固定，展开并滚动高级参数后仍可生成', (tester) async {
    try {
      final container = _container();
      await _pump(tester, container);
      final operation = find.byKey(const ValueKey('image-operation'));
      final before = tester.getTopLeft(operation);
      await tester.tap(find.text('高级设置'));
      await tester.pumpAndSettle();
      final parameterScroll = find.ancestor(of: find.byKey(const ValueKey('image-parameters')), matching: find.byType(SingleChildScrollView)).first;
      await tester.drag(parameterScroll, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(operation), before);
      expect(find.text('立即生成').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('已保存的批量图片使用多列并打开对应真实作品详情', (tester) async {
    try {
      final works = List.generate(6, (index) => Artwork(id: 'work-$index', title: '作品 $index', prompt: '测试提示词', imageUrl: 'fixture:$index', createdAt: DateTime(2026), width: 1, height: 1));
      final output = GenerationOutput(runId: 'test-run', run: null, images: [MediaBytes(bytes: _png, mimeType: 'image/png')], prompt: '测试提示词', model: 'gpt-image-1.5', ratio: '1:1', quality: 'auto', requestedCount: 6);
      final container = _container(imageState: GenerationState(output: output, works: works));
      await _pump(tester, container);
      expect(find.byKey(const ValueKey('saved-image-results')), findsOneWidget);
      expect(find.byType(ArtworkTile), findsNWidgets(6));
      final first = find.byType(ArtworkTile).first;
      await Scrollable.ensureVisible(tester.element(first));
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.text('详情：work-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('保存失败时批量原图和重试保存按钮保持可见', (tester) async {
    try {
      final output = GenerationOutput(runId: 'unsaved-run', run: null, images: List.generate(3, (_) => MediaBytes(bytes: _png, mimeType: 'image/png')), prompt: '保留回复', model: 'gpt-image-1.5', ratio: '1:1', quality: 'auto', requestedCount: 3);
      final container = _container(imageState: GenerationState(output: output, error: '作品保存失败'));
      await _pump(tester, container);
      expect(find.byKey(const ValueKey('unsaved-image-thumbnails')), findsOneWidget);
      expect(find.text('重新保存已生成图片'), findsOneWidget);
      expect(find.bySemanticsLabel('预览第 3 张图片'), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-image-results')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('移动视频草稿离页后恢复，操作按钮独立于内容滚动', (tester) async {
    try {
      final container = _container(models: [_model('grok-imagine-video', capability: 'video')]);
      final router = await _pump(tester, container, video: true, platform: TargetPlatform.android, size: const Size(390, 844));
      await tester.enterText(find.byType(EditableText).first, '森林中的移动镜头');
      await tester.pumpAndSettle();
      final operation = find.byKey(const ValueKey('video-operation'));
      expect(find.text('生成视频').hitTestable(), findsOneWidget);
      final position = tester.getTopLeft(operation);
      final mainScroll = find.descendant(of: find.byType(VideoPage), matching: find.byType(SingleChildScrollView)).first;
      await tester.drag(mainScroll, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(operation), position);
      router.go('/away'); await tester.pumpAndSettle();
      router.go('/video'); await tester.pumpAndSettle();
      expect(find.text('森林中的移动镜头'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally { debugDefaultTargetPlatformOverride = null; }
  });

  testWidgets('账号切换后旧创作页面不能发起新账号生成', (tester) async {
    try {
      final container = _container();
      await _pump(tester, container);
      await tester.enterText(find.byType(EditableText).first, '旧账号提示词');
      (container.read(sessionProvider.notifier) as _Session).switchAccount(_accountB);
      await tester.pumpAndSettle();
      // Keep the old widget mounted to exercise a queued action before AccountGate replaces it.
      await tester.tap(find.text('立即生成'));
      await tester.pumpAndSettle();
      expect(container.read(generationProvider).runId, isEmpty);
      expect(container.read(generationProvider).busy, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally { debugDefaultTargetPlatformOverride = null; }
  });
}
