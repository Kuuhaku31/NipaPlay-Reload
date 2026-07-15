// 弹幕来源请求与批次模型

import 'package:nipaplay/models/danmaku/danmaku_item.dart';


/// 一次弹幕来源加载请求的稳定身份.
class DanmakuRequest {
  const DanmakuRequest({
    required this.sourceId,
    required this.episodeId,
    required this.animeId,
    this.cacheVariant = '',
  });

  final String sourceId;
  final String episodeId;
  final int animeId;
  final String cacheVariant;

  String get cacheKey => '$sourceId:$episodeId:$cacheVariant';
}

/// 某来源一次加载得到的不可变弹幕结果.
class DanmakuBatch {
  DanmakuBatch({
    required this.sourceId,
    required this.episodeId,
    required this.animeId,
    required this.fetchedAt,
    required Iterable<DanmakuItem> items,
  }) : items = List<DanmakuItem>.unmodifiable(items);

  final String sourceId;
  final String episodeId;
  final int animeId;
  final DateTime fetchedAt;
  final List<DanmakuItem> items;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': 2,
      'source': sourceId,
      'episodeId': episodeId,
      'animeId': animeId,
      'timestamp': fetchedAt.millisecondsSinceEpoch,
      'count': items.length,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
  }

  factory DanmakuBatch.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is Iterable
        ? rawItems
            .whereType<Map>()
            .map((item) => DanmakuItem.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false)
        : const <DanmakuItem>[];
    final timestamp = json['timestamp'];
    final timestampMs = timestamp is num
        ? timestamp.toInt()
        : int.tryParse(timestamp?.toString() ?? '') ?? 0;
    final rawAnimeId = json['animeId'];
    final animeId = rawAnimeId is num
        ? rawAnimeId.toInt()
        : int.tryParse(rawAnimeId?.toString() ?? '') ?? 0;
    return DanmakuBatch(
      sourceId: json['source']?.toString() ?? 'dandanplay',
      episodeId: json['episodeId']?.toString() ?? '',
      animeId: animeId,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
      items: items,
    );
  }
}

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.batch,
    required this.isFromCache,
  });

  final DanmakuBatch batch;
  final bool isFromCache;
}
