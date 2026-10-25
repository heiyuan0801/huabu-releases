import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Viewport-only transforms keep the scene unbounded without a giant widget.
class CanvasBoard extends StatefulWidget {
  const CanvasBoard({required this.nodes, required this.connections, required this.selected, required this.viewport, required this.panMode, required this.locked, required this.onSelect, required this.onViewport, required this.onMove, required this.onMoveStart, required this.onAddText, required this.onClearSelection, super.key});
  final List<Json> nodes, connections;
  final Set<String> selected;
  final Json viewport;
  final bool panMode, locked;
  final ValueChanged<String> onSelect;
  final ValueChanged<Json> onViewport;
  final void Function(String, Offset) onMove;
  final VoidCallback onMoveStart, onClearSelection;
  final ValueChanged<Offset> onAddText;

  @override
  State<CanvasBoard> createState() => _CanvasBoardState();
}

class _CanvasBoardState extends State<CanvasBoard> {
  final _focus = FocusNode(debugLabel: '创作画布');
  late Json _view;
  Json _startView = const {};
  Offset _startFocal = Offset.zero, _startNode = Offset.zero, _doubleTap = Offset.zero;
  double _startScale = 1;
  String? _dragId, _hoverId;
  bool _gesturing = false;

  @override
  void initState() { super.initState(); _view = _viewport(widget.viewport); }

  @override
  void didUpdateWidget(CanvasBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (['x', 'y', 'k'].any((key) => oldWidget.viewport[key] != widget.viewport[key])) _view = _viewport(widget.viewport);
    if (widget.locked && !oldWidget.locked) _dragId = null;
  }

  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  double get _scale => _number(_view['k'], 1);
  Offset get _translation => Offset(_number(_view['x']), _number(_view['y']));
  Offset _world(Offset screen) => (screen - _translation) / _scale;

  Json? _hit(Offset screen) {
    final point = _world(screen);
    for (final node in widget.nodes.reversed) {
      if (_nodeRect(node).contains(point)) return node;
    }
    return null;
  }

  void _setView(Json value) {
    setState(() => _view = value);
    widget.onViewport(value);
  }

  void _beginView(Offset focal, [double scale = 1]) {
    _startFocal = focal;
    _startView = Map.of(_view);
    _startScale = scale;
  }

  void _scaleStart(ScaleStartDetails details) {
    _focus.requestFocus();
    _beginView(details.localFocalPoint);
    final node = _hit(details.localFocalPoint);
    _dragId = !widget.locked && !widget.panMode && details.pointerCount == 1 && node != null && _editable(node)
        ? jsonString(node['id']) : null;
    if (_dragId != null) {
      _startNode = _nodeRect(node!).topLeft;
      if (!widget.selected.contains(_dragId)) widget.onSelect(_dragId!);
      widget.onMoveStart();
    }
    setState(() => _gesturing = true);
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    if (_dragId != null && details.pointerCount > 1) {
      _dragId = null;
      _beginView(details.localFocalPoint, details.scale);
      return;
    }
    if (_dragId != null) {
      if (!widget.locked) widget.onMove(_dragId!, _startNode + (details.localFocalPoint - _startFocal) / _number(_startView['k'], 1));
      return;
    }
    final startScale = _number(_startView['k'], 1);
    final scale = (startScale * details.scale / _startScale).clamp(.1, 4.0).toDouble();
    final anchor = (_startFocal - Offset(_number(_startView['x']), _number(_startView['y']))) / startScale;
    final translation = details.localFocalPoint - anchor * scale;
    _setView({'x': translation.dx, 'y': translation.dy, 'k': scale});
  }

