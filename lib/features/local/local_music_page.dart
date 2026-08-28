import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../../shared/widgets/mini_player_bar.dart';

/// 本地音乐扫描器
class LocalMusicScanner {
  final _supportedExtensions = {'.mp3', '.flac', '.wav', '.m4a', '.ogg', '.aac'};

  Future<List<LocalMusicFile>> scan(String rootPath,
      {void Function(int current, int total)? onProgress}) async {
    final results = <LocalMusicFile>[];
    final dir = Directory(rootPath);
    if (!await dir.exists()) return results;

    final allFiles = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        if (_supportedExtensions.any((e) => ext.endsWith(e))) {
          allFiles.add(entity);
        }
      }
    }

    for (var i = 0; i < allFiles.length; i++) {
      final file = allFiles[i] as File;
      onProgress?.call(i + 1, allFiles.length);

      final name = file.path.split(Platform.pathSeparator).last;
      // 简单解析文件名: "歌手 - 歌名.mp3" 格式
      String singer = '';
      String songName = name;
      if (name.contains(' - ')) {
        final parts = name.replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$'), '').split(' - ');
        if (parts.length >= 2) {
          singer = parts[0];
          songName = parts.sublist(1).join(' - ');
        }
      } else {
        songName = name.replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$'), '');
      }

      final stat = await file.stat();
      results.add(LocalMusicFile(
        path: file.path,
        name: songName,
        singer: singer,
        size: stat.size,
        modified: stat.modified,
      ));
    }

    return results;
  }
}

class LocalMusicFile {
  final String path;
  final String name;
  final String singer;
  final int size;
  final DateTime modified;

  LocalMusicFile({
    required this.path,
    required this.name,
    this.singer = '',
    required this.size,
    required this.modified,
  });

  String get sizeString {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}

class LocalMusicPage extends ConsumerStatefulWidget {
  const LocalMusicPage({super.key});

  @override
  ConsumerState<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends ConsumerState<LocalMusicPage> {
  List<LocalMusicFile> _files = [];
  bool _scanning = false;
  double _progress = 0;
  String _progressText = '';

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _progress = 0;
      _progressText = '正在请求权限...';
    });

    // Android 需要存储权限
    if (await Permission.storage.request().isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要存储权限才能扫描本地音乐')),
        );
      }
      setState(() => _scanning = false);
      return;
    }

    setState(() => _progressText = '正在扫描...');

    String? scanPath;
    if (Platform.isAndroid) {
      // Android: 扫描 /storage/emulated/0/Music
      scanPath = '/storage/emulated/0/Music';
    } else if (Platform.isWindows) {
      // Windows: 扫描用户音乐目录
      final home = Platform.environment['USERPROFILE'] ?? '';
      scanPath = '$home\\Music';
    }

    if (scanPath == null) {
      final dir = await getApplicationDocumentsDirectory();
      scanPath = dir.path;
    }

    final scanner = LocalMusicScanner();
    final results = await scanner.scan(scanPath, onProgress: (current, total) {
      setState(() {
        _progress = total > 0 ? current / total : 0;
        _progressText = '$current / $total';
      });
    });

    setState(() {
      _files = results;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地音乐'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: _scanning
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(value: _progress),
                  const SizedBox(height: 16),
                  Text(_progressText),
                ],
              ),
            )
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.library_music, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('点击右上角扫描本地音乐'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _scan,
                        icon: const Icon(Icons.search),
                        label: const Text('扫描'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return ListTile(
                      leading: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.audiotrack),
                      ),
                      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        file.singer.isNotEmpty
                            ? '${file.singer} · ${file.sizeString}'
                            : file.sizeString,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        // 使用 just_audio 播放本地文件
                        // _player.setFilePath(file.path);
                      },
                    );
                  },
                ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }
}
