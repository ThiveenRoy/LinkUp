// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> pickWallpaperBytesWeb() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  final c = Completer<Uint8List?>();
  input.onChange.listen((_) async {
    final f = input.files?.first;
    if (f == null) return c.complete(null);
    final reader = html.FileReader();
    reader.onError.listen((_) => c.complete(null));
    reader.onLoadEnd.listen((_) {
      final data = reader.result;
      if (data is Uint8List) return c.complete(data);
      if (data is List<int>) return c.complete(Uint8List.fromList(data));
      return c.complete(null);
    });
    reader.readAsArrayBuffer(f);
  });
  input.click();
  return c.future;
}
