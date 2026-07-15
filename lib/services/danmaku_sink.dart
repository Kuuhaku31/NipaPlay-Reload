import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/ass_danmaku.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';

abstract class DanmakuSink<T> {
  const DanmakuSink();

  T deliver(Iterable<DanmakuItem> items);
}

class InternalPlayerSink extends DanmakuSink<List<Map<String, dynamic>>> {
  const InternalPlayerSink();

  @override
  List<Map<String, dynamic>> deliver(Iterable<DanmakuItem> items) {
    return items.map((item) => item.toMap()).toList();
  }
}

class ExternalAssSink extends DanmakuSink<DanmakuAssConversionResult> {
  const ExternalAssSink(this.settings);

  final AssExportSettings settings;

  List<Map<String, dynamic>> buildLayoutInput(
    Iterable<DanmakuItem> items,
  ) {
    return items.map((item) => item.toMap()).toList();
  }

  @override
  DanmakuAssConversionResult deliver(Iterable<DanmakuItem> items) {
    return convertDanmakuToAssWithEvents(buildLayoutInput(items), settings);
  }
}
