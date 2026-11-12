import 'dart:io';

import 'package:eggplant_chat/chat_screen.dart';
import 'package:eggplant_chat/lan_service.dart';
import 'package:eggplant_chat/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

class RecordingService extends LanService {
  RecordingService() : super(Directory.systemTemp, deviceName: 'Mac A') {
    id = newId();
  }

  final connections = <(String, int, String?)>[];

  @override
  int get port => lanPort;

  @override
  Future<Peer> connect(
    String host,
    int remotePort, {
    String? expectedId,
  }) async {
    connections.add((host, remotePort, expectedId));
    final peer = Peer(
      id: expectedId ?? newId(),
      name: 'Mac Studio',
      host: host,
      port: remotePort,
      platform: 'macos',
    )..lastSeen = DateTime.now();
    peers[peer.id] = peer;
    notify();
    return peer;
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
  Future<void> showScreen(WidgetTester tester, RecordingService service) async {
    tester.view.physicalSize = const Size(1180, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ShadApp(
        localizationsDelegates: const [
          quill.FlutterQuillLocalizations.delegate,
        ],
        home: ChatScreen(service: service, onToggleTheme: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> closeScreen(WidgetTester tester, LanService service) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final closing = service.close();
    await tester.pump();
    await closing;
  }

  testWidgets(
    'dates are centered groups, including midnight, without per-message times',
    (tester) async {
      final service = RecordingService();
      final peer = Peer(
        id: newId(),
        name: '对方',
        host: '192.168.1.2',
        port: lanPort,
        platform: 'windows',
      );
      service.peers[peer.id] = peer;
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final times = [
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 40),
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 42),
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 58),
        DateTime(now.year, now.month, now.day, 0, 1),
      ];
      final oldDate = '${yesterday.month}月${yesterday.day}日';
      for (var i = 0; i < times.length; i++) {
        service.messages.add(
          ChatMessage(
            id: newId(),
            peerId: peer.id,
            outgoing: i.isOdd,
            kind: 'text',
            time: times[i],
            delta: [
              {'insert': '消息 $i\n'},
            ],
          ),
        );
      }
      await showScreen(tester, service);
      for (final label in ['$oldDate  23:40', '$oldDate  23:58', '00:01']) {
        final date = find.text(label);
        expect(date, findsOneWidget);
        expect(tester.getCenter(date).dx, 762);
      }
      expect(find.text('$oldDate  23:42'), findsNothing);
      expect(find.text('${now.month}月${now.day}日  00:01'), findsNothing);
      for (final time in ['23:40', '23:42', '23:58']) {
        expect(find.text(time), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await closeScreen(tester, service);
    },
  );

  for (final platform in ['macos', 'windows', 'linux', 'unknown']) {
    testWidgets('device avatar uses $platform identity in list and header', (
      tester,
    ) async {
      final service = RecordingService();
      final peer = Peer(
        id: newId(),
        name: '设备',
        host: '192.168.1.2',
        port: lanPort,
        platform: platform,
      );
      service.peers[peer.id] = peer;
      await showScreen(tester, service);
      if (platform == 'unknown') {
        expect(find.byIcon(LucideIcons.monitor), findsNWidgets(2));
      } else {
        final icons = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
        expect(
          icons.where(
            (icon) =>
                icon.bytesLoader is SvgAssetLoader &&
                (icon.bytesLoader as SvgAssetLoader).assetName ==
                    'assets/platforms/$platform.svg',
          ),
          hasLength(2),
        );
      }
      expect(tester.takeException(), isNull);
      await closeScreen(tester, service);
    });
  }

  testWidgets('clicking a nearby device connects without a dialog', (
    tester,
  ) async {
    final service = RecordingService();
    final nearby = Peer(
      id: newId(),
      name: 'Mac Studio',
      host: '192.168.3.11',
      port: lanPort,
      platform: 'macos',
    )..lastSeen = DateTime.now();
    service.nearby[nearby.id] = nearby;
    await showScreen(tester, service);
    await tester.tap(find.text('Mac Studio'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(service.connections, [('192.168.3.11', lanPort, nearby.id)]);
    expect(
      find.byType(DragToMoveArea),
      findsNWidgets(Platform.isMacOS ? 3 : 2),
    );
    expect(find.byType(ShadDialog), findsNothing);
    expect(find.text('Mac Studio'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await closeScreen(tester, service);
  });

  testWidgets('a fixed IP connects with no pairing code field', (tester) async {
    final service = RecordingService();
    await showScreen(tester, service);
    await tester.tap(find.text('通过 IP 连接'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('对方配对码'), findsNothing);
    expect(find.text('六位数字'), findsNothing);
    final host = find
        .descendant(
          of: find.byType(ShadDialog),
          matching: find.byType(ShadInput),
        )
        .first;
    await tester.enterText(host, '192.168.3.11');
    await tester.tap(find.text('连接'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.connections, [('192.168.3.11', lanPort, null)]);
    expect(find.byType(ShadDialog), findsNothing);
    expect(find.text('Mac Studio'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await closeScreen(tester, service);
  });

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
