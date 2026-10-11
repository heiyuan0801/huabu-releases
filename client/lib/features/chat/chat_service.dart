import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sse_parser/sse_parser.dart';

import '../../core/providers.dart';
import '../channels/channel_providers.dart';
import 'chat_models.dart';

class ChatStreamUpdate {
  const ChatStreamUpdate(this.text, {this.status = 'pending', this.notice = ''});
  final String text, status, notice;
}

class ChatStreamException implements Exception {
  const ChatStreamException(this.message, {this.confirmed = false});
  final String message;
  final bool confirmed;
}

/// A separate app_state key keeps text conversations independent of image chats and canvases.
class ChatStore {
  ChatStore(this.api) : epoch = api.epoch;
  static const namespace = 'app_state', key = 'infinite-canvas:ai_chat_store';
  final ApiClient api;
  final int epoch;
  bool live = true;
  CancelToken? token;
  void check() {
    api.assertEpoch(epoch);
    if (!live) throw const ApiException('操作已取消', canceled: true);
  }
  void cancel() { token?.cancel('已停止本次回复'); }
  void dispose() { live = false; cancel(); }

  Future<ChatState> read() async {
    check();
    final record = await api.storageRead(namespace, key);
    check();
    if (record == null) return const ChatState();
    if (record.blob || record.value is! String) throw const ApiException('聊天记录格式异常，已停止覆盖服务器数据');
    final decoded = jsonDecode(record.value as String);
    if (decoded is! Map || decoded['version'] != 0 || decoded['state'] is! Map) throw const ApiException('聊天记录版本无法读取，已保留原数据');
    final value = jsonObject(decoded['state']);
    if (value['sessions'] is! List || value['activeSessionId'] is! String) throw const ApiException('聊天记录损坏，已保留原数据');
    return ChatState(sessions: (value['sessions'] as List).map((item) => ChatSession.fromJson(jsonObject(item))).toList(), activeSessionId: value['activeSessionId'], revision: record.revision);
  }

  Future<String> save(ChatState state) async {
    check();
    final revision = await api.storageWrite(namespace, key, jsonEncode(state.toJson()), revision: state.revision);
    check();
    return revision;
  }

  String _safeMessage(ModelApiTarget target, String message) {
    final secret = target.channel?.apiKey ?? '';
    return secret.isEmpty ? message : message.replaceAll(secret, '[密钥已隐藏]');
  }

  Future<List<Json>> _input(List<ChatMessage> messages, bool gemini) async {
    final result = <Json>[];
    for (final message in messages) {
      if (message.role == 'assistant' && message.content.isEmpty) continue;
      if (!gemini && message.role == 'assistant') {
        result.add({'role': 'assistant', 'content': message.content});
        continue;
      }
      final parts = <Json>[];
      if (message.content.isNotEmpty) parts.add(gemini ? {'text': message.content} : {'type': 'input_text', 'text': message.content});
      for (final attachment in message.attachments) {
        check();
        final media = await api.file(attachment.source);
        check();
        parts.add(gemini ? {'inlineData': {'mimeType': media.mimeType, 'data': base64Encode(media.bytes)}} : {'type': 'input_image', 'image_url': UriData.fromBytes(media.bytes, mimeType: media.mimeType).toString()});
      }
      result.add(gemini ? {'role': message.role == 'assistant' ? 'model' : 'user', 'parts': parts} : {'role': message.role, 'content': parts});
    }
    return result;
  }

  String _responseText(Json response) {
    if (response['output_text'] is String) return response['output_text'];
    return (response['output'] as List? ?? []).where((item) => jsonObject(item)['type'] == 'message').expand((item) => jsonObject(item)['content'] as List? ?? []).map((item) { final value = jsonObject(item); return jsonString(value['type'] == 'refusal' ? value['refusal'] : value['text']); }).join();
  }

