import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../channels/channel_providers.dart';
import 'media_info.dart';
import 'video_actions.dart';
import 'video_controller.dart';
import 'video_preview.dart';
import 'video_repository.dart';
import 'video_service.dart';
import 'video_draft.dart';

class VideoPage extends ConsumerStatefulWidget {
  const VideoPage({super.key});
  @override
  ConsumerState<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<VideoPage> {
  late final TextEditingController _prompt, _seconds;
  late final int _draftEpoch;
  String? _modelId;
  String _ratio = '16:9', _resolution = '720p', _mode = 'generate';
  bool _audio = true, _watermark = false, _reading = false, _dragging = false, _savingAsset = false;
  final _references = <VideoReference>[];

  @override
  void initState() {
    super.initState();
    final draft = ref.read(videoDraftProvider);
    _draftEpoch = ref.read(apiProvider).epoch;
    _prompt = TextEditingController(text: draft.prompt); _seconds = TextEditingController(text: draft.seconds);
    _modelId = draft.modelId; _ratio = draft.ratio; _resolution = draft.resolution; _mode = draft.mode;
    _audio = draft.audio; _watermark = draft.watermark; _references.addAll(draft.references);
    _prompt.addListener(_saveDraft); _seconds.addListener(_saveDraft);
  }

  @override
  void dispose() { _prompt.dispose(); _seconds.dispose(); super.dispose(); }

  void _saveDraft() {
    if (mounted && ref.read(apiProvider).epoch == _draftEpoch) ref.read(videoDraftProvider.notifier).setDraft(VideoDraft(prompt: _prompt.text, modelId: _modelId, seconds: _seconds.text, ratio: _ratio, resolution: _resolution, mode: _mode, audio: _audio, watermark: _watermark, references: List.unmodifiable(_references)));
  }
  void _update(VoidCallback action) {
    if (!mounted || ref.read(apiProvider).epoch != _draftEpoch) return;
    setState(action); _saveDraft();
  }

  ImageModel? _selected(List<ImageModel> models) => models.where((model) => model.id == _modelId).firstOrNull ?? models.firstOrNull;
  bool get _busy => ref.read(videoGenerationProvider).busy || ref.read(videoGenerationProvider).saving || _reading;
  bool _current(int epoch) => mounted && ref.read(apiProvider).epoch == epoch && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _pick(String kind) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    try {
      final files = await openFiles(acceptedTypeGroups: [switch (kind) {
        'image' => const XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp'], uniformTypeIdentifiers: ['public.image']),
        'video' => const XTypeGroup(label: '视频', extensions: ['mp4', 'mov'], uniformTypeIdentifiers: ['public.movie']),
        _ => const XTypeGroup(label: '音频', extensions: ['mp3', 'wav'], uniformTypeIdentifiers: ['public.audio']),
      }]);
      api.assertEpoch(epoch);
      if (_current(epoch)) await _readFiles(files);
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
  }

  Future<void> _readFiles(List<XFile> files) async {
    if (_busy || files.isEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() { _reading = true; _dragging = false; });
    final accepted = <VideoReference>[];
    try {
      for (final file in files) {
        api.assertEpoch(epoch);
        final bookmark = file is DropItem ? file.extraAppleBookmark : null;
        var access = false;
        try {
          if (Platform.isMacOS && bookmark != null && bookmark.isNotEmpty) access = await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark);
          api.assertEpoch(epoch);
          final bytes = await file.readAsBytes();
          api.assertEpoch(epoch);
          if (!_current(epoch)) return;
          final mime = lookupMimeType(file.name, headerBytes: bytes) ?? '';
          final kind = mime.startsWith('image/') ? 'image' : ['video/mp4', 'video/quicktime'].contains(mime) ? 'video' : ['audio/mpeg', 'audio/wav', 'audio/x-wav', 'audio/mp3'].contains(mime) ? 'audio' : '';
          if (kind.isEmpty) throw const ApiException('请选择 PNG/JPG/WebP 图片、MP4/MOV 视频或 MP3/WAV 音频');
          final model = _selected((ref.read(catalogProvider).asData?.value ?? []).where((model) => model.capability == 'video').toList());
          if (model == null || !videoReferenceSupported(videoProtocol(model), _mode, kind)) throw const ApiException('当前模型或创作方式不支持这种参考素材，请切换方式后添加');
          var width = 0, height = 0, durationMs = 0;
          if (kind == 'image') {
            final codec = await ui.instantiateImageCodec(bytes);
            try { final frame = await codec.getNextFrame(); width = frame.image.width; height = frame.image.height; frame.image.dispose(); }
            finally { codec.dispose(); }
          } else {
            final info = await readMediaInfo(MediaBytes(bytes: bytes, mimeType: mime));
            width = info.width; height = info.height; durationMs = info.durationMs;
          }
          api.assertEpoch(epoch);
          if (!_current(epoch)) return;
          accepted.add(VideoReference(kind: kind, name: file.name, media: MediaBytes(bytes: bytes, mimeType: mime), width: width, height: height, durationMs: durationMs));
        } finally { if (access && bookmark != null) await DesktopDrop.instance.stopAccessingSecurityScopedResource(bookmark: bookmark); }
      }
      if (_current(epoch)) _update(() => _references.addAll(accepted));
    } catch (error) {
      if (mounted && _current(epoch)) { if (accepted.isNotEmpty) _update(() => _references.addAll(accepted)); toast(context, errorMessage(error)); }
    } finally { if (mounted && api.epoch == epoch) setState(() => _reading = false); }
  }

