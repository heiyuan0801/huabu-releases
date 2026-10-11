import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/repository.dart';
import 'package:huabu_app/features/channels/channel_providers.dart';
import 'package:huabu_app/features/chat/chat_controller.dart';
import 'package:huabu_app/features/chat/chat_models.dart';
import 'package:huabu_app/features/chat/chat_service.dart';
import 'package:huabu_app/features/generation/generation_controller.dart';
import 'package:huabu_app/features/generation/generation_service.dart';
import 'package:huabu_app/features/video/video_repository.dart';
import 'package:huabu_app/features/video/video_service.dart';

// Every request stops at this adapter. No sockets, credentials or billed APIs.
class _MemoryAdapter implements HttpClientAdapter {
  _MemoryAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (requestStream != null) await requestStream.drain<void>();
    requests.add(options);
    return respond(options);
  }
  @override
  void close({bool force = false}) {}
}

(ApiClient, _MemoryAdapter) _api(FutureOr<ResponseBody> Function(RequestOptions) respond) {
  final api = ApiClient(baseUrl: 'https://huabu-fixture.invalid/api')..resetAccount('fixture-account-a');
  final adapter = _MemoryAdapter(respond);
  api.dio.httpClientAdapter = adapter;
  addTearDown(api.close);
  return (api, adapter);
}

ResponseBody _json(Object? value, {int status = 200, Map<String, List<String>> headers = const {}}) =>
  ResponseBody.fromString(jsonEncode(value), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType], ...headers});
ResponseBody _empty() => ResponseBody.fromString('', 204);
ResponseBody _error(String message) => _json({'error': message}, status: 503);
ResponseBody _sse(List<Json> events, {bool done = false}) => ResponseBody.fromString(
  '${events.map((event) => 'data: ${jsonEncode(event)}\n\n').join()}${done ? 'data: [DONE]\n\n' : ''}',
  200, headers: {Headers.contentTypeHeader: ['text/event-stream']},
);
Never _unexpected(RequestOptions request) => throw StateError('未预期的测试请求：${request.method} ${request.path}');
Matcher get _canceled => isA<ApiException>().having((error) => error.canceled, 'canceled', isTrue);

ImageModel _model({String name = 'gpt-image-1', String format = 'openai', String capability = 'image'}) => ImageModel(
  id: name, providerId: 'fixture-provider', providerName: '测试渠道', model: name,
  displayName: name, apiFormat: format, capability: capability, creditCost: 0,
  value: 'managed:fixture-provider::$name',
);
Json _run({String status = 'success', int count = 1}) => {
  'id': 'fixture-run', 'model': _model().value, 'capability': 'image',
  'status': status, 'serverStatus': status, 'requestedCount': count,
  'resultCount': status == 'success' ? count : 0,
};
const _user = UserAccount(id: 'fixture-account-a', email: '', displayName: '测试账号', avatarUrl: '', role: 'user', status: 'active');
const _message = ChatMessage(id: 'fixture-message', role: 'user', content: '测试问题', createdAt: 0);

ResponseBody? _generationBookkeeping(RequestOptions request) {
  if (request.path == '/generations' && request.method == 'POST') return _json({'id': 'fixture-run'});
  if (request.path == '/storage/generation_contexts/fixture-run') return _json({});
  if (request.path == '/generations/fixture-run/status') return _json(_run());
  return null;
}

