import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'theme_controller.dart';

class ThemeBg extends StatelessWidget {
  final ThemeController controller;
  final Widget child;

  const ThemeBg({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    final fit = controller.wallpaperFit;
    final dim = controller.wallpaperDim;

    ImageProvider? provider;

    if (kIsWeb) {
      final bytes = controller.wallpaperBytes;
      if (bytes != null && bytes.isNotEmpty) {
        provider = MemoryImage(bytes);
      }
    } else {
      final path = controller.wallpaperPath;
      if (path != null && path.isNotEmpty) {
        provider = FileImage(File(path));
      }
    }

    if (provider == null) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(image: provider, fit: fit),
        Container(color: Colors.black.withOpacity(dim)),
        child,
      ],
    );
  }
}
