import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    fetchCalendarInfo();
  }

  Future<void> fetchCalendarInfo() async {
    final query =
        await FirebaseFirestore.instance.collection('calendars').get();

    for (final doc in query.docs) {
      final data = doc.data();
      if (data['sharedLinkEdit'] == widget.sharedLinkId ||
          data['sharedLinkView'] == widget.sharedLinkId) {
        calendarName = data['name'];
        calendarId = doc.id;

        final ownerId = data['ownerId'];
        if (ownerId != null) {
          final ownerDoc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(ownerId)
                  .get();
          ownerName =
              ownerDoc.exists
                  ? (ownerDoc.data()?['displayName'] ??
                      ownerDoc.data()?['email'] ??
                      'Anonymous')
                  : 'Anonymous';
        }

        final user = FirebaseAuth.instance.currentUser;
        final prefs = await SharedPreferences.getInstance();
        final guestId = prefs.getString('guestId');
        final currentId = user?.uid ?? guestId;

        final members = List<Map<String, dynamic>>.from(
          (data['members'] ?? []).map((e) => Map<String, dynamic>.from(e)),
        );

        isAlreadyJoined = members.any((m) => m['id'] == currentId);
        memberCount = members.length;

        final canEdit = (data['sharedLinkEdit'] == widget.sharedLinkId);
        await prefs.setBool('editAccess_$calendarId', canEdit);

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
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId');
    final currentId = user?.uid ?? guestId;

    if (calendarId == null || currentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing calendar or user ID.")),
      );
      return;
    }

    try {
      final calendarRef = FirebaseFirestore.instance
          .collection('calendars')
          .doc(calendarId);

      await calendarRef.update({
        'members': FieldValue.arrayUnion([
          {
            'id': currentId,
            'name':
                user == null
                    ? 'Anonymous'
                    : (user.displayName ?? user.email ?? 'User'),
          },
        ]),
      });

      if (user == null && guestId != null) {
        final guestCalendarRef = FirebaseFirestore.instance
            .collection('guests')
            .doc(guestId)
            .collection('sharedCalendars')
            .doc(calendarId);

        await guestCalendarRef.set({
          'calendarName': calendarName,
          'joinedAt': Timestamp.now(),
        });
      }

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
      print("\u274C Failed to join: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error joining calendar: $e")));
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
      body:
          isLoading
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
                    horizontal: 24,
                    vertical: 32,
                  ),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
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
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
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
                      Text(
                        user != null
                            ? "Welcome back, ${user.email ?? 'User'}!"
                            : "You’re currently viewing as a Guest",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 30),

                      // === CONDITIONAL BUTTONS ===
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
                          label: Text(
                            user != null ? "Join Calendar" : "Join as Guest",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3F72AF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        if (user == null)
                          const SizedBox(height: 12), // spacing between buttons
                        OutlinedButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                              'pendingSharedCalendarId',
                              calendarId!,
                            );
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/',
                              (_) => false,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3F72AF),
                            side: const BorderSide(color: Color(0xFF3F72AF)),
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
                  ),
                ),
              ),
    );
  }
}
