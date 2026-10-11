import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/providers.dart';
import '../channels/channel_providers.dart';
import 'media_info.dart';

class VideoReference {
  const VideoReference({required this.kind, required this.name, required this.media, this.width = 0, this.height = 0, this.durationMs = 0});
  final String kind, name;
  final MediaBytes media;
  final int width, height, durationMs;
  String get dataUrl => 'data:${media.mimeType};base64,${base64Encode(media.bytes)}';
}

class VideoConfig {
  const VideoConfig({required this.model, required this.prompt, required this.seconds, required this.ratio, required this.resolution, this.mode = 'generate', this.generateAudio = true, this.watermark = false, this.references = const []});
  final ImageModel model;
  final String prompt, ratio, resolution, mode;
  final int seconds;
  final bool generateAudio, watermark;
  final List<VideoReference> references;
  List<VideoReference> ofKind(String kind) => references.where((item) => item.kind == kind).toList();
  Json get parameters => {'model': model.value, 'videoModel': model.value, 'size': ratio, 'vquality': resolution, 'videoSeconds': '$seconds', 'grokVideoMode': mode, 'videoGenerateAudio': '$generateAudio', 'videoWatermark': '$watermark'};
}

String videoProtocol(ImageModel model) {
  if (model.apiFormat == 'ark') return 'seedance';
  if (model.apiFormat != 'openai' || model.model.toLowerCase().startsWith('firefly-')) return '';
  if (model.model.toLowerCase() == 'muse-video') return 'muse';
  if (model.model.toLowerCase().contains('grok') && model.model.toLowerCase().contains('video')) return 'grok';
  return 'openai';
}

String videoProtocolLabel(ImageModel model) => switch (videoProtocol(model)) {'muse' => 'Muse', 'grok' => 'Grok', 'seedance' => 'Seedance', 'openai' => 'OpenAI 兼容', _ => '当前协议尚不支持'};

class VideoTask {
  const VideoTask({required this.id, required this.runId, required this.protocol, required this.model});
  factory VideoTask.fromJson(Json value) => VideoTask(id: jsonString(value['id']), runId: jsonString(jsonObject(value['generationRun'])['id']), protocol: jsonString(value['protocol']).isNotEmpty ? jsonString(value['protocol']) : jsonString(value['provider']), model: jsonString(value['model']));
  final String id, runId, protocol, model;
  Json toJson() => {'id': id, 'provider': protocol == 'muse' ? 'openai' : protocol, 'protocol': protocol, 'model': model, 'generationRun': {'id': runId}};
}

class VideoGenerationException extends ApiException {
  const VideoGenerationException(super.message, {required this.runId, this.task, this.confirmedFailure = false, super.status, super.canceled});
  final String runId;
  final VideoTask? task;
  final bool confirmedFailure;
}

class VideoService {
  const VideoService(this.api, this.target);
  final ApiClient api;
  final ModelApiTarget target;

