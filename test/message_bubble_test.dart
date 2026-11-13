import 'dart:io';

import 'package:eggplant_chat/message_bubble.dart';
import 'package:eggplant_chat/app_theme.dart';
import 'package:eggplant_chat/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('chat sides, avatars and content sizing (dark: $dark)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ShadApp(
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          darkTheme: ShadThemeData(
            brightness: Brightness.dark,
            colorScheme: const ShadZincColorScheme.dark(),
          ),
          localizationsDelegates: const [
            quill.FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    MessageBubble(
                      senderName: i == 0 ? '对方' : '我',
                      message: ChatMessage(
                        id: '$i',
                        peerId: 'peer',
                        outgoing: i != 0,
                        kind: 'text',
                        time: DateTime.now(),
                        delta: [
                          {
                            'insert': i == 2
                                ? List.filled(12, '长文字自动换行，').join()
                                : '短消息',
                            'attributes': {'bold': true},
                          },
                          {'insert': '\n'},
                        ],
                      ),
                      onRetry: () {},
                      onDelete: () async {},
                      onError: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avatars = find.byType(ShadAvatar);
      final editors = find.byType(quill.QuillEditor);
      expect(avatars, findsNWidgets(3));
      expect(tester.getTopLeft(avatars.at(0)).dx, 0);
      expect(tester.getTopRight(avatars.at(1)).dx, 360);
      expect(
        tester.getTopLeft(editors.at(0)).dx,
        greaterThan(tester.getTopRight(avatars.at(0)).dx),
      );
      expect(
        tester.getTopRight(editors.at(1)).dx,
        lessThan(tester.getTopLeft(avatars.at(1)).dx),
      );
      expect(tester.getSize(editors.at(0)).width, lessThan(120));
      expect(tester.getSize(editors.at(2)).width, lessThanOrEqualTo(360 * .72));
      expect(
        tester.getSize(editors.at(2)).height,
        greaterThan(tester.getSize(editors.at(1)).height),
      );
      final bubbles = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration as BoxDecoration).borderRadius ==
                    AppTheme.messageRadius,
          )
          .toList();
      expect(bubbles, hasLength(3));
      expect(
        (bubbles[1].decoration as BoxDecoration).color,
        dark ? AppTheme.outgoingBubbleDark : AppTheme.outgoingBubbleLight,
      );
      expect(
        (bubbles[0].decoration as BoxDecoration).color,
        isNot((bubbles[1].decoration as BoxDecoration).color),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('text context menu invokes delete without save as', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: MessageBubble(
            senderName: '我',
            message: ChatMessage(
              id: newId(),
              peerId: newId(),
              outgoing: true,
              kind: 'text',
              time: DateTime.now(),
              delta: [
                {'insert': 'hello\n'},
              ],
              status: 'sent',
            ),
            onRetry: () {},
            onDelete: () async {
              deleted = true;
            },
            onError: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(quill.QuillEditor),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextSelectionToolbar), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.byIcon(LucideIcons.copy), findsNothing);
    expect(find.text('Save as…'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
    expect(find.text('删除这条消息？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
    await tester.tap(
      find.byType(quill.QuillEditor),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  for (final entry in {
    'report.pdf': LucideIcons.file,
    'REPORT.PDF': LucideIcons.file,
    'notes.txt': LucideIcons.fileText,
    'letter.docx': LucideIcons.fileText,
    'table.XLSX': LucideIcons.fileSpreadsheet,
    'backup.zip': LucideIcons.fileArchive,
    'README': LucideIcons.file,
  }.entries) {
    testWidgets('file card icon and context menu: ${entry.key}', (
      tester,
    ) async {
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: MessageBubble(
              senderName: '我',
              message: ChatMessage(
                id: newId(),
                peerId: newId(),
                outgoing: true,
                kind: 'file',
                time: DateTime.now(),
                name: entry.key,
                path: '/tmp/report.pdf',
                status: 'sent',
              ),
              onRetry: () {},
              onDelete: () async {},
              onError: (_) {},
            ),
          ),
        ),
      );
      expect(
        find.text('PDF'),
        entry.key.toLowerCase().endsWith('.pdf')
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.byIcon(entry.value), findsOneWidget);
      expect(find.text('另存为'), findsNothing);
      await tester.tap(
        find.text(entry.key),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Save as…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final outgoing in [true, false]) {
    testWidgets('image save is in context menu (outgoing: $outgoing)', (
      tester,
    ) async {
      final message = ChatMessage(
        id: newId(),
        peerId: newId(),
        outgoing: outgoing,
        kind: 'image',
        time: DateTime.now(),
        name: 'image.png',
        path: 'assets/branding/app-icon-1024-raw.png',
        status: 'sent',
      );
      await tester.pumpWidget(const ShadApp(home: Scaffold()));
      await tester.runAsync(
        () => precacheImage(
          FileImage(File(message.path!)),
          tester.element(find.byType(Scaffold)),
        ),
      );
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: MessageBubble(
              senderName: outgoing ? '我' : '对方',
              message: message,
              onRetry: () {},
              onDelete: () async {},
              onError: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('另存为'), findsNothing);
      expect(find.text('Save as…'), findsNothing);
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.getSize(find.byType(Image)).width, lessThanOrEqualTo(320));
      expect(tester.getSize(find.byType(Image)).height, lessThanOrEqualTo(360));
      await tester.tap(
        find.byType(Image),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Save as…'), findsOneWidget);
    });
  }
}
