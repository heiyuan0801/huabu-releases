import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/database.dart';
import '../../core/models.dart';
import '../generation/generation_service.dart';

class LocalImageDatabase extends GeneratedDatabase {
  LocalImageDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'huabu_local_images', native: DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory)));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
    await customStatement('CREATE TABLE images (scope TEXT NOT NULL, id TEXT NOT NULL, document TEXT NOT NULL, PRIMARY KEY (scope, id))');
  });
  Json _document(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map || ['id', 'source', 'base', 'relativePath', 'imageUrl'].any((key) => value[key] is! String || (value[key] as String).isEmpty)) throw const ApiException('本机图片索引损坏，已停止读取，请保留原文件和数据库后处理');
    return jsonObject(value);
  }
  Future<List<Json>> records(String scope) async => (await customSelect('SELECT document FROM images WHERE scope = ?', variables: [Variable(scope)]).get()).map((row) => _document(row.read<String>('document'))).toList();
  Future<Json?> record(String scope, String id) async {
    final row = await customSelect('SELECT document FROM images WHERE scope = ? AND id = ?', variables: [Variable(scope), Variable(id)]).getSingleOrNull();
    return row == null ? null : _document(row.read<String>('document'));
  }
  Future<void> put(String scope, String id, Json value) => customStatement('INSERT INTO images (scope, id, document) VALUES (?, ?, ?) ON CONFLICT(scope, id) DO UPDATE SET document = excluded.document', [scope, id, jsonEncode(value)]);
  Future<void> remove(String scope, String id) => customStatement('DELETE FROM images WHERE scope = ? AND id = ?', [scope, id]);
}

