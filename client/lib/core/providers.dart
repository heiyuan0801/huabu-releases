import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api/api_client.dart';
import 'database.dart';
import 'models.dart';
import 'repository.dart';
import '../features/channels/channel_providers.dart';
import '../features/works/local_image_store.dart';

export 'api/api_client.dart';
export 'models.dart';

const apiOrigin = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://image.iyuns.com');
String errorMessage(Object error) => error is ApiException ? error.message : error is PlatformException && error.code == 'Unexpected security result code' ? '系统安全存储读取失败，请处理钥匙串授权后重新读取' : error is PlatformException && error.code == 'image_folder' ? '无法访问本机图片目录，请重新选择原文件夹授权' : error is FormatException ? '读取的数据格式异常，请重试并保留原数据' : '操作未完成，请重试';

final apiProvider = Provider<ApiClient>((ref) {
  final api = ApiClient(baseUrl: '${apiOrigin.replaceFirst(RegExp(r'/+$'), '')}/api');
  api.onUnauthorized = () => ref.read(sessionProvider.notifier).expire().catchError((Object _) {});
  ref.onDispose(api.close);
  return api;
});
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});
final localImageDatabaseProvider = Provider((ref) {
  final database = LocalImageDatabase();
  ref.onDispose(database.close);
  return database;
});
final localImageStoreProvider = Provider((ref) => LocalImageStore(ref.watch(apiProvider), ref.watch(localImageDatabaseProvider), ref.watch(databaseProvider)));
final imageFolderProvider = FutureProvider((ref) async {
  await _signedIn(ref);
  return ref.watch(localImageStoreProvider).folder();
});
final repositoryProvider = Provider((ref) => HuabuRepository(ref.watch(apiProvider), localImages: ref.watch(localImageStoreProvider)));
Future<MediaBytes> readArtworkMedia(Ref ref, String source) => LocalImageStore.isLocal(source) ? ref.read(localImageStoreProvider).read(source) : ref.read(apiProvider).file(source);
final siteProvider = FutureProvider((ref) async => SiteData.fromJson(await ref.watch(apiProvider).get('/site')));

final sessionProvider = AsyncNotifierProvider<SessionController, UserAccount?>(SessionController.new,
  retry: (count, error) => error is PlatformException ? null : ProviderContainer.defaultRetry(count, error));
