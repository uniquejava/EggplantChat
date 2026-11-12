import 'package:eggplant_chat/message_bubble.dart';
import 'package:eggplant_chat/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
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
