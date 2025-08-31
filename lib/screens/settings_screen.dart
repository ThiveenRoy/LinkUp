import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeController theme;
  const SettingsScreen({super.key, required this.theme});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _picker = ImagePicker();

  final List<Color> _presets = const [
    Color(0xFF3F72AF),
    Color(0xFF7C3AED),
    Color(0xFF16A34A),
    Color(0xFFEA580C),
    Color(0xFF0EA5E9),
    Color(0xFFEF4444),
    Color(0xFF10B981),
    Color(0xFFDB2777),
  ];

  Future<void> _pickCustomColor() async {
    Color temp = widget.theme.seedColor;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: temp,
            onColorChanged: (c) => temp = c,
            enableAlpha: false,
            labelTypes: const [],
            portraitOnly: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () { Navigator.pop(context); widget.theme.setSeedColor(temp); }, child: const Text('Apply')),
        ],
      ),
    );
  }

  Future<void> _pickWallpaper() async {
    // Use image_picker across all platforms
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,               // keep memory reasonable
      maxHeight: 2400,
      imageQuality: 90,             // ignored on web, but harmless
    );
    if (xfile == null) return;

    if (kIsWeb) {
      final Uint8List bytes = await xfile.readAsBytes();
      // Optional: you could downscale large images client-side; keeping it simple here.
      await widget.theme.setWallpaperBytes(bytes);
    } else {
      await widget.theme.setWallpaperPath(xfile.path);
    }
  }

  Future<void> _clearWallpaper() async {
    if (kIsWeb) {
      await widget.theme.setWallpaperBytes(null);
    } else {
      await widget.theme.setWallpaperPath(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final preview = kIsWeb
        ? (t.wallpaperBytes != null && t.wallpaperBytes!.isNotEmpty
            ? Image.memory(t.wallpaperBytes!, height: 160, width: double.infinity, fit: BoxFit.cover)
            : null)
        : (t.wallpaperPath != null && t.wallpaperPath!.isNotEmpty
            ? Image.file(File(t.wallpaperPath!), height: 160, width: double.infinity, fit: BoxFit.cover)
            : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),

          // Mode
          SegmentedButton<ThemeModePref>(
            segments: const [
              ButtonSegment(value: ThemeModePref.system, label: Text('System')),
              ButtonSegment(value: ThemeModePref.light,  label: Text('Light')),
              ButtonSegment(value: ThemeModePref.dark,   label: Text('Dark')),
            ],
            selected: {t.modePref},
            onSelectionChanged: (s) => t.setMode(s.first),
          ),

          const SizedBox(height: 20),
          Text('Accent color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._presets.map((c) => _ColorDot(
                    color: c,
                    selected: c.value == t.seedColor.value,
                    onTap: () => t.setSeedColor(c),
                  )),
              _ColorDot(
                color: t.seedColor,
                icon: Icons.edit,
                onTap: _pickCustomColor,
              ),
            ],
          ),

          const SizedBox(height: 28),
          Text('Wallpaper (web supported)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _pickWallpaper,
                icon: const Icon(Icons.image),
                label: const Text('Upload wallpaper'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: (kIsWeb ? t.wallpaperBytes != null : (t.wallpaperPath != null && t.wallpaperPath!.isNotEmpty))
                    ? _clearWallpaper
                    : null,
                icon: const Icon(Icons.delete),
                label: const Text('Clear wallpaper'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (preview != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: preview,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Fit'),
                const SizedBox(width: 12),
                DropdownButton<BoxFit>(
                  value: t.wallpaperFit,
                  items: const [
                    BoxFit.cover, BoxFit.contain, BoxFit.fill, BoxFit.fitWidth, BoxFit.fitHeight
                  ].map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
                  onChanged: (f) => f == null ? null : t.setWallpaperFit(f),
                ),
                const Spacer(),
                const Text('Dim'),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: Slider(
                    value: t.wallpaperDim,
                    min: 0.0,
                    max: 0.8,
                    onChanged: (v) => t.setWallpaperDim(v),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _ColorDot({
    required this.color,
    required this.onTap,
    this.selected = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3) : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 40, width: 40,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: border),
        child: icon == null ? null : Icon(icon, color: Colors.white),
      ),
    );
  }
}
