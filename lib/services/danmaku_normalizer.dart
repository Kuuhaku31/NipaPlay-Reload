// 弹幕响应标准化与旧 Map 协议适配

import 'dart:convert';

import 'package:nipaplay/models/danmaku/danmaku_item.dart';


/// 旧 `Map<String, dynamic>` 调用方与强类型弹幕之间的临时边界.
class DanmakuMapAdapter {

  static List<DanmakuItem> fromLegacyList(Iterable<dynamic> values) {
    return values
        .whereType<Map>()
        .map(DanmakuItem.fromMap)
        .where((item) => item.content.isNotEmpty && !item.time.isNegative)
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> toLegacyList(
    Iterable<DanmakuItem> items,
  ) {
    return items.map((item) {
      return <String, dynamic>{
        ...item.toMap(),
        if (item.danmakuId != null) 'cid': item.danmakuId,
      };
    }).toList(growable: false);
  }
}

/// 将弹弹play IO, Web 和代理返回统一为 [DanmakuItem].
///
/// 弹弹play的 `p` 字段格式为 `时间,模式,颜色,发送者标识`; `cid` 是弹幕 ID,
/// 不得作为发送者标识回退. `withRelated=true` 返回的内容仍属于同一个
/// episode 弹幕库, 因而统一使用 `dandanplay` 来源身份.
class DandanplayDanmakuNormalizer {
  static const String sourceId = 'dandanplay';

  static bool hasCommentList(dynamic response) {
    final decoded = response is String ? json.decode(response) : response;
    final payload = decoded is Map && decoded['data'] is Map
        ? decoded['data']
        : decoded;
    return payload is Map && payload['comments'] is Iterable;
  }

  static List<DanmakuItem> normalizeResponse(dynamic response) {
    final decoded = response is String ? json.decode(response) : response;
    final payload = decoded is Map && decoded['data'] is Map
        ? decoded['data']
        : decoded;
    final comments = payload is Map ? payload['comments'] : payload;
    if (comments is! Iterable) return const [];

    final items = <DanmakuItem>[];
    final seen = <String>{};
    for (final raw in comments) {
      if (raw is! Map) continue;
      final item = normalizeComment(raw);
      if (item == null) continue;
      final displayIdentity = <Object>[
        item.time.inMicroseconds,
        item.content,
        item.mode.typeName,
        item.colorRgb,
      ].join('\u0000');
      if (seen.add(displayIdentity)) items.add(item);
    }
    return List<DanmakuItem>.unmodifiable(items);
  }

  static DanmakuItem? normalizeComment(Map<dynamic, dynamic> comment) {
    final raw = <String, dynamic>{};
    for (final entry in comment.entries) {
      if (entry.key is String) raw[entry.key as String] = entry.value;
    }
    final p = raw['p']?.toString().split(',');
    final explicitSender = _resolveExplicitSender(raw);

    final canonical = <String, dynamic>{
      ...raw,
      if (p != null && p.isNotEmpty) 'time': p[0],
      if (p != null && p.length > 1) 'originalType': p[1],
      if (p != null && p.length > 2) 'color': p[2],
      if (explicitSender == null &&
          p != null &&
          p.length > 3 &&
          _nonEmpty(p[3]) != null)
        'senderId': p[3],
      if (raw['m'] != null) 'content': raw['m'],
      if (_nonEmpty(raw['danmakuId'] ?? raw['cid'] ?? raw['id']) != null)
        'danmakuId': raw['danmakuId'] ?? raw['cid'] ?? raw['id'],
      'source': sourceId,
    };
    final item = DanmakuItem.fromMap(canonical);
    if (item.content.isEmpty || item.time.isNegative) return null;
    return item;
  }

  /// 迁移期供旧服务 API 返回标准 Map, 所有平台复用同一转换结果.
  static Map<String, dynamic> normalizeLegacyResponse(dynamic response) {
    final decoded = response is String ? json.decode(response) : response;
    final items = normalizeResponse(decoded);
    final fromCache = decoded is Map && decoded['fromCache'] == true;
    return <String, dynamic>{
      'comments': DanmakuMapAdapter.toLegacyList(items),
      'fromCache': fromCache,
      'count': items.length,
    };
  }

  static String? _nonEmpty(dynamic value) {
    if (value == null || value is Map || value is Iterable) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == '0' || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  static String? _resolveExplicitSender(Map<String, dynamic> raw) {
    for (final key in const [
      'senderId',
      'sender',
      'userId',
      'userID',
      'uid',
      'midHash',
      'userHash',
      'hash',
    ]) {
      final value = _nonEmpty(raw[key]);
      if (value != null) return value;
    }
    for (final nested in [raw['user'], raw['sender']]) {
      if (nested is! Map) continue;
      for (final key in const ['id', 'uid', 'hash']) {
        final value = _nonEmpty(nested[key]);
        if (value != null) return value;
      }
    }
    return null;
  }
}
