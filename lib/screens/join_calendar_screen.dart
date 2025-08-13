import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ⬇️ Make sure this import matches your project structure
import '../utils/guest_helper.dart'; // or: package:shared_calendar/utils/guest_helper.dart

class JoinCalendarScreen extends StatefulWidget {
  final String sharedLinkId;

  const JoinCalendarScreen({super.key, required this.sharedLinkId});

  @override
  State<JoinCalendarScreen> createState() => _JoinCalendarScreenState();
}

class _JoinCalendarScreenState extends State<JoinCalendarScreen> {
  String? calendarName;
  String? calendarId;
  String? ownerName;
  int memberCount = 0;
  bool isLoading = true;
  bool isAlreadyJoined = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // ✅ Make sure we have an auth session (anonymous or signed-in)
    await ensureAuthSession();
    await fetchCalendarInfo();
  }

  Future<void> fetchCalendarInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final currentId = await getCurrentUserId(); // guaranteed non-null

    // Find the calendar by shared link id
    final query = await FirebaseFirestore.instance.collection('calendars').get();

    for (final doc in query.docs) {
      final data = doc.data();
      if (data['sharedLinkEdit'] == widget.sharedLinkId ||
          data['sharedLinkView'] == widget.sharedLinkId) {
        calendarName = (data['name'] ?? '').toString();
        calendarId = doc.id;

        // Owner field in your other screens is 'owner' (not 'ownerId'), so handle both
        final ownerId = (data['owner'] ?? data['ownerId'])?.toString();
        if (ownerId != null && ownerId.isNotEmpty) {
          final ownerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(ownerId)
              .get();
          ownerName = ownerDoc.exists
              ? (ownerDoc.data()?['displayName'] ??
                  ownerDoc.data()?['email'] ??
                  'Anonymous')
              : 'Anonymous';
        }

        // Members can be strings or maps in your data model; handle both safely
        final rawMembers = (data['members'] ?? []) as List<dynamic>;
        final normalized = rawMembers.map<String>((m) {
          if (m is String) return m;
          if (m is Map && m['id'] != null) return m['id'].toString();
          return '';
        }).where((e) => e.isNotEmpty).toList();

        isAlreadyJoined = normalized.contains(currentId);
        memberCount = rawMembers.length;

        // Save whether this link grants edit access
        final canEditViaLink = (data['sharedLinkEdit'] == widget.sharedLinkId);
        await prefs.setBool('editAccess_$calendarId', canEditViaLink);

        setState(() => isLoading = false);
        return;
      }
    }

    setState(() {
      calendarName = null;
      isLoading = false;
    });
  }

  Future<void> joinCalendar() async {
    // Ensure (again) we have an auth/guest session in case user waited long or reloaded
    await ensureAuthSession();

    final user = FirebaseAuth.instance.currentUser;
    final currentId = await getCurrentUserId(); // non-null
    final displayName = (await getCurrentUserName()) ?? 'Anonymous';

    if (calendarId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing calendar ID.")),
      );
      return;
    }

    try {
      final calendarRef =
          FirebaseFirestore.instance.collection('calendars').doc(calendarId);

      // Use arrayUnion on a small member object (id+name).
      await calendarRef.update({
        'members': FieldValue.arrayUnion([
          {'id': currentId, 'name': displayName},
        ]),
      });

      // Optional: record guest’s joined calendars for your UX
      if (user == null || (user.isAnonymous)) {
        final guestId = currentId; // our helper returns uid or local id
        await FirebaseFirestore.instance
            .collection('guests')
            .doc(guestId)
            .collection('sharedCalendars')
            .doc(calendarId)
            .set({
          'calendarName': calendarName,
          'joinedAt': Timestamp.now(),
        });
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/calendarHome',
        arguments: {
          'calendarId': calendarId,
          'calendarName': calendarName,
          'tabIndex': 1,
          'fromInvite': true,
        },
      );
    } catch (e) {
      // If members doesn't exist yet, create it
      if (e.toString().contains('NOT_FOUND')) {
        try {
          await FirebaseFirestore.instance
              .collection('calendars')
              .doc(calendarId)
              .set({
            'members': [
              {'id': currentId, 'name': displayName},
            ],
          }, SetOptions(merge: true));

          if (!mounted) return;
          Navigator.pushReplacementNamed(
            context,
            '/calendarHome',
            arguments: {
              'calendarId': calendarId,
              'calendarName': calendarName,
              'tabIndex': 1,
              'fromInvite': true,
            },
          );
          return;
        } catch (_) {}
      }

      debugPrint("❌ Failed to join: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error joining calendar: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FB),
      appBar: AppBar(
        title: const Text("Join Calendar"),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        foregroundColor: Colors.black,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : calendarName == null
              ? const Center(
                  child: Text(
                    "Invalid calendar link.",
                    style: TextStyle(fontSize: 16, color: Colors.redAccent),
                  ),
                )
              : Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_month,
                          size: 48,
                          color: Color(0xFF3F72AF),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isAlreadyJoined
                              ? "You're already a member of"
                              : "You've been invited to join",
                          style:
                              TextStyle(fontSize: 16, color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: [
                            Text(
                              '"$calendarName"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF112D4E),
                              ),
                            ),
                            if (ownerName != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Created by $ownerName',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                "$memberCount member${memberCount > 1 ? 's' : ''} in this calendar",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        FutureBuilder<String?>(
                          future: getCurrentUserName(),
                          builder: (_, snap) {
                            final name = snap.data;
                            return Text(
                              (user != null && !(user.isAnonymous))
                                  ? "Welcome back, ${name ?? user.email ?? 'User'}!"
                                  : "You’re currently viewing as ${name ?? 'Guest'}",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            );
                          },
                        ),
                        const SizedBox(height: 30),

                        // === Buttons ===
                        if (isAlreadyJoined) ...[
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pushReplacementNamed(
                                context,
                                '/calendarHome',
                                arguments: {
                                  'calendarId': calendarId,
                                  'calendarName': calendarName,
                                  'tabIndex': 1,
                                  'fromInvite': true,
                                },
                              );
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Show Calendar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3F72AF),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: joinCalendar,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(
                                (user != null && !(user.isAnonymous))
                                    ? "Join Calendar"
                                    : "Join as Guest"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3F72AF),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          if (user == null || user.isAnonymous) ...[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setString(
                                    'pendingSharedCalendarId', calendarId!);
                                if (!mounted) return;
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/',
                                  (_) => false,
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF3F72AF),
                                side: const BorderSide(
                                    color: Color(0xFF3F72AF)),
                                backgroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "Log in instead",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF3F72AF),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }
}
