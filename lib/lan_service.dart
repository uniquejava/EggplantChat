import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import 'models.dart';

const lanPort = 53318;
const discoveryPort = 53319;
const _jsonLimit = 2 * 1024 * 1024;

Map<String, String> _credentials() {
  final pair = CryptoUtils.generateEcKeyPair();
  final key = pair.privateKey as ECPrivateKey;
  final csr = X509Utils.generateEccCsrPem(
    {'CN': 'EggplantChat'},
    key,
    pair.publicKey as ECPublicKey,
  );
  return {
    'key': CryptoUtils.encodeEcPrivateKeyToPem(key),
    'cert': X509Utils.generateSelfSignedCertificate(key, csr, 3650),
  };
}

class LanService {
  LanService(this.directory, {String? deviceName})
    : name = deviceName ?? Platform.localHostname;

  final Directory directory;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  final Map<String, Peer> peers = {};
  final Map<String, Peer> nearby = {};
  final List<ChatMessage> messages = [];
  final Set<String> _inflight = {};
  final Set<String> _probing = {};
  final Map<String, (int, DateTime)> _attempts = {};
  final Set<HttpClient> _clients = {};
  late String id;
  String name;
  late String fingerprint;
  final String pairingCode = (100000 + Random.secure().nextInt(900000))
      .toString();
  DateTime? pairingUntil;
  String? warning;
  List<String> addresses = [];
  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _timer;
  Future<void> _writes = Future.value();
  bool _closed = false;
  int get port => _server!.port;
  bool get pairingOpen => pairingUntil?.isAfter(DateTime.now()) ?? false;
  void notify() {
    if (!_closed) _changes.add(null);
  }

