import '../../core/models.dart';

class ChatAttachment {
  const ChatAttachment({required this.key, required this.name, required this.mimeType});
  factory ChatAttachment.fromJson(Json value) {
    if (value['key'] is! String || value['name'] is! String || value['mimeType'] is! String) throw const FormatException('聊天附件格式异常');
    return ChatAttachment(key: value['key'], name: value['name'], mimeType: value['mimeType']);
  }
  final String key, name, mimeType;
  String get source => mediaFilePath(key);
  Json toJson() => {'key': key, 'name': name, 'mimeType': mimeType};
}

class ChatMessage {
  const ChatMessage({required this.id, required this.role, required this.content, required this.createdAt, this.status = 'complete', this.model = '', this.modelName = '', this.runId = '', this.notice = '', this.attachments = const []});
  factory ChatMessage.fromJson(Json value) {
    if (value['id'] is! String || !['user', 'assistant'].contains(value['role']) || value['content'] is! String || value['createdAt'] is! num || value['attachments'] is! List) throw const FormatException('聊天消息格式异常');
    return ChatMessage(id: value['id'], role: value['role'], content: value['content'], createdAt: jsonInt(value['createdAt']), status: jsonString(value['status']), model: jsonString(value['model']), modelName: jsonString(value['modelName']), runId: jsonString(value['runId']), notice: jsonString(value['notice']), attachments: (value['attachments'] as List).map((item) => ChatAttachment.fromJson(jsonObject(item))).toList());
  }
  final String id, role, content, status, model, modelName, runId, notice;
  final int createdAt;
  final List<ChatAttachment> attachments;
  ChatMessage copyWith({String? content, String? status, String? runId, String? notice}) => ChatMessage(id: id, role: role, content: content ?? this.content, createdAt: createdAt, status: status ?? this.status, model: model, modelName: modelName, runId: runId ?? this.runId, notice: notice ?? this.notice, attachments: attachments);
  Json toJson() => {'id': id, 'role': role, 'content': content, 'createdAt': createdAt, 'status': status, 'model': model, 'modelName': modelName, 'runId': runId, 'notice': notice, 'attachments': attachments.map((item) => item.toJson()).toList()};
}

class ChatSession {
  const ChatSession({required this.id, required this.title, required this.createdAt, required this.updatedAt, this.messages = const [], this.model = ''});
  factory ChatSession.fromJson(Json value) {
    if (value['id'] is! String || value['title'] is! String || value['createdAt'] is! num || value['updatedAt'] is! num || value['messages'] is! List) throw const FormatException('聊天会话格式异常');
    return ChatSession(id: value['id'], title: value['title'], createdAt: jsonInt(value['createdAt']), updatedAt: jsonInt(value['updatedAt']), model: jsonString(value['model']), messages: (value['messages'] as List).map((item) => ChatMessage.fromJson(jsonObject(item))).toList());
  }
  final String id, title, model;
  final int createdAt, updatedAt;
  final List<ChatMessage> messages;
  ChatSession copyWith({String? title, String? model, List<ChatMessage>? messages}) => ChatSession(id: id, title: title ?? this.title, model: model ?? this.model, createdAt: createdAt, updatedAt: DateTime.now().millisecondsSinceEpoch, messages: messages ?? this.messages);
  Json toJson() => {'id': id, 'title': title, 'model': model, 'createdAt': createdAt, 'updatedAt': updatedAt, 'messages': messages.map((item) => item.toJson()).toList()};
}

class ChatState {
  const ChatState({this.sessions = const [], this.activeSessionId = '', this.revision = '0', this.busy = false, this.dirty = false, this.conflict = false, this.saveError = ''});
  final List<ChatSession> sessions;
  final String activeSessionId, revision, saveError;
  final bool busy, dirty, conflict;
  ChatSession? get active => sessions.where((item) => item.id == activeSessionId).firstOrNull;
  ChatState copyWith({List<ChatSession>? sessions, String? activeSessionId, String? revision, bool? busy, bool? dirty, bool? conflict, String? saveError}) => ChatState(sessions: sessions ?? this.sessions, activeSessionId: activeSessionId ?? this.activeSessionId, revision: revision ?? this.revision, busy: busy ?? this.busy, dirty: dirty ?? this.dirty, conflict: conflict ?? this.conflict, saveError: saveError ?? this.saveError);
  ChatState replaceSession(ChatSession session) => copyWith(sessions: [session, ...sessions.where((item) => item.id != session.id)], activeSessionId: session.id);
  Json toJson() => {'state': {'sessions': sessions.map((item) => item.toJson()).toList(), 'activeSessionId': activeSessionId}, 'version': 0};
}
