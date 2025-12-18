// lib/screens/settings_screen.dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/paywall_screen.dart';
import '../screens/manage_subscription_screen.dart';
import '../widgets/glass.dart';
import 'dart:ui';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Color accentColor;

  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<Color> onAccentChanged;

  final String appName;
  final String appVersion;
  final String createdBy;

  const SettingsScreen({
    super.key,
    required this.onThemeModeChanged,
    required this.onAccentChanged,
    required this.appName,
    required this.appVersion,
    required this.createdBy,
    this.themeMode = ThemeMode.system,
    this.accentColor = const Color(0xFF006399),
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeMode _mode = ThemeMode.system;
  Color _accent = const Color(0xFF006399);

  static const _defaultBlue = Color(0xFF006399);

  bool _expPremium = true;
  bool _expNotif = true;
  bool _expAppearance = true;
  bool _expAbout = true;

  static const _swatches = <Color>[
    Color(0xFF6750A4),
    Color(0xFF386A20),
    _defaultBlue,
    Color(0xFFB3261E),
    Color(0xFF885200),
    Color(0xFF0B5C5A),
    Color(0xFF6C2A6A),
    Color(0xFF4E5B62),
  ];

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  @override
  void initState() {
    super.initState();
    _mode = widget.themeMode;
    _accent = widget.accentColor;
  }

  // -------------------------------------------------------------
  // PUSH NOTIFICATIONS
  // -------------------------------------------------------------
  Future<void> _enablePushAndroid(String uid) async {
    if (!_isAndroid) return;

    final status = await Permission.notification.request();
    if (!status.isGranted) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _users.doc(uid).collection('tokens').doc(token).set(
            {'platform': 'android', 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      await _users.doc(uid).collection('tokens').doc(t).set(
            {'platform': 'android', 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
    });

    await _users.doc(uid).set({
      'notif': {'pushEnabled': true}
    }, SetOptions(merge: true));
  }

  Future<void> _enablePushIOS(String uid) async {
    if (!_isIOS) return;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _users.doc(uid).collection('tokens').doc(token).set(
            {'platform': 'ios', 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      await _users.doc(uid).collection('tokens').doc(t).set(
            {'platform': 'ios', 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
    });

    await _users.doc(uid).set({
      'notif': {'pushEnabled': true}
    }, SetOptions(merge: true));
  }

  Future<void> _disablePushAndroid(String uid) async {
    final toks = await _users.doc(uid).collection('tokens').get();
    for (final d in toks.docs) {
      if (d.data()['platform'] == 'android') {
        await d.reference.delete();
      }
    }
    await _users.doc(uid).set({
      'notif': {'pushEnabled': false}
    }, SetOptions(merge: true));
  }

  Future<void> _disablePushIOS(String uid) async {
    final toks = await _users.doc(uid).collection('tokens').get();
    for (final d in toks.docs) {
      if (d.data()['platform'] == 'ios') {
        await d.reference.delete();
      }
    }
    await _users.doc(uid).set({
      'notif': {'pushEnabled': false}
    }, SetOptions(merge: true));
  }

  Future<void> _setEmailPref(String uid, bool enabled) async {
    await _users.doc(uid).set(
      {'notif': {'emailEnabled': enabled}},
      SetOptions(merge: true),
    );
  }

  // -------------------------------------------------------------
  // SECTION WRAPPER
  // -------------------------------------------------------------
  Widget _section({
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: GlassPanel(
        radius: BorderRadius.circular(16),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        blur: 18,
        opacity: 0.10,
        accentBorder: true,
        accentOpacity: 0.16,
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            if (expanded) const SizedBox(height: 12),
            if (expanded) child,
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // PREMIUM SECTION
  // -------------------------------------------------------------
  Widget _premiumContent(bool isPremium) {
    final cs = Theme.of(context).colorScheme;
    final feats = const [
      "Unlimited shared calendars",
      "Notifications & reminders",
      "All themes & accent colors",
      "Future AI summaries & exports",
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isPremium)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.verified, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Premium active — your subscription is up to date.",
                    style: TextStyle(color: cs.onSecondaryContainer),
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ManageSubscriptionScreen()),
                    );
                  },
                  child: const Text("Manage",
                  style:  TextStyle( color: Colors.white),)
                ),
              ],
            ),
          ),
        for (final f in feats) _featureRow(f),
        const SizedBox(height: 14),
        if (!isPremium)
          FilledButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              );
            },
            child: const Text("Upgrade"),
          ),
      ],
    );
  }

  Widget _featureRow(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // ACCENT COLOR GRID
  // -------------------------------------------------------------
  Widget _accentGrid(bool isPremium) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in _swatches) _swatch(c, isPremium),
      ],
    );
  }

  Widget _swatch(Color c, bool isPremium) {
    final cs = Theme.of(context).colorScheme;

    final locked = !isPremium && c.value != _defaultBlue.value;
    final selected = _accent == c;

    return InkWell(
      onTap: () {
        if (locked) {
          _showPremiumPopup();
          return;
        }
        setState(() => _accent = c);
        widget.onAccentChanged(c);
      },
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? cs.onSurface : Colors.transparent,
                width: selected ? 2 : 1,
              ),
            ),
          ),
          if (locked)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // ===============================
