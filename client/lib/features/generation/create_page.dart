import 'package:file_selector/file_selector.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'generation_controller.dart';
import 'create_draft.dart';
import '../catalog/catalog_providers.dart';
import '../channels/channel_providers.dart';

class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key});
  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  late final TextEditingController _prompt;
  late final TextEditingController _count;
  late final int _draftEpoch;
  String? _modelId;
  String _ratio = '1:1', _quality = 'auto';
  bool _asynchronous = false, _imageMode = false, _dragging = false, _batchMode = false;
  ImageReference? _reference;
  String _resultRunId = '';
  int _selectedResult = 0;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(imageDraftProvider);
    _draftEpoch = ref.read(apiProvider).epoch;
    _prompt = TextEditingController(text: ref.read(promptDraftProvider));
    _count = TextEditingController(text: draft.count);
    _modelId = draft.modelId;
    _ratio = draft.ratio; _quality = draft.quality;
    _asynchronous = draft.asynchronous; _imageMode = draft.imageMode; _reference = draft.reference; _batchMode = draft.batchMode;
    _count.addListener(_saveDraft);
  }

  @override
  void dispose() { _prompt.dispose(); _count.dispose(); super.dispose(); }

  void _saveDraft() {
    if (mounted && ref.read(apiProvider).epoch == _draftEpoch) ref.read(imageDraftProvider.notifier).setDraft(ImageDraft(modelId: _modelId, ratio: _ratio, quality: _quality, count: _count.text, asynchronous: _asynchronous, imageMode: _imageMode, batchMode: _batchMode, reference: _reference));
  }
  void _update(VoidCallback action) {
    if (!mounted || ref.read(apiProvider).epoch != _draftEpoch) return;
    setState(action); _saveDraft();
  }
  bool _current(int epoch) => mounted && ref.read(apiProvider).epoch == epoch && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _readReference(XFile file) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final bookmark = file is DropItem ? file.extraAppleBookmark : null;
    var accessed = false;
    try {
      if (bookmark != null) accessed = await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark);
      final bytes = await file.readAsBytes();
      api.assertEpoch(epoch);
      final mime = lookupMimeType(file.name, headerBytes: bytes);
      if (!['image/png', 'image/jpeg', 'image/webp'].contains(mime)) throw const ApiException('请选择 PNG、JPEG 或 WebP 图片');
      if (_current(epoch)) _update(() { _reference = ImageReference(bytes: bytes, mimeType: mime!, filename: file.name); _imageMode = true; });
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
    finally { if (accessed && bookmark != null) await DesktopDrop.instance.stopAccessingSecurityScopedResource(bookmark: bookmark); }
  }

  Future<void> _pickReference() async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    try {
      final file = await openFile(acceptedTypeGroups: [const XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp'], uniformTypeIdentifiers: ['public.image'], mimeTypes: ['image/png', 'image/jpeg', 'image/webp'])]);
      api.assertEpoch(epoch);
      if (file != null && _current(epoch)) await _readReference(file);
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
  }

  Future<void> _importPrompts() async {
    final epoch = ref.read(apiProvider).epoch;
    try {
      final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '提示词文本', extensions: ['txt'], uniformTypeIdentifiers: ['public.plain-text'])]);
      if (file == null || !_current(epoch)) return;
      final text = await file.readAsString();
      if (!_current(epoch)) return;
      if (ref.read(generationProvider).working) return;
      _prompt.text = text.replaceFirst('\uFEFF', '');
      ref.read(promptDraftProvider.notifier).setPrompt(_prompt.text);
      setState(() {});
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
  }
  List<String> get _prompts => _prompt.text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();

  void _generate(List<ImageModel> models) {
    if (!mounted || ref.read(apiProvider).epoch != _draftEpoch) return;
    final state = ref.read(generationProvider);
    if (state.working || state.hasUnsaved) return;
    final model = models.where((item) => item.id == _modelId).firstOrNull ?? models.firstOrNull;
    if (model == null || !imageParameters(model).supported) return;
    final parameters = imageParameters(model);
    if (_imageMode && _reference == null) { toast(context, '请先添加参考图片'); return; }
    final count = parameters.singleImageEdit && _imageMode ? 1 : int.tryParse(_count.text);
    if (count == null || count < 1) { toast(context, '请输入正整数图片数量'); return; }
    if (_prompt.text.trim().isEmpty) { toast(context, '请填写提示词'); return; }
    ref.read(promptDraftProvider.notifier).setPrompt(_prompt.text);
    if (_batchMode) {
      ref.read(generationProvider.notifier).generateBatch(model, prompts: _prompts, ratio: parameters.ratio ? _ratio : 'auto', count: count, quality: parameters.quality ? _quality : 'auto', reference: _imageMode ? _reference : null, asynchronous: _asynchronous && parameters.asynchronous);
      return;
    }
    ref.read(generationProvider.notifier).generate(model, prompt: _prompt.text, ratio: parameters.ratio ? _ratio : 'auto', count: count, quality: parameters.quality ? _quality : 'auto', reference: _imageMode ? _reference : null, asynchronous: _asynchronous && parameters.asynchronous);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(imageDraftProvider);
    final models = ref.watch(modelsProvider);
    final state = ref.watch(generationProvider);
    final issues = ref.watch(catalogIssuesProvider);
    ref.listen(defaultModelProvider, (_, value) {
      if (_modelId == null && value.asData?.value != null) _update(() => _modelId = value.asData!.value);
    });
    _modelId ??= ref.watch(defaultModelProvider).asData?.value;
    if (_resultRunId != (state.output?.runId ?? '')) { _resultRunId = state.output?.runId ?? ''; _selectedResult = 0; }
    return models.when(
      loading: () => const StatePanel(title: '正在读取可用模型', loading: true),
      error: (error, _) => StatePanel(title: '模型读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => refreshCatalog(ref), child: const Text('重新读取'))),
      data: (models) => models.isEmpty
        ? StatePanel(title: issues.isEmpty ? '暂时没有可用图片模型' : '图片模型目录尚未完整读取', description: issues.isEmpty ? '请在渠道设置中添加个人接口，或联系管理员开放图片模型。' : issues.entries.map((entry) => '${entry.key}：${entry.value}').join('\n'), icon: FLucideIcons.box, action: issues.isEmpty ? null : FButton(mainAxisSize: MainAxisSize.min, onPress: () => refreshCatalog(ref), child: const Text('重试目录')))
        : CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _generate(models), const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => _generate(models)},
            child: LayoutBuilder(builder: (context, bounds) {
              final desktop = AppLayout.isDesktop;
              final width = desktop && bounds.maxWidth < 920 ? 920.0 : bounds.maxWidth;
              final workspace = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [
                Row(children: [Text('AI 生图', style: context.theme.typography.display.xl2), const Spacer(), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '查看生成记录', semanticsTooltip: '查看生成记录', onPress: () => context.go('/works'), child: const Icon(FLucideIcons.history, size: 17))]),
                if (issues.isNotEmpty) ...[for (final entry in issues.entries) FAlert(title: Text('${entry.key}暂时无法读取'), subtitle: Text(entry.value)), FButton(mainAxisSize: MainAxisSize.min, variant: FButtonVariant.ghost, onPress: () => refreshCatalog(ref), child: const Text('重试目录'))],
                _composer(state, models),
                if (!desktop) FButton(variant: FButtonVariant.secondary, prefix: const Icon(FLucideIcons.slidersHorizontal, size: 16), onPress: () => _showParameters(models), child: const Text('模型与生成参数')),
                if (_batchMode && state.batch.isNotEmpty) _batchResults(state) else _results(state),
              ]);
              if (!desktop) return Column(children: [Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: workspace)), SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: _operation(models, state)))]);
              return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: width, height: bounds.maxHeight, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: workspace)),
                SizedBox(width: 310, child: Padding(padding: const EdgeInsets.fromLTRB(0, 32, 24, 24), child: Column(spacing: 16, children: [Expanded(child: SingleChildScrollView(child: _parameters(models, state))), _operation(models, state)]))),
              ])));
            }),
          ),
    );
  }

  Widget _composer(GenerationState state, List<ImageModel> models) {
    final busy = state.working;
    final model = models.where((item) => item.id == _modelId).firstOrNull ?? models.first;
    final supported = imageParameters(model).supported;
    final theme = context.theme;
    return FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: [
      Row(spacing: 8, children: [
        for (final mode in [(false, '单次创作'), (true, '批量生图')]) FButton(variant: _batchMode == mode.$1 ? FButtonVariant.secondary : FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: busy || state.hasUnsaved ? null : () => _update(() => _batchMode = mode.$1), child: Text(mode.$2)),
        const Spacer(),
        if (_batchMode) FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '导入提示词 TXT', onPress: busy ? null : _importPrompts, child: const Icon(FLucideIcons.fileInput, size: 17)),
      ]),
      Row(spacing: 8, children: [
        for (final mode in [(false, '文生图'), (true, '图生图')]) FButton(variant: _imageMode == mode.$1 ? FButtonVariant.primary : FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: busy || !supported ? null : () => _update(() => _imageMode = mode.$1), child: Text(mode.$2)),
      ]),
      FTextField.multiline(control: FTextFieldControl.managed(controller: _prompt, onChange: (value) { if (ref.read(apiProvider).epoch == _draftEpoch) { ref.read(promptDraftProvider.notifier).setPrompt(value.text); if (_batchMode) setState(() {}); } }), hint: _batchMode ? '每行一条提示词，空行忽略。也可导入 TXT 文件。\n例如：雨夜街头的蓝色跑车\n例如：暖光下的玻璃香水瓶' : '描述你的想象：主体、光线、色彩，以及每一个细节…', minLines: 4, maxLines: 7, enabled: !busy),
      if (_batchMode) Text('共 ${_prompts.length} 项 · 使用相同模型与参数${_imageMode ? '及参考图' : ''}。逐项执行，失败后继续，不自动重试。请保持应用运行。', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
      Text('新图片按日期保存到本机；服务器不提供图片备份。保存位置可在个人设置中修改。', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
      if (_imageMode) DropTarget(
        enable: AppLayout.isDesktop && !busy && supported && ModalRoute.of(context)?.isCurrent == true && GoRouter.of(context).routeInformationProvider.value.uri.path == '/create',
        onDragEntered: (_) => setState(() => _dragging = true), onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) { setState(() => _dragging = false); if (details.files.length == 1) { _readReference(details.files.single); } else { toast(context, '当前模式支持一张参考图片，请选择单张图片'); } },
        child: AnimatedContainer(duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.fast, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _dragging ? theme.colors.secondary : theme.colors.muted, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: _dragging ? AppTheme.accent : theme.colors.border)), child: Row(spacing: 14, children: [
          if (_reference != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 64, height: 64, child: Image.memory(_reference!.bytes, fit: BoxFit.cover, cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context)).ceil()))) else Icon(FLucideIcons.imagePlus, size: 28, color: theme.colors.mutedForeground),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [Text(_reference?.filename ?? '添加参考图片', maxLines: 1, overflow: TextOverflow.ellipsis), Text(AppLayout.isDesktop ? '拖入图片，或点击选择' : '从照片或文件中选择', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground))])),
          FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '选择参考图片', onPress: busy || !supported ? null : _pickReference, child: const Icon(FLucideIcons.plus, size: 18)),
          if (_reference != null) FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '移除参考图片', onPress: busy ? null : () => _update(() => _reference = null), child: const Icon(FLucideIcons.x, size: 16)),
        ])),
      ),
      Text('⌘ / Ctrl + Enter 开始生成', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
    ]));
  }

  void _showParameters(List<ImageModel> models) {
    showFSheet(context: context, side: FLayout.btt, mainAxisMaxRatio: .85, useSafeArea: true, builder: (sheetContext) => Consumer(builder: (sheetContext, sheetRef, _) {
      sheetRef.listen(sessionProvider.select((session) => session.asData?.value?.id), (previous, next) { if (previous != next && sheetContext.mounted) Navigator.of(sheetContext).pop(); });
      final state = sheetRef.watch(generationProvider);
      return StatefulBuilder(builder: (sheetContext, updateSheet) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: _parameters(models, state, refresh: () => updateSheet(() {}))));
    }));
  }

  Widget _parameters(List<ImageModel> models, GenerationState state, {VoidCallback? refresh}) {
    final selected = models.where((model) => model.id == _modelId).firstOrNull ?? models.first;
    final parameters = imageParameters(selected);
    final busy = state.working;
    void update(VoidCallback action) { _update(action); refresh?.call(); }
    return FCard(key: const ValueKey('image-parameters'), builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: [
      const Text('模型设置', style: TextStyle(fontWeight: FontWeight.w600)),
      FSelect<String>.rich(label: const Text('创作模型'), format: (id) => models.firstWhere((model) => model.id == id).name,
        enabled: !busy, control: FSelectControl.lifted(value: selected.id, onChange: (value) => update(() => _modelId = value)),
        children: [for (final model in models) FSelectItem(title: Text('${model.name} · ${model.providerName}'), value: model.id)]),
      if (!parameters.supported) Text('该模型的图片协议尚未接入，请切换模型。', style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
      if (parameters.ratio) FSelect(label: const Text('画幅比例'), items: const {'自动': 'auto', '方形 · 1:1': '1:1', '竖向 · 3:4': '3:4', '横向 · 4:3': '4:3', '手机 · 9:16': '9:16', '宽屏 · 16:9': '16:9'}, control: FSelectControl.lifted(value: _ratio, onChange: (value) { if (value != null) update(() => _ratio = value); }), enabled: !busy),
      if (parameters.quality) FSelect(label: Text(parameters.qualityAsSize ? '输出尺寸' : '图片质量'), items: parameters.qualityAsSize ? const {'自动': 'auto', '1K': 'low', '2K': 'medium', '4K': 'high'} : const {'自动': 'auto', '标准': 'low', '精细': 'medium', '高质量': 'high'}, control: FSelectControl.lifted(value: _quality, onChange: (value) { if (value != null) update(() => _quality = value); }), enabled: !busy),
      if (parameters.supported && !parameters.ratio) Text('画幅与输出质量由上游确定。', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
      if (parameters.asynchronous) FAccordion(children: [FAccordionItem(title: const Text('高级设置'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        FSelect(label: const Text('请求方式'), items: const {'同步生成': 'sync', '标准异步任务': 'async'}, control: FSelectControl.lifted(value: _asynchronous ? 'async' : 'sync', onChange: (value) => update(() => _asynchronous = value == 'async')), enabled: !busy),
        Text('仅在渠道支持标准图片任务接口时开启异步任务。未知结果保留在任务记录中核对。', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
      ]))]),
    ]));
  }

  Widget _operation(List<ImageModel> models, GenerationState state) {
    final selected = models.where((model) => model.id == _modelId).firstOrNull ?? models.first;
    final parameters = imageParameters(selected), busy = state.working;
    final singleEdit = parameters.singleImageEdit && _imageMode;
    final count = singleEdit ? 1 : int.tryParse(_count.text);
    return FCard(key: const ValueKey('image-operation'), builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      if (singleEdit) Text(_batchMode ? '参考图编辑 · 每项生成 1 张' : '参考图编辑 · 本次生成 1 张') else FTextField(control: FTextFieldControl.managed(controller: _count), label: Text(_batchMode ? '每项生成数量' : '生成数量'), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], enabled: !busy && parameters.supported),
      Text(selected.providerId.startsWith('local:') ? '个人渠道 · 由渠道计费' : '${count != null && count > 0 ? '预计 ${selected.creditCost * count * (_batchMode ? _prompts.length : 1)} 算力' : '每张 ${selected.creditCost} 算力'} · 以服务端记录为准', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
      if (state.hasUnsaved) Text('请先重新保存已生成的图片，再开始新创作。', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.destructive)),
      FButton(prefix: busy ? const FCircularProgress() : const Icon(FLucideIcons.sparkles, size: 17), onPress: busy || state.hasUnsaved || !parameters.supported ? null : () => _generate(models), child: Text(state.saving ? '正在保存到本机' : busy ? '正在生成' : _batchMode ? '开始批量生成' : '立即生成')),
      if (state.batchRunning && state.batch.any((item) => item.status == BatchImageStatus.queued)) FButton(variant: FButtonVariant.outline, onPress: state.stopRequested ? null : () => ref.read(generationProvider.notifier).stopBatch(), child: Text(state.stopRequested ? '当前项完成后停止' : '停止后续任务')),
    ]));
  }

  Widget _batchResults(GenerationState state) {
    final completed = state.batch.where((item) => ![BatchImageStatus.queued, BatchImageStatus.generating, BatchImageStatus.saving].contains(item.status)).length;
    final saved = state.batch.fold<int>(0, (count, item) => count + item.works.length);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Row(children: [const Text('批量任务', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), const Spacer(), Text('$completed / ${state.batch.length} 项 · 已保存 $saved 张', style: context.theme.typography.body.xs)]),
      FDeterminateProgress(value: completed / state.batch.length, semanticsLabel: '已处理 $completed 项，共 ${state.batch.length} 项'),
      if (state.stopRequested) const FAlert(title: Text('已请求停止后续任务'), subtitle: Text('当前已提交的请求继续接收并保存结果，未执行项不会扣费。')),
      for (var index = 0; index < state.batch.length; index++) FCard(builder: cardBody, child: Builder(builder: (context) {
        final item = state.batch[index];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Row(spacing: 10, children: [Text('${index + 1}'.padLeft(2, '0'), style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)), Expanded(child: Text(item.prompt, maxLines: 2, overflow: TextOverflow.ellipsis)), FBadge(variant: FBadgeVariant.secondary, child: Text(item.label))]),
          if (item.error.isNotEmpty) Text(item.error, style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
          if (item.status == BatchImageStatus.saveFailed) FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: state.working ? null : () => ref.read(generationProvider.notifier).saveBatchItem(index), child: const Text('仅重新保存，不重新生成')),
          if (item.output != null) ...[
            const Text('以下图片仍在内存中，未完成本机保存，请勿退出应用。'),
            SizedBox(height: 120, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: item.output!.images.length, separatorBuilder: (_, _) => const SizedBox(width: 10), itemBuilder: (_, image) => ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: Image.memory(item.output!.images[image].bytes, width: 120, height: 120, fit: BoxFit.cover, cacheWidth: (120 * MediaQuery.devicePixelRatioOf(context)).ceil())))),
          ],
          if (item.runId.isNotEmpty && [BatchImageStatus.failed, BatchImageStatus.partial].contains(item.status)) FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => context.go('/tasks'), child: const Text('查看真实任务状态')),
          if (item.works.isNotEmpty) SizedBox(height: 120, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: item.works.length, separatorBuilder: (_, _) => const SizedBox(width: 10), itemBuilder: (_, image) => SizedBox(width: 120, child: ArtworkTile(artwork: item.works[image], imageOnly: true, onPress: () => context.push('/work', extra: item.works[image]))))),
        ]);
      })),
    ]);
  }

  Widget _results(GenerationState state) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [const Text('生成结果', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), const Spacer(), if (state.output != null) Text('${state.works.isNotEmpty ? state.works.length : state.output!.images.length} 张', style: TextStyle(color: context.theme.colors.mutedForeground))]),
    const SizedBox(height: 18),
    if (state.error.isNotEmpty) ...[
      FAlert(title: const Text('本次操作需要处理'), subtitle: Text(state.error)),
      const SizedBox(height: 12),
      if (state.output != null) FButton(variant: FButtonVariant.outline, onPress: state.saving ? null : () => ref.read(generationProvider.notifier).saveOutput(), child: const Text('重新保存已生成图片')),
      if (state.runId.isNotEmpty) FButton(variant: FButtonVariant.ghost, onPress: () => context.go('/tasks'), child: const Text('前往任务记录核对')),
      const SizedBox(height: 16),
    ],
    if (state.output?.notice.isNotEmpty == true) ...[FAlert(title: const Text('任务提示'), subtitle: Text(state.output!.notice)), const SizedBox(height: 16)],
    if (state.busy) const FCard(child: SizedBox(height: 330, child: StatePanel(title: '灵感正在成形', description: '模型正在绘制。你可以切换页面，稍后在这里查看结果。', loading: true)))
    else if (state.output == null) FCard(child: SizedBox(height: 330, child: StatePanel(title: '下一张作品，从这里诞生', description: '写下画面描述，选择模型与比例。', icon: FLucideIcons.aperture)))
    else LayoutBuilder(builder: (context, bounds) {
      final columns = bounds.maxWidth >= 760 ? 3 : 2;
      if (state.works.isNotEmpty) return MasonryGridView.count(key: const ValueKey('saved-image-results'), crossAxisCount: state.works.length == 1 ? 1 : columns, mainAxisSpacing: 12, crossAxisSpacing: 12, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: state.works.length, itemBuilder: (context, index) => ArtworkTile(artwork: state.works[index], imageOnly: true, onPress: () => context.push('/work', extra: state.works[index])));
      final images = state.output!.images;
      if (images.isEmpty) return const StatePanel(title: '没有可显示的图片', description: '请在任务记录中核对上游结果。');
      final selected = _selectedResult.clamp(0, images.length - 1);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        FCard(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 440), child: Image.memory(images[selected].bytes, fit: BoxFit.contain, gaplessPlayback: true))),
        Text(state.saving ? '正在保存 ${images.length} 张图片' : '图片已取得，尚未保存到作品库', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
        if (images.length > 1) GridView.builder(key: const ValueKey('unsaved-image-thumbnails'), shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 10, crossAxisSpacing: 10), itemCount: images.length, itemBuilder: (context, index) => FButton.raw(variant: FButtonVariant.ghost, selected: selected == index, semanticsLabel: '预览第 ${index + 1} 张图片', onPress: () => setState(() => _selectedResult = index), child: Container(clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: selected == index ? context.theme.colors.primary : context.theme.colors.border, width: selected == index ? 2 : 1)), child: Image.memory(images[index].bytes, fit: BoxFit.contain, cacheWidth: (bounds.maxWidth / columns * MediaQuery.devicePixelRatioOf(context)).ceil())))),
      ]);
    }),
  ]);
}
