// lib/widgets/glass.dart
import 'dart:ui';
import 'package:flutter/material.dart';

/// Frosted panel: backdrop blur + theme-aware tint + optional accent border.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;            // 8–32
  final double? opacity;        // null → smart per-theme defaults
  final BorderRadius radius;
  final BoxConstraints? constraints;

  /// New: accent rim
  final bool accentBorder;      // if true, use colorScheme.primary as border
  final double accentOpacity;   // 0.10–0.30 usually looks good
  final double borderWidth;     // 0.6–1.2

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.blur = 24,
    this.opacity,
    this.radius = const BorderRadius.all(Radius.circular(18)),
    this.constraints,
    this.accentBorder = false,
    this.accentOpacity = 0.22,
    this.borderWidth = 0.9,
  });


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Base tint from surface to match your theme
    final base = Color.alphaBlend(
      cs.surfaceTint.withOpacity(isDark ? 0.00 : 0.10), // brighten light a bit
      cs.surface,
    );
    final on = cs.onSurface;

    // Softer in light; a bit denser in dark
    final o = opacity ?? (isDark ? 0.11 : 0.038);
    
    // Hairline fallback (if not using accent)
    final hairline = on.withOpacity(isDark ? 0.18 : 0.10);

    // Accent rim color
    final rim = cs.primary.withOpacity(accentOpacity);

    // Gentle top highlight for the “glass” feel
    final highlight = Colors.white.withOpacity(isDark ? 0.04 : 0.10);

    return ConstrainedBox(
      constraints: constraints ?? const BoxConstraints(),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(highlight, base).withOpacity(o + (isDark ? 0.0 : 0.01)),
                  base.withOpacity(o),
                ],
              ),
              borderRadius: radius,
              border: Border.all(
                color: accentBorder ? cs.primary.withOpacity(isDark ? 0.16 : 0.20) // rim slightly subtler
                                    : on.withOpacity(isDark ? 0.16 : 0.08),
                width: borderWidth, // keep control via parameter
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), // softer shadow in light
                  blurRadius: isDark ? 18 : 16,
                  offset: const Offset(0, 10),
                ),
              ],
              ),
            child: child,
          ),
        ),
      ),
    );
  }
}
