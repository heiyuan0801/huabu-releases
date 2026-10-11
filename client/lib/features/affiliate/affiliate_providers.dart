import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'affiliate_service.dart';

export 'affiliate_service.dart';

final affiliateServiceProvider = Provider((ref) => AffiliateService(ref.watch(apiProvider)));

CancelToken _cancelToken(Ref ref) {
  final token = CancelToken();
  ref.onDispose(() => token.cancel('页面已关闭'));
  return token;
}

Future<void> _account(Ref ref) async {
  ref.watch(sessionProvider.select((value) => value.asData?.value?.id));
  final user = await ref.read(sessionProvider.future);
  if (!ref.mounted) throw const ApiException('操作已取消', canceled: true);
  if (user == null) throw const ApiException('登录后查看邀请信息', status: 401);
}

final affiliateProgramProvider = FutureProvider.autoDispose((ref) => ref.watch(affiliateServiceProvider).program(cancelToken: _cancelToken(ref)));
final affiliateOverviewProvider = FutureProvider.autoDispose((ref) async {
  await _account(ref);
  if (!ref.mounted) throw const ApiException('操作已取消', canceled: true);
  return ref.watch(affiliateServiceProvider).overview(cancelToken: _cancelToken(ref));
});
final affiliateRecordsProvider = FutureProvider.autoDispose.family<AffiliateRecords, ({AffiliateRecordKind kind, int page})>((ref, query) async {
  await _account(ref);
  if (!ref.mounted) throw const ApiException('操作已取消', canceled: true);
  return ref.watch(affiliateServiceProvider).records(query.kind, query.page, cancelToken: _cancelToken(ref));
});
