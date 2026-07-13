
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
  });

  final String  playerPath;   // 外部播放器可执行文件路径
  final String  mediaPath;    // 外部播放器播放的视频文件路径
  final int     processId;    // 外部播放器进程 ID
  final String? animeTitle;   // 播放的番剧标题
  final String? episodeTitle; // 播放的番剧集数标题
  final int?    episodeId;    // 播放的番剧集数 ID
}