  void _generate(List<ImageModel> models) {
    if (!mounted || ref.read(apiProvider).epoch != _draftEpoch) return;
    if (_busy || ref.read(videoGenerationProvider).work?.status == 'pending') return;
    final model = _selected(models);
    if (model == null || videoProtocol(model).isEmpty) return;
    final protocol = videoProtocol(model);
    final seconds = protocol == 'grok' && _mode == 'edit' ? 6 : int.tryParse(_seconds.text);
    if (seconds == null) { toast(context, '请输入整数视频时长'); return; }
    if (_references.any((item) => !videoReferenceSupported(protocol, _mode, item.kind))) { toast(context, '请移除当前方式不支持的参考素材，或切换模型与创作方式'); return; }
    final ratio = protocol == 'openai' && !['auto', '16:9', '9:16'].contains(_ratio) ? '16:9' : _ratio;
    ref.read(videoGenerationProvider.notifier).generate(VideoConfig(model: model, prompt: _prompt.text.trim(), seconds: seconds, ratio: ratio, resolution: _resolution, mode: _mode, generateAudio: _audio, watermark: _watermark, references: List.of(_references)));
  }

  void _resume(VideoWork work, List<ImageModel> models) {
    if (!mounted || ref.read(apiProvider).epoch != _draftEpoch) return;
    final model = models.where((item) => item.value == work.model).firstOrNull;
    if (model == null) { toast(context, '该作品的渠道或模型已不可用，请先恢复渠道配置'); return; }
    ref.read(videoGenerationProvider.notifier).resume(work, model);
  }

