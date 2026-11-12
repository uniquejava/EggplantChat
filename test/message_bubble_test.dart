import 'package:eggplant_chat/message_bubble.dart';
import 'package:eggplant_chat/app_theme.dart';
import 'package:eggplant_chat/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'copy appears on hover or keyboard focus without shifting messages',
    (tester) async {
      await tester.pumpWidget(
        ShadApp(
          localizationsDelegates: const [
            quill.FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(
            body: Column(
              children: [
                for (var i = 0; i < 2; i++)
                  MessageBubble(
                    senderName: '对方',
                    message: ChatMessage(
                      id: '$i',
                      peerId: 'peer',
                      outgoing: false,
                      kind: 'text',
                      time: DateTime.now(),
                      delta: [
                        {'insert': '消息 $i\n'},
                      ],
                    ),
                    onRetry: () {},
                    onError: (_) {},
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final copies = find.byIcon(LucideIcons.copy);
      double opacity(int index) => tester
          .widget<Opacity>(
            find
                .ancestor(of: copies.at(index), matching: find.byType(Opacity))
                .last,
          )
          .opacity;
      expect(opacity(0), 0);
      expect(opacity(1), 0);
      final position = tester.getTopLeft(find.byType(MessageBubble).last);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(790, 590));
      await mouse.moveTo(
        tester.getCenter(find.byType(quill.QuillEditor).first),
      );
      await tester.pump();
      expect(opacity(0), 1);
      expect(opacity(1), 0);
      expect(tester.getTopLeft(find.byType(MessageBubble).last), position);
      await mouse.moveTo(const Offset(790, 590));
      await tester.pump();
      expect(opacity(0), 0);
      final editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor).first,
      );
      editor.focusNode.requestFocus();
      editor.controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4),
        quill.ChangeSource.local,
      );
      await tester.pump();
      expect(opacity(0), 1);
      expect(
        editor.config.textSelectionThemeData!.selectionColor!.a,
        lessThan(.5),
      );
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    },
  );

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
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: MessageBubble(
              senderName: outgoing ? '我' : '对方',
              message: message,
              onRetry: () {},
              onError: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('另存为'), findsNothing);
      expect(find.text('另存为…'), findsNothing);
      await tester.tap(
        find.byType(Image),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('另存为…'), findsOneWidget);
    });
  }
}
