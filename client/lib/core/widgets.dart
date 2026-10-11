import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import 'providers.dart';
import 'theme.dart';

Widget cardBody(BuildContext context, FCardStyle style, Widget? child) => Padding(padding: style.padding, child: child);

class StatePanel extends StatelessWidget {
  const StatePanel({required this.title, this.description = '', this.icon = FLucideIcons.images, this.action, this.loading = false, super.key});
  final String title, description;
  final IconData icon;
  final Widget? action;
  final bool loading;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (loading) const FCircularProgress() else Icon(icon, size: 36, color: context.theme.colors.mutedForeground),
      const SizedBox(height: 20),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      if (description.isNotEmpty) ...[const SizedBox(height: 8), Text(description, textAlign: TextAlign.center, style: TextStyle(color: context.theme.colors.mutedForeground, height: 1.7))],
      if (action != null) ...[const SizedBox(height: 20), action!],
    ]),
  )).animate(effects: MediaQuery.disableAnimationsOf(context) ? const [] : [FadeEffect(duration: AppMotion.normal), MoveEffect(begin: const Offset(0, 6), end: Offset.zero, duration: AppMotion.normal, curve: AppMotion.curve)]);
}

class AccountGate extends ConsumerWidget {
  const AccountGate({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(sessionProvider).when(
    loading: () => const StatePanel(title: '正在读取账号', loading: true),
    error: (error, _) => StatePanel(title: '账号读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(sessionProvider), child: const Text('重新读取'))),
    data: (user) => user == null ? StatePanel(title: '登录后，开始你的创作', description: '作品与素材随账号同步，在不同设备接续灵感。', action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => context.go('/login'), child: const Text('登录账号'))) : KeyedSubtree(key: ValueKey(user.id), child: child),
  );
}

class ServerImage extends ConsumerWidget {
  const ServerImage(this.source, {this.fit = BoxFit.cover, this.thumbnail, super.key});
  final String source;
  final BoxFit fit;
  final bool? thumbnail;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (source.isEmpty) return Icon(FLucideIcons.image, color: context.theme.colors.mutedForeground);
    return ref.watch(imageProvider(source)).when(
      data: (image) => LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final decodeWidth = (thumbnail ?? fit == BoxFit.cover) && width.isFinite && width > 0
            ? (width * MediaQuery.devicePixelRatioOf(context)).ceil() : null;
        return Image.memory(image.bytes, fit: fit, cacheWidth: decodeWidth, gaplessPlayback: true, errorBuilder: (_, _, _) => const Center(child: Text('图片无法显示')));
      }),
      loading: () => ColoredBox(color: context.theme.colors.muted, child: const Center(child: FCircularProgress())),
      error: (error, _) => Center(child: FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '重新加载图片', onPress: () => ref.invalidate(imageProvider(source)), child: const Icon(FLucideIcons.imageOff))),
    );
  }
}

class ArtworkTile extends ConsumerStatefulWidget {
  const ArtworkTile({required this.artwork, required this.onPress, this.imageOnly = false, super.key});
  final Artwork artwork;
  final VoidCallback onPress;
  final bool imageOnly;
  @override
  ConsumerState<ArtworkTile> createState() => _ArtworkTileState();
}
class _ArtworkTileState extends ConsumerState<ArtworkTile> {
  bool _hovered = false, _focused = false;
  @override
  Widget build(BuildContext context) {
    final work = widget.artwork;
    final parts = work.ratio.split(':');
    final width = double.tryParse(parts.first) ?? 1;
    final height = parts.length == 2 ? double.tryParse(parts.last) ?? 1 : 1;
    final size = work.width > 0 && work.height > 0 ? null : ref.watch(imageSizeProvider(work.imageUrl)).asData?.value;
    final ratio = work.width > 0 && work.height > 0 ? work.width / work.height : size != null ? size.width / size.height : width > 0 && height > 0 ? width / height : 1.0;
    final active = _hovered || _focused;
    final information = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 5, children: [
      Text(work.title.isEmpty ? '无题作品' : work.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: widget.imageOnly ? AppTheme.imageForeground : null)),
      Text(['published', 'community', 'favorite'].contains(work.source) ? work.author : work.model.split(':').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: widget.imageOnly ? AppTheme.imageForeground.withValues(alpha: .75) : context.theme.colors.mutedForeground)),
    ]);
    return FButton.raw(
      variant: FButtonVariant.ghost,
      semanticsLabel: '查看作品：${work.title}',
      onPress: widget.onPress,
      onHoverChange: (value) => setState(() => _hovered = value),
      onFocusChange: (value) => setState(() => _focused = value),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.normal,
        transform: Matrix4.translationValues(0, active ? -3 : 0, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: context.theme.colors.card, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: widget.imageOnly ? AspectRatio(aspectRatio: ratio, child: Stack(fit: StackFit.expand, children: [
          ServerImage(work.imageUrl),
          Positioned(left: 0, right: 0, bottom: 0, child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.fast,
            child: Container(padding: const EdgeInsets.fromLTRB(14, 36, 14, 14), decoration: const BoxDecoration(gradient: AppTheme.imageOverlay), child: information),
          )),
        ])) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: ratio, child: ServerImage(work.imageUrl)),
          Padding(padding: const EdgeInsets.all(12), child: information),
        ]),
      ),
    );
  }
}

