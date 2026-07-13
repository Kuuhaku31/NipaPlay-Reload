
// external_player_session.dart

import 'dart:convert';


/// 用于表示外部播放器会话的模型类,
/// 包含播放器路径, 媒体路径, 进程 ID 以及可选的番剧信息
class ExternalPlayerSession {

  const ExternalPlayerSession({
    required this.id,
    required this.playerPath,
    required this.mediaPath,
    required this.processId,
    this.animeTitle,
    this.episodeTitle,
    this.episodeId,
  });

  static const windowType = 'externalPlayerConsole';

  final String  id;           // 会话 ID
  final String  playerPath;   // 播放器路径
  final String  mediaPath;    // 媒体路径
  final int     processId;    // 播放器进程 ID
  final String? animeTitle;   // 番剧标题
  final String? episodeTitle; // 剧集标题
  final int?    episodeId;    // 剧集 ID

  // 将当前会话对象转换为 JSON 格式的 Map
  Map<String, dynamic> toJson() => {
    'id'          : id,
    'windowType'  : windowType,
    'playerPath'  : playerPath,
    'mediaPath'   : mediaPath,
    'processId'   : processId,
    'animeTitle'  : animeTitle,
    'episodeTitle': episodeTitle,
    'episodeId'   : episodeId,
  };

  // 把外部播放器会话打包成可以传给新窗口的启动参数
  String toWindowArgumentsJson() => jsonEncode(toJson());

  // 尝试从启动参数中解析出外部播放器会话对象, 如果参数不符合预期则返回 null
  static ExternalPlayerSession? tryParseLaunchArguments(List<String> args) {

    if (args.length < 3 || args.first != 'multi_window') return null;

    try {
      // 解析第三个参数为 JSON 对象
      final dynamic decoded = jsonDecode(args[2]);
      if (decoded is! Map<String, dynamic> ||
          decoded['windowType'] != windowType) {
        return null;
      }

      // 检查并提取必要的字段
      final String? id = _asString(decoded['id']);
      final int? processId = _asInt(decoded['processId']);
      if (id == null || processId == null || processId <= 0) return null;

      // 构造并返回 ExternalPlayerSession 对象
      return ExternalPlayerSession(
        id          : id,
        playerPath  : _asString(decoded['playerPath'  ]) ?? '',
        mediaPath   : _asString(decoded['mediaPath'   ]) ?? '',
        processId   : processId,
        animeTitle  : _asString(decoded['animeTitle']),
        episodeTitle: _asString(decoded['episodeTitle']),
        episodeId   : _asInt(decoded['episodeId']),
      );
    }
    catch (_) { return null; } // 解析失败则返回 null
  }

  // 尝试将动态值转换为非空字符串, 如果无法转换则返回 null
  static String? _asString(dynamic value) {
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  // 尝试将动态值转换为整数, 如果无法转换则返回 null
  static int? _asInt(dynamic value) {
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

}
