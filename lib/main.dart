// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:linkup_calendar/theme/theme_bg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/calendar_home_screen.dart';
import 'screens/master_calendar_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/join_calendar_screen.dart';
import 'screens/shared_calendar_screen.dart';

// THEME
import 'theme/theme_controller.dart';
import 'theme/app_theme.dart';

// 👇 add this


Future<String> _computeInitialRoute() async {
  final prefs = await SharedPreferences.getInstance();
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final seenTutorial = prefs.getBool('seenTutorial') ?? false;

  // Respect actual browser URL (Flutter Web)
  final incomingRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  if (incomingRoute.startsWith('/cal/')) {
    return incomingRoute; // deep link to invite
  }

  if (firebaseUser != null) {
    return seenTutorial ? '/calendarHome' : '/onboarding';
  } else {
    return '/';
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final initialRoute = await _computeInitialRoute();

  // Load theming
  final theme = ThemeController();
  await theme.load();

  runApp(MyApp(initialRoute: initialRoute, theme: theme));
}

// Web scroll behavior
class WebScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final ThemeController theme;

  const MyApp({super.key, required this.initialRoute, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme, // rebuild on theme changes (color, mode, wallpaper)
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'LinkUp Calendar',
          scrollBehavior: WebScrollBehavior(),

          // Theme from your controller
          themeMode: theme.themeMode,
          theme: buildLightTheme(theme.seedColor),
          darkTheme: buildDarkTheme(theme.seedColor),

          // 👇 Mount the wallpaper once for the whole app
          builder: (context, child) => ThemeBg(
            controller: theme,
            child: child ?? const SizedBox.shrink(),
          ),

          initialRoute: initialRoute,

          onGenerateRoute: (settings) {
            final uri = Uri.parse(settings.name ?? '');

            // /cal/<sharedLinkId> deep link
            if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'cal') {
              final sharedLinkId = uri.pathSegments[1];
              return MaterialPageRoute(
                builder: (_) => InviteGate(sharedLinkId: sharedLinkId),
                settings: settings,
              );
            }

            if (settings.name == '/calendarHome') {
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (_) => CalendarHomeScreen(
                  theme: theme, // pass controller so Settings can modify it
                  calendarId: args?['calendarId'],
                  calendarName: args?['calendarName'] ?? 'LinkUp Calendar',
                  tabIndex: args?['tabIndex'] ?? 0,
                ),
                settings: settings,
              );
            }

            return null; // allow routes map to handle the rest
          },

          routes: {
            '/': (context) => AuthLandingScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
            '/masterCalendar': (context) => const MasterCalendarScreen(),
            '/sharedCalendar': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              return SharedCalendarScreen(
                calendarId: args?['calendarId'],
                calendarName: args?['calendarName'],
                sharedLinkId: args?['sharedLinkId'],
              );
            },
          },
        );
      },
    );
  }
}

/// Gate for /cal/<sharedLinkId>
class InviteGate extends StatefulWidget {
  final String sharedLinkId;
  const InviteGate({super.key, required this.sharedLinkId});

  @override
  State<InviteGate> createState() => _InviteGateState();
}

class _InviteGateState extends State<InviteGate> {
  @override
  void initState() {
    super.initState();
    _routeFromInvite();
  }

  Future<void> _routeFromInvite() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('pendingInviteId', widget.sharedLinkId);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/'); // go sign in
      return;
    }

    try {
      // Optional prefetch: find the calendarId associated with this link
      final q = await FirebaseFirestore.instance.collection('calendars').get();
      for (final doc in q.docs) {
        final data = doc.data();
        if (data['sharedLinkEdit'] == widget.sharedLinkId ||
            data['sharedLinkView'] == widget.sharedLinkId) {
          final calendarId = doc.id;
          final linkGrantsEdit = (data['sharedLinkEdit'] == widget.sharedLinkId);
          await prefs.setString('pendingSharedCalendarId', calendarId);
          await prefs.setBool('editAccess_$calendarId', linkGrantsEdit);
          break;
        }
      }
    } catch (_) {
      // ignore; Join handles it later
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => JoinCalendarScreen(sharedLinkId: widget.sharedLinkId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