void toast(BuildContext context, String message) => showFToast(context: context, title: Text(message));

Future<void> copyText(BuildContext context, WidgetRef ref, String text) async {
  final api = ref.read(apiProvider), epoch = api.epoch;
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted && api.epoch == epoch) toast(context, '已复制');
  } catch (_) { if (context.mounted && api.epoch == epoch) toast(context, '复制失败，请重试'); }
}

Future<void> exportImage(BuildContext context, WidgetRef ref, Artwork work) async {
  final api = ref.read(apiProvider);
  final epoch = api.epoch;
  try {
    final media = await api.file(work.imageUrl);
    api.assertEpoch(epoch);
    final extension = switch (media.mimeType) {'image/jpeg' => 'jpg', 'image/webp' => 'webp', 'image/gif' => 'gif', _ => 'png'};
    final name = 'huabu-${work.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$extension';
    final file = XFile.fromData(media.bytes, mimeType: media.mimeType, name: name);
    if (!context.mounted) return;
    if (Platform.isIOS || Platform.isAndroid) {
      final box = context.findRenderObject() as RenderBox?;
      final result = await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: [name], sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
      api.assertEpoch(epoch);
      if (context.mounted && result.status == ShareResultStatus.success) toast(context, '已分享图片');
    } else {
      final location = await getSaveLocation(suggestedName: name);
      api.assertEpoch(epoch);
      if (location == null || !context.mounted) return;
      await file.saveTo(location.path);
      api.assertEpoch(epoch);
      if (context.mounted) toast(context, '图片已保存');
    }
  } catch (error) { if (context.mounted && api.epoch == epoch) toast(context, errorMessage(error)); }
}

Future<void> exportImages(BuildContext context, WidgetRef ref, List<Artwork> works) async {
  if (works.isEmpty) return;
  final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
  try {
    final directory = Platform.isMacOS || Platform.isWindows ? await getDirectoryPath(confirmButtonText: '保存到此文件夹') : null;
    api.assertEpoch(epoch);
    if ((Platform.isMacOS || Platform.isWindows) && directory == null) return;
    final files = <XFile>[], names = <String>[];
    for (final work in works) {
      api.assertEpoch(epoch);
      final image = await api.file(work.imageUrl);
      api.assertEpoch(epoch);
      final extension = switch (image.mimeType) {'image/jpeg' => 'jpg', 'image/webp' => 'webp', 'image/gif' => 'gif', _ => 'png'};
      final name = 'huabu-${const Uuid().v4()}.$extension';
      final file = XFile.fromData(image.bytes, mimeType: image.mimeType, name: name);
      if (directory != null) { await file.saveTo('$directory${Platform.pathSeparator}$name'); } else { files.add(file); names.add(name); }
    }
    api.assertEpoch(epoch);
    if (!context.mounted) return;
    if (files.isNotEmpty) {
      final box = context.findRenderObject() as RenderBox?;
      final result = await SharePlus.instance.share(ShareParams(files: files, fileNameOverrides: names, sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
      api.assertEpoch(epoch);
      if (context.mounted && result.status == ShareResultStatus.success) toast(context, '已分享 ${works.length} 张图片');
    } else { toast(context, '已保存 ${works.length} 张图片'); }
  } catch (error) { if (context.mounted && api.epoch == epoch) toast(context, errorMessage(error)); }
}

Future<bool> confirmRemoval(BuildContext context, String title) async =>
  await showFDialog<bool>(context: context, builder: (context, style, animation) => FDialog(
    style: style, animation: animation,
    builder: (context, _) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12), const Text('移除素材列表中的条目，已有作品和画布中的文件仍保留。'),
      const SizedBox(height: 24), Row(spacing: 12, mainAxisAlignment: MainAxisAlignment.end, children: [
        FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, false), child: const Text('取消')),
        FButton(variant: FButtonVariant.destructive, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, true), child: const Text('移除')),
      ]),
    ])),
  )) ?? false;
