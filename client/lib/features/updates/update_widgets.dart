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

Future<void> showSoftwareUpdates(BuildContext context) {
  final theme = AppTheme.softwareUpdates(context.theme);
  return showFDialog<void>(context: context, useSafeArea: true, style: theme.dialogStyle,
    builder: (context, style, animation) => FTheme(data: theme, child: FDialog(
      style: style, animation: animation, semanticsLabel: '软件更新', constraints: const BoxConstraints(maxWidth: 860),
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(child: _UpdateDetails(onClose: () => Navigator.of(context).pop())),
      ),
    )),
  );
}

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

class SoftwareUpdateCard extends StatelessWidget {
  const SoftwareUpdateCard({super.key});
  @override
  Widget build(BuildContext context) => FTheme(data: AppTheme.softwareUpdates(context.theme), child: FCard(child: const _UpdateDetails()));
}

class _UpdateDetails extends ConsumerWidget {
  const _UpdateDetails({this.onClose});
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(packageInfoProvider), latest = ref.watch(clientReleaseProvider);
    final release = latest.asData?.value, info = installed.asData?.value;
    final update = ref.watch(nativeUpdateProvider), theme = context.theme;
    final native = update.feed == release?.appcasts[clientPlatform] ? update : const NativeUpdateState();
    final newer = release != null && info != null && release.newerThan(info);
    final checking = latest.isLoading || installed.isLoading;
    final title = checking ? '正在检查更新…' : switch (native.stage) {
      NativeUpdateStage.opening => '正在打开更新…', NativeUpdateStage.checking => '正在检查更新…',
      NativeUpdateStage.downloaded => '更新包已下载', NativeUpdateStage.beforeQuit => '准备安装更新',
      NativeUpdateStage.error => '更新暂未完成', NativeUpdateStage.noUpdate => '未发现适用更新',
      _ => latest.hasError ? '暂时无法检查更新' : installed.hasError ? '版本状态待确认' : newer ? '发现新版本' : release == null ? '暂无可用更新渠道' : '已是最新版本',
    };
    final description = newer ? '新版本已发布，查看本次更新内容，让创作体验更进一步。'
      : !checking && !latest.hasError && !installed.hasError && release != null ? '当前版本已是该发布渠道的最新版本' : '保持软件更新，继续享受流畅、稳定的创作体验。';
    return LayoutBuilder(builder: (context, constraints) {
      final wide = AppLayout.isDesktop && constraints.maxWidth >= 640;
      final padding = wide ? AppSpace.xl : AppSpace.lg;
      final horizontalActions = constraints.maxWidth - padding * 2 >= 300 && MediaQuery.textScalerOf(context).scale(16) <= 20;
      final download = release?.downloads[clientPlatform];
      final action = release == null || info == null ? const SizedBox.shrink() : newer ? _UpdateAction(release: release, fullWidth: true)
        : download == null ? const Text('此平台的安装包尚未发布') : FButton(variant: FButtonVariant.outline, size: FButtonSizeVariant.lg,
          prefix: const Icon(FLucideIcons.download, size: 16), onPress: () => _openUpdatePage(context, download.toString()), child: const Flexible(child: Text('下载安装包')));
      final version = Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (info != null) Text('当前版本 ${info.version} · ${info.buildNumber}', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
        if (release != null && info != null) Icon(FLucideIcons.arrowRight, size: 16, color: theme.colors.mutedForeground),
        if (release != null) Text('最新版本 ${release.version} · ${release.buildNumber}', style: theme.typography.body.sm.copyWith(color: theme.colors.primary)),
      ]);
      final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
        Semantics(header: true, child: Text(title, style: theme.typography.display.xl2.copyWith(fontSize: wide ? AppTheme.updateDesktopTitleSize : AppTheme.updateMobileTitleSize, letterSpacing: -.5))), version,
      ]);
      return Padding(padding: EdgeInsets.all(padding), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
        Row(spacing: AppSpace.sm, children: [
          const Icon(FLucideIcons.download, size: 18, color: AppTheme.updateBlue),
          Expanded(child: Text('软件更新', style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600))),
          FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '检查软件更新', semanticsTooltip: '检查软件更新', onPress: checking || update.busy ? null : () => _checkRelease(ref), child: const Icon(FLucideIcons.refreshCw, size: 17)),
          if (onClose != null) FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '关闭软件更新', onPress: onClose, child: const Icon(FLucideIcons.x, size: 19)),
        ]),
        if (wide) Row(spacing: AppSpace.xl, children: [const _UpdateArtwork(size: 104), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [heading, Text(description, style: theme.typography.body.md.copyWith(color: theme.colors.mutedForeground))]))])
        else ...[
          if (constraints.maxWidth - padding * 2 >= 320 && MediaQuery.textScalerOf(context).scale(16) <= 20)
            Row(spacing: AppSpace.lg, crossAxisAlignment: CrossAxisAlignment.start, children: [const _UpdateArtwork(size: 64), Expanded(child: heading)])
          else Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [const _UpdateArtwork(size: 64), heading]),
          Text(description, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground, height: 1.7)),
        ],
        if (checking || native.message.isNotEmpty) _UpdateProgress(checking: checking, native: native),
        if (installed.hasError) const FAlert(variant: FAlertVariant.destructive, title: Text('当前版本读取失败，请重新检查')),
        latest.when(skipLoadingOnRefresh: false,
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const FAlert(variant: FAlertVariant.destructive, title: Text('更新信息读取失败'), subtitle: Text('请检查网络后重试，尚未确认最新版本。')),
          data: (release) => release == null ? const Text('正式更新渠道尚未配置。') : Container(
            padding: EdgeInsets.all(wide ? AppSpace.xl : AppSpace.lg),
            decoration: BoxDecoration(color: theme.colors.secondary, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [
              Row(spacing: AppSpace.md, children: [
                Container(padding: const EdgeInsets.all(AppSpace.sm), decoration: BoxDecoration(gradient: AppTheme.updateGradient, borderRadius: BorderRadius.circular(AppRadius.sm)), child: const Icon(FLucideIcons.fileText, size: 18, color: AppTheme.imageForeground)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.xs, children: [
                  Text('更新内容', style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600)),
                  Text('更新日志 · ${release.version}', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
                ])),
              ]),
              if (release.notes.trim().isEmpty) Text('此版本暂未提供更新日志。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))
              else ConstrainedBox(constraints: BoxConstraints(maxHeight: wide ? 160 : 128), child: SingleChildScrollView(primary: false, child: MarkdownBody(data: release.notes, selectable: true,
                styleSheet: MarkdownStyleSheet(p: theme.typography.body.sm.copyWith(height: 1.8), a: theme.typography.body.sm.copyWith(color: theme.colors.primary), h1: theme.typography.display.md, h2: theme.typography.display.sm, h3: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600), listBullet: theme.typography.body.sm.copyWith(color: theme.colors.primary),
                  code: theme.typography.body.sm.copyWith(fontFamily: 'monospace', color: theme.colors.foreground, backgroundColor: theme.colors.muted), codeblockDecoration: BoxDecoration(color: theme.colors.muted, borderRadius: BorderRadius.circular(AppRadius.sm))),
                imageBuilder: (_, _, alt) => Text(alt ?? '更新日志图片'),
                onTapLink: (_, href, _) { if (href != null) _openUpdatePage(context, href); },
              ))),
            ]),
          ),
        ),
        if (release != null && info != null) ...[
          if (onClose != null) Flex(direction: horizontalActions ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: horizontalActions ? CrossAxisAlignment.end : CrossAxisAlignment.stretch, spacing: AppSpace.md, children: [
              if (horizontalActions) ...[
                Expanded(child: FButton(variant: FButtonVariant.secondary, size: FButtonSizeVariant.lg, onPress: onClose, child: Text(newer ? '稍后更新' : '关闭'))),
                Expanded(child: action),
              ] else ...[
                action,
                FButton(variant: FButtonVariant.secondary, size: FButtonSizeVariant.lg, onPress: onClose, child: Text(newer ? '稍后更新' : '关闭')),
              ],
            ])
          else action,
        ],
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.md, runSpacing: AppSpace.sm, children: [
          Text(AppLayout.isDesktop ? '下载与安装将在系统更新窗口中确认' : '安装需系统确认', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
          FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, prefix: const Icon(FLucideIcons.externalLink, size: 14), onPress: () => _openUpdatePage(context, releaseHistoryUrl), child: const Flexible(child: Text('查看历史更新日志'))),
        ]),
      ]));
    });
  }
}

