// lib/widgets/theme_bg.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/theme_controller.dart';

// Conditional helper so web builds don't import dart:io
import '../widgets/theme_bg_stub.dart' if (dart.library.io) 'theme_bg_io.dart';

class ThemeBg extends StatelessWidget {
  final ThemeController controller;
  final Widget child;

  const ThemeBg({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller, // <- rebuild when theme changes
      builder: (_, __) {
        final fit = controller.wallpaperFit;
        final dim = controller.wallpaperDim;

        Image? img;
        if (kIsWeb) {
          final bytes = controller.wallpaperBytes;
          if (bytes != null && bytes.isNotEmpty) {
            img = Image.memory(
              bytes,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            );
          }
        } else {
          // implemented in theme_bg_io.dart (only on mobile/desktop)
          img = buildWallpaperFromPath(controller.wallpaperPath, fit);
        }

        if (img == null) return child;

        return Stack(
          fit: StackFit.expand,
          children: [
            img,
            Container(color: Colors.black.withOpacity(dim)), // dim overlay
            child,
          ],
        );
      },
    );
  }
}
