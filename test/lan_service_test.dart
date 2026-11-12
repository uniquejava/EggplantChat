import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:eggplant_chat/lan_service.dart';
import 'package:eggplant_chat/models.dart';
import 'package:eggplant_chat/rich_clipboard.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late LanService a;
  late LanService b;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('eggplant-chat-test-');
    a = LanService(Directory('${temporary.path}/a'), deviceName: 'Mac A');
    b = LanService(Directory('${temporary.path}/b'), deviceName: 'Windows B');
    await Future.wait([
      a.start(listenPort: 0, discovery: false),
      b.start(listenPort: 0, discovery: false),
    ]);
  });

  tearDown(() async {
    await Future.wait([a.close(), b.close()]);
    await temporary.delete(recursive: true);
  });

  Future<Peer> connect() => a.connect('127.0.0.1', b.port);

  Future<HttpClientResponse> post(
    HttpClient client,
    String path,
    Object body, {
    String? token,
  }) async {
    final request = await client.postUrl(
      Uri.parse('https://127.0.0.1:${b.port}$path'),
    );
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    request.write(jsonEncode(body));
    return request.close();
  }

  test('connects directly without a code or an open dialog', () async {
    final peer = await connect();
    expect(peer.id, b.id);
    expect(b.peers[a.id]!.name, 'Mac A');
    final token = peer.token;
    final inboundToken = peer.inboundToken;
    final reconnected = await connect();
    expect(reconnected.token, token);
    expect(reconnected.inboundToken, inboundToken);
    expect(a.peers, hasLength(1));
    expect(b.peers, hasLength(1));
  });

  test('rejects invalid addresses and mismatched device identities', () async {
    for (final address in ['example.com', '8.8.8.8', '::1']) {
      await expectLater(a.connect(address, b.port), throwsFormatException);
    }
    await expectLater(
      a.connect('127.0.0.1', b.port, expectedId: newId()),
      throwsFormatException,
    );
    await expectLater(a.connect('127.0.0.1', a.port), throwsFormatException);
    expect(a.peers, isEmpty);
    expect(b.peers, isEmpty);
  });

  test(
    'rich text survives bidirectional HTTPS transfer, retry and restart',
    () async {
      final peer = await connect();
      final delta = [
        {
          'insert': '中文标题',
          'attributes': {'bold': true},
        },
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {'insert': '列表项目'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': '  final x = 1;  '},
        {
          'insert': '\n',
          'attributes': {'code-block': true},
        },
      ];
      await a.sendText(peer, delta);
      expect(a.messages.single.status, 'sent');
      expect(b.messages.single.delta, delta);
      expect(
        Document.fromJson(b.messages.single.delta!).toPlainText(),
        '中文标题\n列表项目\n  final x = 1;  \n',
      );
      expect(richTextHtml(delta), contains('<strong>中文标题</strong>'));
      expect(richTextHtml(delta), contains('<ul>'));
      await a.retry(a.messages.single);
      expect(b.messages, hasLength(1));
      await b.sendText(b.peers[a.id]!, [
        {'insert': '收到\n'},
      ]);
      expect(a.messages.last.plainText, '收到\n');
      final directory = a.directory;
      await a.close();
      a = LanService(directory);
      await a.start(listenPort: 0, discovery: false);
      expect(a.messages.first.delta, delta);
      expect(a.peers.values.single.fingerprint, b.fingerprint);
      final reconnected = await connect();
      await a.sendText(reconnected, [
        {'insert': '重启后直连\n'},
      ]);
      expect(a.messages.last.status, 'sent');
      expect(b.messages.last.plainText, '重启后直连\n');
      await b.sendText(b.peers[a.id]!, [
        {'insert': '重启后收到\n'},
      ]);
      expect(b.messages.last.plainText, '重启后收到\n');
      expect(a.messages.last.plainText, '重启后收到\n');
      expect(a.messages.last.status, 'sent');
    },
  );

  test(
    'streams attachments, keeps a local snapshot, and deduplicates retries',
    () async {
      final peer = await connect();
      final bytes = List.generate(256 * 1024 + 17, (i) => i % 251);
      final file = await File('${temporary.path}/报告与图片.bin')
          .writeAsBytes(bytes);
      await a.sendFile(peer, file);
      final received = b.messages.single;
      expect(received.status, 'sent');
      expect(received.name, '报告与图片.bin');
      expect(await File(received.path!).readAsBytes(), bytes);
      expect(received.digest, sha256.convert(bytes).toString());
      await file.delete();
      await a.retry(a.messages.single);
      expect(a.messages.single.status, 'sent');
      expect(b.messages, hasLength(1));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1sAAAAASUVORK5CYII=',
      );
      final image = await File('${temporary.path}/图片.png').writeAsBytes(png);
      await a.sendFile(peer, image);
      expect(b.messages.last.kind, 'image');
      expect(await File(b.messages.last.path!).readAsBytes(), png);
      await b.sendFile(b.peers[a.id]!, image);
      expect(a.messages.last.outgoing, isFalse);
      expect(a.messages.last.status, 'sent');
      expect(await File(a.messages.last.path!).readAsBytes(), png);
    },
  );

  test('certificate pinning rejects a changed device certificate', () async {
    final peer = await connect();
    a.peers[peer.id] = Peer.fromJson({
      ...peer.toJson(),
      'fingerprint': '0' * 64,
    });
    await a.sendText(a.peers[peer.id]!, [
      {'insert': '不可泄露\n'},
    ]);
    expect(a.messages.single.status, 'failed');
    expect(b.messages, isEmpty);
  });

  test(
    'unauthenticated traffic and malformed documents are rejected',
    () async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      addTearDown(() => client.close(force: true));
      final unauthorized = await post(client, '/v1/message', {});
      expect(unauthorized.statusCode, HttpStatus.unauthorized);
      await unauthorized.drain<void>();
      final peer = await connect();
      final invalid = await post(client, '/v1/message', {
        'id': newId(),
        'kind': 'text',
        'delta': [
          {
            'insert': {'image': 'file:///private'},
          },
        ],
      }, token: peer.token);
      expect(invalid.statusCode, HttpStatus.badRequest);
      await invalid.drain<void>();
      expect(b.messages, isEmpty);
    },
  );

  test('failed file integrity checks remove partial files', () async {
    final peer = await connect();
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(
      Uri.parse('https://127.0.0.1:${b.port}/v1/file'),
    );
    request.headers.set('Authorization', 'Bearer ${peer.token}');
    request.headers.set(
      'X-Chat-Metadata',
      base64Url.encode(
        utf8.encode(
          jsonEncode({
            'id': newId(),
            'kind': 'file',
            'name': '../../unsafe.txt',
            'size': 3,
            'digest': '0' * 64,
          }),
        ),
      ),
    );
    request.contentLength = 3;
    request.add([1, 2, 3]);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.badRequest);
    await response.drain<void>();
    expect(b.messages.single.status, 'failed');
    expect(b.messages.single.path, isNull);
    final partials = await b.directory
        .list(recursive: true)
        .where((entry) => entry.path.endsWith('.part'))
        .toList();
    expect(partials, isEmpty);
  });

  test('simultaneous direct connections keep both directions usable', () async {
    await Future.wait([
      a.connect('127.0.0.1', b.port),
      b.connect('127.0.0.1', a.port),
    ]);
    await Future.wait([
      a.sendText(a.peers[b.id]!, [
        {'insert': '来自 A\n'},
      ]),
      b.sendText(b.peers[a.id]!, [
        {'insert': '来自 B\n'},
      ]),
    ]);
    expect(a.messages.where((m) => m.outgoing).single.status, 'sent');
    expect(b.messages.where((m) => m.outgoing).single.status, 'sent');
    expect(a.messages.where((m) => !m.outgoing).single.plainText, '来自 B\n');
    expect(b.messages.where((m) => !m.outgoing).single.plainText, '来自 A\n');
  });

  test(
    'direct connection cannot overwrite an existing device identity',
    () async {
      final peer = await connect();
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      addTearDown(() => client.close(force: true));
      final original = b.peers[a.id]!;
      for (final changes in [
        {'fingerprint': '0' * 64},
        {'token': newId() + newId()},
      ]) {
        final response = await post(client, '/v1/connect', {
          'targetId': b.id,
          'id': a.id,
          'name': a.name,
          'port': a.port,
          'platform': Platform.operatingSystem,
          'fingerprint': a.fingerprint,
          'token': peer.inboundToken,
          ...changes,
        });
        expect(response.statusCode, HttpStatus.badRequest);
        await response.drain<void>();
        expect(b.peers[a.id], same(original));
      }
    },
  );

  test('text retry persists a message after a failed disk write', () async {
    final peer = await connect();
    final blocker = await Directory('${b.directory.path}/state.json.tmp')
        .create();
    await a.sendText(peer, [
      {'insert': '必须保存\n'},
    ]);
    expect(a.messages.single.status, 'failed');
    await blocker.delete();
    await a.retry(a.messages.single);
    expect(a.messages.single.status, 'sent');
    final directory = b.directory;
    await b.close();
    b = LanService(directory);
    await b.start(listenPort: 0, discovery: false);
    expect(b.messages.single.plainText, '必须保存\n');
  });

  test('restart marks interrupted incoming attachments as failed', () async {
    final peer = await connect();
    final file = await File('${temporary.path}/data.bin').writeAsBytes([1, 2]);
    await a.sendFile(peer, file);
    b.messages.single.status = 'receiving';
    b.messages.single.path = null;
    await b.save();
    final directory = b.directory;
    await b.close();
    b = LanService(directory);
    await b.start(listenPort: 0, discovery: false);
    expect(b.messages.single.status, 'failed');
  });

  test('document validation preserves whitespace and drops unsafe links', () {
    final delta = checkedDelta([
      {
        'insert': '  保留缩进\n\n',
        'attributes': {
          'bold': true,
          'link': 'javascript:alert(1)',
          'unknown': 7,
        },
      },
    ]);
    expect(delta.single['insert'], '  保留缩进\n\n');
    expect(delta.single['attributes'], {'bold': true});
    expect(
      () => checkedDelta([
        {'insert': 'missing newline'},
      ]),
      throwsFormatException,
    );
  });
}
