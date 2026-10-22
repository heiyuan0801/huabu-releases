import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/models.dart';
import '../channels/channel_providers.dart';

class GenerationOutput {
  const GenerationOutput({required this.runId, required this.run, required this.images, required this.prompt, required this.model, required this.ratio, required this.quality, required this.requestedCount, this.partial = false, this.notice = '', this.receivedAt});
  final String runId, prompt, model, ratio, quality, notice;
  final GenerationRun? run;
  final int requestedCount;
  final bool partial;
  final List<MediaBytes> images;
  final DateTime? receivedAt;
}

class GenerationException extends ApiException {
  const GenerationException(super.message, {required this.runId, super.status, super.canceled});
  final String runId;
}

class GenerationContextMissing extends GenerationException {
  const GenerationContextMissing({required super.runId, required this.prompt, required this.ratio, required this.quality})
    : super('任务缺少创作上下文，请填写当时使用的提示词、比例和质量后恢复');
  final String prompt, ratio, quality;
}

class GenerationService {
  const GenerationService(this.api);
  final ApiClient api;
  static const _sizes = {'1:1': ['1024x1024', '1536x1536', '2048x2048'], '3:4': ['1536x2048'], '4:3': ['2048x1536'], '9:16': ['1024x1792', '1536x2752'], '16:9': ['1792x1024', '2752x1536']};

