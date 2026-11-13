import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme.dart';
import 'models.dart';
import 'rich_clipboard.dart';

IconData _fileIcon(String? name) {
  final extension = name != null && name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  return switch (extension) {
    'pdf' || 'doc' || 'docx' || 'txt' || 'rtf' || 'odt' => LucideIcons.fileText,
    'xls' || 'xlsx' || 'csv' || 'ods' => LucideIcons.fileSpreadsheet,
    'ppt' || 'pptx' || 'odp' => LucideIcons.fileChartColumn,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => LucideIcons.fileArchive,
    'mp3' ||
    'wav' ||
    'flac' ||
    'aac' ||
    'm4a' ||
    'ogg' => LucideIcons.fileAudio,
    'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' => LucideIcons.fileVideo,
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'svg' ||
    'heic' => LucideIcons.fileImage,
    'dart' ||
    'js' ||
    'ts' ||
    'tsx' ||
    'json' ||
    'html' ||
    'css' ||
    'py' ||
    'java' ||
    'swift' ||
    'cpp' ||
    'c' ||
    'sh' ||
    'yaml' ||
    'yml' ||
    'xml' => LucideIcons.fileCode,
    _ => LucideIcons.file,
  };
}

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.senderName,
    required this.onRetry,
    required this.onError,
    required this.onDelete,
  });
  final ChatMessage message;
  final String senderName;
  final VoidCallback onRetry;
  final Future<void> Function() onDelete;
  final void Function(String) onError;
  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  quill.QuillController? _controller;
  final _focus = FocusNode();
  final _contextMenu = ShadContextMenuController();
  Offset _menuPosition = Offset.zero;
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

  List<ShadContextMenuItem> _menu() {
    final m = widget.message;
    final busy = ['sending', 'receiving'].contains(m.status);
    return [
      ShadContextMenuItem(
        enabled: m.kind == 'text' || (m.path != null && !busy),
        onPressed: () async {
          try {
            await copyMessage(m);
          } on Object catch (error) {
            widget.onError('复制失败：$error');
          }
        },
        child: const Text('Copy'),
      ),
      if (m.kind != 'text')
        ShadContextMenuItem(
          enabled: m.path != null && !busy,
          onPressed: _save,
          child: const Text('Save as…'),
        ),
      ShadContextMenuItem(
        enabled: !busy,
        onPressed: () async {
          final confirmed = await showShadDialog<bool>(
            context: context,
            barrierColor: const Color(0x33000000),
            builder: (dialogContext) => ShadDialog(
              title: const Text('删除这条消息？'),
              actions: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                ShadButton.destructive(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          try {
            await widget.onDelete();
          } on Object catch (error) {
            widget.onError('删除失败：$error');
          }
        },
        child: const Text('Delete'),
      ),
    ];
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

  Future<void> _viewImage() => showShadDialog<void>(
    context: context,
    builder: (dialogContext) => ShadDialog(
      title: Text(widget.message.name ?? '图片'),
      actions: [
        ShadButton.outline(onPressed: _save, child: const Text('另存为')),
        ShadButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
      child: SizedBox(
        width: MediaQuery.sizeOf(dialogContext).width * .8,
        height: MediaQuery.sizeOf(dialogContext).height * .7,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 12,
          child: Center(
            child: Image.file(
              File(widget.message.path!),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text('图片预览不可用'),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller?.dispose();
    _contextMenu.dispose();
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
    final hasImage =
        m.kind == 'image' && m.path != null && m.status != 'receiving';
    final busy = ['sending', 'receiving'].contains(m.status);
    return ShadContextMenu(
      controller: _contextMenu,
      anchor: ShadGlobalAnchor(_menuPosition),
      items: _menu(),
      child: Listener(
        onPointerDown: (event) {
          if (m.kind == 'text' && event.buttons == kSecondaryMouseButton) {
            setState(() => _menuPosition = event.position);
            _contextMenu.show();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = min(560.0, constraints.maxWidth * .72);
            return Padding(
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
                                if (m.kind == 'text')
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
                                  padding: !hasImage
                                      ? const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        )
                                      : EdgeInsets.zero,
                                  decoration: BoxDecoration(
                                    color: m.kind == 'text'
                                        ? bubbleColor
                                        : (hasImage ? null : colors.muted),
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
                                            enableSelectionToolbar: false,
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
                                            if (hasImage)
                                              ShadContextMenuRegion(
                                                items: _menu(),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: Semantics(
                                                    label: '查看图片',
                                                    button: true,
                                                    child: InkWell(
                                                      onTap: _viewImage,
                                                      hoverColor:
                                                          Colors.transparent,
                                                      highlightColor:
                                                          Colors.transparent,
                                                      splashFactory: NoSplash
                                                          .splashFactory,
                                                      child: ConstrainedBox(
                                                        constraints:
                                                            BoxConstraints(
                                                              maxWidth: min(
                                                                width,
                                                                320,
                                                              ),
                                                              maxHeight: 360,
                                                            ),
                                                        child: Image.file(
                                                          File(m.path!),
                                                          fit: BoxFit.contain,
                                                          errorBuilder:
                                                              (
                                                                _,
                                                                _,
                                                                _,
                                                              ) => const SizedBox(
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
                                                ),
                                              ),
                                            if (!hasImage)
                                              ShadContextMenuRegion(
                                                items: _menu(),
                                                child: SizedBox(
                                                  width: min(width - 24, 280),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 8,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                m.name ?? '附件',
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 6,
                                                              ),
                                                              Text(
                                                                fileSize(
                                                                  m.size,
                                                                ),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: colors
                                                                      .mutedForeground,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 16,
                                                        ),
                                                        Icon(
                                                          _fileIcon(m.name),
                                                          size: 32,
                                                          color: colors
                                                              .mutedForeground,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
