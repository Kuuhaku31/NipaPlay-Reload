
// external_player_console_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/external_player_session.dart';


/// 管理外部播放器弹幕控制台
class ExternalPlayerConsoleService extends ChangeNotifier {

  ExternalPlayerConsoleService({
    Duration monitorInterval = const Duration(seconds: 1), // 每秒轮询一次播放器状态
  }) :
  _monitorInterval  = monitorInterval;

  // 单例实例
  static final ExternalPlayerConsoleService instance = ExternalPlayerConsoleService();


  // 状态
  ExternalPlayerSession?          _session;  // 当前外部播放器会话
  ExternalPlayerPlaybackProgress? _progress; // 当前播放进度

  final Duration _monitorInterval;  // 轮询间隔
  Timer? _monitorTimer;             // 轮询播放器状态的定时器
  bool  _isClosing         = false; // 是否正在关闭播放器
  bool  _isCheckingProcess = false; // 是否正在检查播放器进程状态

  // --- Getters ---
  ExternalPlayerSession?          get session          => _session;         // 当前外部播放器会话
  ExternalPlayerPlaybackProgress? get progress         => _progress;        // 当前播放进度
  bool                            get hasActiveSession => _session != null; // 是否有活动的外部播放器会话
  bool                            get isClosing        => _isClosing;       // 是否正在关闭播放器


  /// 把一个新的外部播放器会话设置为当前唯一会话, 并启动播放器状态与进度监控,
  /// 若已有会话, 先关闭旧播放器, 再用新会话替换控制台内容
  Future<void> showSession(ExternalPlayerSession session) async {

    // 如果已有会话, 且进程 ID 不同, 先关闭旧播放器
    final previous = _session;
    if (previous != null && previous.processId != session.processId) {
      _terminate(previous.processId);
    }

    // 重置状态, 刷新 UI
    _monitorTimer?.cancel();
    _session   = session;
    _progress  = null;
    _isClosing = false;
    notifyListeners();

    // 启动轮询器
    _monitorTimer = Timer.periodic(_monitorInterval, (_) => unawaited(_refreshProcessState()));
  }

  /// 关闭当前播放器并收起主程序内的控制台面板。
  Future<void> closePlayerAndConsole() async {

    // 如果正在关闭, 或者没有会话, 则直接返回
    final current = _session;
    if (_isClosing || current == null) return;

    // 重置状态, 刷新 UI
    _isClosing = true;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _session      = null;
    _progress     = null;
    notifyListeners();

    // 终止播放器进程
    try { _terminate(current.processId); }
    finally { _isClosing = false; }
  }

  /// 检查播放器是否仍在运行,
  /// 播放器自行退出后自动收起控制台
  Future<void> _refreshProcessState() async {

    // 如果没有会话, 或者正在关闭播放器, 或者正在检查进程状态, 则直接返回
    final current = _session;
    if (current == null || _isClosing || _isCheckingProcess) return;
    _isCheckingProcess = true; // 标记正在检查进程状态, 避免重复调用

    // 检查播放器进程是否仍在运行, 并更新播放进度
    try {

      // 检查播放器进程是否仍在运行
      final running = await _isLinuxProcessRunning(current.processId);
      if (!identical(_session, current)) return; // 如果会话已被替换, 则直接返回

      // 如果播放器仍在运行, 则尝试读取播放进度, 并更新状态
      if (running) {

        // 如果会话已被替换, 或者读取播放进度失败, 则直接返回
        final nextProgress = await _readMpvProgress(current);
        if (!identical(_session, current) || nextProgress == null) return;

        // 如果播放进度没有变化, 则不刷新 UI
        final previous = _progress;
        if (previous?.position == nextProgress.position && previous?.duration == nextProgress.duration) return;

        // 更新播放进度, 刷新 UI
        _progress = nextProgress;
        notifyListeners();
      }

      // 播放器已退出, 则收起控制台
      else {
        _monitorTimer?.cancel();
        _monitorTimer = null;
        _session      = null;
        _progress     = null;
        notifyListeners();
      }

    }
    catch (e) { debugPrint('[ExtPlayerConsole] 刷新播放器状态失败: $e'); }
    finally   { _isCheckingProcess = false; }
  }

  /// 终止播放器进程
  void _terminate(int processId) {
    try {
      final killed = Process.killPid(processId, ProcessSignal.sigterm);
      if (!killed) debugPrint('[ExtPlayerConsole] 播放器进程终止失败: pid=$processId');
    }
    catch (e) { debugPrint('[ExtPlayerConsole] 关闭播放器失败: $e'); }
  }

  /// 检查 Linux 系统下的进程是否仍在运行
  static Future<bool> _isLinuxProcessRunning(int processId) async {
    if (processId <= 0) return false;
    final stat = File('/proc/$processId/stat');
    try {
      final value = await stat.readAsString();
      final closingParen = value.lastIndexOf(')');
      if (closingParen < 0 || closingParen + 2 >= value.length) return true;
      return value.substring(closingParen + 2, closingParen + 3) != 'Z';
    } on FileSystemException {
      return false;
    }
  }

  /// 通过 mpv JSON IPC 查询当前播放位置和媒体总时长。
  static Future<ExternalPlayerPlaybackProgress?>
  _readMpvProgress(ExternalPlayerSession session) async {

    final ipcPath = session.ipcPath;
    if (ipcPath == null || ipcPath.isEmpty) return null;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(ipcPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.write('${jsonEncode({
        'command': ['get_property', 'time-pos'],
        'request_id': 1,
      })}\n');
      socket.write('${jsonEncode({
        'command': ['get_property', 'duration'],
        'request_id': 2,
      })}\n');
      await socket.flush();

      double? positionSeconds;
      double? durationSeconds;
      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800));
      await for (final line in lines) {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic> || value['error'] != 'success') {
          continue;
        }
        final data = value['data'];
        if (data is! num) continue;
        if (value['request_id'] == 1) positionSeconds = data.toDouble();
        if (value['request_id'] == 2) durationSeconds = data.toDouble();
        if (positionSeconds != null && durationSeconds != null) break;
      }

      if (positionSeconds == null || durationSeconds == null) return null;
      return ExternalPlayerPlaybackProgress(
        position: Duration(milliseconds: (positionSeconds * 1000).round()),
        duration: Duration(milliseconds: (durationSeconds * 1000).round()),
      );
    } catch (_) {
      // mpv 启动初期 Socket 可能尚未建立，等待下一次轮询即可。
      return null;
    } finally {
      socket?.destroy();
    }
  }


  /// 释放资源
  @override
  void dispose() {
    _monitorTimer?.cancel();
    super.dispose();
  }
}
