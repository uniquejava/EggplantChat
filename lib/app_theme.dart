import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

abstract final class AppTheme {
  static const railWidth = 64.0;
  static const sidebarWidth = 280.0;
  static const radius = BorderRadius.all(Radius.circular(12));
  static const fontFallback = [
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ];
  static const reading = TextStyle(
    fontSize: 14,
    height: 1.65,
    fontFamilyFallback: fontFallback,
  );

  static DefaultStyles editorStyles(Color foreground) => DefaultStyles(
    paragraph: DefaultTextBlockStyle(
      reading.copyWith(color: foreground),
      const HorizontalSpacing(0, 0),
      const VerticalSpacing(0, 4),
      const VerticalSpacing(0, 0),
      null,
    ),
  );
}
