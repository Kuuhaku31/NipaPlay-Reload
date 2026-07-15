import 'package:nipaplay/models/danmaku/danmaku_item.dart';

enum DanmakuSourceLoadState {
  idle,
  loading,
  ready,
  failed,
}

class DanmakuSource {
  DanmakuSource({
    required this.id,
    required this.name,
    required this.provider,
    Iterable<DanmakuItem> items = const [],
    this.enabled = true,
    this.offset = Duration.zero,
    this.loadState = DanmakuSourceLoadState.ready,
    this.error,
    this.episodeId,
    this.animeId,
    this.filePath,
    this.loadedAt,
  }) : items = List<DanmakuItem>.unmodifiable(items);

  final String id;
  final String name;
  final String provider;
  final List<DanmakuItem> items;
  final bool enabled;
  final Duration offset;
  final DanmakuSourceLoadState loadState;
  final String? error;
  final String? episodeId;
  final String? animeId;
  final String? filePath;
  final DateTime? loadedAt;

  DanmakuSource copyWith({
    String? name,
    String? provider,
    Iterable<DanmakuItem>? items,
    bool? enabled,
    Duration? offset,
    DanmakuSourceLoadState? loadState,
    String? error,
    String? episodeId,
    String? animeId,
    String? filePath,
    DateTime? loadedAt,
  }) {
    return DanmakuSource(
      id: id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      items: items ?? this.items,
      enabled: enabled ?? this.enabled,
      offset: offset ?? this.offset,
      loadState: loadState ?? this.loadState,
      error: error,
      episodeId: episodeId ?? this.episodeId,
      animeId: animeId ?? this.animeId,
      filePath: filePath ?? this.filePath,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }

  Map<String, dynamic> toLegacyMap() {
    return <String, dynamic>{
      'name': name,
      'source': provider,
      'danmakuList': items.map((item) => item.toMap()).toList(),
      'count': items.length,
      'enabled': enabled,
      'offset': offset.inMicroseconds / Duration.microsecondsPerSecond,
      'loadState': loadState.name,
      if (error != null) 'error': error,
      if (episodeId != null) 'episodeId': episodeId,
      if (animeId != null) 'animeId': animeId,
      if (filePath != null) 'filePath': filePath,
      if (loadedAt != null) 'loadTime': loadedAt,
    };
  }
}
