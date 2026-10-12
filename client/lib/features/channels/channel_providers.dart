import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

import '../../core/providers.dart';

class LocalChannel {
  const LocalChannel({required this.id, required this.name, required this.baseUrl, required this.apiKey, required this.apiFormat, required this.models, this.enabled = true});
  factory LocalChannel.fromJson(Json json) => LocalChannel(id: jsonString(json['id']), name: jsonString(json['name']), baseUrl: jsonString(json['baseUrl']), apiKey: jsonString(json['apiKey']), apiFormat: jsonString(json['apiFormat']), enabled: json['enabled'] == true, models: (json['models'] as List).map(jsonObject).toList());
  final String id, name, baseUrl, apiKey, apiFormat;
  final bool enabled;
  final List<Json> models;
  Json toJson() => {'id': id, 'name': name, 'baseUrl': baseUrl, 'apiKey': apiKey, 'apiFormat': apiFormat, 'enabled': enabled, 'models': models};
  LocalChannel copyWith({bool? enabled}) => LocalChannel(id: id, name: name, baseUrl: baseUrl, apiKey: apiKey, apiFormat: apiFormat, models: models, enabled: enabled ?? this.enabled);
  List<ImageModel> get catalog => [for (final entry in models) ImageModel(id: 'local:$id::${entry['name']}', providerId: 'local:$id', providerName: name, model: jsonString(entry['name']), displayName: jsonString(entry['name']), apiFormat: apiFormat, capability: jsonString(entry['capability']), creditCost: 0, value: 'local:$id::${entry['name']}')];
}

const _channelStorage = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));
String _channelKey(ApiClient api) => 'huabu:local-channels:${Uri.parse(apiOrigin).origin}:${api.accountId}';
Future<List<LocalChannel>> _readChannels(ApiClient api) async {
  final epoch = api.epoch;
  if (api.accountId.isEmpty) throw const ApiException('登录后配置个人渠道');
  final raw = await _channelStorage.read(key: _channelKey(api));
  api.assertEpoch(epoch);
  if (raw == null) return [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) throw const ApiException('个人渠道配置损坏，已停止覆盖，请检查系统安全存储');
  return decoded.map((value) => LocalChannel.fromJson(jsonObject(value))).toList();
}

Future<ModelApiTarget> resolveModelApiTarget(ApiClient api, ImageModel model) async {
  final epoch = api.epoch;
  if (!model.providerId.startsWith('local:')) return ModelApiTarget(api, model);
  final id = model.providerId.substring(6);
  final channel = (await _readChannels(api)).where((entry) => entry.id == id && entry.enabled).firstOrNull;
  api.assertEpoch(epoch);
  if (channel == null || channel.apiKey.isEmpty || !channel.models.any((entry) => entry['name'] == model.model)) throw const ApiException('个人渠道已停用、移除或缺少模型与密钥，请重新配置');
  return ModelApiTarget(api, model, channel: channel);
}

Future<ModelApiTarget> resolveModelValueApiTarget(ApiClient api, String value) async {
  final parts = value.split('::');
  if (parts.length < 2) throw const ApiException('任务缺少可识别的模型渠道，请在原设备或网页核对');
  final name = parts.skip(1).join('::');
  if (parts.first.startsWith('local:')) {
    final epoch = api.epoch;
    final channel = (await _readChannels(api)).where((entry) => 'local:${entry.id}' == parts.first && entry.enabled).firstOrNull;
    api.assertEpoch(epoch);
    final model = channel?.catalog.where((entry) => entry.model == name).firstOrNull;
    if (channel == null || model == null || channel.apiKey.isEmpty) throw const ApiException('当前设备没有该任务的个人渠道配置，请配置原渠道后重新核对');
    return ModelApiTarget(api, model, channel: channel);
  }
  if (!parts.first.startsWith('managed:')) throw const ApiException('任务渠道标识无法识别，请在原设备或网页核对');
  final provider = parts.first.substring(8);
  return ModelApiTarget(api, ImageModel(id: value, providerId: provider, providerName: '', model: name, displayName: name, apiFormat: 'openai', capability: 'image', creditCost: 0, value: value));
}

final localChannelsProvider = AsyncNotifierProvider<LocalChannelsController, List<LocalChannel>>(LocalChannelsController.new,
  retry: (count, error) => error is PlatformException ? null : ProviderContainer.defaultRetry(count, error));
class LocalChannelsController extends AsyncNotifier<List<LocalChannel>> {
  late String _key;
  Future<void> _writes = Future.value();

  @override
  Future<List<LocalChannel>> build() async {
    ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
    final user = await ref.read(sessionProvider.future);
    if (user == null || !ref.mounted) throw const ApiException('登录后配置个人渠道');
    final api = ref.read(apiProvider);
    _key = _channelKey(api);
    return _readChannels(api);
  }

