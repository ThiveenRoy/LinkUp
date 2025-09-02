// lib/widgets/tutorial_wrapper.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/calendar_home_screen.dart';
import '../screens/onboarding_screen.dart';
// 👇 add this
import '../theme/theme_controller.dart';

class TutorialWrapper extends StatefulWidget {
  final Map<String, dynamic>? args;

  // 👇 add theme controller
  final ThemeController theme;

  const TutorialWrapper({
    super.key,
    this.args,
    required this.theme, // 👈 required
  });

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
    bool seenLocal = prefs.getBool('seenTutorial') ?? false;

    // Optional: if signed-in, trust server flag and sync local
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final seenServer = (snap.data()?['seenTutorial'] == true);
        if (seenServer && !seenLocal) {
          await prefs.setBool('seenTutorial', true);
          seenLocal = true;
        }
      } catch (_) {
        // ignore; fall back to local flag
      }
    }

    if (!mounted) return;
    setState(() {
      _showTutorial = !seenLocal;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_showTutorial) {
      return const OnboardingScreen();
    }

    // 👇 pass the theme controller into CalendarHomeScreen
    return CalendarHomeScreen(
      theme: widget.theme,
      calendarId: widget.args?['calendarId'],
      calendarName: (widget.args?['calendarName'] as String?) ?? 'LinkUp Calendar',
      tabIndex: (widget.args?['tabIndex'] as int?) ?? 0,
      fromInvite: (widget.args?['fromInvite'] as bool?) ?? false,
    );
  }
}
