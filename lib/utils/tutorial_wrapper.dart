import 'package:flutter/material.dart';
import '../screens/calendar_home_screen.dart';
import '../screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialWrapper extends StatefulWidget {
  final Map<String, dynamic>? args;
  const TutorialWrapper({super.key, this.args});

  @override
  State<TutorialWrapper> createState() => _TutorialWrapperState();
}

class _TutorialWrapperState extends State<TutorialWrapper> {
  bool _loading = true;
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    _checkSeenTutorial();
  }

  Future<void> _checkSeenTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seenTutorial') ?? false;
    setState(() {
      _showTutorial = !seen;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_showTutorial) {
      return const OnboardingScreen();
    }

    return CalendarHomeScreen(
      calendarId: widget.args?['calendarId'],
      calendarName: widget.args?['calendarName'] ?? 'LinkUp Calendar',
      tabIndex: widget.args?['tabIndex'] ?? 0,
    );
  }
}
