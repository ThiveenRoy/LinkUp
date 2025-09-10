import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Use the *base* asset names. We'll auto-switch to `_dark` variants.
  final List<Map<String, String>> _onboardingData = const [
    {
      'image': 'assets/onboarding_0.png',
      'title': 'Welcome to LinkUp',
      'desc': 'Organize your life, your way.'
    },
    {
      'image': 'assets/onboarding_1.png',
      'title': 'Add Events Easily',
      'desc': 'Tap, create, and manage events fast.'
    },
    {
      'image': 'assets/onboarding_2.png',
      'title': 'Collaborate & Share',
      'desc': 'Share calendars and co-edit.'
    },
  ];

  @override
  void initState() {
    super.initState();
    // If someone reached here unauthenticated, bounce to auth.
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
        }
      });
    }
  }

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

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'seenTutorial': true,
          'seenTutorialAt': FieldValue.serverTimestamp(),
          'displayName': user.displayName,
          'email': user.email,
        }, SetOptions(merge: true));
      } catch (_) {
        // non-fatal
      }
    }

    final pendingInviteId = prefs.getString('pendingInviteId');
    if (pendingInviteId != null && pendingInviteId.isNotEmpty) {
      try {
        final joinResult = await _joinCalendarViaInvite(pendingInviteId);
        await prefs.remove('pendingInviteId');
        await prefs.remove('pendingSharedCalendarId');

        if (!mounted) return;
        if (joinResult != null) {
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
        }
      } catch (_) {
        await prefs.remove('pendingInviteId');
        await prefs.remove('pendingSharedCalendarId');
      }
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/calendarHome');
  }

  /// Resolve invite → add the **signed-in** user as member → return minimal info.
  Future<_JoinOutcome?> _joinCalendarViaInvite(String sharedLinkId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null; // must be logged in

    // Look up the calendar by link (edit or view)
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

    // Add user as member if not already there
    final uid = user.uid;
    final displayName = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim()
        : (user.email?.trim().isNotEmpty == true
            ? user.email!.trim()
            : 'User');

    final rawMembers = (data['members'] ?? []) as List<dynamic>;
    final memberIds = rawMembers
        .map<String>((m) {
          if (m is String) return m;
          if (m is Map && m['id'] != null) return m['id'].toString();
          return '';
        })
        .where((e) => e.isNotEmpty)
        .toList();

    if (!memberIds.contains(uid)) {
      try {
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(calendarId)
            .update({
          'members': FieldValue.arrayUnion([
            {'id': uid, 'name': displayName}
          ]),
          'memberIds': FieldValue.arrayUnion([uid]),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
          'updatedByName': displayName,
        });
      } catch (e) {
        if (e.toString().contains('NOT_FOUND')) {
          await FirebaseFirestore.instance
              .collection('calendars')
              .doc(calendarId)
              .set({
            'members': [
              {'id': uid, 'name': displayName}
            ],
            'memberIds': [uid],
            'lastUpdatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
            'updatedByName': displayName,
          }, SetOptions(merge: true));
        } else {
          rethrow;
        }
      }
    }

    // Optional: remember link’s edit flag locally if other parts of the app read it
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('editAccess_$calendarId', linkGrantsEdit);

    return _JoinOutcome(calendarId: calendarId, calendarName: calendarName);
  }

  /// Returns the themed version of an asset (e.g., `onboarding_0_dark.png`) when in dark mode.
  String _themedAsset(BuildContext context, String path) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return path;
    final dot = path.lastIndexOf('.');
    if (dot <= 0) return path;
    final base = path.substring(0, dot);
    final ext = path.substring(dot);
    return '${base}_dark$ext';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final titleStyle = theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold);

    final descStyle = theme.textTheme.bodyMedium?.copyWith(
          // onSurfaceVariant has good contrast for both light & dark.
          color: cs.onSurfaceVariant,
        ) ??
        TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.7));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _onboardingData.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (_, i) {
                  final item = _onboardingData[i];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Auto-pick _dark image when theme is dark.
                        Image.asset(
                          _themedAsset(context, item['image']!),
                          height: MediaQuery.of(context).size.height * 0.45,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 32),
                        Text(item['title']!, style: titleStyle, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(item['desc']!, style: descStyle, textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Page dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_onboardingData.length, (i) {
                final selected = _currentIndex == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: selected ? 20 : 8,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary
                        : theme.colorScheme.onSurface.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            // Next / Get Started Button
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
                    ),
                    label: Text(
                      _currentIndex == _onboardingData.length - 1
                          ? 'Get Started'
                          : 'Next',
                    ),
                    onPressed: _handleNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary, // icon & text
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: isDark ? 0 : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinOutcome {
  final String calendarId;
  final String calendarName;
  _JoinOutcome({required this.calendarId, required this.calendarName});
}
