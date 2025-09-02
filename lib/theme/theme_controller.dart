import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeModePref { system, light, dark }

class ThemeController extends ChangeNotifier {
  // ---------- Theme state ----------
  Color _seedColor = const Color(0xFF3F72AF);
  ThemeModePref _modePref = ThemeModePref.system;

  // Wallpaper:
  // - Web: bytes (persisted base64 in SharedPreferences)
  // - Mobile/Desktop: absolute file path persisted in SharedPreferences
  String? _wallpaperPath;         // non-web only
  Uint8List? _wallpaperBytes;     // web only
  BoxFit _wallpaperFit = BoxFit.cover;
  double _wallpaperDim = 0.15;    // overlay 0..1

  // ---------- Getters ----------
  Color get seedColor => _seedColor;
  ThemeModePref get modePref => _modePref;
  String? get wallpaperPath => _wallpaperPath;
  Uint8List? get wallpaperBytes => _wallpaperBytes;
  BoxFit get wallpaperFit => _wallpaperFit;
  double get wallpaperDim => _wallpaperDim;

  ThemeMode get themeMode {
    switch (_modePref) {
      case ThemeModePref.light: return ThemeMode.light;
      case ThemeModePref.dark:  return ThemeMode.dark;
      case ThemeModePref.system:
      return ThemeMode.system;
    }
  }

  // ---------- Setters (persist + notify) ----------
  Future<void> setSeedColor(Color c) async {
    _seedColor = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme.seed', c.value);
  }

  Future<void> setMode(ThemeModePref pref) async {
    _modePref = pref;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme.mode', pref.name);
  }

  /// Set wallpaper from bytes (web) or from file path (mobile/desktop).
  Future<void> setWallpaperBytes(Uint8List? bytes) async {
    if (!kIsWeb) {
      // On non-web, prefer setWallpaperPath instead. But allow clearing here.
      if (bytes != null) return;
      _wallpaperPath = null;
    }
    _wallpaperBytes = bytes;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (bytes == null) {
      await prefs.remove('theme.wallpaper.bytes');
    } else {
      // base64 encode
      await prefs.setString('theme.wallpaper.bytes', base64Encode(bytes));
    }
  }

  Future<void> setWallpaperPath(String? path) async {
    if (kIsWeb) {
      // On web, ignore paths; use bytes instead.
      return;
    }
    _wallpaperPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('theme.wallpaper.path');
    } else {
      await prefs.setString('theme.wallpaper.path', path);
    }
  }

  Future<void> setWallpaperFit(BoxFit fit) async {
    _wallpaperFit = fit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme.wallpaper.fit', fit.name);
  }

  Future<void> setWallpaperDim(double dim) async {
    _wallpaperDim = dim.clamp(0.0, 0.9);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('theme.wallpaper.dim', _wallpaperDim);
  }

    bool get hasWallpaper {
    if (kIsWeb) {
      final b = _wallpaperBytes;
      return b != null && b.isNotEmpty;
    } else {
      final p = _wallpaperPath;
      return p != null && p.isNotEmpty;
    }
  }

  // ---------- Load persisted state ----------
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final v = prefs.getInt('theme.seed');
    if (v != null) _seedColor = Color(v);

    final m = prefs.getString('theme.mode');
    if (m != null) {
      _modePref = ThemeModePref.values.firstWhere(
        (e) => e.name == m,
        orElse: () => ThemeModePref.system,
      );
    }

    // Wallpaper
    if (kIsWeb) {
      final b64 = prefs.getString('theme.wallpaper.bytes');
      _wallpaperBytes = (b64 == null) ? null : base64Decode(b64);
    } else {
      _wallpaperPath = prefs.getString('theme.wallpaper.path');
    }

    final fitName = prefs.getString('theme.wallpaper.fit');
    if (fitName != null) {
      _wallpaperFit = BoxFit.values.firstWhere(
        (f) => f.name == fitName,
        orElse: () => BoxFit.cover,
      );
    }

    _wallpaperDim = prefs.getDouble('theme.wallpaper.dim') ?? _wallpaperDim;

    notifyListeners();
  }

  // Add this method alongside your other setters
  Future<void> clearWallpaper() async {
    // Clear in-memory
    if (kIsWeb) {
      _wallpaperBytes = null;
    } else {
      _wallpaperPath = null;
    }
    notifyListeners();

    // Clear persisted values
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('theme.wallpaper.bytes');
    await prefs.remove('theme.wallpaper.path');
  }
  
}
