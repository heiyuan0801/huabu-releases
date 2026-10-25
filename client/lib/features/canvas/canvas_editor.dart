import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../generation/generation_controller.dart';
import '../generation/create_draft.dart';
import 'canvas_controller.dart';

List<Json> canvasNodes(Json? project) => (project?['nodes'] as List? ?? []).map(jsonObject).toList();
List<Json> canvasConnections(Json? project) => (project?['connections'] as List? ?? []).map(jsonObject).toList();
double canvasNumber(Object? value, [double fallback = 0]) => value is num && value.isFinite ? value.toDouble() : fallback;
Offset canvasPosition(Json node) => Offset(canvasNumber(jsonObject(node['position'])['x']), canvasNumber(jsonObject(node['position'])['y']));
String canvasImageSource(Json node) {
  final data = jsonObject(node['metadata']), local = jsonString(jsonObject(node['metadata'])['huabuLocalImageId']);
  if (local.isNotEmpty) return 'huabu-local:$local';
  final key = jsonString(data['storageKey']);
  var source = key.isNotEmpty ? mediaFilePath(key) : jsonString(data['content']);
  if (source.isEmpty && data['images'] is List) {
    final images = (data['images'] as List).map(jsonObject).toList();
    final image = images.where((item) => item['id'] == data['primaryImageId']).firstOrNull ?? images.firstOrNull;
    if (image != null) {
      final key = jsonString(image['storageKey']);
      source = key.isEmpty ? jsonString(image['content']) : mediaFilePath(key);
    }
  }
  return source;
}

class CanvasEditorState {
  const CanvasEditorState({this.project, this.selected = const {}, this.dirty = false, this.saving = false, this.generating = false, this.message = ''});
  final Json? project;
  final Set<String> selected;
  final bool dirty, saving, generating;
  final String message;
  bool get locked => saving || generating;
  CanvasEditorState copy({Json? project, Set<String>? selected, bool? dirty, bool? saving, bool? generating, String? message}) => CanvasEditorState(
    project: project ?? this.project, selected: selected ?? this.selected, dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving, generating: generating ?? this.generating, message: message ?? this.message);
}