  void validate(VideoConfig config) {
    final protocol = videoProtocol(config.model);
    if (config.prompt.trim().isEmpty) throw const ApiException('请先填写视频提示词');
    if (config.model.capability != 'video' || protocol.isEmpty) throw const ApiException('该模型的视频协议尚未接入，请选择已支持模型');
    if (protocol == 'seedance') {
      if (config.seconds != -1 && (config.seconds < 4 || config.seconds > 15)) throw const ApiException('Seedance 时长为 4–15 秒，或选择自动');
      for (final kind in ['image', 'video', 'audio']) {
        final items = config.ofKind(kind), limit = kind == 'image' ? 9 : 3;
        if (items.length > limit) throw ApiException('Seedance 最多支持 $limit 个${kind == 'image' ? '参考图' : kind == 'video' ? '参考视频' : '参考音频'}');
        final maxBytes = (kind == 'image' ? 30 : kind == 'video' ? 200 : 15) * 1024 * 1024;
        if (items.any((item) => item.media.bytes.length > maxBytes)) throw ApiException('Seedance ${kind == 'image' ? '图片' : kind == 'video' ? '视频' : '音频'}超过现有文件限制');
        if (kind != 'image') {
          if (items.any((item) => item.durationMs != 0 && (item.durationMs < 2000 || item.durationMs > 15000)) || items.fold<int>(0, (sum, item) => sum + item.durationMs) > 15000) throw const ApiException('Seedance 参考视频与音频单项为 2–15 秒，同类合计不超过 15 秒');
        }
      }
      if (config.ofKind('audio').isNotEmpty && config.ofKind('image').isEmpty && config.ofKind('video').isEmpty) throw const ApiException('Seedance 参考音频需要同时提供参考图或视频');
      return;
    }
    if (config.seconds < 1 || config.seconds > 20) throw const ApiException('视频时长沿用现有 1–20 秒范围');
    if (config.ofKind('audio').isNotEmpty) throw const ApiException('该视频协议暂不支持参考音频，请移除后重试');
    if (protocol != 'grok' && config.ofKind('video').isNotEmpty) throw const ApiException('该视频协议暂不支持参考视频，请移除后重试');
    if ((protocol == 'muse' || protocol == 'grok') && config.ofKind('image').length > 1) throw const ApiException('当前协议仅支持一张首帧参考图');
    if (protocol == 'openai' && config.ofKind('image').length > 7) throw const ApiException('OpenAI 兼容协议沿用最多 7 张参考图');
    if (protocol == 'grok') {
      if (config.mode == 'generate' && config.ofKind('video').isNotEmpty) throw const ApiException('Grok 生成模式不支持参考视频，请选择剪辑或扩展');
      if (config.mode != 'generate' && (config.ofKind('video').length != 1 || config.ofKind('image').isNotEmpty)) throw const ApiException('Grok 剪辑与扩展需要一段参考视频，并移除参考图');
    }
  }

  Future<VideoTask> submit(VideoConfig config, String runId) async {
    final epoch = api.epoch, protocol = videoProtocol(config.model);
    api.assertEpoch(epoch);
    Object body;
    String path;
    if (protocol == 'muse') {
      path = '/v1/videos';
      body = {'model': config.model.model, 'prompt': config.prompt, 'duration': config.seconds, if (config.ratio != 'auto') 'size': config.ratio, if (config.resolution != 'auto') 'resolution': config.resolution, if (config.ofKind('image').isNotEmpty) 'reference_image': config.ofKind('image').first.dataUrl};
    } else if (protocol == 'grok') {
      path = '/v1/videos/${config.mode == 'edit' ? 'edits' : config.mode == 'extend' ? 'extensions' : 'generations'}';
      body = {'model': config.model.model, 'prompt': config.prompt, if (config.mode != 'edit') 'duration': config.seconds, if (config.mode != 'generate') 'video': {'url': config.ofKind('video').first.dataUrl}, if (config.mode == 'generate' && config.ofKind('image').isNotEmpty) 'image': {'url': config.ofKind('image').first.dataUrl}};
    } else if (protocol == 'seedance') {
      path = '/api/v3/contents/generations/tasks';
      body = {'model': config.model.model, 'content': [{'type': 'text', 'text': config.prompt}, for (final item in config.references) {'type': '${item.kind}_url', '${item.kind}_url': {'url': item.dataUrl}, 'role': 'reference_${item.kind}'}], 'ratio': config.ratio == 'auto' ? 'adaptive' : config.ratio, 'resolution': config.resolution == 'auto' ? '720p' : config.resolution, 'duration': config.seconds, 'generate_audio': config.generateAudio, 'watermark': config.watermark};
    } else {
      path = '/v1/videos';
      final form = FormData.fromMap({'model': config.model.model, 'prompt': config.prompt, 'seconds': '${config.seconds}', if (config.ratio != 'auto') 'size': config.ratio == '9:16' ? '720x1280' : '1280x720', 'resolution_name': config.resolution == 'auto' ? '720p' : config.resolution, 'preset': 'normal'});
      for (final image in config.ofKind('image')) { form.files.add(MapEntry('input_reference[]', MultipartFile.fromBytes(image.media.bytes, filename: image.name, contentType: DioMediaType.parse(image.media.mimeType)))); }
      body = form;
    }
    try {
      final response = _unwrap(await target.post(path, body, runId: runId));
      api.assertEpoch(epoch);
      final taskId = jsonString(response['request_id'] ?? response['id']);
      if (taskId.isEmpty) throw const ApiException('上游没有返回任务编号，结果需在任务记录核对');
      return VideoTask(id: taskId, runId: runId, protocol: protocol, model: config.model.value);
    } on ApiException catch (error) { throw VideoGenerationException(target.redact(error.message), runId: runId, status: error.status, canceled: error.canceled); }
  }

