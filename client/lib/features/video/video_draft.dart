import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'video_service.dart';

class VideoDraft {
  const VideoDraft({this.prompt = '', this.modelId, this.seconds = '6', this.ratio = '16:9', this.resolution = '720p', this.mode = 'generate', this.audio = true, this.watermark = false, this.references = const []});
  final String prompt, seconds, ratio, resolution, mode;
  final String? modelId;
  final bool audio, watermark;
  final List<VideoReference> references;
}

final videoDraftProvider = NotifierProvider<VideoDraftController, VideoDraft>(VideoDraftController.new);
class VideoDraftController extends Notifier<VideoDraft> {
  @override
  VideoDraft build() {
    ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
    return const VideoDraft();
  }
  void setDraft(VideoDraft draft) => state = draft;
}

bool videoReferenceSupported(String protocol, String mode, String kind) => switch (protocol) {
  'seedance' => ['image', 'video', 'audio'].contains(kind),
  'grok' => kind == (mode == 'generate' ? 'image' : 'video'),
  'muse' || 'openai' => kind == 'image',
  _ => false,
};
