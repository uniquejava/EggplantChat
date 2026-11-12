import 'dart:io';

import 'package:eggplant_chat/chat_screen.dart';
import 'package:eggplant_chat/lan_service.dart';
import 'package:eggplant_chat/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RecordingService extends LanService {
  RecordingService() : super(Directory.systemTemp, deviceName: 'Mac A') {
    id = newId();
  }

  @override
  Future<void> sendText(Peer peer, List<dynamic> delta) async {
    messages.add(
      ChatMessage(
        id: newId(),
        peerId: peer.id,
        outgoing: true,
        kind: 'text',
        time: DateTime.now(),
        delta: checkedDelta(delta),
      ),
    );
    notify();
  }
}

void main() {
  testWidgets(
    'chat editor sends rich text and keeps separate conversation drafts',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = RecordingService();
      final first = Peer(
        id: newId(),
        name: '设备 B',
        host: '192.168.1.2',
        port: lanPort,
        platform: 'windows',
      );
      final second = Peer(
        id: newId(),
        name: '设备 C',
        host: '192.168.1.3',
        port: lanPort,
        platform: 'macos',
      );
      service.peers.addAll({first.id: first, second.id: second});
      await tester.pumpWidget(
        ShadApp(
          localizationsDelegates: const [
            quill.FlutterQuillLocalizations.delegate,
          ],
          home: ChatScreen(service: service, onToggleTheme: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      final delta = [
        {
          'insert': '带格式消息',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ];
      var editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor).first,
      );
      editor.controller.document = quill.Document.fromJson(delta);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('设备 C').first);
      await tester.pump(const Duration(milliseconds: 250));
      editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor).first,
      );
      expect(editor.controller.document.toPlainText(), '\n');
      await tester.tap(find.text('设备 B').first);
      await tester.pump(const Duration(milliseconds: 250));
      editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor).first,
      );
      expect(editor.controller.document.toDelta().toJson(), delta);
      await tester.tap(find.text('发送'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(service.messages.single.delta, delta);
      expect(service.messages.single.peerId, first.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      final closing = service.close();
      await tester.pump();
      await closing;
    },
  );
}
