import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/guest_helper.dart';
import '../screens/calendar_home_screen.dart';

void showCreateCalendarDialog(BuildContext context) {
  final TextEditingController _nameController = TextEditingController();
  String? _errorText;
  bool _creating = false;

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Create New Calendar", style: TextStyle(fontWeight: FontWeight.bold)),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8), // space below title
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Calendar Name',
                      border: const OutlineInputBorder(),
                      errorText: _errorText,
                    ),
                  ),
                  const SizedBox(height: 24), // space before buttons
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton.icon(
                onPressed: _creating
                    ? null
                    : () async {
                        final name = _nameController.text.trim();
                        if (name.isEmpty) {
                          setState(() => _errorText = "Please enter a calendar name");
                          return;
                        }

                        setState(() {
                          _creating = true;
                          _errorText = null;
                        });

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
                          'allowEdit': true,
                          'createdAt': Timestamp.now(),
                          'lastUpdatedAt': Timestamp.now(),
                          'updatedBy': currentUserId,
                          'updatedByName': currentUserName,
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
                      },
                icon: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: const Text("Create"),
              ),
            ],
          );
        },
      );
    },
  );
}


String _generateLinkId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
}
