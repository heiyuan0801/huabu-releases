import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'generation_service.dart';

class GenerationState {
  const GenerationState({this.busy = false, this.saving = false, this.output, this.works = const [], this.error = '', this.runId = ''});
  final bool busy, saving;
  final GenerationOutput? output;
  final List<Artwork> works;
  final String error, runId;
}

final generationProvider = NotifierProvider<GenerationController, GenerationState>(GenerationController.new);
class GenerationController extends Notifier<GenerationState> {
  @override
  GenerationState build() {
    ref.watch(sessionProvider.select((value) => value.asData?.value?.id));
    return const GenerationState();
  }

  Future<void> generate(ImageModel model, {required String prompt, required String ratio, required int count, required String quality, required bool asynchronous, ImageReference? reference}) async {
    if (state.busy || state.saving) return;
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
    if (output == null || state.saving) return;
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
      state = GenerationState(output: output, runId: output.runId, error: '图片已生成，但作品保存未完成：${errorMessage(error)}');
    }
  }
}
