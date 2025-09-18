// lib/theme/theme_bg.dart
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

// Choose IO (Android/iOS/desktop) or stub (web) at build time.
import 'theme_bg_impl_stub.dart'
  if (dart.library.io) 'theme_bg_impl_io.dart' as impl;

// --- function APIs (existing calls keep working) ---
Widget buildWallpaperFromPath(String? path, BoxFit fit) =>
    impl.buildWallpaperFromPath(path, fit);

Widget buildWallpaperFromBytes(Uint8List? bytes, BoxFit fit) =>
    impl.buildWallpaperFromBytes(bytes, fit);

// --- Widget wrapper so you can use ThemeBg(...) in widgets ---
class ThemeBg extends StatelessWidget {
  /// Provide either [bytes] OR [path]. If both are set, [bytes] wins.
  final Uint8List? bytes;
  final String? path;
  final BoxFit fit;
  final Widget child;

  const ThemeBg({
    super.key,
    this.bytes,
    this.path,
    this.fit = BoxFit.cover,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bg = bytes != null
        ? buildWallpaperFromBytes(bytes, fit)
        : buildWallpaperFromPath(path, fit);

    return Stack(
      fit: StackFit.expand,
      children: [bg, child],
    );
  }
}
