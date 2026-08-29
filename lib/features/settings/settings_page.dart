import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/player/player_service.dart';
import '../../shared/providers/providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _buildSection(context, '音源'),
          _buildItem(
            context, Icons.source, '音源管理',
            '导入/删除洛雪音源', '/settings/sources',
          ),

          _buildSection(context, '播放'),
          ListTile(
            leading: const Icon(Icons.high_quality),
            title: const Text('默认音质'),
            subtitle: Text(_qualityLabel(settings.defaultQuality)),
            trailing: DropdownButton<String>(
              value: settings.defaultQuality,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: '128k', child: Text('标准 128k')),
                DropdownMenuItem(value: '320k', child: Text('高品 320k')),
                DropdownMenuItem(value: 'flac', child: Text('无损 FLAC')),
              ],
              onChanged: (v) => settingsNotifier.setDefaultQuality(v ?? '128k'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('定时关闭'),
            subtitle: const Text('设置自动停止播放'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSleepTimerDialog(context, ref),
          ),

          _buildSection(context, '外观'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('深色模式'),
            subtitle: const Text('手动切换深色主题'),
            value: settings.darkMode,
            onChanged: (v) => settingsNotifier.setDarkMode(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lyrics),
            title: const Text('桌面歌词'),
            subtitle: const Text('在桌面显示悬浮歌词（Windows）'),
            value: settings.desktopLyrics,
            onChanged: (v) => settingsNotifier.setDesktopLyrics(v),
          ),
          ListTile(
            leading: const Icon(Icons.color_lens),
            title: const Text('主题颜色'),
            subtitle: const Text('选择应用主色调'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showColorPicker(context, ref),
          ),

          _buildSection(context, '高级'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('缓存上限'),
            subtitle: Text('${settings.cacheLimitMB} MB'),
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: settings.cacheLimitMB.toDouble(),
                min: 100,
                max: 2000,
                divisions: 19,
                label: '${settings.cacheLimitMB} MB',
                onChanged: (v) => settingsNotifier.setCacheLimit(v.round()),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.update),
            title: const Text('自动检查音源更新'),
            subtitle: const Text('启动时自动检查'),
            value: settings.autoUpdateSources,
            onChanged: (v) => settingsNotifier.setAutoUpdateSources(v),
          ),

          _buildSection(context, '关于'),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于应用'),
            subtitle: const Text('v1.0.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源协议'),
            subtitle: const Text('查看依赖许可'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLicensePage(context),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('反馈问题'),
            subtitle: const Text('提交 Bug 或建议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openFeedback,
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              '用 ❤️ 和 Flutter 制作',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _qualityLabel(String q) => switch (q) {
        '128k' => '标准 128k',
        '320k' => '高品 320k',
        'flac' => '无损 FLAC',
        _ => q,
      };

  Widget _buildSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, IconData icon, String title, String subtitle, String? route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: route != null ? const Icon(Icons.chevron_right) : null,
      onTap: route != null ? () => context.push(route) : null,
    );
  }

  void _showSleepTimerDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('定时关闭'),
        children: [
          _timerOption(context, ref, '15 分钟', const Duration(minutes: 15)),
          _timerOption(context, ref, '30 分钟', const Duration(minutes: 30)),
          _timerOption(context, ref, '60 分钟', const Duration(minutes: 60)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cancel),
            title: const Text('取消定时'),
            onTap: () {
              ref.read(playerServiceProvider).cancelSleepTimer();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _timerOption(BuildContext context, WidgetRef ref, String label, Duration d) {
    return ListTile(
      leading: const Icon(Icons.timer),
      title: Text(label),
      onTap: () {
        ref.read(playerServiceProvider).startSleepTimer(d);
        Navigator.pop(context);
      },
    );
  }

  void _showColorPicker(BuildContext context, WidgetRef ref) {
    final colors = [
      0xFF6750A4, 0xFF1976D2, 0xFF388E3C, 0xFFD32F2F, 0xFFF57C00,
      0xFF7B1FA2, 0xFF0097A7, 0xFFC2185B, 0xFF5D4037, 0xFF455A64,
    ];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择主题颜色'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((c) => GestureDetector(
                onTap: () {
                  ref.read(appSettingsProvider.notifier).setThemeColor(c);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  ),
                )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '音乐播放器',
      applicationVersion: 'v1.0.0',
      applicationLegalese: '© 2026 yangpeidong123',
      children: const [
        SizedBox(height: 12),
        Text('一款支持导入洛雪音源的跨平台音乐播放器。'),
      ],
    );
  }

  void _showLicensePage(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: '音乐播放器',
      applicationVersion: 'v1.0.0',
    );
  }

  Future<void> _openFeedback() async {
    final uri = Uri.parse('https://github.com/yangpeidong123/music_player/issues');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
