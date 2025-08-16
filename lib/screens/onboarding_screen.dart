import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Helpers used in your app (ensure the import path matches your project)
import 'package:shared_calendar/utils/guest_helper.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      'image': 'assets/onboarding_0.png',
      'title': 'Welcome to LinkUp',
      'desc': 'Organize your life, your way.',
    },
    {
      'image': 'assets/onboarding_1.png',
      'title': 'Add Events Easily',
      'desc': 'Tap, create, and manage all your events in seconds.',
    },
    {
      'image': 'assets/onboarding_2.png',
      'title': 'Collaborate & Share',
      'desc': 'Share calendars and allow others to edit together.',
    },
  ];

  void _handleNext() {
    if (_currentIndex < _onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenTutorial', true);

    // ✅ Persist onboarding completion for logged-in users so future logins skip tutorial
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(
          {
            'seenTutorial': true,
            'seenTutorialAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        // Non-fatal; continue navigation anyway
      }
    }

    final pendingInviteId = prefs.getString('pendingInviteId');

    if (pendingInviteId != null && pendingInviteId.isNotEmpty) {
      // Try to resolve invite → join → go to shared calendar
      try {
        final joinResult = await _joinCalendarViaInvite(pendingInviteId);

        // clear pending keys to avoid loops
        await prefs.remove('pendingInviteId');
        await prefs.remove('pendingSharedCalendarId');

        if (!mounted) return;
        if (joinResult != null) {
          // Go straight to Shared tab with the joined calendar
          Navigator.pushReplacementNamed(
            context,
            '/calendarHome',
            arguments: {
              'calendarId': joinResult.calendarId,
              'calendarName': joinResult.calendarName,
              'tabIndex': 1,
              'fromInvite': true,
            },
          );
          return;
        } else {
          // If we couldn't resolve/join, fall back to home (Join screen flow will handle if needed)
          Navigator.pushReplacementNamed(context, '/calendarHome');
          return;
        }
      } catch (_) {
        // On any error, still clear and fall back to home
        await prefs.remove('pendingInviteId');
        await prefs.remove('pendingSharedCalendarId');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/calendarHome');
        return;
      }
    }

    // No invite → default behavior
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/calendarHome');
  }

  /// Resolves a shared invite ID to a calendar, adds current user/guest
  /// to the calendar's members, and returns minimal info for navigation.
  Future<_JoinOutcome?> _joinCalendarViaInvite(String sharedLinkId) async {
    // Ensure session (guest or logged-in)
    await ensureAuthSession();

    // Resolve calendar by link
    final q = await FirebaseFirestore.instance.collection('calendars').get();
    DocumentSnapshot<Map<String, dynamic>>? targetDoc;
    bool linkGrantsEdit = false;

    for (final doc in q.docs) {
      final data = doc.data();
      if (data['sharedLinkEdit'] == sharedLinkId ||
          data['sharedLinkView'] == sharedLinkId) {
        targetDoc = doc;
        linkGrantsEdit = (data['sharedLinkEdit'] == sharedLinkId);
        break;
      }
    }
    if (targetDoc == null) return null;

    final data = targetDoc.data()!;
    final calendarId = targetDoc.id;
    final calendarName = (data['name'] ?? 'Shared Calendar').toString();

    // Save link edit flag for later permission checks
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('editAccess_$calendarId', linkGrantsEdit);

    // Add current user/guest as a member (id + name)
    final currentUserId = await getCurrentUserId(); // non-null
    final displayName = (await getCurrentUserName()) ?? 'Anonymous';

    // Normalize existing members to avoid duplicates
    final rawMembers = (data['members'] ?? []) as List<dynamic>;
    final normalizedIds = rawMembers
        .map<String>((m) {
          if (m is String) return m;
          if (m is Map && m['id'] != null) return m['id'].toString();
          return '';
        })
        .where((e) => e.isNotEmpty)
        .toList();

    if (!normalizedIds.contains(currentUserId)) {
      try {
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(calendarId)
            .update({
          'members': FieldValue.arrayUnion([
            {'id': currentUserId, 'name': displayName},
          ]),
        });
      } catch (e) {
        // If field not found, create it with merge
        if (e.toString().contains('NOT_FOUND')) {
          await FirebaseFirestore.instance
              .collection('calendars')
              .doc(calendarId)
              .set({
            'members': [
              {'id': currentUserId, 'name': displayName},
            ],
          }, SetOptions(merge: true));
        } else {
          rethrow;
        }
      }
    }

    // Optionally record guest’s joined calendars
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null || authUser.isAnonymous) {
      await FirebaseFirestore.instance
          .collection('guests')
          .doc(currentUserId)
          .collection('sharedCalendars')
          .doc(calendarId)
          .set({
        'calendarName': calendarName,
        'joinedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }

    return _JoinOutcome(calendarId: calendarId, calendarName: calendarName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _onboardingData.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final item = _onboardingData[index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        item['image']!,
                        height: MediaQuery.of(context).size.height * 0.45,
                        width: MediaQuery.of(context).size.width * 0.7,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        item['title']!,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item['desc']!,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_onboardingData.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: _currentIndex == index ? 20 : 8,
                decoration: BoxDecoration(
                  color: _currentIndex == index
                      ? Colors.deepPurple
                      : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ),

          const SizedBox(height: 24),

          // Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: ElevatedButton.icon(
                  icon: Icon(
                    _currentIndex == _onboardingData.length - 1
                        ? Icons.check
                        : Icons.arrow_forward,
                    color: Colors.white,
                  ),
                  label: Text(
                    _currentIndex == _onboardingData.length - 1
                        ? 'Get Started'
                        : 'Next',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                  onPressed: _handleNext,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    backgroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinOutcome {
  final String calendarId;
  final String calendarName;
  _JoinOutcome({required this.calendarId, required this.calendarName});
}