  Future<GenerationOutput> generate(ImageModel model, {required String prompt, String ratio = '1:1', String quality = 'auto', int count = 1, ImageReference? reference, bool asynchronous = false}) async {
    if (prompt.trim().isEmpty) throw const ApiException('请先描述你想创作的画面');
    if (count < 1) throw const ApiException('图片数量必须是正整数');
    if (model.capability != 'image' || !['openai', 'gemini', 'ark'].contains(model.apiFormat)) throw const ApiException('当前客户端暂不支持该模型的图片接口');
    if (model.model.toLowerCase().startsWith('firefly-')) throw const ApiException('该模型使用自定义图片协议，请在网页端使用');
    final muse = model.model.toLowerCase() == 'muse-image';
    final grok = model.model.toLowerCase().contains('grok') && model.model.toLowerCase().contains('image');
    final supportsImageSize = model.model.toLowerCase().contains('gemini-3') || model.model.toLowerCase().contains('3.1') || model.model.toLowerCase().contains('3-pro');
    if (grok && reference != null && count != 1) throw const ApiException('Grok 参考图编辑每次只生成一张图片');
    if (asynchronous && (model.apiFormat != 'openai' || muse)) throw const ApiException('该模型没有标准异步图片接口，请使用同步生成');
    if (model.apiFormat != 'gemini' && !grok && !muse && ratio != 'auto') _size(ratio, quality);
    final epoch = api.epoch;
    final target = await resolveModelApiTarget(api, model);
    api.assertEpoch(epoch);
    // Existing server opt-in: redact media from receipts instead of archiving it.
    final begun = await api.post('/generations', {'model': model.value, 'capability': 'image', 'source': target.source, 'requestedCount': count, 'detail': {'prompt': prompt, 'size': ratio, 'quality': quality, 'n': count, 'resultStorage': 'browser'}});
    api.assertEpoch(epoch);
    final runId = jsonString(begun['id']);
    if (runId.isEmpty) throw const ApiException('服务器没有返回任务编号');
    final images = <MediaBytes>[];
    DateTime? receivedAt;
    GenerationRun? run;
    GenerationOutput output({bool partial = false, String notice = ''}) => GenerationOutput(runId: runId, run: run, images: images, prompt: prompt, model: model.value, ratio: ratio, quality: quality, requestedCount: count, partial: partial, notice: notice, receivedAt: receivedAt);
    try {
      await api.storageWrite('generation_contexts', runId, {'prompt': prompt, 'model': model.value, 'capability': 'image', 'size': ratio, 'quality': quality, 'requestedCount': count}, revision: '0');
      final requestCount = model.apiFormat == 'gemini' || model.model.toLowerCase() == 'muse-image' ? count : 1;
      for (var index = 0; index < requestCount; index++) {
        api.assertEpoch(epoch);
        Json payload;
        if (model.apiFormat == 'gemini') {
          payload = await target.post('/v1beta/models/${Uri.encodeComponent(model.model)}:generateContent', {'contents': [{'role': 'user', 'parts': [{'text': prompt}, if (reference != null) {'inlineData': {'mimeType': reference.mimeType, 'data': base64Encode(reference.bytes)}}]}], 'generationConfig': {'responseModalities': ['TEXT', 'IMAGE'], 'imageConfig': {if (ratio != 'auto') 'aspectRatio': ratio, if (supportsImageSize && quality != 'auto') 'imageSize': quality == 'high' ? '4K' : quality == 'medium' ? '2K' : '1K'}}}, runId: runId);
        } else {
          final body = <String, dynamic>{'model': model.model, 'prompt': prompt, 'n': requestCount == 1 ? count : 1, if (!grok) 'output_format': 'png', if (!RegExp('gpt-image', caseSensitive: false).hasMatch(model.model)) 'response_format': grok ? 'url' : 'b64_json', if (!grok && ratio != 'auto') 'size': muse ? ratio : _size(ratio, quality), if (!grok && !muse && quality != 'auto') 'quality': quality};
          if (muse && reference != null) body['reference_image'] = 'data:${reference.mimeType};base64,${base64Encode(reference.bytes)}';
          if (grok && reference != null) {
            body.remove('n');
            body['image'] = {'type': 'image_url', 'url': 'data:${reference.mimeType};base64,${base64Encode(reference.bytes)}'};
          }
          if (model.apiFormat == 'ark') {
            if (reference != null) body['image'] = ['data:${reference.mimeType};base64,${base64Encode(reference.bytes)}'];
            payload = await target.post('/v1/images/generations', body, runId: runId);
          } else if (reference != null && !muse && !grok) {
            final form = FormData.fromMap({...body, 'image': MultipartFile.fromBytes(reference.bytes, filename: reference.filename, contentType: DioMediaType.parse(reference.mimeType))});
            payload = await target.post('/v1/images/edits${asynchronous ? '/async' : ''}', form, runId: runId);
          } else {
            payload = await target.post('/v1/images/${reference != null && grok ? 'edits' : 'generations'}${asynchronous ? '/async' : ''}', body, runId: runId);
          }
          if (asynchronous) payload = await _pollImages(target, payload, epoch, runId);
        }
        api.assertEpoch(epoch);
        final sources = imageSources(payload);
        if (sources.isEmpty) {
          run = await status(runId);
          if (run.serverStatus == 'pending' || run.serverStatus == 'unknown') throw GenerationException('上游任务已受理或结果尚未确认，请在作品任务中手动核对；不会重复发起生成', runId: runId);
          throw GenerationException(run.message.isEmpty ? '模型没有返回当前客户端可读取的图片，请在任务记录核对' : run.message, runId: runId);
        }
        ApiException? downloadError;
        for (final source in sources) {
          api.assertEpoch(epoch);
          try {
            images.add(await target.media(source, runId: runId));
            receivedAt ??= DateTime.now();
            api.assertEpoch(epoch);
          } on ApiException catch (error) {
            api.assertEpoch(epoch);
            if (error.canceled) rethrow;
            downloadError ??= error;
          }
        }
        if (downloadError != null) throw downloadError;
      }
      await api.patch('/generations/$runId', {'status': 'success', 'resultCount': images.length, 'error': ''});
      api.assertEpoch(epoch);
      run = await status(runId);
      api.assertEpoch(epoch);
      return output(partial: images.length < count, notice: images.length < count ? '已取得部分图片，其余结果请在任务记录核对；服务器不备份新生成图片' : '');
    } on ApiException catch (error) {
      api.assertEpoch(epoch);
      if (images.isNotEmpty && !error.canceled) {
        return output(partial: true, notice: '已取得 ${images.length} 张图片，${error.message}。其余结果请在任务记录核对');
      }
      throw GenerationException(error.canceled ? error.message : '${error.message}。可在任务记录核对结果', runId: runId, status: error.status, canceled: error.canceled);
    }
  }

  Future<Json> _pollImages(ModelApiTarget target, Json created, int epoch, String runId) async {
    final taskId = jsonString(created['task_id'] ?? created['id']);
    if (taskId.isEmpty) throw GenerationException('异步图片接口没有返回任务编号，请手动核对', runId: runId);
    // 沿用 web/src/services/api/image.ts 的标准图片查询间隔与期限，不重发生成请求。
    final deadline = DateTime.now().add(const Duration(minutes: 30));
    for (;;) {
      api.assertEpoch(epoch);
      final task = await target.get('/v1/images/tasks/${Uri.encodeComponent(taskId)}', runId: runId);
      api.assertEpoch(epoch);
      if (task['status'] == 'completed') return task['result'] is Map ? jsonObject(task['result']) : {'data': [{'url': task['image_url']}]};
      if (task['status'] == 'failed') throw GenerationException('上游已确认图片生成失败，请查看任务记录', runId: runId);
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw GenerationException('已达到现有图片查询期限，保留待核对任务，请手动查询', runId: runId);
      await Future<void>.delayed(remaining < const Duration(seconds: 3) ? remaining : const Duration(seconds: 3));
    }
  }

