import 'dart:async';
import 'dart:io';

import 'package:eggplant_chat/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  final delta = [
    {
      'insert': '你好',
      'attributes': {'bold': true},
    },
    {'insert': '\n'},
  ];

  Future<quill.QuillEditor> showComposer(
    WidgetTester tester, {
    required Future<void> Function(List<dynamic>, List<File>) onSend,
    List<File> files = const [],
    void Function(String)? onError,
  }) async {
    await tester.pumpWidget(
      ShadApp(
        localizationsDelegates: const [
          quill.FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: ChatComposer(
            directory: Directory.systemTemp,
            initialDelta: delta,
            initialFiles: files,
            onDraftChanged: (_, _) {},
            onSend: onSend,
            onError: onError ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    editor.focusNode.requestFocus();
    editor.controller.updateSelection(
      const TextSelection.collapsed(offset: 2),
      quill.ChangeSource.local,
    );
    await tester.pump();
    return editor;
  }

  testWidgets('Enter clears immediately while delivery is pending', (
    tester,
  ) async {
    final delivery = Completer<void>();
    final sent = <List<dynamic>>[];
    final editor = await showComposer(
      tester,
      onSend: (text, _) {
        sent.add(text);
        return delivery.future;
      },
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent.single, delta);
    expect(editor.controller.document.toPlainText(), '\n');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sent, hasLength(1));
    delivery.complete();
    await tester.pump();
    expect(editor.controller.document.toPlainText(), '\n');
  });

  testWidgets('Shift Enter inserts a newline without sending', (tester) async {
    var sends = 0;
    final editor = await showComposer(
      tester,
      onSend: (_, _) async {
        sends++;
      },
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sends, 0);
    expect(editor.controller.document.toPlainText(), '你好\n\n');
  });

  testWidgets('IME confirmation does not send a message', (tester) async {
    var sends = 0;
    await showComposer(
      tester,
      onSend: (_, _) async {
        sends++;
      },
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你好',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 0);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你好',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sends, 1);
  });

  testWidgets('failed handoff restores rich text and attachments', (
    tester,
  ) async {
    final delivery = Completer<void>();
    final errors = <String>[];
    final file = File('/tmp/draft.png');
    final editor = await showComposer(
      tester,
      files: [file],
      onSend: (_, files) {
        expect(files, [file]);
        return delivery.future;
      },
      onError: errors.add,
    );
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(editor.controller.document.toPlainText(), '\n');
    expect(find.text('draft.png'), findsNothing);
    delivery.completeError(StateError('test failure'));
    await tester.pump();
    expect(editor.controller.document.toDelta().toJson(), delta);
    expect(find.text('draft.png'), findsOneWidget);
    expect(errors.single, contains('发送失败'));
  });
}
