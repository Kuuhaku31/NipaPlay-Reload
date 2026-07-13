
// external_player_console_app.dart

import 'package:flutter/material.dart';
import 'package:nipaplay/models/external_player_session.dart';


/// 启动控制台 Flutter 应用
/// 当 main() 判断当前窗口属于外部播放器控制台时, 会调用这个函数
Future<void> runExternalPlayerConsoleApp(ExternalPlayerSession session) async {
  // 把 ExternalPlayerConsoleApp 设置为当前子窗口 Flutter Engine 的根组件
  runApp(ExternalPlayerConsoleApp(session: session));
}


/// 将外部播放器会话数据渲染成一个独立的 Linux 控制台窗口,
/// 仅在 Linux 平台上运行
class ExternalPlayerConsoleApp extends StatelessWidget {

  // 构造函数, 接收一个 ExternalPlayerSession 对象作为参数
  const ExternalPlayerConsoleApp({super.key, required this.session});

  // 外部播放器会话对象
  final ExternalPlayerSession session;

  // 构建 Flutter 控件树, 显示外部播放器会话信息
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('外部播放器控制台')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _row('番剧', session.animeTitle ?? '未知番剧'),
            _row('剧集', session.episodeTitle ?? '未知剧集'),
            _row('episodeId', session.episodeId?.toString() ?? '-'),
            _row('播放器 PID', session.processId.toString()),
          ],
        ),
      ),
    );
  }

  // 构建一个显示标签和值的行控件, 用于显示外部播放器会话信息
  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120, child: Text(label)),
      Expanded(child: SelectableText(value)),
    ]),
  );

}
