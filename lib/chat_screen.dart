import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_theme.dart';
import 'chat_composer.dart';
import 'lan_service.dart';
import 'message_bubble.dart';
import 'models.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.service,
    required this.onToggleTheme,
  });
  final LanService service;
  final VoidCallback onToggleTheme;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  final _drafts = <String, List<dynamic>>{};
  final _draftFiles = <String, List<File>>{};
  final _unread = <String, int>{};
  late StreamSubscription<void> _subscription;
  String? _selected;
  String? _notice;
  String _query = '';
  int _messageCount = 0;
  LanService get service => widget.service;

  @override
  void initState() {
    super.initState();
    _selected = service.peers.keys.firstOrNull;
    _messageCount = service.messages.length;
    _subscription = service.changes.listen((_) {
      if (!mounted) return;
      for (final message in service.messages.skip(_messageCount)) {
        if (!message.outgoing && message.peerId != _selected) {
          _unread.update(message.peerId, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      final added = service.messages.length > _messageCount;
      _messageCount = service.messages.length;
      setState(() {
        _selected ??= service.peers.keys.firstOrNull;
      });
      if (added && _scroll.hasClients && _scroll.offset < 120) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  void _error(String error) {
    if (mounted) setState(() => _notice = error);
  }

  void _select(String id) {
    setState(() {
      _selected = id;
      _unread.remove(id);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _subscription.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Widget _icon(String label, IconData icon, VoidCallback onPressed) =>
      ShadTooltip(
        builder: (_) => Text(label),
        child: Semantics(
          label: label,
          child: ShadIconButton.ghost(
            icon: Icon(icon, size: 19),
            width: 40,
            height: 40,
            onPressed: onPressed,
          ),
        ),
      );

  Future<void> _pair({Peer? candidate}) async {
    service.pairingUntil = DateTime.now().add(const Duration(minutes: 5));
    final host = TextEditingController(text: candidate?.host ?? '');
    final port = TextEditingController(text: '${candidate?.port ?? lanPort}');
    final code = TextEditingController();
    var busy = false;
    String? error;
    await showShadDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => ShadDialog(
          title: const Text('连接设备'),
          description: const Text('两台电脑都打开此窗口，然后在一台电脑上输入对方的配对码。'),
          constraints: const BoxConstraints(maxWidth: 460),
          actions: [
            ShadButton.outline(
              enabled: !busy,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
            ShadButton(
              enabled: !busy,
              leading: const Icon(LucideIcons.link, size: 15),
              onPressed: () async {
                update(() {
                  busy = true;
                  error = null;
                });
                try {
                  final peer = await service.pair(
                    host.text.trim(),
                    int.tryParse(port.text.trim()) ?? 0,
                    code.text.trim(),
                    expectedId: candidate?.id,
                  );
                  if (mounted) _select(peer.id);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } on Object catch (e) {
                  if (context.mounted) {
                    update(() {
                      error = '$e';
                      busy = false;
                    });
                  }
                }
              },
              child: Text(busy ? '连接中…' : '连接'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: ShadTheme.of(context).colorScheme.muted,
                  borderRadius: AppTheme.radius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本机配对码 · 5 分钟内有效',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      service.pairingCode,
                      style: const TextStyle(
                        fontSize: 30,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      service.addresses
                          .map((ip) => '$ip:${service.port}')
                          .join('\n'),
                      style: TextStyle(
                        fontSize: 12,
                        color: ShadTheme.of(context)
                            .colorScheme
                            .mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('对方 IP 地址', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: host,
                      placeholder: const Text('192.168.1.20'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: ShadInput(
                      controller: port,
                      placeholder: const Text('端口'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('对方配对码', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              ShadInput(
                controller: code,
                placeholder: const Text('六位数字'),
                maxLength: 6,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: ShadTheme.of(context).colorScheme.destructive,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '配对后，此设备可以向你发送消息和附件。',
                style: TextStyle(
                  fontSize: 11,
                  color: ShadTheme.of(context).colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    service.pairingUntil = null;
    // Dialog exit animations may still reference its text controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    host.dispose();
    port.dispose();
    code.dispose();
  }

  Future<void> _settings() async {
    final name = TextEditingController(text: service.name);
    await showShadDialog<void>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('本机设置'),
        constraints: const BoxConstraints(maxWidth: 460),
        actions: [
          ShadButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              service.name = name.text.trim();
              try {
                await service.save();
                service.notify();
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } on Object catch (error) {
                _error('设置保存失败：$error');
              }
            },
            child: const Text('保存'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('设备名称'),
            const SizedBox(height: 8),
            ShadInput(controller: name, maxLength: 80),
            const SizedBox(height: 20),
            const Text('局域网地址'),
            const SizedBox(height: 8),
            SelectableText(
              service.addresses.map((ip) => '$ip:${service.port}').join('\n'),
            ),
            const SizedBox(height: 20),
            const Text('聊天记录与附件位置'),
            const SizedBox(height: 8),
            SelectableText(
              service.directory.path,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
  }

  Widget _avatar(Peer peer, {double size = 42}) {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Icon(
        peer.platform == 'macos' ? LucideIcons.laptop : LucideIcons.monitor,
        size: size * .46,
        color: colors.foreground,
      ),
    );
  }

  Widget _rail() {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      width: AppTheme.railWidth,
      color: colors.muted,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              LucideIcons.messagesSquare,
              color: colors.primaryForeground,
              size: 21,
            ),
          ),
          const SizedBox(height: 28),
          ShadTooltip(
            builder: (_) => const Text('会话'),
            child: ShadIconButton.secondary(
              icon: const Icon(LucideIcons.messageSquare, size: 21),
              onPressed: () {},
              width: 42,
              height: 42,
            ),
          ),
          const SizedBox(height: 10),
          _icon('连接设备', LucideIcons.plus, _pair),
          const Spacer(),
          _icon(
            '切换明暗主题',
            ShadTheme.of(context).brightness == Brightness.dark
                ? LucideIcons.sun
                : LucideIcons.moon,
            widget.onToggleTheme,
          ),
          const SizedBox(height: 4),
          _icon('本机设置', LucideIcons.settings, _settings),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _sidebar() {
    final colors = ShadTheme.of(context).colorScheme;
    final peers =
        service.peers.values
            .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
            .toList()
          ..sort((a, b) {
            final at = service.messages
                .where((m) => m.peerId == a.id)
                .lastOrNull
                ?.time;
            final bt = service.messages
                .where((m) => m.peerId == b.id)
                .lastOrNull
                ?.time;
            return (bt ?? DateTime(2000)).compareTo(at ?? DateTime(2000));
          });
    final nearby = service.nearby.values
        .where(
          (p) =>
              !service.peers.containsKey(p.id) &&
              p.online &&
              p.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return Container(
      width: AppTheme.sidebarWidth,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 14, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '消息',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                _icon('连接设备', LucideIcons.plus, _pair),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: ShadInput(
              leading: Icon(
                LucideIcons.search,
                size: 15,
                color: colors.mutedForeground,
              ),
              placeholder: const Text('搜索设备'),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                if (peers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 28),
                    child: Text(
                      _query.isEmpty ? '暂无会话\n连接一台设备后开始聊天' : '没有匹配的设备',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.8,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
                for (final peer in peers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ShadButton.ghost(
                      height: 80,
                      expands: true,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      backgroundColor: _selected == peer.id
                          ? colors.muted
                          : null,
                      onPressed: () => _select(peer.id),
                      child: Row(
                        children: [
                          _avatar(peer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        peer.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if ((_unread[peer.id] ?? 0) > 0)
                                      ShadBadge(
                                        child: Text('${_unread[peer.id]}'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  service.messages
                                          .where((m) => m.peerId == peer.id)
                                          .lastOrNull
                                          ?.preview ??
                                      (peer.online ? '已连接，可以发送消息' : '等待设备上线'),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.normal,
                                    color: colors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 24, 8, 10),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.wifi,
                        size: 13,
                        color: colors.mutedForeground,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '附近设备',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.mutedForeground,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${nearby.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final peer in nearby)
                  ShadButton.ghost(
                    height: 64,
                    expands: true,
                    onPressed: () => _pair(candidate: peer),
                    child: Row(
                      children: [
                        _avatar(peer, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                peer.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                peer.host,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          LucideIcons.plus,
                          size: 14,
                          color: colors.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                if (nearby.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Text(
                      '正在查找同一网络中的设备…',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.foreground,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                ShadTooltip(
                  builder: (_) => const Text('本机服务已启动'),
                  child: Icon(
                    LucideIcons.shieldCheck,
                    size: 14,
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final colors = ShadTheme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.background,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                LucideIcons.messagesSquare,
                size: 34,
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '连接你的另一台电脑',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              '在两台电脑上打开 EggplantChat，连接后发送文字、图片和附件。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 24),
            ShadButton(
              onPressed: _pair,
              leading: const Icon(LucideIcons.plus, size: 16),
              child: const Text('连接设备'),
            ),
            const SizedBox(height: 18),
            Text(
              'macOS  ·  Windows',
              style: TextStyle(fontSize: 11, color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversation(Peer peer) {
    final colors = ShadTheme.of(context).colorScheme;
    final messages = service.messages
        .where((m) => m.peerId == peer.id)
        .toList()
        .reversed
        .toList();
    return Column(
      children: [
        Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: colors.background,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              _avatar(peer, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      peer.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${peer.online ? '在线' : '离线'} · ${peer.host}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              ShadBadge.outline(child: const Text('已配对')),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    '发送第一条消息',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.mutedForeground,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final previous = index + 1 < messages.length
                        ? messages[index + 1]
                        : null;
                    return Column(
                      children: [
                        if (previous == null ||
                            message.time.difference(previous.time).inMinutes >=
                                10)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              '${message.time.month}月${message.time.day}日  '
                              '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.mutedForeground,
                              ),
                            ),
                          ),
                        MessageBubble(
                          key: ValueKey('${message.outgoing}/${message.id}'),
                          message: message,
                          onRetry: () async {
                            try {
                              await service.retry(message);
                            } on Object catch (error) {
                              _error('$error');
                            }
                          },
                          onError: _error,
                        ),
                      ],
                    );
                  },
                ),
        ),
        ChatComposer(
          key: ValueKey(peer.id),
          directory: service.directory,
          initialDelta: _drafts[peer.id],
          initialFiles: _draftFiles[peer.id] ?? [],
          onDraftChanged: (delta, files) {
            _drafts[peer.id] = delta;
            _draftFiles[peer.id] = files;
          },
          onError: _error,
          onSend: (delta, files) async {
            if (delta.any(
              (op) => (op['insert'] as String? ?? '').trim().isNotEmpty,
            )) {
              await service.sendText(peer, delta);
            }
            for (final file in files) {
              await service.sendFile(peer, file);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final peer = service.peers[_selected];
    final notice = _notice ?? service.warning;
    return Scaffold(
      backgroundColor: colors.muted.withValues(alpha: .4),
      body: Row(
        children: [
          _rail(),
          _sidebar(),
          Expanded(
            child: Column(
              children: [
                if (notice != null)
                  Container(
                    color: colors.muted,
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.circleAlert,
                          size: 15,
                          color: colors.destructive,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            notice,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        ShadIconButton.ghost(
                          icon: const Icon(LucideIcons.x, size: 14),
                          width: 28,
                          height: 28,
                          onPressed: () => setState(() {
                            _notice = null;
                            service.warning = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: peer == null ? _empty() : _conversation(peer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
