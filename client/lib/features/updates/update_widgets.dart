import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'client_updates.dart';

const _platformNames = {'macos': 'macOS', 'windows': 'Windows', 'android': 'Android', 'ios': 'iOS'};

void _checkRelease(WidgetRef ref) {
  ref.invalidate(packageInfoProvider);
  ref.invalidate(clientReleaseProvider);
  if (ref.read(nativeUpdateReadyProvider).hasError) ref.invalidate(nativeUpdateReadyProvider);
}

Future<void> _openUpdatePage(BuildContext context, String address) async {
  try { await openReleaseDownload(releaseUri(address)); }
  catch (_) { if (context.mounted) toast(context, '页面未能打开，请检查地址或网络后重试'); }
}

Future<void> showSoftwareUpdates(BuildContext context) => showFDialog<void>(
  context: context,
  builder: (context, style, animation) => FDialog(
    style: style, animation: animation, constraints: const BoxConstraints(minWidth: 280, maxWidth: 600),
    builder: (context, _) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: SingleChildScrollView(child: Consumer(builder: (context, ref, _) => _updateDetails(context, ref, onClose: () => Navigator.of(context).pop()))),
    )),
  ),
);

class SoftwareUpdateButton extends ConsumerWidget {
  const SoftwareUpdateButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(clientReleaseProvider), installed = ref.watch(packageInfoProvider);
    final release = latest.asData?.value, info = installed.asData?.value;
    final newer = release != null && info != null && release.newerThan(info);
    final version = release == null ? '' : '${release.version} · ${release.buildNumber}';
    final label = newer ? '版本更新啦 · $version' : latest.isLoading ? '正在检查软件更新' : latest.hasError || installed.hasError ? '更新检查失败，点击重新检查' : '检查更新与下载';
    return FTooltip(tipBuilder: (_, _) => Text(label), child: Stack(clipBehavior: Clip.none, children: [
      FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: label, onPress: () { _checkRelease(ref); showSoftwareUpdates(context); }, child: latest.isLoading ? const SizedBox(width: 16, height: 16, child: FCircularProgress()) : const Icon(FLucideIcons.download, size: 17)),
      if (newer) Positioned(top: 4, right: 3, child: IgnorePointer(child: Container(key: const ValueKey('software-update-dot'), width: 8, height: 8, decoration: BoxDecoration(color: context.theme.colors.destructive, shape: BoxShape.circle, border: Border.all(color: context.theme.colors.background))))),
    ]));
  }
}

class ReleaseDownloads extends ConsumerWidget {
  const ReleaseDownloads({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(clientReleaseProvider).when(
    loading: () => const FAlert(title: Text('正在读取软件下载地址'), icon: FCircularProgress()),
    error: (_, _) => FAlert(variant: FAlertVariant.destructive, title: const Text('软件下载信息读取失败'), subtitle: FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(clientReleaseProvider), child: const Text('重新读取'))),
    data: (release) => FCard(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
      Text('下载 AI Studio', style: context.theme.typography.display.md),
      if (release == null || release.downloads.isEmpty) const Text('正式安装包尚未发布。发布后，这里会显示各平台的真实下载入口。')
      else ...[
        Text('版本 ${release.version} · ${release.buildNumber}', style: context.theme.typography.body.sm),
        Wrap(spacing: 10, runSpacing: 10, children: [for (final item in release.downloads.entries) FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.download, size: 16), onPress: () async {
          try { await openReleaseDownload(item.value); } catch (_) { if (context.mounted) toast(context, '下载页面未能打开，请重试'); }
        }, child: Text(_platformNames[item.key]!))]),
      ],
    ]))),
  );
}

class SoftwareUpdateCard extends ConsumerWidget {
  const SoftwareUpdateCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FCard(builder: cardBody, child: _updateDetails(context, ref));
}

