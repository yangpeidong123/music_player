import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _buildSection(context, '音源', [
            _buildItem(context, Icons.source, '音源管理', '导入/删除洛雪音源', '/settings/sources'),
            _buildItem(context, Icons.update, '检查音源更新', '查看是否有新版本', null),
          ]),
          _buildSection(context, '播放', [
            ListTile(
              leading: const Icon(Icons.high_quality),
              title: const Text('默认音质'),
              subtitle: Text(settings.defaultQuality),
              trailing: DropdownButton<String>(
                value: settings.defaultQuality,
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
            _buildItem(context, Icons.download, '缓存管理', '清理播放缓存', null),
          ]),
          _buildSection(context, '外观', [
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text('深色模式'),
              subtitle: const Text('手动切换深色主题'),
              value: settings.darkMode,
              onChanged: (v) => settingsNotifier.setDarkMode(v),
            ),
            _buildItem(context, Icons.palette, '主题颜色', '选择应用主色调', null),
            _buildItem(context, Icons.font_download, '字体设置', '自定义字体', null),
          ]),
          _buildSection(context, '高级', [
            SwitchListTile(
              secondary: const Icon(Icons.lyrics),
              title: const Text('桌面歌词'),
              subtitle: const Text('在桌面显示悬浮歌词（Windows）'),
              value: settings.desktopLyrics,
              onChanged: (v) => settingsNotifier.setDesktopLyrics(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.update),
              title: const Text('自动检查音源更新'),
              subtitle: const Text('启动时自动检查'),
              value: settings.autoUpdateSources,
              onChanged: (v) => settingsNotifier.setAutoUpdateSources(v),
            ),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('缓存上限'),
              subtitle: Text('${settings.cacheLimitMB} MB'),
              trailing: Slider(
                value: settings.cacheLimitMB.toDouble(),
                min: 100,
                max: 2000,
                divisions: 19,
                onChanged: (v) => settingsNotifier.setCacheLimit(v.round()),
              ),
            ),
          ]),
          _buildSection(context, '关于', [
            _buildItem(context, Icons.info, '关于应用', 'v1.0.0', null),
            _buildItem(context, Icons.code, '开源协议', 'MIT License', null),
            _buildItem(context, Icons.bug_report, '反馈问题', '提交 Bug 或建议', null),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          )),
        ),
        ...items,
        const Divider(),
      ],
    );
  }

  Widget _buildItem(BuildContext context, IconData icon, String title, String subtitle, String? route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: route != null ? () => context.push(route) : null,
    );
  }

  void _showSleepTimerDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('定时关闭'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              ref.read(playerServiceProvider).startSleepTimer(const Duration(minutes: 15));
              Navigator.pop(context);
            },
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('15 分钟')),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(playerServiceProvider).startSleepTimer(const Duration(minutes: 30));
              Navigator.pop(context);
            },
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('30 分钟')),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(playerServiceProvider).startSleepTimer(const Duration(minutes: 60));
              Navigator.pop(context);
            },
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('60 分钟')),
          ),
          SimpleDialogOption(
            onPressed: () {
              ref.read(playerServiceProvider).cancelSleepTimer();
              Navigator.pop(context);
            },
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('取消定时')),
          ),
        ],
      ),
    );
  }
}
