import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../channels/channel_providers.dart';
import 'chat_models.dart';
import 'chat_service.dart';

class ChatPickedImage {
  const ChatPickedImage(this.media, this.name);
  final MediaBytes media;
  final String name;
}

// Keep unsaved replies for this account when the workspace leaves the screen.
final chatProvider = AsyncNotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends AsyncNotifier<ChatState> {
  static const _uuid = Uuid();
  ChatStore? _store;
  ChatStore get _activeStore => _store ?? (throw const ApiException('请先成功读取聊天记录'));

  @override
  Future<ChatState> build() async {
    _store?.dispose();
    _store = null;
    ref.watch(sessionProvider.select((value) => value.asData?.value?.id));
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final user = await ref.read(sessionProvider.future);
    api.assertEpoch(epoch);
    if (user == null || !ref.mounted) throw const ApiException('登录后使用 AI 聊天');
    final store = ChatStore(api);
    _store = store;
    ref.onDispose(() {
      store.dispose();
      if (identical(_store, store)) _store = null;
    });
    return store.read();
  }

  bool _current(ChatStore store) => ref.mounted && identical(store, _store) && store.live && store.api.epoch == store.epoch;
  void _publish(ChatStore store, ChatState next) { if (_current(store)) state = AsyncData(next); }
  ChatState _editable() {
    _activeStore.check();
    final current = state.asData?.value;
    if (current == null) throw const ApiException('请先成功读取聊天记录');
    if (current.busy) throw const ApiException('请等待当前操作完成');
    if (current.dirty) throw const ApiException('请先保存当前会话，或重新读取服务器记录');
    return current;
  }

  Future<ChatState> _save(ChatStore store, ChatState next) async {
    store.check();
    try {
      final revision = await store.save(next);
      final saved = next.copyWith(revision: revision, dirty: false, conflict: false, saveError: '');
      _publish(store, saved);
      return saved;
    } catch (error) {
      store.check();
      final conflict = error is ApiException && error.status == 409;
      _publish(store, next.copyWith(dirty: true, conflict: conflict, saveError: conflict ? '服务器记录已在其他设备更新。当前内容保留在内存，请复制需要的回复后重新读取。' : '保存失败：${errorMessage(error)}'));
      rethrow;
    }
  }

  Future<void> _change(ChatState next) async {
    final store = _activeStore;
    _publish(store, next.copyWith(busy: true));
    try { await _save(store, next.copyWith(busy: true)); }
    finally { if (_current(store)) _publish(store, state.requireValue.copyWith(busy: false)); }
  }

  Future<void> newSession() async {
    final current = _editable(), now = DateTime.now().millisecondsSinceEpoch;
    await _change(current.replaceSession(ChatSession(id: _uuid.v4(), title: '新对话', createdAt: now, updatedAt: now)));
  }

  Future<void> selectSession(String id) async {
    final current = _editable();
    if (current.sessions.any((item) => item.id == id)) await _change(current.copyWith(activeSessionId: id));
  }

  Future<void> deleteSession(String id) async {
    final current = _editable();
    final remaining = current.sessions.where((item) => item.id != id).toList();
    await _change(current.copyWith(sessions: remaining, activeSessionId: current.activeSessionId == id ? remaining.firstOrNull?.id ?? '' : current.activeSessionId));
  }

  Future<void> retrySave() async {
    final current = state.requireValue;
    if (current.busy || current.conflict || !current.dirty) return;
    await _change(current);
  }

  void stop({int? epoch}) {
    final store = _store;
    if (store != null && (epoch == null || store.epoch == epoch)) store.cancel();
  }

  Future<bool> send(String prompt, ImageModel model, List<ChatPickedImage> images) async {
    var next = _editable();
    if (prompt.trim().isEmpty) throw const ApiException('请先输入消息');
    final store = _activeStore;
    final token = store.token = CancelToken();
    _publish(store, next.copyWith(busy: true));
    var dispatched = false, runId = '', replyId = '', sessionId = '';
    try {
      final target = await ref.read(modelApiTargetProvider(model).future);
      store.check();
      if (token.isCancelled) throw const ApiException('操作已取消', canceled: true);
      final attachments = <ChatAttachment>[];
      for (final image in images) {
        store.check();
        if (token.isCancelled) throw const ApiException('操作已取消', canceled: true);
        final key = 'image:${_uuid.v4()}';
        await store.api.storageWrite('image_files', key, image.media.bytes, revision: '0', mimeType: image.media.mimeType);
        store.check();
        attachments.add(ChatAttachment(key: key, name: image.name, mimeType: image.media.mimeType));
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final session = next.active ?? ChatSession(id: _uuid.v4(), title: '新对话', createdAt: now, updatedAt: now);
      sessionId = session.id;
      replyId = _uuid.v4();
      final messages = [...session.messages,
        ChatMessage(id: _uuid.v4(), role: 'user', content: prompt.trim(), createdAt: now, attachments: attachments),
        ChatMessage(id: replyId, role: 'assistant', content: '', createdAt: now, status: 'pending', model: model.value, modelName: model.name),
      ];
      next = next.replaceSession(session.copyWith(title: session.messages.isEmpty ? prompt.trim().split('\n').first : session.title, model: model.value, messages: messages)).copyWith(busy: true);
      next = await _save(store, next);
      store.check();
      if (token.isCancelled) throw const ApiException('操作已取消', canceled: true);
      final runResponse = await store.api.request('/generations', method: 'POST', body: {'model': model.value, 'capability': 'text', 'source': target.source, 'requestedCount': 1, 'detail': {'prompt': prompt.trim()}}, cancelToken: token);
      store.check();
      runId = jsonString(jsonObject(runResponse.data)['id']);
      if (runId.isEmpty) throw const ApiException('服务器未返回任务编号，尚未发起模型请求');
      _replaceReply(store, sessionId, replyId, (reply) => reply.copyWith(runId: runId));
      store.check();
      await store.api.storageWrite('generation_contexts', runId, {'prompt': prompt.trim(), 'model': model.value, 'capability': 'text', 'size': '', 'quality': ''}, revision: '0');
      store.check();
      if (token.isCancelled) throw const ApiException('操作已取消', canceled: true);
      dispatched = true;
      await for (final update in store.stream(target, messages, runId)) {
        store.check();
        _replaceReply(store, sessionId, replyId, (reply) => reply.copyWith(content: update.text, status: update.status, notice: update.notice));
      }
      store.check();
      final reply = state.requireValue.active!.messages.last;
      if (reply.status == 'complete') {
        try {
          await store.api.patch('/generations/${Uri.encodeComponent(runId)}', {'status': 'success', 'resultCount': 1});
          store.check();
          if (ref.mounted) { ref.invalidate(taskPageProvider); ref.invalidate(creditsProvider); }
        } catch (_) {
          store.check();
          _replaceReply(store, sessionId, replyId, (value) => value.copyWith(notice: '回复已完成，任务状态回执未保存，请在任务记录核对'));
        }
      }
    } catch (error) {
      if (!_current(store)) return dispatched;
      final canceled = token.isCancelled || error is ApiException && error.canceled;
      final message = error is ChatStreamException ? error.message : error is FormatException ? '流数据无法读取，完成状态未确认，请在任务记录核对' : errorMessage(error);
      if (replyId.isNotEmpty) _replaceReply(store, sessionId, replyId, (reply) => reply.copyWith(status: dispatched ? canceled ? 'interrupted' : 'error' : 'not_sent', notice: dispatched ? canceled ? '已停止接收，收到的内容已保留；上游状态以任务记录为准' : message : '尚未发起模型请求。$message'));
      if (runId.isNotEmpty && error is ChatStreamException && error.confirmed) {
        try {
          store.check();
          await store.api.patch('/generations/${Uri.encodeComponent(runId)}', {'status': 'failed', 'resultCount': 0, 'error': message});
          store.check();
          ref.invalidate(taskPageProvider);
          ref.invalidate(creditsProvider);
        } catch (_) { if (!_current(store)) return dispatched; }
      }
      if (replyId.isEmpty) rethrow;
    } finally {
      if (_current(store)) {
        final current = state.requireValue;
        if (replyId.isNotEmpty && !current.dirty) {
          try { await _save(store, current.copyWith(busy: false)); }
          catch (_) { /* Preserve the response in memory; retrySave never repeats a model request. */ }
        }
        if (_current(store)) _publish(store, state.requireValue.copyWith(busy: false));
        if (identical(store.token, token)) store.token = null;
      }
    }
    return dispatched;
  }

  void _replaceReply(ChatStore store, String sessionId, String replyId, ChatMessage Function(ChatMessage) apply) {
    store.check();
    if (!_current(store)) return;
    final current = state.requireValue;
    final session = current.sessions.where((item) => item.id == sessionId).first;
    _publish(store, current.replaceSession(session.copyWith(messages: session.messages.map((message) => message.id == replyId ? apply(message) : message).toList())));
  }
}
