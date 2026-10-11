import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/core/widgets.dart';
import 'package:huabu_app/features/explore/explore_page.dart';
import 'package:material_ui/material_ui.dart';

late Uint8List _png;

class _DecorativeBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => key.startsWith('assets/branding/')
      ? ByteData.sublistView(_png)
      : rootBundle.load(key);
}

Future<(ProviderContainer, GoRouter)> _mount(
  WidgetTester tester,
  TargetPlatform platform,
  Size size,
) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  var externalReads = 0;
  Never forbiddenRead() {
    externalReads++;
    throw StateError('首页 UI 测试不应读取外部服务或本地数据库');
  }

  addTearDown(() => expect(externalReads, 0));
  final container = ProviderContainer.test(overrides: [
    apiProvider.overrideWith((ref) => forbiddenRead()),
    databaseProvider.overrideWith((ref) => forbiddenRead()),
    sessionProvider.overrideWithBuild((ref, notifier) async => null),
    imageProvider.overrideWith((ref, source) async => MediaBytes(bytes: _png, mimeType: 'image/png')),
    siteProvider.overrideWith((ref) async => SiteData(
      siteName: '未来画布', terms: '', privacy: '', emailCodeLogin: false,
      captchaEnabled: false, emailConfigured: false,
      content: List.generate(24, (index) => Artwork(
        id: 'fixture-$index', title: '作品 $index', prompt: '测试画面',
        author: '测试作者', category: index.isEven ? 'design' : 'ecommerce',
        source: 'published', imageUrl: 'fixture://image-$index',
        width: 400, height: index.isEven ? 600 : 300,
        createdAt: DateTime(2026),
      )),
    )),
  ]);
  final router = GoRouter(initialLocation: '/explore', routes: [
    GoRoute(path: '/explore', builder: (_, _) => const Scaffold(body: ExplorePage())),
    for (final path in ['/create', '/video', '/chat'])
      GoRoute(path: path, builder: (_, _) => Scaffold(body: Text('目标 $path'))),
  ]);
  addTearDown(router.dispose);
  final touch = !AppLayout.isDesktop;
  final theme = AppTheme.dark(touch: touch);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      theme: theme.toApproximateMaterialTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      builder: (_, child) => FTheme(data: theme, child: FToaster(child: FTooltipGroup(
        child: DefaultAssetBundle(bundle: _DecorativeBundle(), child: child!),
      ))),
    ),
  ));
  await tester.pumpAndSettle();
  return (container, router);
}

Finder get _decorativeImages => find.byWidgetPredicate((widget) {
  if (widget is! Image) return false;
  final provider = widget.image is ResizeImage ? (widget.image as ResizeImage).imageProvider : widget.image;
  return provider is AssetImage && provider.assetName.startsWith('assets/branding/');
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF7958FF), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    _png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });

  for (final scenario in [
    (platform: TargetPlatform.macOS, size: const Size(464, 480), desktop: true),
    (platform: TargetPlatform.macOS, size: const Size(720, 480), desktop: true),
    (platform: TargetPlatform.windows, size: const Size(1360, 860), desktop: true),
    (platform: TargetPlatform.macOS, size: const Size(2560, 1000), desktop: true),
    (platform: TargetPlatform.iOS, size: const Size(390, 844), desktop: false),
    (platform: TargetPlatform.android, size: const Size(390, 844), desktop: false),
  ]) {
    testWidgets('${scenario.platform.name} ${scenario.size} 首页密度与真实作品比例', (tester) async {
      try {
      await _mount(tester, scenario.platform, scenario.size);
      expect(tester.takeException(), isNull);
      expect(find.text('AI 3D'), findsNothing);
      expect(find.byType(ArtworkTile), findsWidgets);
      final first = find.byType(ArtworkTile).first;
      final size = tester.getSize(find.descendant(of: first, matching: find.byType(AspectRatio)).first);
      expect(size.width / size.height, closeTo(400 / 600, .01));
      expect(_decorativeImages, scenario.desktop ? findsNWidgets(3) : findsNothing);
      final grid = tester.widget<SliverMasonryGrid>(find.byType(SliverMasonryGrid));
      expect(grid.gridDelegate, scenario.desktop
          ? isA<SliverSimpleGridDelegateWithMaxCrossAxisExtent>()
          : isA<SliverSimpleGridDelegateWithFixedCrossAxisCount>());
      if (scenario.desktop) {
        expect(tester.getTopLeft(first).dy, lessThan(scenario.size.height));
        final y = tester.getTopLeft(first).dy;
        final row = find.byType(ArtworkTile).evaluate().where((element) =>
          (tester.getTopLeft(find.byWidget(element.widget)).dy - y).abs() < 1).length;
        if (scenario.size.width > 2000) expect(row, greaterThan(4));
        if (scenario.size.height < 640) expect(y, lessThan(310));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('桌面三项入口导航并保留首页提示词', (tester) async {
    try {
    final (container, router) = await _mount(tester, TargetPlatform.macOS, const Size(1360, 860));
    await tester.enterText(find.byType(FTextField), '日落下的透明玻璃雕塑');
    for (final entry in [('AI 图片', '/create'), ('AI 视频', '/video'), ('AI 聊天', '/chat')]) {
      await tester.tap(find.byWidgetPredicate((widget) => widget is FButton && widget.semanticsLabel == entry.$1));
      await tester.pumpAndSettle();
      expect(find.text('目标 ${entry.$2}'), findsOneWidget);
      expect(container.read(promptDraftProvider), '日落下的透明玻璃雕塑');
      router.go('/explore');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('减少动画时首页入口与作品首帧可见', (tester) async {
    try {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _mount(tester, TargetPlatform.macOS, const Size(720, 480));
    expect(find.text('AI 图片').hitTestable(), findsOneWidget);
    expect(find.byType(ArtworkTile).first.hitTestable(), findsOneWidget);
    expect(tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .every((widget) => widget.duration == Duration.zero), isTrue);
    expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
