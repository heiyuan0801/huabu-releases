import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../generation/create_draft.dart';
import '../generation/generation_controller.dart';
import 'canvas_board.dart';
import 'canvas_controller.dart';
import 'canvas_editor.dart';

class CanvasPage extends ConsumerStatefulWidget {
  const CanvasPage({super.key});
  @override
  ConsumerState<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends ConsumerState<CanvasPage> {
  bool _creating = false, _pan = false, _additive = false, _importing = false, _dragging = false;
  Size _boardSize = const Size(800, 600);
  CanvasEditorController get editor => ref.read(canvasEditorProvider.notifier);
  bool _current(int epoch) => mounted && ref.read(apiProvider).epoch == epoch && GoRouter.of(context).routeInformationProvider.value.uri.path == '/canvas';
  Offset get _center {
    final view = jsonObject(ref.read(canvasEditorProvider).project?['viewport']);
    final k = canvasNumber(view['k'], 1);
    return Offset((_boardSize.width / 2 - canvasNumber(view['x'])) / k - 150, (_boardSize.height / 2 - canvasNumber(view['y'])) / k - 110);
  }
  Future<void> _create() async {
    final epoch = ref.read(apiProvider).epoch;
    var name = '';
    final title = await showFDialog<String>(context: context, builder: (context, style, animation) => FDialog(style: style, animation: animation,
      builder: (context, _) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
        Text('创建画布', style: context.theme.typography.display.lg),
        FTextField(autofocus: true, control: FTextFieldControl.managed(onChange: (value) => name = value.text), hint: '例如：新品视觉 / 角色设定 / 分镜灵感', onSubmit: (value) => Navigator.pop(context, value.trim())),
        FButton(onPress: () => Navigator.pop(context, name.trim()), child: const Text('创建')),
      ]))));
    if (!_current(epoch) || title == null) return;
    setState(() => _creating = true);
    try {
      final project = await ref.read(canvasProjectsProvider.notifier).createProject(title);
      if (_current(epoch)) editor.open(project);
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
    finally { if (_current(epoch)) setState(() => _creating = false); }
  }
  Future<bool> _discard() async {
    if (!ref.read(canvasEditorProvider).dirty) return true;
    return await showFDialog<bool>(context: context, builder: (context, style, animation) => FDialog(style: style, animation: animation,
      builder: (context, _) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [
        Text('画布还有未保存的修改', style: context.theme.typography.display.lg),
        const Text('返回编辑并保存，或放弃这次修改。图片原文件仍保留在本机。遇到保存冲突时，可先导出项目再重新读取。'),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, false), child: const Text('继续编辑')),
          FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, true), child: const Text('放弃修改')),
        ]),
      ])))) ?? false;
  }
  Future<void> _back() async {
    final epoch = ref.read(apiProvider).epoch;
    if (await _discard() && _current(epoch)) editor.close();
  }
  Future<void> _reload() async {
    final epoch = ref.read(apiProvider).epoch;
    if (await _discard() && _current(epoch)) { editor.close(); ref.invalidate(canvasProjectsProvider); }
  }
  Future<void> _import([List<XFile>? dropped]) async {
    if (_importing || ref.read(canvasEditorProvider).locked) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final id = ref.read(canvasEditorProvider).project?['id'], position = _center;
    setState(() => _importing = true);
    try {
      final files = dropped ?? await openFiles(acceptedTypeGroups: [const XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'], uniformTypeIdentifiers: ['public.image'])]);
      api.assertEpoch(epoch);
      for (var i = 0; i < files.length; i++) {
        if (!_current(epoch) || ref.read(canvasEditorProvider).project?['id'] != id) return;
        if (ref.read(canvasEditorProvider).locked) throw const ApiException('画布正在执行操作，已停止导入剩余图片');
        final bytes = await _readImport(files[i], epoch);
        api.assertEpoch(epoch);
        if (!_current(epoch) || ref.read(canvasEditorProvider).project?['id'] != id) return;
        if (ref.read(canvasEditorProvider).locked) throw const ApiException('画布正在执行操作，已停止导入剩余图片');
        final work = await ref.read(localImageStoreProvider).importImage(MediaBytes(bytes: bytes, mimeType: lookupMimeType(files[i].name, headerBytes: bytes) ?? 'application/octet-stream'), files[i].name);
        if (mounted && api.epoch == epoch) ref.invalidate(worksProvider);
        if (!_current(epoch) || ref.read(canvasEditorProvider).project?['id'] != id) return;
        if (ref.read(canvasEditorProvider).locked) throw const ApiException('图片已保存到本机作品，当前画布操作结束后可从本机作品添加');
        editor.addImage(work, position + Offset(i * 340, 0));
      }
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
    finally { if (_current(epoch)) setState(() => _importing = false); }
  }
  Future<Uint8List> _readImport(XFile file, int epoch) async {
    final bookmark = file is DropItem ? file.extraAppleBookmark : null;
    var accessed = false;
    try {
      if (bookmark != null) accessed = await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark);
      if (!_current(epoch)) throw const ApiException('图片导入已取消', canceled: true);
      return await file.readAsBytes();
    } finally { if (accessed && bookmark != null) await DesktopDrop.instance.stopAccessingSecurityScopedResource(bookmark: bookmark); }
  }
  Future<void> _pickWork() async {
    final epoch = ref.read(apiProvider).epoch, id = ref.read(canvasEditorProvider).project?['id'];
    final work = await showFDialog<Artwork>(context: context, builder: (context, style, animation) => FDialog(style: style, animation: animation,
      builder: (context, _) => SizedBox(width: 680, height: MediaQuery.sizeOf(context).height * .7, child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Column(spacing: AppSpace.lg, children: [
        Row(children: [Expanded(child: Text('从本机作品添加', style: context.theme.typography.display.lg)), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '关闭作品选择', onPress: () => Navigator.pop(context), child: const Icon(FLucideIcons.x, size: 18))]),
        Expanded(child: Consumer(builder: (context, ref, _) => ref.watch(worksProvider).when(
          loading: () => const StatePanel(title: '正在读取本机作品', loading: true),
          error: (error, _) => StatePanel(title: '本机作品读取失败', description: errorMessage(error), action: FButton(onPress: () => ref.invalidate(worksProvider), child: const Text('重新读取'))),
          data: (works) => works.isEmpty ? const StatePanel(title: '还没有本机图片', description: '先生成图片，或从电脑导入图片。') : LayoutBuilder(builder: (context, constraints) => GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: constraints.maxWidth < 440 ? 2 : 3, crossAxisSpacing: 12, mainAxisSpacing: 12), itemCount: works.length,
            itemBuilder: (context, index) => FButton.raw(onPress: () => Navigator.pop(context, works[index]), child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: ServerImage(works[index].imageUrl))),
          )),
        ))),
      ])))));
    if (_current(epoch) && id == ref.read(canvasEditorProvider).project?['id'] && work != null) editor.addImage(work, _center);
  }
  Future<void> _export() async {
    final project = ref.read(canvasEditorProvider).project;
    if (project == null) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final file = XFile.fromData(Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(project))), mimeType: 'application/json', name: 'huabu-canvas.json');
    try {
      if (AppLayout.isDesktop) {
        final location = await getSaveLocation(suggestedName: 'huabu-canvas.json');
        api.assertEpoch(epoch);
        if (location == null) return;
        await file.saveTo(location.path);
        if (mounted && _current(epoch)) toast(context, '已导出画布结构；图片原文件不包含在 JSON 中');
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: ['huabu-canvas.json'], sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
      }
    } catch (error) { if (mounted && _current(epoch)) toast(context, errorMessage(error)); }
  }
  void _zoom(double factor) {
    final view = jsonObject(ref.read(canvasEditorProvider).project?['viewport']);
    final old = canvasNumber(view['k'], 1), next = (old * factor).clamp(.1, 4.0);
    editor.setViewport({'k': next, 'x': _boardSize.width / 2 - (_boardSize.width / 2 - canvasNumber(view['x'])) * next / old,
      'y': _boardSize.height / 2 - (_boardSize.height / 2 - canvasNumber(view['y'])) * next / old});
  }
  void _fit() {
    final nodes = canvasNodes(ref.read(canvasEditorProvider).project);
    if (nodes.isEmpty) { editor.setViewport({'x': 0, 'y': 0, 'k': 1}); return; }
    Rect bounds(Json node) => canvasPosition(node) & Size(canvasNumber(node['width'], 300), canvasNumber(node['height'], 220));
    final rect = nodes.map(bounds).reduce((a, b) => a.expandToInclude(b));
    final k = ((_boardSize.width - 96) / rect.width).clamp(.1, 1.0).toDouble();
    final scale = k < (_boardSize.height - 96) / rect.height ? k : ((_boardSize.height - 96) / rect.height).clamp(.1, 1.0).toDouble();
    editor.setViewport({'k': scale, 'x': _boardSize.width / 2 - rect.center.dx * scale, 'y': _boardSize.height / 2 - rect.center.dy * scale});
  }
  Widget _tool(IconData icon, String label, VoidCallback? action, {bool selected = false}) => FButton.icon(
    variant: FButtonVariant.ghost, selected: selected, semanticsLabel: label, semanticsTooltip: label, onPress: action, child: Icon(icon, size: 18));
  void _connect() { try { editor.connectSelected(); } catch (error) { toast(context, errorMessage(error)); } }
  void _showInspector() {
    if (!AppLayout.isDesktop) {
      showFSheet(context: context, side: FLayout.btt, mainAxisMaxRatio: .85, useSafeArea: true,
        builder: (context) => SizedBox(height: MediaQuery.sizeOf(context).height * .75, child: const _CanvasInspector(inDialog: true)));
      return;
    }
    showFDialog<void>(context: context, builder: (context, style, animation) => FDialog(style: style, animation: animation,
      builder: (context, _) => SizedBox(width: 360, height: MediaQuery.sizeOf(context).height * .78, child: Column(children: [
        Align(alignment: Alignment.centerRight, child: _tool(FLucideIcons.x, '关闭参数面板', () => Navigator.pop(context))),
        const Expanded(child: _CanvasInspector(inDialog: true)),
      ]))));
  }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canvasEditorProvider), projects = ref.watch(canvasProjectsProvider);
    final project = state.project, colors = context.theme.colors;
    if (project == null) {
      return Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.xl, children: [
      Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.md, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('创作画布', style: context.theme.typography.display.xl2),
        FButton(mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.plus, size: 16), onPress: _creating || !projects.hasValue || projects.isLoading || projects.hasError ? null : _create, child: Text(_creating ? '正在创建…' : '新建画布')),
        _tool(FLucideIcons.refreshCw, '刷新画布列表', _creating ? null : () => ref.invalidate(canvasProjectsProvider)),
      ]),
      Text('把提示词、参考图与生成结果放在同一张画布上，自由编排你的创作。', style: context.theme.typography.body.sm.copyWith(color: colors.mutedForeground)),
      Expanded(child: projects.when(skipLoadingOnRefresh: false,
        loading: () => const StatePanel(title: '正在读取画布', loading: true),
        error: (error, _) => StatePanel(title: '画布读取失败', description: errorMessage(error), action: FButton(onPress: () => ref.invalidate(canvasProjectsProvider), child: const Text('重新读取'))),
        data: (items) => items.isEmpty ? StatePanel(title: '灵感，从一张空白画布开始', description: '添加文字、连接参考图，再将生成结果继续编排。', icon: FLucideIcons.workflow,
          action: FButton(mainAxisSize: MainAxisSize.min, onPress: _creating ? null : _create, child: const Text('创建第一张画布'))) : LayoutBuilder(builder: (context, constraints) => GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (constraints.maxWidth / 300).floor().clamp(1, 5).toInt(), childAspectRatio: 1.45, crossAxisSpacing: AppSpace.lg, mainAxisSpacing: AppSpace.lg),
          itemCount: items.length, itemBuilder: (context, index) {
            final item = items[index], nodes = canvasNodes(items[index]);
            return FButton.raw(onPress: _creating ? null : () => editor.open(item), child: Container(
              padding: const EdgeInsets.all(AppSpace.xl), decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: colors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(FLucideIcons.workflow, size: 30, color: colors.primary),
                Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
                  Text(jsonString(item['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.theme.typography.body.lg),
                  Text('${nodes.length} 个节点 · ${canvasConnections(item).length} 条连接', style: context.theme.typography.body.sm.copyWith(color: colors.mutedForeground)),
                ]),
              ]),
            ));
          },
        )),
      )),
      ]));
    }
    final mac = Platform.isMacOS;
    return CallbackShortcuts(bindings: {
      SingleActivator(LogicalKeyboardKey.keyS, meta: mac, control: !mac): editor.save,
      SingleActivator(LogicalKeyboardKey.keyZ, meta: mac, control: !mac): () { if (FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() == null) editor.undo(); },
      SingleActivator(LogicalKeyboardKey.keyZ, meta: mac, control: !mac, shift: true): () { if (FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() == null) editor.redo(); },
    }, child: Focus(child: Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm), child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 650;
        final actions = [
          _tool(FLucideIcons.undo2, '撤销', editor.canUndo ? editor.undo : null),
          _tool(FLucideIcons.redo2, '重做', editor.canRedo ? editor.redo : null),
          _tool(FLucideIcons.download, '导出项目结构', _export),
          _tool(FLucideIcons.refreshCw, '重新读取服务器画布', state.locked || _importing ? null : _reload),
        ];
        return Column(children: [Row(children: [
          _tool(FLucideIcons.arrowLeft, '返回项目', state.locked || _importing ? null : _back),
          Expanded(child: Text(jsonString(project['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w600))),
          if (state.dirty) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('未保存', style: context.theme.typography.body.xs.copyWith(color: colors.primary))),
          if (!narrow) ...actions,
          FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: state.dirty && !state.locked ? editor.save : null, child: Text(state.saving ? '保存中…' : '保存')),
        ]), if (narrow) Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: actions)))]);
      })),
      if (state.message.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text(state.message, style: context.theme.typography.body.xs))),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final sidePanel = AppLayout.isDesktop && constraints.maxWidth >= 940;
        return Row(children: [Expanded(child: LayoutBuilder(builder: (context, boardConstraints) {
          _boardSize = boardConstraints.biggest;
          return DropTarget(enable: AppLayout.isDesktop && !state.locked && !_importing && ModalRoute.of(context)?.isCurrent == true,
            onDragEntered: (_) => setState(() => _dragging = true), onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) { setState(() => _dragging = false); _import(details.files); }, child: Stack(children: [
            Positioned.fill(child: CanvasBoard(nodes: canvasNodes(project), connections: canvasConnections(project), selected: state.selected,
              viewport: jsonObject(project['viewport']), panMode: _pan, locked: state.locked || _importing,
              onSelect: (id) => editor.select(id, additive: _additive || HardwareKeyboard.instance.isShiftPressed),
              onViewport: editor.setViewport, onMove: editor.move, onMoveStart: editor.checkpoint,
              onAddText: editor.addText, onClearSelection: editor.clearSelection)),
            if (canvasNodes(project).isEmpty) Positioned.fill(child: IgnorePointer(child: Center(child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Column(mainAxisSize: MainAxisSize.min, spacing: AppSpace.md, children: [
              Icon(FLucideIcons.workflow, size: 40, color: colors.mutedForeground),
              Text('自由连接，让灵感成为作品', textAlign: TextAlign.center, style: context.theme.typography.display.lg),
              Text('双击空白添加提示词，或从下方导入图片', textAlign: TextAlign.center, style: context.theme.typography.body.sm.copyWith(color: colors.mutedForeground)),
            ]))))),
            if (_dragging) Positioned.fill(child: IgnorePointer(child: Container(decoration: BoxDecoration(color: colors.primary.withValues(alpha: .08), border: Border.all(color: colors.primary, width: 2)), child: const Center(child: Text('松开图片，保存到本机并加入画布'))))),
          ]));
        })), if (sidePanel) SizedBox(width: 300, child: DecoratedBox(decoration: BoxDecoration(border: Border(left: BorderSide(color: colors.border))), child: const _CanvasInspector()))]);
      })),
      Padding(padding: const EdgeInsets.all(AppSpace.sm), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: AppSpace.xs, children: [
        _tool(FLucideIcons.mousePointer2, '选择节点', () => setState(() => _pan = false), selected: !_pan),
        _tool(FLucideIcons.hand, '拖动画布', () => setState(() => _pan = true), selected: _pan),
        _tool(FLucideIcons.squareDashed, '多选节点', () => setState(() => _additive = !_additive), selected: _additive),
        _tool(FLucideIcons.type, '添加文字节点', state.locked ? null : () => editor.addText(_center)),
        _tool(FLucideIcons.imagePlus, '导入图片到本机', state.locked || _importing ? null : _import),
        _tool(FLucideIcons.images, '添加本机作品', state.locked ? null : _pickWork),
        _tool(FLucideIcons.link, '连接所选节点', state.locked || state.selected.length != 2 ? null : _connect),
        _tool(FLucideIcons.trash2, '移除所选文字或图片节点', state.locked || state.selected.isEmpty ? null : editor.removeSelected),
        _tool(FLucideIcons.minus, '缩小', state.locked ? null : () => _zoom(1 / 1.2)),
        Text('${(canvasNumber(jsonObject(project['viewport'])['k'], 1) * 100).round()}%', style: context.theme.typography.body.xs),
        _tool(FLucideIcons.plus, '放大', state.locked ? null : () => _zoom(1.2)),
        _tool(FLucideIcons.scan, '适应全部节点', state.locked ? null : _fit),
        _tool(FLucideIcons.slidersHorizontal, '节点与生成参数', _showInspector),
      ]))),
    ])));
  }
}