  Future<void> _change(List<LocalChannel> Function(List<LocalChannel>) apply) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final key = _key;
    final operation = _writes.catchError((Object _) {}).then((_) async {
      api.assertEpoch(epoch);
      final current = await future;
      api.assertEpoch(epoch);
      final next = apply(current);
      await _channelStorage.write(key: key, value: jsonEncode(next.map((channel) => channel.toJson()).toList()));
      api.assertEpoch(epoch);
      if (ref.mounted) state = AsyncData(next);
    });
    _writes = operation;
    await operation;
  }

  Future<void> save(LocalChannel channel) async {
    ModelApiTarget.validateBase(channel.baseUrl);
    if (channel.name.trim().isEmpty) throw const ApiException('请填写渠道名称');
    if (channel.enabled && channel.apiKey.isEmpty) throw const ApiException('启用个人渠道前请填写 API Key');
    await _change((current) => [...current.where((entry) => entry.id != channel.id), channel]);
  }
  Future<void> remove(String id) => _change((current) => current.where((entry) => entry.id != id).toList());
  Future<void> setEnabled(LocalChannel channel, bool enabled) => save(channel.copyWith(enabled: enabled));
}

final cloudCatalogProvider = FutureProvider<List<ImageModel>>((ref) async {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  final user = await ref.read(sessionProvider.future);
  if (user == null || !ref.mounted) throw const ApiException('登录后查看模型目录');
  final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
  final data = await api.get('/catalog/models');
  api.assertEpoch(epoch);
  return (data['models'] as List).map((value) => ImageModel.fromJson(jsonObject(value))).toList();
});
final catalogProvider = FutureProvider<List<ImageModel>>((ref) async {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  final user = await ref.read(sessionProvider.future);
  if (user == null || !ref.mounted) throw const ApiException('登录后查看模型目录', status: 401);
  final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
  if (api.accountId != user.id) throw const ApiException('账号已切换，目录读取已取消', canceled: true);
  final cloud = ref.watch(cloudCatalogProvider), local = ref.watch(localChannelsProvider);
  final sources = await Future.wait([
    cloud.hasError ? Future.value(AsyncError<List<ImageModel>>(cloud.error!, cloud.stackTrace!)) : AsyncValue.guard(() => ref.watch(cloudCatalogProvider.future)),
    local.hasError ? Future.value(AsyncError<List<ImageModel>>(local.error!, local.stackTrace!)) : AsyncValue.guard(() async => (await ref.watch(localChannelsProvider.future)).where((channel) => channel.enabled).expand((channel) => channel.catalog).toList()),
  ]);
  if (!ref.mounted) throw const ApiException('目录读取已取消', canceled: true);
  api.assertEpoch(epoch);
  for (final source in sources) {
    if (source.error case final ApiException error when error.canceled || error.status == 401 || error.status == 403) throw error;
  }
  if (sources.every((source) => source.hasError)) throw ApiException('平台目录：${errorMessage(sources[0].error!)}；本机个人目录：${errorMessage(sources[1].error!)}');
  return [for (final source in sources) ...?source.asData?.value];
});

final catalogIssuesProvider = Provider<Map<String, String>>((ref) {
  final sources = {'平台目录': ref.watch(cloudCatalogProvider), '本机个人目录': ref.watch(localChannelsProvider)};
  return {for (final entry in sources.entries)
    if (entry.value.hasError && !(entry.value.error is ApiException && (entry.value.error! as ApiException).canceled)) entry.key: errorMessage(entry.value.error!),
  };
});

void refreshCatalog(WidgetRef ref) {
  ref.invalidate(cloudCatalogProvider);
  ref.invalidate(localChannelsProvider);
  ref.invalidate(catalogProvider);
}

final modelApiTargetProvider = FutureProvider.autoDispose.family<ModelApiTarget, ImageModel>((ref, model) async {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
  LocalChannel? channel;
  if (model.providerId.startsWith('local:')) {
    final id = model.providerId.substring(6);
    channel = (await ref.watch(localChannelsProvider.future)).where((entry) => entry.id == id && entry.enabled).firstOrNull;
    if (channel == null || channel.apiKey.isEmpty || !channel.models.any((entry) => entry['name'] == model.model && entry['capability'] == model.capability)) throw const ApiException('个人渠道已停用、移除或缺少模型与密钥，请重新配置');
  }
  api.assertEpoch(epoch);
  return ModelApiTarget(api, model, channel: channel);
});

/// Each target belongs to the account scope where it was created.
class ModelApiTarget {
  ModelApiTarget(this.api, this.model, {this.channel}) : epoch = api.epoch;
  final ApiClient api;
  final ImageModel model;
  final LocalChannel? channel;
  final int epoch;
  String get source => channel == null ? 'platform' : 'personal';
  String get apiFormat => model.apiFormat;
  String get value => model.value;
  String redact(String message) {
    final secret = channel?.apiKey ?? '';
    return secret.isEmpty ? message : message.replaceAll(secret, '[密钥已隐藏]');
  }
  ApiException redactError(ApiException error) => ApiException(redact(error.message), status: error.status, canceled: error.canceled);

