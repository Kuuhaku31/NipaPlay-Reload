import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/services/external_player_console_service.dart';

ExternalPlayerSession _session(int processId) => ExternalPlayerSession(
      playerPath: '/bin/mpv',
      mediaPath: '/video/$processId.mkv',
      processId: processId,
      animeTitle: '测试番剧',
      episodeTitle: '第 1 话',
      episodeId: 12345,
    );

void main() {
  test('only keeps the latest external player session', () async {
    final terminated = <int>[];
    final service = ExternalPlayerConsoleService(
      processProbe: (_) async => true,
      terminateProcess: (pid) {
        terminated.add(pid);
        return true;
      },
      monitorInterval: const Duration(days: 1),
    );
    addTearDown(service.dispose);

    await service.showSession(_session(100));
    await service.showSession(_session(101));

    expect(service.session?.processId, 101);
    expect(terminated, <int>[100]);
  });

  test('close button behavior terminates player and hides console', () async {
    final terminated = <int>[];
    final service = ExternalPlayerConsoleService(
      processProbe: (_) async => true,
      terminateProcess: (pid) {
        terminated.add(pid);
        return true;
      },
      monitorInterval: const Duration(days: 1),
    );
    addTearDown(service.dispose);
    await service.showSession(_session(100));

    await service.closePlayerAndConsole();
    await service.closePlayerAndConsole();

    expect(service.session, isNull);
    expect(terminated, <int>[100]);
  });

  test('console hides when player exits without terminating it again',
      () async {
    final terminated = <int>[];
    final service = ExternalPlayerConsoleService(
      processProbe: (_) async => false,
      terminateProcess: (pid) {
        terminated.add(pid);
        return true;
      },
      monitorInterval: const Duration(days: 1),
    );
    addTearDown(service.dispose);
    await service.showSession(_session(100));

    await service.refreshProcessState();

    expect(service.session, isNull);
    expect(terminated, isEmpty);
  });

  test('stale process check does not hide a replacement session', () async {
    final probeResult = Completer<bool>();
    final service = ExternalPlayerConsoleService(
      processProbe: (_) => probeResult.future,
      terminateProcess: (_) => true,
      monitorInterval: const Duration(days: 1),
    );
    addTearDown(service.dispose);
    final first = _session(100);
    final replacement = _session(100);
    await service.showSession(first);

    final checking = service.refreshProcessState();
    await service.showSession(replacement);
    probeResult.complete(false);
    await checking;

    expect(service.session, same(replacement));
  });
}
