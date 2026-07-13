
// external_player_session.dart


/// 外部播放器弹幕控制台所展示的会话信息
class ExternalPlayerSession {

  const ExternalPlayerSession({
    required this.playerPath,
    required this.mediaPath,
    required this.processId,
    this.animeTitle,
    this.episodeTitle,
    this.episodeId,
    this.ipcPath,
  });

  final String  playerPath;   // 外部播放器可执行文件路径
  final String  mediaPath;    // 外部播放器播放的视频文件路径
  final int     processId;    // 外部播放器进程 ID
  final String? animeTitle;   // 播放的番剧标题
  final String? episodeTitle; // 播放的番剧集数标题
  final int?    episodeId;    // 播放的番剧集数 ID
  final String? ipcPath;      // mpv JSON IPC Unix Socket 路径
}


/// 从外部播放器读取到的实时播放进度。
class ExternalPlayerPlaybackProgress {

  const ExternalPlayerPlaybackProgress({
    required this.position,
    required this.duration,
  });

  final Duration position; // 当前播放位置
  final Duration duration; // 媒体总时长

  /// 计算播放进度百分比, 范围为 0.0 ~ 1.0, 如果总时长 <= 0, 则返回 null
  double? get fraction {
    if (duration <= Duration.zero) return null;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }
}