// PREMIUM POPUP (GLASS VERSION)
// ===============================
void _showPremiumPopup() {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final tt = theme.textTheme;

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,   // <-- Square-ish card, not stretched
              minWidth: 320,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: cs.primary.withOpacity(0.25),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.workspace_premium,
                              color: Colors.white, size: 26),
                          const SizedBox(width: 10),
                          Text("Go Premium",
                              style: tt.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              )),
                        ],
                      ),

                      const SizedBox(height: 14),

                      const _DialogFeat("Unlimited shared calendars"),
                      const _DialogFeat("Notifications & reminders"),
                      const _DialogFeat("All themes & accent colors"),
                      const _DialogFeat("Future AI summaries & exports"),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              "Maybe later",
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PaywallScreen(),
                                ),
                              );
                            },
                            child: const Text("Upgrade"),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

  // -------------------------------------------------------------
  // BUILD UI
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: user == null
                ? const Stream.empty()
                : _users.doc(user.uid).snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? {};
              final isPremium = data['premium'] == true;

              if (!isPremium && _accent.value != _defaultBlue.value) {
                _accent = _defaultBlue;
              }

              return Column(
                children: [
                  _section(
                    title: "Premium",
                    icon: Icons.workspace_premium,
                    expanded: _expPremium,
                    onToggle: () => setState(() => _expPremium = !_expPremium),
                    child: _premiumContent(isPremium),
                  ),
                  _section(
                    title: "Notifications",
                    icon: Icons.notifications,
                    expanded: _expNotif,
                    onToggle: () => setState(() => _expNotif = !_expNotif),
                    child: _buildNotifSection(),
                  ),
                  _section(
                    title: "Appearance",
                    icon: Icons.color_lens,
                    expanded: _expAppearance,
                    onToggle: () =>
                        setState(() => _expAppearance = !_expAppearance),
                    child: _buildAppearanceSection(isPremium),
                  ),
                  _section(
                    title: "About",
                    icon: Icons.info_outline,
                    expanded: _expAbout,
                    onToggle: () => setState(() => _expAbout = !_expAbout),
                    child: _buildAboutSection(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // SUB-SECTIONS
  // -------------------------------------------------------------
  Widget _buildNotifSection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Text("Sign in to manage notifications.");
    }

    final uid = user.uid;
    final doc = _users.doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: doc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final notif = data['notif'] ?? {};
        final pushEnabled = notif['pushEnabled'] ?? false;
        final emailEnabled = notif['emailEnabled'] ?? true;

        if (kIsWeb) {
          return SwitchListTile(
            title: const Text("Email notifications"),
            subtitle: const Text("We’ll email you when events are added."),
            value: emailEnabled,
            onChanged: (v) => _setEmailPref(uid, v),
          );
        }

        return Column(
          children: [
            SwitchListTile(
              title: const Text("Push notifications"),
              value: pushEnabled,
              subtitle: Text(_isAndroid
                  ? "Get alerts when events are added on this Android device"
                  : "Get alerts when events are added on this iOS device"),
              onChanged: (v) async {
                if (v) {
                  _isAndroid
                      ? await _enablePushAndroid(uid)
                      : await _enablePushIOS(uid);
                } else {
                  _isAndroid
                      ? await _disablePushAndroid(uid)
                      : await _disablePushIOS(uid);
                }
              },
            ),
            SwitchListTile(
              title: const Text("Email notifications"),
              value: emailEnabled,
              subtitle: const Text("We’ll email you when events are added."),
              onChanged: (v) => _setEmailPref(uid, v),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAppearanceSection(bool isPremium) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Theme",
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _themeChip("System", ThemeMode.system),
            _themeChip("Light", ThemeMode.light),
            _themeChip("Dark", ThemeMode.dark),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text("Accent color",
                style:
                    tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (!isPremium)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, size: 14),
                    SizedBox(width: 4),
                    Text("Premium required"),
                  ],
                ),
              )
          ],
        ),
        const SizedBox(height: 8),
        _accentGrid(isPremium),
      ],
    );
  }

  Widget _themeChip(String label, ThemeMode mode) {
    final cs = Theme.of(context).colorScheme;
    final selected = _mode == mode;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: cs.secondaryContainer,
      backgroundColor: cs.surface,
      labelStyle: TextStyle(
        color: selected ? cs.onSecondaryContainer : cs.onSurface,
        fontWeight: FontWeight.w600,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: 1.2,
        ),
      ),
      onSelected: (_) {
        setState(() => _mode = mode);
        widget.onThemeModeChanged(mode);
      },
    );
  }

  Widget _buildAboutSection() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

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
                  fontWeight: FontWeight.w700, color: cs.onSurface)),
          subtitle: Text(widget.appVersion,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person),
          title: const Text('Created by'),
          subtitle: Text(widget.createdBy),
        ),
      ],
    );
  }
}

// ===============================
// PREMIUM POPUP FEATURE ROW
// ===============================
class _DialogFeat extends StatelessWidget {
  final String text;
  const _DialogFeat(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          Icons.check_circle,
          size: 18,
          color: cs.primary.withOpacity(0.95),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
