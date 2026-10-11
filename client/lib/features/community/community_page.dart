import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

typedef CommunityQuery = ({int page, String keyword, String topic, String order});
final communityPostsProvider = FutureProvider.autoDispose.family<Json, CommunityQuery>((ref, query) async {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  return ref.watch(apiProvider).get('/community/posts', query: {'page': query.page, 'keyword': query.keyword, 'topic': query.topic, 'order': query.order});
});
final communityPostProvider = FutureProvider.autoDispose.family<Json, String>((ref, id) async {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  return ref.watch(apiProvider).get('/community/posts/${Uri.encodeComponent(id)}');
});

Artwork _artwork(Json post, Json image) => Artwork(
  id: '${jsonString(post['id'])}:${jsonString(image['key'])}', title: jsonString(post['title']), prompt: jsonString(post['prompt']),
  imageUrl: jsonString(image['url']), width: jsonInt(image['width']), height: jsonInt(image['height']),
  author: jsonString(post['displayName']), description: jsonString(post['body']), createdAt: jsonDate(post['createdAt']), source: 'community',
);

class CommunityPage extends ConsumerStatefulWidget {
  const CommunityPage({super.key});
  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends ConsumerState<CommunityPage> {
  int _page = 1;
  String _keyword = '', _topic = 'all', _order = 'latest';
  CommunityQuery get _query => (page: _page, keyword: _keyword, topic: _topic, order: _order);

  void _open(Json post) => showFDialog<void>(context: context, builder: (context, style, animation) => FDialog(
    style: style, animation: animation, constraints: BoxConstraints(minWidth: 280, maxWidth: AppLayout.isDesktop ? 1160 : 560),
    builder: (context, _) => SizedBox(width: AppLayout.isDesktop ? MediaQuery.sizeOf(context).width * .85 : MediaQuery.sizeOf(context).width - 32, height: MediaQuery.sizeOf(context).height * .8,
      child: _PostDetail(id: jsonString(post['id']), onChanged: () => ref.invalidate(communityPostsProvider(_query)))),
  ));

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final theme = context.theme, data = ref.watch(communityPostsProvider(_query));
    return CustomScrollView(slivers: [
      SliverPadding(padding: EdgeInsets.all(AppLayout.isDesktop ? 32 : 20), sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
        Row(children: [Text('创作广场', style: theme.typography.display.xl2), const Spacer(), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '刷新创作广场', onPress: () => ref.invalidate(communityPostsProvider(_query)), child: const Icon(FLucideIcons.refreshCw, size: 17))]),
        Row(spacing: 16, children: [
          Expanded(child: FTextField(hint: '搜索作品与提示词', prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(FLucideIcons.search, size: 16)), textInputAction: TextInputAction.search,
            control: FTextFieldControl.managed(), onSubmit: (value) => setState(() { _keyword = value; _page = 1; }))),
          SizedBox(width: 122, child: FSelect(items: const {'最新作品': 'latest', '热门作品': 'popular'}, control: FSelectControl.lifted(value: _order, onChange: (value) { if (value != null) setState(() { _order = value; _page = 1; }); }))),
        ]),
        Wrap(spacing: 8, children: [for (final topic in [('all', '全部'), ('prompt', '提示词'), ('canvas', '画布'), ('mine', '我的分享')]) FButton(variant: _topic == topic.$1 ? FButtonVariant.primary : FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: () => setState(() { _topic = topic.$1; _page = 1; }), child: Text(topic.$2))]),
      ]))),
      data.when(
        loading: () => const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '正在读取广场作品', loading: true)),
        error: (error, _) => SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '广场读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(communityPostsProvider(_query)), child: const Text('重新读取')))),
        data: (data) {
          final posts = (data['items'] as List).map(jsonObject).toList();
          if (posts.isEmpty) return const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '暂时没有相关作品', description: '试试其他分类或关键词。'));
          return SliverPadding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), sliver: SliverMasonryGrid.count(
            crossAxisCount: bounds.maxWidth < 600 ? 2 : bounds.maxWidth < 1100 ? 3 : 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childCount: posts.length,
            itemBuilder: (_, index) {
              final post = posts[index], images = (post['images'] as List? ?? []).map(jsonObject).toList();
              if (images.isNotEmpty) return ArtworkTile(artwork: _artwork(post, images.first), imageOnly: AppLayout.isDesktop, onPress: () => _open(post));
              return FButton.raw(variant: FButtonVariant.ghost, onPress: () => _open(post), child: FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                const Icon(FLucideIcons.quote, size: 22), Text(jsonString(post['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(jsonString(post['body']), maxLines: 5, overflow: TextOverflow.ellipsis, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
                Text(jsonString(post['displayName']), style: theme.typography.body.xs),
              ])));
            },
          ));
        },
      ),
      if (data.asData != null) SliverPadding(padding: const EdgeInsets.all(24), sliver: SliverToBoxAdapter(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: _page > 1 ? () => setState(() => _page--) : null, child: const Text('上一页')),
        Text('第 $_page 页 · 共 ${jsonInt(data.asData!.value['total'])} 件作品', style: theme.typography.body.xs),
        FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: _page * 10 < jsonInt(data.asData!.value['total']) ? () => setState(() => _page++) : null, child: const Text('下一页')),
      ]))),
    ]);
  });
}

class _PostDetail extends ConsumerStatefulWidget {
  const _PostDetail({required this.id, required this.onChanged});
  final String id;
  final VoidCallback onChanged;
  @override
  ConsumerState<_PostDetail> createState() => _PostDetailState();
}

