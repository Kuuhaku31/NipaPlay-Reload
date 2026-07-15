import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/danmaku_source.dart';
import 'package:nipaplay/services/danmaku_pipeline.dart';

void main() {
  test('merges enabled sources, applies offsets, and isolates failures', () {
    const pipeline = DanmakuPipeline();
    final result = pipeline.process([
      DanmakuSource(
        id: 'first',
        name: 'First',
        provider: 'local',
        offset: const Duration(seconds: 2),
        items: [DanmakuItem(time: Duration.zero, content: 'shifted')],
      ),
      DanmakuSource(
        id: 'failed',
        name: 'Failed',
        provider: 'remote',
        loadState: DanmakuSourceLoadState.failed,
        error: 'network error',
        items: [DanmakuItem(time: Duration.zero, content: 'ignored')],
      ),
      DanmakuSource(
        id: 'disabled',
        name: 'Disabled',
        provider: 'local',
        enabled: false,
        items: [DanmakuItem(time: Duration.zero, content: 'ignored too')],
      ),
    ]);

    expect(result.outputItems, hasLength(1));
    expect(result.outputItems.single.content, 'shifted');
    expect(result.outputItems.single.time, const Duration(seconds: 2));
    expect(result.outputItems.single.source, 'first');
  });

  test('runs plugin, block, display, and sort exactly once after merge', () {
    var pluginCalls = 0;
    var blockCalls = 0;
    var displayCalls = 0;
    final result = const DanmakuPipeline().process(
      [
        DanmakuSource(
          id: 'one',
          name: 'One',
          provider: 'local',
          items: [
            DanmakuItem(time: const Duration(seconds: 2), content: 'keep'),
          ],
        ),
        DanmakuSource(
          id: 'two',
          name: 'Two',
          provider: 'local',
          items: [
            DanmakuItem(time: const Duration(seconds: 1), content: 'block'),
          ],
        ),
      ],
      pluginTransform: (items) {
        pluginCalls++;
        return items;
      },
      shouldInclude: (item) {
        blockCalls++;
        return item.content != 'block';
      },
      prepareForDisplay: (item) {
        displayCalls++;
        return item.copyWith(content: '${item.content}!');
      },
    );

    expect(pluginCalls, 1);
    expect(blockCalls, 2);
    expect(displayCalls, 1);
    expect(result.outputItems.single.content, 'keep!');
  });
}
