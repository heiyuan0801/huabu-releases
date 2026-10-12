import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/updates/update_widgets.dart';

const _destinations = [
  (path: '/explore', label: '发现', icon: FLucideIcons.compass),
  (path: '/create', label: '创作', icon: FLucideIcons.sparkles),
  (path: '/works', label: '作品', icon: FLucideIcons.images),
  (path: '/assets', label: '素材', icon: FLucideIcons.folderOpen),
  (path: '/settings', label: '我的', icon: FLucideIcons.userRound),
];

const _desktopDestinations = [
  (path: '/explore', label: '首页 / 探索', icon: FLucideIcons.house),
  (path: '/create', label: 'AI 生图', icon: FLucideIcons.image),
  (path: '/video', label: 'AI 视频', icon: FLucideIcons.video),
  (path: '/chat', label: 'AI 聊天', icon: FLucideIcons.messagesSquare),
  (path: '/models', label: '模型中心', icon: FLucideIcons.layers),
  (path: '/community', label: '创作广场', icon: FLucideIcons.compass),
  (path: '/works', label: '我的作品', icon: FLucideIcons.images),
  (path: '/assets', label: '素材库', icon: FLucideIcons.folderOpen),
  (path: '/channels', label: '渠道设置', icon: FLucideIcons.network),
  (path: '/affiliate', label: '邀请奖励', icon: FLucideIcons.gift),
  (path: '/settings', label: '个人中心', icon: FLucideIcons.settings),
];

class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  late final TextEditingController _search;
  final _searchFocus = FocusNode();
  bool? _collapsed;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(exploreSearchProvider));
  }

  @override
  void dispose() { _search.dispose(); _searchFocus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final desktop = AppLayout.isDesktop;
    final compact = _collapsed ?? MediaQuery.sizeOf(context).width < 980;
    final colors = context.theme.colors;
    final matched = _destinations.indexWhere((item) => widget.location.startsWith(item.path));
    final index = matched >= 0 ? matched : ['/models', '/channels'].contains(widget.location) ? 4 : widget.location == '/community' ? 0 : 1;
    ref.listen(exploreSearchProvider, (_, query) {
      if (_search.text != query) _search.value = TextEditingValue(text: query, selection: TextSelection.collapsed(offset: query.length));
    });
    final keys = [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5];
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyK, control: !mac, meta: mac): _searchFocus.requestFocus,
        for (var i = 0; i < keys.length; i++)
          SingleActivator(keys[i], control: !mac, meta: mac): () => context.go(_desktopDestinations[i].path),
      },
      child: FScaffold(
        childPad: false,
        sidebar: desktop
            ? FSidebar(
                style: FSidebarStyleDelta.delta(
                  constraints: BoxConstraints.tightFor(width: compact ? 72 : 220),
                  decoration: DecorationDelta.value(BoxDecoration(color: colors.background, border: Border(right: BorderSide(color: colors.border.withValues(alpha: .6))))),
                  headerPadding: EdgeInsetsGeometryDelta.value(EdgeInsets.fromLTRB(compact ? 12 : 20, 20, compact ? 12 : 12, 26)),
                  contentPadding: const EdgeInsetsGeometryDelta.value(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  footerPadding: EdgeInsetsGeometryDelta.value(EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 12 : 16, 16)),
                ),
                header: compact ? Column(spacing: 16, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/branding/app-icon.png', width: 32, height: 32, cacheWidth: 96)),
                  FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '展开侧栏', semanticsTooltip: '展开侧栏', onPress: () => setState(() => _collapsed = false), child: const Icon(FLucideIcons.chevronRight, size: 16)),
                ]) : Row(children: [
                  const Expanded(child: _Brand(compact: true)),
                  FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '收起侧栏', semanticsTooltip: '收起侧栏', onPress: () => setState(() => _collapsed = true), child: const Icon(FLucideIcons.chevronLeft, size: 16)),
                ]),
                footer: _AccountSummary(compact: compact),
                children: [
                  for (final range in [(0, 6), (6, _desktopDestinations.length)])
                    FSidebarGroup(label: compact || range.$1 == 0 ? null : const Text('我的创作'), children: [
                      for (var i = range.$1; i < range.$2; i++)
                        Semantics(label: compact ? _desktopDestinations[i].label : null, child: FSidebarItem(
                          style: FSidebarItemStyleDelta.delta(padding: EdgeInsetsGeometryDelta.value(EdgeInsets.symmetric(horizontal: compact ? 14 : 12, vertical: 11)), iconSpacing: 12),
                          icon: Icon(_desktopDestinations[i].icon, size: 17),
                          label: compact ? null : Text(_desktopDestinations[i].label),
                          selected: widget.location.startsWith(_desktopDestinations[i].path),
                          onPress: () => context.go(_desktopDestinations[i].path),
                        )),
                    ]),
                ],
              )
            : null,
        header: desktop
            ? null
            : SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
                  child: Row(children: [
                    const Expanded(child: _Brand(compact: true)),
                    FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '扫码登录', semanticsTooltip: '扫码登录网页或桌面客户端', onPress: () => context.push('/web-login'), child: const Icon(FLucideIcons.scanLine, size: 18)),
                    const _ThemeToggle(),
                  ]),
                ),
              ),
        footer: desktop
            ? null
            : FBottomNavigationBar(
                safeAreaBottom: true,
                index: index,
                onChange: (value) => context.go(_destinations[value].path),
                children: [
                  for (final item in _destinations)
                    FBottomNavigationBarItem(icon: Icon(item.icon), label: Text(item.label), semanticsLabel: item.label),
                ],
              ),
        child: SafeArea(top: desktop, bottom: false, child: Column(children: [
          const UpdateNotice(),
          Expanded(child: desktop ? Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(32, 16, 28, 0), child: Row(spacing: 16, children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: FTextField(
              focusNode: _searchFocus,
              control: FTextFieldControl.managed(controller: _search, onChange: (value) => ref.read(exploreSearchProvider.notifier).setQuery(value.text)),
              hint: '搜索作品、作者或提示词…',
              prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(FLucideIcons.search, size: 15)),
              textInputAction: TextInputAction.search,
              onSubmit: (_) => context.go('/explore'),
            )))),
            FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '开始图片创作', semanticsTooltip: '开始图片创作', onPress: () => context.go('/create'), child: const Icon(FLucideIcons.squarePen, size: 17)),
            const _ThemeToggle(),
          ])),
          Expanded(child: widget.child),
        ]) : widget.child),
        ])),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 12,
    children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/branding/app-icon.png', width: 32, height: 32, cacheWidth: 96)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 3,
        children: [
          Text('未来画布', style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w700, letterSpacing: .4)),
          if (!compact) Text('创意，由你定义', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
        ],
      ),
    ],
  );
}

