import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/danmaku/danmaku_batch.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/services/danmaku_normalizer.dart';
import 'package:nipaplay/services/danmaku_repository.dart';


void main() {
  const request = DanmakuRequest(
    sourceId: 'dandanplay',
    episodeId: '1001',
    animeId: 42,
    cacheVariant: 'chConvert=1',
  );

  test('DanmakuBatch round trips typed metadata', () {
    final batch = DanmakuBatch(
      sourceId: request.sourceId,
      episodeId: request.episodeId,
      animeId: request.animeId,
      fetchedAt: DateTime.utc(2026, 7, 15),
      items: [
        DanmakuItem(
          time: const Duration(seconds: 1),
          content: 'metadata',
          senderId: 'sender',
          danmakuId: 'comment',
          source: 'dandanplay',
          extra: const {'provider': 'related'},
        ),
      ],
    );

    final restored = DanmakuBatch.fromJson(batch.toJson());

    expect(restored.sourceId, batch.sourceId);
    expect(restored.episodeId, batch.episodeId);
    expect(restored.fetchedAt, batch.fetchedAt);
    expect(restored.items.single.toJson(), batch.items.single.toJson());
  });

  test('cache hit, including an empty batch, skips remote fetch', () async {
    final store = MemoryDanmakuCacheStore();
    final emptyBatch = DanmakuBatch(
      sourceId: request.sourceId,
      episodeId: request.episodeId,
      animeId: request.animeId,
      fetchedAt: DateTime.utc(2026, 7, 15),
      items: const [],
    );
    await store.write(request, emptyBatch);
    var fetchCount = 0;
    final repository = DanmakuRepository(
      fetchRemote: (_) async {
        fetchCount++;
        return const {'comments': []};
      },
      normalize: DandanplayDanmakuNormalizer.normalizeResponse,
      cacheStore: store,
    );

    final result = await repository.load(request);

    expect(result.isFromCache, isTrue);
    expect(result.batch.items, isEmpty);
    expect(fetchCount, 0);
  });

  test('coalesces concurrent requests and preserves distinct comment IDs', () async {
    final response = Completer<dynamic>();
    var fetchCount = 0;
    final repository = DanmakuRepository(
      fetchRemote: (_) {
        fetchCount++;
        return response.future;
      },
      normalize: DandanplayDanmakuNormalizer.normalizeResponse,
      cacheStore: MemoryDanmakuCacheStore(),
      now: () => DateTime.utc(2026, 7, 15),
    );

    final first = repository.load(request);
    final second = repository.load(request);
    await Future<void>.delayed(Duration.zero);
    expect(fetchCount, 1);

    response.complete(const {
      'comments': [
        {'p': '1,1,16777215,user', 'm': 'same', 'cid': 'one'},
        {'p': '1,1,16777215,user', 'm': 'same', 'cid': 'two'},
        {'p': '1,1,16777215,user', 'm': 'same', 'cid': 'one'},
      ],
    });
    final results = await Future.wait([first, second]);

    expect(identical(results[0], results[1]), isTrue);
    expect(results.first.batch.items, hasLength(2));
    expect(
      results.first.batch.items.map((item) => item.danmakuId),
      ['one', 'two'],
    );
  });

  test('cache failures do not hide a successful remote result', () async {
    final repository = DanmakuRepository(
      fetchRemote: (_) async => const {
        'comments': [
          {'p': '2,1,16777215,user', 'm': 'remote'},
        ],
      },
      normalize: DandanplayDanmakuNormalizer.normalizeResponse,
      cacheStore: _FailingCacheStore(),
    );

    final result = await repository.load(request);

    expect(result.isFromCache, isFalse);
    expect(result.batch.items.single.content, 'remote');
  });
}

class _FailingCacheStore implements DanmakuCacheStore {
  @override
  Future<DanmakuBatch?> read(DanmakuRequest request) {
    throw StateError('read failed');
  }

  @override
  Future<void> write(DanmakuRequest request, DanmakuBatch batch) {
    throw StateError('write failed');
  }
}