  Future<MediaBytes> wait(VideoTask task) async {
    final epoch = api.epoch;
    // 沿用 web/src/services/api/video.ts：Seedance 5秒，其余2.5秒，最多120次；只查询、不重新提交。
    for (var attempt = 0; attempt < 120; attempt++) {
      api.assertEpoch(epoch);
      final result = await query(task);
      api.assertEpoch(epoch);
      if (result != null) return result;
      if (attempt < 119) await Future<void>.delayed(Duration(milliseconds: task.protocol == 'seedance' ? 5000 : 2500));
    }
    throw VideoGenerationException('已达到现有视频查询次数，任务保留待核对，可手动继续查询', runId: task.runId, task: task);
  }

  Future<MediaBytes?> query(VideoTask task) async {
    final epoch = api.epoch;
    try {
      final path = task.protocol == 'seedance' ? '/api/v3/contents/generations/tasks/${Uri.encodeComponent(task.id)}' : '/v1/videos/${Uri.encodeComponent(task.id)}';
      final result = _unwrap(await target.get(path, runId: task.runId));
      api.assertEpoch(epoch);
      final status = jsonString(result['status']);
      if (['failed', 'cancelled', 'error', 'expired'].contains(status)) throw VideoGenerationException(_error(result['error']).isEmpty ? '上游已确认视频生成失败，请查看任务记录' : _error(result['error']), runId: task.runId, task: task, confirmedFailure: true);
      final video = jsonObject(result['video']), content = jsonObject(result['content']);
      final source = [jsonObject(result['result'])['url'], result['video_url'], result['result_url'], result['url'], video['url'], content['video_url'], content['url']].map(jsonString).where((item) => item.isNotEmpty).firstOrNull;
      final completed = ['done', 'completed', 'succeeded'].contains(status);
      if (source == null && !completed) return null;
      if (source == null && task.protocol != 'openai') throw const ApiException('上游显示完成但没有视频地址，结果保留待核对');
      final media = await target.media(source ?? '/v1/videos/${Uri.encodeComponent(task.id)}/content', runId: task.runId);
      api.assertEpoch(epoch);
      if (media.bytes.isEmpty || (!media.mimeType.startsWith('video/') && media.mimeType != 'application/octet-stream')) throw const ApiException('没有读取到有效视频文件，结果保留待核对');
      final info = await readMediaInfo(media, requireVideo: true);
      api.assertEpoch(epoch);
      return VideoMedia(bytes: media.bytes, mimeType: media.mimeType, width: info.width, height: info.height, durationMs: info.durationMs);
    } on VideoGenerationException catch (error) { throw VideoGenerationException(target.redact(error.message), runId: error.runId, task: error.task, confirmedFailure: error.confirmedFailure, status: error.status, canceled: error.canceled); }
    on ApiException catch (error) { throw VideoGenerationException(target.redact(error.message), runId: task.runId, task: task, status: error.status, canceled: error.canceled); }
  }

  Json _unwrap(Json value) {
    if (value.containsKey('code')) {
      if (value['code'] != 0 && value['code'] != '0') throw ApiException(_error(value).isEmpty ? '视频接口返回错误' : _error(value));
      final data = jsonObject(value['data']);
      if (data.isEmpty) throw const ApiException('视频接口没有返回任务数据');
      return data;
    }
    return value;
  }

  String _error(Object? value) => target.redact(value is String ? value : jsonString(jsonObject(value)['message'] ?? jsonObject(value)['msg'] ?? jsonObject(value)['error']));
}
