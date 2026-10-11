import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ArtworkDetailPage extends ConsumerStatefulWidget {
  const ArtworkDetailPage({required this.artwork, super.key});
  final Artwork artwork;
  @override
  ConsumerState<ArtworkDetailPage> createState() => _ArtworkDetailPageState();
}

class _ArtworkDetailPageState extends ConsumerState<ArtworkDetailPage> {
  late final String _ownerId;
  String _busy = '';
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    _ownerId = ref.read(apiProvider).accountId;
  }

  bool _current(int operation, int epoch) => mounted && _operation == operation && ref.read(apiProvider).epoch == epoch;

  Future<void> _saveAsset() async {
    final account = ref.read(sessionProvider).asData?.value;
    if (_busy.isNotEmpty || account == null) return;
    final api = ref.read(apiProvider);
    final epoch = api.epoch, operation = ++_operation;
    if (account.id != api.accountId) return;
    setState(() => _busy = 'asset');
    try {
      final image = await api.file(widget.artwork.imageUrl);
      api.assertEpoch(epoch);
      await ref.read(repositoryProvider).addImageAsset(image, widget.artwork.title.isEmpty ? '灵感作品' : widget.artwork.title);
      api.assertEpoch(epoch);
      if (mounted && _current(operation, epoch)) {
        ref.invalidate(assetsProvider);
        toast(context, '已保存到个人素材');
      }
    } catch (error) {
      if (mounted && _current(operation, epoch)) toast(context, errorMessage(error));
    } finally {
      if (_current(operation, epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _export() async {
    if (_busy.isNotEmpty) return;
    final epoch = ref.read(apiProvider).epoch, operation = ++_operation;
    setState(() => _busy = 'export');
    await exportImage(context, ref, widget.artwork);
    if (_current(operation, epoch)) setState(() => _busy = '');
  }

  Future<void> _favorite() async {
    if (_busy.isNotEmpty) return;
    final epoch = ref.read(apiProvider).epoch, operation = ++_operation;
    setState(() => _busy = 'favorite');
    try {
      await ref.read(repositoryProvider).saveFavorite(widget.artwork);
      if (mounted && _current(operation, epoch)) { ref.invalidate(favoritesProvider); toast(context, '已收藏独立作品副本'); }
    } catch (error) { if (mounted && _current(operation, epoch)) toast(context, errorMessage(error)); }
    finally { if (_current(operation, epoch)) setState(() => _busy = ''); }
  }

  void _reuse() {
    ref.read(promptDraftProvider.notifier).setPrompt(widget.artwork.prompt);
    context.go('/create');
  }

  double get _ratio {
    final work = widget.artwork;
    if (work.width > 0 && work.height > 0) return work.width / work.height;
    final size = ref.watch(imageSizeProvider(work.imageUrl)).asData?.value;
    if (size != null) return size.width / size.height;
    final parts = work.ratio.split(':');
    final width = double.tryParse(parts.first) ?? 1;
    final height = parts.length == 2 ? double.tryParse(parts.last) ?? 1 : 1;
    return width > 0 && height > 0 ? width / height : 1;
  }

  Widget _information() {
    final work = widget.artwork, theme = context.theme;
    final session = ref.watch(sessionProvider);
    final size = work.width > 0 && work.height > 0 ? null : ref.watch(imageSizeProvider(work.imageUrl)).asData?.value;
    final width = work.width > 0 ? work.width : size?.width.toInt() ?? 0, height = work.height > 0 ? work.height : size?.height.toInt() ?? 0;
    final fields = <(String, String)>[
      if (work.author.isNotEmpty) ('创作者', work.author),
      if (work.model.isNotEmpty) ('生成模型', work.model.split(':').last),
      if (width > 0 && height > 0) ('图片尺寸', '$width × $height'),
      if (work.source != 'published' && work.ratio.isNotEmpty) ('画幅比例', work.ratio),
      if (work.createdAt.millisecondsSinceEpoch > 0) ('创建时间', MaterialLocalizations.of(context).formatMediumDate(work.createdAt.toLocal())),
      if (work.category.isNotEmpty) ('作品分类', work.category),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        FBadge(variant: FBadgeVariant.secondary, child: Text(work.source == 'published' ? '公开灵感' : work.source == 'favorite' ? '收藏作品' : '我的作品')),
        Text(work.title.isEmpty ? '无题作品' : work.title, style: theme.typography.display.xl.copyWith(fontWeight: FontWeight.w600, height: 1.5)),
        if (work.description.isNotEmpty) Text(work.description, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground, height: 1.7)),
      ]),
      FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
        Row(children: [
          Expanded(child: Text('创意提示词', style: theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600))),
          FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '复制提示词', onPress: work.prompt.isEmpty ? null : () => copyText(context, ref, work.prompt), child: const Icon(FLucideIcons.copy, size: 16)),
        ]),
        SelectableText(work.prompt.isEmpty ? '这张作品未提供提示词。' : work.prompt, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground, height: 1.8)),
      ])),
      if (fields.isNotEmpty) FTileGroup(children: [
        for (final field in fields) FTile(title: Text(field.$1), details: Text(field.$2)),
      ]),
      Column(spacing: 12, children: [
        FButton(prefix: const Icon(FLucideIcons.sparkles, size: 16), onPress: _busy.isEmpty && work.prompt.isNotEmpty ? _reuse : null, child: const Text('复用提示词')),
        if (work.source == 'published') FButton(variant: FButtonVariant.secondary, prefix: _busy == 'favorite' ? const FCircularProgress() : const Icon(FLucideIcons.bookmark, size: 16), onPress: _busy.isNotEmpty || session.isLoading ? null : session.asData?.value == null ? () => context.go('/login') : _favorite, child: Text(_busy == 'favorite' ? '正在收藏' : '收藏作品')),
        Row(spacing: 12, children: [
          Expanded(child: FButton(
            variant: FButtonVariant.outline,
            prefix: _busy == 'asset' ? const FCircularProgress() : const Icon(FLucideIcons.folderPlus, size: 16),
            onPress: _busy.isNotEmpty || session.isLoading ? null : session.hasError ? () => ref.invalidate(sessionProvider) : session.asData?.value == null ? () => context.go('/login') : _saveAsset,
            child: Text(_busy == 'asset' ? '保存中' : session.isLoading ? '读取账号' : session.hasError ? '重试账号' : session.asData?.value == null ? '登录后保存' : '保存素材'),
          )),
          Expanded(child: FButton(variant: FButtonVariant.outline, prefix: _busy == 'export' ? const FCircularProgress() : const Icon(FLucideIcons.download, size: 16), onPress: _busy.isEmpty && work.imageUrl.isNotEmpty ? _export : null, child: Text(_busy == 'export' ? '导出中' : '导出图片'))),
        ]),
      ]),
    ]);
  }

  Widget _content() => LayoutBuilder(builder: (context, constraints) {
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ColoredBox(color: context.theme.colors.card, child: ServerImage(widget.artwork.imageUrl, fit: BoxFit.contain)),
    );
    if (AppLayout.isDesktop) {
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(
        width: constraints.maxWidth < 900 ? 900 : constraints.maxWidth, height: constraints.maxHeight,
        child: Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(32), child: Center(child: preview))),
          SizedBox(width: 380, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 24, 32, 32), child: _information())),
      ])));
    }
    return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [
      AspectRatio(aspectRatio: _ratio, child: preview),
      _information(),
    ]));
  });

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((state) => state.asData?.value?.id), (previous, next) {
      if (previous != next && mounted) setState(() { _operation++; _busy = ''; });
    });
    final session = ref.watch(sessionProvider);
    return FScaffold(
      childPad: false,
      header: FHeader.nested(title: const Text('作品详情'), prefixes: [FHeaderAction.back(onPress: () {
        if (context.canPop()) { context.pop(); } else { context.go('/explore'); }
      })]),
      child: SafeArea(top: false, child: widget.artwork.source == 'published' ? _content() : session.when(
        loading: () => const StatePanel(title: '正在读取账号', loading: true),
        error: (error, _) => StatePanel(title: '账号读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(sessionProvider), child: const Text('重新读取'))),
        data: (user) => user?.id != _ownerId || _ownerId.isEmpty
            ? StatePanel(title: '请在所属账号查看作品', description: '账号已切换，重新打开当前账号的作品。', action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => context.go(user == null ? '/login' : '/works'), child: Text(user == null ? '登录账号' : '查看我的作品')))
            : _content(),
      )),
    );
  }
}
