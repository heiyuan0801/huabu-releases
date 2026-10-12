import 'dart:convert';

import 'package:auto_updater/auto_updater.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';

const updateManifestUrl = String.fromEnvironment('APP_UPDATE_MANIFEST_URL', defaultValue: 'https://github.com/heiyuan0801/huabu-releases/releases/latest/download/flutter-release.json');
const releaseHistoryUrl = 'https://github.com/heiyuan0801/huabu-releases/releases';
final packageInfoProvider = FutureProvider((ref) => PackageInfo.fromPlatform());

String get clientPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => 'macos', TargetPlatform.windows => 'windows',
  TargetPlatform.android => 'android', TargetPlatform.iOS => 'ios', _ => '',
};

Uri releaseUri(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
    throw const FormatException('发布地址必须为不含凭据的 HTTPS 地址');
  }
  return uri;
}

class ClientRelease {
  const ClientRelease({required this.version, required this.buildNumber, required this.notes, required this.downloads, required this.appcasts});
  factory ClientRelease.fromJson(dynamic value) {
    if (value is! Map || value['schemaVersion'] != 1 || value['version'] is! String || value['buildNumber'] is! int || value['buildNumber'] < 1 || value['notes'] is! String) {
      throw const FormatException('软件发布信息格式异常');
    }
    Map<String, Uri> addresses(dynamic data) {
      if (data is! Map) throw const FormatException('软件发布地址格式异常');
      return data.map((key, address) {
        if (!['macos', 'windows', 'android', 'ios'].contains(key) || address is! String) throw const FormatException('软件平台地址格式异常');
        return MapEntry(key as String, releaseUri(address));
      });
    }
    return ClientRelease(version: Version.parse(value['version']), buildNumber: value['buildNumber'], notes: value['notes'], downloads: addresses(value['downloads']), appcasts: addresses(value['appcasts']));
  }
  final Version version;
  final int buildNumber;
  final String notes;
  final Map<String, Uri> downloads, appcasts;

  bool newerThan(PackageInfo installed) {
    final current = Version.parse(installed.version);
    final build = int.tryParse(installed.buildNumber);
    return version > current || (version == current && build != null && buildNumber > build);
  }
}

final clientReleaseDioProvider = Provider((ref) {
  final dio = Dio();
  ref.onDispose(dio.close);
  return dio;
});
final clientReleaseProvider = FutureProvider<ClientRelease?>((ref) async {
  if (updateManifestUrl.isEmpty) return null;
  final dio = ref.watch(clientReleaseDioProvider), cancel = CancelToken();
  ref.onDispose(() => cancel.cancel());
  final response = await dio.getUri(releaseUri(updateManifestUrl), cancelToken: cancel);
  releaseUri(response.realUri.toString());
  final data = response.data;
  return ClientRelease.fromJson(data is String ? jsonDecode(data) : data);
}, retry: (_, _) => null);

Future<void> openReleaseDownload(Uri uri) async {
  releaseUri(uri.toString());
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw const ApiException('无法打开下载地址，请重试');
}

final nativeUpdateReadyProvider = FutureProvider<bool>((ref) async {
  if (!['macos', 'windows'].contains(clientPlatform)) return false;
  return await const MethodChannel('chat.weilai.huabu/window').invokeMethod<bool>('hasUpdateKey') ?? false;
});

class NativeUpdateState {
  const NativeUpdateState({this.message = '', this.error = false, this.busy = false});
  final String message;
  final bool error, busy;
}

final nativeUpdateProvider = NotifierProvider<NativeUpdateController, NativeUpdateState>(NativeUpdateController.new);
class NativeUpdateController extends Notifier<NativeUpdateState> with UpdaterListener {
  bool _listening = false, _opening = false;
  @override
  NativeUpdateState build() {
    ref.onDispose(() { if (_listening) autoUpdater.removeListener(this); });
    return const NativeUpdateState();
  }
  Future<void> start(Uri feed) async {
    if (_opening) return;
    _opening = true;
    try {
      releaseUri(feed.toString());
      if (!await ref.read(nativeUpdateReadyProvider.future)) throw const ApiException('当前安装包尚未配置更新签名，请使用下载入口');
      if (!ref.mounted) return;
      if (!_listening) { autoUpdater.addListener(this); _listening = true; }
      state = const NativeUpdateState(message: '正在打开系统更新窗口…', busy: true);
      await autoUpdater.setFeedURL(feed.toString());
      if (ref.mounted) await autoUpdater.checkForUpdates(inBackground: false);
    } catch (error) {
      if (ref.mounted) state = NativeUpdateState(message: error is ApiException ? error.message : '更新窗口未能打开，请重试', error: true);
    } finally {
      _opening = false;
      if (ref.mounted && state.busy) state = NativeUpdateState(message: state.message, error: state.error);
    }
  }
  void _status(String message, {bool error = false}) { if (ref.mounted) state = NativeUpdateState(message: message, error: error, busy: _opening); }
  @override
  void onUpdaterError(UpdaterError? error) => _status(error?.message ?? '更新未完成，请重试', error: true);
  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) => _status('系统更新窗口正在检查版本');
  @override
  void onUpdaterUpdateAvailable(AppcastItem? item) => _status('发现可用更新，请在系统窗口中确认下载安装');
  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) => error == null ? _status('更新源未发现适用于本机的新版本') : onUpdaterError(error);
  @override
  void onUpdaterUpdateDownloaded(AppcastItem? item) => _status('更新包已下载，请在系统窗口中确认安装');
  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? item) => _status('更新已准备安装，请按系统窗口提示完成安装');
}
