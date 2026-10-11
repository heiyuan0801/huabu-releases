import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/auth/login_page.dart';
import '../features/affiliate/affiliate_page.dart';
import '../features/explore/explore_page.dart';
import '../features/generation/create_page.dart';
import '../features/works/works_page.dart';
import '../features/works/artwork_detail_page.dart';
import '../features/assets/assets_page.dart';
import '../features/settings/settings_page.dart';
import '../features/catalog/catalog_page.dart';
import '../features/channels/channels_page.dart';
import '../features/chat/chat_page.dart';
import '../features/community/community_page.dart';
import '../features/video/video_page.dart';
import '../features/video/video_detail_page.dart';
import '../features/video/video_repository.dart';
import 'workspace_shell.dart';

final routerProvider = Provider((ref) {
  final router = GoRouter(initialLocation: '/explore', routes: [
    GoRoute(path: '/', redirect: (_, _) => '/explore'),
    GoRoute(path: '/login', builder: (_, state) => LoginPage(initialEmail: state.uri.queryParameters['email'] ?? '', inviteCode: state.uri.queryParameters['ref'] ?? '')),
    GoRoute(path: '/register', builder: (_, state) => LoginPage(mode: AuthMode.register, inviteCode: state.uri.queryParameters['ref'] ?? '')),
    GoRoute(path: '/forgot-password', builder: (_, state) => LoginPage(mode: AuthMode.reset, initialEmail: state.uri.queryParameters['email'] ?? '')),
    GoRoute(path: '/tasks', redirect: (_, _) => '/works?tab=tasks'),
    GoRoute(path: '/work', builder: (_, state) => state.extra is Artwork
      ? ArtworkDetailPage(artwork: state.extra as Artwork)
      : const FScaffold(child: StatePanel(title: '请从作品列表打开作品'))),
    ShellRoute(builder: (_, state, child) => WorkspaceShell(location: state.uri.path, child: child), routes: [
      GoRoute(path: '/explore', pageBuilder: (context, state) => _page(context, state, const ExplorePage())),
      GoRoute(path: '/create', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: CreatePage()))),
      GoRoute(path: '/video', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: VideoPage()))),
      GoRoute(path: '/video/work', pageBuilder: (context, state) => _page(context, state, AccountGate(child: state.extra is VideoWork ? VideoDetailPage(work: state.extra as VideoWork) : const StatePanel(title: '请从作品列表打开视频')))),
      GoRoute(path: '/chat', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: ChatPage()))),
      GoRoute(path: '/community', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: CommunityPage()))),
      GoRoute(path: '/models', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: CatalogPage()))),
      GoRoute(path: '/channels', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: ChannelsPage()))),
      GoRoute(path: '/works', pageBuilder: (context, state) => _page(context, state, AccountGate(child: WorksPage(initialTasks: state.uri.queryParameters['tab'] == 'tasks')))),
      GoRoute(path: '/assets', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: AssetsPage()))),
      GoRoute(path: '/settings', pageBuilder: (context, state) => _page(context, state, const AccountGate(child: SettingsPage()))),
      GoRoute(path: '/affiliate', pageBuilder: (context, state) => _page(context, state, const AffiliatePage())),
    ]),
  ], errorBuilder: (_, _) => const FScaffold(child: StatePanel(title: '页面不存在')));
  ref.onDispose(router.dispose);
  return router;
});

CustomTransitionPage<void> _page(BuildContext context, GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.page,
  child: child,
  transitionsBuilder: (_, animation, _, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(position: Tween(begin: const Offset(0, .012), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: AppMotion.curve)), child: child),
  ),
);

class HuabuApp extends ConsumerWidget {
  const HuabuApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final touch = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
    final light = AppTheme.light(touch: touch), dark = AppTheme.dark(touch: touch);
    ref.watch(sessionProvider);
    return MaterialApp.router(
      title: '未来画布', debugShowCheckedModeBanner: false,
      themeMode: ref.watch(themeModeProvider),
      theme: light.toApproximateMaterialTheme(), darkTheme: dark.toApproximateMaterialTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
      scrollBehavior: const _AppScrollBehavior(),
      builder: (context, child) => FTheme(
        data: Theme.brightnessOf(context) == Brightness.dark ? dark : light,
        child: _WindowAppearance(child: FToaster(child: FTooltipGroup(child: child!))),
      ),
    );
  }
}

class _WindowAppearance extends StatefulWidget {
  const _WindowAppearance({required this.child});
  final Widget child;
  @override
  State<_WindowAppearance> createState() => _WindowAppearanceState();
}

class _WindowAppearanceState extends State<_WindowAppearance> {
  static const _channel = MethodChannel('chat.weilai.huabu/window');
  Brightness? _brightness;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.brightnessOf(context);
    if (!AppLayout.isDesktop || brightness == _brightness) return;
    _brightness = brightness;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || brightness != _brightness) return;
      try {
        await _channel.invokeMethod<void>('setBrightness', brightness.name);
      } on MissingPluginException {
        // Widget tests and unsupported hosts have no native window channel.
      } on PlatformException catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'native window appearance'));
      }
    });
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
}
