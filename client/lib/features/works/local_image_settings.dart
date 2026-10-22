import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../generation/generation_controller.dart';

class LocalImageSettings extends ConsumerStatefulWidget {
  const LocalImageSettings({super.key});
  @override
  ConsumerState<LocalImageSettings> createState() => _LocalImageSettingsState();
}
class _LocalImageSettingsState extends ConsumerState<LocalImageSettings> {
  bool _busy = false;
  String _error = '';
  Future<void> _act({bool choose = false}) async {
    if (_busy) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = true; _error = ''; });
    try {
      final store = ref.read(localImageStoreProvider);
      if (choose) {
        if (await store.chooseFolder()) {
          api.assertEpoch(epoch);
          if (mounted) { ref.invalidate(imageFolderProvider); toast(context, '新图片将保存到新目录，已有文件保持原位'); }
        }
      } else { await store.openFolder(); }
    } catch (error) { if (mounted && api.epoch == epoch) setState(() => _error = errorMessage(error)); }
    finally { if (mounted && api.epoch == epoch) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final folder = ref.watch(imageFolderProvider), generation = ref.watch(generationProvider);
    ref.listen(sessionProvider.select((value) => value.asData?.value?.id), (_, _) { if (mounted) setState(() { _busy = false; _error = ''; }); });
    return FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
      Row(spacing: 10, children: [Icon(FLucideIcons.folderOpen, size: 19, color: context.theme.colors.primary), Text('本机图片存储', style: context.theme.typography.display.md.copyWith(fontWeight: FontWeight.w600))]),
      Text('新生成图片与新收藏只保存在本设备，按站点、账号和日期归档，不上传服务器。', style: context.theme.typography.body.sm),
      folder.when(data: (path) => SelectableText('$path${AppLayout.isDesktop ? ' / 年-月-日' : ''}', style: context.theme.typography.body.xs), loading: () => const FCircularProgress(), error: (error, _) => FAlert(title: const Text('保存目录读取失败'), subtitle: Text(errorMessage(error)))),
      if (_error.isNotEmpty) FAlert(title: const Text('文件夹操作未完成'), subtitle: Text(_error)),
      if (AppLayout.isDesktop) Wrap(spacing: 8, runSpacing: 8, children: [
        FButton(variant: FButtonVariant.outline, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _busy || generation.working ? null : () => _act(choose: true), child: const Text('选择保存目录')),
        FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _busy || !folder.hasValue ? null : _act, child: const Text('打开文件夹')),
        if (folder.hasError) FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(imageFolderProvider), child: const Text('重新读取')),
      ]),
      Text(AppLayout.isDesktop ? '默认使用应用文档目录；可选择外置盘。修改目录只影响后续保存，原图不会自动搬移或删除，请自行备份。' : '使用应用本地文档目录，卸载前请导出图片备份；可在作品详情中分享或导出。', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
    ]));
  }
}