class _UpdateArtwork extends StatelessWidget {
  const _UpdateArtwork({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: SizedBox.square(dimension: size, child: Stack(alignment: Alignment.center, children: [
    Container(decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.blue.withValues(alpha: .08))),
    Transform.translate(offset: Offset(-size * .13, -size * .05), child: Transform.rotate(angle: -.16, child: Container(width: size * .66, height: size * .72, decoration: BoxDecoration(color: AppTheme.blue.withValues(alpha: .15), borderRadius: BorderRadius.circular(size * .17))))),
    Container(width: size * .72, height: size * .72, decoration: BoxDecoration(gradient: AppTheme.updateGradient, borderRadius: BorderRadius.circular(size * .19), border: Border.all(color: AppTheme.imageForeground.withValues(alpha: .35)), boxShadow: [BoxShadow(color: AppTheme.updateBlue.withValues(alpha: .24), offset: Offset(0, size * .08), blurRadius: size * .16)]), child: Icon(FLucideIcons.arrowDownToLine, size: size * .36, color: AppTheme.imageForeground)),
  ])));
}

class _UpdateProgress extends StatelessWidget {
  const _UpdateProgress({required this.checking, required this.native});
  final bool checking;
  final NativeUpdateState native;
  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final complete = native.stage == NativeUpdateStage.downloaded || native.stage == NativeUpdateStage.beforeQuit;
    final pending = checking || native.stage == NativeUpdateStage.opening || native.stage == NativeUpdateStage.checking;
    return Semantics(liveRegion: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
      if (pending) const FProgress(semanticsLabel: '正在检查更新，进度未确定'),
      if (complete && !checking) const FDeterminateProgress(value: 1, semanticsLabel: '更新包已下载，尚需确认安装'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
        Icon(native.error && !checking ? FLucideIcons.circleAlert : complete && !checking ? FLucideIcons.circleCheck : FLucideIcons.info, size: 16, color: native.error && !checking ? theme.colors.destructive : theme.colors.primary),
        Expanded(child: Text(checking ? '正在读取发行信息，请稍候。' : native.message, style: theme.typography.body.sm.copyWith(color: native.error && !checking ? theme.colors.destructive : theme.colors.mutedForeground))),
      ]),
    ]));
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
        _UpdateAction(release: release), FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () => showSoftwareUpdates(context), child: const Text('查看更新日志')), FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, onPress: () => setState(() => _dismissed = '${release.version}+${release.buildNumber}'), child: const Text('稍后提醒')),
      ]),
    ));
  }
}

