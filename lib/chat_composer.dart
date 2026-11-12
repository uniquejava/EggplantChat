// Flutter Quill 11.x marks its clipboard hooks as experimental.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme.dart';
import 'rich_clipboard.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.directory,
    required this.initialDelta,
    required this.initialFiles,
    required this.onDraftChanged,
    required this.onSend,
    required this.onError,
  });
  final Directory directory;
  final List<dynamic>? initialDelta;
  final List<File> initialFiles;
  final void Function(List<dynamic>, List<File>) onDraftChanged;
  final Future<void> Function(List<dynamic>, List<File>) onSend;
  final void Function(String) onError;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final quill.QuillController _controller;
  final _focus = FocusNode();
  final _editorKey = GlobalKey<quill.QuillRawEditorState>();
  final _scroll = ScrollController();
  late final List<File> _files;
  bool _sending = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _files = List.of(widget.initialFiles);
    _controller = quill.QuillController(
      document: widget.initialDelta == null
          ? quill.Document()
          : quill.Document.fromJson(widget.initialDelta!),
      selection: const TextSelection.collapsed(offset: 0),
      config: quill.QuillControllerConfig(
        clipboardConfig: quill.QuillClipboardConfig(
          onClipboardPaste: _pasteImage,
          onRichTextPaste: (delta, external) async {
            if (delta.toJson().any((op) => op['insert'] is! String)) {
              widget.onError('含图片的内容请通过图片或附件按钮添加');
              return null;
            }
            return delta;
          },
        ),
      ),
    )..addListener(_draftChanged);
  }

  void _draftChanged() {
    widget.onDraftChanged(
      _controller.document.toDelta().toJson(),
      List.of(_files),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _pasteImage() async {
    if (_sending) return true;
    try {
      final file = await clipboardImage(widget.directory);
      if (file == null) return false;
      if (mounted) {
        _files.add(file);
        _draftChanged();
      }
      return true;
    } on Object catch (error) {
      widget.onError('无法读取剪贴板：$error');
      return true;
    }
  }

  Future<void> _pick(bool images) async {
    try {
      final selected = await openFiles(
        acceptedTypeGroups: images
            ? const [
                XTypeGroup(
                  label: '图片',
                  extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
                  uniformTypeIdentifiers: ['public.image'],
                ),
              ]
            : [],
      );
      if (!mounted) return;
      _files.addAll(selected.map((file) => File(file.path)));
      _draftChanged();
    } on Object catch (error) {
      widget.onError('无法选择附件：$error');
    }
  }

  Future<void> _send() async {
    if (_sending ||
        _controller.document.toPlainText().trim().isEmpty && _files.isEmpty) {
      return;
    }
    final delta = _controller.document.toDelta().toJson();
    final files = List<File>.of(_files);
    final selection = _controller.selection;
    setState(() => _sending = true);
    _controller.readOnly = true;
    _files.clear();
    _controller.document = quill.Document();
    _controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      quill.ChangeSource.local,
    );
    _draftChanged();
    try {
      await widget.onSend(delta, files);
    } on Object catch (error) {
      if (!mounted) return;
      _files.addAll(files);
      _controller.document = quill.Document.fromJson(delta);
      _controller.updateSelection(selection, quill.ChangeSource.local);
      _draftChanged();
      widget.onError('发送失败：$error');
    } finally {
      if (mounted) {
        _controller.readOnly = false;
        setState(() => _sending = false);
        _focus.requestFocus();
      }
    }
  }

  Widget _tool(String label, IconData icon, VoidCallback action) => ShadTooltip(
    builder: (_) => Text(label),
    child: Semantics(
      label: label,
      child: ShadIconButton.ghost(
        icon: Icon(icon, size: 18),
        width: 36,
        height: 36,
        enabled: !_sending,
        onPressed: action,
      ),
    ),
  );

  @override
  void dispose() {
    _controller.removeListener(_draftChanged);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return DropTarget(
      enable: !_sending,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        for (final file in detail.files) {
          if (await FileSystemEntity.isFile(file.path)) {
            _files.add(File(file.path));
          } else {
            widget.onError('请选择文件；文件夹可压缩后发送');
          }
        }
        if (mounted) _draftChanged();
      },
      child: Container(
        decoration: BoxDecoration(
          color: _dragging ? colors.muted : colors.background,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _files
                      .map(
                        (file) => ShadButton.secondary(
                          size: ShadButtonSize.sm,
                          enabled: !_sending,
                          leading: const Icon(LucideIcons.paperclip, size: 14),
                          trailing: const Icon(LucideIcons.x, size: 12),
                          onPressed: () {
                            _files.remove(file);
                            _draftChanged();
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(
                              file.uri.pathSegments.last,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            SizedBox(
              height: AppTheme.composerHeight,
              child: quill.QuillEditor(
                controller: _controller,
                focusNode: _focus,
                scrollController: _scroll,
                config: quill.QuillEditorConfig(
                  editorKey: _editorKey,
                  onKeyPressed: (event, _) {
                    if (event.logicalKey != LogicalKeyboardKey.enter &&
                        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
                      return null;
                    }
                    final composing = _editorKey
                        .currentState
                        ?.currentTextEditingValue
                        ?.composing;
                    if (composing != null && !composing.isCollapsed) {
                      return KeyEventResult.skipRemainingHandlers;
                    }
                    if (HardwareKeyboard.instance.isAltPressed ||
                        HardwareKeyboard.instance.isControlPressed ||
                        HardwareKeyboard.instance.isMetaPressed) {
                      return null;
                    }
                    if (event is KeyDownEvent) {
                      if (HardwareKeyboard.instance.isShiftPressed) {
                        if (!_sending) {
                          final selection = _controller.selection;
                          _controller.replaceText(
                            selection.start,
                            selection.end - selection.start,
                            '\n',
                            TextSelection.collapsed(
                              offset: selection.start + 1,
                            ),
                          );
                        }
                      } else {
                        _send();
                      }
                    }
                    return KeyEventResult.handled;
                  },
                  placeholder: _dragging ? '松开以添加附件' : '输入消息…',
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textSelectionThemeData: AppTheme.selection,
                  customStyles: AppTheme.editorStyles(
                    colors.foreground,
                    colors.mutedForeground,
                  ),
                  onLaunchUrl: (_) async {},
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _tool('发送图片', LucideIcons.imagePlus, () => _pick(true)),
                _tool('添加附件', LucideIcons.paperclip, () => _pick(false)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enter 发送 · Shift + Enter 换行',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
                ShadButton(
                  size: ShadButtonSize.sm,
                  enabled:
                      !_sending &&
                      (_controller.document.toPlainText().trim().isNotEmpty ||
                          _files.isNotEmpty),
                  onPressed: _send,
                  leading: Icon(
                    _sending ? LucideIcons.loaderCircle : LucideIcons.send,
                    size: 15,
                  ),
                  child: Text(_sending ? '发送中' : '发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
