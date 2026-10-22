import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/repository.dart';
import 'package:huabu_app/features/generation/generation_controller.dart';
import 'package:huabu_app/features/generation/generation_service.dart';

const _model = ImageModel(id: 'fixture', providerId: 'fixture', providerName: '测试', model: 'gpt-image-1', displayName: '', apiFormat: 'openai', capability: 'image', creditCost: 0, value: 'managed:fixture::gpt-image-1');
class _Session extends SessionController {
  @override
  Future<UserAccount?> build() async => const UserAccount(id: 'a', email: '', displayName: '', avatarUrl: '', role: 'user', status: 'active');
}
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? generate;
  int runs = 0;
  ResponseBody json(Object? value) => ResponseBody.fromString(jsonEncode(value), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) async {
    if (body != null) await body.drain<void>();
    requests.add(options);
    if (options.path == '/generations') return json({'id': 'run-${++runs}'});
    if (options.path.startsWith('/storage/generation_contexts/')) return json({});
    if (options.path.startsWith('/platform/')) return generate == null ? json({'data': [{'b64_json': 'AQID'}]}) : generate!(options);
    if (options.path.endsWith('/status')) return json({'id': 'run-$runs', 'model': _model.value, 'status': 'success', 'serverStatus': 'success', 'resultCount': 1, 'requestedCount': 1});
    if (options.method == 'PATCH') return json({'ok': true});
    throw StateError('Unexpected request: ${options.path}');
  }
  @override
  void close({bool force = false}) {}
}
class _Repository extends HuabuRepository {
  _Repository(super.api);
  final saves = <String>[];
  Future<void> Function(GenerationOutput)? beforeSave;
  @override
  Future<List<Artwork>> saveGeneration(GenerationOutput output) async {
    saves.add(output.runId);
    await beforeSave?.call(output);
    return [Artwork(id: output.runId, title: output.prompt, prompt: output.prompt, imageUrl: 'huabu-local:${output.runId}', createdAt: DateTime(2026))];
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient api;
  late _Adapter adapter;
  late _Repository repository;
  late ProviderContainer container;
  Future<void> run(List<String> prompts) => container.read(generationProvider.notifier).generateBatch(_model, prompts: prompts, ratio: '1:1', count: 1, quality: 'auto', asynchronous: false);
  setUp(() async {
    api = ApiClient(baseUrl: 'https://fixture.invalid/api')..resetAccount('a');
    adapter = _Adapter(); api.dio.httpClientAdapter = adapter;
    repository = _Repository(api);
    container = ProviderContainer.test(overrides: [apiProvider.overrideWith((_) => api), repositoryProvider.overrideWith((_) => repository), sessionProvider.overrideWith(_Session.new)]);
    await container.read(sessionProvider.future);
  });
  tearDown(() { container.dispose(); api.close(); });
  test('逐项生成，失败继续，无自动生成重试，使用已有不归档协议', () async {
    var calls = 0;
    adapter.generate = (_) async {
      if (++calls == 1) return ResponseBody.fromString('{"error":"synthetic failure"}', 503, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      return adapter.json({'data': [{'b64_json': 'AQID'}]});
    };
    await run(['第一项', '第二项']);
    final state = container.read(generationProvider);
    expect(calls, 2); expect(state.batchRunning, isFalse);
    expect(state.batch.first.status, BatchImageStatus.failed); expect(state.batch.last.status, BatchImageStatus.saved);
    expect(repository.saves, ['run-2']);
    for (final request in adapter.requests.where((item) => item.path == '/generations')) { expect((request.data as Json)['detail'], containsPair('resultStorage', 'browser')); }
    expect(adapter.requests.where((item) => item.path.contains('image_files') || item.path.contains('image_generation_logs')), isEmpty);
  });
  test('停止只阻止后续项，当前项结果仍保存', () async {
    final entered = Completer<void>(), release = Completer<void>();
    adapter.generate = (_) async { entered.complete(); await release.future; return adapter.json({'data': [{'b64_json': 'AQID'}]}); };
    final running = run(['第一项', '第二项']); await entered.future;
    container.read(generationProvider.notifier).stopBatch(); release.complete(); await running;
    expect(repository.saves, ['run-1']);
    expect(container.read(generationProvider).batch.last.status, BatchImageStatus.stopped);
    expect(adapter.runs, 1);
  });
  test('当前项完成保存前不提交下一项', () async {
    final entered = Completer<void>(), release = Completer<void>();
    repository.beforeSave = (output) async {
      if (output.runId == 'run-1') { entered.complete(); await release.future; }
    };
    final running = run(['第一项', '第二项']); await entered.future;
    expect(adapter.runs, 1);
    expect(container.read(generationProvider).batch.last.status, BatchImageStatus.queued);
    release.complete(); await running;
    expect(repository.saves, ['run-1', 'run-2']);
  });
  test('本机保存失败保留结果，再次保存不重新生成', () async {
    var writes = 0;
    repository.beforeSave = (_) async { if (++writes == 1) throw const ApiException('磁盘写入失败'); };
    await run(['第一项']);
    expect(container.read(generationProvider).hasUnsaved, isTrue);
    final generated = adapter.runs;
    await container.read(generationProvider.notifier).saveBatchItem(0);
    expect(adapter.runs, generated); expect(repository.saves, ['run-1', 'run-1']);
    expect(container.read(generationProvider).batch.single.status, BatchImageStatus.saved);
  });
  test('账号切换后迟到结果不落盘且不继续队列', () async {
    final entered = Completer<void>(), release = Completer<void>();
    adapter.generate = (_) async { entered.complete(); await release.future; return adapter.json({'data': [{'b64_json': 'AQID'}]}); };
    final running = run(['第一项', '第二项']); await entered.future;
    api.resetAccount('b'); release.complete(); await running;
    expect(repository.saves, isEmpty); expect(adapter.runs, 1);
  });
}
