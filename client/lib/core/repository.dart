import 'dart:convert';
import 'dart:ui' as ui;

import 'package:uuid/uuid.dart';

import 'api/api_client.dart';
import 'models.dart';
import '../features/generation/generation_service.dart';
import '../features/works/local_image_store.dart';

class HuabuRepository {
  HuabuRepository(this.api, {this.localImages});
  final ApiClient api;
  final LocalImageStore? localImages;
  LocalImageStore get _local => localImages ?? (throw const ApiException('本机图片存储尚未初始化'));
  Future<List<Artwork>> works() => _local.works();
  Future<List<Artwork>> favorites() => _local.works(favorites: true);
  static const _uuid = Uuid();
  static const _assetKey = 'infinite-canvas:asset_store';

  Future<List<Artwork>> serverWorks() async {
    final epoch = api.epoch;
    final works = <Artwork>[];
    for (final key in await api.storageKeys('image_generation_logs')) {
      api.assertEpoch(epoch);
      final record = await api.storageRead('image_generation_logs', key);
      if (record != null) works.addAll(Artwork.fromGenerationLog(jsonObject(record.value), key));
    }
    api.assertEpoch(epoch);
    works.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return works;
  }

  Future<List<Artwork>> serverFavorites() async {
    final epoch = api.epoch;
    final result = <Artwork>[];
    for (final key in await api.storageKeys('artwork_favorites')) {
      api.assertEpoch(epoch);
      final record = await api.storageRead('artwork_favorites', key);
      api.assertEpoch(epoch);
      if (record == null) continue;
      if (record.blob || record.value is! Map) throw const ApiException('收藏记录格式异常，请重新读取');
      result.add(Artwork.fromJson({...jsonObject(record.value), 'recordKey': key, 'source': 'favorite'}));
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<void> saveFavorite(Artwork work) async {
    final epoch = api.epoch;
    final image = LocalImageStore.isLocal(work.imageUrl) ? await _local.read(work.imageUrl) : await api.file(work.imageUrl);
    api.assertEpoch(epoch);
    await _local.favorite(work, image);
    api.assertEpoch(epoch);
  }

  Future<void> removeWorks(List<Artwork> works) async {
    final epoch = api.epoch;
    for (final work in works.where((work) => LocalImageStore.isLocal(work.imageUrl))) {
      api.assertEpoch(epoch);
      await _local.remove(work);
    }
    for (final work in works.where((work) => work.source == 'favorite')) {
      api.assertEpoch(epoch);
      await api.storageDelete('artwork_favorites', work.recordKey);
    }
    final keys = works.where((work) => work.source != 'favorite' && !LocalImageStore.isLocal(work.imageUrl)).map((work) => work.recordKey).where((key) => key.isNotEmpty).toSet();
    for (final key in keys) {
      api.assertEpoch(epoch);
      final record = await api.storageRead('image_generation_logs', key);
      api.assertEpoch(epoch);
      if (record == null) continue;
      final document = jsonObject(record.value);
      if (record.blob || document['images'] is! List) throw const ApiException('作品记录格式异常，已停止移除');
      final ids = works.where((work) => work.recordKey == key).map((work) => work.id).toSet();
      await api.storageWrite('image_generation_logs', key, {...document, 'images': (document['images'] as List).where((image) => !ids.contains(jsonString(jsonObject(image)['id']))).toList(), 'thumbnails': []}, revision: record.revision);
    }
    api.assertEpoch(epoch);
  }

  Future<Json> _storeImage(MediaBytes image, int epoch) async {
    api.assertEpoch(epoch);
    final codec = await ui.instantiateImageCodec(image.bytes);
    late int width, height;
    try {
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      frame.image.dispose();
    } finally { codec.dispose(); }
    api.assertEpoch(epoch);
    final key = 'image:${_uuid.v4()}';
    await api.storageWrite('image_files', key, image.bytes, revision: '0', mimeType: image.mimeType);
    return {'storageKey': key, 'dataUrl': '', 'width': width, 'height': height, 'bytes': image.bytes.length, 'mimeType': image.mimeType};
  }

  Future<List<Artwork>> saveGeneration(GenerationOutput output) async => _local.saveGeneration(output);

  Future<(Json, String)> _assetDocument(int epoch) async {
    api.assertEpoch(epoch);
    final record = await api.storageRead('app_state', _assetKey);
    api.assertEpoch(epoch);
    if (record == null) return (<String, dynamic>{'state': {'assets': []}, 'version': 0}, '0');
    final value = record.value;
    final document = value is String ? jsonDecode(value) : value;
    if (document is! Map || jsonObject(document['state'])['assets'] is! List) {
      throw const ApiException('素材列表格式异常，已停止保存以保护服务器数据');
    }
    return (jsonObject(document), record.revision);
  }

  List<AssetItem> _assets(Json document) =>
    (jsonObject(document['state'])['assets'] as List).map((value) => AssetItem.fromJson(jsonObject(value))).toList();

  Future<List<AssetItem>> assets() async => _assets((await _assetDocument(api.epoch)).$1);

  Future<void> _writeAssets(Json document, String revision, List<AssetItem> assets, int epoch) async {
    api.assertEpoch(epoch);
    final value = {...document, 'state': {...jsonObject(document['state']), 'assets': assets.map((item) => item.toJson()).toList()}};
    await api.storageWrite('app_state', _assetKey, jsonEncode(value), revision: revision);
  }

  Future<void> addImageAsset(MediaBytes image, String title) async {
    final epoch = api.epoch;
    final stored = await _storeImage(image, epoch);
    final (document, revision) = await _assetDocument(epoch);
    final now = DateTime.now();
    final asset = AssetItem(id: _uuid.v4(), kind: 'image', title: title, coverUrl: '', createdAt: now, updatedAt: now, data: stored);
    await _writeAssets(document, revision, [asset, ..._assets(document)], epoch);
  }

  Future<void> addTextAsset(String title, String content) async {
    final epoch = api.epoch;
    final (document, revision) = await _assetDocument(epoch);
    final now = DateTime.now();
    final asset = AssetItem(id: _uuid.v4(), kind: 'text', title: title, coverUrl: '', createdAt: now, updatedAt: now, data: {'content': content});
    await _writeAssets(document, revision, [asset, ..._assets(document)], epoch);
  }

  Future<void> addVideoAsset(MediaBytes media, String title, {String storageKey = '', int width = 0, int height = 0, int durationMs = 0}) async {
    final epoch = api.epoch;
    final key = storageKey.isEmpty ? 'video:${_uuid.v4()}' : storageKey;
    if (storageKey.isEmpty) await api.storageWrite('media_files', key, media.bytes, revision: '0', mimeType: media.mimeType);
    api.assertEpoch(epoch);
    final (document, revision) = await _assetDocument(epoch);
    final now = DateTime.now();
    final asset = AssetItem(id: _uuid.v4(), kind: 'video', title: title, coverUrl: '', createdAt: now, updatedAt: now,
      data: {'url': '', 'storageKey': key, 'bytes': media.bytes.length, 'mimeType': media.mimeType, 'durationMs': durationMs, 'width': width, 'height': height});
    await _writeAssets(document, revision, [asset, ..._assets(document)], epoch);
  }

  Future<void> removeAsset(String id) async {
    final epoch = api.epoch;
    final (document, revision) = await _assetDocument(epoch);
    await _writeAssets(document, revision, _assets(document).where((item) => item.id != id).toList(), epoch);
    // Attachments may still belong to canvases or generation logs.
  }
}
