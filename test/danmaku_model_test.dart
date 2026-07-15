import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/services/danmaku_normalizer.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';


void main() {
  group('DanmakuItem', () {
    test('round trips the typed cache format without losing metadata', () {
      final item = DanmakuItem(
        time: const Duration(microseconds: 1234567),
        content: '测试弹幕',
        mode: DanmakuMode.top,
        colorRgb: 0x123456,
        senderId: 'sender-hash',
        danmakuId: 'comment-id',
        sentAt: DateTime.utc(2026, 7, 15, 12, 30),
        source: ' dandanplay ',
        fontSize: 25,
        pool: 1,
        weight: 8,
        extra: const {'pluginField': 'kept'},
      );

      final restored = DanmakuItem.fromJson(item.toJson());

      expect(restored.time, item.time);
      expect(restored.content, item.content);
      expect(restored.mode, item.mode);
      expect(restored.colorRgb, item.colorRgb);
      expect(restored.senderId, item.senderId);
      expect(restored.danmakuId, item.danmakuId);
      expect(restored.sentAt, item.sentAt);
      expect(restored.source, 'dandanplay');
      expect(restored.extra, item.extra);
      expect(restored.stableId, 'dandanplay:comment-id');
    });

    test('derives the same fallback stable ID from immutable source fields', () {
      final first = DanmakuItem(
        time: const Duration(milliseconds: 1500),
        content: 'no source id',
        senderId: 'sender',
        source: 'local:test',
      );
      final second = DanmakuItem.fromJson(first.toJson());

      expect(second.stableId, first.stableId);
      expect(first.stableId, startsWith('local:test:'));
    });

    test('never treats cid as a sender identity', () {
      final item = DanmakuItem.fromMap(const {
        'time': 1,
        'content': 'identity test',
        'cid': 'comment-id',
      });

      expect(item.senderId, isNull);
      expect(item.danmakuId, 'comment-id');
      expect(resolveDanmakuSenderId(const {'cid': 'comment-id'}), isNull);
      expect(
        resolveDanmakuSenderId(const {'p': '1,1,16777215,sender-id'}),
        'sender-id',
      );
    });
  });

  group('DandanplayDanmakuNormalizer', () {
    test('normalizes IO, Web and proxy response shapes identically', () {
      const rawComment = {
        'p': '1.25,5,16711680,sender-hash',
        'm': 'hello',
        'cid': 42,
      };
      const normalizedComment = {
        'time': 1.25,
        'content': 'hello',
        'originalType': 5,
        'color': 'rgb(255,0,0)',
        'senderId': 'sender-hash',
        'danmakuId': '42',
      };

      final io = DandanplayDanmakuNormalizer.normalizeResponse({
        'comments': [rawComment],
      });
      final web = DandanplayDanmakuNormalizer.normalizeResponse({
        'comments': [normalizedComment],
      });
      final proxy = DandanplayDanmakuNormalizer.normalizeResponse({
        'data': {
          'comments': [rawComment],
        },
      });

      expect(io.single.toJson(), web.single.toJson());
      expect(proxy.single.toJson(), io.single.toJson());
      expect(io.single.senderId, 'sender-hash');
      expect(io.single.danmakuId, '42');
      expect(io.single.source, 'dandanplay');
      expect(io.single.mode, DanmakuMode.top);
    });

    test('isolates malformed fields and prefers an explicit sender', () {
      final items = DandanplayDanmakuNormalizer.normalizeResponse({
        'comments': [
          {
            1: 'ignored',
            'p': 'NaN,invalid,invalid,p-sender',
            'm': 'safe',
            'senderId': 'explicit-sender',
            'cid': 'comment-id',
          },
        ],
      });

      expect(items, hasLength(1));
      expect(items.single.time, Duration.zero);
      expect(items.single.mode, DanmakuMode.scroll);
      expect(items.single.colorRgb, 0xFFFFFF);
      expect(items.single.senderId, 'explicit-sender');
      expect(items.single.danmakuId, 'comment-id');
    });

    test('keeps the legacy adapter at the pipeline boundary', () {
      final items = DandanplayDanmakuNormalizer.normalizeResponse(const {
        'comments': [
          {'p': '2,1,16777215,user', 'm': 'adapter', 'cid': 'legacy-id'},
        ],
      });

      final legacy = DanmakuMapAdapter.toLegacyList(items);
      final restored = DanmakuMapAdapter.fromLegacyList(legacy);

      expect(restored.single.toJson(), items.single.toJson());
      expect(legacy.single['source'], 'dandanplay');
      expect(legacy.single['cid'], isNotNull);
    });

    test('distinguishes a valid empty library from a malformed response', () {
      expect(
        DandanplayDanmakuNormalizer.hasCommentList(const {'comments': []}),
        isTrue,
      );
      expect(
        DandanplayDanmakuNormalizer.normalizeLegacyResponse(
          const {'comments': []},
        )['count'],
        0,
      );
      expect(
        DandanplayDanmakuNormalizer.hasCommentList(const {'count': 0}),
        isFalse,
      );
    });
  });
}