class SessionController extends AsyncNotifier<UserAccount?> {
  static const _storage = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));
  String get _key => 'huabu_session:${Uri.parse(apiOrigin).origin}';
  int _operation = 0;
  Future<void> _persistence = Future.value();

  void _resetAccount(String id) {
    ref.read(apiProvider).resetAccount(id);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<void> _persist(String? value) {
    final operation = _persistence.catchError((Object _) {}).then((_) => value == null
      ? _storage.delete(key: _key) : _storage.write(key: _key, value: value));
    _persistence = operation;
    return operation;
  }

  Future<void> expire() async {
    final operation = ++_operation;
    final api = ref.read(apiProvider);
    _resetAccount('');
    final epoch = api.epoch;
    if (ref.mounted) state = const AsyncData(null);
    await api.cookieJar.deleteAll();
    api.assertEpoch(epoch);
    if (!ref.mounted || operation != _operation) throw const ApiException('账号已切换，本次清理已取消', canceled: true);
    await _persist(null);
    api.assertEpoch(epoch);
    if (!ref.mounted || operation != _operation) throw const ApiException('账号已切换，本次清理已取消', canceled: true);
  }

  @override
  Future<UserAccount?> build() async {
    final op = ++_operation;
    final api = ref.watch(apiProvider);
    _resetAccount('');
    final saved = await _storage.read(key: _key);
    if (!ref.mounted || op != _operation) return state.asData?.value;
    if (saved == null) return null;
    await api.cookieJar.saveFromResponse(Uri.parse(api.baseUrl), [Cookie.fromSetCookieValue(saved)]);
    try {
      final user = UserAccount.fromJson(await api.get('/auth/me'));
      if (!ref.mounted || op != _operation) return state.asData?.value;
      _resetAccount(user.id);
      return user;
    } on ApiException catch (error) {
      if (error.status != 401 && error.status != 403) rethrow;
      if (!ref.mounted || op != _operation) return state.asData?.value;
      _resetAccount('');
      await api.cookieJar.deleteAll();
      await _persist(null);
      return null;
    }
  }

  Future<void> login(Map<String, dynamic> input, {CancelToken? cancelToken}) => _authenticate('/auth/login', input, cancelToken);

  Future<void> verifyEmail(Map<String, dynamic> input, {CancelToken? cancelToken}) => _authenticate('/auth/verify-email', input, cancelToken);

  Future<void> loginWithQr(String id, {required CancelToken cancelToken}) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) throw const ApiException('扫码登录编号无效');
    final origin = Uri.parse(ref.read(apiProvider).baseUrl).origin;
    return _authenticate('/auth/wechat-qr/$id/consume', {}, cancelToken, headers: {'X-Huabu-QR-Login': '1', 'Origin': origin}, requireSessionCookie: true);
  }

  Future<void> _authenticate(String path, Map<String, dynamic> input, CancelToken? cancelToken, {Map<String, dynamic>? headers, bool requireSessionCookie = false}) async {
    try { await ref.read(sessionProvider.future); } catch (_) {}
    if (!ref.mounted || cancelToken?.isCancelled == true) throw const ApiException('登录操作已取消', canceled: true);
    final op = ++_operation;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    void check(int scope) {
      api.assertEpoch(scope);
      if (!ref.mounted || op != _operation || cancelToken?.isCancelled == true) throw const ApiException('登录操作已取消', canceled: true);
    }
    final request = cancelToken == null ? null : await api.request(path, method: 'POST', body: input, headers: headers, cancelToken: cancelToken);
    final response = request == null ? await api.post(path, input, headers) : request.data;
    check(epoch);
    if (requireSessionCookie && !(request?.headers[HttpHeaders.setCookieHeader] ?? []).any((value) => Cookie.fromSetCookieValue(value).name == 'huabu_session')) throw const ApiException('服务器没有设置登录会话，请联系管理员');
    final value = response is String ? jsonDecode(response) : response;
    if (value is! Map) throw const ApiException('服务器账号数据格式异常，登录未完成');
    final user = UserAccount.fromJson(jsonObject(value));
    if (user.id.isEmpty || user.status != 'active') throw const ApiException('服务器未返回已验证的账号，登录未完成');
    _resetAccount(user.id);
    final activatedEpoch = api.epoch;
    state = const AsyncData(null);
    final cookies = await api.cookieJar.loadForRequest(Uri.parse('${api.baseUrl}/auth/me'));
    check(activatedEpoch);
    final cookie = cookies.where((item) => item.name == 'huabu_session').firstOrNull;
    try {
      if (cookie == null) throw const ApiException('服务器没有设置登录会话，请联系管理员');
      await _persist(cookie.toString());
    } catch (_) {
      check(activatedEpoch);
      await api.cookieJar.deleteAll();
      check(activatedEpoch);
      _resetAccount('');
      rethrow;
    }
    check(activatedEpoch);
    state = AsyncData(user);
  }

  Future<String?> logout() async {
    final operation = ++_operation;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    var confirmed = true;
    try { await api.post('/auth/logout'); } catch (_) { confirmed = false; }
    api.assertEpoch(epoch);
    if (!ref.mounted || operation != _operation) throw const ApiException('账号已切换，本次退出已取消', canceled: true);
    try { await _persist(null); }
    catch (_) {
      api.assertEpoch(epoch);
      if (!ref.mounted || operation != _operation) throw const ApiException('账号已切换，本次退出已取消', canceled: true);
      throw ApiException('${confirmed ? '服务器已注销，但' : ''}系统安全存储清理失败，本机退出未完成，请重试。');
    }
    api.assertEpoch(epoch);
    if (!ref.mounted || operation != _operation) throw const ApiException('账号已切换，本次退出已取消', canceled: true);
    await api.cookieJar.deleteAll();
    api.assertEpoch(epoch);
    if (!ref.mounted || operation != _operation) throw const ApiException('账号已切换，本次退出已取消', canceled: true);
    _resetAccount('');
    state = const AsyncData(null);
    return confirmed ? null : '本机登录会话已清除，服务器注销尚未确认。请联网后核对账号会话。';
  }

  Future<void> updateProfile(String name) async {
    final api = ref.read(apiProvider), epoch = api.epoch;
    final user = UserAccount.fromJson(await api.put('/profile', {'displayName': name}));
    api.assertEpoch(epoch);
    if (ref.mounted) state = AsyncData(user);
  }

  Future<void> updateAvatar(Uint8List bytes, String mime) async {
    final api = ref.read(apiProvider), epoch = api.epoch;
    final response = await api.request('/profile/avatar', method: 'PUT', body: Stream<List<int>>.value(bytes), headers: {'Content-Type': mime, 'Content-Length': bytes.length});
    api.assertEpoch(epoch);
    if (ref.mounted) state = AsyncData(UserAccount.fromJson(jsonObject(response.data)));
  }
}

