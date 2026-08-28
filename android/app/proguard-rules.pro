# Flutter 混淆规则

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# flutter_js (QuickJS)
-keep class com.hieng.** { *; }
-keep class io.github.pustek.** { *; }

# audio_service
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audioservice.MediaButtonReceiver { *; }

# just_audio
-keep class com.ryanheise.just_audio.** { *; }

# ExoPlayer
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# 加密库
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
-keep class javax.crypto.** { *; }

# SQLite
-keep class org.sqlite.** { *; }

# Dart 类（通过 Platform Channel 传递的）
-keep class com.example.music_player.** { *; }

# 通用
-dontwarn javax.annotation.**
-dontwarn org.jetbrains.annotations.**
