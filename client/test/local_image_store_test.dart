import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huabu_app/core/api/api_client.dart';
import 'package:huabu_app/core/database.dart';
import 'package:huabu_app/core/models.dart';
import 'package:huabu_app/features/generation/generation_service.dart';
import 'package:huabu_app/features/works/local_image_store.dart';

class _Preferences extends AppDatabase {
  _Preferences(this.path) : super(NativeDatabase.memory());
  String path;
  @override
  Future<String?> readPreference(String key) async => path;
  @override
  Future<void> writePreference(String key, String value) async { path = value; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chat.weilai.huabu/window');
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
  late Directory root;
  late LocalImageDatabase database;
  late _Preferences preferences;
  late ApiClient api;
  late LocalImageStore store;
  int networkRequests = 0;
  GenerationOutput output() => GenerationOutput(runId: 'run-one', run: null, images: [MediaBytes(bytes: png, mimeType: 'image/png')], prompt: '测试图片', model: 'fixture', ratio: '1:1', quality: 'auto', requestedCount: 1, receivedAt: DateTime(2026, 10, 22));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('huabu-local-image-test-');
    database = LocalImageDatabase(NativeDatabase.memory());
    preferences = _Preferences(root.path);
    api = ApiClient(baseUrl: 'https://fixture.invalid/api')..resetAccount('account-a');
    networkRequests = 0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      networkRequests++;
      handler.reject(DioException(requestOptions: request, error: StateError('本机归档测试禁止网络')));
    }));
    store = LocalImageStore(api, database, preferences);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => call.method == 'accessImageFolder' ? call.arguments : null);
  });
  tearDown(() async {
    expect(networkRequests, 0);
    await database.close(); await preferences.close(); api.close();
    await root.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test('按日期保存且重试不重复文件或记录，移除列表保留磁盘原图', () async {
    final first = (await store.saveGeneration(output())).single;
    final again = (await store.saveGeneration(output())).single;
    expect(again.id, first.id);
    expect(await store.works(), hasLength(1));
    expect((await store.read(first.imageUrl)).bytes, png);
    final files = await root.list(recursive: true).where((entity) => entity is File).toList();
    expect(files, hasLength(1)); expect(files.single.path, contains('2026-10-22'));
    await store.remove(first);
    expect(await store.works(), isEmpty); expect(await files.single.exists(), isTrue);
  });
  test('站点和账号隔离，不能读取另一账号的本机图片', () async {
    final work = (await store.saveGeneration(output())).single;
    api.resetAccount('account-b');
    expect(await store.works(), isEmpty);
    await expectLater(store.read(work.imageUrl), throwsA(isA<ApiException>()));
    final otherSite = ApiClient(baseUrl: 'https://another.invalid/api')..resetAccount('account-a');
    try { expect(await LocalImageStore(otherSite, database, preferences).works(), isEmpty); }
    finally { otherSite.close(); }
    api.resetAccount('account-a'); expect(await store.works(), hasLength(1));
  });
  test('文件缺失保留历史记录，不请求服务器恢复或重生', () async {
    final work = (await store.saveGeneration(output())).single;
    for (final file in await root.list(recursive: true).where((entity) => entity is File).toList()) { await file.delete(); }
    await expectLater(store.read(work.imageUrl), throwsA(isA<ApiException>()));
    expect(await store.works(), hasLength(1));
  });
  test('保存失败可改目录重试，不修改其他图片已有位置', () async {
    final work = (await store.saveGeneration(output())).single;
    final newRoot = await Directory('${root.path}/new-folder').create();
    preferences.path = newRoot.path;
    expect((await store.read(work.imageUrl)).bytes, png);
    expect((await store.saveGeneration(output())).single.id, work.id);
    expect(await store.works(), hasLength(1));
    expect(await newRoot.list(recursive: true).where((entity) => entity is File).length, 1);
  });
}
