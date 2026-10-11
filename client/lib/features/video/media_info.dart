import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';

class VideoMedia extends MediaBytes {
  const VideoMedia({required super.bytes, required super.mimeType, required this.width, required this.height, required this.durationMs});
  final int width, height, durationMs;
}

Future<({int width, int height, int durationMs})> readMediaInfo(MediaBytes media, {bool requireVideo = false}) async {
  final root = await getTemporaryDirectory();
  final directory = await Directory('${root.path}/huabu-inspect-${const Uuid().v4()}').create();
  Player? player;
  try {
    final file = File('${directory.path}/reference.${media.mimeType.startsWith('audio/') ? 'audio' : 'video'}');
    await file.writeAsBytes(media.bytes);
    player = Player();
    final duration = player.stream.duration.firstWhere((duration) => duration > Duration.zero);
    final failure = player.stream.error.first.then<Duration>((_) => throw const ApiException('无法读取媒体文件，请核对原文件'));
    final reading = Future.any([duration, failure]);
    reading.ignore();
    await player.open(Media(file.path), play: false);
    final value = player.state.duration > Duration.zero ? player.state.duration : await reading;
    final track = player.state.tracks.video.where((track) => track.id != 'auto' && track.id != 'no' && track.albumart != true).firstOrNull;
    if (requireVideo && track == null) throw const ApiException('上游文件不含视频轨道，结果保留待核对');
    return (width: player.state.width ?? track?.w ?? 0, height: player.state.height ?? track?.h ?? 0, durationMs: value.inMilliseconds);
  } finally { await player?.dispose(); if (await directory.exists()) await directory.delete(recursive: true); }
}
