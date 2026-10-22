import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import '../generation/generation_service.dart';
import '../video/video_controller.dart';
import '../video/video_repository.dart';
import '../channels/channel_providers.dart';

class WorksPage extends ConsumerStatefulWidget {
  const WorksPage({this.initialTasks = false, super.key});
  final bool initialTasks;
  @override
  ConsumerState<WorksPage> createState() => _WorksPageState();
}
class _WorksPageState extends ConsumerState<WorksPage> {
  late bool _tasks = widget.initialTasks;
  int _page = 1;
  String _keyword = '', _recovering = '', _kind = 'image';
  bool _selecting = false, _managing = false;
  final _selected = <String>{};
  FutureProvider<List<Artwork>> get _images => _kind == 'favorite' ? favoritesProvider : _kind == 'server' ? serverImageHistoryProvider : worksProvider;

  @override
  void didUpdateWidget(WorksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTasks != widget.initialTasks) _tasks = widget.initialTasks;
  }

  Future<void> _manage(List<Artwork> works, {bool remove = false}) async {
    if (_managing) return;
    final selected = works.where((work) => _selected.contains(work.id)).toList();
    if (selected.isEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    if (remove) {
      final confirmed = await showFDialog<bool>(context: context, builder: (context, style, animation) => FDialog(style: style, animation: animation, builder: (context, _) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
        Text('移除 ${selected.length} 件作品？', style: context.theme.typography.display.lg), const Text('仅移除选中列表记录，本机磁盘原图、已有素材、画布附件和服务端任务记录仍保留。'),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 12, children: [FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, false), child: const Text('取消')), FButton(variant: FButtonVariant.destructive, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, true), child: const Text('移除'))]),
      ])))) ?? false;
      if (!confirmed || !mounted || api.epoch != epoch) return;
    }
    if (!mounted || api.epoch != epoch) return;
    setState(() => _managing = true);
    try {
      if (remove) {
        await ref.read(repositoryProvider).removeWorks(selected);
        api.assertEpoch(epoch);
        if (mounted) { ref.invalidate(worksProvider); ref.invalidate(favoritesProvider); toast(context, '已移除选中作品'); setState(_selected.clear); }
      } else { await exportImages(context, ref, selected); }
    } catch (error) { if (mounted && api.epoch == epoch) { ref.invalidate(worksProvider); ref.invalidate(favoritesProvider); toast(context, errorMessage(error)); } }
    finally { if (mounted && api.epoch == epoch) setState(() => _managing = false); }
  }

  Future<void> _recover(GenerationRun run) async {
    final api = ref.read(apiProvider), repository = ref.read(repositoryProvider), router = GoRouter.of(context);
    final epoch = api.epoch, page = _page;
    bool current() => mounted && _tasks && api.epoch == epoch && _page == page && router.routeInformationProvider.value.uri.path == '/works';
    final service = GenerationService(api);
    setState(() => _recovering = run.id);
    try {
      GenerationOutput output;
      try {
        output = await service.recover(run.id);
      } on GenerationContextMissing catch (missing) {
        if (!mounted || !current()) return;
        final input = await showFDialog<({String prompt, String ratio, String quality})>(context: context, builder: (_, style, animation) => _RecoveryContextDialog(style: style, animation: animation, missing: missing, current: current));
        if (!current() || input == null) return;
        output = await service.recover(run.id, prompt: input.prompt, ratio: input.ratio, quality: input.quality);
      }
      if (!current()) return;
      await repository.saveGeneration(output);
      if (!mounted || !current()) return;
      ref.invalidate(worksProvider);
      ref.invalidate(taskPageProvider(_page));
      ref.invalidate(creditsProvider);
      toast(context, output.notice.isEmpty ? '已恢复可读取的图片' : output.notice);
    } catch (error) { if (mounted && current()) toast(context, errorMessage(error)); }
    finally { if (mounted && _recovering == run.id) setState(() => _recovering = ''); }
  }

  Future<void> _resumeVideo(VideoWork work) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() => _recovering = work.id);
    try {
      final models = await ref.read(catalogProvider.future);
      api.assertEpoch(epoch);
      if (!mounted || _kind != 'video' || _tasks) return;
      final current = ref.read(videoGenerationProvider);
      if (current.busy || current.saving) throw const ApiException('当前已有视频任务正在处理，请先在 AI 视频页面查看');
      final model = models.where((model) => model.value == work.model).firstOrNull;
      if (model == null) throw const ApiException('原渠道或模型已不可用，请先恢复渠道配置');
      ref.read(videoGenerationProvider.notifier).resume(work, model);
      context.go('/video');
    } catch (error) { if (mounted && api.epoch == epoch) toast(context, errorMessage(error)); }
    finally { if (mounted && _recovering == work.id) setState(() => _recovering = ''); }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth < 600 ? 2 : constraints.maxWidth < 1000 ? 3 : 4;
    return CustomScrollView(slivers: [
      SliverPadding(padding: EdgeInsets.fromLTRB(constraints.maxWidth < 600 ? 20 : 32, 32, 24, 24), sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('我的作品', style: context.theme.typography.display.xl2),
        const SizedBox(height: 8), Text('新图片按日期保存在本机，云端历史保留查看，不自动搬移。', style: TextStyle(color: context.theme.colors.mutedForeground)),
        const SizedBox(height: 24),
        Wrap(spacing: 8, runSpacing: 12, children: [
          FButton(mainAxisSize: MainAxisSize.min, variant: _tasks ? FButtonVariant.ghost : FButtonVariant.secondary, onPress: () => setState(() => _tasks = false), child: const Text('作品')),
          FButton(mainAxisSize: MainAxisSize.min, variant: _tasks ? FButtonVariant.secondary : FButtonVariant.ghost, onPress: () => setState(() => _tasks = true), child: const Text('生成任务')),
          FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '刷新列表', onPress: () { ref.invalidate(worksProvider); ref.invalidate(favoritesProvider); ref.invalidate(serverImageHistoryProvider); ref.invalidate(videoWorksProvider); ref.invalidate(taskPageProvider(_page)); }, child: const Icon(FLucideIcons.refreshCw, size: 18)),
        ]),
        if (!_tasks) ...[
          const SizedBox(height: 20), Wrap(spacing: 8, runSpacing: 8, children: [
            for (final kind in [('image', '本机图片'), ('favorite', '本机收藏'), ('server', '云端历史'), ('video', '视频')]) FButton(variant: _kind == kind.$1 ? FButtonVariant.primary : FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _managing ? null : () => setState(() { _kind = kind.$1; _selected.clear(); _selecting = false; }), child: Text(kind.$2)),
            if (_kind == 'image' || _kind == 'favorite') FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.listChecks, size: 15), onPress: _managing ? null : () => setState(() { _selecting = !_selecting; _selected.clear(); }), child: Text(_selecting ? '完成管理' : '批量管理')),
          ]),
          const SizedBox(height: 16), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: FTextField(hint: '搜索作品、模型或提示词', prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 12), child: Icon(FLucideIcons.search, size: 16)), control: FTextFieldControl.managed(onChange: (value) => setState(() => _keyword = value.text)))),
          if (_selecting) ...[const SizedBox(height: 12), Row(spacing: 12, children: [
            Text('已选 ${_selected.length} 件', style: context.theme.typography.body.xs),
            FButton(variant: FButtonVariant.secondary, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.download, size: 15), onPress: _selected.isEmpty || _managing ? null : () => _manage(ref.read(_kind == 'favorite' ? favoritesProvider : worksProvider).asData?.value ?? []), child: const Text('下载')),
            FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.trash2, size: 15), onPress: _selected.isEmpty || _managing ? null : () => _manage(ref.read(_kind == 'favorite' ? favoritesProvider : worksProvider).asData?.value ?? [], remove: true), child: const Text('移除')),
          ])],
        ],
      ]))),
      if (_tasks) _taskList() else if (_kind == 'video') _videoList() else ref.watch(_images).when(
        loading: () => const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '正在读取作品', loading: true)),
        error: (error, _) => SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '作品读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(_images), child: const Text('重新读取')))),
        data: (works) {
          final filtered = works.where((work) => '${work.title} ${work.prompt} ${work.model}'.toLowerCase().contains(_keyword.toLowerCase())).toList();
          if (filtered.isEmpty) return SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: works.isEmpty ? _kind == 'favorite' ? '还没有收藏' : '还没有作品' : '没有找到匹配作品', description: works.isEmpty ? _kind == 'favorite' ? '收藏喜欢的灵感，独立副本会保存在这里。' : '完成第一次创作，你的作品会出现在这里。' : '试试其他关键词。', action: works.isEmpty ? FButton(mainAxisSize: MainAxisSize.min, onPress: () => context.go(_kind == 'favorite' ? '/explore' : '/create'), child: Text(_kind == 'favorite' ? '探索灵感' : '开始创作')) : null));
          return SliverPadding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), sliver: SliverMasonryGrid.count(crossAxisCount: columns, mainAxisSpacing: 12, crossAxisSpacing: 12, childCount: filtered.length, itemBuilder: (_, index) {
            final work = filtered[index];
            return Stack(children: [
              ArtworkTile(artwork: work, imageOnly: AppLayout.isDesktop, onPress: _selecting ? () { if (!_managing) setState(() => _selected.contains(work.id) ? _selected.remove(work.id) : _selected.add(work.id)); } : () => context.push('/work', extra: work)),
              if (_selecting) Positioned(top: 8, right: 8, child: IgnorePointer(child: FBadge(child: Icon(_selected.contains(work.id) ? FLucideIcons.circleCheck : FLucideIcons.circle, size: 18)))),
            ]);
          }));
        },
      ),
    ]);
  });

  Widget _videoList() => ref.watch(videoWorksProvider).when(
    loading: () => const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '正在读取视频作品', loading: true)),
    error: (error, _) => SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '视频读取失败', description: errorMessage(error), action: FButton(onPress: () => ref.invalidate(videoWorksProvider), child: const Text('重新读取')))),
    data: (works) {
      final filtered = works.where((work) => '${work.title} ${work.prompt} ${work.model}'.toLowerCase().contains(_keyword.toLowerCase())).toList();
      return SliverPadding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), sliver: SliverList.list(children: [
        if (filtered.isEmpty) const StatePanel(title: '暂时没有相关视频', description: '生成完成的视频会保存在这里。', icon: FLucideIcons.video),
        for (final work in filtered) Padding(padding: const EdgeInsets.only(bottom: 12), child: FCard(builder: cardBody, child: Row(spacing: 16, children: [
          Icon(FLucideIcons.video, color: context.theme.colors.mutedForeground),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Text(work.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), Text(work.status == 'success' ? '已保存视频' : work.status == 'failed' ? '已确认失败' : '待核对', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground))])),
          FButton(variant: FButtonVariant.secondary, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _recovering.isNotEmpty ? null : () => work.status == 'success' ? context.push('/video/work', extra: work) : work.status == 'failed' ? context.go('/works?tab=tasks') : _resumeVideo(work), child: Text(_recovering == work.id ? '读取中' : work.status == 'success' ? '查看' : work.status == 'failed' ? '查看任务' : '核对进度')),
        ]))),
      ]));
    },
  );

  Widget _taskList() => ref.watch(taskPageProvider(_page)).when(
    loading: () => const SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '正在读取任务', loading: true)),
    error: (error, _) => SliverFillRemaining(hasScrollBody: false, child: StatePanel(title: '任务读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(taskPageProvider(_page)), child: const Text('重新读取')))),
    data: (data) {
      final items = (data['items'] as List).map((item) => GenerationRun.fromJson(jsonObject(item))).toList();
      final total = jsonInt(data['total']);
      return SliverPadding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), sliver: SliverList.list(children: [
        if (items.isEmpty) const StatePanel(title: '暂时没有生成任务', description: '开始创作后可以在这里查看任务状态。'),
        for (final run in items) Padding(padding: const EdgeInsets.only(bottom: 12), child: FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, children: [Text(run.model.split('::').last, style: const TextStyle(fontWeight: FontWeight.w600)), FBadge(child: Text(run.statusLabel)), Text(switch (run.capability) {'image' => '图片', 'video' => '视频', 'audio' => '音频', _ => '文本'})]),
          const SizedBox(height: 8), Text('${run.createdAt.toLocal().toString().split('.').first} · 已确认 ${run.resultCount}/${run.requestedCount} ${run.capability == 'image' ? '张' : '个结果'}', style: TextStyle(fontSize: 12, color: context.theme.colors.mutedForeground)),
          if (run.message.isNotEmpty) ...[const SizedBox(height: 8), Text(run.message)],
          if (run.capability == 'image') ...[const SizedBox(height: 16), FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: _recovering == run.id ? const FCircularProgress() : const Icon(FLucideIcons.rotateCcw, size: 16), onPress: _recovering.isNotEmpty ? null : () => _recover(run), child: const Text('核对并恢复图片'))],
          if (run.capability == 'video') ...[const SizedBox(height: 16), FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.video, size: 16), onPress: () => context.go('/video'), child: const Text('查看视频任务'))],
        ]))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: _page == 1 || _recovering.isNotEmpty ? null : () => setState(() => _page--), child: const Text('上一页')),
          Text('第 $_page 页 · 共 $total 个任务', style: TextStyle(fontSize: 12, color: context.theme.colors.mutedForeground)),
          FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: _page * 10 >= total || _recovering.isNotEmpty ? null : () => setState(() => _page++), child: const Text('下一页')),
        ]),
      ]));
    },
  );
}

