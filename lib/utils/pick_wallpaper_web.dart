import 'dart:async';
import 'dart:typed_data';
import 'dart:js_util' as js;

dynamic get _win => js.globalThis;
dynamic get _doc => js.getProperty(_win, 'document');

Future<Uint8List?> pickWallpaperBytes() {
  final completer = Completer<Uint8List?>();
  final input = js.callMethod(_doc, 'createElement', ['input']);
  js.setProperty(input, 'type', 'file');
  js.setProperty(input, 'accept', 'image/*');

  void onChange(dynamic _) {
    final files = js.getProperty(input, 'files');
    final file = js.getProperty(files, '0');
    if (file == null) { completer.complete(null); return; }

    final reader = js.callConstructor(js.getProperty(_win, 'FileReader'), []);
    js.setProperty(reader, 'onloadend', js.allowInterop((dynamic __) {
      final result = js.getProperty(reader, 'result'); // ArrayBuffer
      if (result == null) { completer.complete(null); return; }

      final u8 = js.callConstructor(js.getProperty(_win, 'Uint8Array'), [result]);
      final len = (js.getProperty(u8, 'length') as num).toInt();
      final bytes = Uint8List(len);
      for (var i = 0; i < len; i++) {
        bytes[i] = (js.getProperty(u8, i) as num).toInt();
      }
      completer.complete(bytes);
    }));
    js.callMethod(reader, 'readAsArrayBuffer', [file]);
  }

  js.callMethod(input, 'addEventListener', ['change', js.allowInterop(onChange)]);
  js.callMethod(input, 'click', []);
  return completer.future;
}
