import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/affiliate/affiliate_page.dart';
import 'package:huabu_app/features/affiliate/affiliate_providers.dart';
import 'package:huabu_app/features/updates/client_updates.dart';
import 'package:material_ui/material_ui.dart';

const _user = UserAccount(id: 'affiliate-fixture', email: '', displayName: '测试账号', avatarUrl: '', role: 'user', status: 'active');
const _program = {'enabled': true, 'inviterGrant': 120, 'inviteeGrant': 60, 'commissionEnabled': true, 'commissionRateBps': 1500, 'commissionMode': 'first'};
const _overview = {'code': 'fixture-code', 'settings': _program, 'stats': {'registered': 3, 'verified': 2, 'inviteCredits': 240, 'signupCredits': 0, 'commissionCredits': 75}};

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final FutureOr<Object> Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(await handler(options)), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}

ApiClient _api(_Adapter adapter) {
  final api = ApiClient(baseUrl: 'https://example.invalid/api')..resetAccount(_user.id);
  api.dio.httpClientAdapter = adapter;
  addTearDown(api.close);
  return api;
}

Widget _app(ProviderContainer container) {
  final theme = AppTheme.dark(touch: !AppLayout.isDesktop);
  return UncontrolledProviderScope(container: container, child: MaterialApp(
    theme: theme.toApproximateMaterialTheme(), locale: const Locale('zh', 'CN'),
    supportedLocales: FLocalizations.supportedLocales, localizationsDelegates: FLocalizations.localizationsDelegates,
    builder: (_, child) => FTheme(data: theme, child: FToaster(child: child!)),
    home: const FScaffold(child: AffiliatePage()),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('邀请链接沿用真实注册路由并正确编码邀请码', () {
    expect(affiliateLink('https://example.invalid/api?old=true#fragment', 'code /+&'), 'https://example.invalid/register?ref=code+%2F%2B%26');
  });

  test('奖励规则缺少或异常额度不能伪造成 0 积分', () {
    expect(() => AffiliateProgram.fromJson({..._program, 'inviteeGrant': '60'}), throwsA(isA<ApiException>()));
    expect(() => AffiliateOverview.fromJson({..._overview, 'stats': {'registered': 3}}), throwsA(isA<ApiException>()));
  });

  test('邀请读取使用现有端点与账号请求头，收益分页保持服务器默认', () async {
    final adapter = _Adapter((options) => switch (options.path) {
      '/affiliate' => _overview,
      '/affiliate/earnings' => {'items': [{'id': 'earning', 'inviteeName': '受邀好友', 'kind': 'invite_reward', 'amount': 120, 'rateBps': 0, 'createdAt': '2026-10-11T08:00:00Z'}], 'total': 11},
      _ => throw StateError('禁止未声明的请求'),
    });
    final service = AffiliateService(_api(adapter));
    expect((await service.overview()).stats['inviteCredits'], 240);
    final records = await service.records(AffiliateRecordKind.earnings, 2);
    expect(records.items.single['amount'], 120);
    expect(records.total, 11);
    expect(adapter.requests.map((request) => request.method), everyElement('GET'));
    expect(adapter.requests.last.queryParameters, {'page': 2});
    expect(adapter.requests.last.headers['X-Account-ID'], _user.id);
  });

  test('损坏的收益记录不能显示虚假到账额度', () async {
    final service = AffiliateService(_api(_Adapter((_) => {'items': [{'id': 'bad', 'inviteeName': '好友', 'kind': 'invite_reward', 'amount': '120', 'rateBps': 0, 'createdAt': '2026-10-11T08:00:00Z'}], 'total': 1})));
    await expectLater(service.records(AffiliateRecordKind.earnings, 1), throwsA(isA<ApiException>()));
  });

  test('账号切换后忽略迟到的邀请数据', () async {
    final pending = Completer<Object>();
    final api = _api(_Adapter((_) => pending.future));
    final result = AffiliateService(api).overview();
    await Future<void>.delayed(Duration.zero);
    api.resetAccount('different-account');
    pending.complete(_overview);
    await expectLater(result, throwsA(isA<ApiException>().having((error) => error.canceled, '已取消', true)));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
  for (final failure in [false, true]) {
    testWidgets('${platform.name} 邀请页${failure ? '失败保持错误状态' : '展示真实规则与空记录'}', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
      tester.view.physicalSize = platform == TargetPlatform.iOS ? const Size(390, 844) : const Size(720, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
      final api = _api(_Adapter((_) => throw StateError('UI 测试禁止真实请求')));
      final container = ProviderContainer.test(retry: (_, _) => null, overrides: [
        apiProvider.overrideWithValue(api),
        sessionProvider.overrideWithBuild((ref, notifier) => _user),
        affiliateOverviewProvider.overrideWith((ref) async => AffiliateOverview.fromJson(_overview)),
        clientReleaseProvider.overrideWith((ref) async => null),
        affiliateRecordsProvider.overrideWith((ref, query) async {
          if (failure) throw const ApiException('测试读取失败');
          return const AffiliateRecords(items: [], total: 0);
        }),
      ]);
      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('240'), findsOneWidget);
      expect(find.textContaining('你获得 120 积分'), findsOneWidget);
      expect(find.text('邀请记录读取失败'), failure ? findsOneWidget : findsNothing);
      expect(find.text('还没有邀请记录'), failure ? findsNothing : findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      } finally { debugDefaultTargetPlatformOverride = null; }
    });
  }
  }
}
