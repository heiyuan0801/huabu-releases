import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:huabu_app/app/desktop_launch.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:material_ui/material_ui.dart';

class _Lifecycle {
  int starts = 0, disposals = 0, shortcuts = 0;
}

class _Content extends StatefulWidget {
  const _Content(this.lifecycle, this.focus);
  final _Lifecycle lifecycle;
  final FocusNode focus;
  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  final _searchFocus = FocusNode();
  @override
  void initState() { super.initState(); widget.lifecycle.starts++; }
  @override
  void dispose() { _searchFocus.dispose(); widget.lifecycle.disposals++; super.dispose(); }
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {SingleActivator(LogicalKeyboardKey.keyK, control: defaultTargetPlatform != TargetPlatform.macOS, meta: defaultTargetPlatform == TargetPlatform.macOS): () {
      widget.lifecycle.shortcuts++;
      _searchFocus.requestFocus();
    }},
    child: Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('正在使用的工作区'),
      FButton(focusNode: widget.focus, onPress: () {}, child: const Text('工作区操作')),
      SizedBox(width: 280, child: FTextField(focusNode: _searchFocus, hint: '搜索工作区')),
    ]))),
  );
}

Future<({ValueNotifier<ThemeMode> theme, _Lifecycle lifecycle, FocusNode focus, GlobalKey<NavigatorState> navigator})> _mount(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  bool reduceMotion = false,
  Size size = const Size(1360, 860),
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  final mode = ValueNotifier(ThemeMode.dark), lifecycle = _Lifecycle(), focus = FocusNode();
  final navigator = GlobalKey<NavigatorState>();
  final light = AppTheme.light(touch: false), dark = AppTheme.dark(touch: false);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    focus.dispose();
    mode.dispose();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    debugDefaultTargetPlatformOverride = null;
  });
  await tester.pumpWidget(ValueListenableBuilder(
    valueListenable: mode,
    builder: (_, value, _) => MaterialApp(
      navigatorKey: navigator,
      theme: light.toApproximateMaterialTheme(), darkTheme: dark.toApproximateMaterialTheme(), themeMode: value,
      locale: const Locale('zh', 'CN'),
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      builder: (context, child) => FTheme(
        data: Theme.brightnessOf(context) == Brightness.dark ? dark : light,
        child: DesktopLaunchOverlay(child: child!),
      ),
      home: _Content(lifecycle, focus),
    ),
  ));
  // Flutter Animate starts via a zero-delay timer, not a microtask.
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 16));
  return (theme: mode, lifecycle: lifecycle, focus: focus, navigator: navigator);
}

Future<void> _shortcut(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void _launchTest(String description, WidgetTesterCallback callback) => testWidgets(description, (tester) async {
  try { await callback(tester); } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  }
});

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    _launchTest('${platform.name} 在 1.2 秒后移除开屏并保留工作区和 Navigator', (tester) async {
      final app = await _mount(tester, platform: platform);
      final navigator = app.navigator.currentState;
      expect(find.text('跳过').hitTestable(), findsOneWidget);
      expect(app.lifecycle.starts, 1);
      expect(app.lifecycle.disposals, 0);
      await _shortcut(tester);
      expect(app.lifecycle.shortcuts, 0);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('跳过'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('跳过'), findsNothing);
      expect(find.text('正在使用的工作区').hitTestable(), findsOneWidget);
      expect(app.navigator.currentState, same(navigator));
      expect(app.lifecycle.starts, 1);
      expect(app.lifecycle.disposals, 0);
      expect(app.focus.hasFocus, isTrue);
      await _shortcut(tester);
      expect(app.lifecycle.shortcuts, 1);
      expect(tester.widget<FTextField>(find.byType(FTextField)).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  _launchTest('Esc 跳过后恢复工作区键盘焦点', (tester) async {
    final app = await _mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(app.focus.hasFocus, isTrue);
    await _shortcut(tester);
    expect(app.lifecycle.shortcuts, 1);
    expect(app.lifecycle.starts, 1);
    expect(app.lifecycle.disposals, 0);
    expect(tester.takeException(), isNull);
  });

  _launchTest('鼠标点击跳过后工作区保持挂载', (tester) async {
    final app = await _mount(tester);
    await tester.tap(find.text('跳过'));
    await tester.pump();
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(app.lifecycle.starts, 1);
    expect(app.lifecycle.disposals, 0);
    expect(app.focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  _launchTest('初始减少动态效果直接展示工作区，关闭设置后不重播', (tester) async {
    final app = await _mount(tester, reduceMotion: true);
    expect(find.text('跳过'), findsNothing);
    expect(find.text('正在使用的工作区').hitTestable(), findsOneWidget);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('跳过'), findsNothing);
    expect(app.lifecycle.starts, 1);
    expect(tester.takeException(), isNull);
  });

  _launchTest('中途减少动态效果立即退出并恢复焦点，关闭后不重播', (tester) async {
    final app = await _mount(tester);
    await tester.pump(const Duration(milliseconds: 300));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(app.focus.hasFocus, isTrue);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('跳过'), findsNothing);
    expect(app.lifecycle.starts, 1);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.linux, TargetPlatform.fuchsia]) {
    _launchTest('${platform.name} 不显示桌面开屏', (tester) async {
      final app = await _mount(tester, platform: platform);
      expect(find.text('跳过'), findsNothing);
      expect(find.text('正在使用的工作区').hitTestable(), findsOneWidget);
      expect(app.lifecycle.starts, 1);
      expect(tester.takeException(), isNull);
    });
  }

  _launchTest('主题切换和父级重建不延长或重播开屏', (tester) async {
    final app = await _mount(tester);
    final navigator = app.navigator.currentState;
    await tester.pump(const Duration(milliseconds: 700));
    app.theme.value = ThemeMode.light;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    app.theme.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(find.text('跳过'), findsNothing);
    expect(app.navigator.currentState, same(navigator));
    expect(app.lifecycle.starts, 1);
    expect(app.lifecycle.disposals, 0);
    expect(tester.takeException(), isNull);
  });

  _launchTest('720 × 480 最小窗口保持内容可见并可以跳过', (tester) async {
    await _mount(tester, size: const Size(720, 480));
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.text('未来画布').hitTestable(), findsOneWidget);
    expect(find.text('跳过').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(find.text('跳过'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _launchTest('动画中卸载会释放资源且不执行迟到更新', (tester) async {
    final app = await _mount(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(app.lifecycle.disposals, 1);
    expect(tester.takeException(), isNull);
  });
}