  static Uri validateBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) throw const ApiException('请输入完整 HTTP/HTTPS 接口地址，不包含账号、查询参数或片段');
    return uri;
  }

  Uri _upstream(String path, Map<String, dynamic>? query) {
    final base = validateBase(channel!.baseUrl);
    final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
    var suffix = path.startsWith('/') ? path : '/$path';
    for (final version in ['/api/plan/v3', '/api/v3', '/v1beta', '/v1']) {
      if (prefix.endsWith(version) && suffix.startsWith('$version/')) { suffix = suffix.substring(version.length); break; }
    }
    if (prefix.endsWith('/api/v3') || prefix.endsWith('/api/plan/v3')) {
      for (final version in ['/api/plan/v3', '/api/v3', '/v1']) {
        if (suffix.startsWith('$version/')) { suffix = suffix.substring(version.length); break; }
      }
    }
    final uri = Uri.parse('${base.origin}$prefix$suffix');
    return query == null ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...query.map((key, value) => MapEntry(key, '$value'))});
  }

  Map<String, dynamic> _headers(String? runId) => {
    if (channel == null) 'X-Huabu-Model': model.model,
    'X-Huabu-Run-ID': ?runId,
    if (channel != null && channel!.apiFormat == 'gemini') 'x-goog-api-key': channel!.apiKey,
    if (channel != null && channel!.apiFormat != 'gemini') 'Authorization': 'Bearer ${channel!.apiKey}',
  };

  Future<Response<dynamic>> request(String path, {String method = 'GET', Object? body, Map<String, dynamic>? query, Map<String, dynamic>? headers, String? runId, ResponseType responseType = ResponseType.json, CancelToken? cancelToken}) async {
    api.assertEpoch(epoch);
    if (Uri.parse(path).hasScheme) throw const ApiException('模型接口路径必须属于当前渠道');
    try {
      final response = await api.request(channel == null ? '/platform/${Uri.encodeComponent(model.providerId)}$path' : '/proxy', method: method, body: body, query: channel == null ? query : {'url': _upstream(path, query).toString()}, headers: {..._headers(runId), ...?headers}, responseType: responseType, cancelToken: cancelToken);
      api.assertEpoch(epoch);
      return response;
    } on ApiException catch (error) {
      throw redactError(error);
    }
  }

  Json _json(Response<dynamic> response) {
    final value = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (value is! Map) throw const ApiException('模型接口返回的数据格式无法读取，请在任务记录核对');
    return jsonObject(value);
  }
  Future<Json> get(String path, {String? runId, Map<String, dynamic>? query, CancelToken? cancelToken}) async => _json(await request(path, runId: runId, query: query, cancelToken: cancelToken));
  Future<Json> post(String path, Object? body, {String? runId, CancelToken? cancelToken}) async => _json(await request(path, method: 'POST', body: body, runId: runId, cancelToken: cancelToken));

  Future<MediaBytes> media(String source, {String? runId}) async {
    api.assertEpoch(epoch);
    try {
      final uri = Uri.parse(source);
      final headers = <String, dynamic>{'X-Huabu-Run-ID': ?runId};
      String resolved = source;
      if (!source.startsWith('data:')) {
        if (channel != null) {
          final base = validateBase(channel!.baseUrl);
          final target = uri.hasScheme ? uri : base.resolve(source);
          resolved = target.toString();
          if (target.origin == base.origin) headers.addAll(_headers(runId));
        } else if (!uri.hasScheme && (source.startsWith('/v1/') || source.startsWith('/v1beta/'))) {
          resolved = '/platform/${Uri.encodeComponent(model.providerId)}$source';
          headers.addAll(_headers(runId));
        }
      }
      final result = await api.file(resolved, headers: headers);
      api.assertEpoch(epoch);
      return result;
    } on ApiException catch (error) {
      throw redactError(error);
    } on FormatException {
      throw const ApiException('模型媒体地址或数据格式异常，请在任务记录核对');
    }
  }

  Future<List<String>> fetchModels({CancelToken? cancelToken}) async {
    final names = <String>{};
    String token = '';
    final tokens = <String>{};
    do {
      final response = await get(apiFormat == 'gemini' ? '/v1beta/models' : '/v1/models', query: token.isEmpty ? null : {'pageToken': token}, cancelToken: cancelToken);
      final entries = response[apiFormat == 'gemini' ? 'models' : 'data'];
      if (entries is! List) throw const ApiException('渠道没有返回标准模型列表');
      for (final entry in entries) {
        final value = jsonString(jsonObject(entry)[apiFormat == 'gemini' ? 'name' : 'id']).replaceFirst(RegExp(r'^models/'), '');
        if (value.isNotEmpty) names.add(value);
      }
      token = apiFormat == 'gemini' ? jsonString(response['nextPageToken']) : '';
      if (token.isNotEmpty && !tokens.add(token)) throw const ApiException('模型列表分页响应重复，请联系接口提供方');
    } while (token.isNotEmpty);
    return names.toList()..sort();
  }
}
