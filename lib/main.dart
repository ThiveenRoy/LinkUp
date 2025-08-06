
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_calendar/screens/join_calendar_screen.dart';
import 'package:shared_calendar/screens/shared_calendar_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

import 'screens/auth_screen.dart';
import 'screens/calendar_home_screen.dart';
import 'screens/master_calendar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  String initialRoute = '/'; // Default route

  final prefs = await SharedPreferences.getInstance();
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final guestId = prefs.getString('guestId');

  if (firebaseUser != null || guestId != null) {
    initialRoute = '/calendarHome';
  }

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LinkUp Calendar',

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

        if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'cal') {
          final sharedLinkId = uri.pathSegments[1];
          return MaterialPageRoute(
            builder: (_) => JoinCalendarScreen(sharedLinkId: sharedLinkId),
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
          );
        }

        return null;
      },

      routes: {
        '/': (context) => AuthLandingScreen(),
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
