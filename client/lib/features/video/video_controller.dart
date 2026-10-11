import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../channels/channel_providers.dart';
import 'video_repository.dart';
import 'video_service.dart';

final videoWorksProvider = FutureProvider<List<VideoWork>>((ref) async {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  final api = ref.watch(apiProvider), epoch = ref.read(apiProvider).epoch;
  final user = await ref.read(sessionProvider.future);
  api.assertEpoch(epoch);
  if (user == null || !ref.mounted) throw const ApiException('登录后查看视频作品');
  return VideoRepository(api).works();
});

class VideoState {
  const VideoState({this.busy = false, this.saving = false, this.work, this.media, this.error = '', this.runId = ''});
  final bool busy, saving;
  final VideoWork? work;
  final MediaBytes? media;
  final String error, runId;
}

final videoGenerationProvider = NotifierProvider<VideoController, VideoState>(VideoController.new);
class VideoController extends Notifier<VideoState> {
  @override
  VideoState build() {
    ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
    return const VideoState();
  }

  bool _current(ApiClient api, int epoch) => ref.mounted && api.epoch == epoch;
  void newDraft() { if (!state.busy && !state.saving) state = const VideoState(); }

  Future<void> generate(VideoConfig config) async {
    if (state.busy || state.saving) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    state = const VideoState(busy: true);
    String runId = '';
    VideoWork? work;
    try {
      final target = await ref.read(modelApiTargetProvider(config.model).future);
      api.assertEpoch(epoch);
      final service = VideoService(api, target);
      service.validate(config);
      final started = await api.post('/generations', {'model': config.model.value, 'capability': 'video', 'source': target.source, 'requestedCount': 1, 'detail': {'prompt': config.prompt, 'size': config.ratio, 'seconds': '${config.seconds}'}});
      api.assertEpoch(epoch);
      runId = jsonString(started['id']);
      if (runId.isEmpty) throw const ApiException('服务器没有返回任务编号');
      await api.storageWrite('generation_contexts', runId, {'prompt': config.prompt, 'model': config.model.value, 'capability': 'video', ...config.parameters}, revision: '0');
      api.assertEpoch(epoch);
      work = await VideoRepository(api).begin(config, runId);
      api.assertEpoch(epoch);
      if (!_current(api, epoch)) return;
      state = VideoState(busy: true, work: work, runId: runId);
      final task = await service.submit(config, runId);
      api.assertEpoch(epoch);
      work = work.withTask(task);
      state = VideoState(busy: true, work: work, runId: runId);
      work = await VideoRepository(api).save(work);
      api.assertEpoch(epoch);
      state = VideoState(busy: true, work: work, runId: runId);
      ref.invalidate(videoWorksProvider);
      final media = await service.wait(task);
      api.assertEpoch(epoch);
      state = VideoState(work: work, media: media, runId: runId);
      await saveResult();
    } catch (error) {
      if (!_current(api, epoch)) return;
      if (error is VideoGenerationException && error.confirmedFailure && work != null) {
        work = work.withError(error.message, failed: true);
        try { work = await VideoRepository(api).save(work); } catch (_) {}
        if (!_current(api, epoch)) return;
      }
      state = VideoState(work: work ?? state.work, media: state.media, runId: runId, error: errorMessage(error));
    } finally {
      if (_current(api, epoch)) { ref.invalidate(creditsProvider); ref.invalidate(videoWorksProvider); }
    }
  }

  Future<void> resume(VideoWork work, ImageModel model) async {
    if (state.busy || state.saving) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    state = VideoState(busy: true, work: work, runId: work.runId);
    try {
      final target = await ref.read(modelApiTargetProvider(model).future);
      api.assertEpoch(epoch);
      MediaBytes media;
      if (work.url.isNotEmpty) {
        media = await (work.fileKey.isNotEmpty ? api.file(work.url) : target.media(work.url, runId: work.runId));
      } else {
        var task = work.task;
        if (task == null && work.runId.isNotEmpty) {
          final result = await api.get('/generations/${Uri.encodeComponent(work.runId)}');
          api.assertEpoch(epoch);
          final id = jsonString(result['taskId']);
          if (id.isNotEmpty) task = VideoTask(id: id, runId: work.runId, protocol: videoProtocol(model), model: model.value);
        }
        if (task == null) throw const ApiException('没有可恢复的上游任务编号，请在任务记录核对，不会重新提交生成');
        task = VideoTask(id: task.id, runId: task.runId, protocol: videoProtocol(model), model: model.value);
        media = await VideoService(api, target).wait(task);
        work = work.withTask(task);
      }
      api.assertEpoch(epoch);
      state = VideoState(work: work, media: media, runId: work.runId);
      if (work.status != 'success' || work.fileKey.isEmpty) await saveResult();
    } catch (error) {
      if (!_current(api, epoch)) return;
      if (error is VideoGenerationException && error.confirmedFailure) {
        work = work.withError(error.message, failed: true);
        try { work = await VideoRepository(api).save(work); } catch (_) {}
      }
      if (_current(api, epoch)) state = VideoState(work: work, error: errorMessage(error), runId: work.runId);
    } finally {
      if (_current(api, epoch)) { ref.invalidate(videoWorksProvider); ref.invalidate(creditsProvider); }
    }
  }

  Future<void> saveResult() async {
    if (state.saving || state.work == null || state.media == null) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final work = state.work!, media = state.media!;
    state = VideoState(saving: true, work: work, media: media, runId: work.runId);
    try {
      final saved = await VideoRepository(api).saveMedia(work, media);
      api.assertEpoch(epoch);
      if (!_current(api, epoch)) return;
      state = VideoState(work: saved, media: media, runId: work.runId);
      ref.invalidate(videoWorksProvider);
      if (work.runId.isNotEmpty) {
        try {
          await api.patch('/generations/${Uri.encodeComponent(work.runId)}', {'status': 'success', 'resultCount': 1, 'error': ''});
          api.assertEpoch(epoch);
        } catch (error) {
          if (_current(api, epoch)) state = VideoState(work: saved, media: media, runId: work.runId, error: '视频已保存，任务状态尚待核对：${errorMessage(error)}');
        }
      }
    } catch (error) {
      if (_current(api, epoch)) state = VideoState(work: work, media: media, runId: work.runId, error: '视频已取得，保存未完成：${errorMessage(error)}。可重试保存');
    }
  }
}
