import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme.dart';
import 'models.dart';
import 'rich_clipboard.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.senderName,
    required this.onRetry,
    required this.onError,
  });
  final ChatMessage message;
  final String senderName;
  final VoidCallback onRetry;
  final void Function(String) onError;
  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  quill.QuillController? _controller;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.message.delta != null) {
      _controller = quill.QuillController(
        document: quill.Document.fromJson(widget.message.delta!),
        selection: const TextSelection.collapsed(offset: 0),
      )..readOnly = true;
    }
  }

  Future<void> _save() async {
    try {
      final location = await getSaveLocation(
        suggestedName: widget.message.name!.replaceAll(
          RegExp(r'[\\/:*?"<>|\x00-\x1f]'),
          '_',
        ),
      );
      if (location != null) {
        await File(widget.message.path!).copy(location.path);
      }
    } on Object catch (error) {
      widget.onError('保存失败：$error');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final colors = ShadTheme.of(context).colorScheme;
    final bubbleColor = m.outgoing
        ? (ShadTheme.of(context).brightness == Brightness.dark
              ? AppTheme.outgoingBubbleDark
              : AppTheme.outgoingBubbleLight)
        : colors.muted;
    final busy = ['sending', 'receiving'].contains(m.status);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(560.0, constraints.maxWidth * .72);
        return Focus(
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                textDirection: m.outgoing
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShadTooltip(
                    builder: (_) => Text(widget.senderName),
                    child: Semantics(
                      label: widget.senderName,
                      child: ShadAvatar(
                        null,
                        size: const Size.square(AppTheme.messageAvatarSize),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppTheme.messageRadius,
                        ),
                        backgroundColor: m.outgoing
                            ? colors.primary
                            : colors.secondary,
                        placeholder: Text(
                          m.outgoing
                              ? '我'
                              : widget.senderName.characters.first
                                    .toUpperCase(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: m.outgoing
                                ? colors.primaryForeground
                                : colors.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: m.outgoing
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          IntrinsicWidth(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: m.outgoing ? null : -4,
                                  right: m.outgoing ? -4 : null,
                                  top: 14,
                                  child: Transform.rotate(
                                    angle: pi / 4,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      color: bubbleColor,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bubbleColor,
                                    borderRadius: AppTheme.messageRadius,
                                  ),
                                  child: _controller != null
                                      ? quill.QuillEditor(
                                          controller: _controller!,
                                          focusNode: _focus,
                                          scrollController: _scroll,
                                          config: quill.QuillEditorConfig(
                                            scrollable: false,
                                            showCursor: false,
                                            padding: EdgeInsets.zero,
                                            showCodeBlockLineNumbers: false,
                                            textSelectionThemeData:
                                                AppTheme.selection,
                                            customStyles: AppTheme.editorStyles(
                                              colors.foreground,
                                              colors.mutedForeground,
                                            ),
                                            onLaunchUrl: (_) async {},
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (m.kind == 'image' &&
                                                m.path != null &&
                                                m.status != 'receiving')
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 10,
                                                ),
                                                child: ShadContextMenuRegion(
                                                  items: [
                                                    ShadContextMenuItem(
                                                      enabled: !busy,
                                                      leading: const Icon(
                                                        LucideIcons.download,
                                                        size: 14,
                                                      ),
                                                      onPressed: _save,
                                                      child: const Text('另存为…'),
                                                    ),
                                                  ],
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    child: Image.file(
                                                      File(m.path!),
                                                      width: min(
                                                        width - 32,
                                                        320,
                                                      ),
                                                      height: 200,
                                                      fit: BoxFit.contain,
                                                      cacheWidth: 800,
                                                      errorBuilder: (_, _, _) =>
                                                          const SizedBox(
                                                            height: 64,
                                                            child: Center(
                                                              child: Text(
                                                                '图片预览不可用',
                                                              ),
                                                            ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  m.kind == 'image'
                                                      ? LucideIcons.image
                                                      : LucideIcons.fileText,
                                                  size: 30,
                                                  color: colors.mutedForeground,
                                                ),
                                                const SizedBox(width: 12),
                                                Flexible(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        m.name ?? '附件',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        fileSize(m.size),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: colors
                                                              .mutedForeground,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (busy)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 12,
                                                ),
                                                child: ShadProgress(
                                                  value: m.progress,
                                                ),
                                              ),
                                            if (m.kind != 'image' &&
                                                m.path != null &&
                                                !busy)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 10,
                                                ),
                                                child: ShadButton.outline(
                                                  size: ShadButtonSize.sm,
                                                  leading: const Icon(
                                                    LucideIcons.download,
                                                    size: 14,
                                                  ),
                                                  onPressed: _save,
                                                  child: const Text('另存为'),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                          if (busy || m.status == 'failed')
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  if (busy)
                                    Text(
                                      m.kind == 'text'
                                          ? '发送中…'
                                          : '${(m.progress * 100).round()}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colors.mutedForeground,
                                      ),
                                    ),
                                  if (m.status == 'failed')
                                    ShadTooltip(
                                      builder: (_) => Text(m.error ?? '传输未完成'),
                                      child: ShadButton.ghost(
                                        size: ShadButtonSize.sm,
                                        onPressed: m.outgoing
                                            ? widget.onRetry
                                            : null,
                                        leading: Icon(
                                          LucideIcons.circleAlert,
                                          size: 12,
                                          color: colors.destructive,
                                        ),
                                        child: Text(
                                          m.outgoing ? '发送失败，重试' : '接收未完成',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.destructive,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_controller != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
                      child: IgnorePointer(
                        ignoring: !_hovered && !_focused,
                        child: Opacity(
                          opacity: _hovered || _focused ? 1 : 0,
                          child: ShadTooltip(
                            builder: (_) => const Text('复制，保留格式'),
                            child: Semantics(
                              label: '复制消息，保留格式',
                              child: ShadIconButton.ghost(
                                icon: const Icon(LucideIcons.copy, size: 12),
                                width: 28,
                                height: 28,
                                onPressed: () async {
                                  try {
                                    await copyRichText(m);
                                  } on Object catch (error) {
                                    widget.onError('复制失败：$error');
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
