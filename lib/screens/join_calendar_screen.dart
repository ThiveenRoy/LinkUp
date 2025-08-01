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
  bool isLoading = true;
  bool isAlreadyJoined = false;

  @override
  void initState() {
    super.initState();
    fetchCalendarInfo();
  }

  Future<void> fetchCalendarInfo() async {
    final query = await FirebaseFirestore.instance.collection('calendars').get();

    for (final doc in query.docs) {
      final data = doc.data();
      if (data['sharedLinkEdit'] == widget.sharedLinkId || data['sharedLinkView'] == widget.sharedLinkId) {
        calendarName = data['name'];
        calendarId = doc.id;

        final user = FirebaseAuth.instance.currentUser;
        final prefs = await SharedPreferences.getInstance();
        final guestId = prefs.getString('guestId');
        final currentId = user?.uid ?? guestId;

        final members = List<String>.from(data['members'] ?? []);
        isAlreadyJoined = members.contains(currentId);

        // ✅ Save edit access status in SharedPreferences
        final canEdit = (data['sharedLinkEdit'] == widget.sharedLinkId);
        await prefs.setBool('editAccess_$calendarId', canEdit);

        setState(() => isLoading = false);
        return;
      }
    }

    // If not found
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

    print("📌 joinCalendar called");
    print("calendarId: $calendarId");
    print("guestId: $guestId");
    print("user uid: ${user?.uid}");

    if (calendarId == null || currentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing calendar or user ID.")),
      );
      return;
    }

    try {
      final calendarRef =
          FirebaseFirestore.instance.collection('calendars').doc(calendarId);

      // Add user to members
      await calendarRef.update({
        'members': FieldValue.arrayUnion([currentId])
      });

      // Save guest metadata
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

      // Navigate
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
      print("❌ Failed to join: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error joining calendar: $e")),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Join Calendar")),
        body: isLoading
      ? const Center(child: CircularProgressIndicator())
      : calendarName == null
          ? const Center(child: Text("Invalid calendar link."))
          : Center( // <-- Center everything
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Center vertically
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "You’ve been invited to join \"$calendarName\"",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      user != null
                          ? "Welcome back, ${user.email ?? 'User'}!"
                          : "You’re currently viewing as a Guest",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    if (isAlreadyJoined)
                      ElevatedButton(
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
                        child: Text('Go to Calendar'),
                      )
                    else ...[
                      ElevatedButton(
                        onPressed: joinCalendar,
                        child: Text(user != null
                            ? "Join Calendar"
                            : "Join as Guest"),
                      ),
                      if (user == null)
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamedAndRemoveUntil(
                                context, '/', (_) => false);
                          },
                          child: const Text("Log in instead"),
                        ),
                    ],
                  ],
                ),
              ),
            ),

    );
  }
}
