import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AssetsPage extends ConsumerStatefulWidget {
  const AssetsPage({super.key});

  @override
  ConsumerState<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends ConsumerState<AssetsPage> {
  String _kind = 'all', _busy = '', _accountId = '';
  TextEditingValue _search = TextEditingValue.empty;
  String? _error;

  bool _current(int epoch) => mounted && ref.read(apiProvider).epoch == epoch;

  Future<void> _importImage() async {
    if (_busy.isNotEmpty) return;
    final epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = 'image'; _error = null; });
    try {
      final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '图片素材', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'], uniformTypeIdentifiers: ['public.image'])]);
      if (file == null || !_current(epoch)) return;
      final bytes = await file.readAsBytes();
      if (!_current(epoch)) return;
      final mime = lookupMimeType(file.name, headerBytes: bytes);
      if (!['image/png', 'image/jpeg', 'image/webp', 'image/gif'].contains(mime)) throw const ApiException('请选择 PNG、JPEG、WebP 或 GIF 图片');
      await ref.read(repositoryProvider).addImageAsset(MediaBytes(bytes: bytes, mimeType: mime!), file.name);
      if (mounted && _current(epoch)) { ref.invalidate(assetsProvider); toast(context, '图片已保存到素材库'); }
    } catch (error) {
      if (_current(epoch)) setState(() => _error = errorMessage(error));
    } finally {
      if (_current(epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _createText() async {
    if (_busy.isNotEmpty) return;
    final epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = 'text'; _error = null; });
    try {
      final saved = await showFDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context, style, animation) => _TextAssetDialog(style: style, animation: animation),
      );
      if (mounted && _current(epoch) && saved == true) { ref.invalidate(assetsProvider); toast(context, '文本已保存到素材库'); }
    } finally {
      if (_current(epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _remove(AssetItem asset) async {
    if (_busy.isNotEmpty) return;
    final epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = asset.id; _error = null; });
    try {
      if (!await confirmRemoval(context, '移除「${asset.title}」？') || !_current(epoch)) return;
      await ref.read(repositoryProvider).removeAsset(asset.id);
      if (mounted && _current(epoch)) { ref.invalidate(assetsProvider); toast(context, '素材已移除'); }
    } catch (error) {
      if (_current(epoch)) setState(() => _error = errorMessage(error));
    } finally {
      if (_current(epoch)) setState(() => _busy = '');
    }
  }

  Widget _list(List<AssetItem> items) {
    final query = _search.text.trim().toLowerCase();
    final visible = items.where((asset) => (_kind == 'all' || asset.kind == _kind) && (query.isEmpty || '${asset.title} ${asset.note} ${asset.tags.join(' ')} ${asset.content}'.toLowerCase().contains(query))).toList();
    if (items.isEmpty) return const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '把灵感收进你的素材库', description: '导入图片，或保存一段想法。\n素材随账号同步，随时继续创作。', icon: FLucideIcons.folderOpen));
    if (visible.isEmpty) return SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '没有找到对应素材', description: '试试其他关键词，或切换素材类型。', icon: FLucideIcons.search, action: FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: () => setState(() { _kind = 'all'; _search = TextEditingValue.empty; }), child: const Text('查看全部素材'))));
    return SliverLayoutBuilder(builder: (context, constraints) {
      final columns = (constraints.crossAxisExtent / 238).floor().clamp(1, 5);
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: AppSpace.lg, mainAxisSpacing: AppSpace.lg, mainAxisExtent: 284),
        itemCount: visible.length,
        itemBuilder: (context, index) => _AssetCard(asset: visible[index], busy: _busy.isNotEmpty, removing: _busy == visible[index].id, onRemove: () => _remove(visible[index])),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountId = ref.watch(sessionProvider.select((session) => session.asData?.value?.id)) ?? '';
    if (_accountId != accountId) {
      _accountId = accountId;
      _busy = '';
      _error = null;
      _kind = 'all';
      _search = TextEditingValue.empty;
    }
    final assets = ref.watch(assetsProvider);
    final theme = context.theme;
    return CustomScrollView(slivers: [SliverPadding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width >= AppSpace.desktopBreakpoint ? AppSpace.xxl : AppSpace.lg),
      sliver: SliverMainAxisGroup(slivers: [SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.xl, children: [
        LayoutBuilder(builder: (context, constraints) {
          final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Text('我的素材', style: theme.typography.display.xl2), Text('收集灵感，连接下一次创作。', style: theme.typography.body.md.copyWith(color: theme.colors.mutedForeground))]);
          final actions = Wrap(spacing: 10, runSpacing: 10, children: [
            FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.fileText, size: 17), onPress: _busy.isEmpty && assets.hasValue ? _createText : null, child: const Text('新增文本')),
            FButton(mainAxisSize: MainAxisSize.min, prefix: _busy == 'image' ? const FCircularProgress() : const Icon(FLucideIcons.upload, size: 17), onPress: _busy.isEmpty && assets.hasValue ? _importImage : null, child: Text(_busy == 'image' ? '正在导入' : '导入图片')),
          ]);
          return constraints.maxWidth >= 680 ? Row(children: [Expanded(child: heading), actions]) : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [heading, actions]);
        }),
        if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('操作未完成'), subtitle: Text(_error!)),
        LayoutBuilder(builder: (context, constraints) {
          final filters = Wrap(spacing: 6, runSpacing: 6, children: [for (final filter in const {'all': '所有素材', 'image': '图片', 'text': '文本', 'video': '视频'}.entries) FButton(variant: _kind == filter.key ? FButtonVariant.secondary : FButtonVariant.ghost, selected: _kind == filter.key, mainAxisSize: MainAxisSize.min, onPress: () => setState(() => _kind = filter.key), child: Text(filter.value))]);
          final search = SizedBox(width: constraints.maxWidth >= 760 ? 280 : constraints.maxWidth, child: FTextField(
            control: FTextFieldControl.lifted(value: _search, onChange: (value) => setState(() => _search = value)),
            hint: '搜索素材名称、内容或标签',
            prefixBuilder: (_, _, _) => Padding(padding: const EdgeInsets.only(left: 12, right: 8), child: Icon(FLucideIcons.search, size: 17, color: theme.colors.mutedForeground)),
          ));
          return constraints.maxWidth >= 760 ? Row(children: [Expanded(child: filters), search]) : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [filters, search]);
        }),
        const SizedBox.shrink(),
      ])), assets.when(
          data: _list,
          loading: () => const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '正在读取素材', loading: true)),
          error: (error, _) => SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '素材读取失败', description: errorMessage(error), icon: FLucideIcons.cloudOff, action: FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(assetsProvider), child: const Text('重新读取')))),
        ),
      ]),
    )]);
  }
}

