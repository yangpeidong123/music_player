import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/player/player_service.dart';

/// 桌面歌词控制器
///
/// 在 Windows 上通过透明置顶窗口显示歌词。
/// Android 上可使用系统悬浮窗（需要 SYSTEM_ALERT_WINDOW 权限）。
class DesktopLyricsController {
  bool _visible = false;
  String _currentLine = '';
  String _nextLine = '';
  double _opacity = 0.85;
  Color _textColor = Colors.white;
  Color _highlightColor = const Color(0xFF6750A4);
  double _fontSize = 24;
  Alignment _alignment = Alignment.bottomCenter;

  bool get isVisible => _visible;
  String get currentLine => _currentLine;
  String get nextLine => _nextLine;

  final _controller = StreamController<DesktopLyricsState>.broadcast();
  Stream<DesktopLyricsState> get stateStream => _controller.stream;

  void show() {
    _visible = true;
    _emit();
  }

  void hide() {
    _visible = false;
    _emit();
  }

  void toggle() {
    _visible = !_visible;
    _emit();
  }

  void updateLyrics({String? current, String? next}) {
    if (current != null) _currentLine = current;
    if (next != null) _nextLine = next;
    _emit();
  }

  void setStyle({
    Color? textColor,
    Color? highlightColor,
    double? fontSize,
    double? opacity,
    Alignment? alignment,
  }) {
    if (textColor != null) _textColor = textColor;
    if (highlightColor != null) _highlightColor = highlightColor;
    if (fontSize != null) _fontSize = fontSize;
    if (opacity != null) _opacity = opacity;
    if (alignment != null) _alignment = alignment;
    _emit();
  }

  void _emit() {
    _controller.add(DesktopLyricsState(
      visible: _visible,
      currentLine: _currentLine,
      nextLine: _nextLine,
      textColor: _textColor,
      highlightColor: _highlightColor,
      fontSize: _fontSize,
      opacity: _opacity,
      alignment: _alignment,
    ));
  }

  void dispose() => _controller.close();
}

/// 桌面歌词状态
class DesktopLyricsState {
  final bool visible;
  final String currentLine;
  final String nextLine;
  final Color textColor;
  final Color highlightColor;
  final double fontSize;
  final double opacity;
  final Alignment alignment;

  const DesktopLyricsState({
    this.visible = false,
    this.currentLine = '',
    this.nextLine = '',
    this.textColor = Colors.white,
    this.highlightColor = const Color(0xFF6750A4),
    this.fontSize = 24,
    this.opacity = 0.85,
    this.alignment = Alignment.bottomCenter,
  });
}

/// 桌面歌词 Provider
final desktopLyricsProvider = Provider<DesktopLyricsController>((ref) {
  final controller = DesktopLyricsController();
  ref.onDispose(() => controller.dispose());
  return controller;
});
