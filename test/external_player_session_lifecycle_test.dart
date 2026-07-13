import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/services/external_player_console_service.dart';

ExternalPlayerSession _session(String id, int pid) => ExternalPlayerSession(
      id: id,
      playerPath: '/usr/bin/mpv',
      mediaPath: '/video/$id.mkv',
      processId: pid,
    );

void main() {
  test('tracks one window for every session', () {
    final lifecycle = ExternalPlayerSessionLifecycle(
      readWindowIds: () async => <int>{10, 11},
      isProcessRunning: (_) async => true,
      closeWindow: (_) async {},
    );

    lifecycle.track(_session('a', 100), 10);
    lifecycle.track(_session('b', 101), 11);

    expect(lifecycle.activeSessionCount, 2);
    expect(lifecycle.windowIdForSession('a'), 10);
    expect(lifecycle.windowIdForSession('b'), 11);
  });

  test('manual window close only untracks its session', () async {
    final closedWindows = <int>[];
    final lifecycle = ExternalPlayerSessionLifecycle(
      readWindowIds: () async => <int>{11},
      isProcessRunning: (_) async => true,
      closeWindow: (id) async => closedWindows.add(id),
    );
    lifecycle.track(_session('a', 100), 10);
    lifecycle.track(_session('b', 101), 11);

    await lifecycle.poll();

    expect(lifecycle.windowIdForSession('a'), isNull);
    expect(lifecycle.windowIdForSession('b'), 11);
    expect(closedWindows, isEmpty);
  });

  test('player exit closes only its console window', () async {
    final closedWindows = <int>[];
    final lifecycle = ExternalPlayerSessionLifecycle(
      readWindowIds: () async => <int>{10, 11},
      isProcessRunning: (pid) async => pid != 100,
      closeWindow: (id) async => closedWindows.add(id),
    );
    lifecycle.track(_session('a', 100), 10);
    lifecycle.track(_session('b', 101), 11);

    await lifecycle.poll();

    expect(lifecycle.windowIdForSession('a'), isNull);
    expect(lifecycle.windowIdForSession('b'), 11);
    expect(closedWindows, <int>[10]);
  });
}