// Keep unsaved edits while navigating to generation/results; reset on account change.
final canvasEditorProvider = NotifierProvider<CanvasEditorController, CanvasEditorState>(CanvasEditorController.new);
class CanvasEditorController extends Notifier<CanvasEditorState> {
  final _undo = <Json>[], _redo = <Json>[];
  int _editVersion = 0;
  @override
  CanvasEditorState build() {
    ref.watch(sessionProvider.select((value) => value.asData?.value?.id));
    _undo.clear(); _redo.clear(); _editVersion++;
    return const CanvasEditorState();
  }
  bool get canUndo => _undo.isNotEmpty && !state.locked;
  bool get canRedo => _redo.isNotEmpty && !state.locked;
  void open(Json project) {
    if (state.locked) return;
    _undo.clear(); _redo.clear();
    state = CanvasEditorState(project: copyCanvasJson(project));
  }
  void close() {
    if (state.locked) return;
    _undo.clear(); _redo.clear(); state = const CanvasEditorState();
  }
  void checkpoint() {
    if (state.project == null || state.locked) return;
    _undo.add(copyCanvasJson(state.project!)); _redo.clear();
  }
  void undo() {
    if (!canUndo) return;
    _redo.add(copyCanvasJson(state.project!));
    state = state.copy(project: _undo.removeLast(), selected: {}, dirty: true, message: '');
  }
  void redo() {
    if (!canRedo) return;
    _undo.add(copyCanvasJson(state.project!));
    state = state.copy(project: _redo.removeLast(), selected: {}, dirty: true, message: '');
  }
  void select(String id, {bool additive = false}) {
    final selected = additive ? {...state.selected} : <String>{};
    if (!additive || !selected.remove(id)) selected.add(id);
    state = state.copy(selected: selected);
  }
  void clearSelection() => state = state.copy(selected: {});
  void selectPrompts() => state = state.copy(selected: canvasNodes(state.project).where((n) => n['type'] == 'text').map((n) => n['id'] as String).toSet());
  void patch(Json fields, {bool history = true}) {
    if (state.project == null || state.locked) return;
    if (history) checkpoint();
    _editVersion++;
    state = state.copy(project: {...state.project!, ...fields}, dirty: true, message: '');
  }
  void setViewport(Json viewport) {
    if (state.project == null) return;
    _editVersion++;
    state = state.copy(project: {...state.project!, 'viewport': {...jsonObject(state.project!['viewport']), ...viewport}}, dirty: true);
  }
  void updateNode(String id, Json fields, {bool history = true}) => patch({'nodes': [for (final node in canvasNodes(state.project)) if (node['id'] == id) {...node, ...fields,
    if (fields.containsKey('metadata')) 'metadata': {...jsonObject(node['metadata']), ...jsonObject(fields['metadata'])},
    if (fields.containsKey('position')) 'position': {...jsonObject(node['position']), ...jsonObject(fields['position'])},
  } else node]}, history: history);
  void move(String id, Offset position) => updateNode(id, {'position': {'x': position.dx, 'y': position.dy}}, history: false);
  void addText(Offset position) {
    if (state.project == null || state.locked) return;
    final id = const Uuid().v4();
    patch({'nodes': [...canvasNodes(state.project), {'id': id, 'type': 'text', 'title': '提示词', 'position': {'x': position.dx, 'y': position.dy}, 'width': 300, 'height': 220, 'metadata': {'content': '', 'status': 'idle'}}]});
    select(id);
  }
  Json _imageNode(Artwork work, Offset position) => {
    'id': const Uuid().v4(), 'type': 'image', 'title': work.title.isEmpty ? '本机图片' : work.title,
    'position': {'x': position.dx, 'y': position.dy}, 'width': 300,
    'height': 300 * (work.width > 0 && work.height > 0 ? work.height / work.width : 1) + 42,
    'metadata': {'content': '', 'huabuLocalImageId': work.id, 'localImageMissing': true,
      'prompt': work.prompt, 'model': work.model, 'status': 'success', 'naturalWidth': work.width,
      'naturalHeight': work.height, 'mimeType': work.mimeType},
  };
  void addImage(Artwork work, Offset position) {
    if (state.project == null || state.locked || !work.imageUrl.startsWith('huabu-local:')) return;
    final node = _imageNode(work, position);
    patch({'nodes': [...canvasNodes(state.project), node]}); select(node['id'] as String);
  }
  void removeSelected() {
    final ids = canvasNodes(state.project).where((n) => state.selected.contains(n['id']) && ['text', 'image'].contains(n['type'])).map((n) => n['id']).toSet();
    if (ids.isEmpty) return;
    patch({'nodes': canvasNodes(state.project).where((n) => !ids.contains(n['id'])).toList(),
      'connections': canvasConnections(state.project).where((c) => !ids.contains(c['fromNodeId']) && !ids.contains(c['toNodeId'])).toList()});
    clearSelection();
  }
  void connectSelected() {
    if (state.selected.length != 2) throw const ApiException('先选择来源节点，再按住 Shift 选择目标文字节点');
    final from = state.selected.first, to = state.selected.last;
    final nodes = canvasNodes(state.project), connections = canvasConnections(state.project);
    if (!['text', 'image'].contains(nodes.firstWhere((n) => n['id'] == from)['type']) || nodes.firstWhere((n) => n['id'] == to)['type'] != 'text') throw const ApiException('将文字或图片连接到文字节点，用作提示词或参考图');
    if (connections.any((c) => c['fromNodeId'] == from && c['toNodeId'] == to)) return;
    final visited = <String>{}, pending = [to];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (id == from) throw const ApiException('这条连接会形成循环，请选择其他节点');
      if (visited.add(id)) pending.addAll(connections.where((c) => c['fromNodeId'] == id).map((c) => c['toNodeId'] as String));
    }
    patch({'connections': [...connections, {'id': const Uuid().v4(), 'fromNodeId': from, 'toNodeId': to}]});
  }
  void disconnect(String id) => patch({'connections': canvasConnections(state.project).where((c) => c['id'] != id).toList()});
  Future<void> save() async {
    if (state.project == null || state.locked || !state.dirty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final version = _editVersion;
    state = state.copy(saving: true, message: '');
    try {
      await ref.read(canvasProjectsProvider.notifier).saveProject(copyCanvasJson(state.project!));
      if (ref.mounted && api.epoch == epoch) state = state.copy(dirty: version != _editVersion, message: version == _editVersion ? '画布结构已保存，图片文件仍在本机' : '已保存提交时的画布；新的视图调整尚未保存');
    } catch (error) {
      if (ref.mounted && api.epoch == epoch) state = state.copy(message: errorMessage(error));
    } finally { if (ref.mounted && api.epoch == epoch) state = state.copy(saving: false); }
  }
  Future<void> generate(ImageModel model, {required String ratio, required int count}) async {
    final queue = ref.read(generationProvider);
    if (state.locked || queue.working || queue.hasUnsaved) throw const ApiException('请先完成当前生成，或到批量生图页重新保存未落盘的结果');
    final nodes = canvasNodes(state.project), connections = canvasConnections(state.project);
    final prompts = state.selected.map((id) => nodes.where((n) => n['id'] == id && n['type'] == 'text').firstOrNull).whereType<Json>().toList();
    if (prompts.isEmpty) throw const ApiException('请选择要生成的文字节点');
    final texts = <String>[], sources = <String>[];
    for (final node in prompts) {
      final upstream = connections.where((c) => c['toNodeId'] == node['id']).map((c) => nodes.where((n) => n['id'] == c['fromNodeId']).firstOrNull).whereType<Json>().toList();
      final text = [...upstream.where((n) => n['type'] == 'text').map((n) => jsonString(jsonObject(n['metadata'])['content'])), jsonString(jsonObject(node['metadata'])['content'])].where((s) => s.trim().isNotEmpty).join('\n');
      if (text.isEmpty) throw const ApiException('请先为每个选中的文字节点填写提示词');
      final images = upstream.where((n) => n['type'] == 'image').toList();
      if (images.length > 1) throw const ApiException('当前客户端每次使用一张参考图，请移除多余的图片连接');
      final source = images.isEmpty ? '' : canvasImageSource(images.single);
      if (images.isNotEmpty && source.isEmpty) throw const ApiException('参考图在本机不可用，请重新添加图片');
      texts.add(text); sources.add(source);
    }
    if (sources.toSet().length != 1) throw const ApiException('批量节点需共用同一张参考图；不同参考图请分别选择节点生成');
    if (sources.first.isNotEmpty && imageParameters(model).singleImageEdit && count != 1) throw const ApiException('当前模型参考图编辑每项只能生成一张，请将图片数改为 1');
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    checkpoint();
    state = state.copy(generating: true, message: '');
    try {
      ImageReference? reference;
      if (sources.first.isNotEmpty) {
        final media = await readArtworkMedia(ref, sources.first);
        api.assertEpoch(epoch);
        reference = ImageReference(bytes: media.bytes, mimeType: media.mimeType);
      }
      if (!ref.mounted || api.epoch != epoch) return;
      final latestQueue = ref.read(generationProvider);
      if (latestQueue.working || latestQueue.hasUnsaved) throw const ApiException('其他页面已有生成任务，请先完成当前队列');
      final items = await ref.read(generationProvider.notifier).generateBatch(model, prompts: texts, ratio: ratio, count: count, quality: 'auto', asynchronous: false, reference: reference);
      if (!ref.mounted || api.epoch != epoch) return;
      final resultNodes = [...canvasNodes(state.project)], resultConnections = [...canvasConnections(state.project)];
      for (var i = 0; i < items.length && i < prompts.length; i++) {
        final origin = canvasPosition(prompts[i]);
        var y = origin.dy;
        for (final work in items[i].works) {
          final node = _imageNode(work, Offset(origin.dx + canvasNumber(prompts[i]['width'], 300) + 100, y));
          // Place new results below any existing content in this result column.
          for (;;) {
            final bounds = canvasPosition(node) & Size(canvasNumber(node['width']), canvasNumber(node['height']));
            final overlaps = resultNodes.where((other) => bounds.overlaps(canvasPosition(other) & Size(canvasNumber(other['width']), canvasNumber(other['height'])))).toList();
            if (overlaps.isEmpty) break;
            y = overlaps.map((other) => canvasPosition(other).dy + canvasNumber(other['height']) + 24).reduce((a, b) => a > b ? a : b);
            node['position'] = {'x': canvasPosition(node).dx, 'y': y};
          }
          resultNodes.add(node);
          resultConnections.add({'id': const Uuid().v4(), 'fromNodeId': prompts[i]['id'], 'toNodeId': node['id']});
          y += canvasNumber(node['height']) + 24;
        }
      }
      final added = resultNodes.length - canvasNodes(state.project).length;
      state = state.copy(project: {...state.project!, 'nodes': resultNodes, 'connections': resultConnections}, dirty: state.dirty || added > 0,
        message: '已将 $added 张本机图片加入画布${items.any((i) => i.status == BatchImageStatus.saveFailed) ? '；部分图片保存失败，请到批量生图页仅重试保存，再从本机作品加入画布' : '，任务详情可在批量生图页查看'}');
    } catch (error) {
      if (ref.mounted && api.epoch == epoch) state = state.copy(message: errorMessage(error));
    } finally { if (ref.mounted && api.epoch == epoch) state = state.copy(generating: false); }
  }
}
