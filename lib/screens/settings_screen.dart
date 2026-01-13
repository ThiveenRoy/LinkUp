// lib/screens/settings_screen.dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

// Firebase & permissions
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/glass.dart';
import '../screens/paywall_screen.dart';
import 'manage_subscription_screen.dart';

class SettingsScreen extends StatefulWidget {
  // ===== Appearance inputs =====
  final ThemeMode themeMode;
  final Color accentColor;

  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<Color> onAccentChanged;

  // ===== About inputs =====
  final String appName; // e.g. "LinkUp Calendar"
  final String appVersion; // e.g. "v1.0.0"
  final String createdBy; // e.g. "Your Name / Team"

  const SettingsScreen({
    super.key,
    this.themeMode = ThemeMode.system,
    this.accentColor = const Color(0xFF6750A4),
    required this.onThemeModeChanged,
    required this.onAccentChanged,
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

  // BRAND default blue (free users are locked to this)
  static const _brandBlue = Color(0xFF006399);

  // Simple curated palette
  static const _swatches = <Color>[
    Color(0xFF6750A4), // purple
    Color(0xFF386A20), // green
    _brandBlue, // blue
    Color(0xFFB3261E), // red
    Color(0xFF885200), // orange
    Color(0xFF0B5C5A), // teal
    Color(0xFF6C2A6A), // plum
    Color(0xFF4E5B62), // slate
  ];

  // ===== Platform helpers =====
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  // ===== Android push =====
  Future<void> _enablePushAndroid(String uid) async {
    if (!_isAndroid) return;

    final status = await Permission.notification.request();
    if (!status.isGranted) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _users.doc(uid).collection('tokens').doc(token).set({
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      await _users.doc(uid).collection('tokens').doc(t).set({
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _users.doc(uid).set({
      'notif': {'pushEnabled': true}
    }, SetOptions(merge: true));
  }

  Future<void> _disablePushAndroid(String uid) async {
    final toks = await _users.doc(uid).collection('tokens').get();
    for (final d in toks.docs) {
      if ((d.data()['platform'] as String?) == 'android') {
        await d.reference.delete();
      }
    }
    await _users.doc(uid).set({
      'notif': {'pushEnabled': false}
    }, SetOptions(merge: true));
  }

  // ===== iOS push =====
  Future<void> _enablePushIOS(String uid) async {
    if (!_isIOS) return;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final ok = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!ok) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _users.doc(uid).collection('tokens').doc(token).set({
        'platform': 'ios',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      await _users.doc(uid).collection('tokens').doc(t).set({
        'platform': 'ios',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _users.doc(uid).set({
      'notif': {'pushEnabled': true}
    }, SetOptions(merge: true));
  }

  Future<void> _disablePushIOS(String uid) async {
    final toks = await _users.doc(uid).collection('tokens').get();
    for (final d in toks.docs) {
      if ((d.data()['platform'] as String?) == 'ios') {
        await d.reference.delete();
      }
    }
    await _users.doc(uid).set({
      'notif': {'pushEnabled': false}
    }, SetOptions(merge: true));
  }

  Future<void> _setEmailPref(String uid, bool enabled) async {
    await _users.doc(uid).set({
      'notif': {'emailEnabled': enabled}
    }, SetOptions(merge: true));
  }

  void _openPremiumDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                Icons.workspace_premium,
                  color: Theme.of(context).colorScheme.primary,
                ),
              const SizedBox(width: 8),
              const Text('Go Premium'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Feat(text: 'Unlimited shared calendars'),
              _Feat(text: 'Notifications & reminders'),
              _Feat(text: 'All themes & accent colors'),
              _Feat(text: 'Future AI summaries & exports'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Maybe later')),
            FilledButton(
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
  },
  child: const Text('Upgrade'),
),
          ],
        );
      },
    );
  }

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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

    Widget accentGrid({required bool isPremium}) {
  Widget swatch(Color c) {
    final selected = _accent.value == c.value;
    final locked = !isPremium && c.value != _brandBlue.value;

    return InkWell(
      onTap: () {
        if (locked) {
          _openPremiumDialog();
          return;
        }
        setState(() => _accent = c);
        widget.onAccentChanged(c);
      },
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(
            width: 34, height: 34,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                  color: Colors.black.withOpacity(0.15),
                ),
              ],
            ),
          ),
          if (locked)
            Container(
              width: 34, height: 34,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.lock, size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget customChip() {
    final cs = Theme.of(context).colorScheme;
    final locked = !isPremium;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        if (locked) {
          _openPremiumDialog();
          return;
        }
        final picked = await _pickCustomColor(context, _accent);
        if (picked != null) {
          setState(() => _accent = picked);
          widget.onAccentChanged(picked);
        }
      },
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.primary),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.colorize, size: 16),
              SizedBox(width: 8),
              Text('Custom'),
            ]),
          ),
          if (locked)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.lock, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  return Wrap(
    children: [
      for (final c in _swatches) swatch(c),
      customChip(), // ← now always shown; locked for Free, interactive for Premium
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
                style:
                    tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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

    // ===== Premium section (reads users/{uid}.entitlements.premium) =====
    Widget premiumSection() {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading:
              Icon(
                Icons.workspace_premium,
                color: Theme.of(context).colorScheme.primary,
              ),

          title: const Text('Premium'),
          subtitle: const Text('Sign in to view or upgrade your plan'),
          trailing: FilledButton(
            onPressed: () => _openPremiumDialog(),
            child: const Text('Upgrade'),
          ),
        );
      }

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _users.doc(user.uid).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};
          final isPremium = data['premium'] == true;


          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
  Icons.workspace_premium,
  color: Theme.of(context).colorScheme.primary,
),

                title: Text(isPremium ? 'Premium (Active)' : 'Premium'),
                subtitle: const Text(
                  'Premium unlocks: unlimited shared calendars, notifications, and all themes.',
                ),
                trailing: isPremium
                    ? OutlinedButton(
  style: OutlinedButton.styleFrom(
    foregroundColor: isDark ? Colors.white : Colors.black,
    side: BorderSide(
      color: isDark ? Colors.white : Colors.black,
      width: 1.2,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    ),
  ),
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ManageSubscriptionScreen(),
      ),
    );
  },
  child: const Text('Manage'),
)
                    : FilledButton(
                        onPressed: _openPremiumDialog,
                        child: const Text('Upgrade'),
                      ),
              ),
              const SizedBox(height: 8),
              const _Feat(text: 'Unlimited shared calendars'),
              const _Feat(text: 'Notifications & reminders'),
              const _Feat(text: 'All themes & accent colors'),
              const _Feat(text: 'Future AI summaries & exports'),
            ],
          );
        },
      );
    }

    // ===== Notifications section (platform-aware UI) =====
    Widget notificationsSection() {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const ListTile(
          leading: Icon(Icons.lock),
          title: Text('Sign in to manage notifications'),
        );
      }
      final uid = user.uid;
      final doc = _users.doc(uid);

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};
          final notif = (data['notif'] as Map<String, dynamic>?) ?? {};
          final pushEnabled = (notif['pushEnabled'] as bool?) ?? false;
          final emailEnabled = (notif['emailEnabled'] as bool?) ?? true;

          // WEB → ONLY Email toggle
          if (kIsWeb) {
            return Column(
              children: [
                SwitchListTile(
                  title: const Text('Email notifications'),
                  subtitle:
                      const Text('We’ll email you when events are added.'),
                  value: emailEnabled,
                  onChanged: (v) => _setEmailPref(uid, v),
                ),
              ],
            );
          }

          // ANDROID / iOS → Push + Email
          return Column(
            children: [
              SwitchListTile(
                title: const Text('Push notifications'),
                subtitle: Text(_isAndroid
                    ? 'Get alerts on this Android device when events are added.'
                    : 'Get alerts on this iOS device when events are added.'),
                value: pushEnabled,
                onChanged: (v) async {
                  if (v) {
                    if (_isAndroid) {
                      await _enablePushAndroid(uid);
                    } else if (_isIOS) {
                      await _enablePushIOS(uid);
                    }
                  } else {
                    if (_isAndroid) {
                      await _disablePushAndroid(uid);
                    } else if (_isIOS) {
                      await _disablePushIOS(uid);
                    }
                  }
                },
              ),
              SwitchListTile(
                title: const Text('Email notifications'),
                subtitle:
                    const Text('We’ll email you when events are added.'),
                value: emailEnabled,
                onChanged: (v) => _setEmailPref(uid, v),
              ),
            ],
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            // Premium block on top
            section('Premium', [premiumSection()]),

            // Notifications (platform-aware rendering)
            section('Notifications', [notificationsSection()]),

            // Appearance — locks accent grid for free users
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseAuth.instance.currentUser == null
                  ? const Stream.empty()
                  : _users
                      .doc(FirebaseAuth.instance.currentUser!.uid)
                      .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final isPremium = data['premium'] == true;


                // Ensure free defaults to brand blue
                if (!isPremium && _accent.value != _brandBlue.value) {
                  _accent = _brandBlue;
                }

                return section('Appearance', [
                  const SizedBox(height: 4),
                  Text('Theme',
                      style: tt.labelLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 6),
                  themeModeRow(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Accent color',
                          style: tt.labelLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          )),
                      if (!isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: const [
                            Icon(Icons.lock, size: 14),
                            SizedBox(width: 4),
                            Text('Premium required'),
                          ]),
                        )
                      ]
                    ],
                  ),
                  const SizedBox(height: 6),
                  accentGrid(isPremium: isPremium),
                ]);
              },
            ),

            section('About', [aboutCard()]),
          ],
        ),
      ),
    );
  }

  // ===== Custom color dialog (HSV wheel + sliders) =====
  Future<Color?> _pickCustomColor(BuildContext ctx, Color start) async {
    return showDialog<Color>(
      context: ctx,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        HSVColor hsv = HSVColor.fromColor(start);
        double r = start.red.toDouble();
        double g = start.green.toDouble();
        double b = start.blue.toDouble();

        void _fromHSV(StateSetter setD, HSVColor v) {
          hsv = v;
          final c = v.toColor();
          r = c.red.toDouble();
          g = c.green.toDouble();
          b = c.blue.toDouble();
          setD(() {});
        }

        void _fromRGB(StateSetter setD) {
          final c = Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt());
          hsv = HSVColor.fromColor(c);
          setD(() {});
        }

        Widget _rgbSlider(String label, double value,
            ValueChanged<double> onChanged, StateSetter setD) {
          return Row(
            children: [
              SizedBox(
                  width: 18,
                  child: Text(label,
                      style: tt.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700))),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 255,
                  divisions: 255,
                  value: value,
                  activeColor: cs.primary,
                  onChanged: (v) {
                    onChanged(v);
                    _fromRGB(setD);
                  },
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(value.toInt().toString(),
                    textAlign: TextAlign.right,
                    style:
                        tt.labelLarge?.copyWith(color: cs.onSurface)),
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
              insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 24),
              child: GlassPanel(
                radius: const BorderRadius.all(Radius.circular(16)),
                padding:
                    const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: current,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                                color: Colors.black.withOpacity(0.25))
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Color wheel (Hue + Saturation)
                      _ColorWheel(
                        size: 220,
                        hsv: hsv.withValue(1.0),
                        onChanged: (v) =>
                            _fromHSV(setD, v.withValue(hsv.value)),
                      ),

                      const SizedBox(height: 8),

                      // Brightness
                      Row(
                        children: [
                          SizedBox(
                              width: 18,
                              child: Text('V',
                                  style: tt.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700))),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: 1,
                              divisions: 100,
                              value: hsv.value,
                              activeColor: cs.primary,
                              onChanged: (v) =>
                                  _fromHSV(setD, hsv.withValue(v)),
                            ),
                          ),
                          SizedBox(
                              width: 44,
                              child: Text(
                                  (hsv.value * 100).round().toString(),
                                  textAlign: TextAlign.right)),
                        ],
                      ),

                      // RGB (optional)
                      _rgbSlider('R', r, (v) => r = v, setD),
                      _rgbSlider('G', g, (v) => g = v, setD),
                      _rgbSlider('B', b, (v) => b = v, setD),

                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogCtx, null),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(dialogCtx, current),
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