final promptDraftProvider = NotifierProvider<PromptDraft, String>(PromptDraft.new);
class PromptDraft extends Notifier<String> {
  @override
  String build() { ref.watch(sessionProvider.select((value) => value.asData?.value?.id)); return ''; }
  void setPrompt(String prompt) => state = prompt;
}

final exploreSearchProvider = NotifierProvider<ExploreSearch, String>(ExploreSearch.new);
class ExploreSearch extends Notifier<String> {
  @override
  String build() { ref.watch(sessionProvider.select((value) => value.asData?.value?.id)); return ''; }
  void setQuery(String query) => state = query;
}

Future<void> _signedIn(Ref ref) async {
  ref.watch(sessionProvider.select((value) => value.asData?.value?.id));
  final user = await ref.read(sessionProvider.future);
  if (!ref.mounted) throw const ApiException('操作已取消', canceled: true);
  if (user == null) throw const ApiException('登录后继续', status: 401);
}
final creditsProvider = FutureProvider<double>((ref) async {
  final api = ref.watch(apiProvider);
  await _signedIn(ref);
  return ((await api.get('/credits'))['balance'] as num).toDouble();
});
final modelsProvider = FutureProvider<List<ImageModel>>((ref) async {
  return (await ref.watch(catalogProvider.future)).where((model) => model.capability == 'image').toList();
});
final favoritesProvider = FutureProvider<List<Artwork>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  await _signedIn(ref);
  return repository.favorites();
});
final worksProvider = FutureProvider<List<Artwork>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  await _signedIn(ref);
  return repository.works();
});
final serverImageHistoryProvider = FutureProvider<List<Artwork>>((ref) async {
  await _signedIn(ref);
  final api = ref.watch(apiProvider), epoch = ref.read(apiProvider).epoch;
  final repository = ref.watch(repositoryProvider);
  final works = await repository.serverWorks();
  api.assertEpoch(epoch);
  final favorites = await repository.serverFavorites();
  api.assertEpoch(epoch);
  return [...works, ...favorites]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});
final assetsProvider = FutureProvider<List<AssetItem>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  await _signedIn(ref);
  return repository.assets();
});
final imageProvider = FutureProvider.autoDispose.family<MediaBytes, String>((ref, source) {
  ref.watch(sessionProvider.select((session) => session.asData?.value?.id));
  return readArtworkMedia(ref, source);
});
final imageSizeProvider = FutureProvider.autoDispose.family<ui.Size, String>((ref, source) async {
  final media = await ref.watch(imageProvider(source).future);
  final buffer = await ui.ImmutableBuffer.fromUint8List(media.bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try { return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble()); }
    finally { descriptor.dispose(); }
  } finally { buffer.dispose(); }
});
final taskPageProvider = FutureProvider.autoDispose.family<Json, int>((ref, page) async {
  final api = ref.watch(apiProvider);
  await _signedIn(ref);
  return api.get('/generations', query: {'page': page});
});

final themeModeProvider = NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
class ThemeController extends Notifier<ThemeMode> {
  bool _changed = false;
  int _operation = 0;
  @override
  ThemeMode build() {
    ref.read(databaseProvider).readPreference('theme').then((saved) {
      if (ref.mounted && !_changed && saved != null) state = ThemeMode.values.firstWhere((mode) => mode.name == saved, orElse: () => ThemeMode.system);
    }).catchError((Object _) {});
    return ThemeMode.dark;
  }
  Future<void> setMode(ThemeMode mode) async {
    _changed = true;
    final operation = ++_operation;
    await ref.read(databaseProvider).writePreference('theme', mode.name);
    if (ref.mounted && operation == _operation) state = mode;
  }
}
