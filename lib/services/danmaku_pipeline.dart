import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/danmaku_source.dart';

typedef DanmakuTransform = List<DanmakuItem> Function(
  List<DanmakuItem> items,
);
typedef DanmakuPredicate = bool Function(DanmakuItem item);
typedef DanmakuItemTransform = DanmakuItem Function(DanmakuItem item);

class DanmakuPipelineResult {
  DanmakuPipelineResult({
    required Iterable<DanmakuItem> mergedItems,
    required Iterable<DanmakuItem> outputItems,
  })  : mergedItems = List<DanmakuItem>.unmodifiable(mergedItems),
        outputItems = List<DanmakuItem>.unmodifiable(outputItems);

  final List<DanmakuItem> mergedItems;
  final List<DanmakuItem> outputItems;
}

class DanmakuPipeline {
  const DanmakuPipeline();

  DanmakuPipelineResult process(
    Iterable<DanmakuSource> sources, {
    DanmakuTransform? pluginTransform,
    DanmakuPredicate? shouldInclude,
    DanmakuItemTransform? prepareForDisplay,
  }) {
    final merged = <DanmakuItem>[];
    final seen = <String>{};

    for (final source in sources) {
      if (!source.enabled || source.loadState == DanmakuSourceLoadState.failed) {
        continue;
      }
      for (final original in source.items) {
        final sourced = original.source == null
            ? original.copyWith(source: source.id)
            : original;
        final shifted = source.offset == Duration.zero
            ? sourced
            : sourced.copyWith(time: sourced.time + source.offset);
        if (seen.add(shifted.stableId)) merged.add(shifted);
      }
    }

    merged.sort(_compareTime);
    final pluginOutput = pluginTransform == null
        ? List<DanmakuItem>.of(merged)
        : pluginTransform(List<DanmakuItem>.unmodifiable(merged));
    final output = pluginOutput
        .where((item) => shouldInclude?.call(item) ?? true)
        .map((item) => prepareForDisplay?.call(item) ?? item)
        .toList()
      ..sort(_compareTime);

    return DanmakuPipelineResult(
      mergedItems: merged,
      outputItems: output,
    );
  }

  static int _compareTime(DanmakuItem a, DanmakuItem b) {
    return a.time.compareTo(b.time);
  }
}
