import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../channels/channel_providers.dart';
import 'catalog_providers.dart';

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});
  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  String _category = 'all', _saving = '';
  TextEditingValue _search = TextEditingValue.empty;
  String? _error;
  static const _categories = {'all': '全部模型', 'image': '图片', 'video': '视频', 'text': '文本', 'audio': '音频'};

  IconData _icon(String capability) => switch (capability) {'image' => FLucideIcons.image, 'video' => FLucideIcons.video, 'text' => FLucideIcons.messageSquare, 'audio' => FLucideIcons.audioLines, _ => FLucideIcons.box};

  Future<void> _setDefault(ImageModel model) async {
    if (_saving.isNotEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() { _saving = model.id; _error = null; });
    try {
      await ref.read(defaultModelProvider.notifier).setModel(model.id);
      if (mounted && api.epoch == epoch) toast(context, '已设为本设备默认图片模型');
    } catch (error) {
      if (mounted && api.epoch == epoch) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted && api.epoch == epoch) setState(() => _saving = '');
    }
  }

  void _details(ImageModel model) => showFDialog<void>(context: context, builder: (context, style, animation) => FDialog(
    style: style, animation: animation,
    builder: (context, style) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
      Row(spacing: 12, children: [Icon(_icon(model.capability), color: AppTheme.accent, size: 24), Expanded(child: Text(model.name, style: style.titleTextStyle))]),
      for (final entry in {'模型标识': model.model, '所属渠道': model.providerName, '模型类型': _categories[model.capability] ?? model.capability, '接口协议': model.apiFormat.toUpperCase(), '调用额度': model.providerId.startsWith('local:') ? '由个人渠道计费' : '${model.creditCost} 积分', '配置来源': model.providerId.startsWith('local:') ? '当前账号在本设备的个人配置' : '项目服务器已启用的模型目录'}.entries)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [SizedBox(width: 82, child: Text(entry.key, style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground))), Expanded(child: SelectableText(entry.value, style: context.theme.typography.body.sm))]),
      const FDivider(),
      Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
        FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.copy, size: 15), onPress: () => copyText(context, ref, model.model), child: const Text('复制模型标识')),
        FButton(mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context), child: const Text('关闭')),
      ]),
    ]))),
  ));

  Widget _models(List<ImageModel> models) {
    final query = _search.text.trim().toLowerCase();
    final visible = models.where((model) => (_category == 'all' || model.capability == _category) && '${model.name} ${model.model} ${model.providerName}'.toLowerCase().contains(query)).toList();
    if (models.isEmpty && ref.watch(catalogIssuesProvider).isNotEmpty) return SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '部分模型目录未能读取', description: '已读取的目录暂无模型，请重试失败来源。', action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => refreshCatalog(ref), child: const Text('重新读取'))));
    if (models.isEmpty) return SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '还没有可用模型', description: '平台启用模型后会出现在这里，也可以配置自己的接口。', action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => context.go('/channels'), child: const Text('配置个人渠道'))));
    if (visible.isEmpty) return const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '没有找到对应模型', description: '试试模型名称、渠道名称，或切换模型类型。', icon: FLucideIcons.search));
    final selected = ref.watch(defaultModelProvider).asData?.value;
    final desktop = AppLayout.isDesktop;
    Widget itemBuilder(BuildContext context, int index) {
      final model = visible[index], theme = context.theme;
      final personal = model.providerId.startsWith('local:'), isDefault = selected == model.id;
      final icon = Container(width: 42, height: 42, decoration: BoxDecoration(color: theme.colors.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(AppRadius.md)), child: Icon(_icon(model.capability), color: theme.colors.primary, size: 20));
      final defaultAction = FButton(variant: isDefault ? FButtonVariant.secondary : FButtonVariant.outline, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: _saving == model.id ? const FCircularProgress() : null, onPress: _saving.isEmpty && !isDefault ? () => _setDefault(model) : null, child: Text(isDefault ? '已设默认' : '设为默认'));
      return FCard(
        style: desktop ? const FCardStyleDelta.delta(padding: EdgeInsetsGeometryDelta.value(EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md))) : const FCardStyleDelta.context(),
        builder: cardBody,
        child: LayoutBuilder(builder: (context, bounds) {
          final inline = desktop && bounds.maxWidth >= 620;
          final information = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 5, children: [
            Text(model.name, style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600)),
            Text(model.providerName, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
            Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
              Text(_categories[model.capability] ?? model.capability, style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
              Text(model.apiFormat.toUpperCase(), style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
              Text(personal ? '个人渠道计费' : '${model.creditCost} 积分', style: theme.typography.body.xs.copyWith(fontWeight: FontWeight.w500)),
            ]),
          ]);
          final actions = Wrap(alignment: WrapAlignment.end, spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, semanticsLabel: '查看 ${model.name} 的信息', prefix: const Icon(FLucideIcons.info, size: 15), onPress: () => _details(model), child: const Text('详情')),
            if (model.capability == 'image') defaultAction,
          ]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.md, children: [
            Row(spacing: AppSpace.lg, children: [icon, Expanded(child: information), if (inline) actions]),
            if (!inline) Align(alignment: Alignment.centerRight, child: actions),
          ]);
        }),
      );
    }
    return SliverList.separated(itemCount: visible.length, itemBuilder: itemBuilder, separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(catalogProvider);
    final catalog = snapshot.hasError ? AsyncError<List<ImageModel>>(snapshot.error!, snapshot.stackTrace!) : snapshot;
    final defaults = ref.watch(defaultModelProvider), theme = context.theme;
    final issues = ref.watch(catalogIssuesProvider);
    return CustomScrollView(slivers: [SliverPadding(padding: EdgeInsets.all(AppLayout.isDesktop ? AppSpace.xxl : AppSpace.lg), sliver: SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.xl, children: [
        Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Text('模型中心', style: theme.typography.display.xl2), Text('找到适合这次灵感的模型。', style: theme.typography.body.md.copyWith(color: theme.colors.mutedForeground))])), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '刷新模型目录', onPress: catalog.isLoading ? null : () => refreshCatalog(ref), child: const Icon(FLucideIcons.refreshCw, size: 19))]),
        if (catalog.asData != null) for (final entry in issues.entries) FAlert(variant: FAlertVariant.destructive, title: Text('${entry.key}读取失败'), subtitle: Text('${entry.value}。已保留其他成功读取的目录。')),
        if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('默认模型未保存'), subtitle: Text(_error!)),
        if (defaults.hasError) FAlert(variant: FAlertVariant.destructive, title: const Text('默认模型偏好读取失败'), subtitle: Text(errorMessage(defaults.error!))),
        LayoutBuilder(builder: (context, constraints) {
          final filters = Wrap(spacing: 4, runSpacing: 6, children: [for (final item in _categories.entries) FButton(variant: _category == item.key ? FButtonVariant.secondary : FButtonVariant.ghost, selected: _category == item.key, mainAxisSize: MainAxisSize.min, onPress: () => setState(() => _category = item.key), child: Text(item.value))]);
          final search = SizedBox(width: constraints.maxWidth > 850 ? 270 : constraints.maxWidth, child: FTextField(control: FTextFieldControl.lifted(value: _search, onChange: (value) => setState(() => _search = value)), hint: '搜索模型或渠道', prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(FLucideIcons.search, size: 16))));
          return constraints.maxWidth > 850 ? Row(spacing: 24, children: [Expanded(child: filters), search]) : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [filters, search]);
        }),
        const SizedBox.shrink(),
      ])),
      catalog.when(skipLoadingOnRefresh: false, data: _models, loading: () => const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '正在读取模型目录', loading: true)), error: (error, _) => SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '模型目录读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => refreshCatalog(ref), child: const Text('重新读取'))))),
    ]))]);
  }
}
