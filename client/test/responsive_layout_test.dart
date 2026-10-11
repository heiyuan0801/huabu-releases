import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:huabu_app/app/app.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/features/explore/explore_page.dart';
import 'package:material_ui/material_ui.dart';

const _loginTitle = '登录后，开始你的创作';

ProviderContainer _guestContainer() {
  var externalReads = 0;
  Never forbiddenRead() {
    externalReads++;
    throw StateError('纯 UI 测试不应读取外部服务或本地数据库');
  }
  addTearDown(() => expect(externalReads, 0));
  return ProviderContainer.test(overrides: [
    apiProvider.overrideWith((ref) => forbiddenRead()),
    databaseProvider.overrideWith((ref) => forbiddenRead()),
    sessionProvider.overrideWithBuild((ref, notifier) async => null),
    themeModeProvider.overrideWithBuild((ref, notifier) => ThemeMode.light),
    siteProvider.overrideWith((ref) async => const SiteData(siteName: '未来画布', terms: '', privacy: '', content: [], emailCodeLogin: false, captchaEnabled: false, emailConfigured: false)),
  ]);
}

void _surface(WidgetTester tester, TargetPlatform platform, Size size) {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    debugDefaultTargetPlatformOverride = null;
  });
}

void main() {
  for (final scenario in [
    (platform: TargetPlatform.macOS, size: const Size(720, 480), desktop: true),
    (platform: TargetPlatform.windows, size: const Size(720, 480), desktop: true),
    (platform: TargetPlatform.iOS, size: const Size(390, 844), desktop: false),
    (platform: TargetPlatform.android, size: const Size(390, 844), desktop: false),
  ]) {
    testWidgets('${scenario.platform.name} 导航、3D 移除与页面卸载', (tester) async {
      _surface(tester, scenario.platform, scenario.size);
      try {
      final container = _guestContainer();
      final router = container.read(routerProvider)..go('/create');
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const HuabuApp()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (scenario.desktop) {
        expect(find.byType(FSidebar), findsOneWidget);
        expect(find.byType(FBottomNavigationBar), findsNothing);
        await tester.tap(find.byWidgetPredicate((widget) => widget is FButton && widget.semanticsLabel == '展开侧栏'));
        await tester.pumpAndSettle();
        expect(find.text('首页 / 探索').hitTestable(), findsOneWidget);
        expect(find.text('AI 3D'), findsNothing);
        expect(find.byWidgetPredicate((widget) => widget is FButton && widget.semanticsLabel == '切换深色主题'), findsOneWidget);
        final modifier = scenario.platform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(modifier);
        expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
        expect(tester.testTextInput.hasAnyClients, isTrue);
      } else {
        expect(find.byType(FSidebar), findsNothing);
        expect(find.byType(FBottomNavigationBar), findsOneWidget);
      }
      expect(find.text(_loginTitle).hitTestable(), findsOneWidget);
      router.go('/explore');
      await tester.pumpAndSettle();
      expect(find.byType(ExplorePage), findsOneWidget);
      expect(find.text('灵感正在路上'), findsOneWidget);
      router.go('/3d');
      await tester.pumpAndSettle();
      expect(find.text('页面不存在'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      } finally { debugDefaultTargetPlatformOverride = null; }
    });
  }
  testWidgets('减少动画时账号空态首帧可读', (tester) async {
    _surface(tester, TargetPlatform.iOS, const Size(390, 844));
    try {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final container = _guestContainer();
    container.read(routerProvider).go('/create');
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const HuabuApp()));
    await tester.pump();
    expect(find.text(_loginTitle).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    } finally { debugDefaultTargetPlatformOverride = null; }
  });
}
