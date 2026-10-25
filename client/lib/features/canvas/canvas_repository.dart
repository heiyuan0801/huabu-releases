import 'dart:convert';

import '../../core/api/api_client.dart';
import '../../core/models.dart';

Json copyCanvasJson(Json value) => jsonObject(jsonDecode(jsonEncode(value)));

bool _finite(Object? value) => value is num && value.isFinite;
bool _identifier(Object? value) => value is String && value.trim().isNotEmpty;
Never _invalidCanvas() => throw const ApiException('画布数据格式异常，已停止保存以保护原数据');

void validateCanvasProject(Object? value) {
  if (value is! Map || !_identifier(value['id']) || value['title'] is! String || value['nodes'] is! List || value['connections'] is! List) _invalidCanvas();
  final viewport = value['viewport'];
  if (viewport is! Map || !_finite(viewport['x']) || !_finite(viewport['y']) || !_finite(viewport['k']) || (viewport['k'] as num) <= 0) _invalidCanvas();
  final ids = <String>{}, connectionIds = <String>{};
  for (final node in value['nodes'] as List) {
    if (node is! Map || !_identifier(node['id']) || !ids.add(node['id'] as String) || !_identifier(node['type']) || node['title'] is! String) _invalidCanvas();
    final position = node['position'];
    if (position is! Map || !_finite(position['x']) || !_finite(position['y']) || !_finite(node['width']) || !_finite(node['height']) || (node['width'] as num) <= 0 || (node['height'] as num) <= 0) _invalidCanvas();
    final metadata = node['metadata'];
    if (metadata != null && metadata is! Map) _invalidCanvas();
    if (metadata is Map && ['text', 'image'].contains(node['type'])) {
      for (final field in ['content', 'prompt', 'storageKey', 'huabuLocalImageId']) {
        if (metadata.containsKey(field) && metadata[field] is! String) _invalidCanvas();
      }
    }
  }
  for (final connection in value['connections'] as List) {
    if (connection is! Map || !_identifier(connection['id']) || !connectionIds.add(connection['id'] as String) || !_identifier(connection['fromNodeId']) || !_identifier(connection['toNodeId']) || !ids.contains(connection['fromNodeId']) || !ids.contains(connection['toNodeId'])) _invalidCanvas();
  }
}

void _validateDocument(Json document) {
  if (document['version'] != 0) throw const ApiException('当前客户端不支持此画布数据版本，请更新客户端后再编辑');
  final state = document['state'];
  if (state is! Map || state['projects'] is! List || state['deletedProjects'] is! List) _invalidCanvas();
  final ids = <String>{};
  for (final project in state['projects'] as List) {
    validateCanvasProject(project);
    if (!ids.add((project as Map)['id'] as String)) _invalidCanvas();
  }
  final deletedIds = <String>{};
  for (final deleted in state['deletedProjects'] as List) {
    if (deleted is! Map || !_identifier(deleted['id']) || !deletedIds.add(deleted['id'] as String) || deleted['deletedAt'] is! String) _invalidCanvas();
  }
}

class CanvasDocument {
  const CanvasDocument(this.data, this.revision);
  final Json data;
  final String revision;
  List<Json> get projects => (jsonObject(data['state'])['projects'] as List).map((value) => copyCanvasJson(jsonObject(value))).toList();
}

/// Personal canvases use the same account document as the web client.
class CanvasRepository {
  CanvasRepository(this.api) : epoch = api.epoch;
  final ApiClient api;
  final int epoch;
  static const _key = 'infinite-canvas:canvas_store';

  void checkAccount() {
    api.assertEpoch(epoch);
    if (api.accountId.isEmpty) throw const ApiException('登录后使用创作画布');
  }

  Future<CanvasDocument> load() async {
    checkAccount();
    final record = await api.storageRead('app_state', _key);
    checkAccount();
    if (record == null) return const CanvasDocument({'state': {'projects': [], 'deletedProjects': []}, 'version': 0}, '0');
    if (record.blob || record.value is! String) throw const ApiException('画布数据格式异常，已停止保存以保护原数据');
    final raw = jsonDecode(record.value as String);
    if (raw is! Map) _invalidCanvas();
    final document = jsonObject(raw);
    _validateDocument(document);
    return CanvasDocument(document, record.revision);
  }

  Future<CanvasDocument> save(CanvasDocument current, List<Json> projects) async {
    checkAccount();
    final document = {...current.data, 'state': {...jsonObject(current.data['state']), 'projects': projects}};
    _validateDocument(document);
    final revision = await api.storageWrite('app_state', _key, jsonEncode(document), revision: current.revision);
    checkAccount();
    return CanvasDocument(copyCanvasJson(document), revision);
  }
}
