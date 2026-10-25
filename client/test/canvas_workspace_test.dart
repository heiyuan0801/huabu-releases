import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:huabu_app/core/providers.dart';
import 'package:huabu_app/core/theme.dart';
import 'package:huabu_app/features/canvas/canvas_controller.dart';
import 'package:huabu_app/features/canvas/canvas_editor.dart';
import 'package:huabu_app/features/canvas/canvas_page.dart';
import 'package:huabu_app/features/canvas/canvas_repository.dart';
import 'package:huabu_app/features/generation/generation_controller.dart';
import 'package:material_ui/material_ui.dart';

const _user = UserAccount(id: 'canvas-a', email: '', displayName: '', avatarUrl: '', role: 'user', status: 'active');
const _model = ImageModel(id: 'fixture', providerId: 'fixture', providerName: '测试渠道', model: 'gpt-image-1', displayName: '测试生图模型', apiFormat: 'openai', capability: 'image', creditCost: 0, value: 'managed:fixture::gpt-image-1');
Json _node(String id, {String type = 'text', Json? metadata}) => {
  'id': id, 'type': type, 'title': id, 'position': {'x': 80, 'y': 80}, 'width': 300, 'height': 220,
  'metadata': metadata ?? {'content': '初始提示词', 'extension': {'keep': true}},
};
Json _project(String id) => {
  'id': id, 'title': '测试画布 $id', 'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-01T00:00:00Z',
  'nodes': [_node('text-$id')], 'connections': [], 'viewport': {'x': 0, 'y': 0, 'k': 1},
  'chatSessions': [], 'activeChatId': null, 'backgroundMode': 'dots', 'showImageInfo': false,
  'extension': {'preserve': 'project'},
};
Json _document() => {
  'version': 0, 'extension': {'preserve': 'document'},
  'state': {'projects': [_project('one'), _project('two')], 'deletedProjects': [{'id': 'deleted', 'deletedAt': '2026-01-01T00:00:00Z'}], 'extension': {'preserve': 'state'}},
};

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'https://fixture.invalid/api') { resetAccount(_user.id); }
  Json document = _document();
  String revision = '7';
  Object? readError;
  bool conflict = false;
  int writes = 0;
  Completer<MediaBytes>? reference;
  @override
  Future<StorageRecord?> storageRead(String namespace, String key) async {
    expect(namespace, 'app_state'); expect(key, 'infinite-canvas:canvas_store');
    if (readError != null) throw readError!;
    return StorageRecord(value: jsonEncode(document), revision: revision, blob: false);
  }
  @override
  Future<String> storageWrite(String namespace, String key, Object? value, {required String revision, String? mimeType}) async {
    writes++;
    expect(namespace, 'app_state'); expect(key, 'infinite-canvas:canvas_store');
    expect(value, isA<String>()); expect(revision, this.revision);
    if (conflict) throw const ApiException('画布已被其他设备更新', status: 409);
    document = jsonObject(jsonDecode(value! as String));
    return this.revision = '${int.parse(revision) + 1}';
  }
  @override
  Future<MediaBytes> file(String source, {Map<String, dynamic>? headers}) async {
    if (reference == null) throw StateError('Unexpected media request');
    return reference!.future;
  }
}
class _Session extends SessionController {
  @override
  Future<UserAccount?> build() async => _user;
  void changeAccount() {
    ref.read(apiProvider).resetAccount('canvas-b');
    state = const AsyncData(UserAccount(id: 'canvas-b', email: '', displayName: '', avatarUrl: '', role: 'user', status: 'active'));
  }
}
class _Queue extends GenerationController {
  int calls = 0;
  @override
  GenerationState build() => const GenerationState();
  void startElsewhere() => state = const GenerationState(batchRunning: true, batch: [BatchImageItem(prompt: '其他页面的任务', status: BatchImageStatus.generating)]);
  @override
  Future<List<BatchImageItem>> generateBatch(ImageModel model, {required List<String> prompts, required String ratio, required int count, required String quality, required bool asynchronous, ImageReference? reference}) async {
    calls++;
    return [];
  }
}
ProviderContainer _container(_Api api) => ProviderContainer.test(retry: (count, error) => null, overrides: [
  apiProvider.overrideWith((ref) => api),
  sessionProvider.overrideWith(_Session.new),
  modelsProvider.overrideWith((ref) async => [_model]),
  generationProvider.overrideWith(_Queue.new),
  databaseProvider.overrideWith((ref) => throw StateError('Canvas tests must not open local preferences')),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late ProviderContainer container;
  setUp(() async { api = _Api(); container = _container(api); await container.read(sessionProvider.future); });
  tearDown(() { container.dispose(); api.close(); });

  test('保存项目保留其他项目、删除记录与未知字段，并只写本机图片标识', () async {
    final before = copyCanvasJson(api.document);
    final loaded = await container.read(canvasProjectsProvider.future);
    final project = copyCanvasJson(loaded.first);
    (project['nodes'] as List).add(_node('local-image', type: 'image', metadata: {
      'content': 'data:image/png;base64,AQID', 'huabuLocalImageId': 'local-id', 'storageKey': 'must-not-upload',
      'filePath': '/private/image.png', 'relativePath': 'image.png', 'bytes': [1, 2, 3], 'extension': {'preserve': true},
    }));
    await container.read(canvasProjectsProvider.notifier).saveProject(project);
    expect(api.writes, 1);
    expect(api.document['extension'], before['extension']);
    expect(api.document['state']['extension'], before['state']['extension']);
    expect(api.document['state']['deletedProjects'], before['state']['deletedProjects']);
    expect(api.document['state']['projects'][1], before['state']['projects'][1]);
    final saved = jsonObject(api.document['state']['projects'][0]['nodes'][1]['metadata']);
    expect(saved, {'content': '', 'huabuLocalImageId': 'local-id', 'localImageMissing': true, 'extension': {'preserve': true}});
    expect(container.read(canvasProjectsProvider.notifier).revision, '8');
  });

  test('409 后保留已加载项目，不自动覆盖或重复写，显式刷新后恢复', () async {
    final projects = await container.read(canvasProjectsProvider.future);
    api.conflict = true;
    final controller = container.read(canvasProjectsProvider.notifier);
    await expectLater(controller.saveProject({...projects.first, 'title': '本地修改'}), throwsA(isA<ApiException>()));
    expect(controller.conflicted, isTrue);
    expect(container.read(canvasProjectsProvider).requireValue, projects);
    await expectLater(controller.saveProject(projects.first), throwsA(isA<ApiException>()));
    expect(api.writes, 1);
    api.conflict = false;
    container.invalidate(canvasProjectsProvider);
    await container.read(canvasProjectsProvider.future);
    await container.read(canvasProjectsProvider.notifier).saveProject(projects.first);
    expect(api.writes, 2);
  });

  test('损坏节点和未知文档版本不能被当成空画布覆盖', () async {
    api.document['state']['projects'][0]['nodes'] = 'broken';
    await expectLater(CanvasRepository(api).load(), throwsA(isA<ApiException>()));
    api.document = _document()..['version'] = 99;
    await expectLater(CanvasRepository(api).load(), throwsA(isA<ApiException>()));
    expect(api.writes, 0);
  });

  test('读取失败后没有可写快照，不允许创建空文档覆盖', () async {
    api.readError = const ApiException('暂时断网');
    await expectLater(container.read(canvasProjectsProvider.future), throwsA(isA<ApiException>()));
    await expectLater(container.read(canvasProjectsProvider.notifier).createProject('不能保存'), throwsA(isA<ApiException>()));
    expect(api.writes, 0);
  });

  test('草稿撤销重做保留扩展数据，账号切换清空旧草稿', () async {
    final editor = container.read(canvasEditorProvider.notifier);
    editor.open(_project('one'));
    editor.updateNode('text-one', {'metadata': {'content': '新提示词'}});
    expect(canvasNodes(container.read(canvasEditorProvider).project).first['metadata']['extension'], {'keep': true});
    editor.undo();
    expect(canvasNodes(container.read(canvasEditorProvider).project).first['metadata']['content'], '初始提示词');
    editor.redo();
    expect(canvasNodes(container.read(canvasEditorProvider).project).first['metadata']['content'], '新提示词');
    (container.read(sessionProvider.notifier) as _Session).changeAccount();
    await container.pump();
    expect(container.read(canvasEditorProvider).project, isNull);
    expect(editor.canUndo, isFalse);
  });

  test('读取参考图期间其他页面启动队列，不附加他人批次或再生成', () async {
    final project = _project('one');
    (project['nodes'] as List).add(_node('reference', type: 'image', metadata: {'content': 'https://fixture.invalid/reference.png'}));
    project['connections'] = [{'id': 'reference-edge', 'fromNodeId': 'reference', 'toNodeId': 'text-one'}];
    final editor = container.read(canvasEditorProvider.notifier)..open(project)..select('text-one');
    api.reference = Completer<MediaBytes>();
    final generating = editor.generate(_model, ratio: '1:1', count: 1);
    await Future<void>.delayed(Duration.zero);
    final queue = container.read(generationProvider.notifier) as _Queue;
    queue.startElsewhere();
    api.reference!.complete(MediaBytes(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/png'));
    await generating;
    expect(queue.calls, 0);
    expect(canvasNodes(container.read(canvasEditorProvider).project), project['nodes']);
    expect(container.read(canvasEditorProvider).message, contains('其他页面已有生成任务'));
  });

  for (final scenario in [
    (name: '宽桌面浅色', platform: TargetPlatform.macOS, size: const Size(1280, 800), dark: false),
    (name: '窄桌面深色', platform: TargetPlatform.macOS, size: const Size(720, 480), dark: true),
    (name: '手机深色', platform: TargetPlatform.android, size: const Size(320, 640), dark: true),
  ]) {
    testWidgets('${scenario.name}画布布局与文字撤销无异常', (tester) async {
      debugDefaultTargetPlatformOverride = scenario.platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(() { debugDefaultTargetPlatformOverride = null; tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
      try {
      final editor = container.read(canvasEditorProvider.notifier)..open(_project('one'))..select('text-one');
      final router = GoRouter(initialLocation: '/canvas', routes: [
        GoRoute(path: '/canvas', builder: (_, _) => const FScaffold(childPad: false, child: CanvasPage())),
        GoRoute(path: '/batch', builder: (_, _) => const SizedBox.shrink()),
      ]);
      addTearDown(router.dispose);
      final theme = scenario.dark ? AppTheme.dark(touch: scenario.platform == TargetPlatform.android) : AppTheme.light(touch: false);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(
        routerConfig: router, theme: theme.toApproximateMaterialTheme(),
        localizationsDelegates: FLocalizations.localizationsDelegates, supportedLocales: FLocalizations.supportedLocales,
        builder: (context, child) => FTheme(data: theme, child: FToaster(child: FTooltipGroup(child: child!))),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (scenario.size.width > 1000) {
        await tester.enterText(find.byType(EditableText).at(2), '编辑中的提示词');
        await tester.pump();
        editor.undo();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(canvasNodes(container.read(canvasEditorProvider).project).first['metadata']['content'], '初始提示词');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      } finally { debugDefaultTargetPlatformOverride = null; }
    });
  }
}
