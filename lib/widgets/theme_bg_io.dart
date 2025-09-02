import 'dart:io';
import 'package:flutter/widgets.dart';

Image? buildWallpaperFromPath(String? path, BoxFit fit) {
  if (path == null || path.isEmpty) return null;
  return Image.file(
    File(path),
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    gaplessPlayback: true,
    filterQuality: FilterQuality.low,
  );
}