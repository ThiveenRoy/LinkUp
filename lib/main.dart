import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_calendar/screens/join_calendar_screen.dart';
import 'package:shared_calendar/screens/shared_calendar_screen.dart';
import 'package:shared_calendar/utils/guest_helper.dart';
import 'firebase_options.dart';

import 'screens/auth_screen.dart';
import 'screens/calendar_create_screen.dart';
import 'screens/calendar_home_screen.dart';
import 'screens/master_calendar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await getCurrentUserId();
  runApp(MyApp());

}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LinkUp Calendar',
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');

        // ✅ Handle calendar invite links like /cal/abc123
        if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'cal') {
          final sharedLinkId = uri.pathSegments[1];
          return MaterialPageRoute(
            builder: (_) => JoinCalendarScreen(sharedLinkId: sharedLinkId),
          );
        }

        // ✅ Handle /calendarHome with arguments
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

        return null; // fallback to routes
      },


      routes: {
        '/': (context) => AuthScreen(),
        '/createCalendar': (context) => CreateCalendarScreen(),
        '/masterCalendar': (context) => MasterCalendarScreen(),
        '/sharedCalendar': (context) => SharedCalendarScreen(),
        // '/calendar' is handled in onGenerateRoute
        // '/createEvent' is handled in onGenerateRoute
      },
    );
  }
}