class _RecoveryContextDialog extends ConsumerStatefulWidget {
  const _RecoveryContextDialog({required this.style, required this.animation, required this.missing, required this.current});
  final FDialogStyle style;
  final Animation<double> animation;
  final GenerationContextMissing missing;
  final bool Function() current;
  @override
  ConsumerState<_RecoveryContextDialog> createState() => _RecoveryContextDialogState();
}

class _RecoveryContextDialogState extends ConsumerState<_RecoveryContextDialog> {
  late final _prompt = TextEditingController(text: widget.missing.prompt), _ratio = TextEditingController(text: widget.missing.ratio);
  late String? _quality = widget.missing.quality.isEmpty ? null : widget.missing.quality;
  String? _error;

  @override
  void dispose() { _prompt.dispose(); _ratio.dispose(); super.dispose(); }

  void _confirm() {
    if (!widget.current()) { Navigator.pop(context); return; }
    final prompt = _prompt.text.trim(), ratio = _ratio.text.trim(), quality = _quality;
    if (prompt.isEmpty || ratio.isEmpty || quality == null) { setState(() => _error = '请填写当时使用的提示词、比例，并选择图片质量'); return; }
    Navigator.pop(context, (prompt: prompt, ratio: ratio, quality: quality));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((session) => session.asData?.value?.id), (previous, next) {
      if (previous != next && mounted) Navigator.pop(context);
    });
    return FDialog(style: widget.style, animation: widget.animation, builder: (context, style) => Padding(padding: const EdgeInsets.all(24), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
      Text('补充创作上下文', style: style.titleTextStyle),
      Text('该任务没有保存完整的创作参数。请填写当时的实际内容，用于整理已生成的图片。', style: style.bodyTextStyle.copyWith(color: context.theme.colors.mutedForeground)),
      ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .3), child: FTextField.multiline(control: FTextFieldControl.managed(controller: _prompt), label: const Text('实际提示词'), hint: '填写创建这个任务时使用的提示词', minLines: 3, autofocus: true)),
      FTextField(control: FTextFieldControl.managed(controller: _ratio), label: const Text('实际比例或尺寸'), hint: '如 1:1、1024x1024 或 auto'),
      FSelect<String>(label: const Text('实际图片质量'), hint: '请选择当时使用的质量', items: const {'自动': 'auto', '标准': 'low', '精细': 'medium', '高质量': 'high'}, control: FSelectControl.lifted(value: _quality, onChange: (value) => setState(() => _quality = value))),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('尚未恢复'), subtitle: Text(_error!)),
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
        FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context), child: const Text('取消')),
        FButton(mainAxisSize: MainAxisSize.min, onPress: _confirm, child: const Text('确认并恢复')),
      ]),
    ]))));
  }
}
