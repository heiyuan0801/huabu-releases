import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

Future<void> exportVideo(BuildContext context, WidgetRef ref, MediaBytes media, String id) async {
  final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
  bool current() => context.mounted && api.epoch == epoch && ModalRoute.of(context)?.isCurrent != false;
  final extension = switch (media.mimeType) {'video/quicktime' => 'mov', 'video/webm' => 'webm', _ => 'mp4'};
  final file = XFile.fromData(media.bytes, mimeType: media.mimeType, name: 'huabu-video-$id.$extension');
  try {
    if (AppLayout.isDesktop) {
      final location = await getSaveLocation(suggestedName: file.name);
      api.assertEpoch(epoch);
      if (location == null || !current()) return;
      await file.saveTo(location.path);
      api.assertEpoch(epoch);
      if (context.mounted && current()) toast(context, '视频已导出');
    } else {
      if (!context.mounted || !current()) return;
      final box = context.findRenderObject() as RenderBox?;
      final result = await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: [file.name], sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
      api.assertEpoch(epoch);
      if (context.mounted && current() && result.status == ShareResultStatus.success) toast(context, '已分享视频');
    }
  } catch (error) { if (context.mounted && current()) toast(context, errorMessage(error)); }
}
