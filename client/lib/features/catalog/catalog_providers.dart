import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../channels/channel_providers.dart';

final defaultModelProvider = AsyncNotifierProvider<DefaultModelController, String?>(DefaultModelController.new);
class DefaultModelController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final account = ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
    if (account == null) return null;
    final catalog = await ref.watch(catalogProvider.future);
    final saved = await ref.read(databaseProvider).readPreference('default-image-model:$account');
    return catalog.any((model) => model.capability == 'image' && model.id == saved) ? saved : null;
  }

  Future<void> setModel(String id) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final account = api.accountId;
    if (account.isEmpty) throw const ApiException('登录后设置默认模型');
    final catalog = await ref.read(catalogProvider.future);
    api.assertEpoch(epoch);
    if (!catalog.any((model) => model.capability == 'image' && model.id == id)) throw const ApiException('请选择可用的图片模型');
    await ref.read(databaseProvider).writePreference('default-image-model:$account', id);
    api.assertEpoch(epoch);
    if (ref.mounted) state = AsyncData(id);
  }
}
