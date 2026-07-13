// external_player_session_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/external_player_session.dart';

void main() {
  test('external player session survives multi-window argument round trip', () {
    const source = ExternalPlayerSession(
      id: 'session-1',
      playerPath: '/usr/bin/mpv',
      mediaPath: '/video/episode.mkv',
      processId: 4321,
      animeTitle: '测试番剧',
      episodeTitle: '第 1 话',
      episodeId: 12345,
    );

    final parsed = ExternalPlayerSession.tryParseLaunchArguments([
      'multi_window',
      '7',
      source.toWindowArgumentsJson(),
    ]);

    expect(parsed, isNotNull);
    expect(parsed!.id, 'session-1');
    expect(parsed.processId, 4321);
    expect(parsed.animeTitle, '测试番剧');
    expect(parsed.episodeTitle, '第 1 话');
    expect(parsed.episodeId, 12345);
  });

  test('rejects malformed or unrelated window payloads', () {
    expect(ExternalPlayerSession.tryParseLaunchArguments([]), isNull);
    expect(
      ExternalPlayerSession.tryParseLaunchArguments(
        ['multi_window', '7', '{"windowType":"pip"}'],
      ),
      isNull,
    );
    expect(
      ExternalPlayerSession.tryParseLaunchArguments(
        [
          'multi_window',
          '7',
          '{"windowType":"externalPlayerConsole","processId":123}'
        ],
      ),
      isNull,
    );
  });
}