  Stream<ChatStreamUpdate> stream(ModelApiTarget target, List<ChatMessage> messages, String runId) async* {
    check();
    final gemini = target.apiFormat == 'gemini';
    if (!gemini && target.apiFormat != 'openai') throw const ApiException('该渠道未提供当前聊天支持的标准协议');
    final input = await _input(messages, gemini);
    check();
    if (token?.isCancelled ?? true) throw const ApiException('操作已取消', canceled: true);
    final model = target.model.model.replaceFirst(RegExp(r'^models/'), '');
    final response = await target.request(gemini ? '/v1beta/models/${Uri.encodeComponent(model)}:streamGenerateContent' : '/v1/responses', method: 'POST', body: gemini ? {'contents': input} : {'model': target.model.model, 'input': input, 'stream': true}, query: gemini ? {'alt': 'sse'} : null, headers: {'Accept': 'text/event-stream'}, runId: runId, responseType: ResponseType.stream, cancelToken: token);
    check();
    if (response.data is! ResponseBody) throw const ChatStreamException('接口没有返回可读取的流，请在任务记录核对');
    var text = '';
    await for (final event in (response.data as ResponseBody).stream.parseSse(allowMalformed: false)) {
      check();
      if (token!.isCancelled) throw const ApiException('操作已取消', canceled: true);
      if (event.data.trim().isEmpty) continue;
      if (event.data == '[DONE]') break;
      final decoded = jsonDecode(event.data);
      if (decoded is! Map) throw const ChatStreamException('流事件格式异常，回复完成状态未确认');
      final value = jsonObject(decoded), error = jsonObject(jsonObject(decoded)['error']);
      if (error.isNotEmpty) throw ChatStreamException(_safeMessage(target, jsonString(error['message']).isEmpty ? '上游返回错误，请在任务记录核对' : jsonString(error['message'])), confirmed: true);
      if (gemini) {
        final blocked = jsonString(jsonObject(value['promptFeedback'])['blockReason']);
        if (blocked.isNotEmpty && blocked != 'BLOCK_REASON_UNSPECIFIED') throw const ChatStreamException('上游拒绝了本次输入，请调整内容后重试', confirmed: true);
        final candidates = value['candidates'] as List? ?? [];
        if (candidates.isEmpty) continue;
        final candidate = jsonObject(candidates.first);
        for (final part in jsonObject(candidate['content'])['parts'] as List? ?? []) {
          if (jsonObject(part)['thought'] != true) text += jsonString(jsonObject(part)['text']);
        }
        final finish = jsonString(candidate['finishReason']);
        if (finish.isNotEmpty && finish != 'FINISH_REASON_UNSPECIFIED') {
          yield ChatStreamUpdate(text, status: finish == 'STOP' ? 'complete' : 'incomplete', notice: finish == 'STOP' ? text.isEmpty ? '上游已结束，但没有返回可显示的文本' : '' : finish == 'MAX_TOKENS' ? '上游已达到输出上限，当前为部分回复' : '上游提前结束回复（$finish），请在任务记录核对');
          return;
        }
      } else {
        final type = jsonString(value['type']);
        if (type == 'response.output_text.delta' || type == 'response.refusal.delta') text += jsonString(value['delta']);
        if (type == 'response.output_text.done' && text.isEmpty) text = jsonString(value['text']);
        if (type == 'response.refusal.done' && text.isEmpty) text = jsonString(value['refusal']);
        if (type == 'response.failed' || type == 'error') {
          final failure = jsonObject(jsonObject(value['response'])['error']);
          throw ChatStreamException(_safeMessage(target, jsonString(failure['message']).isEmpty ? jsonString(value['message']).isEmpty ? '上游生成失败，请在任务记录核对' : jsonString(value['message']) : jsonString(failure['message'])), confirmed: true);
        }
        if (type == 'response.completed' || type == 'response.incomplete') {
          final terminal = jsonObject(value['response']), finalText = _responseText(jsonObject(value['response']));
          if (finalText.isNotEmpty) text = finalText;
          final reason = jsonString(jsonObject(terminal['incomplete_details'])['reason']);
          yield ChatStreamUpdate(text, status: type == 'response.completed' ? 'complete' : 'incomplete', notice: type == 'response.completed' ? text.isEmpty ? '上游已结束，但没有返回可显示的文本' : '' : reason == 'max_output_tokens' ? '上游已达到输出上限，当前为部分回复' : '上游未完成回复，请在任务记录核对');
          return;
        }
      }
      yield ChatStreamUpdate(text);
    }
    throw const ChatStreamException('连接已结束，但未收到完成事件；已保留收到的内容，请在任务记录核对');
  }
}
