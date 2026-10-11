import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});
  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  late final TextEditingController _search, _prompt;
  String _category = '';
  int? _hoveredEntry;
  String _categoryLabel(String category) => switch (category) {'ecommerce' => '电商摄影', 'design' => '视觉设计', 'animation' => '动画插画', _ => category};

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(exploreSearchProvider));
    _prompt = TextEditingController(text: ref.read(promptDraftProvider));
  }

  @override
  void dispose() {
    _search.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _openCreate() {
    ref.read(promptDraftProvider.notifier).setPrompt(_prompt.text);
    context.go('/create');
  }

  Widget _mobileIntro() {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 5, children: [
          Text('发现', style: theme.typography.display.xl.copyWith(fontWeight: FontWeight.w600)),
          Text('从一张作品，开始下一次想象。', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
        ]),
        FCard(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              Row(spacing: 8, children: [
                const Icon(FLucideIcons.sparkles, color: AppTheme.accent, size: 16),
                Text('AI 图片创作', style: theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600)),
              ]),
              FTextField(
                control: FTextFieldControl.managed(controller: _prompt, onChange: (value) => ref.read(promptDraftProvider.notifier).setPrompt(value.text)),
                hint: '描述你脑海中的画面，光线、色彩，以及每一个细节…',
                minLines: 2,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
              Row(spacing: 12, children: [
                FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '添加参考图', semanticsTooltip: '添加参考图', onPress: _openCreate, child: const Icon(FLucideIcons.imagePlus, size: 18)),
                Expanded(child: FButton(suffix: const Icon(FLucideIcons.arrowUpRight, size: 16), onPress: _openCreate, child: const Text('开始创作'))),
              ]),
            ]),
          ),
        ])),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry in [('/video', 'AI 视频', FLucideIcons.video), ('/chat', 'AI 聊天', FLucideIcons.messagesSquare), ('/community', '创作广场', FLucideIcons.compass), ('/models', '模型中心', FLucideIcons.layers), ('/channels', '渠道设置', FLucideIcons.network)])
            FButton(variant: FButtonVariant.secondary, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: Icon(entry.$3, size: 15), onPress: () => context.go(entry.$1), child: Text(entry.$2)),
        ]),
      ],
    );
  }

  Widget _desktopIntro(double width, bool compact) {
    final theme = context.theme;
    const entries = [
      (title: 'AI 图片', description: '把想象变成作品', path: '/create', asset: 'image'),
      (title: 'AI 视频', description: '让你的想象动起来', path: '/video', asset: 'video'),
      (title: 'AI 聊天', description: '与你的创意伙伴对话', path: '/chat', asset: 'chat'),
    ];
    final bandHeight = compact ? 72.0 : 80.0;
    final artworkSize = width < 600 ? 68.0 : compact ? 86.0 : 100.0;
    return SizedBox(height: compact ? 196 : 224, child: Stack(children: [
      Positioned(top: 0, left: 0, right: 0, height: bandHeight, child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Row(children: [
          for (var i = 0; i < entries.length; i++) Expanded(child: FButton.raw(
            variant: FButtonVariant.ghost,
            semanticsLabel: entries[i].title,
            onPress: () => i == 0 ? _openCreate() : context.go(entries[i].path),
            onHoverChange: (hovered) => setState(() => _hoveredEntry = hovered ? i : _hoveredEntry == i ? null : _hoveredEntry),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.fast,
              width: double.infinity,
              height: bandHeight,
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
                AppTheme.studioColors[i].withValues(alpha: _hoveredEntry == i ? 1 : .9),
                AppTheme.studioColors[(i + 1) % entries.length].withValues(alpha: .75),
              ])),
              child: Stack(children: [
                Positioned(right: -4, top: compact ? -5 : -8, width: artworkSize, height: artworkSize, child: IgnorePointer(child: ExcludeSemantics(child: Image.asset('assets/branding/studio-${entries[i].asset}.png', fit: BoxFit.contain, cacheWidth: (artworkSize * MediaQuery.devicePixelRatioOf(context)).ceil())))),
                Padding(padding: EdgeInsets.fromLTRB(width < 760 ? 16 : 24, compact ? 16 : 17, artworkSize - 8, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                  Text(entries[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.typography.body.sm.copyWith(color: AppTheme.studioForeground, fontWeight: FontWeight.w600)),
                  if (width >= 850 && !compact) Text(entries[i].description, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.typography.body.xs.copyWith(color: AppTheme.studioForeground.withValues(alpha: .7))),
                ])),
              ]),
            ),
          )),
        ]),
      )),
      Positioned(top: compact ? 54 : 60, left: 0, right: 0, bottom: 0, child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: theme.colors.border.withValues(alpha: .7)),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
            Color.alphaBlend(AppTheme.cyan.withValues(alpha: .06), theme.colors.card),
            theme.colors.card,
            Color.alphaBlend(AppTheme.accent.withValues(alpha: .07), theme.colors.card),
          ]),
        ),
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, spacing: 12, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
            FButton.raw(
              variant: FButtonVariant.ghost,
              semanticsLabel: '添加参考图，进入创作页',
              onPress: _openCreate,
              child: Container(width: compact ? 60 : 64, height: compact ? 56 : 64, decoration: BoxDecoration(border: Border.all(color: theme.colors.border), borderRadius: BorderRadius.circular(AppRadius.md)), child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 4, children: [
                Icon(FLucideIcons.plus, size: 20, color: theme.colors.mutedForeground),
                Text('参考图', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
              ])),
            ),
            Expanded(child: FTextField(
              style: theme.textFieldStyles.md.copyWith(color: FVariants(null, variants: {}), border: FVariants(InputBorder.none, variants: {}), contentPadding: const EdgeInsetsGeometryDelta.value(EdgeInsets.zero)),
              control: FTextFieldControl.managed(controller: _prompt, onChange: (value) => ref.read(promptDraftProvider.notifier).setPrompt(value.text)),
              hint: '描述你脑海中的画面，光线、色彩，以及每一个细节…',
              minLines: compact ? 2 : 3,
              maxLines: compact ? 2 : 3,
              textInputAction: TextInputAction.newline,
            )),
          ]),
          Row(spacing: 12, children: [
            FButton(variant: FButtonVariant.secondary, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.slidersHorizontal, size: 15), onPress: _openCreate, child: const Text('模型与画幅')),
            const Spacer(),
            if (width >= 820) Text('让想象，从这里发生', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
            FButton(mainAxisSize: MainAxisSize.min, suffix: const Icon(FLucideIcons.arrowUp, size: 16), onPress: _openCreate, child: const Text('开始创作')),
          ]),
        ]),
      )),
    ]));
  }

  Widget _gallery(SiteData site, double width, EdgeInsets padding, bool desktop, String query) {
    final theme = context.theme;
    final artworks = site.content.where((work) => work.kind != 'auth' && work.imageUrl.trim().isNotEmpty).toList();
    final categories = ['', ...artworks.map((work) => work.category.trim()).where((value) => value.isNotEmpty).toSet()];
    final active = categories.contains(_category) ? _category : '';
    query = query.trim().toLowerCase();
    final items = artworks.where((work) =>
      (active.isEmpty || work.category.trim() == active) &&
      (query.isEmpty || '${work.title} ${work.prompt} ${work.author} ${work.category}'.toLowerCase().contains(query)),
    ).toList();
    return SliverMainAxisGroup(slivers: [
      SliverPadding(
        padding: padding.copyWith(top: desktop ? 0 : 8, bottom: desktop ? 14 : 20),
        sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: desktop ? 12 : 18, children: [
          Row(children: [
            Expanded(child: desktop ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 8, children: [
              for (final category in categories) FButton(
                variant: active == category ? FButtonVariant.secondary : FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                selected: active == category,
                onPress: () => setState(() => _category = category),
                child: Text(category.isEmpty ? '发现灵感' : _categoryLabel(category)),
              ),
            ])) : Text('公开灵感', style: theme.typography.display.lg.copyWith(fontWeight: FontWeight.w600))),
            if (artworks.isNotEmpty && (!desktop || width >= 700)) Text('${items.length} 件作品', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
            const SizedBox(width: 8),
            FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '刷新公开作品', onPress: () => ref.invalidate(siteProvider), child: const Icon(FLucideIcons.refreshCw, size: 16)),
          ]),
          if (!desktop) ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: FTextField(
              control: FTextFieldControl.managed(controller: _search, onChange: (value) => ref.read(exploreSearchProvider.notifier).setQuery(value.text)),
              hint: '搜索作品、作者或提示词',
              prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(FLucideIcons.search, size: 17)),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (!desktop && categories.length > 1) Wrap(spacing: 8, runSpacing: 8, children: [
            for (final category in categories) FButton(
              variant: active == category ? FButtonVariant.secondary : FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              selected: active == category,
              onPress: () => setState(() => _category = category),
              child: Text(category.isEmpty ? '全部' : _categoryLabel(category)),
            ),
          ]),
        ])),
      ),
      if (items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatePanel(
          title: artworks.isEmpty ? '灵感正在路上' : '没有找到相关作品',
          description: artworks.isEmpty ? '先创作属于你的第一张作品。' : '换一个关键词，或查看其他分类。',
          icon: artworks.isEmpty ? FLucideIcons.sparkles : FLucideIcons.search,
          action: FButton(mainAxisSize: MainAxisSize.min, onPress: () {
            if (artworks.isEmpty) { _openCreate(); return; }
            ref.read(exploreSearchProvider.notifier).setQuery('');
            setState(() => _category = '');
          }, child: Text(artworks.isEmpty ? '开始创作' : '清除筛选')),
        ))
      else SliverPadding(
        padding: padding.copyWith(top: 0, bottom: 32),
        sliver: SliverMasonryGrid(
          gridDelegate: desktop ? const SliverSimpleGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320) : SliverSimpleGridDelegateWithFixedCrossAxisCount(crossAxisCount: width >= 800 ? 3 : 2),
          mainAxisSpacing: desktop ? 8 : 16,
          crossAxisSpacing: desktop ? 8 : 12,
          delegate: SliverChildBuilderDelegate((context, index) => ArtworkTile(artwork: items[index], imageOnly: desktop, onPress: () => context.push('/work', extra: items[index])), childCount: items.length),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(promptDraftProvider, (_, prompt) {
      if (_prompt.text != prompt) _prompt.value = TextEditingValue(text: prompt, selection: TextSelection.collapsed(offset: prompt.length));
    });
    ref.listen(exploreSearchProvider, (_, query) {
      if (_search.text != query) _search.value = TextEditingValue(text: query, selection: TextSelection.collapsed(offset: query.length));
    });
    final query = ref.watch(exploreSearchProvider);
    return LayoutBuilder(builder: (context, constraints) {
    final desktop = AppLayout.isDesktop;
    final compact = constraints.maxHeight < 640;
    final padding = EdgeInsets.symmetric(horizontal: desktop ? constraints.maxWidth >= 1100 ? AppSpace.xxl : constraints.maxWidth >= 640 ? AppSpace.xl : AppSpace.lg : AppSpace.lg);
    return CustomScrollView(slivers: [
      SliverPadding(padding: padding.copyWith(top: desktop && !compact ? 20 : 16, bottom: desktop && !compact ? 20 : 16), sliver: SliverToBoxAdapter(child: desktop ? _desktopIntro(constraints.maxWidth, compact) : _mobileIntro())),
      ref.watch(siteProvider).when(
        data: (site) => _gallery(site, constraints.maxWidth, padding, desktop, query),
        loading: () => const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '正在读取公开作品', loading: true)),
        error: (error, _) => SliverFillRemaining(hasScrollBody: false, child: StatePanel(
          title: '灵感读取失败', description: errorMessage(error),
          action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(siteProvider), child: const Text('重新读取')),
        )),
      ),
    ]);
    });
  }
}
