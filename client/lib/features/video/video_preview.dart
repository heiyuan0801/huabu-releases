import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class VideoPreview extends ConsumerStatefulWidget {
  const VideoPreview({required this.media, super.key});
  final MediaBytes media;
  @override
  ConsumerState<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends ConsumerState<VideoPreview> {
  Player? _player;
  VideoController? _controller;
  Directory? _directory;
  StreamSubscription<String>? _errors;
  int _operation = 0;
  Future<void> _opening = Future.value();
  bool _ready = false;
  String _error = '';

  @override
  void initState() { super.initState(); _open(); }

  @override
  void didUpdateWidget(VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.media, oldWidget.media)) { _ready = false; _error = ''; _open(); }
  }

  Future<void> _release() async {
    final player = _player, directory = _directory, errors = _errors;
    _player = null; _controller = null; _directory = null; _errors = null;
    try { await errors?.cancel(); await player?.dispose(); }
    finally { if (directory != null && await directory.exists()) await directory.delete(recursive: true); }
  }

  Future<void> _open() {
    final operation = ++_operation;
    _opening = _opening.catchError((Object _) {}).then((_) => _initialize(operation));
    return _opening;
  }

  Future<void> _initialize(int operation) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    bool current() => mounted && operation == _operation && api.epoch == epoch;
    Directory? pending;
    try {
      await _release();
      if (!current()) return;
      final root = await getTemporaryDirectory();
      if (!current()) return;
      pending = await Directory('${root.path}/huabu-preview-${const Uuid().v4()}').create();
      if (!current()) { await pending.delete(recursive: true); return; }
      _directory = pending;
      final extension = widget.media.mimeType == 'video/quicktime' ? 'mov' : widget.media.mimeType == 'video/webm' ? 'webm' : 'mp4';
      final file = File('${pending.path}/preview.$extension');
      await file.writeAsBytes(widget.media.bytes);
      if (!current()) { await _release(); return; }
      final player = Player();
      _player = player;
      _controller = VideoController(player);
      _errors = player.stream.error.listen((error) { if (current()) setState(() => _error = '视频无法解码，请下载原文件查看'); });
      await player.open(Media(file.path), play: false);
      if (!current()) { await _release(); return; }
      setState(() => _ready = true);
    } catch (_) {
      if (current()) setState(() => _error = '视频预览读取失败，请下载原文件查看');
      if (pending != null && _directory != pending && await pending.exists()) await pending.delete(recursive: true);
    }
  }

  @override
  void dispose() { ++_operation; unawaited(_release().catchError((Object _) {})); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((session) => session.asData?.value?.id), (previous, next) {
      if (previous != next) { ++_operation; _ready = false; unawaited(_release().catchError((Object _) {})); }
    });
    if (_error.isNotEmpty || !_ready || _controller == null || _player == null) {
      return ConstrainedBox(constraints: BoxConstraints(minHeight: AppLayout.isDesktop ? 280 : 210), child: _error.isNotEmpty
        ? StatePanel(title: '预览不可用', description: _error, icon: FLucideIcons.videoOff)
        : const StatePanel(title: '正在读取视频', loading: true));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg), child: StreamBuilder<VideoParams>(stream: _player!.stream.videoParams, initialData: _player!.state.videoParams, builder: (_, snapshot) {
          final ratio = snapshot.data?.aspect;
          return AspectRatio(aspectRatio: ratio != null && ratio > 0 ? ratio : 16 / 9, child: Video(controller: _controller!, fit: BoxFit.contain));
        }));
  }
}
