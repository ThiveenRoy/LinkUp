import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // web drag support
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/calendar_home_screen.dart';
import 'screens/master_calendar_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/join_calendar_screen.dart';
import 'screens/shared_calendar_screen.dart';

// ✅ Stable anonymous auth + guest name helpers
import 'utils/guest_helper.dart';

Future<String> _computeInitialRoute() async {
  final prefs = await SharedPreferences.getInstance();
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final guestId = prefs.getString('guestId');
  final hasContinuedAsGuest = prefs.getBool('hasContinuedAsGuest') ?? false;
  final seenTutorial = prefs.getBool('seenTutorial') ?? false;

  // Respect actual browser URL (Flutter Web)
  final incomingRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;

  if (incomingRoute.startsWith('/cal/')) {
    return incomingRoute; // deep link to invite
  } else {
    if (firebaseUser != null || (guestId != null && hasContinuedAsGuest)) {
      return seenTutorial ? '/calendarHome' : '/onboarding';
    } else {
      return '/';
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔐 Ensure persistent auth (anonymous if needed) + stable guest name
  await bootstrapAuth();

  // Decide initial route now that auth is ready
  final initialRoute = await _computeInitialRoute();

  runApp(MyApp(initialRoute: initialRoute));
}

// ✅ Web scroll behavior
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
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LinkUp Calendar',
      scrollBehavior: WebScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF9F7F7),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF9F7F7),
          elevation: 0.5,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      initialRoute: initialRoute,

      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');

        // 🔗 /cal/<sharedLinkId> deep link entry
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
              calendarId: args?['calendarId'],
              calendarName: args?['calendarName'] ?? 'LinkUp Calendar',
              tabIndex: args?['tabIndex'] ?? 0,
            ),
            settings: settings,
          );
        }

        return null; // fall back to named routes map below
      },

      routes: {
        '/': (context) => AuthLandingScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/masterCalendar': (context) => MasterCalendarScreen(),
        '/sharedCalendar': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return SharedCalendarScreen(
            calendarId: args?['calendarId'],
            calendarName: args?['calendarName'],
            sharedLinkId: args?['sharedLinkId'],
          );
        },
      },
    );
  }
}

/// A tiny gate that runs when opening /cal/<sharedLinkId>.
/// It ensures the invite is stashed, then ALWAYS goes to JoinCalendarScreen
/// (which handles both new and returning users).
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
    // Make sure we have an auth session before any Firestore reads
    await bootstrapAuth();

    final prefs = await SharedPreferences.getInstance();

    // Stash invite + (optionally) cache calendarId/editAccess for convenience
    await prefs.setString('pendingInviteId', widget.sharedLinkId);

    try {
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
      // ignore; Join/Onboarding handles it later
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
