import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:kuroko_flutter/kuroko_flutter.dart';

import './abstract_player.dart';
import './player_data_models.dart';
import './player_enums.dart';

class KurokoPlayerAdapter implements AbstractPlayer {
  KurokoPlayerAdapter() {
    if (_isSupported) {
      _eventSubscription = _player.events.listen(
        _handleEvent,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('KurokoPlayerAdapter event error: $error');
        },
      );
    }
  }

  final KurokoPlayer _player = KurokoPlayer();
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: const <String>[],
    PlayerMediaType.audio: const <String>[],
    PlayerMediaType.subtitle: const <String>[],
    PlayerMediaType.unknown: const <String>[],
  };
  final Map<String, String> _properties = <String, String>{};

  StreamSubscription<KurokoPlayerEvent>? _eventSubscription;
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  String _media = '';
  double _volume = 100.0;
  double _playbackRate = 1.0;
  int _lastPositionMs = 0;
  DateTime _lastPositionUpdate = DateTime.now();
  bool _disposed = false;

  // Real Kuroko track descriptors, kept so the UI's index-based
  // activeAudioTracks/activeSubtitleTracks can be mapped back to native ids.
  List<KurokoTrackInfo> _audioTrackInfos = const <KurokoTrackInfo>[];
  List<KurokoTrackInfo> _subtitleTrackInfos = const <KurokoTrackInfo>[];
  List<int> _activeAudioTracks = const <int>[];
  List<int> _activeSubtitleTracks = const <int>[];

  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  bool get prefersPlatformVideoSurface => _isSupported;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value.clamp(0.0, 100.0).toDouble();
  }

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    setPlaybackRate(value);
  }

  @override
  PlayerPlaybackState get state => _state;

  @override
  set state(PlayerPlaybackState value) {
    switch (value) {
      case PlayerPlaybackState.playing:
        unawaited(playDirectly());
        break;
      case PlayerPlaybackState.paused:
        unawaited(pauseDirectly());
        break;
      case PlayerPlaybackState.stopped:
        _state = PlayerPlaybackState.stopped;
        _lastPositionMs = 0;
        unawaited(_player.stop());
        break;
    }
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _media;

  @override
  set media(String value) {
    setMedia(value, PlayerMediaType.video);
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> value) {
    _activeSubtitleTracks = List<int>.from(value);
    if (!_isSupported) {
      return;
    }
    // Empty selection means "no subtitle".
    if (value.isEmpty) {
      unawaited(_player.selectSubtitleTrack(null));
      return;
    }
    final index = value.first;
    if (index >= 0 && index < _subtitleTrackInfos.length) {
      unawaited(_player.selectSubtitleTrack(_subtitleTrackInfos[index].id));
    }
  }

  @override
  List<int> get activeAudioTracks => _activeAudioTracks;

  @override
  set activeAudioTracks(List<int> value) {
    _activeAudioTracks = List<int>.from(value);
    if (!_isSupported) {
      return;
    }
    // Empty selection falls back to the first real audio track.
    if (value.isEmpty) {
      if (_audioTrackInfos.isNotEmpty) {
        unawaited(_player.selectAudioTrack(_audioTrackInfos.first.id));
      }
      return;
    }
    final index = value.first;
    if (index >= 0 && index < _audioTrackInfos.length) {
      unawaited(_player.selectAudioTrack(_audioTrackInfos[index].id));
    }
  }

  @override
  int get position {
    if (_state != PlayerPlaybackState.playing) {
      return _lastPositionMs;
    }
    final elapsedMs =
        DateTime.now().difference(_lastPositionUpdate).inMilliseconds;
    return _lastPositionMs + (elapsedMs * _playbackRate).round();
  }

  @override
  int get bufferedPosition => position;

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {}

  @override
  bool get supportsExternalSubtitles => false;

  @override
  Future<int?> updateTexture() async => null;

  @override
  void setMedia(String path, PlayerMediaType type) {
    if (type == PlayerMediaType.video || type == PlayerMediaType.unknown) {
      _media = path;
      _lastPositionMs = 0;
      _lastPositionUpdate = DateTime.now();
      _mediaInfo = PlayerMediaInfo(duration: 0);
    }
  }

  @override
  Future<void> prepare() async {
    _ensureSupported();
    if (_media.isEmpty) {
      return;
    }
    await _player.ensureCreated();
    await _player.open(_media);
    _state = PlayerPlaybackState.paused;
  }

  @override
  void seek({required int position}) {
    final clamped = position < 0 ? 0 : position;
    _lastPositionMs = clamped;
    _lastPositionUpdate = DateTime.now();
    unawaited(_player.seek(Duration(milliseconds: clamped)));
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    unawaited(_player.dispose());
    _textureIdNotifier.dispose();
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async => null;

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    _decoders[type] = List<String>.from(decoders);
  }

  @override
  List<String> getDecoders(PlayerMediaType type) =>
      List<String>.from(_decoders[type] ?? const <String>[]);

  @override
  String? getProperty(String key) => _properties[key];

  @override
  void setProperty(String key, String value) {
    _properties[key] = value;
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {}

  @override
  Future<void> playDirectly() async {
    _ensureSupported();
    await _player.ensureCreated();
    await _player.play();
    _state = PlayerPlaybackState.playing;
    _lastPositionUpdate = DateTime.now();
  }

  @override
  Future<void> pauseDirectly() async {
    _ensureSupported();
    await _player.ensureCreated();
    _lastPositionMs = position;
    await _player.pause();
    _state = PlayerPlaybackState.paused;
    _lastPositionUpdate = DateTime.now();
  }

  @override
  void setPlaybackRate(double rate) {
    _playbackRate = rate <= 0 ? 1.0 : rate;
    if (_isSupported) {
      unawaited(_player.setPlaybackRate(_playbackRate));
    }
  }

  Widget buildPlatformVideoSurface({
    String? debugLabel,
    ValueChanged<int?>? onPlatformViewIdChanged,
    ValueChanged<Rect?>? onFrameRectChanged,
  }) {
    _ensureSupported();
    return KurokoWindowOverlayVideoView(
      player: _player,
      debugLabel: debugLabel,
      onPlatformViewIdChanged: onPlatformViewIdChanged,
      onFrameRectChanged: onFrameRectChanged,
    );
  }

  // ---- Kuroko native danmaku passthrough ----
  //
  // Kuroko composites danmaku into the video frame natively, so when the Kuroko
  // kernel is active NipaPlay feeds its danmaku list + settings here instead of
  // driving its own Flutter danmaku overlay. The list uses NipaPlay's standard
  // danmaku maps ({time, content, type, color, ...}); Kuroko's JSON parser
  // accepts that shape directly, so it is forwarded as-is.

  bool get supportsNativeDanmaku => _isSupported;

  Future<void> loadDanmakuList(List<Map<String, dynamic>> danmakuList) async {
    if (!_isSupported) {
      return;
    }
    await _player.loadDanmakuJson(jsonEncode(danmakuList));
  }

  Future<void> clearDanmaku() async {
    if (!_isSupported) {
      return;
    }
    await _player.clearDanmaku();
  }

  Future<void> setDanmakuEnabled(bool enabled) async {
    if (!_isSupported) {
      return;
    }
    await _player.setDanmakuEnabled(enabled);
  }

  Future<void> setDanmakuGlobalOffset(Duration offset) async {
    if (!_isSupported) {
      return;
    }
    await _player.setDanmakuGlobalOffset(offset);
  }

  /// Bridges NipaPlay's danmaku display settings onto Kuroko's DFM+ config.
  /// All arguments are optional; only the supplied ones are pushed down.
  Future<void> setDanmakuConfig({
    bool? enabled,
    double? fontSize,
    double? opacity,
    double? displayArea,
    double? scrollDurationSeconds,
    double? scrollSpeedFactor,
    double? trackGapRatio,
    double? outlineWidth,
    int? shadowStyle,
    String? customFontFamily,
    String? customFontFilePath,
    bool? mergeDuplicates,
    bool? allowStacking,
    int? maxQuantity,
    int? maxLinesPerMode,
    bool? blockTop,
    bool? blockBottom,
    bool? blockScroll,
    List<String>? blockWords,
  }) async {
    if (!_isSupported) {
      return;
    }
    await _player.setDanmakuConfig(
      enabled: enabled,
      fontSize: fontSize,
      opacity: opacity,
      displayArea: displayArea,
      scrollDurationSeconds: scrollDurationSeconds,
      scrollSpeedFactor: scrollSpeedFactor,
      trackGapRatio: trackGapRatio,
      outlineWidth: outlineWidth,
      shadowStyle: shadowStyle,
      customFontFamily: customFontFamily,
      customFontFilePath: customFontFilePath,
      mergeDuplicates: mergeDuplicates,
      allowStacking: allowStacking,
      maxQuantity: maxQuantity,
      maxLinesPerMode: maxLinesPerMode,
      blockTop: blockTop,
      blockBottom: blockBottom,
      blockScroll: blockScroll,
      blockWords: blockWords,
    );
  }

  Map<String, dynamic> getDetailedMediaInfo() {
    return <String, dynamic>{
      'kernel': 'Kuroko',
      'state': _state.name,
      'position': position,
      'duration': _mediaInfo.duration,
      'videoWidth': _mediaInfo.video?.isNotEmpty == true
          ? _mediaInfo.video!.first.codec.width
          : null,
      'videoHeight': _mediaInfo.video?.isNotEmpty == true
          ? _mediaInfo.video!.first.codec.height
          : null,
    };
  }

  Future<Map<String, dynamic>> getDetailedMediaInfoAsync() async =>
      getDetailedMediaInfo();

  void _handleEvent(KurokoPlayerEvent event) {
    switch (event.state) {
      case KurokoPlaybackState.playing:
        _state = PlayerPlaybackState.playing;
        break;
      case KurokoPlaybackState.paused:
      case KurokoPlaybackState.ready:
      case KurokoPlaybackState.opening:
        _state = PlayerPlaybackState.paused;
        break;
      case KurokoPlaybackState.stopped:
      case KurokoPlaybackState.closed:
      case KurokoPlaybackState.idle:
      case KurokoPlaybackState.error:
        _state = PlayerPlaybackState.stopped;
        break;
    }

    if (event.position >= Duration.zero) {
      _lastPositionMs = event.position.inMilliseconds;
      _lastPositionUpdate = DateTime.now();
    }

    var updatedInfo = _mediaInfo;
    if (event.duration > Duration.zero) {
      updatedInfo =
          updatedInfo.copyWith(duration: event.duration.inMilliseconds);
    }
    if (event.video.width > 0 && event.video.height > 0) {
      updatedInfo = updatedInfo.copyWith(
        video: <PlayerVideoStreamInfo>[
          PlayerVideoStreamInfo(
            codec: PlayerVideoCodecParams(
              width: event.video.width,
              height: event.video.height,
              name: 'Kuroko Video',
            ),
            codecName: 'unknown',
          ),
        ],
      );
    }
    // Kuroko emits the full descriptor list (with native ids, titles and the
    // selected flag) on TracksChanged/TrackSelectionChanged. Use it to build
    // mediaInfo so the UI's index-based track selection maps to real ids.
    if (event.trackList.isNotEmpty) {
      final audioInfos = event.trackList
          .where((t) => t.kind == KurokoTrackKind.audio)
          .toList(growable: false);
      final subtitleInfos = event.trackList
          .where((t) => t.kind == KurokoTrackKind.subtitle)
          .toList(growable: false);
      _audioTrackInfos = audioInfos;
      _subtitleTrackInfos = subtitleInfos;
      updatedInfo = updatedInfo.copyWith(
        audio: <PlayerAudioStreamInfo>[
          for (var i = 0; i < audioInfos.length; i++)
            PlayerAudioStreamInfo(
              codec: PlayerAudioCodecParams(
                name: audioInfos[i].codec ?? 'unknown',
              ),
              title: audioInfos[i].title ?? 'Audio ${i + 1}',
              language: audioInfos[i].language,
              metadata: <String, String>{'id': '${audioInfos[i].id}'},
              rawRepresentation: 'Kuroko Audio ${i + 1}',
            ),
        ],
        subtitle: <PlayerSubtitleStreamInfo>[
          for (var i = 0; i < subtitleInfos.length; i++)
            PlayerSubtitleStreamInfo(
              title: subtitleInfos[i].title ?? 'Subtitle ${i + 1}',
              language: subtitleInfos[i].language,
              metadata: <String, String>{'id': '${subtitleInfos[i].id}'},
              rawRepresentation: 'Kuroko Subtitle ${i + 1}',
            ),
        ],
      );
      _activeAudioTracks = <int>[
        for (var i = 0; i < audioInfos.length; i++)
          if (audioInfos[i].selected) i,
      ];
      _activeSubtitleTracks = <int>[
        for (var i = 0; i < subtitleInfos.length; i++)
          if (subtitleInfos[i].selected) i,
      ];
    }
    _mediaInfo = updatedInfo;
  }

  void _ensureSupported() {
    if (!_isSupported) {
      throw UnsupportedError('Kuroko is currently only wired on macOS.');
    }
  }
}