Widget _updateDetails(BuildContext context, WidgetRef ref, {VoidCallback? onClose}) {
  final installed = ref.watch(packageInfoProvider), latest = ref.watch(clientReleaseProvider);
  final native = ref.watch(nativeUpdateProvider), theme = context.theme;
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [
    Row(spacing: AppSpace.sm, children: [
      Icon(FLucideIcons.download, size: 19, color: theme.colors.primary),
      Expanded(child: Text('软件更新', style: theme.typography.display.md)),
      FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '检查软件更新', semanticsTooltip: '检查软件更新', onPress: latest.isLoading ? null : () => _checkRelease(ref), child: const Icon(FLucideIcons.refreshCw, size: 16)),
      if (onClose != null) FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '关闭软件更新', onPress: onClose, child: const Icon(FLucideIcons.x, size: 16)),
    ]),
    installed.when(data: (info) => Text('当前版本 ${info.version} · ${info.buildNumber}', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)), loading: () => const FCircularProgress(), error: (_, _) => const FAlert(variant: FAlertVariant.destructive, title: Text('当前版本读取失败，请重新检查'))),
    latest.when(
      skipLoadingOnRefresh: false,
      loading: () => const Row(spacing: AppSpace.sm, children: [FCircularProgress(), Expanded(child: Text('正在检查更新…'))]),
      error: (_, _) => const FAlert(variant: FAlertVariant.destructive, title: Text('更新信息读取失败'), subtitle: Text('请检查网络后重试，尚未确认最新版本。')),
      data: (release) => release == null ? const Text('正式更新渠道尚未配置。') : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [
        installed.when(
          data: (info) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
            Text(release.newerThan(info) ? '发现新版本 ${release.version} · ${release.buildNumber}' : '当前版本已是该发布渠道的最新版本', style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600)),
            if (release.newerThan(info)) _UpdateAction(release: release)
            else if (release.downloads[clientPlatform] case final download?) FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.download, size: 16), onPress: () => _openUpdatePage(context, download.toString()), child: const Flexible(child: Text('下载安装包')))
            else const Text('此平台的安装包尚未发布'),
          ]), loading: () => const SizedBox.shrink(), error: (_, _) => const SizedBox.shrink(),
        ),
        const FDivider(),
        Text('更新日志 · ${release.version}', style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600)),
        if (release.notes.trim().isEmpty) Text('此版本暂未提供更新日志。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))
        else MarkdownBody(data: release.notes, selectable: true,
          styleSheet: MarkdownStyleSheet(p: theme.typography.body.sm.copyWith(height: 1.7), a: theme.typography.body.sm.copyWith(color: theme.colors.primary), h1: theme.typography.display.lg, h2: theme.typography.display.md, h3: theme.typography.display.sm, listBullet: theme.typography.body.sm),
          imageBuilder: (_, _, alt) => Text(alt ?? '更新日志图片'),
          onTapLink: (_, href, _) { if (href != null) _openUpdatePage(context, href); },
        ),
      ]),
    ),
    if (native.message.isNotEmpty) FAlert(variant: native.error ? FAlertVariant.destructive : FAlertVariant.primary, title: Text(native.message)),
    FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, prefix: const Icon(FLucideIcons.externalLink, size: 15), onPress: () => _openUpdatePage(context, releaseHistoryUrl), child: const Flexible(child: Text('查看历史更新日志'))),
  ]);
}

class UpdateNotice extends ConsumerStatefulWidget {
  const UpdateNotice({super.key});
  @override
  ConsumerState<UpdateNotice> createState() => _UpdateNoticeState();
}
class _UpdateNoticeState extends ConsumerState<UpdateNotice> {
  String? _dismissed;
  @override
  Widget build(BuildContext context) {
    final release = ref.watch(clientReleaseProvider).asData?.value;
    final info = ref.watch(packageInfoProvider).asData?.value;
    if (release == null || info == null || !release.newerThan(info) || _dismissed == '${release.version}+${release.buildNumber}') return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 0), child: FAlert(
      icon: const Icon(FLucideIcons.download), title: Text('AI Studio ${release.version} 已发布'),
      subtitle: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _UpdateAction(release: release), FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () => showSoftwareUpdates(context), child: const Text('查看更新日志')), FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () => setState(() => _dismissed = '${release.version}+${release.buildNumber}'), child: const Text('稍后提醒')),
      ]),
    ));
  }
}

class _UpdateAction extends ConsumerWidget {
  const _UpdateAction({required this.release});
  final ClientRelease release;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = release.appcasts[clientPlatform], download = release.downloads[clientPlatform];
    final ready = ref.watch(nativeUpdateReadyProvider), busy = ref.watch(nativeUpdateProvider).busy;
    if (feed != null && ready.isLoading) return const Row(mainAxisSize: MainAxisSize.min, spacing: AppSpace.sm, children: [SizedBox(width: 16, height: 16, child: FCircularProgress()), Flexible(child: Text('正在确认更新方式…'))]);
    if (feed != null && ready.asData?.value == true) return FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, prefix: busy ? const SizedBox(width: 14, height: 14, child: FCircularProgress()) : const Icon(FLucideIcons.download, size: 15), onPress: busy ? null : () => ref.read(nativeUpdateProvider.notifier).start(feed), child: Flexible(child: Text(busy ? '正在打开更新…' : '更新并安装')));
    if (download == null) return const Text('此平台的安装包尚未发布');
    final button = FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () async {
      try { await openReleaseDownload(download); } catch (_) { if (context.mounted) toast(context, '更新下载页面未能打开，请重试'); }
    }, child: Flexible(child: Text(clientPlatform == 'ios' ? '前往安装渠道更新' : '下载新版本')));
    if (!['macos', 'windows'].contains(clientPlatform)) return button;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
      Text(ready.hasError ? '更新签名读取失败，可先下载安装包。' : '当前安装包未提供自动更新配置，请下载后安装。', style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
      button,
    ]);
  }
}