class _Feat extends StatelessWidget {
  final String text;
  const _Feat({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.check_circle, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

/// ===== Lightweight HSV color wheel (no packages) =====
class _ColorWheel extends StatelessWidget {
  final double size; // diameter
  final HSVColor hsv; // hue & saturation; value controlled outside
  final ValueChanged<HSVColor> onChanged;

  const _ColorWheel({
    required this.size,
    required this.hsv,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _WheelCore(size: size, hsv: hsv, onChanged: onChanged);
  }
}

class _WheelCore extends StatefulWidget {
  final double size;
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _WheelCore(
      {required this.size, required this.hsv, required this.onChanged});

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
    if (angle < 0) angle += math.pi * 2; // 0..2pi

    final h = (angle / (math.pi * 2)) * 360.0; // 0..360
    final s = (dist / radius).clamp(0.0, 1.0); // 0..1
    setState(() => _hsv = _hsv.withHue(h).withSaturation(s));
    widget.onChanged(_hsv);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) =>
          _handlePos(d.localPosition, Size(widget.size, widget.size)),
      onPanUpdate: (d) =>
          _handlePos(d.localPosition, Size(widget.size, widget.size)),
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
    final sweep =
        Paint()..shader = SweepGradient(colors: hueColors).createShader(rect);
    canvas.drawCircle(size.center(Offset.zero), radius, sweep);

    // 2) Saturation fade to white in the middle
    final sat = Paint()
      ..shader = const RadialGradient(
        colors: [Colors.white, Colors.transparent],
        stops: [0.0, 1.0],
      ).createShader(rect);
    canvas.drawCircle(size.center(Offset.zero), radius, sat);

    // 3) Thumb
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