/// Image bytes stay in dated folders. Only their account-scoped index is in Drift.
class LocalImageStore {
  LocalImageStore(this.api, this.database, this.preferences);
  final ApiClient api;
  final LocalImageDatabase database;
  final AppDatabase preferences;
  static const _channel = MethodChannel('chat.weilai.huabu/window');
  static bool isLocal(String source) => source.startsWith('huabu-local:');
  static String favoriteId(Artwork work) => sha256.convert(utf8.encode('favorite:${work.id}:${work.imageUrl}')).toString();
  String get scope => sha256.convert(utf8.encode('${Uri.parse(api.baseUrl).origin}\n${api.accountId}')).toString();
  String get _folderKey => 'image-folder:$scope';
  String get _relativeRoot => ['未来画布', Uri.parse(api.baseUrl).host.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_'), 'account-${scope.substring(0, 16)}'].join(Platform.pathSeparator);
  void _check(int epoch) {
    api.assertEpoch(epoch);
    if (api.accountId.isEmpty) throw const ApiException('登录后读取本机图片');
  }
  Future<String> _base(int epoch) async {
    final chosen = await preferences.readPreference(_folderKey);
    _check(epoch);
    final path = chosen ?? (await getApplicationDocumentsDirectory()).path;
    _check(epoch);
    return path;
  }
  Future<T> _access<T>(String base, int epoch, Future<T> Function(String) action) async {
    _check(epoch);
    final resolved = Platform.isMacOS ? await _channel.invokeMethod<String>('accessImageFolder', base) : base;
    try { _check(epoch); return await action(resolved ?? base); }
    on FileSystemException { throw const ApiException('本机图片文件无法读写，请检查磁盘空间、文件是否被移动及目录权限；可重新选择保存目录'); }
    finally { if (Platform.isMacOS) await _channel.invokeMethod<void>('releaseImageFolder', base); }
  }
  Future<String> folder() async {
    final epoch = api.epoch, relative = _relativeRoot;
    return _access(await _base(epoch), epoch, (base) async => '$base${Platform.pathSeparator}$relative');
  }
  Future<bool> chooseFolder() async {
    final epoch = api.epoch, key = _folderKey;
    final path = Platform.isMacOS ? await _channel.invokeMethod<String>('chooseImageFolder') : await getDirectoryPath(confirmButtonText: '保存图片到此文件夹');
    _check(epoch);
    if (path == null) return false;
    await preferences.writePreference(key, path);
    _check(epoch);
    return true;
  }
  Future<void> openFolder([Artwork? work]) async {
    final epoch = api.epoch;
    final record = work == null ? null : await database.record(scope, work.id);
    _check(epoch);
    if (work != null && record == null) throw const ApiException('本机没有这张图片的文件记录');
    final base = record == null ? await _base(epoch) : record['base'] as String;
    final relative = record == null ? _relativeRoot : File(record['relativePath'] as String).parent.path;
    await _access(base, epoch, (resolved) async {
      final directory = Directory('$resolved${Platform.pathSeparator}$relative');
      await directory.create(recursive: true);
      _check(epoch);
      final opened = Platform.isMacOS ? await _channel.invokeMethod<bool>('openImageFolder', directory.path) ?? false : await launchUrl(directory.uri);
      if (!opened) throw const ApiException('无法打开文件夹，请复制保存路径后手动打开');
    });
  }
  Future<List<Artwork>> works({bool favorites = false}) async {
    final epoch = api.epoch;
    _check(epoch);
    final records = await database.records(scope);
    _check(epoch);
    final works = records.where((item) => (item['source'] == 'local-favorite') == favorites).map(Artwork.fromJson).toList();
    works.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return works;
  }
  Future<MediaBytes> read(String source) async {
    final epoch = api.epoch;
    _check(epoch);
    final record = await database.record(scope, source.substring('huabu-local:'.length));
    _check(epoch);
    if (record == null) throw const ApiException('本机没有这张图片的记录，请在所属账号查看');
    return _access(record['base'] as String, epoch, (base) async {
      final bytes = await File('$base${Platform.pathSeparator}${record['relativePath']}').readAsBytes();
      _check(epoch);
      return MediaBytes(bytes: bytes, mimeType: record['mimeType'] as String);
    });
  }
  Future<Artwork> _save(MediaBytes image, {required String id, required String title, required String prompt, required String model, required String ratio, required String runId, required DateTime date, String source = 'local', String quality = 'auto', int requestedCount = 1, Artwork? original}) async {
    final epoch = api.epoch, owner = scope, relativeRoot = _relativeRoot;
    _check(epoch);
    final previous = await database.record(owner, id);
    _check(epoch);
    final base = await _base(epoch);
    _check(epoch);
    final mime = lookupMimeType('', headerBytes: image.bytes) ?? image.mimeType;
    final extension = switch (mime) { 'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp', 'image/gif' => 'gif', _ => throw const ApiException('当前图片格式无法保存，请保留结果后核对接口') };
    final day = date.toLocal().toIso8601String().split('T').first;
    final relative = previous?['base'] == base ? previous!['relativePath'] as String : '$relativeRoot${Platform.pathSeparator}$day${Platform.pathSeparator}huabu-$id.$extension';
    final buffer = await ui.ImmutableBuffer.fromUint8List(image.bytes);
    late int width, height;
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try { width = descriptor.width; height = descriptor.height; }
      finally { descriptor.dispose(); }
    } finally { buffer.dispose(); }
    _check(epoch);
    await _access(base, epoch, (resolved) async {
      final file = File('$resolved${Platform.pathSeparator}$relative');
      await file.parent.create(recursive: true);
      _check(epoch);
      final existing = await file.exists() ? await file.readAsBytes() : null;
      _check(epoch);
      if (existing != null && sha256.convert(existing) != sha256.convert(image.bytes)) throw const ApiException('本机同名图片内容不同，已停止覆盖，请手动检查保存目录');
      if (existing == null) {
        final temporary = File('${file.path}.part');
        await temporary.writeAsBytes(image.bytes, flush: true);
        _check(epoch);
        await temporary.rename(file.path);
      }
      _check(epoch);
    });
    final work = Artwork(id: id, title: title, prompt: prompt, model: model, ratio: ratio, runId: runId, createdAt: date, source: source, recordKey: runId, imageUrl: 'huabu-local:$id', width: width, height: height, bytes: image.bytes.length, mimeType: mime, author: original?.author ?? '', description: original?.description ?? '', category: original?.category ?? '');
    _check(epoch);
    await database.put(owner, id, {...work.toJson(), 'base': base, 'relativePath': relative, 'quality': quality, 'requestedCount': requestedCount});
    _check(epoch);
    return work;
  }
  Future<List<Artwork>> saveGeneration(GenerationOutput output) async {
    final epoch = api.epoch;
    final works = <Artwork>[], seen = <String>{};
    for (final image in output.images) {
      _check(epoch);
      final id = sha256.convert(utf8.encode('${output.runId}:${sha256.convert(image.bytes)}')).toString();
      if (!seen.add(id)) continue;
      works.add(await _save(image, id: id, title: output.prompt, prompt: output.prompt, model: output.model, ratio: output.ratio, runId: output.runId, date: output.receivedAt ?? output.run?.createdAt ?? DateTime.now(), quality: output.quality, requestedCount: output.requestedCount));
    }
    _check(epoch);
    return works;
  }
  Future<void> favorite(Artwork work, MediaBytes image) async {
    await _save(image, id: favoriteId(work), title: work.title, prompt: work.prompt, model: work.model, ratio: work.ratio, runId: work.runId, date: DateTime.now(), source: 'local-favorite', original: work);
  }
  Future<void> remove(Artwork work) async {
    final epoch = api.epoch;
    _check(epoch);
    await database.remove(scope, work.id);
    _check(epoch);
    // Removing a library entry keeps the dated original on disk.
  }
}
