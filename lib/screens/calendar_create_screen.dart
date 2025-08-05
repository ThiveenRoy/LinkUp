import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_calendar/utils/guest_helper.dart';
import 'calendar_home_screen.dart';

class CreateCalendarScreen extends StatefulWidget {
  const CreateCalendarScreen({super.key});

  @override
  State<CreateCalendarScreen> createState() => _CreateCalendarScreenState();
}

class _CreateCalendarScreenState extends State<CreateCalendarScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool allowEdit = true;
  bool _creating = false;
  

  String _generateLinkId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _createCalendar() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);

    final currentUserId = await getCurrentUserId();
    final currentUserName = await getCurrentUserName() ?? 'Anonymous';

    final docRef = await FirebaseFirestore.instance.collection('calendars').add({
      'name': name,
      'owner': currentUserId,
      'members': [
        {
          'id': currentUserId,
          'name': currentUserName,
        }
      ],
      'isShared': true,
      'allowEdit': allowEdit,
      'createdAt': Timestamp.now(),
      'sharedLinkEdit': _generateLinkId(),
      'sharedLinkView': _generateLinkId(),
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarHomeScreen(
          tabIndex: 1,
          calendarId: docRef.id,
          calendarName: name,
        ),
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Calendar")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Calendar Name'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _creating ? null : _createCalendar,
              icon: const Icon(Icons.check),
              label: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
