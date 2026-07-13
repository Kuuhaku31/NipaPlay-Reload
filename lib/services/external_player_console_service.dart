
// external_player_console_service.dart

import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/models/external_player_session.dart';


/// 负责管理 Linux 平台下的外部播放器会话及其对应的控制台窗口
typedef ExternalPlayerWindowIdsReader = Future<Set<int>?> Function();

/// 用于检查指定进程 ID 是否仍在运行的函数类型
typedef ExternalPlayerProcessProbe = Future<bool> Function(int processId);

/// 用于关闭指定窗口的函数类型
typedef ExternalPlayerWindowCloser = Future<void> Function(int windowId);


/// 可独立测试的 session -> windowId 生命周期协调器。
///
/// 手动关闭控制台只会停止跟踪，不会结束播放器；播放器退出时则关闭对应控制台。
class ExternalPlayerSessionLifecycle {
  ExternalPlayerSessionLifecycle({
    required ExternalPlayerWindowIdsReader readWindowIds,
    required ExternalPlayerProcessProbe isProcessRunning,
    required ExternalPlayerWindowCloser closeWindow,
  })  : _readWindowIds = readWindowIds,
        _isProcessRunning = isProcessRunning,
        _closeWindow = closeWindow;

  final ExternalPlayerWindowIdsReader _readWindowIds;
  final ExternalPlayerProcessProbe _isProcessRunning;
  final ExternalPlayerWindowCloser _closeWindow;
  final Map<String, ({ExternalPlayerSession session, int windowId})>
      _activeSessions = {};
  bool _polling = false;

  int get activeSessionCount => _activeSessions.length;

  int? windowIdForSession(String sessionId) =>
      _activeSessions[sessionId]?.windowId;

  void track(ExternalPlayerSession session, int windowId) {
    _activeSessions[session.id] = (session: session, windowId: windowId);
  }

  void untrack(String sessionId) {
    _activeSessions.remove(sessionId);
  }

  Future<void> poll() async {
    if (_polling || _activeSessions.isEmpty) return;
    _polling = true;
    try {
      Set<int>? windowIds;
      try {
        windowIds = await _readWindowIds();
      } catch (_) {
        // 窗口枚举失败不应妨碍播放器退出检测。
      }

      for (final entry in _activeSessions.entries.toList()) {
        final tracked = entry.value;
        if (windowIds != null && !windowIds.contains(tracked.windowId)) {
          // 用户手动关窗：解除映射，但不干预外部播放器。
          _activeSessions.remove(entry.key);
          continue;
        }

        bool running = true;
        try {
          running = await _isProcessRunning(tracked.session.processId);
        } catch (_) {
          // 暂时无法探测时保留会话，避免误关窗口。
          continue;
        }
        if (running) continue;

        // 先解除映射，再发起关闭，避免插件 close 卡住时阻塞后续轮询。
        _activeSessions.remove(entry.key);
        try {
          await _closeWindow(tracked.windowId);
        } catch (_) {}
      }
    } finally {
      _polling = false;
    }
  }
}


/// 管理 Linux 外部播放器会话及其一一对应的控制台窗口。
class ExternalPlayerConsoleService {
  ExternalPlayerConsoleService._();

  static const Duration _pollInterval = Duration(seconds: 1);
  static const Duration _windowCloseTimeout = Duration(seconds: 2);

  static final ExternalPlayerSessionLifecycle _lifecycle =
      ExternalPlayerSessionLifecycle(
    readWindowIds: () async =>
        (await DesktopMultiWindow.getAllSubWindowIds()).toSet(),
    isProcessRunning: _isLinuxProcessRunning,
    closeWindow: (int windowId) => WindowController.fromWindowId(windowId)
        .close()
        .timeout(_windowCloseTimeout),
  );

  static Timer? _pollTimer;

  static int get activeSessionCount => _lifecycle.activeSessionCount;

  static int? windowIdForSession(String sessionId) =>
      _lifecycle.windowIdForSession(sessionId);

  /// 关闭外部播放器进程以及与其对应的弹幕控制台窗口。
  static Future<void> closePlayerAndWindow(
    ExternalPlayerSession session,
    int windowId,
  ) async {

    // 先终止播放器, 即使播放器已经退出或终止失败也继续关闭控制台
    try {
      final killed = Process.killPid(session.processId, ProcessSignal.sigterm);
      if (!killed) {
        debugPrint('[ExtPlayerConsole] 播放器进程不存在: pid=${session.processId}');
      }
    } catch (e) {
      debugPrint('[ExtPlayerConsole] 关闭播放器失败: $e');
    }

    try {
      await WindowController.fromWindowId(windowId)
          .close()
          .timeout(_windowCloseTimeout);
    } catch (e) {
      debugPrint('[ExtPlayerConsole] 关闭当前窗口失败: $e');
    }
  }

  /// 主动关闭指定会话的控制台。外部播放器进程不受影响。
  static Future<bool> close(String sessionId) async {
    final windowId = _lifecycle.windowIdForSession(sessionId);
    if (windowId == null) return false;

    _lifecycle.untrack(sessionId);
    try {
      await WindowController.fromWindowId(windowId)
          .close()
          .timeout(_windowCloseTimeout);
      return true;
    } catch (e) {
      debugPrint('[ExtPlayerConsole] 关闭窗口失败: $e');
      return false;
    } finally {
      if (_lifecycle.activeSessionCount == 0) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    }
  }

  static Future<bool> open(ExternalPlayerSession session) async {

    // 保证只在 Linux 平台上运行, 并且不是 Web 平台
    if (kIsWeb || !Platform.isLinux) return false;

    WindowController? window;
    try {
      window = await DesktopMultiWindow.createWindow(
        session.toWindowArgumentsJson(),
      );

      // 设置窗口的大小、标题和位置, 并显示窗口
      await window.setFrame(const Rect.fromLTWH(0, 0, 520, 360));
      await window.setTitle('NipaPlay 外部播放器控制台');
      await window.center();
      await window.show();

      _lifecycle.track(session, window.windowId);
      _ensurePolling();
      unawaited(_pollOnce());
      return true;

    } catch (e) {
      debugPrint('[ExtPlayerConsole] 创建窗口失败: $e');
      if (window != null) {
        unawaited(
            window.close().timeout(_windowCloseTimeout).catchError((_) {}));
      }
      return false;
    }
  }

  static void _ensurePolling() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      unawaited(_pollOnce());
    });
  }

  static Future<void> _pollOnce() async {
    await _lifecycle.poll();
    if (_lifecycle.activeSessionCount == 0) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  static Future<bool> _isLinuxProcessRunning(int processId) async {
    if (processId <= 0) return false;
    final stat = File('/proc/$processId/stat');
    try {
      final value = await stat.readAsString();
      final closingParen = value.lastIndexOf(')');
      if (closingParen < 0 || closingParen + 2 >= value.length) return true;
      // /proc/<pid>/stat 的右括号后第一个字段是进程状态；Z 表示僵尸进程。
      return value.substring(closingParen + 2, closingParen + 3) != 'Z';
    } on FileSystemException {
      return false;
    }
  }
}
