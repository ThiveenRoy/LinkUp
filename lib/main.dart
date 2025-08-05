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

      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0.5,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      themeMode: ThemeMode.system, // 🔁 Auto switch based on system settings

      initialRoute: '/',
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
        '/createCalendar': (context) => CreateCalendarScreen(),
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
