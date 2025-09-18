// lib/theme/theme_bg_impl_io.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

Widget buildWallpaperFromBytes(Uint8List? bytes, BoxFit fit) {
  return bytes != null ? Image.memory(bytes, fit: fit)
                       : const SizedBox.shrink();
}

Widget buildWallpaperFromPath(String? path, BoxFit fit) {
  if (path != null && path.isNotEmpty && File(path).existsSync()) {
    return Image.file(File(path), fit: fit);
  }
  return const SizedBox.shrink();
}