  void _scroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _gesturing) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      final scroll = signal as PointerScrollEvent;
      final anchor = _world(scroll.localPosition);
      final scale = (_scale * math.exp(-scroll.scrollDelta.dy / 360)).clamp(.1, 4.0).toDouble();
      final translation = scroll.localPosition - anchor * scale;
      _setView({'x': translation.dx, 'y': translation.dy, 'k': scale});
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Focus(focusNode: _focus, child: LayoutBuilder(builder: (context, constraints) {
      final visible = Rect.fromLTWH(-_translation.dx / _scale, -_translation.dy / _scale, constraints.maxWidth / _scale, constraints.maxHeight / _scale).inflate(AppSpace.xl / _scale);
      return ClipRect(child: MouseRegion(
        cursor: _gesturing ? SystemMouseCursors.grabbing : widget.panMode ? SystemMouseCursors.grab : SystemMouseCursors.basic,
        onHover: (event) {
          final id = jsonString(_hit(event.localPosition)?['id']);
          if (id != _hoverId) setState(() => _hoverId = id);
        },
        onExit: (_) { if (_hoverId != null) setState(() => _hoverId = null); },
        child: Listener(onPointerSignal: _scroll, child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            _focus.requestFocus();
            final node = _hit(details.localPosition);
            if (node == null) { widget.onClearSelection(); } else { widget.onSelect(jsonString(node['id'])); }
          },
          onDoubleTapDown: (details) => _doubleTap = details.localPosition,
          onDoubleTap: () {
            _focus.requestFocus();
            if (!widget.locked && _hit(_doubleTap) == null) widget.onAddText(_world(_doubleTap));
          },
          onScaleStart: _scaleStart,
          onScaleUpdate: _scaleUpdate,
          onScaleEnd: (_) => setState(() { _dragId = null; _gesturing = false; }),
          child: ColoredBox(color: colors.background, child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BoardPainter(
              nodes: widget.nodes, connections: widget.connections, selected: widget.selected,
              translation: _translation, scale: _scale, gridColor: colors.border, lineColor: colors.mutedForeground, accent: colors.primary,
            )))),
            for (final node in widget.nodes)
              if (_nodeRect(node).overlaps(visible)) _positionedNode(context, node),
          ])),
        )),
      ));
    }));
  }

  Widget _positionedNode(BuildContext context, Json node) {
    final rect = _nodeRect(node), id = jsonString(node['id']);
    final position = rect.topLeft * _scale + _translation;
    return Positioned(key: ValueKey(id), left: position.dx, top: position.dy, width: rect.width * _scale, height: rect.height * _scale,
      child: MouseRegion(cursor: widget.panMode ? SystemMouseCursors.grab : !widget.locked && _editable(node) ? SystemMouseCursors.move : SystemMouseCursors.click,
        child: Semantics(label: '${jsonString(node['title'])}，${node['type'] == 'text' ? '文字' : node['type'] == 'image' ? '图片' : '只读'}节点', button: true, explicitChildNodes: true, selected: widget.selected.contains(id), onTap: () { _focus.requestFocus(); widget.onSelect(id); },
          child: FittedBox(fit: BoxFit.fill, alignment: Alignment.topLeft, child: SizedBox(width: rect.width, height: rect.height,
            child: _BoardNode(node: node, selected: widget.selected.contains(id), hovered: _hoverId == id),
          )),
        ),
      ),
    );
  }
}

double _number(Object? value, [double fallback = 0]) => value is num && value.isFinite ? value.toDouble() : fallback;
Json _viewport(Json value) => {'x': _number(value['x']), 'y': _number(value['y']), 'k': _number(value['k'], 1).clamp(.1, 4.0).toDouble()};
bool _editable(Json node) => node['type'] == 'text' || node['type'] == 'image';
Rect _nodeRect(Json node) {
  final position = jsonObject(node['position']);
  final width = _number(node['width'], 320), height = _number(node['height'], 240);
  return Rect.fromLTWH(_number(position['x']), _number(position['y']), width > 0 ? width : 320, height > 0 ? height : 240);
}

