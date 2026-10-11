import 'dart:typed_data';

typedef Json = Map<String, dynamic>;

Json jsonObject(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
String jsonString(Object? value) => value is String ? value : '';
int jsonInt(Object? value) => value is num ? value.toInt() : 0;
DateTime jsonDate(Object? value) => value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : DateTime.tryParse(jsonString(value)) ?? DateTime.fromMillisecondsSinceEpoch(0);
String mediaFilePath(String key, {bool video = false}) {
  final team = key.startsWith('team:') ? key.split(':')[1] : '';
  return team.isNotEmpty ? '/api/teams/${Uri.encodeComponent(team)}/files/${Uri.encodeComponent(key)}' : '/api/storage/${video ? 'media_files' : 'image_files'}/${Uri.encodeComponent(key)}';
}

class UserAccount {
  const UserAccount({required this.id, required this.email, required this.displayName, required this.avatarUrl, required this.role, required this.status});
  factory UserAccount.fromJson(Json json) => UserAccount(id: jsonString(json['id']), email: jsonString(json['email']), displayName: jsonString(json['displayName']), avatarUrl: jsonString(json['avatarUrl']), role: jsonString(json['role']), status: jsonString(json['status']));
  final String id, email, displayName, avatarUrl, role, status;
}

class SiteData {
  const SiteData({required this.siteName, required this.terms, required this.privacy, required this.emailCodeLogin, required this.captchaEnabled, required this.emailConfigured, required this.content});
  factory SiteData.fromJson(Json json) {
    final site = jsonObject(json['site']);
    final auth = jsonObject(json['auth']);
    return SiteData(siteName: jsonString(site['siteName']), terms: jsonString(site['terms']), privacy: jsonString(site['privacy']), emailCodeLogin: auth['emailCodeLogin'] == true, captchaEnabled: auth['captchaEnabled'] == true, emailConfigured: json['emailConfigured'] == true, content: (json['content'] as List? ?? []).map((item) => Artwork.fromHomeJson(jsonObject(item))).toList());
  }
  final String siteName, terms, privacy;
  final bool emailCodeLogin, captchaEnabled, emailConfigured;
  final List<Artwork> content;
}

class ImageModel {
  const ImageModel({required this.id, required this.providerId, required this.providerName, required this.model, required this.displayName, required this.apiFormat, required this.capability, required this.creditCost, required this.value});
  factory ImageModel.fromJson(Json json) => ImageModel(id: jsonString(json['id']), providerId: jsonString(json['providerId']), providerName: jsonString(json['providerName']), model: jsonString(json['model']), displayName: jsonString(json['displayName']), apiFormat: jsonString(json['apiFormat']), capability: jsonString(json['capability']), creditCost: jsonInt(json['creditCost']), value: jsonString(json['value']));
  final String id, providerId, providerName, model, displayName, apiFormat, capability, value;
  final int creditCost;
  String get name => displayName.isEmpty ? model : displayName;
}

class Artwork {
  const Artwork({required this.id, required this.title, required this.prompt, required this.imageUrl, required this.createdAt, this.fileKey = '', this.model = '', this.ratio = '1:1', this.runId = '', this.author = '', this.width = 0, this.height = 0, this.source = 'private', this.description = '', this.category = '', this.kind = '', this.mimeType = 'image/png', this.bytes = 0, this.recordKey = ''});
  factory Artwork.fromJson(Json json) => Artwork(id: jsonString(json['id']), title: jsonString(json['title']), prompt: jsonString(json['prompt']), imageUrl: jsonString(json['imageUrl']), fileKey: jsonString(json['fileKey']), model: jsonString(json['model']), ratio: jsonString(json['ratio']).isEmpty ? '1:1' : jsonString(json['ratio']), runId: jsonString(json['runId']), author: jsonString(json['author']), width: jsonInt(json['width']), height: jsonInt(json['height']), createdAt: jsonDate(json['createdAt']), source: jsonString(json['source']).isEmpty ? 'private' : jsonString(json['source']), description: jsonString(json['description']), category: jsonString(json['category']), kind: jsonString(json['kind']), mimeType: jsonString(json['mimeType']).isEmpty ? 'image/png' : jsonString(json['mimeType']), bytes: jsonInt(json['bytes']), recordKey: jsonString(json['recordKey']));
  factory Artwork.fromHomeJson(Json json) => Artwork.fromJson({...json, 'source': 'published', 'author': jsonString(json['author']).isEmpty ? '官方灵感' : json['author']});
  static List<Artwork> fromGenerationLog(Json log, String key) {
    final images = log['images'] as List? ?? [];
    return images.map((value) {
      final image = jsonObject(value);
      final fileKey = jsonString(image['storageKey']);
      return Artwork(id: jsonString(image['id']), title: jsonString(log['title']), prompt: jsonString(log['prompt']), model: jsonString(log['model']), ratio: jsonString(log['size']), createdAt: jsonDate(log['createdAt']), fileKey: fileKey, imageUrl: fileKey.isEmpty ? jsonString(image['dataUrl']) : mediaFilePath(fileKey), width: jsonInt(image['width']), height: jsonInt(image['height']), mimeType: jsonString(image['mimeType']).isEmpty ? 'image/png' : jsonString(image['mimeType']), bytes: jsonInt(image['bytes']), runId: jsonString(log['runId']), recordKey: key);
    }).toList();
  }
  final String id, title, prompt, imageUrl, fileKey, model, ratio, runId, author, source, description, category, kind, mimeType, recordKey;
  final int width, height, bytes;
  final DateTime createdAt;
  Json toJson() => {'id': id, 'title': title, 'prompt': prompt, 'imageUrl': imageUrl, 'fileKey': fileKey, 'model': model, 'ratio': ratio, 'runId': runId, 'author': author, 'width': width, 'height': height, 'createdAt': createdAt.toIso8601String(), 'source': source, 'description': description, 'mimeType': mimeType, 'bytes': bytes, 'recordKey': recordKey};
}

class AssetItem {
  const AssetItem({required this.id, required this.kind, required this.title, required this.coverUrl, required this.createdAt, required this.updatedAt, required this.data, this.tags = const [], this.source = '', this.note = '', this.metadata = const {}});
  factory AssetItem.fromJson(Json json) => AssetItem(id: jsonString(json['id']), kind: jsonString(json['kind']), title: jsonString(json['title']), coverUrl: jsonString(json['coverUrl']), tags: (json['tags'] as List? ?? []).whereType<String>().toList(), source: jsonString(json['source']), note: jsonString(json['note']), createdAt: jsonDate(json['createdAt']), updatedAt: jsonDate(json['updatedAt']), data: jsonObject(json['data']), metadata: jsonObject(json['metadata']));
  final String id, kind, title, coverUrl, source, note;
  final DateTime createdAt, updatedAt;
  final List<String> tags;
  final Json data, metadata;
  String get fileKey => jsonString(data['storageKey']);
  String get imageUrl => fileKey.isNotEmpty ? mediaFilePath(fileKey, video: kind == 'video') : jsonString(data[kind == 'video' ? 'url' : 'dataUrl']);
  String get content => jsonString(data['content']);
  int get width => jsonInt(data['width']);
  int get height => jsonInt(data['height']);
  Json toJson() => {'id': id, 'kind': kind, 'title': title, 'coverUrl': coverUrl, 'tags': tags, 'source': source, 'note': note, 'createdAt': createdAt.toIso8601String(), 'updatedAt': updatedAt.toIso8601String(), 'data': data, 'metadata': metadata};
}

class GenerationRun {
  const GenerationRun({required this.id, required this.model, required this.capability, required this.status, required this.serverStatus, required this.createdAt, required this.message, required this.durationMs, required this.resultCount, required this.requestedCount});
  factory GenerationRun.fromJson(Json json) => GenerationRun(id: jsonString(json['id']), model: jsonString(json['model']), capability: jsonString(json['capability']), status: jsonString(json['status']), serverStatus: jsonString(json['serverStatus']), createdAt: jsonDate(json['createdAt']), message: jsonString(json['message']), durationMs: jsonInt(json['durationMs']), resultCount: jsonInt(json['resultCount']), requestedCount: jsonInt(json['requestedCount']));
  final String id, model, capability, status, serverStatus, message;
  final DateTime createdAt;
  final int durationMs, resultCount, requestedCount;
  String get statusLabel => switch (serverStatus) {'success' => '已完成', 'failed' => '已确认失败', 'pending' => '生成中', _ => '待核对'};
}

class MediaBytes {
  const MediaBytes({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

class ImageReference extends MediaBytes {
  const ImageReference({required super.bytes, required super.mimeType, this.filename = 'reference.png'});
  final String filename;
}
