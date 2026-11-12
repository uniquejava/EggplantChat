import 'dart:convert';
import 'dart:math';

String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String requiredString(Map<String, dynamic> json, String key, {int max = 256}) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > max) {
    throw FormatException('无效的 $key');
  }
  return value;
}

String checkedId(Map<String, dynamic> json, String key) {
  final value = requiredString(json, key);
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
    throw FormatException('无效的 $key');
  }
  return value;
}

int checkedPort(dynamic value) {
  if (value is! int || value < 1 || value > 65535) {
    throw const FormatException('端口必须在 1–65535 之间');
  }
  return value;
}

String checkedFingerprint(dynamic value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('无效的设备证书');
  }
  return value;
}

/// Keep only text operations and supported Quill attributes at the network boundary.
List<dynamic> checkedDelta(dynamic value) {
  if (value is! List ||
      value.isEmpty ||
      value.length > 20000 ||
      utf8.encode(jsonEncode(value)).length > 1024 * 1024) {
    throw const FormatException('消息过大或格式无效');
  }
  const booleans = {
    'bold',
    'italic',
    'underline',
    'strike',
    'code',
    'blockquote',
    'code-block',
  };
  final result = <dynamic>[];
  for (final item in value) {
    if (item is! Map ||
        item['insert'] is! String ||
        (item['insert'] as String).isEmpty) {
      throw const FormatException('请通过图片或附件按钮发送嵌入内容');
    }
    final attrs = <String, dynamic>{};
    final raw = item['attributes'];
    if (raw != null && raw is! Map) {
      throw const FormatException('无效的文本样式');
    }
    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = entry.key;
        final v = entry.value;
        if (booleans.contains(k) && v is bool ||
            k == 'header' && v is int && v >= 1 && v <= 6 ||
            k == 'indent' && v is int && v >= 0 && v <= 8 ||
            k == 'list' &&
                ['bullet', 'ordered', 'checked', 'unchecked'].contains(v) ||
            k == 'align' &&
                ['left', 'center', 'right', 'justify'].contains(v) ||
            k == 'direction' && v == 'rtl' ||
            k == 'script' && ['sub', 'super'].contains(v) ||
            ['color', 'background'].contains(k) &&
                v is String &&
                RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(v) ||
            k == 'size' &&
                v is String &&
                (['small', 'large', 'huge'].contains(v) ||
                    RegExp(r'^(?:[89]|[1-6]\d|7[0-2])$').hasMatch(v))) {
          attrs[k as String] = v;
        } else if (k == 'link' && v is String && v.length <= 2048) {
          final uri = Uri.tryParse(v);
          if (uri != null && ['https', 'http', 'mailto'].contains(uri.scheme)) {
            attrs['link'] = v;
          }
        }
      }
    }
    result.add({
      'insert': item['insert'],
      if (attrs.isNotEmpty) 'attributes': attrs,
    });
  }
  if (!(result.last['insert'] as String).endsWith('\n')) {
    throw const FormatException('文本缺少结尾换行');
  }
  return result;
}

class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.platform,
    this.fingerprint = '',
    this.token = '',
    this.inboundToken = '',
  });

  final String id;
  String name;
  String host;
  int port;
  final String platform;
  final String fingerprint;
  final String token;
  final String inboundToken;
  DateTime? lastSeen;
  bool get online =>
      lastSeen != null &&
      DateTime.now().difference(lastSeen!) < const Duration(seconds: 24);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'platform': platform,
    'fingerprint': fingerprint,
    'token': token,
    'inboundToken': inboundToken,
  };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    id: checkedId(json, 'id'),
    name: requiredString(json, 'name', max: 80),
    host: requiredString(json, 'host'),
    port: checkedPort(json['port']),
    platform: requiredString(json, 'platform', max: 32),
    fingerprint: checkedFingerprint(json['fingerprint']),
    token: requiredString(json, 'token', max: 128),
    inboundToken: requiredString(json, 'inboundToken', max: 128),
  );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.peerId,
    required this.outgoing,
    required this.kind,
    required this.time,
    this.delta,
    this.name,
    this.size = 0,
    this.digest,
    this.path,
    this.status = 'sent',
  });

  final String id;
  final String peerId;
  final bool outgoing;
  final String kind;
  final DateTime time;
  final List<dynamic>? delta;
  final String? name;
  final int size;
  final String? digest;
  String? path;
  String status;
  String? error;
  double progress = 0;
  String get plainText =>
      delta?.map((op) => op['insert'] as String).join() ?? '';
  String get preview => kind == 'text'
      ? plainText.trim()
      : '${kind == 'image' ? '[图片]' : '[附件]'} ${name ?? ''}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'peerId': peerId,
    'outgoing': outgoing,
    'kind': kind,
    'time': time.toIso8601String(),
    'delta': delta,
    'name': name,
    'size': size,
    'digest': digest,
    'path': path,
    'status': status,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final kind = requiredString(json, 'kind');
    if (!['text', 'file', 'image'].contains(kind)) {
      throw const FormatException('不支持的消息类型');
    }
    final size = json['size'] ?? 0;
    if (size is! int || size < 0 || size > 10 * 1024 * 1024 * 1024) {
      throw const FormatException('单个附件最大为 10 GB');
    }
    return ChatMessage(
      id: checkedId(json, 'id'),
      peerId: checkedId(json, 'peerId'),
      outgoing: json['outgoing'] == true,
      kind: kind,
      time: DateTime.parse(requiredString(json, 'time')),
      delta: kind == 'text' ? checkedDelta(json['delta']) : null,
      name: kind == 'text' ? null : requiredString(json, 'name', max: 255),
      size: size,
      digest: kind == 'text' ? null : checkedFingerprint(json['digest']),
      path: json['path'] as String?,
      status: json['status'] as String? ?? 'sent',
    );
  }
}

String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