class _BoardNode extends StatelessWidget {
  const _BoardNode({required this.node, required this.selected, required this.hovered});
  final Json node;
  final bool selected, hovered;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors, typography = context.theme.typography;
    final metadata = jsonObject(node['metadata']);
    final type = jsonString(node['type']), title = jsonString(node['title']);
    final status = jsonString(metadata['status']);
    final localId = jsonString(metadata['huabuLocalImageId']);
    final key = jsonString(metadata['storageKey']);
    var source = localId.isNotEmpty ? 'huabu-local:$localId' : key.isNotEmpty ? mediaFilePath(key) : jsonString(metadata['content']);
    if (type == 'image' && source.isEmpty && metadata['images'] is List) {
      final images = (metadata['images'] as List).map(jsonObject).toList();
      if (images.isNotEmpty) {
        final image = images.firstWhere((image) => image['id'] == metadata['primaryImageId'], orElse: () => images.first);
        final imageKey = jsonString(image['storageKey']);
        source = imageKey.isNotEmpty ? mediaFilePath(imageKey) : jsonString(image['content']);
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: selected ? colors.primary : hovered ? colors.mutedForeground : colors.border, width: selected ? 2 : 1)),
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(AppSpace.md), child: Row(spacing: AppSpace.sm, children: [
          Icon(type == 'text' ? FLucideIcons.type : type == 'image' ? FLucideIcons.image : FLucideIcons.box, size: 15, color: selected ? colors.primary : colors.mutedForeground),
          Expanded(child: Text(title.isEmpty ? type == 'text' ? '文字' : type == 'image' ? '图片' : '只读节点' : title, maxLines: 1, overflow: TextOverflow.ellipsis, style: typography.body.sm.copyWith(fontWeight: FontWeight.w600))),
          if (localId.isNotEmpty) Icon(FLucideIcons.hardDrive, size: 14, color: colors.mutedForeground),
          if (status == 'loading') const SizedBox(width: 14, height: 14, child: FCircularProgress()),
          if (status == 'error') Icon(FLucideIcons.circleAlert, size: 14, color: colors.destructive),
        ])),
        Expanded(child: type == 'image'
          ? source.isNotEmpty && !source.startsWith('blob:')
            ? ServerImage(source, fit: BoxFit.contain, thumbnail: true)
            : Center(child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(source.startsWith('blob:') ? '此图片仅在原浏览器可用' : '图片尚未载入，请重新添加图片', textAlign: TextAlign.center, style: typography.body.sm.copyWith(color: colors.mutedForeground))))
          : type == 'text'
            ? Padding(padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg), child: ClipRect(child: Text(jsonString(metadata['content']).isEmpty ? '选中节点，在面板中写下创意…' : jsonString(metadata['content']), style: typography.body.sm.copyWith(color: jsonString(metadata['content']).isEmpty ? colors.mutedForeground : colors.foreground), overflow: TextOverflow.fade)))
            : Center(child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text('此类型暂为只读\n请在网页版编辑', textAlign: TextAlign.center, style: typography.body.sm.copyWith(color: colors.mutedForeground)))),
        ),
      ])),
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({required this.nodes, required this.connections, required this.selected, required this.translation, required this.scale, required this.gridColor, required this.lineColor, required this.accent});
  final List<Json> nodes, connections;
  final Set<String> selected;
  final Offset translation;
  final double scale;
  final Color gridColor, lineColor, accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    var spacing = AppSpace.xl * scale;
    while (spacing < AppSpace.lg) { spacing *= 2; }
    final grid = Paint()..color = gridColor;
    for (var x = translation.dx % spacing; x < size.width; x += spacing) {
      for (var y = translation.dy % spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), .8, grid);
      }
    }
    final byId = {for (final node in nodes) jsonString(node['id']): node};
    for (final connection in connections) {
      final fromId = jsonString(connection['fromNodeId']), toId = jsonString(connection['toNodeId']);
      final from = byId[fromId], to = byId[toId];
      if (from == null || to == null) continue;
      final start = _nodeRect(from).centerRight * scale + translation;
      final end = _nodeRect(to).centerLeft * scale + translation;
      final bend = math.max(AppSpace.xxl * scale, (end.dx - start.dx).abs() / 2);
      final path = Path()..moveTo(start.dx, start.dy)..cubicTo(start.dx + bend, start.dy, end.dx - bend, end.dy, end.dx, end.dy);
      final active = selected.contains(fromId) || selected.contains(toId);
      final stroke = Paint()
        ..color = active ? accent.withValues(alpha: .8) : lineColor.withValues(alpha: .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2 : 1.3;
      canvas.drawPath(path, stroke);
      canvas.drawCircle(start, 3, Paint()..color = active ? accent : lineColor);
      canvas.drawCircle(end, 3, Paint()..color = active ? accent : lineColor);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) => oldDelegate.nodes != nodes || oldDelegate.connections != connections || oldDelegate.selected != selected || oldDelegate.translation != translation || oldDelegate.scale != scale || oldDelegate.gridColor != gridColor || oldDelegate.lineColor != lineColor || oldDelegate.accent != accent;
}
