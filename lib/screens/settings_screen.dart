// lib/screens/settings_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/glass.dart';

class SettingsScreen extends StatefulWidget {
  // ======= Appearance inputs =======
  final ThemeMode themeMode;
  final Color accentColor;

  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<Color> onAccentChanged;

  // ======= About inputs =======
  final String appName;      // e.g. "LinkUp Calendar"
  final String appVersion;   // e.g. "v1.0.0"
  final String createdBy;    // e.g. "Your Name / Team"

  const SettingsScreen({
    super.key,
    // Appearance
    this.themeMode = ThemeMode.system,
    this.accentColor = const Color(0xFF6750A4),
    required this.onThemeModeChanged,
    required this.onAccentChanged,
    // About
    required this.appName,
    required this.appVersion,
    required this.createdBy,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _mode = widget.themeMode;
  late Color _accent = widget.accentColor;

  // Simple curated palette that matches Material tones nicely.
  static const _swatches = <Color>[
    Color(0xFF6750A4), // purple
    Color(0xFF386A20), // green
    Color(0xFF006399), // blue
    Color(0xFFB3261E), // red
    Color(0xFF885200), // orange
    Color(0xFF0B5C5A), // teal
    Color(0xFF6C2A6A), // plum
    Color(0xFF4E5B62), // slate
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassPanel(
        radius: const BorderRadius.all(Radius.circular(16)),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        blur: isDark ? 18 : 28,
        opacity: isDark ? 0.10 : 0.05,
        accentBorder: true,
        accentOpacity: isDark ? 0.16 : 0.20,
        borderWidth: 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                )),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );

    Widget themeModeRow() {
      Widget chip(String label, ThemeMode value) => ChoiceChip(
        label: Text(label),
        selected: _mode == value,
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: cs.surface,
        selectedColor: cs.secondaryContainer,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: _mode == value ? cs.onSecondaryContainer : cs.onSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: _mode == value ? cs.primary : cs.outlineVariant,
            width: _mode == value ? 1.25 : 1.0,
          ),
        ),
        onSelected: (_) {
          setState(() => _mode = value);
          widget.onThemeModeChanged(value);
        },
      );

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('System', ThemeMode.system),
          chip('Light', ThemeMode.light),
          chip('Dark', ThemeMode.dark),
        ],
      );
    }

    Widget accentGrid() {
      Widget swatch(Color c) {
        final selected = _accent.value == c.value;
        return InkWell(
          onTap: () {
            setState(() => _accent = c);
            widget.onAccentChanged(c);
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 34, height: 34,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? cs.onSurface : Colors.transparent,
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                  color: Colors.black.withOpacity(0.15),
                ),
              ],
            ),
          ),
        );
      }

      return Wrap(
        children: [
          for (final c in _swatches) swatch(c),
          // “Custom…” chip – opens wheel + sliders dialog
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () async {
              final picked = await _pickCustomColor(context, _accent);
              if (picked != null) {
                setState(() => _accent = picked);
                widget.onAccentChanged(picked);
              }
            },
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.primary),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.colorize, size: 16),
                const SizedBox(width: 8),
                Text('Custom', style: tt.labelLarge),
              ]),
            ),
          ),
        ],
      );
    }

    Widget aboutCard() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: cs.secondaryContainer,
              child: Icon(Icons.info, color: cs.onSecondaryContainer),
            ),
            title: Text(widget.appName,
                style: tt.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                )),
            subtitle: Text(widget.appVersion,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person),
            title: const Text('Created by'),
            subtitle: Text(widget.createdBy),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            section('Appearance', [
              const SizedBox(height: 4),
              Text('Theme', style: tt.labelLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 6),
              themeModeRow(),
              const SizedBox(height: 14),
              Text('Accent color', style: tt.labelLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 6),
              accentGrid(),
            ]),
            section('About', [aboutCard()]),
          ],
        ),
      ),
    );
  }

  // ===== Custom color dialog (Color wheel + Brightness + RGB sliders) =====
  Future<Color?> _pickCustomColor(BuildContext ctx, Color start) async {
    return showDialog<Color>(
      context: ctx,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        // Local color state (HSV + RGB mirrors)
        HSVColor hsv = HSVColor.fromColor(start);
        double r = start.red.toDouble();
        double g = start.green.toDouble();
        double b = start.blue.toDouble();

        void _fromHSV(StateSetter setD, HSVColor v) {
          hsv = v;
          final c = v.toColor();
          r = c.red.toDouble(); g = c.green.toDouble(); b = c.blue.toDouble();
          setD(() {});
        }

        void _fromRGB(StateSetter setD) {
          final c = Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt());
          hsv = HSVColor.fromColor(c);
          setD(() {});
        }

        Widget _rgbSlider(String label, double value, ValueChanged<double> onChanged, StateSetter setD) {
          return Row(
            children: [
              SizedBox(width: 18, child: Text(label, style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
              Expanded(
                child: Slider(
                  min: 0, max: 255, divisions: 255,
                  value: value,
                  activeColor: cs.primary,
                  onChanged: (v) { onChanged(v); _fromRGB(setD); },
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(value.toInt().toString(),
                    textAlign: TextAlign.right, style: tt.labelLarge?.copyWith(color: cs.onSurface)),
              ),
            ],
          );
        }

        return StatefulBuilder(
          builder: (dialogCtx, setD) {
            final current = hsv.toColor();
            return Dialog(
              elevation: 0,
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: GlassPanel(
                radius: const BorderRadius.all(Radius.circular(16)),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                blur: isDark ? 20 : 30,
                opacity: isDark ? 0.12 : 0.06,
                accentBorder: true,
                accentOpacity: isDark ? 0.16 : 0.20,
                borderWidth: 1.0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Pick custom color',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          )),
                      const SizedBox(height: 12),

                      // Preview
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: current,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.outlineVariant),
                          boxShadow: [BoxShadow(blurRadius: 10, offset: const Offset(0,4), color: Colors.black.withOpacity(0.25))],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 🎯 Color wheel (Hue+Saturation)
                      _ColorWheel(
                        size: 220,
                        hsv: hsv.withValue(1.0),   // draw wheel at full V
                        onChanged: (v) => _fromHSV(setD, v.withValue(hsv.value)),
                      ),

                      const SizedBox(height: 8),

                      // Brightness (Value)
                      Row(
                        children: [
                          SizedBox(width: 18, child: Text('V', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                          Expanded(
                            child: Slider(
                              min: 0, max: 1, divisions: 100,
                              value: hsv.value,
                              activeColor: cs.primary,
                              onChanged: (v) => _fromHSV(setD, hsv.withValue(v)),
                            ),
                          ),
                          SizedBox(width: 44, child: Text((hsv.value*100).round().toString(), textAlign: TextAlign.right)),
                        ],
                      ),

                      // RGB (optional, stays in sync)
                      _rgbSlider('R', r, (v) => r = v, setD),
                      _rgbSlider('G', g, (v) => g = v, setD),
                      _rgbSlider('B', b, (v) => b = v, setD),

                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogCtx, null),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(dialogCtx, current),
                            child: const Text('Use color'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// ===== Lightweight HSV color wheel (no packages) =====
class _ColorWheel extends StatelessWidget {
  final double size;               // diameter
  final HSVColor hsv;              // uses hue & saturation; value is controlled outside
  final ValueChanged<HSVColor> onChanged;

  const _ColorWheel({
    required this.size,
    required this.hsv,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _WheelCore(
      size: size,
      hsv: hsv,
      onChanged: onChanged,
    );
  }
}

class _WheelCore extends StatefulWidget {
  final double size;
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _WheelCore({required this.size, required this.hsv, required this.onChanged});

  @override
  State<_WheelCore> createState() => _WheelCoreState();
}

class _WheelCoreState extends State<_WheelCore> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = widget.hsv;
  }

  @override
  void didUpdateWidget(covariant _WheelCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hsv != widget.hsv) _hsv = widget.hsv;
  }

  void _handlePos(Offset local, Size size) {
    final center = size.center(Offset.zero);
    final v = local - center;
    final radius = size.shortestSide / 2;
    final dist = v.distance.clamp(0.0, radius);
    double angle = math.atan2(v.dy, v.dx); // -pi..pi
    if (angle < 0) angle += math.pi * 2;   // 0..2pi

    final h = (angle / (math.pi * 2)) * 360.0;  // 0..360
    final s = (dist / radius).clamp(0.0, 1.0);  // 0..1
    setState(() => _hsv = _hsv.withHue(h).withSaturation(s));
    widget.onChanged(_hsv);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _handlePos(d.localPosition, Size(widget.size, widget.size)),
      onPanUpdate: (d) => _handlePos(d.localPosition, Size(widget.size, widget.size)),
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _WheelPainter(hsv: _hsv),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  _WheelPainter({required this.hsv});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.shortestSide / 2;

    // 1) Hue sweep
    final hueColors = <Color>[];
    for (int i = 0; i <= 360; i += 12) {
      hueColors.add(HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor());
    }
    final sweep = Paint()
      ..shader = SweepGradient(colors: hueColors).createShader(rect);
    canvas.drawCircle(size.center(Offset.zero), radius, sweep);

    // 2) Saturation fade to white in the middle
    final sat = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.transparent],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawCircle(size.center(Offset.zero), radius, sat);

    // 3) Thumb showing current H/S
    final angle = (hsv.hue / 360.0) * math.pi * 2;
    final r = hsv.saturation * radius;
    final cx = size.width / 2 + r * math.cos(angle);
    final cy = size.height / 2 + r * math.sin(angle);
    final thumb = Paint()
      ..style = PaintingStyle.fill
      ..color = hsv.toColor();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.black.withOpacity(0.7);
    canvas.drawCircle(Offset(cx, cy), 8, thumb);
    canvas.drawCircle(Offset(cx, cy), 8, ring);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.hsv != hsv;
}