class _RetryRepository extends HuabuRepository {
  _RetryRepository(super.api);
  int saves = 0;
  final outputs = <GenerationOutput>[];
  @override
  Future<List<Artwork>> saveGeneration(GenerationOutput output) async {
    outputs.add(output);
    if (++saves == 1) throw const ApiException('测试保存失败');
    return [Artwork(id: 'saved-image', title: output.prompt, prompt: output.prompt,
      imageUrl: '/storage/image_files/saved-image', createdAt: DateTime(2026))];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('账号切换取消迟到请求、显式页面请求与旧模型入口', () async {
    final entered = Completer<void>(), late = Completer<ResponseBody>();
    final (api, adapter) = _api((request) {
      if (request.path == '/late') { entered.complete(); return late.future; }
      return _json({'account': request.headers['X-Account-ID']});
    });
    final oldTarget = ModelApiTarget(api, _model());
    final token = CancelToken();
    final pending = api.request('/late', cancelToken: token);
    final canceled = expectLater(pending, throwsA(_canceled));
    await entered.future;
    api.resetAccount('fixture-account-b');
    late.complete(_json({'account': 'fixture-account-a'}));
    await canceled;
    expect(token.isCancelled, isTrue);
    await expectLater(oldTarget.post('/v1/images/generations', {}), throwsA(_canceled));
    expect(adapter.requests.length, 1);
    expect((await api.get('/fresh'))['account'], 'fixture-account-b');
  });

  test('媒体经服务器代理，同源个人认证不会发送到跨源 CDN', () async {
    final (api, adapter) = _api((request) => ResponseBody.fromBytes([1, 2, 3], 200,
      headers: {Headers.contentTypeHeader: ['image/png']}));
    const channel = LocalChannel(id: 'fixture', name: '测试渠道', baseUrl: 'https://upstream-fixture.invalid/v1',
      apiKey: 'synthetic-test-key', apiFormat: 'openai', models: []);
    final target = ModelApiTarget(api, _model(), channel: channel);
    await target.media('/v1/media/same-origin', runId: 'fixture-run');
    await target.media('https://cdn-fixture.invalid/output.png', runId: 'fixture-run');
    expect(adapter.requests.map((request) => request.path), everyElement('/proxy'));
    expect(adapter.requests.first.queryParameters['url'], 'https://upstream-fixture.invalid/v1/media/same-origin');
    expect(adapter.requests.first.headers['Authorization'], 'Bearer synthetic-test-key');
    expect(adapter.requests.last.headers.containsKey('Authorization'), isFalse);
    expect(adapter.requests.last.headers['X-Huabu-Run-ID'], 'fixture-run');
    await expectLater(api.get('https://forbidden-fixture.invalid/private'), throwsA(isA<ApiException>()));
    expect(adapter.requests.length, 2);
  });

  test('代理上游 401 不注销本站账号，本站 401 才触发失效', () async {
    final (api, _) = _api((request) => _json({'error': '测试拒绝'}, status: 401,
      headers: request.path == '/proxy' ? {'X-Huabu-Request-ID': ['fixture-request']} : {}));
    var expired = 0;
    api.onUnauthorized = () => expired++;
    await expectLater(api.get('/proxy'), throwsA(isA<ApiException>().having((error) => error.status, 'status', 401)));
    expect(expired, 0);
    await expectLater(api.get('/profile'), throwsA(isA<ApiException>()));
    expect(expired, 1);
  });

  test('图片未知结果保持任务编号，不宣告成功或重新提交', () async {
    final (api, adapter) = _api((request) {
      if (request.path == '/generations/fixture-run/status') return _json(_run(status: 'unknown'));
      if (request.path == '/platform/fixture-provider/v1/images/generations') return _json({'task_id': 'accepted-task'});
      return _generationBookkeeping(request) ?? _unexpected(request);
    });
    await expectLater(GenerationService(api).generate(_model(), prompt: '测试图片'), throwsA(
      isA<GenerationException>().having((error) => error.runId, 'runId', 'fixture-run')));
    expect(adapter.requests.where((request) => request.path.contains('/v1/images/') && request.method == 'POST'), hasLength(1));
    expect(adapter.requests.where((request) => request.method == 'PATCH'), isEmpty);
  });

  test('图片部分附件读取失败保留已取得图片，避免伪造完整成功', () async {
    final (api, adapter) = _api((request) {
      if (request.path.endsWith('/v1/images/generations')) return _json({'data': [{'url': '/v1/media/first'}, {'url': '/v1/media/missing'}]});
      if (request.path.endsWith('/v1/media/first')) return ResponseBody.fromBytes([1, 2, 3], 200, headers: {Headers.contentTypeHeader: ['image/png']});
      if (request.path.endsWith('/v1/media/missing')) return _error('测试附件读取失败');
      return _generationBookkeeping(request) ?? _unexpected(request);
    });
    final output = await GenerationService(api).generate(_model(), prompt: '测试图片', count: 2);
    expect(output.images.single.bytes, [1, 2, 3]);
    expect(output.partial, isTrue);
    expect(output.notice, contains('附件读取失败'));
    expect(adapter.requests.where((request) => request.method == 'PATCH'), isEmpty);
    final request = adapter.requests.singleWhere((request) => request.path.endsWith('/v1/images/generations'));
    expect(request.data, containsPair('n', 2));
    expect(request.headers['X-Huabu-Run-ID'], 'fixture-run');
  });

  test('图片作品保存失败保留结果，重试仅保存而不再次生成', () async {
    final (api, adapter) = _api((request) {
      if (request.path.endsWith('/v1/images/generations')) return _json({'data': [{'b64_json': 'AQID'}]});
      if (request.path == '/generations/fixture-run' && request.method == 'PATCH') return _json({});
      return _generationBookkeeping(request) ?? _unexpected(request);
    });
    final repository = _RetryRepository(api);
    final container = ProviderContainer.test(overrides: [
      apiProvider.overrideWithValue(api), repositoryProvider.overrideWithValue(repository),
      sessionProvider.overrideWithBuild((ref, notifier) async => _user),
    ]);
    await container.read(sessionProvider.future);
    final controller = container.read(generationProvider.notifier);
    await controller.generate(_model(), prompt: '测试图片', ratio: '1:1', count: 1, quality: 'auto', asynchronous: false);
    final failed = container.read(generationProvider);
    expect(failed.output?.images.single.bytes, [1, 2, 3]);
    expect(failed.error, contains('作品保存未完成'));
    await controller.saveOutput();
    expect(repository.saves, 2);
    expect(identical(repository.outputs.first, repository.outputs.last), isTrue);
    expect(container.read(generationProvider).works.single.id, 'saved-image');
    expect(adapter.requests.where((request) => request.path.endsWith('/v1/images/generations')), hasLength(1));
  });

  test('Muse 请求携带真实协议参数与首帧，不按模型名虚构结果', () async {
    final (api, adapter) = _api((request) => _json({'code': 0, 'data': {'id': 'fixture-video-task'}}));
    final model = _model(name: 'muse-video', capability: 'video');
    final service = VideoService(api, ModelApiTarget(api, model));
    final config = VideoConfig(model: model, prompt: '测试视频', seconds: 8, ratio: '16:9', resolution: '1080p',
      references: [VideoReference(kind: 'image', name: '首帧.png', media: MediaBytes(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/png'))]);
    service.validate(config);
    final task = await service.submit(config, 'fixture-run');
    expect(task.id, 'fixture-video-task');
    expect(task.protocol, 'muse');
    expect(adapter.requests.single.path, '/platform/fixture-provider/v1/videos');
    expect(adapter.requests.single.data, {
      'model': 'muse-video', 'prompt': '测试视频', 'duration': 8,
      'size': '16:9', 'resolution': '1080p', 'reference_image': 'data:image/png;base64,AQID',
    });
    expect(adapter.requests.single.headers['X-Huabu-Run-ID'], 'fixture-run');
  });

  test('Seedance 个人渠道版本路径与内容字段遵循协议', () async {
    final (api, adapter) = _api((request) => _json({'id': 'fixture-video-task'}));
    final model = _model(name: 'seedance-test', format: 'ark', capability: 'video');
    const channel = LocalChannel(id: 'fixture', name: '测试渠道', baseUrl: 'https://upstream-fixture.invalid/api/plan/v3',
      apiKey: 'synthetic-test-key', apiFormat: 'ark', models: []);
    final service = VideoService(api, ModelApiTarget(api, model, channel: channel));
    final config = VideoConfig(model: model, prompt: '测试视频', seconds: -1, ratio: 'auto', resolution: 'auto', watermark: true);
    service.validate(config);
    await service.submit(config, 'fixture-run');
    expect(adapter.requests.single.path, '/proxy');
    expect(adapter.requests.single.queryParameters['url'], 'https://upstream-fixture.invalid/api/plan/v3/contents/generations/tasks');
    expect(adapter.requests.single.data, {
      'model': 'seedance-test', 'content': [{'type': 'text', 'text': '测试视频'}],
      'ratio': 'adaptive', 'resolution': '720p', 'duration': -1, 'generate_audio': true, 'watermark': true,
    });
  });

  test('视频未知与缺地址完成状态不当作确认失败或伪成功', () async {
    var status = 'processing';
    final (api, adapter) = _api((request) => _json({'status': status}));
    final model = _model(name: 'muse-video', capability: 'video');
    final service = VideoService(api, ModelApiTarget(api, model));
    final task = VideoTask(id: 'fixture-video-task', runId: 'fixture-run', protocol: 'muse', model: model.value);
    expect(await service.query(task), isNull);
    status = 'completed';
    await expectLater(service.query(task), throwsA(isA<VideoGenerationException>()
      .having((error) => error.confirmedFailure, 'confirmedFailure', isFalse)
      .having((error) => error.task?.id, 'task.id', task.id)));
    status = 'failed';
    await expectLater(service.query(task), throwsA(isA<VideoGenerationException>()
      .having((error) => error.confirmedFailure, 'confirmedFailure', isTrue)));
    expect(adapter.requests.map((request) => request.method), everyElement('GET'));
    expect(adapter.requests, hasLength(3));
  });

  test('视频记录写入失败重试复用已保存附件，不重复上传或生成', () async {
    Uint8List? stored;
    var logWrites = 0, mediaWrites = 0;
    final media = MediaBytes(bytes: Uint8List.fromList([1, 2, 3, 4]), mimeType: 'video/mp4');
    final (api, adapter) = _api((request) {
      if (request.path == '/storage/media_files/video%3Afixture-run') {
        if (request.method == 'GET') {
          return stored == null ? _empty() : ResponseBody.fromBytes(stored!, 200,
            headers: {'X-Storage-Blob': ['1'], 'X-Storage-Revision': ['1']});
        }
        mediaWrites++; stored = media.bytes; return _json({});
      }
      if (request.path == '/storage/video_generation_logs/fixture-run') {
        if (request.method == 'GET') return _empty();
        return ++logWrites == 1 ? _error('测试记录保存失败') : _json({});
      }
      return _unexpected(request);
    });
    final repository = VideoRepository(api);
    const work = VideoWork('fixture-run', {'id': 'fixture-run', 'runId': 'fixture-run', 'prompt': '测试视频', 'status': 'pending'});
    await expectLater(repository.saveMedia(work, media), throwsA(isA<ApiException>()));
    final saved = await repository.saveMedia(work, media);
    expect(saved.status, 'success');
    expect(saved.fileKey, 'video:fixture-run');
    expect(mediaWrites, 1);
    expect(logWrites, 2);
    expect(adapter.requests.where((request) => request.path.contains('/generations')), isEmpty);
  });

  test('已保存视频不能被迟到 pending 结果降级', () async {
    final (api, adapter) = _api((request) => _json({'id': 'fixture-run', 'status': 'success', 'video': {'storageKey': 'video:fixture-run'}}));
    final saved = await VideoRepository(api).save(const VideoWork('fixture-run', {'id': 'fixture-run', 'status': 'pending'}));
    expect(saved.status, 'success');
    expect(saved.fileKey, 'video:fixture-run');
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'GET');
  });

  for (final damaged in [
    (name: 'blob', value: <String, dynamic>{'images': []}, blob: true),
    (name: '非对象', value: 'damaged-record', blob: false),
    (name: 'images 非列表', value: <String, dynamic>{'images': 'damaged-images'}, blob: false),
  ]) {
    test('损坏图片记录 ${damaged.name} 拒绝覆盖', () async {
      final (api, adapter) = _api((request) => _json(damaged.value,
        headers: {if (damaged.blob) 'X-Storage-Blob': ['1']}));
      const output = GenerationOutput(runId: 'fixture-run', run: null, images: [],
        prompt: '测试图片', model: 'managed:fixture-provider::gpt-image-1',
        ratio: '1:1', quality: 'auto', requestedCount: 1);
      await expectLater(HuabuRepository(api).saveGeneration(output), throwsA(isA<ApiException>()));
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.method, 'GET');
    });
  }

  for (final damaged in [
    (name: 'blob', value: <String, dynamic>{'status': 'pending'}, blob: true),
    (name: '非对象', value: 'damaged-record', blob: false),
    (name: 'video 非对象', value: <String, dynamic>{'status': 'success', 'video': []}, blob: false),
  ]) {
    test('损坏视频记录 ${damaged.name} 拒绝覆盖', () async {
      final (api, adapter) = _api((request) => _json(damaged.value,
        headers: {if (damaged.blob) 'X-Storage-Blob': ['1']}));
      await expectLater(VideoRepository(api).save(const VideoWork('fixture-run', {'id': 'fixture-run', 'status': 'pending'})),
        throwsA(isA<ApiException>()));
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.method, 'GET');
    });
  }

  test('聊天只有 DONE 或断流时保留已收到文本，不伪造完成事件', () async {
    final (api, adapter) = _api((request) => _sse([
      {'type': 'response.output_text.delta', 'delta': '已收到部分内容'},
    ], done: true));
    final store = ChatStore(api)..token = CancelToken();
    addTearDown(store.dispose);
    final updates = <ChatStreamUpdate>[];
    await expectLater(store.stream(ModelApiTarget(api, _model(capability: 'text')), [_message], 'fixture-run').forEach(updates.add),
      throwsA(isA<ChatStreamException>().having((error) => error.confirmed, 'confirmed', isFalse)));
    expect(updates.single.text, '已收到部分内容');
    expect(updates.single.status, 'pending');
    expect(adapter.requests.single.path, '/platform/fixture-provider/v1/responses');
    expect(adapter.requests.single.data, containsPair('stream', true));
  });

  test('聊天附件读取失败在模型请求前停止，保留输入附件', () async {
    final (api, adapter) = _api((request) => _error('测试附件读取失败'));
    final store = ChatStore(api)..token = CancelToken();
    addTearDown(store.dispose);
    const message = ChatMessage(id: 'fixture-message', role: 'user', content: '测试问题', createdAt: 0,
      attachments: [ChatAttachment(key: 'image:fixture', name: '参考图.png', mimeType: 'image/png')]);
    await expectLater(store.stream(ModelApiTarget(api, _model(capability: 'text')), [message], 'fixture-run').toList(),
      throwsA(isA<ApiException>()));
    expect(message.attachments.single.key, 'image:fixture');
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.path, '/storage/image_files/image%3Afixture');
  });

  test('聊天最终保存失败保留完整回复，重试只保存会话', () async {
    var sessionWrites = 0;
    final (api, adapter) = _api((request) {
      if (request.path.startsWith('/storage/app_state/')) {
        if (request.method == 'GET') return _empty();
        return ++sessionWrites == 2 ? _error('测试最终保存失败') : _json({}, headers: {'X-Storage-Revision': ['$sessionWrites']});
      }
      if (request.path.endsWith('/v1/responses')) {
        return _sse([
          {'type': 'response.output_text.delta', 'delta': '完整回复'},
          {'type': 'response.completed', 'response': {'output_text': '完整回复'}},
        ]);
      }
      if (request.path == '/generations/fixture-run') return _json({});
      return _generationBookkeeping(request) ?? _unexpected(request);
    });
    final container = ProviderContainer.test(overrides: [
      apiProvider.overrideWithValue(api), sessionProvider.overrideWithBuild((ref, notifier) async => _user),
    ]);
    await container.read(sessionProvider.future);
    await container.read(chatProvider.future);
    final controller = container.read(chatProvider.notifier);
    expect(await controller.send('测试问题', _model(capability: 'text'), []), isTrue);
    final failed = container.read(chatProvider).requireValue;
    expect(failed.dirty, isTrue);
    expect(failed.active!.messages.last.content, '完整回复');
    expect(failed.active!.messages.last.status, 'complete');
    await controller.retrySave();
    expect(container.read(chatProvider).requireValue.dirty, isFalse);
    expect(container.read(chatProvider).requireValue.active!.messages.last.content, '完整回复');
    expect(sessionWrites, 3);
    expect(adapter.requests.where((request) => request.path.endsWith('/v1/responses')), hasLength(1));
    expect(adapter.requests.where((request) => request.path == '/generations' && request.method == 'POST'), hasLength(1));
  });

  test('账号切换后聊天迟到的流终态不能发布为当前账号回复', () async {
    final events = StreamController<Uint8List>();
    final (api, _) = _api((request) => ResponseBody(events.stream, 200,
      headers: {Headers.contentTypeHeader: ['text/event-stream']}));
    final store = ChatStore(api)..token = CancelToken();
    addTearDown(store.dispose);
    final first = Completer<void>(), updates = <ChatStreamUpdate>[];
    final canceled = expectLater(store.stream(ModelApiTarget(api, _model(capability: 'text')), [_message], 'fixture-run').forEach((update) {
      updates.add(update); first.complete();
    }), throwsA(_canceled));
    events.add(Uint8List.fromList(utf8.encode('data: {"type":"response.output_text.delta","delta":"旧账号部分回复"}\n\n')));
    await first.future;
    api.resetAccount('fixture-account-b');
    events.add(Uint8List.fromList(utf8.encode('data: {"type":"response.completed","response":{"output_text":"旧账号完整回复"}}\n\n')));
    await canceled;
    await events.close();
    expect(updates.single.text, '旧账号部分回复');
    expect(updates.single.status, 'pending');
  });
}
