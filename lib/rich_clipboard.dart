import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:super_clipboard/super_clipboard.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'models.dart';

String richTextHtml(List<dynamic> delta) => QuillDeltaToHtmlConverter(
  delta.map((op) => Map<String, dynamic>.from(op)).toList(),
  ConverterOptions.forEmail(),
).convert();

Future<void> copyRichText(ChatMessage message) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) throw UnsupportedError('系统剪贴板暂不可用');
  final item = DataWriterItem()
    ..add(Formats.plainText(message.plainText))
    ..add(Formats.htmlText(richTextHtml(message.delta!)));
  await clipboard.write([item]);
}

Future<void> copyMessage(ChatMessage message) async {
  if (message.kind == 'text') return copyRichText(message);
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) throw UnsupportedError('系统剪贴板暂不可用');
  final source = File(message.path!);
  final item = DataWriterItem();
  if (message.kind == 'image') {
    final codec = await ui.instantiateImageCodec(await source.readAsBytes());
    try {
      final frame = await codec.getNextFrame();
      try {
        final bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (bytes == null) throw StateError('无法读取图片');
        item.add(Formats.png(bytes.buffer.asUint8List()));
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } else {
    final folder = await Directory.systemTemp.createTemp('eggplant-chat-copy-');
    final name = (message.name ?? '附件').replaceAll(
      RegExp(r'[\\/:*?"<>|\x00-\x1f]'),
      '_',
    );
    final copy = await source.copy('${folder.path}/$name');
    item.add(Formats.fileUri(copy.uri));
  }
  await clipboard.write([item]);
}

Future<File?> clipboardImage(Directory directory) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();
  // Prefer rich text when an application offers both HTML and an image preview.
  if (reader.canProvide(Formats.htmlText) || !reader.canProvide(Formats.png)) {
    return null;
  }
  final result = Completer<File?>();
  reader.getFile(Formats.png, (image) async {
    try {
      final folder = Directory('${directory.path}/clipboard');
      await folder.create(recursive: true);
      final file = File('${folder.path}/${newId()}.png');
      final sink = file.openWrite();
      try {
        await sink.addStream(image.getStream());
      } finally {
        await sink.close();
      }
      result.complete(file);
    } on Object catch (error, stack) {
      result.completeError(error, stack);
    }
  }, onError: (error) => result.completeError(error));
  return result.future;
}