class _AssetCard extends StatefulWidget {
  const _AssetCard({required this.asset, required this.busy, required this.removing, required this.onRemove});
  final AssetItem asset;
  final bool busy, removing;
  final VoidCallback onRemove;
  @override
  State<_AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends State<_AssetCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final theme = context.theme;
    final label = switch (asset.kind) { 'image' => '图片', 'text' => '文本', 'video' => '视频', _ => '文件' };
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.normal,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        child: FCard(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: asset.kind == 'image' ? SizedBox.expand(child: ServerImage(asset.imageUrl))
              : Padding(padding: const EdgeInsets.all(22), child: asset.kind == 'text'
                  ? Align(alignment: Alignment.topLeft, child: Text(asset.content, maxLines: 6, overflow: TextOverflow.ellipsis, style: theme.typography.body.sm.copyWith(height: 1.7)))
                  : Center(child: Column(mainAxisSize: MainAxisSize.min, spacing: 12, children: [Icon(asset.kind == 'video' ? FLucideIcons.video : FLucideIcons.file, size: 36, color: theme.colors.mutedForeground), Text('$label素材', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))])))),
          Padding(padding: const EdgeInsets.all(14), child: Row(spacing: 8, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [Text(asset.title.isEmpty ? '未命名素材' : asset.title, style: theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis), Text(asset.kind == 'image' && asset.width > 0 && asset.height > 0 ? '$label · ${asset.width} × ${asset.height}' : label, style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground))])),
            FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '移除素材：${asset.title}', onPress: widget.busy ? null : widget.onRemove, child: widget.removing ? const FCircularProgress() : Icon(FLucideIcons.trash2, size: 16, color: theme.colors.mutedForeground)),
          ])),
        ])),
      ),
    );
  }
}

class _TextAssetDialog extends ConsumerStatefulWidget {
  const _TextAssetDialog({required this.style, required this.animation});
  final FDialogStyle style;
  final Animation<double> animation;
  @override
  ConsumerState<_TextAssetDialog> createState() => _TextAssetDialogState();
}

class _TextAssetDialogState extends ConsumerState<_TextAssetDialog> {
  final _title = TextEditingController(), _content = TextEditingController();
  late final int _epoch;
  bool _saving = false;
  String? _error;

  @override
  void initState() { super.initState(); _epoch = ref.read(apiProvider).epoch; }

  @override
  void dispose() { _title.dispose(); _content.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving) return;
    if (ref.read(apiProvider).epoch != _epoch) { Navigator.pop(context, false); return; }
    final title = _title.text.trim(), content = _content.text.trim();
    if (title.isEmpty || content.isEmpty) { setState(() => _error = '请填写素材名称和文本内容'); return; }
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(repositoryProvider).addTextAsset(title, content);
      if (mounted && api.epoch == epoch) Navigator.pop(context, true);
    } catch (error) {
      if (mounted && api.epoch == epoch) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((session) => session.asData?.value?.id), (previous, next) {
      if (previous != next && mounted) Navigator.pop(context, false);
    });
    return PopScope(
    canPop: !_saving,
    child: FDialog(
      style: widget.style,
      animation: widget.animation,
      builder: (context, style) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
        Text('保存一段灵感', style: style.titleTextStyle),
        Text('提示词、创作笔记，或任何值得留下的想法。', style: style.bodyTextStyle.copyWith(color: context.theme.colors.mutedForeground)),
        FTextField(control: FTextFieldControl.managed(controller: _title), label: const Text('素材名称'), hint: '为这段灵感起个名字', autofocus: true, enabled: !_saving),
        ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .3), child: FTextField.multiline(control: FTextFieldControl.managed(controller: _content), label: const Text('文本内容'), hint: '写下你的想法…', enabled: !_saving, minLines: 4)),
        if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('尚未保存'), subtitle: Text(_error!)),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: _saving ? null : () => Navigator.pop(context, false), child: const Text('取消')),
          FButton(mainAxisSize: MainAxisSize.min, prefix: _saving ? const FCircularProgress() : null, onPress: _saving ? null : _save, child: Text(_saving ? '正在保存' : '保存素材')),
        ]),
      ]))),
    ),
    );
  }
}
