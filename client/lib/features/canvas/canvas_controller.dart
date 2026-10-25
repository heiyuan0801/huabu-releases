import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import 'canvas_repository.dart';

export 'canvas_repository.dart' show copyCanvasJson;

final canvasProjectsProvider = AsyncNotifierProvider<CanvasProjectsController, List<Json>>(CanvasProjectsController.new);

class CanvasProjectsController extends AsyncNotifier<List<Json>> {
  CanvasRepository? _repository;
  CanvasDocument? _document;
  int _generation = 0;
  bool _conflicted = false, _saving = false;
  bool get conflicted => _conflicted;
  bool get saving => _saving;
  String? get revision => _document?.revision;

  @override
  Future<List<Json>> build() async {
    ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
    final generation = ++_generation;
    _repository = null;
    _document = null;
    _conflicted = false;
    _saving = false;
    final user = await ref.read(sessionProvider.future);
    _check(generation);
    if (user == null) throw const ApiException('登录后使用创作画布');
    final repository = CanvasRepository(ref.read(apiProvider));
    final document = await repository.load();
    _check(generation);
    repository.checkAccount();
    _repository = repository;
    _document = document;
    return document.projects;
  }

  void _check(int generation) {
    if (!ref.mounted || generation != _generation) throw const ApiException('画布读取范围已变更，本次操作已取消', canceled: true);
  }

  Future<void> _write(List<Json> Function(List<Json>) update) async {
    final repository = _repository, document = _document, generation = _generation;
    _check(generation);
    if (repository == null || document == null) throw const ApiException('请先成功读取画布，再保存修改');
    repository.checkAccount();
    if (_conflicted) throw const ApiException('画布已在其他页面或设备更新，请保留当前草稿并重新加载后编辑', status: 409);
    if (_saving) throw const ApiException('画布正在保存，请等待完成后再操作');
    final projects = update(document.projects);
    _saving = true;
    try {
      final saved = await repository.save(document, projects);
      _check(generation);
      repository.checkAccount();
      _document = saved;
      state = AsyncData(saved.projects);
    } on ApiException catch (error) {
      if (ref.mounted && generation == _generation && error.status == 409) _conflicted = true;
      rethrow;
    } finally {
      if (ref.mounted && generation == _generation) _saving = false;
    }
  }

  Future<Json> createProject(String title) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final project = <String, dynamic>{
      'id': const Uuid().v4(), 'title': title.trim().isEmpty ? '未命名画布' : title.trim(),
      'createdAt': now, 'updatedAt': now, 'nodes': [], 'connections': [],
      'chatSessions': [], 'activeChatId': null, 'backgroundMode': 'dots',
      'showImageInfo': false, 'viewport': {'x': 0, 'y': 0, 'k': 1},
    };
    await _write((projects) => [project, ...projects]);
    return copyCanvasJson(project);
  }

  Future<void> saveProject(Json project) async {
    validateCanvasProject(project);
    final next = copyCanvasJson(project);
    for (final node in next['nodes'] as List) {
      if (node is! Map || node['metadata'] is! Map) continue;
      final metadata = node['metadata'] as Map;
      if (jsonString(metadata['huabuLocalImageId']).isEmpty) continue;
      // Only an opaque device reference belongs in the cloud document.
      metadata['content'] = '';
      metadata['localImageMissing'] = true;
      for (final key in ['storageKey', 'url', 'dataUrl', 'coverUrl', 'previewUrl', 'base', 'relativePath', 'filePath', 'path', 'bytes', 'base64', 'b64_json']) { metadata.remove(key); }
    }
    await _write((projects) {
      if (!projects.any((item) => item['id'] == next['id'])) throw const ApiException('画布已不存在，请重新读取列表');
      return [for (final item in projects) if (item['id'] == next['id']) {...item, ...next, 'updatedAt': DateTime.now().toUtc().toIso8601String()} else item];
    });
  }

  Future<void> renameProject(String id, String title) async {
    if (title.trim().isEmpty) throw const ApiException('请填写画布名称');
    await _write((projects) {
      if (!projects.any((item) => item['id'] == id)) throw const ApiException('画布已不存在，请重新读取列表');
      return [for (final item in projects) if (item['id'] == id) {...item, 'title': title.trim(), 'updatedAt': DateTime.now().toUtc().toIso8601String()} else item];
    });
  }
}
