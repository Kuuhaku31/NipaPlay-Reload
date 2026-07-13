
// external_player_console_service.dart

import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/models/external_player_session.dart';


/// 提供在 Linux 平台上打开外部播放器控制台窗口的服务类
class ExternalPlayerConsoleService {
  ExternalPlayerConsoleService._(); // 私有构造函数, 防止实例化

  // 尝试打开一个新的外部播放器控制台窗口, 并传入会话数据
  // 如果当前平台不是 Linux 或者创建窗口失败, 返回 false
  static Future<bool> open(ExternalPlayerSession session) async {

    // 保证只在 Linux 平台上运行, 并且不是 Web 平台
    if (kIsWeb || !Platform.isLinux) return false;

    // 使用 desktop_multi_window 插件创建一个新的窗口, 并传入会话数据
    try {
      final window = await DesktopMultiWindow.createWindow(
        session.toWindowArgumentsJson(),
      );

      // 设置窗口的大小、标题和位置, 并显示窗口
      await window.setFrame(const Rect.fromLTWH(0, 0, 520, 360));
      await window.setTitle('NipaPlay 外部播放器控制台');
      await window.center();
      await window.show();
      return true;

    } catch (e) {
      debugPrint('[ExtPlayerConsole] 创建窗口失败: $e');
      return false;
    }
  }

}
