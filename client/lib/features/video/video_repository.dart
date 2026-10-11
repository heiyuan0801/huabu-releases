import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import 'media_info.dart';
import 'video_service.dart';

class VideoWork {
  const VideoWork(this.key, this.data);
  final String key;
  final Json data;
  String get id => jsonString(data['id']);
  String get runId => jsonString(data['runId']).isEmpty ? jsonString(jsonObject(jsonObject(data['task'])['generationRun'])['id']) : jsonString(data['runId']);
  String get prompt => jsonString(data['prompt']);
  String get title => jsonString(data['title']).isEmpty ? '视频作品' : jsonString(data['title']);
  String get model => jsonString(data['model']);
  String get status => jsonString(data['status']);
  String get fileKey => jsonString(jsonObject(data['video'])['storageKey']);
  String get url => fileKey.isEmpty ? jsonString(jsonObject(data['video'])['url']) : mediaFilePath(fileKey, video: true);
  DateTime get createdAt => jsonDate(data['createdAt']);
  VideoTask? get task {
    final value = jsonObject(data['task']);
    return jsonString(value['id']).isEmpty ? null : VideoTask.fromJson({...value, 'model': model, 'generationRun': {...jsonObject(value['generationRun']), 'id': runId}});
  }
  VideoWork withTask(VideoTask task) => VideoWork(key, {...data, 'task': task.toJson()});
  VideoWork withError(String error, {bool failed = false}) => VideoWork(key, {...data, 'error': error, 'status': failed ? 'failed' : 'pending'});
}

class VideoRepository {
  const VideoRepository(this.api);
  final ApiClient api;
  static const _uuid = Uuid();

  Future<List<VideoWork>> works() async {
    final epoch = api.epoch, keys = await api.storageKeys('video_generation_logs');
    final result = <VideoWork>[];
    for (final key in keys) {
      api.assertEpoch(epoch);
      final record = await api.storageRead('video_generation_logs', key);
      api.assertEpoch(epoch);
      if (record != null && !record.blob) result.add(VideoWork(key, jsonObject(record.value)));
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<VideoWork> begin(VideoConfig config, String runId) async {
    final epoch = api.epoch;
    final references = <Json>[], videos = <Json>[], audios = <Json>[];
    for (final item in config.references) {
      api.assertEpoch(epoch);
      final id = _uuid.v4(), key = '${item.kind}-reference:${_uuid.v4()}';
      await api.storageWrite(item.kind == 'image' ? 'image_files' : 'media_files', key, item.media.bytes, revision: '0', mimeType: item.media.mimeType);
      api.assertEpoch(epoch);
      final metadata = {'id': id, 'name': item.name, 'storageKey': key, 'bytes': item.media.bytes.length, 'mimeType': item.media.mimeType, 'type': item.media.mimeType, 'width': item.width, 'height': item.height, 'durationMs': item.durationMs, if (item.kind == 'image') 'dataUrl': '' else 'url': ''};
      (item.kind == 'image' ? references : item.kind == 'video' ? videos : audios).add(metadata);
    }
    final now = DateTime.now();
    final work = VideoWork(runId, {'id': runId, 'runId': runId, 'createdAt': now.millisecondsSinceEpoch, 'title': config.prompt, 'prompt': config.prompt, 'time': now.toIso8601String(), 'model': config.model.value, 'config': config.parameters, 'references': references, 'videoReferences': videos, 'audioReferences': audios, 'durationMs': 0, 'size': config.ratio, 'resolution': config.resolution, 'seconds': '${config.seconds}', 'status': 'pending'});
    await save(work);
    api.assertEpoch(epoch);
    return work;
  }

  Future<VideoWork> save(VideoWork work) async {
    final epoch = api.epoch;
    final previous = await api.storageRead('video_generation_logs', work.key);
    api.assertEpoch(epoch);
    if (previous != null && (previous.blob || previous.value is! Map)) throw const ApiException('视频记录格式异常，已停止覆盖');
    final old = jsonObject(previous?.value);
    if ((old.containsKey('video') && old['video'] is! Map) || ['references', 'videoReferences', 'audioReferences'].any((key) => old.containsKey(key) && old[key] is! List)) throw const ApiException('视频记录格式异常，已停止覆盖');
    // 已保存作品不能被迟到的查询结果降级。
    if (old['status'] == 'success' && work.status != 'success') return VideoWork(work.key, old);
    await api.storageWrite('video_generation_logs', work.key, {...old, ...work.data}, revision: previous?.revision ?? '0');
    api.assertEpoch(epoch);
    return work;
  }

  Future<VideoWork> saveMedia(VideoWork work, MediaBytes media, {int width = 0, int height = 0, int durationMs = 0}) async {
    if (media is VideoMedia) { width = media.width; height = media.height; durationMs = media.durationMs; }
    final epoch = api.epoch, key = 'video:${work.runId.isEmpty ? work.id : work.runId}';
    final previous = await api.storageRead('media_files', key);
    api.assertEpoch(epoch);
    if (previous == null) {
      await api.storageWrite('media_files', key, media.bytes, revision: '0', mimeType: media.mimeType);
    } else if (!previous.blob || sha256.convert(previous.value as List<int>) != sha256.convert(media.bytes)) {
      throw const ApiException('该任务已有不同的视频文件，已停止覆盖，请在作品记录核对');
    }
    api.assertEpoch(epoch);
    final oldVideo = jsonObject(work.data['video']);
    final next = VideoWork(work.key, {...work.data, 'status': 'success', 'error': '', 'video': {...oldVideo, 'id': jsonString(oldVideo['id']).isEmpty ? _uuid.v4() : oldVideo['id'], 'url': '', 'storageKey': key, 'bytes': media.bytes.length, 'mimeType': media.mimeType, 'width': width > 0 ? width : jsonInt(oldVideo['width']), 'height': height > 0 ? height : jsonInt(oldVideo['height']), 'durationMs': durationMs > 0 ? durationMs : jsonInt(oldVideo['durationMs']), 'prompt': work.prompt, 'model': work.model}});
    return save(next);
  }
}