  String _size(String ratio, String quality) {
    final sizes = _sizes[ratio];
    if (sizes == null) throw const ApiException('请选择当前客户端支持的图片比例');
    return quality == 'high' ? sizes.last : quality == 'medium' && sizes.length > 1 ? sizes[1] : sizes.first;
  }

  Future<GenerationRun> status(String runId) async => GenerationRun.fromJson(await api.get('/generations/${Uri.encodeComponent(runId)}/status'));
  Future<Json> readResult(String runId) => api.get('/generations/${Uri.encodeComponent(runId)}');
  Future<GenerationOutput> recover(String runId, {String? prompt, String? ratio, String? quality}) async {
    final epoch = api.epoch;
    final context = jsonObject((await api.storageRead('generation_contexts', runId))?.value);
    api.assertEpoch(epoch);
    final actualPrompt = prompt ?? jsonString(context['prompt']);
    final actualRatio = ratio ?? jsonString(context['size']);
    final actualQuality = quality ?? jsonString(context['quality']);
    if (actualPrompt.trim().isEmpty || actualRatio.trim().isEmpty) throw GenerationContextMissing(runId: runId, prompt: actualPrompt, ratio: actualRatio, quality: actualQuality);
    final result = await readResult(runId);
    api.assertEpoch(epoch);
    final run = await status(runId);
    api.assertEpoch(epoch);
    final responses = (result['responses'] as List? ?? []).map(jsonObject).toList();
    if (responses.isEmpty && result['response'] is Map) responses.add(jsonObject(result['response']));
    final sources = responses.expand(imageSources).toSet();
    if (sources.isEmpty) throw GenerationException(run.message.isEmpty ? '没有可恢复的图片。新任务仅保存到本机，服务器只提供任务状态，不备份图片；请检查本机保存目录' : run.message, runId: runId);
    final images = <MediaBytes>[];
    final target = await resolveModelValueApiTarget(api, run.model);
    api.assertEpoch(epoch);
    ApiException? downloadError;
    for (final source in sources) {
      api.assertEpoch(epoch);
      try {
        images.add(await target.media(source, runId: runId));
        api.assertEpoch(epoch);
      } on ApiException catch (error) {
        api.assertEpoch(epoch);
        if (error.canceled) rethrow;
        downloadError ??= error;
      }
    }
    if (images.isEmpty && downloadError != null) throw downloadError;
    final notice = downloadError == null ? '' : '已恢复 ${images.length} 张图片，${downloadError.message}。其余结果请稍后手动恢复';
    return GenerationOutput(runId: runId, run: run, images: images, prompt: actualPrompt, model: run.model, ratio: actualRatio, quality: actualQuality, requestedCount: run.requestedCount, partial: notice.isNotEmpty || images.length < run.requestedCount, notice: notice.isNotEmpty ? notice : images.length < run.requestedCount ? '已恢复部分成功图片，其余结果仍需核对' : '');
  }

  static List<String> imageSources(Json payload) {
    if (payload['result'] is Map) payload = jsonObject(payload['result']);
    final result = <String>[];
    final items = payload['data'] ?? payload['images'] ?? payload['results'];
    for (final value in items is List ? items : const []) {
      final image = jsonObject(value);
      if (jsonString(image['b64_json']).isNotEmpty) { result.add('data:image/png;base64,${image['b64_json']}'); }
      else if (jsonString(image['url']).isNotEmpty) { result.add(image['url'] as String); }
    }
    if (jsonString(payload['image_url']).isNotEmpty) result.add(payload['image_url'] as String);
    for (final value in payload['candidates'] as List? ?? []) {
      final candidate = jsonObject(value);
      for (final value in jsonObject(candidate['content'])['parts'] as List? ?? []) {
        final part = jsonObject(value);
        final inline = jsonObject(part['inlineData'] ?? part['inline_data']);
        final file = jsonObject(part['fileData'] ?? part['file_data']);
        if (jsonString(inline['data']).isNotEmpty) { result.add('data:${jsonString(inline['mimeType'] ?? inline['mime_type']).isEmpty ? 'image/png' : inline['mimeType'] ?? inline['mime_type']};base64,${inline['data']}'); }
        else if (jsonString(file['fileUri'] ?? file['file_uri']).isNotEmpty) { result.add((file['fileUri'] ?? file['file_uri']) as String); }
      }
    }
    return result.toSet().toList();
  }
}
