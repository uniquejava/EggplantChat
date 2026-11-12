import 'dart:async';
import 'dart:io';

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
