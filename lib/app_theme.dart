import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

abstract final class AppTheme {
  static const messageAvatarSize = 36.0;
  static const messageRadius = BorderRadius.all(Radius.circular(8));
  static const outgoingBubbleLight = Color(0xFFB2EF9B);
  static const outgoingBubbleDark = Color(0xFF294A30);
  static const pdfIconLight = Color(0xFFB91C1C);
  static const pdfIconDark = Color(0xFFF87171);
  static const composerHeight = 104.0;
  static const windowControlsHeight = 32.0;
  static const railWidth = 64.0;
  static const sidebarWidth = 280.0;
  static const radius = BorderRadius.all(Radius.circular(12));
  static const fontFallback = [
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ];
  static const selection = TextSelectionThemeData(
    selectionColor: Color(0x663B82F6),
  );
  static const reading = TextStyle(
    fontSize: 14,
    height: 1.65,
    fontFamilyFallback: fontFallback,
  );

  static DefaultStyles editorStyles(Color foreground, Color mutedForeground) =>
      DefaultStyles(
        placeHolder: DefaultTextBlockStyle(
          reading.copyWith(
            color: mutedForeground,
            fontWeight: FontWeight.normal,
          ),
          const HorizontalSpacing(0, 0),
          const VerticalSpacing(0, 4),
          const VerticalSpacing(0, 0),
          null,
        ),
        paragraph: DefaultTextBlockStyle(
          reading.copyWith(color: foreground),
          const HorizontalSpacing(0, 0),
          const VerticalSpacing(0, 4),
          const VerticalSpacing(0, 0),
          null,
        ),
      );
}