class _PostDetailState extends ConsumerState<_PostDetail> {
  int _image = 0;
  String _busy = '';

  Future<void> _action(String name, Future<void> Function() action) async {
    if (_busy.isNotEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() => _busy = name);
    try {
      await action(); api.assertEpoch(epoch);
      if (mounted) {
        ref.invalidate(communityPostProvider(widget.id)); ref.invalidate(favoritesProvider); widget.onChanged();
        if (name == 'favorite') toast(context, '已收藏独立作品副本');
      }
    } catch (error) { if (mounted && api.epoch == epoch) toast(context, errorMessage(error)); }
    finally { if (mounted && api.epoch == epoch) setState(() => _busy = ''); }
  }

  Widget _content(Json post) {
    final theme = context.theme, images = (post['images'] as List? ?? []).map(jsonObject).toList();
    final work = images.isEmpty ? null : _artwork(post, images[_image < images.length ? _image : 0]);
    final saved = work != null && (ref.watch(favoritesProvider).asData?.value.any((favorite) => favorite.id == work.id) ?? false);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: [
      Row(spacing: 12, children: [FAvatar.raw(size: 34, child: post['avatarUrl'] == '' ? const Icon(FLucideIcons.userRound, size: 17) : ServerImage(jsonString(post['avatarUrl']))), Expanded(child: Text(jsonString(post['displayName']), style: const TextStyle(fontWeight: FontWeight.w600)))]),
      Text(jsonString(post['title']), style: theme.typography.display.lg),
      Text(jsonString(post['body']), style: theme.typography.body.sm.copyWith(height: 1.7, color: theme.colors.mutedForeground)),
      Row(spacing: 12, children: [
        FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, prefix: Icon(FLucideIcons.heart, size: 16, color: post['liked'] == true ? AppTheme.accent : null), onPress: _busy.isEmpty ? () => _action('like', () async { await ref.read(apiProvider).put('/community/posts/${Uri.encodeComponent(widget.id)}/like', {'liked': post['liked'] != true}); }) : null, child: Text('${jsonInt(post['likes'])}')),
        Text('${jsonInt(post['comments'])} 条评论', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
      ]),
      if (jsonString(post['prompt']).isNotEmpty) FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [const Text('提示词', style: TextStyle(fontWeight: FontWeight.w600)), SelectableText(jsonString(post['prompt']), style: theme.typography.body.sm.copyWith(height: 1.6)), FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.copy, size: 15), onPress: () => copyText(context, ref, jsonString(post['prompt'])), child: const Text('复制'))])),
      if (work != null) Row(spacing: 10, children: [
        Expanded(child: FButton(variant: FButtonVariant.secondary, prefix: const Icon(FLucideIcons.bookmark, size: 15), onPress: _busy.isEmpty && !saved ? () => _action('favorite', () => ref.read(repositoryProvider).saveFavorite(work)) : null, child: Text(_busy == 'favorite' ? '正在收藏' : saved ? '已收藏' : '收藏'))),
        Expanded(child: FButton(variant: FButtonVariant.secondary, prefix: const Icon(FLucideIcons.download, size: 15), onPress: _busy.isEmpty ? () => _action('export', () => exportImage(context, ref, work)) : null, child: const Text('下载'))),
      ]),
      FButton(prefix: const Icon(FLucideIcons.sparkles, size: 16), onPress: jsonString(post['prompt']).isEmpty ? null : () { ref.read(promptDraftProvider.notifier).setPrompt(jsonString(post['prompt'])); Navigator.of(context).pop(); context.go('/create'); }, child: const Text('复用提示词')),
    ]);
    final preview = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      if (work != null) Expanded(child: Center(child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg), child: ServerImage(work.imageUrl, fit: BoxFit.contain)))) else const Expanded(child: StatePanel(title: '提示词分享', icon: FLucideIcons.quote)),
      if (images.length > 1) SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 8, children: [for (var i = 0; i < images.length; i++) FButton.raw(variant: FButtonVariant.ghost, selected: _image == i, onPress: () => setState(() => _image = i), child: SizedBox(width: 60, height: 60, child: ServerImage(jsonString(images[i]['url']))))])),
    ]);
    return LayoutBuilder(builder: (context, bounds) => AppLayout.isDesktop ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: bounds.maxWidth < 760 ? 760 : bounds.maxWidth, height: bounds.maxHeight, child: Row(spacing: 24, children: [Expanded(child: preview), SizedBox(width: 300, child: SingleChildScrollView(child: info))]))) : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [SizedBox(height: 280, child: preview), info])));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((session) => session.asData?.value?.id), (previous, next) { if (previous != next && mounted) Navigator.of(context).pop(); });
    return Padding(padding: const EdgeInsets.all(24), child: Column(spacing: 20, children: [
      Row(children: [const Expanded(child: Text('作品详情', style: TextStyle(fontWeight: FontWeight.w600))), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '关闭作品详情', onPress: () => Navigator.of(context).pop(), child: const Icon(FLucideIcons.x, size: 18))]),
      Expanded(child: ref.watch(communityPostProvider(widget.id)).when(data: _content, loading: () => const StatePanel(title: '正在读取作品详情', loading: true), error: (error, _) => StatePanel(title: '作品详情读取失败', description: errorMessage(error), action: FButton(onPress: () => ref.invalidate(communityPostProvider(widget.id)), child: const Text('重新读取'))))),
    ]));
  }
}
