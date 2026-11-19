import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eggplant_chat/message_bubble.dart';
import 'package:eggplant_chat/models.dart';
import 'package:eggplant_chat/rich_clipboard.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// Run with EGGPLANT_CHAT_TEST_PASTEBOARD=1 flutter test -d macos
// integration_test/rich_clipboard_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('copies PNG pixels through an isolated macOS pasteboard', (
    tester,
  ) async {
    const channel = MethodChannel('eggplant_chat/test_pasteboard');
    expect(await channel.invokeMethod<bool>('isIsolated'), isTrue);
    final folder = await Directory.systemTemp.createTemp('chat-clipboard-');
    addTearDown(() => folder.delete(recursive: true));
    final pixels = Uint8List.fromList([255, 0, 0, 255, 0, 255, 17, 255]);
    final sourceImage = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      2,
      1,
      ui.PixelFormat.rgba8888,
      sourceImage.complete,
    );
    final source = File('${folder.path}/selected.png');
    final image = await sourceImage.future;
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await source.writeAsBytes(png.buffer.asUint8List());
    } finally {
      image.dispose();
    }

    final errors = <String>[];
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: newId(),
              peerId: newId(),
              outgoing: false,
              kind: 'image',
              time: DateTime.now(),
              name: 'selected.png',
              path: source.path,
            ),
            senderName: 'Test sender',
            onRetry: () {},
            onDelete: () async {},
            onError: errors.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(Image),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    File? pasted;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (pasted == null &&
        errors.isEmpty &&
        DateTime.now().isBefore(deadline)) {
      pasted = await clipboardImage(folder);
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(errors, isEmpty);
    expect(
      pasted,
      isNotNull,
      reason: 'Copy should put an image on the pasteboard',
    );
    final pngFile = pasted!;
    final codec = await ui.instantiateImageCodec(await pngFile.readAsBytes());
    try {
      final readBack = (await codec.getNextFrame()).image;
      try {
        expect((readBack.width, readBack.height), (2, 1));
        final bytes = (await readBack.toByteData())!;
        expect(bytes.buffer.asUint8List(), orderedEquals(pixels));
      } finally {
        readBack.dispose();
      }
    } finally {
      codec.dispose();
    }

    await deleteClipboardImage(File(pngFile.path));
    expect(await pngFile.exists(), isTrue);
    await deleteClipboardImage(pngFile);
    expect(await pngFile.exists(), isFalse);
    await deleteClipboardImage(source);
    expect(await source.exists(), isTrue);
  }, skip: !Platform.isMacOS);
}
