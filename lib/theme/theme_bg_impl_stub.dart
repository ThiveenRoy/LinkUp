// lib/theme/theme_bg_impl_stub.dart
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

Widget buildWallpaperFromBytes(Uint8List? bytes, BoxFit fit) {
  return bytes != null ? Image.memory(bytes, fit: fit)
                       : const SizedBox.shrink();
}

Widget buildWallpaperFromPath(String? path, BoxFit fit) {
  // No file paths on web; show nothing (or swap to a gradient if you prefer).
  return const SizedBox.shrink();
}
