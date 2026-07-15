import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/services/danmaku_sink.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';

void main() {
  final items = [
    DanmakuItem(
      time: const Duration(seconds: 1),
      content: 'sink',
      danmakuId: '42',
      senderId: 'sender',
      source: 'test',
    ),
  ];

  test('internal sink preserves modeled metadata at the legacy boundary', () {
    final output = const InternalPlayerSink().deliver(items);

    expect(output.single['danmakuId'], '42');
    expect(output.single['senderId'], 'sender');
    expect(output.single['source'], 'test');
  });

  test('external sink produces ASS from the same typed items', () {
    const sink = ExternalAssSink(AssExportSettings(fontSize: 36));
    final result = sink.deliver(items);

    expect(result.ass, contains('sink'));
    expect(result.events.single.content, 'sink');
    expect(sink.buildLayoutInput(items).single['source'], 'test');
  });
}
