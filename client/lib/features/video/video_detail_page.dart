import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../channels/channel_providers.dart';
import 'video_actions.dart';
import 'video_preview.dart';
import 'video_repository.dart';

final videoDetailMediaProvider = FutureProvider.autoDispose.family<MediaBytes, VideoWork>((ref, work) async {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
  if (api.accountId.isEmpty || work.url.isEmpty) throw const ApiException('该记录没有已保存的视频文件');
  if (work.fileKey.isNotEmpty) return api.file(work.url);
  final models = await ref.watch(catalogProvider.future);
  api.assertEpoch(epoch);
  if (!ref.mounted) throw const ApiException('操作已取消', canceled: true);
  final model = models.where((model) => model.value == work.model).firstOrNull;
  if (model == null) throw const ApiException('原渠道不可用，无法读取上游媒体');
  final target = await ref.watch(modelApiTargetProvider(model).future);
  api.assertEpoch(epoch);
  if (!ref.mounted) throw const ApiException('操作已取消', canceled: true);
  return target.media(work.url, runId: work.runId);
});

class VideoDetailPage extends ConsumerStatefulWidget {
  const VideoDetailPage({required this.work, super.key});
  final VideoWork work;
  @override
  ConsumerState<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends ConsumerState<VideoDetailPage> {
  late final _owner = ref.read(apiProvider).accountId;
  String _busy = '';

  Future<void> _saveAsset(MediaBytes media) async {
    if (_busy.isNotEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final repository = ref.read(repositoryProvider), work = widget.work, meta = jsonObject(widget.work.data['video']);
    setState(() => _busy = 'asset');
    try {
      await repository.addVideoAsset(media, work.title, storageKey: work.fileKey, width: jsonInt(meta['width']), height: jsonInt(meta['height']), durationMs: jsonInt(meta['durationMs']));
      api.assertEpoch(epoch);
      if (mounted) { ref.invalidate(assetsProvider); toast(context, '已保存到素材库'); }
    } catch (error) { if (mounted && api.epoch == epoch) toast(context, errorMessage(error)); }
    finally { if (mounted && api.epoch == epoch) setState(() => _busy = ''); }
  }

  Future<void> _export(MediaBytes media) async {
    if (_busy.isNotEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() => _busy = 'export');
    await exportVideo(context, ref, media, widget.work.id);
    if (mounted && api.epoch == epoch) setState(() => _busy = '');
  }

  Widget _content() {
    final work = widget.work, media = ref.watch(videoDetailMediaProvider(work)), meta = jsonObject(work.data['video']);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: [
      Text(work.title, style: context.theme.typography.display.xl),
      FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Row(children: [const Expanded(child: Text('视频提示词', style: TextStyle(fontWeight: FontWeight.w600))), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '复制提示词', onPress: () => copyText(context, ref, work.prompt), child: const Icon(FLucideIcons.copy, size: 16))]),
        SelectableText(work.prompt, style: TextStyle(color: context.theme.colors.mutedForeground, height: 1.8)),
      ])),
      FTileGroup(children: [
        FTile(title: const Text('模型'), details: Text(work.model.split('::').last)),
        if (jsonInt(meta['durationMs']) > 0) FTile(title: const Text('实际时长'), details: Text('${(jsonInt(meta['durationMs']) / 1000).toStringAsFixed(1)} 秒')),
        if (jsonInt(meta['width']) > 0 && jsonInt(meta['height']) > 0) FTile(title: const Text('视频尺寸'), details: Text('${meta['width']} × ${meta['height']}')),
        FTile(title: const Text('创建时间'), details: Text(MaterialLocalizations.of(context).formatMediumDate(work.createdAt.toLocal()))),
      ]),
      FButton(prefix: const Icon(FLucideIcons.download, size: 16), onPress: _busy.isNotEmpty || media.asData?.value == null ? null : () => _export(media.asData!.value), child: Text(_busy == 'export' ? '导出中' : '导出视频')),
      FButton(variant: FButtonVariant.outline, prefix: const Icon(FLucideIcons.folderPlus, size: 16), onPress: _busy.isNotEmpty || media.asData?.value == null ? null : () => _saveAsset(media.asData!.value), child: Text(_busy == 'asset' ? '保存中' : '保存素材')),
    ]);
    final preview = media.when(data: (media) => VideoPreview(media: media), loading: () => const StatePanel(title: '正在读取视频', loading: true), error: (error, _) => StatePanel(title: '视频读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(videoDetailMediaProvider(work)), child: const Text('重新读取'))));
    return LayoutBuilder(builder: (context, bounds) {
      final desktop = AppLayout.isDesktop;
      final width = desktop && bounds.maxWidth < 900 ? 900.0 : bounds.maxWidth;
      final content = SingleChildScrollView(padding: const EdgeInsets.all(28), child: desktop
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 28, children: [Expanded(child: preview), SizedBox(width: width < 1000 ? 280 : 360, child: info)])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [preview, info]));
      return desktop ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: width, height: bounds.maxHeight, child: content)) : content;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(sessionProvider).asData?.value?.id;
    return FScaffold(childPad: false, header: FHeader.nested(title: const Text('视频详情'), prefixes: [FHeaderAction.back(onPress: () => context.canPop() ? context.pop() : context.go('/works'))]), child: account != _owner || _owner.isEmpty
      ? StatePanel(title: '请在所属账号查看作品', description: '账号已切换，请重新打开当前账号的作品。', action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => context.go('/works'), child: const Text('查看我的作品')))
      : _content());
  }
}
