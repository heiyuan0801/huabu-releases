import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets.dart';
import 'client_updates.dart';

const _platformNames = {'macos': 'macOS', 'windows': 'Windows', 'android': 'Android', 'ios': 'iOS'};

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
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(packageInfoProvider), latest = ref.watch(clientReleaseProvider);
    final native = ref.watch(nativeUpdateProvider);
    return FCard(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
      Row(spacing: 10, children: [Icon(FLucideIcons.download, size: 19, color: context.theme.colors.primary), Text('软件更新', style: context.theme.typography.display.md), const Spacer(), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '检查软件更新', onPress: latest.isLoading ? null : () { ref.invalidate(packageInfoProvider); ref.invalidate(clientReleaseProvider); }, child: const Icon(FLucideIcons.refreshCw, size: 16))]),
      installed.when(data: (info) => Text('当前版本 ${info.version} · ${info.buildNumber}'), loading: () => const FCircularProgress(), error: (_, _) => const Text('当前版本读取失败，请重新检查')),
      latest.when(
        loading: () => const Row(spacing: 10, children: [FCircularProgress(), Text('正在检查更新…')]),
        error: (_, _) => const FAlert(variant: FAlertVariant.destructive, title: Text('更新信息读取失败'), subtitle: Text('请检查网络后重试，尚未确认最新版本。')),
        data: (release) => release == null ? const Text('正式更新渠道尚未配置。') : installed.when(
          data: (info) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Text(release.newerThan(info) ? '发现新版本 ${release.version} · ${release.buildNumber}' : '当前版本已是该发布渠道的最新版本'),
            if (release.notes.isNotEmpty) Text(release.notes, style: context.theme.typography.body.sm),
            if (release.newerThan(info)) _UpdateAction(release: release),
          ]), loading: () => const SizedBox.shrink(), error: (_, _) => const SizedBox.shrink(),
        ),
      ),
      if (native.message.isNotEmpty) FAlert(variant: native.error ? FAlertVariant.destructive : FAlertVariant.primary, title: Text(native.message)),
    ])));
  }
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
        _UpdateAction(release: release), FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () => setState(() => _dismissed = '${release.version}+${release.buildNumber}'), child: const Text('稍后提醒')),
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
    final ready = ref.watch(nativeUpdateReadyProvider).asData?.value == true;
    if (feed != null && ready) return FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () => ref.read(nativeUpdateProvider.notifier).start(feed), child: const Text('更新并安装'));
    if (download == null) return const Text('此平台的安装包尚未发布');
    return FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () async {
      try { await openReleaseDownload(download); } catch (_) { if (context.mounted) toast(context, '更新下载页面未能打开，请重试'); }
    }, child: Text(clientPlatform == 'ios' ? '前往安装渠道更新' : '下载新版本'));
  }
}