  Future<void> _saveAsset(VideoState state) async {
    if (!mounted || ref.read(apiProvider).epoch != _draftEpoch) return;
    if (_savingAsset || state.media == null || state.work == null) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final work = state.work!, repository = ref.read(repositoryProvider);
    setState(() => _savingAsset = true);
    try {
      final metadata = jsonObject(work.data['video']);
      await repository.addVideoAsset(state.media!, work.title, storageKey: work.fileKey, width: jsonInt(metadata['width']), height: jsonInt(metadata['height']), durationMs: jsonInt(metadata['durationMs']));
      api.assertEpoch(epoch);
      if (mounted && _current(epoch)) { ref.invalidate(assetsProvider); toast(context, '已保存到素材库'); }
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
    finally { if (mounted && api.epoch == epoch) setState(() => _savingAsset = false); }
  }

  Future<void> _export(VideoState state) async {
    if (!mounted || ref.read(apiProvider).epoch != _draftEpoch) return;
    if (state.media == null) return;
    await exportVideo(context, ref, state.media!, state.work?.id ?? 'result');
  }

  Widget _parameters(List<ImageModel> models, VideoState state, {void Function(VoidCallback)? update}) {
    final change = update ?? _update;
    final model = _selected(models), protocol = model == null ? '' : videoProtocol(model);
    final disabled = state.busy || state.saving || _reading;
    final ratios = protocol == 'openai' ? const {'自动': 'auto', '横屏 16:9': '16:9', '竖屏 9:16': '9:16'} : const {'自动': 'auto', '16:9': '16:9', '9:16': '9:16', '1:1': '1:1', '4:3': '4:3', '3:4': '3:4', '21:9': '21:9'};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
      Text('生成参数', style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w600)),
      FSelect<String>.rich(label: const Text('视频模型'), format: (value) => models.where((model) => model.id == value).firstOrNull?.name ?? value, enabled: !disabled, control: FSelectControl.lifted(value: model?.id, onChange: (value) => change(() => _modelId = value)), children: [for (final model in models) FSelectItem(title: Text(model.name), subtitle: Text('${model.providerName} · ${videoProtocolLabel(model)}'), value: model.id)]),
      if (model != null) Text(videoProtocolLabel(model), style: TextStyle(fontSize: 12, color: context.theme.colors.mutedForeground)),
      if (protocol.isEmpty) Text('当前模型使用未接入的自定义协议。请切换模型，生成按钮已禁用。', style: TextStyle(color: context.theme.colors.mutedForeground)),
      if (protocol == 'grok') FSelect<String>(label: const Text('创作方式'), items: const {'生成': 'generate', '剪辑': 'edit', '扩展': 'extend'}, enabled: !disabled, control: FSelectControl.lifted(value: _mode, onChange: (value) => change(() => _mode = value ?? 'generate'))),
      if (protocol.isNotEmpty && !(protocol == 'grok' && _mode == 'edit')) FTextField(control: FTextFieldControl.managed(controller: _seconds), label: const Text('时长（秒）'), hint: protocol == 'seedance' ? '4–15，或 -1 自动' : '1–20', enabled: !disabled, keyboardType: const TextInputType.numberWithOptions(signed: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-\d]'))]),
      if (protocol == 'grok' && _mode == 'edit') Text('剪辑时长由参考视频确定。', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
      if (protocol.isNotEmpty && protocol != 'grok') ...[
        FSelect<String>(label: const Text('画幅'), items: ratios, enabled: !disabled && protocol.isNotEmpty, control: FSelectControl.lifted(value: ratios.values.contains(_ratio) ? _ratio : '16:9', onChange: (value) => change(() => _ratio = value ?? 'auto'))),
        FSelect<String>(label: const Text('清晰度'), items: const {'自动': 'auto', '480p': '480p', '720p': '720p', '1080p': '1080p'}, enabled: !disabled && protocol.isNotEmpty, control: FSelectControl.lifted(value: _resolution, onChange: (value) => change(() => _resolution = value ?? 'auto'))),
      ] else if (protocol == 'grok') Text('Grok 画幅与清晰度由上游确定。', style: TextStyle(fontSize: 12, color: context.theme.colors.mutedForeground)),
      if (protocol == 'seedance') FAccordion(children: [FAccordionItem(title: const Text('高级设置'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        FSelect<String>(label: const Text('生成音频'), items: const {'开启': 'true', '关闭': 'false'}, enabled: !disabled, control: FSelectControl.lifted(value: '$_audio', onChange: (value) => change(() => _audio = value == 'true'))),
        FSelect<String>(label: const Text('水印'), items: const {'关闭': 'false', '开启': 'true'}, enabled: !disabled, control: FSelectControl.lifted(value: '$_watermark', onChange: (value) => change(() => _watermark = value == 'true'))),
      ]))]),
    ]);
  }

  void _showParameters(List<ImageModel> models) {
    final epoch = ref.read(apiProvider).epoch;
    showFSheet<void>(context: context, side: FLayout.btt, useSafeArea: true, mainAxisMaxRatio: .85, builder: (sheetContext) => Consumer(builder: (context, ref, _) {
      ref.listen(sessionProvider, (_, next) { if (ref.read(apiProvider).epoch != epoch) Navigator.maybePop(sheetContext); });
      return StatefulBuilder(builder: (_, sheetSetState) => SingleChildScrollView(padding: const EdgeInsets.all(24), child: _parameters(models, ref.watch(videoGenerationProvider), update: (action) { if (mounted) { _update(action); sheetSetState(() {}); } })));
    }));
  }

  Widget _editor(List<ImageModel> models, VideoState state) {
    final protocol = _selected(models) == null ? '' : videoProtocol(_selected(models)!);
    final referenceArea = AnimatedContainer(duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.fast, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _dragging ? context.theme.colors.secondary : context.theme.colors.muted.withValues(alpha: .4), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: _dragging ? context.theme.colors.primary : context.theme.colors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
      Row(children: [Expanded(child: Text(_reading ? '正在读取参考素材…' : AppLayout.isDesktop ? '拖入参考素材，或选择文件' : '参考素材', style: TextStyle(color: context.theme.colors.mutedForeground, fontSize: 12))), if (_reading) const SizedBox(width: 16, height: 16, child: FCircularProgress())]),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (videoReferenceSupported(protocol, _mode, 'image')) FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.imagePlus, size: 15), onPress: _busy ? null : () => _pick('image'), child: const Text('图片')),
        if (videoReferenceSupported(protocol, _mode, 'video')) FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.video, size: 15), onPress: _busy ? null : () => _pick('video'), child: const Text('视频')),
        if (videoReferenceSupported(protocol, _mode, 'audio')) FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.audioLines, size: 15), onPress: _busy ? null : () => _pick('audio'), child: const Text('音频')),
      ]),
      for (var i = 0; i < _references.length; i++) Row(spacing: 10, children: [
        SizedBox(width: 44, height: 44, child: _references[i].kind == 'image' ? ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm), child: Image.memory(_references[i].media.bytes, fit: BoxFit.cover, cacheWidth: (44 * MediaQuery.devicePixelRatioOf(context)).ceil())) : Icon(_references[i].kind == 'video' ? FLucideIcons.video : FLucideIcons.audioLines, color: context.theme.colors.mutedForeground)),
        Expanded(child: Text(_references[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
        if (_references[i].durationMs > 0) Text('${(_references[i].durationMs / 1000).toStringAsFixed(1)}s', style: const TextStyle(fontSize: 11)),
        if (!videoReferenceSupported(protocol, _mode, _references[i].kind)) Icon(FLucideIcons.circleAlert, size: 15, color: context.theme.colors.error),
        FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.xs, semanticsLabel: '移除参考素材', onPress: _busy ? null : () => _update(() => _references.removeAt(i)), child: const Icon(FLucideIcons.x, size: 14)),
      ]),
    ]));
    return FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
      Row(children: [const Icon(FLucideIcons.clapperboard, size: 18), const SizedBox(width: 8), const Expanded(child: Text('描述你的镜头', style: TextStyle(fontWeight: FontWeight.w600))), if (!AppLayout.isDesktop) FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '生成参数', onPress: () => _showParameters(models), child: const Icon(FLucideIcons.slidersHorizontal, size: 18))]),
      FTextField(control: FTextFieldControl.managed(controller: _prompt), hint: '镜头从晨雾中的森林缓缓推进，阳光穿过枝叶…\n描述主体、动作、镜头与氛围。', minLines: 4, maxLines: 6, enabled: !_busy, textInputAction: TextInputAction.newline),
      if (AppLayout.isDesktop) DropTarget(enable: !_busy && protocol.isNotEmpty && ModalRoute.of(context)?.isCurrent == true, onDragEntered: (_) => setState(() => _dragging = true), onDragExited: (_) => setState(() => _dragging = false), onDragDone: (details) => _readFiles(details.files), child: referenceArea) else referenceArea,
      if (_references.any((item) => !videoReferenceSupported(protocol, _mode, item.kind))) FAlert(title: const Text('参考素材需要调整'), subtitle: const Text('草稿中的部分素材不适用于当前模型或创作方式。请移除标记的素材，或切换回原方式。')),
    ]));
  }

  Widget _preview(VideoState state, List<ImageModel> models) => FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
    Row(children: [const Expanded(child: Text('视频预览', style: TextStyle(fontWeight: FontWeight.w600))), FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _busy ? null : () { ref.read(videoGenerationProvider.notifier).newDraft(); _update(() { _prompt.clear(); _references.clear(); }); }, prefix: const Icon(FLucideIcons.plus, size: 15), child: const Text('新建创作'))]),
    if (state.media != null) VideoPreview(media: state.media!)
    else ConstrainedBox(constraints: BoxConstraints(minHeight: AppLayout.isDesktop ? 280 : 210), child: StatePanel(title: state.busy ? '上游正在处理视频' : '等待你的第一个镜头', description: state.busy ? '实际时长由上游决定，任务可在记录中恢复。' : '完成生成后，视频会显示在这里。', icon: FLucideIcons.clapperboard, loading: state.busy)),
    if (state.error.isNotEmpty) Text(state.error, style: TextStyle(color: context.theme.colors.error, fontSize: 13)),
    if (state.runId.isNotEmpty) Text('任务 ${state.runId}', style: TextStyle(color: context.theme.colors.mutedForeground, fontSize: 11)),
    Wrap(spacing: 8, runSpacing: 8, children: [
      if (state.media != null) ...[
        FButton(variant: FButtonVariant.secondary, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.download, size: 15), onPress: state.saving ? null : () => _export(state), child: const Text('导出视频')),
        FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.folderPlus, size: 15), onPress: _savingAsset || state.saving ? null : () => _saveAsset(state), child: Text(_savingAsset ? '保存中' : '存入素材库')),
        if (state.work?.status != 'success') FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: state.saving ? null : () => ref.read(videoGenerationProvider.notifier).saveResult(), child: const Text('重试保存')),
      ] else if (state.work != null && !_busy) FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.refreshCw, size: 15), onPress: () => _resume(state.work!, models), child: const Text('继续查询')),
      FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => context.go('/works'), child: const Text('任务记录')),
    ]),
  ]));

  Widget _operation(List<ImageModel> models, VideoState state) {
    final model = _selected(models), protocol = model == null ? '' : videoProtocol(model);
    final pending = state.work?.status == 'pending';
    final incompatible = _references.any((item) => !videoReferenceSupported(protocol, _mode, item.kind));
    return FCard(key: const ValueKey('video-operation'), builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Text('1 段视频${model == null ? '' : model.providerId.startsWith('local:') ? ' · 个人渠道计费' : ' · ${model.creditCost} 算力'}', style: context.theme.typography.body.sm),
      Text(pending && !_busy ? '当前任务待核对，可继续查询或新建创作。' : '以服务端确认结果为准', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
      FButton(prefix: _busy ? const FCircularProgress() : const Icon(FLucideIcons.sparkles, size: 17), onPress: _busy || protocol.isEmpty || pending || incompatible ? null : () => _generate(models), child: Text(state.saving ? '保存作品中' : state.busy ? '视频生成中' : '生成视频')),
    ]));
  }

  Widget _history(List<ImageModel> models) => FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
    Row(children: [const Expanded(child: Text('最近视频', style: TextStyle(fontWeight: FontWeight.w600))), FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '刷新视频记录', onPress: () => ref.invalidate(videoWorksProvider), child: const Icon(FLucideIcons.refreshCw, size: 15))]),
    ref.watch(videoWorksProvider).when(
      loading: () => const StatePanel(title: '正在读取记录', loading: true),
      error: (error, _) => StatePanel(title: '记录读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(videoWorksProvider), child: const Text('重试'))),
      data: (works) => works.isEmpty ? const StatePanel(title: '还没有视频作品', description: '生成记录会保存在你的账号中。', icon: FLucideIcons.video) : Column(spacing: 8, children: [
        for (final work in works) FButton.raw(variant: FButtonVariant.ghost, onPress: _busy ? null : () => work.status == 'success' ? context.push('/video/work', extra: work) : _resume(work, models), child: Padding(padding: const EdgeInsets.all(10), child: Row(spacing: 10, children: [
          Icon(work.status == 'success' ? FLucideIcons.play : work.status == 'failed' ? FLucideIcons.circleAlert : FLucideIcons.clock3, size: 17, color: context.theme.colors.mutedForeground),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            Text(work.status == 'success' ? '已保存' : work.status == 'failed' ? '上游已确认失败' : '待核对', style: TextStyle(fontSize: 11, color: context.theme.colors.mutedForeground)),
          ])),
        ]))),
      ]),
    ),
  ]));

  @override
  Widget build(BuildContext context) {
    ref.watch(videoDraftProvider);
    final catalog = ref.watch(catalogProvider), state = ref.watch(videoGenerationProvider);
    final issues = ref.watch(catalogIssuesProvider);
    return catalog.when(
      loading: () => const StatePanel(title: '正在读取视频模型', loading: true),
      error: (error, _) => StatePanel(title: '视频模型读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => refreshCatalog(ref), child: const Text('重试'))),
      data: (catalog) {
        final models = catalog.where((model) => model.capability == 'video').toList();
        if (models.isEmpty) return StatePanel(title: issues.isEmpty ? '暂时没有可用视频模型' : '视频模型目录尚未完整读取', description: issues.isEmpty ? '开启平台视频模型，或在渠道设置中添加个人视频模型。' : issues.entries.map((entry) => '${entry.key}：${entry.value}').join('\n'), icon: FLucideIcons.video, action: FButton(mainAxisSize: MainAxisSize.min, onPress: issues.isEmpty ? () => context.go('/channels') : () => refreshCatalog(ref), child: Text(issues.isEmpty ? '配置渠道' : '重试目录')));
        return CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => _generate(models), const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _generate(models)}, child: LayoutBuilder(builder: (context, bounds) {
          final desktop = AppLayout.isDesktop;
          final width = desktop && bounds.maxWidth < 920 ? 920.0 : bounds.maxWidth;
          final content = SingleChildScrollView(padding: EdgeInsets.all(desktop ? 28 : 20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 7, children: [Text('AI 视频', style: context.theme.typography.display.xl2), Text('从一个想法，走进下一个镜头。', style: TextStyle(color: context.theme.colors.mutedForeground))]),
            if (issues.isNotEmpty) ...[for (final entry in issues.entries) FAlert(title: Text('${entry.key}暂时无法读取'), subtitle: Text(entry.value)), FButton(mainAxisSize: MainAxisSize.min, variant: FButtonVariant.ghost, onPress: () => refreshCatalog(ref), child: const Text('重试目录'))],
            _editor(models, state), _preview(state, models), if (!desktop || width < 1200) _history(models),
          ]));
          if (!desktop) return Column(children: [Expanded(child: content), SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: _operation(models, state)))]);
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: width, height: bounds.maxHeight, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: content),
            SizedBox(width: 300, child: Padding(padding: const EdgeInsets.fromLTRB(0, 28, 24, 24), child: Column(spacing: 16, children: [Expanded(child: SingleChildScrollView(child: FCard(builder: cardBody, child: _parameters(models, state)))), _operation(models, state)]))),
            if (width >= 1200) SizedBox(width: 230, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 28, 20, 24), child: _history(models))),
          ])));
        }));
      },
    );
  }
}
