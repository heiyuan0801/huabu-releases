import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'generation_service.dart';

class GenerationState {
  const GenerationState({this.busy = false, this.saving = false, this.output, this.works = const [], this.error = '', this.runId = '', this.batch = const [], this.batchRunning = false, this.stopRequested = false});
  final bool busy, saving;
  final GenerationOutput? output;
  final List<Artwork> works;
  final String error, runId;
  final List<BatchImageItem> batch;
  final bool batchRunning, stopRequested;
  bool get working => busy || saving || batchRunning;
  bool get hasUnsaved => output != null && works.isEmpty || batch.any((item) => item.status == BatchImageStatus.saveFailed);
}

enum BatchImageStatus { queued, generating, saving, saved, partial, saveFailed, failed, stopped }
class BatchImageItem {
  const BatchImageItem({required this.prompt, this.status = BatchImageStatus.queued, this.runId = '', this.error = '', this.works = const [], this.output});
  final String prompt, runId, error;
  final BatchImageStatus status;
  final List<Artwork> works;
  final GenerationOutput? output;
  String get label => switch (status) {
    BatchImageStatus.queued => '等待生成', BatchImageStatus.generating => '正在生成', BatchImageStatus.saving => '正在保存到本机',
    BatchImageStatus.saved => '已保存到本机', BatchImageStatus.partial => '部分结果已保存', BatchImageStatus.saveFailed => '图片已生成 · 保存失败',
    BatchImageStatus.failed => '未取得图片 · 请核对任务', BatchImageStatus.stopped => '未执行',
  };
}

final generationProvider = NotifierProvider<GenerationController, GenerationState>(GenerationController.new);
class GenerationController extends Notifier<GenerationState> {
  @override
  GenerationState build() {
    ref.watch(sessionProvider.select((value) => value.asData?.value?.id));
    return const GenerationState();
  }

  Future<void> generate(ImageModel model, {required String prompt, required String ratio, required int count, required String quality, required bool asynchronous, ImageReference? reference}) async {
    if (state.working || state.hasUnsaved) return;
    final api = ref.read(apiProvider);
    final epoch = api.epoch;
    state = const GenerationState(busy: true);
    try {
      final output = await GenerationService(api).generate(model, prompt: prompt, ratio: ratio, count: count, quality: quality, reference: reference, asynchronous: asynchronous);
      if (!ref.mounted || api.epoch != epoch) return;
      state = GenerationState(output: output, runId: output.runId);
      await saveOutput();
    } catch (error) {
      if (!ref.mounted || api.epoch != epoch) return;
      state = GenerationState(error: errorMessage(error), runId: error is GenerationException ? error.runId : '');
    } finally {
      if (ref.mounted && api.epoch == epoch) ref.invalidate(creditsProvider);
    }
  }

  Future<void> saveOutput() async {
    final output = state.output;
    if (output == null || state.working) return;
    final api = ref.read(apiProvider);
    final epoch = api.epoch;
    state = GenerationState(output: output, runId: output.runId, saving: true);
    try {
      final works = await ref.read(repositoryProvider).saveGeneration(output);
      if (!ref.mounted || api.epoch != epoch) return;
      ref.invalidate(worksProvider);
      state = GenerationState(output: output, runId: output.runId, works: works);
    } catch (error) {
      if (!ref.mounted || api.epoch != epoch) return;
      ref.invalidate(worksProvider);
      state = GenerationState(output: output, runId: output.runId, error: '图片已生成，但本机保存未完成：${errorMessage(error)}。请勿退出应用，可重新保存，不会再次生成');
    }
  }

  void _batchState(List<BatchImageItem> items, {bool? running, bool? stop}) {
    state = GenerationState(batch: List.unmodifiable(items), batchRunning: running ?? state.batchRunning, stopRequested: stop ?? state.stopRequested);
  }
  void stopBatch() {
    if (state.batchRunning) _batchState(state.batch, stop: true);
  }
  Future<void> generateBatch(ImageModel model, {required List<String> prompts, required String ratio, required int count, required String quality, required bool asynchronous, ImageReference? reference}) async {
    if (state.working || state.hasUnsaved || prompts.isEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final repository = ref.read(repositoryProvider);
    _batchState(prompts.map((prompt) => BatchImageItem(prompt: prompt)).toList(), running: true, stop: false);
    for (var index = 0; index < prompts.length; index++) {
      if (!ref.mounted || api.epoch != epoch) return;
      if (state.stopRequested) {
        _batchState([for (final item in state.batch) item.status == BatchImageStatus.queued ? BatchImageItem(prompt: item.prompt, status: BatchImageStatus.stopped) : item]);
        break;
      }
      void update(BatchImageItem item) {
        if (!ref.mounted || api.epoch != epoch) return;
        final items = [...state.batch]; items[index] = item; _batchState(items);
      }
      update(BatchImageItem(prompt: prompts[index], status: BatchImageStatus.generating));
      GenerationOutput? output;
      try {
        output = await GenerationService(api).generate(model, prompt: prompts[index], ratio: ratio, count: count, quality: quality, reference: reference, asynchronous: asynchronous);
        if (!ref.mounted || api.epoch != epoch) return;
        update(BatchImageItem(prompt: prompts[index], runId: output.runId, status: BatchImageStatus.saving));
        final works = await repository.saveGeneration(output);
        if (!ref.mounted || api.epoch != epoch) return;
        update(BatchImageItem(prompt: prompts[index], runId: output.runId, status: output.partial ? BatchImageStatus.partial : BatchImageStatus.saved, works: works, error: output.notice));
      } catch (error) {
        if (!ref.mounted || api.epoch != epoch) return;
        update(BatchImageItem(prompt: prompts[index], runId: output?.runId ?? (error is GenerationException ? error.runId : ''), status: output == null ? BatchImageStatus.failed : BatchImageStatus.saveFailed, output: output, error: errorMessage(error)));
      }
      if (!ref.mounted || api.epoch != epoch) return;
      ref.invalidate(worksProvider);
      ref.invalidate(creditsProvider);
    }
    if (ref.mounted && api.epoch == epoch) _batchState(state.batch, running: false);
  }

  Future<void> saveBatchItem(int index) async {
    if (state.working || index < 0 || index >= state.batch.length) return;
    final item = state.batch[index], output = state.batch[index].output;
    if (output == null || item.status != BatchImageStatus.saveFailed) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    void update(BatchImageItem value) { final items = [...state.batch]; items[index] = value; _batchState(items); }
    _batchState(state.batch, running: true);
    update(BatchImageItem(prompt: item.prompt, status: BatchImageStatus.saving, runId: item.runId, output: output));
    try {
      final works = await ref.read(repositoryProvider).saveGeneration(output);
      if (!ref.mounted || api.epoch != epoch) return;
      update(BatchImageItem(prompt: item.prompt, runId: item.runId, status: output.partial ? BatchImageStatus.partial : BatchImageStatus.saved, works: works, error: output.notice));
    } catch (error) {
      if (!ref.mounted || api.epoch != epoch) return;
      update(BatchImageItem(prompt: item.prompt, runId: item.runId, status: BatchImageStatus.saveFailed, output: output, error: errorMessage(error)));
    } finally {
      if (ref.mounted && api.epoch == epoch) { _batchState(state.batch, running: false); ref.invalidate(worksProvider); }
    }
  }
}
