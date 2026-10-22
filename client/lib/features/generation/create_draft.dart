import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class ImageDraft {
  const ImageDraft({this.modelId, this.ratio = '1:1', this.quality = 'auto', this.count = '1', this.asynchronous = false, this.imageMode = false, this.batchMode = false, this.reference});
  final String? modelId;
  final String ratio, quality, count;
  final bool asynchronous, imageMode, batchMode;
  final ImageReference? reference;
}

final imageDraftProvider = NotifierProvider<ImageDraftController, ImageDraft>(ImageDraftController.new);
class ImageDraftController extends Notifier<ImageDraft> {
  @override
  ImageDraft build() {
    ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
    return const ImageDraft();
  }
  void setDraft(ImageDraft draft) => state = draft;
}

// Mirrors fields actually sent by GenerationService; the catalog has no finer capability flags.
({bool supported, bool ratio, bool quality, bool qualityAsSize, bool asynchronous, bool singleImageEdit}) imageParameters(ImageModel model) {
  final name = model.model.toLowerCase(), gemini = model.apiFormat == 'gemini';
  final muse = name == 'muse-image', grok = name.contains('grok') && name.contains('image');
  final supported = model.capability == 'image' && ['openai', 'gemini', 'ark'].contains(model.apiFormat) && !name.startsWith('firefly-');
  final imageSize = gemini && (name.contains('gemini-3') || name.contains('3.1') || name.contains('3-pro'));
  return (supported: supported, ratio: supported && (gemini || !grok), quality: supported && (gemini ? imageSize : !muse && !grok), qualityAsSize: imageSize, asynchronous: supported && model.apiFormat == 'openai' && !muse && !grok, singleImageEdit: grok);
}
