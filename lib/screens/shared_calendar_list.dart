import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'calendar_create_screen.dart'; // Make sure to import this

class SharedCalendarList extends StatefulWidget {
  final Function(String calendarId, String calendarName) onSelect;

  const SharedCalendarList({super.key, required this.onSelect});

  @override
  State<SharedCalendarList> createState() => _SharedCalendarListState();
}

class _SharedCalendarListState extends State<SharedCalendarList> {
  Future<List<Map<String, dynamic>>> fetchJoinedCalendars() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId');
    final currentId = user?.uid ?? guestId;

    final query = await FirebaseFirestore.instance
        .collection('calendars')
        .where('members', arrayContains: currentId)
        .where('isShared', isEqualTo: true)
        .get();

    return query.docs
        .map((doc) => {'id': doc.id, 'name': doc['name']})
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared Calendars')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchJoinedCalendars(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final calendars = snapshot.data ?? [];

          if (calendars.isEmpty) {
            return const Center(child: Text('No shared calendars yet.'));
          }

          return ListView.builder(
            itemCount: calendars.length,
            itemBuilder: (context, index) {
              final calendar = calendars[index];
              return ListTile(
                title: Text(calendar['name']),
                subtitle: Text('ID: ${calendar['id']}'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => widget.onSelect(calendar['id'], calendar['name']),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateCalendarScreen()),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Create New Calendar',
      ),
    );
  }
}