class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = context.theme.colors.brightness == Brightness.dark;
    return FButton.icon(
      variant: FButtonVariant.ghost,
      semanticsLabel: dark ? '切换浅色主题' : '切换深色主题',
      semanticsTooltip: dark ? '切换浅色主题' : '切换深色主题',
      onPress: () async {
        try {
          await ref.read(themeModeProvider.notifier).setMode(dark ? ThemeMode.light : ThemeMode.dark);
        } catch (error) {
          if (context.mounted) toast(context, errorMessage(error));
        }
      },
      child: Icon(dark ? FLucideIcons.sun : FLucideIcons.moon, size: 18),
    );
  }
}

class _AccountSummary extends ConsumerWidget {
  const _AccountSummary({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    if (compact) {
      return Column(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
        session.when(
          data: (user) => FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: user?.displayName ?? '登录账号', semanticsTooltip: user?.displayName ?? '登录账号', onPress: () => context.go(user == null ? '/login' : '/settings'), child: const Icon(FLucideIcons.userRound, size: 18)),
          loading: () => const FCircularProgress(),
          error: (_, _) => FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '重新读取账号', onPress: () => ref.invalidate(sessionProvider), child: const Icon(FLucideIcons.refreshCw, size: 16)),
        ),
        const SoftwareUpdateButton(),
      ]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        if (session.asData?.value != null)
          DecoratedBox(
            decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Text('可用算力', style: typography.body.xs.copyWith(color: colors.mutedForeground)),
                  ref.watch(creditsProvider).when(
                    data: (value) => Row(
                      spacing: 8,
                      children: [
                        const Icon(FLucideIcons.zap, size: 16, color: AppTheme.accent),
                        Text(value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2), style: typography.display.xl.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    loading: () => const Text('读取中…'),
                    error: (_, _) => Row(
                      children: [
                        const Expanded(child: Text('算力读取失败')),
                        FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '重新读取算力', onPress: () => ref.invalidate(creditsProvider), child: const Icon(FLucideIcons.refreshCw, size: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        Row(spacing: AppSpace.xs, children: [Expanded(child: session.when(
          data: (user) => FButton.raw(
            variant: FButtonVariant.ghost,
            onPress: () => context.go(user == null ? '/login' : '/settings'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                spacing: AppSpace.sm,
                children: [
                  FAvatar.raw(size: 30, child: const Icon(FLucideIcons.userRound, size: 16)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(user?.displayName ?? '登录创作', overflow: TextOverflow.ellipsis, style: typography.body.sm.copyWith(fontWeight: FontWeight.w600)),
                        Text(user == null ? '同步作品与个人配置' : '个人创作空间', maxLines: 1, overflow: TextOverflow.ellipsis, style: typography.body.xs.copyWith(color: colors.mutedForeground)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          loading: () => const Row(spacing: AppSpace.sm, children: [SizedBox(width: 16, height: 16, child: FCircularProgress()), Expanded(child: Text('正在读取账号…', maxLines: 1, overflow: TextOverflow.ellipsis))]),
          error: (_, _) => FButton(
            variant: FButtonVariant.ghost,
            prefix: const Icon(FLucideIcons.refreshCw, size: 16),
            onPress: () => ref.invalidate(sessionProvider),
            child: const Text('账号读取失败，重试', maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        )), const SoftwareUpdateButton()]),
      ],
    );
  }
}
