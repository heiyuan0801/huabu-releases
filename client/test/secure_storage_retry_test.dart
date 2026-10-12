import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/features/channels/channel_providers.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _user = UserAccount(id: 'fixture-account', email: '', displayName: '测试账号', avatarUrl: '', role: 'user', status: 'active');

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'https://example.invalid/api');
  int reads = 0;
  bool failFirst = false;
  @override
  Future<Json> get(String path, {Map<String, dynamic>? query, Map<String, dynamic>? headers}) async {
    if (path != '/auth/me') throw StateError('测试禁止真实请求');
    reads++;
    if (failFirst && reads == 1) throw const ApiException('测试网络错误');
    return {'id': _user.id, 'email': '', 'displayName': _user.displayName, 'avatarUrl': '', 'role': 'user', 'status': 'active'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final local in [false, true]) {
    test('${local ? '个人渠道' : '登录会话'}拒绝授权后不自动重读，手动重试才再次读取', () async {
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method != 'read') throw StateError('测试禁止写入或删除凭据');
        reads++;
        throw PlatformException(code: 'Unexpected security result code', details: -128);
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
      final api = _Api()..resetAccount(local ? _user.id : '');
      addTearDown(api.close);
      final container = ProviderContainer.test(overrides: [
        apiProvider.overrideWithValue(api),
        if (local) sessionProvider.overrideWithBuild((ref, notifier) => _user),
      ]);
      if (local) { container.listen(localChannelsProvider, (_, _) {}); } else { container.listen(sessionProvider, (_, _) {}); }
      Future<Object?> read() => local ? container.read(localChannelsProvider.future) : container.read(sessionProvider.future);
      await expectLater(read(), throwsA(isA<PlatformException>()));
      await container.pump();
      expect(reads, 1);
      expect(local ? container.read(localChannelsProvider).hasError : container.read(sessionProvider).hasError, isTrue);
      if (local) { container.invalidate(localChannelsProvider); } else { container.invalidate(sessionProvider); }
      await expectLater(read(), throwsA(isA<PlatformException>()));
      expect(reads, 2);
      expect(api.reads, 0);
    });
  }

  test('安全存储成功后账号网络失败仍沿用原自动重试', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method != 'read') throw StateError('测试禁止写入或删除凭据');
      return 'huabu_session=fixture-session';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
    final api = _Api()..failFirst = true;
    addTearDown(api.close);
    final container = ProviderContainer.test(overrides: [apiProvider.overrideWithValue(api)]);
    container.listen(sessionProvider, (_, _) {});
    expect((await container.read(sessionProvider.future))?.id, _user.id);
    expect(api.reads, 2);
  });
}
