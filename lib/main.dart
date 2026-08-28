import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'app.dart';
import 'core/storage/database.dart';
import 'shared/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化音频服务（后台播放）
  // final audioHandler = await AudioService.init(
  //   builder: () => AudioHandler(...),
  //   config: const AudioServiceConfig(
  //     androidNotificationChannelId: 'com.example.music_player.channel.audio',
  //     androidNotificationChannelName: 'Music Player',
  //     androidNotificationOngoing: true,
  //     androidStopForegroundOnPause: true,
  //   ),
  // );

  runApp(const ProviderScope(child: MusicPlayerApp()));
}
