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
    required this.onRetry,
    required this.onError,
  });
  final ChatMessage message;
  final VoidCallback onRetry;
  final void Function(String) onError;
  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  quill.QuillController? _controller;
  final _focus = FocusNode();
  final _scroll = ScrollController();

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
    final busy = ['sending', 'receiving'].contains(m.status);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(560.0, constraints.maxWidth - 72);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: m.outgoing
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: width),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: m.outgoing ? colors.secondary : colors.background,
                  border: Border.all(color: colors.border),
                  borderRadius: AppTheme.radius,
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
                          customStyles: AppTheme.editorStyles(
                            colors.foreground,
                          ),
                          onLaunchUrl: (_) async {},
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m.kind == 'image' &&
                              m.path != null &&
                              m.status != 'receiving')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
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
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(m.path!),
                                    width: min(width - 32, 320),
                                    height: 200,
                                    fit: BoxFit.contain,
                                    cacheWidth: 800,
                                    errorBuilder: (_, _, _) => const SizedBox(
                                      height: 64,
                                      child: Center(child: Text('图片预览不可用')),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      m.name ?? '附件',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      fileSize(m.size),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (busy)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: ShadProgress(value: m.progress),
                            ),
                          if (m.kind != 'image' && m.path != null && !busy)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
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
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(
                    '${m.time.hour.toString().padLeft(2, '0')}:${m.time.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.mutedForeground,
                    ),
                  ),
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
                  if (m.status == 'sent' && m.outgoing)
                    Icon(
                      LucideIcons.check,
                      size: 12,
                      color: colors.mutedForeground,
                    ),
                  if (_controller != null)
                    ShadTooltip(
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
                  if (m.status == 'failed')
                    ShadTooltip(
                      builder: (_) => Text(m.error ?? '传输未完成'),
                      child: ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        onPressed: m.outgoing ? widget.onRetry : null,
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
            ],
          ),
        );
      },
    );
  }
}
