import 'package:flutter/material.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/services/external_player_console_service.dart';

/// 主导航中常驻的部播放器弹幕控制台页面。
class ExternalPlayerConsolePage extends StatelessWidget {
  const ExternalPlayerConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ExternalPlayerConsoleService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final session = service.session;
        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: session == null
                    ? const _EmptyConsole()
                    : _ConsoleCard(
                        session: session,
                        progress: service.progress,
                        isPaused: service.isPaused,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyConsole extends StatelessWidget {
  const _EmptyConsole();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.subtitles_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 20),
          Text('尚未启动外部播放器', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '启动外部播放器后，会话信息和控制操作将显示在这里。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ConsoleCard extends StatelessWidget {
  const _ConsoleCard({
    required this.session,
    required this.progress,
    required this.isPaused,
  });

  final ExternalPlayerSession session;
  final ExternalPlayerPlaybackProgress? progress;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.subtitles_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text('外部播放器弹幕控制台', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 20),
            _row('番剧', session.animeTitle ?? '未知番剧'),
            _row('剧集', session.episodeTitle ?? '未知剧集'),
            _row('episodeId', session.episodeId?.toString() ?? '-'),
            _row('播放器 PID', session.processId.toString()),
            _row('媒体路径', session.mediaPath),
            const SizedBox(height: 20),
            _buildProgress(context),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: session.ipcPath == null
                        ? null
                        : ExternalPlayerConsoleService.instance.togglePause,
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(isPaused ? '继续播放' : '暂停'),
                  ),
                  FilledButton.icon(
                    onPressed: ExternalPlayerConsoleService
                        .instance.closePlayerAndConsole,
                    icon: const Icon(Icons.close),
                    label: const Text('关闭播放器'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: SelectableText(value),
        ),
      ],
    ),
  );

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    final supportsProgress = session.ipcPath != null;
    final current = progress;
    final progressText = !supportsProgress
        ? '当前播放器暂不支持进度同步'
        : current == null
            ? '正在获取播放进度…'
            : '${_formatDuration(current.position)} / '
                '${_formatDuration(current.duration)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('播放进度', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: supportsProgress ? current?.fraction : 0,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 8),
        Text(
          progressText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
