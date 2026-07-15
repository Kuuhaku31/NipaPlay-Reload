// 弹幕统一获取, 缓存和并发请求管理

import 'dart:async';

import 'package:nipaplay/models/danmaku/danmaku_batch.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';


abstract class DanmakuCacheStore {
  Future<DanmakuBatch?> read(DanmakuRequest request);
  Future<void> write(DanmakuRequest request, DanmakuBatch batch);
}

class MemoryDanmakuCacheStore implements DanmakuCacheStore {
  final Map<String, DanmakuBatch> _batches = {};

  @override
  Future<DanmakuBatch?> read(DanmakuRequest request) async {
    return _batches[request.cacheKey];
  }

  @override
  Future<void> write(DanmakuRequest request, DanmakuBatch batch) async {
    _batches[request.cacheKey] = batch;
  }
}

typedef DanmakuRemoteFetcher = Future<dynamic> Function(
  DanmakuRequest request,
);
typedef DanmakuResponseNormalizer = List<DanmakuItem> Function(
  dynamic response,
);

/// 播放, 预加载和外部导出共同使用的唯一远程加载入口.
class DanmakuRepository {
  DanmakuRepository({
    required DanmakuRemoteFetcher fetchRemote,
    required DanmakuResponseNormalizer normalize,
    required DanmakuCacheStore cacheStore,
    DateTime Function()? now,
  }) :
    _fetchRemote = fetchRemote,
    _normalize = normalize,
    _cacheStore = cacheStore,
    _now = now ?? DateTime.now;

  final DanmakuRemoteFetcher _fetchRemote;
  final DanmakuResponseNormalizer _normalize;
  final DanmakuCacheStore _cacheStore;
  final DateTime Function() _now;
  final Map<String, Future<DanmakuLoadResult>> _inFlight = {};

  Future<DanmakuLoadResult> load(
    DanmakuRequest request, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      try {
        final cached = await _cacheStore.read(request);
        if (cached != null) {
          return DanmakuLoadResult(batch: cached, isFromCache: true);
        }
      } catch (_) {
        // 缓存损坏或暂时不可用时继续走远程来源.
      }
    }

    final existing = _inFlight[request.cacheKey];
    if (existing != null) return existing;

    final future = _loadRemote(request);
    _inFlight[request.cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[request.cacheKey], future)) {
        _inFlight.remove(request.cacheKey);
      }
    }
  }

  Future<DanmakuLoadResult> _loadRemote(DanmakuRequest request) async {
    final response = await _fetchRemote(request);
    final items = _deduplicate(_normalize(response));
    final batch = DanmakuBatch(
      sourceId: request.sourceId,
      episodeId: request.episodeId,
      animeId: request.animeId,
      fetchedAt: _now(),
      items: items,
    );
    try {
      await _cacheStore.write(request, batch);
    } catch (_) {
      // 缓存写入失败不应丢弃已经成功取得的远程结果.
    }
    return DanmakuLoadResult(batch: batch, isFromCache: false);
  }

  List<DanmakuItem> _deduplicate(Iterable<DanmakuItem> items) {
    final seen = <String>{};
    return items
        .where((item) => seen.add(item.stableId))
        .toList(growable: false);
  }
}
