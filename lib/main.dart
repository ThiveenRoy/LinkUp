import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // web drag support
import 'package:firebase_core/firebase_core.dart';
import '../screens/join_calendar_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/shared_calendar_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/calendar_home_screen.dart';
import 'screens/master_calendar_screen.dart';

// If you use guest helpers elsewhere, import them here if needed
// import 'package:shared_calendar/utils/guest_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final prefs = await SharedPreferences.getInstance();
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final guestId = prefs.getString('guestId');
  final hasContinuedAsGuest = prefs.getBool('hasContinuedAsGuest') ?? false;
  final seenTutorial = prefs.getBool('seenTutorial') ?? false;

  // Respect the actual browser URL (very important on Flutter Web)
  final incomingRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;

  String initialRoute;
  if (incomingRoute.startsWith('/cal/')) {
    // Deep link to invite should be honored
    initialRoute = incomingRoute;
  } else {
    // Your previous logic for non-invite entry
    if (firebaseUser != null || (guestId != null && hasContinuedAsGuest)) {
      initialRoute = seenTutorial ? '/calendarHome' : '/onboarding';
    } else {
      initialRoute = '/';
    }
  }

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

        // 🔗 /cal/<sharedLinkId> entry point
        if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'cal') {
          final sharedLinkId = uri.pathSegments[1];
          // Use a small gate widget to stash invite + decide where to go
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
/// It ensures the invite is stashed, then:
/// - if first-time (no tutorial) → go to Onboarding
/// - else → go straight to JoinCalendarScreen
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

    // Stash invite + (optionally) cache calendarId/editAccess
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
    // ✅ Always show Join first (new OR returning users)
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

