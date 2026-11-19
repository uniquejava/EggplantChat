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

class ChatDraft extends ChangeNotifier {
  ChatDraft({this._delta, List<File> files = const []})
    : _files = List.of(files);

  List<dynamic>? _delta;
  List<File> _files;
  bool _sending = false;

  void _setSendState(bool sending, List<dynamic>? delta, List<File> files) {
    _sending = sending;
    _delta = delta;
    _files = files;
    if (hasListeners) notifyListeners();
  }
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.directory,
    required this.draft,
    required this.onSendText,
    required this.onSendFile,
    required this.onError,
  });
  final Directory directory;
  final ChatDraft draft;
  final Future<void> Function(List<dynamic>) onSendText;
  final Future<void> Function(File) onSendFile;
  final void Function(String) onError;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final quill.QuillController _controller;
  final _focus = FocusNode();
  final _editorKey = GlobalKey<quill.QuillRawEditorState>();
  final _scroll = ScrollController();
  List<File> get _files => widget.draft._files;
  bool get _sending => widget.draft._sending;
  int _sendGeneration = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _controller = quill.QuillController(
      document: draft._delta == null
          ? quill.Document()
          : quill.Document.fromJson(draft._delta!),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: _sending,
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
    draft.addListener(_applyDraft);
  }

  void _draftChanged() {
    if (_sending) return;
    widget.draft._delta = _controller.document.toDelta().toJson();
    if (mounted) setState(() {});
  }

  void _applyDraft() {
    final draft = widget.draft;
    final delta = draft._delta;
    _controller.removeListener(_draftChanged);
    _controller.readOnly = _sending;
    _controller.document = delta == null
        ? quill.Document()
        : quill.Document.fromJson(delta);
    _controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      quill.ChangeSource.local,
    );
    _controller.addListener(_draftChanged);
    setState(() {});
  }

  Future<bool> _pasteImage() async {
    if (_sending) return true;
    final generation = _sendGeneration;
    try {
      final file = await clipboardImage(widget.directory);
      if (file == null) return false;
      if (!mounted || _sending || generation != _sendGeneration) {
        await deleteClipboardImage(file);
        return true;
      }
      _files.add(file);
      _draftChanged();
      return true;
    } on Object catch (error) {
      if (mounted) widget.onError('无法读取剪贴板：$error');
      return true;
    }
  }

  Future<void> _pick(bool images) async {
    final generation = _sendGeneration;
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
      if (!mounted || _sending || generation != _sendGeneration) return;
      _files.addAll(selected.map((file) => File(file.path)));
      _draftChanged();
    } on Object catch (error) {
      widget.onError('无法选择附件：$error');
    }
  }

  Future<void> _send() async {
    final hasText = _controller.document.toPlainText().trim().isNotEmpty;
    if (_sending || !hasText && _files.isEmpty) return;

    final draft = widget.draft;
    final sendText = widget.onSendText;
    final sendFile = widget.onSendFile;
    final onError = widget.onError;
    List<dynamic>? remainingText = _controller.document.toDelta().toJson();
    final files = _files;
    final selection = _controller.selection;
    var nextFile = 0;
    _sendGeneration++;
    draft._setSendState(true, null, []);
    try {
      if (hasText) {
        await sendText(remainingText);
        remainingText = null;
      }
      for (; nextFile < files.length; nextFile++) {
        await sendFile(files[nextFile]);
      }
      remainingText = null;
    } on Object catch (error) {
      onError('发送失败：$error');
    } finally {
      draft._setSendState(false, remainingText, files.sublist(nextFile));
      if (mounted) {
        if (remainingText != null) {
          _controller.updateSelection(selection, quill.ChangeSource.local);
        }
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
    widget.draft.removeListener(_applyDraft);
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
        final generation = _sendGeneration;
        setState(() => _dragging = false);
        final files = <File>[];
        for (final file in detail.files) {
          if (await FileSystemEntity.isFile(file.path)) {
            files.add(File(file.path));
          } else {
            widget.onError('请选择文件；文件夹可压缩后发送');
          }
        }
        if (!mounted || _sending || generation != _sendGeneration) return;
        _files.addAll(files);
        _draftChanged();
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
                          onPressed: () async {
                            if (_sending || !_files.remove(file)) return;
                            _draftChanged();
                            await deleteClipboardImage(file);
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