class _CanvasInspector extends ConsumerStatefulWidget {
  const _CanvasInspector({this.inDialog = false});
  final bool inDialog;
  @override
  ConsumerState<_CanvasInspector> createState() => _CanvasInspectorState();
}
class _CanvasInspectorState extends ConsumerState<_CanvasInspector> {
  String? _modelId;
  String _ratio = '1:1', _count = '1';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canvasEditorProvider), editor = ref.read(canvasEditorProvider.notifier);
    final nodes = canvasNodes(state.project), selection = nodes.where((node) => state.selected.contains(node['id'])).toList();
    final node = selection.length == 1 ? selection.single : null, data = jsonObject(selection.length == 1 ? selection.single['metadata'] : null);
    final queue = ref.watch(generationProvider), colors = context.theme.colors;
    return ListView(padding: const EdgeInsets.all(AppSpace.lg), children: [
      Text('节点与生成', style: context.theme.typography.display.lg), const SizedBox(height: AppSpace.lg),
      if (state.project != null) _CanvasField(key: ValueKey('${state.project!['id']}-title'), label: '画布名称', enabled: !state.locked,
        value: jsonString(state.project!['title']), onChange: (value) => editor.patch({'title': value})),
      const SizedBox(height: AppSpace.lg),
      if (selection.isEmpty) ...[
        Text('选中一个节点编辑，按住 Shift 或开启多选工具可选择多个节点。', style: context.theme.typography.body.sm.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: AppSpace.md), FButton(variant: FButtonVariant.ghost, onPress: editor.selectPrompts, child: const Text('选择全部文字节点')),
      ] else ...[
        Text(selection.length == 1 ? '${node!['type'] == 'text' ? '文字' : node['type'] == 'image' ? '图片' : '只读'}节点' : '已选择 ${selection.length} 个节点', style: context.theme.typography.body.md),
        const SizedBox(height: AppSpace.md),
        if (node != null && ['text', 'image'].contains(node['type'])) _CanvasField(key: ValueKey('${node['id']}-title'), label: '节点名称', enabled: !state.locked,
          value: jsonString(node['title']), onChange: (value) => editor.updateNode(node['id'] as String, {'title': value})),
        if (node?['type'] == 'text') ...[
          const SizedBox(height: AppSpace.md),
          _CanvasField(key: ValueKey('${node!['id']}-content'), label: '提示词 / 文本', multiline: true, enabled: !state.locked,
            value: jsonString(data['content']), onChange: (value) => editor.updateNode(node['id'] as String, {'metadata': {'content': value}})),
        ],
        if (node?['type'] == 'image') ...[
          const SizedBox(height: AppSpace.md), Text('连接到文字节点后，可作为生成参考图。图片原文件不会随画布结构上传。', style: context.theme.typography.body.sm.copyWith(color: colors.mutedForeground)),
        ],
        if (node != null && !['text', 'image'].contains(node['type'])) const Text('此类节点暂时只读，请在网页端编辑；保存时会保留原始内容。'),
        for (final connection in canvasConnections(state.project).where((c) => state.selected.contains(c['fromNodeId']) || state.selected.contains(c['toNodeId']))) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Row(children: [
          Expanded(child: Text('${jsonString(nodes.where((n) => n['id'] == connection['fromNodeId']).firstOrNull?['title'])} → ${jsonString(nodes.where((n) => n['id'] == connection['toNodeId']).firstOrNull?['title'])}', maxLines: 2, overflow: TextOverflow.ellipsis, style: context.theme.typography.body.xs)),
          FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '移除此连接', onPress: state.locked ? null : () => editor.disconnect(connection['id'] as String), child: const Icon(FLucideIcons.unlink, size: 15)),
        ])),
      ],
      const SizedBox(height: AppSpace.xl),
      Text('生成设置', style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w600)), const SizedBox(height: AppSpace.md),
      ref.watch(modelsProvider).when(
        loading: () => const Padding(padding: EdgeInsets.all(AppSpace.lg), child: FCircularProgress()),
        error: (error, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(errorMessage(error)), FButton(variant: FButtonVariant.ghost, onPress: () => ref.invalidate(modelsProvider), child: const Text('重新读取模型'))]),
        data: (all) {
          final models = all.where((m) => imageParameters(m).supported).toList();
          final model = models.where((m) => m.id == _modelId).firstOrNull ?? models.firstOrNull;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.md, children: [
            FSelect<String>(label: const Text('模型'), hint: '暂无可用生图模型', items: {for (final model in models) '${model.name} · ${model.providerName}': model.id}, enabled: !state.locked && models.isNotEmpty,
              control: FSelectControl.lifted(value: model?.id, onChange: (value) => setState(() => _modelId = value))),
            if (model != null && imageParameters(model).ratio) FSelect<String>(label: const Text('图片比例'), items: const {'自动': 'auto', '1:1': '1:1', '16:9': '16:9', '9:16': '9:16', '4:3': '4:3', '3:4': '3:4'}, enabled: !state.locked,
              control: FSelectControl.lifted(value: _ratio, onChange: (value) => setState(() => _ratio = value ?? '1:1'))),
            FSelect<String>(label: const Text('每条提示词图片数'), items: const {'1 张': '1', '2 张': '2', '4 张': '4'}, enabled: !state.locked,
              control: FSelectControl.lifted(value: _count, onChange: (value) => setState(() => _count = value ?? '1'))),
            Text('按选择逐项生成，失败继续，不自动重试。成功图片保存到本机后加入画布。', style: context.theme.typography.body.xs.copyWith(color: colors.mutedForeground)),
            FButton(prefix: const Icon(FLucideIcons.sparkles, size: 16), onPress: model == null || state.locked || queue.working || queue.hasUnsaved || !selection.any((n) => n['type'] == 'text') ? null : () async {
              try { await editor.generate(model, ratio: imageParameters(model).ratio ? _ratio : 'auto', count: int.parse(_count)); }
              catch (error) { if (context.mounted) toast(context, errorMessage(error)); }
            }, child: Text(state.generating ? '正在逐项生成…' : '生成所选文字节点')),
            if (state.generating && queue.batchRunning) ...[
              Text('已保存 ${queue.batch.where((i) => i.status == BatchImageStatus.saved || i.status == BatchImageStatus.partial).length} / ${queue.batch.length} 项', style: context.theme.typography.body.sm),
              FButton(variant: FButtonVariant.outline, onPress: queue.stopRequested ? null : ref.read(generationProvider.notifier).stopBatch, child: Text(queue.stopRequested ? '当前项完成后停止' : '停止后续任务')),
            ],
            FButton(variant: FButtonVariant.ghost, onPress: () { final router = GoRouter.of(context); if (widget.inDialog) Navigator.pop(context); router.go('/batch'); }, child: const Text('打开批量任务与结果')),
          ]);
        },
      ),
      const SizedBox(height: AppSpace.xl),
      Text('画布结构保存到账号。图片保存在当前设备；关闭应用前请保存画布，跨设备不会自动同步原图。', style: context.theme.typography.body.xs.copyWith(color: colors.mutedForeground)),
    ]);
  }
}

class _CanvasField extends StatefulWidget {
  const _CanvasField({required this.label, required this.value, required this.onChange, required this.enabled, this.multiline = false, super.key});
  final String label, value;
  final ValueChanged<String> onChange;
  final bool enabled, multiline;
  @override
  State<_CanvasField> createState() => _CanvasFieldState();
}
class _CanvasFieldState extends State<_CanvasField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  late String _lastText = widget.value;
  @override
  void didUpdateWidget(_CanvasField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastText = widget.value;
    if (_controller.text != widget.value) _controller.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FTextField(control: FTextFieldControl.managed(controller: _controller, onChange: (value) {
    if (value.text == _lastText) return;
    _lastText = value.text;
    widget.onChange(value.text);
  }),
    label: Text(widget.label), enabled: widget.enabled, minLines: widget.multiline ? 5 : 1, maxLines: widget.multiline ? 10 : 1,
    keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
    textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done);
}
