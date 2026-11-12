import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'chat_screen.dart';
import 'lan_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(1180, 800),
      minimumSize: const Size(820, 620),
      center: true,
      title: 'EggplantChat',
      titleBarStyle: Platform.isMacOS
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: true,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  final directory = await getApplicationSupportDirectory();
  runApp(ChatApp(directory: directory));
}

class ChatApp extends StatefulWidget {
  const ChatApp({super.key, required this.directory});
  final Directory directory;
  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  late LanService _service;
  late Future<void> _startup;
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _service = LanService(widget.directory);
    _startup = _service.start();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShadApp(
    title: 'EggplantChat',
    themeMode: _mode,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadZincColorScheme.light(),
    ),
    darkTheme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadZincColorScheme.dark(),
    ),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: const [FlutterQuillLocalizations.delegate],
    home: FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.circleAlert, size: 36),
                    const SizedBox(height: 16),
                    const Text('无法启动聊天服务'),
                    const SizedBox(height: 8),
                    SelectableText(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ShadButton.outline(
                      onPressed: () async {
                        await _service.close();
                        if (mounted) setState(_start);
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShadProgress(),
                    SizedBox(height: 16),
                    Text('正在启动局域网服务…'),
                  ],
                ),
              ),
            ),
          );
        }
        return ChatScreen(
          service: _service,
          onToggleTheme: () => setState(() {
            _mode = ShadTheme.of(context).brightness == Brightness.dark
                ? ThemeMode.light
                : ThemeMode.dark;
          }),
        );
      },
    ),
  );
}