class _UpdateAction extends ConsumerWidget {
  const _UpdateAction({required this.release, this.fullWidth = false});
  final ClientRelease release;
  final bool fullWidth;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = release.appcasts[clientPlatform], download = release.downloads[clientPlatform];
    final ready = ref.watch(nativeUpdateReadyProvider), busy = ref.watch(nativeUpdateProvider).busy;
    final axisSize = fullWidth ? MainAxisSize.max : MainAxisSize.min;
    final size = fullWidth ? FButtonSizeVariant.lg : FButtonSizeVariant.sm;
    if (feed != null && ready.isLoading) return const Row(mainAxisSize: MainAxisSize.min, spacing: AppSpace.sm, children: [SizedBox(width: 16, height: 16, child: FCircularProgress()), Flexible(child: Text('正在确认更新方式…'))]);
    if (feed != null && ready.asData?.value == true) return FButton(mainAxisSize: axisSize, size: size, prefix: busy ? const SizedBox(width: 14, height: 14, child: FCircularProgress()) : const Icon(FLucideIcons.download, size: 15), onPress: busy ? null : () => ref.read(nativeUpdateProvider.notifier).start(feed), child: Flexible(child: Text(busy ? '正在打开更新…' : '更新并安装')));
    if (download == null) return const Text('此平台的安装包尚未发布');
    final button = FButton(mainAxisSize: axisSize, size: size, onPress: () async {
      try { await openReleaseDownload(download); } catch (_) { if (context.mounted) toast(context, '更新下载页面未能打开，请重试'); }
    }, child: Flexible(child: Text(clientPlatform == 'ios' ? '前往安装渠道更新' : '下载新版本')));
    if (!['macos', 'windows'].contains(clientPlatform)) return button;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
      Text(ready.hasError ? '更新签名读取失败，可先下载安装包。' : '当前安装包未提供自动更新配置，请下载后安装。', style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
      button,
    ]);
  }
}
