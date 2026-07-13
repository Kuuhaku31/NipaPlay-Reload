
// external_player_console_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/external_player_session.dart';

typedef ExternalPlayerProcessProbe = Future<bool> Function(int processId);
typedef ExternalPlayerProcessTerminator = bool Function(int processId);


/// 管理外部播放器弹幕控制台
class ExternalPlayerConsoleService extends ChangeNotifier {

  ExternalPlayerConsoleService({
    ExternalPlayerProcessProbe? processProbe,
    ExternalPlayerProcessTerminator? terminateProcess,
    Duration monitorInterval = const Duration(seconds: 1),
  }) :
  _processProbe = processProbe ?? _isLinuxProcessRunning,
  _terminateProcess = terminateProcess ?? _terminateLinuxProcess,
  _monitorInterval = monitorInterval;

  // 单例实例
  static final ExternalPlayerConsoleService instance = ExternalPlayerConsoleService();

  // 进程探测器和终止器
  final ExternalPlayerProcessProbe      _processProbe;
  final ExternalPlayerProcessTerminator _terminateProcess;
  final Duration                        _monitorInterval;

  // 当前会话信息
  ExternalPlayerSession? _session;
  Timer?                 _monitorTimer;
  bool                   _isClosing = false;
  bool                   _isCheckingProcess = false;

  // --- Getters ---
  ExternalPlayerSession? get session => _session;
  bool get hasActiveSession => _session != null;
  bool get isClosing => _isClosing;

  /// 显示新会话。若已有会话，先关闭旧播放器，再用新会话替换控制台内容。
  Future<void> showSession(ExternalPlayerSession session) async {
    final previous = _session;
    if (previous != null && previous.processId != session.processId) {
      _terminate(previous.processId);
    }

    _monitorTimer?.cancel();
    _session = session;
    _isClosing = false;
    notifyListeners();
    _monitorTimer = Timer.periodic(_monitorInterval, (_) {
      unawaited(refreshProcessState());
    });
  }

  /// 关闭当前播放器并收起主程序内的控制台面板。
  Future<void> closePlayerAndConsole() async {
    if (_isClosing) return;
    final current = _session;
    if (current == null) return;

    _isClosing = true;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _session = null;
    notifyListeners();

    try {
      _terminate(current.processId);
    } finally {
      _isClosing = false;
    }
  }

  /// 检查播放器是否仍在运行；播放器自行退出后自动收起控制台。
  Future<void> refreshProcessState() async {
    final current = _session;
    if (current == null || _isClosing || _isCheckingProcess) return;

    _isCheckingProcess = true;
    bool running;
    try {
      running = await _processProbe(current.processId);
    } catch (e) {
      debugPrint('[ExtPlayerConsole] 检查播放器进程失败: $e');
      return;
    } finally {
      _isCheckingProcess = false;
    }
    if (running || !identical(_session, current)) return;

    _monitorTimer?.cancel();
    _monitorTimer = null;
    _session = null;
    notifyListeners();
  }

  void _terminate(int processId) {
    try {
      final killed = _terminateProcess(processId);
      if (!killed) {
        debugPrint('[ExtPlayerConsole] 播放器进程不存在: pid=$processId');
      }
    } catch (e) {
      debugPrint('[ExtPlayerConsole] 关闭播放器失败: $e');
    }
  }

  static bool _terminateLinuxProcess(int processId) {
    return Process.killPid(processId, ProcessSignal.sigterm);
  }

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

  @override
  void dispose() {
    _monitorTimer?.cancel();
    super.dispose();
  }
}
