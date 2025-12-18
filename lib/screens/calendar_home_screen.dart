// lib/screens/calendar_home_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:linkup_calendar/utils/pick_wallpaper.dart';
import 'package:linkup_calendar/widgets/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';
import 'master_calendar_screen.dart';
import 'settings_screen.dart';
import 'shared_calendar_list.dart';
import 'shared_calendar_screen.dart';
import 'dart:html' as html;


class CalendarHomeScreen extends StatefulWidget {
  final String? calendarId;
  final String calendarName;
  final int tabIndex;
  final bool fromInvite;

  /// Inject your ThemeController so Settings can read/update it.
  final ThemeController theme;

  const CalendarHomeScreen({
    super.key,
    this.calendarId,
    required this.calendarName,
    this.tabIndex = 0,
    this.fromInvite = false,
    required this.theme,
  });

  @override
  State<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

class _CalendarHomeScreenState extends State<CalendarHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_SharedCalendarTabState> _sharedTabKey = GlobalKey();
  bool _showTutorialCard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePostPurchasePopup();
    });
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.tabIndex,
    );

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1 && !widget.fromInvite) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _sharedTabKey.currentState?.resetToListView();
        });
      }
      setState(() {}); // keep mobile bottom nav in sync
    });

    _maybeShowTutorialOnce();
  }
  void _handlePostPurchasePopup() async {
  final uri = Uri.base.toString();

  // Only trigger when arriving from Stripe success URL
  final fromSuccess = uri.contains("billing/success");

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userRef = FirebaseFirestore.instance.collection("users").doc(user.uid);
  final snap = await userRef.get();
  final data = snap.data() ?? {};

  final isPremium = data["premium"] == true;
  final shouldShow = data["showPremiumWelcome"] == true;

  if (fromSuccess && isPremium && shouldShow) {
    // Remove the ugly URL before showing popup
    html.window.history.replaceState(null, "LinkUp", "/#/calendarHome");

    // Show popup AFTER the UI is fully stable
    Future.delayed(const Duration(milliseconds: 400), () {
      _showPremiumWelcomePopup();
    });

    // Prevent future popups
    await userRef.update({"showPremiumWelcome": false});
  }
}

  void _checkPurchaseStatus() async {
    final uri = Uri.base;

    // Stripe will redirect without query params in Flutter Web with hash routing,
    // so instead check if premium was just enabled.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef =
        FirebaseFirestore.instance.collection("users").doc(user.uid);
    final snap = await docRef.get();
    final data = snap.data() ?? {};

    final isPremium = data["premium"] == true;
    final shouldShow = data["showPremiumWelcome"] == true;

    if (isPremium && shouldShow) {
      // 1) Show popup
      _showPremiumWelcomePopup();

      // 2) Disable future popups
      await docRef.update({"showPremiumWelcome": false});
    }
  }

  void _showPremiumWelcomePopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: GlassPanel(
            radius: const BorderRadius.all(Radius.circular(20)),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            blur: 20,
            opacity: 0.10,
            accentBorder: true,
            accentOpacity: 0.20,
            borderWidth: 1.2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium, size: 42, color: cs.primary),
                const SizedBox(height: 12),
                Text("Thank You for Upgrading!",
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 8),
                Text(
                  "Your upgrade helps us improve LinkUp Calendar.\n"
                  "We'll continue building better features for you!",
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Continue"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  Future<void> _maybeShowTutorialOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final seenTutorial = prefs.getBool('seenTutorial') ?? false;
    if (!seenTutorial) {
      setState(() => _showTutorialCard = true);
    }
  }

  @override
  void didUpdateWidget(CalendarHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.calendarId != oldWidget.calendarId &&
        widget.calendarId != null) {
      _tabController.index = 1;
    }
    if (widget.tabIndex != oldWidget.tabIndex) {
      _tabController.index = widget.tabIndex;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  // ---------------- Settings ----------------

  void _openSettings() {
    final t = widget.theme;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => SettingsScreen(
              // values
              themeMode: t.themeMode,
              accentColor: t.seedColor,

              // callbacks
              onThemeModeChanged: (m) {
                switch (m) {
                  case ThemeMode.light:
                    t.setMode(ThemeModePref.light);
                    break;
                  case ThemeMode.dark:
                    t.setMode(ThemeModePref.dark);
                    break;
                  case ThemeMode.system:
                    t.setMode(ThemeModePref.system);
                    break;
                }
              },
              onAccentChanged: t.setSeedColor,

              // about
              appName: 'LinkUp Calendar',
              appVersion: 'v1.1.0',
              createdBy: 'Thiveen Roy',
            ),
      ),
    );
  }

  String _themedAsset(BuildContext context, String path) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (!isDark) return path;
  final i = path.lastIndexOf('.');
  if (i <= 0) return path;
  return '${path.substring(0, i)}_dark${path.substring(i)}';
}

  /// Picks an image and saves it to ThemeController:
  /// - Web: stores bytes (SharedPreferences base64).
  /// - Mobile/Desktop: stores absolute file path.
  Future<void> _pickAndApplyWallpaper(ThemeController t) async {
    try {
      if (kIsWeb) {
        // No plugin on web
        final bytes = await pickWallpaperBytes();
        if (bytes == null) return;
        await t.setWallpaperBytes(bytes);
        return;
      }

      // Mobile / Desktop: file path via file_picker
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (res == null || res.files.single.path == null) return;
      await t.setWallpaperPath(res.files.single.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load wallpaper: $e')));
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final desktopAppBar = AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 1,
      title: Row(
        children: [
           Image.asset(_themedAsset(context, 'assets/logo_final.png'), height: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'LinkUp Calendar',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
      actions: [
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings),
          onPressed: _openSettings,
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          icon: const Icon(Icons.logout, color: Colors.redAccent),
          label: const Text(
            'Logout',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: () => _logout(context),
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Theme.of(context).colorScheme.primary,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: Theme.of(context).hintColor,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(icon: Icon(Icons.calendar_today), text: 'Master Calendar'),
          Tab(icon: Icon(Icons.group), text: 'Shared Calendar'),
        ],
      ),
    ); 

    final mobileTopBar = SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: [
            Image.asset(_themedAsset(context, 'assets/logo_final.png'), height: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'LinkUp Calendar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'logout') _logout(context);
                if (v == 'settings') _openSettings();
              },
              itemBuilder:
                  (ctx) => const [
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                    PopupMenuItem(value: 'logout', child: Text('Logout')),
                  ],
            ),
          ],
        ),
      ),
    );

    final mobileBottomNav = NavigationBar(
      selectedIndex: _tabController.index,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.calendar_today),
          label: 'Master Calendar',
        ),
        NavigationDestination(
          icon: Icon(Icons.group),
          label: 'Shared Calendar',
        ),
      ],
      onDestinationSelected: (i) {
        _tabController.index = i;
        setState(() {});
      },
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Pick container/foreground that adapt to light/dark + Material 3
    final bg = scheme.secondaryContainer;
    final fg = scheme.onSecondaryContainer;
    final accent = scheme.secondary; // for the bulb icon

    return WillPopScope(
      onWillPop: () async {
        if (widget.fromInvite) {
          _tabController.animateTo(1);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: isMobile ? null : desktopAppBar,
        bottomNavigationBar: isMobile ? mobileBottomNav : null,
        body: Column(
          children: [
            if (isMobile) mobileTopBar,
            if (_showTutorialCard)
              Card(
                margin: const EdgeInsets.all(16),
                color: bg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb, color: accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Welcome! Use the "+" button to add events.\nSwitch tabs to manage calendars.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: fg,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        icon: Icon(Icons.close, color: fg.withOpacity(0.8)),
                        onPressed:
                            () => setState(() => _showTutorialCard = false),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const MasterCalendarScreen(),
                  SharedCalendarTab(
                    key: _sharedTabKey,
                    calendarId: widget.calendarId,
                    calendarName: widget.calendarName,
                    fromInvite: widget.fromInvite,
                    theme: widget.theme, // pass ThemeController to list
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SharedCalendarTab extends StatefulWidget {
  final String? calendarId;
  final String? calendarName;
  final bool fromInvite;

  /// Pass ThemeController down to the shared list screen.
  final ThemeController theme;

  const SharedCalendarTab({
    super.key,
    this.calendarId,
    this.calendarName,
    this.fromInvite = false,
    required this.theme,
  });

  @override
  State<SharedCalendarTab> createState() => _SharedCalendarTabState();
}

class _SharedCalendarTabState extends State<SharedCalendarTab> {
  String? _activeCalendarId;
  String? _activeCalendarName;

  @override
  void initState() {
    super.initState();
    if (widget.calendarId != null) {
      _activeCalendarId = widget.calendarId;
      _activeCalendarName = widget.calendarName;
    }
  }

  void resetToListView() {
    if (!widget.fromInvite) {
      setState(() {
        _activeCalendarId = null;
        _activeCalendarName = null;
      });
    }
  }

  void _openCalendar(String id, String name) {
    setState(() {
      _activeCalendarId = id;
      _activeCalendarName = name;
    });
  }

  void _goBackToList() {
    setState(() {
      _activeCalendarId = null;
      _activeCalendarName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_activeCalendarId != null) {
      return SharedCalendarScreen(
        calendarId: _activeCalendarId,
        calendarName: _activeCalendarName,
        onBackToList: _goBackToList,
      );
    }
    return SharedCalendarList(onSelect: _openCalendar, theme: widget.theme);
  }
}