  Future<void> start({int listenPort = lanPort, bool discovery = true}) async {
    await directory.create(recursive: true);
    final stateFile = File('${directory.path}/state.json');
    if (await stateFile.exists()) {
      final json =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      id = checkedId(json, 'id');
      name = requiredString(json, 'name', max: 80);
      for (final p in json['peers'] as List) {
        final peer = Peer.fromJson(Map<String, dynamic>.from(p));
        peers[peer.id] = peer;
      }
      for (final m in json['messages'] as List) {
        final message = ChatMessage.fromJson(Map<String, dynamic>.from(m));
        if (['sending', 'receiving'].contains(message.status)) {
          message.status = 'failed';
        }
        messages.add(message);
      }
    } else {
      id = newId();
    }
    final certFile = File('${directory.path}/certificate.pem');
    final keyFile = File('${directory.path}/private-key.pem');
    if (!await certFile.exists() || !await keyFile.exists()) {
      if (peers.isNotEmpty) throw StateError('设备证书缺失，请恢复应用数据后重试');
      final credentials = await Isolate.run(_credentials);
      await keyFile.writeAsString(credentials['key']!, flush: true);
      await certFile.writeAsString(credentials['cert']!, flush: true);
    }
    final pem = await certFile.readAsString();
    fingerprint = sha256
        .convert(CryptoUtils.getBytesFromPEMString(pem))
        .toString();
    final security = SecurityContext()
      ..useCertificateChain(certFile.path)
      ..usePrivateKey(keyFile.path);
    _server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      listenPort,
      security,
    );
    _server!.idleTimeout = const Duration(seconds: 30);
    _server!.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object error) {
        warning = '接收服务异常：$error';
        notify();
      },
    );
    await save();
    await _refreshAddresses();
    if (discovery) {
      try {
        _udp = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
          reusePort: !Platform.isWindows,
        );
        _udp!.broadcastEnabled = true;
        _udp!.multicastHops = 1;
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        for (final interface in interfaces) {
          try {
            _udp!.joinMulticast(InternetAddress('239.255.42.99'), interface);
          } on SocketException {
            /* Some virtual interfaces have no multicast route. */
          }
        }
        _udp!.listen(
          (event) {
            if (event == RawSocketEvent.read) _receiveDiscovery();
          },
          onError: (Object error) {
            warning = '自动发现暂不可用，请检查本地网络权限，或通过 IP 连接';
            notify();
          },
        );
      } on SocketException {
        warning = '自动发现不可用，请通过 IP 连接';
      }
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 6), (_) => _tick());
    }
    notify();
  }

  Future<void> save() {
    final data = jsonEncode({
      'id': id,
      'name': name,
      'peers': peers.values.map((p) => p.toJson()).toList(),
      'messages': messages.map((m) => m.toJson()).toList(),
    });
    final write = _writes.then((_) async {
      final target = File('${directory.path}/state.json');
      final temp = File('${directory.path}/state.json.tmp');
      await temp.writeAsString(data, flush: true);
      await temp.rename(target.path);
    });
    _writes = write.catchError((Object error) {
      warning = '聊天记录保存失败：$error';
      notify();
    });
    return write;
  }

  Future<void> _refreshAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    addresses = interfaces
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .toList();
  }

  void _tick() {
    unawaited(_refreshAddresses().catchError((Object _) {}));
    final bytes = utf8.encode(
      jsonEncode({
        'app': 'eggplant-chat',
        'v': 1,
        'id': id,
        'name': name,
        'port': port,
        'platform': Platform.operatingSystem,
      }),
    );
    for (final address in ['239.255.42.99', '255.255.255.255']) {
      try {
        _udp?.send(bytes, InternetAddress(address), discoveryPort);
      } on SocketException {
        /* Manual IP connection remains available. */
      }
    }
    for (final peer in peers.values.toList()) {
      unawaited(_probe(peer, nearby[peer.id] ?? peer));
    }
    notify();
  }

  void _receiveDiscovery() {
    Datagram? datagram;
    while ((datagram = _udp?.receive()) != null) {
      try {
        if (datagram!.data.length > 2048) continue;
        final json =
            jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
        if (json['app'] != 'eggplant-chat' || json['v'] != 1) continue;
        final remoteId = checkedId(json, 'id');
        if (remoteId == id) continue;
        final peer = Peer(
          id: remoteId,
          name: requiredString(json, 'name', max: 80),
          host: datagram.address.address,
          port: checkedPort(json['port']),
          platform: requiredString(json, 'platform', max: 32),
        )..lastSeen = DateTime.now();
        nearby[remoteId] = peer;
        notify();
      } on Object {
        /* Ignore malformed, unauthenticated discovery packets. */
      }
    }
  }

  HttpClient _client({String? pin}) {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = ((_) => 'DIRECT')
      ..badCertificateCallback = (cert, host, port) =>
          pin == null || sha256.convert(cert.der).toString() == pin;
    _clients.add(client);
    return client;
  }

  Future<Map<String, dynamic>> _readJson(Stream<List<int>> body) async {
    final bytes = <int>[];
    await for (final chunk in body.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > _jsonLimit) {
        throw const FormatException('请求内容过大');
      }
      bytes.addAll(chunk);
    }
    final result = jsonDecode(utf8.decode(bytes));
    if (result is! Map<String, dynamic>) throw const FormatException('无效的请求');
    return result;
  }

  Future<Map<String, dynamic>> _post(
    String host,
    int port,
    String path,
    Map<String, dynamic> body, {
    String? pin,
    String? token,
    void Function(X509Certificate)? onCertificate,
  }) async {
    final client = _client(pin: pin);
    try {
      final request = await client.postUrl(
        Uri(scheme: 'https', host: host, port: port, path: path),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (onCertificate != null) {
        final certificate = response.certificate;
        if (certificate == null) throw const HandshakeException('设备未提供证书');
        onCertificate(certificate);
      }
      final json = await _readJson(response);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(json['error'] as String? ?? '连接失败');
      }
      return json;
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  Future<void> _probe(Peer peer, Peer candidate) async {
    if (!_probing.add(peer.id)) return;
    try {
      final json = await _post(
        candidate.host,
        candidate.port,
        '/v1/ping',
        {},
        pin: peer.fingerprint,
        token: peer.token,
      );
      if (json['id'] == peer.id) {
        peer.host = candidate.host;
        peer.port = candidate.port;
        peer.lastSeen = DateTime.now();
        notify();
      }
    } on Object {
      /* Presence expires; sending still retries the actual connection. */
    } finally {
      _probing.remove(peer.id);
    }
  }

  Future<Peer> pair(
    String host,
    int remotePort,
    String code, {
    String? expectedId,
  }) async {
    if (InternetAddress.tryParse(host) == null) {
      throw const FormatException('请输入对方的 IPv4 地址');
    }
    checkedPort(remotePort);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException('请输入六位配对码');
    }
    final inboundToken = newId() + newId();
    String? remoteFingerprint;
    // First pairing trusts the LAN endpoint; subsequent connections pin its certificate.
    final json = await _post(
      host,
      remotePort,
      '/v1/pair',
      {
        'code': code,
        'id': id,
        'name': name,
        'port': port,
        'platform': Platform.operatingSystem,
        'fingerprint': fingerprint,
        'token': inboundToken,
      },
      onCertificate: (cert) =>
          remoteFingerprint = sha256.convert(cert.der).toString(),
    );
    final peer = Peer.fromJson({
      ...json,
      'host': host,
      'port': remotePort,
      'fingerprint': remoteFingerprint,
      'inboundToken': inboundToken,
    });
    if (peer.id == id || expectedId != null && peer.id != expectedId) {
      throw const FormatException('对方的设备身份不匹配');
    }
    peer.lastSeen = DateTime.now();
    peers[peer.id] = peer;
    await save();
    notify();
    return peer;
  }

  Future<void> _reply(
    HttpRequest request,
    int status,
    Map<String, dynamic> json,
  ) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(json));
    await request.response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'POST') {
        await _reply(request, 405, {'error': '不支持的请求'});
        return;
      }
      if (request.uri.path == '/v1/pair') {
        final host = request.connectionInfo!.remoteAddress.address;
        final attempts = _attempts[host];
        final now = DateTime.now();
        final count =
            attempts != null && now.difference(attempts.$2).inMinutes < 1
            ? attempts.$1
            : 0;
        if (!pairingOpen || count >= 5) {
          await _reply(request, 403, {'error': '请在对方打开配对窗口，或一分钟后重试'});
          return;
        }
        // Reserve the attempt before reading a potentially delayed request body.
        _attempts[host] = (count + 1, now);
        final json = await _readJson(request);
        if (!pairingOpen || json['code'] != pairingCode) {
          await _reply(request, 403, {'error': '配对码错误'});
          return;
        }
        final remoteId = checkedId(json, 'id');
        if (remoteId == id) throw const FormatException('不能与自己配对');
        final token = newId() + newId();
        final peer = Peer.fromJson({
          ...json,
          'host': host,
          'inboundToken': token,
        })..lastSeen = now;
        peers[peer.id] = peer;
        await save();
        notify();
        await _reply(request, 200, {
          'id': id,
          'name': name,
          'platform': Platform.operatingSystem,
          'token': token,
        });
        return;
      }
      final authorization = request.headers.value('Authorization');
      final peer = peers.values
          .where((p) => authorization == 'Bearer ${p.inboundToken}')
          .firstOrNull;
      if (peer == null) {
        await _reply(request, 401, {'error': '请先配对设备'});
        return;
      }
      peer.lastSeen = DateTime.now();
      if (request.uri.path == '/v1/ping') {
        await _reply(request, 200, {'id': id});
        return;
      }
      if (request.uri.path == '/v1/message') {
        final json = await _readJson(request);
        final message = ChatMessage.fromJson({
          ...json,
          'peerId': peer.id,
          'outgoing': false,
          'path': null,
          'status': 'sent',
          'time': DateTime.now().toIso8601String(),
        });
        if (message.kind != 'text') throw const FormatException('请使用附件接口');
        if (!messages.any(
          (m) => !m.outgoing && m.id == message.id && m.peerId == peer.id,
        )) {
          messages.add(message);
        }
        // A previous attempt may have reached memory but failed to reach disk.
        await save();
        notify();
        await _reply(request, 200, {'ok': true});
        return;
      }
      if (request.uri.path == '/v1/file') {
        await _receiveFile(request, peer);
        return;
      }
      await _reply(request, 404, {'error': '接口不存在'});
    } on Object catch (error) {
      try {
        await _reply(request, error is FormatException ? 400 : 500, {
          'error': error is FormatException ? error.message : '接收失败，请检查磁盘空间后重试',
        });
      } on Object {
        /* The sender may have disconnected mid-transfer. */
      }
    }
  }

  Future<void> _receiveFile(HttpRequest request, Peer peer) async {
    final header = request.headers.value('X-Chat-Metadata');
    if (header == null || header.length > 8192) {
      throw const FormatException('附件元数据无效');
    }
    final json = jsonDecode(
      utf8.decode(base64Url.decode(header)),
    ) as Map<String, dynamic>;
    final message = ChatMessage.fromJson({
      ...json,
      'peerId': peer.id,
      'outgoing': false,
      'path': null,
      'status': 'receiving',
      'time': DateTime.now().toIso8601String(),
    });
    if (message.kind == 'text' || request.contentLength != message.size) {
      throw const FormatException('附件长度不匹配');
    }
    final transferKey = '${peer.id}/${message.id}';
    if (!_inflight.add(transferKey)) throw const FormatException('附件正在接收');
    File? partial;
    try {
      final existing = messages
          .where(
            (m) =>
                !m.outgoing &&
                m.peerId == peer.id &&
                m.id == message.id &&
                m.status == 'sent',
          )
          .firstOrNull;
      if (existing != null) {
        await request.drain<void>();
        await _reply(request, 200, {'ok': true});
        return;
      }
      final folder = Directory(
        '${directory.path}/received/${peer.id}/${message.id}',
      );
      await folder.create(recursive: true);
      partial = File('${folder.path}/content.part');
      final output = partial.openWrite();
      var received = 0;
      var update = DateTime.now();
      messages.removeWhere(
        (m) => !m.outgoing && m.peerId == peer.id && m.id == message.id,
      );
      messages.add(message);
      notify();
      try {
        await for (final chunk in request.timeout(
          const Duration(seconds: 30),
        )) {
          received += chunk.length;
          if (received > message.size) throw const FormatException('附件超过声明的长度');
          output.add(chunk);
          await output.flush();
          message.progress = message.size == 0 ? 1 : received / message.size;
          if (DateTime.now().difference(update).inMilliseconds > 100) {
            notify();
            update = DateTime.now();
          }
        }
      } finally {
        await output.close();
      }
      if (received != message.size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              message.digest) {
        throw const FormatException('附件校验失败，请重新发送');
      }
      final file = await partial.rename('${folder.path}/content');
      message.path = file.path;
      message.status = 'sent';
      message.progress = 1;
      await save();
      notify();
      await _reply(request, 200, {'ok': true});
    } on Object {
      message.status = 'failed';
      message.error = '接收中断，请让对方重试';
      if (partial != null && await partial.exists()) await partial.delete();
      notify();
      rethrow;
    } finally {
      _inflight.remove(transferKey);
    }
  }

  Future<void> sendText(Peer peer, List<dynamic> delta) async {
    final message = ChatMessage(
      id: newId(),
      peerId: peer.id,
      outgoing: true,
      kind: 'text',
      time: DateTime.now(),
      delta: checkedDelta(delta),
      status: 'sending',
    );
    messages.add(message);
    await save();
    notify();
    await retry(message);
  }

  Future<void> sendFile(Peer peer, File file) async {
    if (await file.length() > 10 * 1024 * 1024 * 1024) {
      throw const FormatException('单个附件最大为 10 GB');
    }
    final name = file.uri.pathSegments.last;
    final messageId = newId();
    final folder = Directory('${directory.path}/sent/$messageId');
    await folder.create(recursive: true);
    final snapshot = await file.copy('${folder.path}/content');
    final size = await snapshot.length();
    final image = RegExp(
      r'\.(png|jpe?g|gif|webp|bmp)$',
      caseSensitive: false,
    ).hasMatch(name);
    final message = ChatMessage(
      id: messageId,
      peerId: peer.id,
      outgoing: true,
      kind: image ? 'image' : 'file',
      time: DateTime.now(),
      name: name,
      size: size,
      digest: (await sha256.bind(snapshot.openRead()).first).toString(),
      path: snapshot.path,
      status: 'sending',
    );
    messages.add(message);
    await save();
    notify();
    await retry(message);
  }

  Future<void> retry(ChatMessage message) async {
    if (!message.outgoing || !_inflight.add('send/${message.id}')) return;
    final peer = peers[message.peerId]!;
    message.status = 'sending';
    message.error = null;
    message.progress = 0;
    notify();
    try {
      if (message.kind == 'text') {
        await _post(
          peer.host,
          peer.port,
          '/v1/message',
          message.toJson(),
          pin: peer.fingerprint,
          token: peer.token,
        );
      } else {
        final file = File(message.path!);
        if (await file.length() != message.size ||
            (await sha256.bind(file.openRead()).first).toString() !=
                message.digest) {
          throw const FileSystemException('原文件已改变，请重新选择');
        }
        final client = _client(pin: peer.fingerprint);
        try {
          final request = await client.postUrl(
            Uri(
              scheme: 'https',
              host: peer.host,
              port: peer.port,
              path: '/v1/file',
            ),
          );
          request.followRedirects = false;
          request.headers.set('Authorization', 'Bearer ${peer.token}');
          request.headers.set(
            'X-Chat-Metadata',
            base64Url.encode(
              utf8.encode(
                jsonEncode(
                  message.toJson()
                    ..remove('path')
                    ..remove('delta'),
                ),
              ),
            ),
          );
          request.contentLength = message.size;
          var sent = 0;
          var update = DateTime.now();
          await request
              .addStream(
                file.openRead().map((chunk) {
                  sent += chunk.length;
                  message.progress = message.size == 0
                      ? 1
                      : sent / message.size;
                  if (DateTime.now().difference(update).inMilliseconds > 100) {
                    notify();
                    update = DateTime.now();
                  }
                  return chunk;
                }),
              )
              .timeout(const Duration(minutes: 30));
          final response = await request.close().timeout(
            const Duration(minutes: 5),
          );
          final json = await _readJson(response);
          if (response.statusCode != 200) {
            throw HttpException(json['error'] as String? ?? '附件发送失败');
          }
        } finally {
          client.close(force: true);
          _clients.remove(client);
        }
      }
      message.status = 'sent';
      message.progress = 1;
      peer.lastSeen = DateTime.now();
    } on Object catch (error) {
      message.status = 'failed';
      message.error = '发送失败：$error';
    } finally {
      _inflight.remove('send/${message.id}');
      await save();
      notify();
    }
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _udp?.close();
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    await _server?.close(force: true);
    await _writes;
    await _changes.close();
  }
}
