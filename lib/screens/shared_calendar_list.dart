import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'calendar_create_screen.dart';

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

    final allCalendars =
        await FirebaseFirestore.instance
            .collection('calendars')
            .where('isShared', isEqualTo: true)
            .get();

    final joinedCalendars =
        allCalendars.docs.where((doc) {
          final members = List<Map<String, dynamic>>.from(
            (doc['members'] ?? []).map((e) => Map<String, dynamic>.from(e)),
          );
          return members.any((m) => m['id'] == currentId);
        }).toList();

    return joinedCalendars.map((doc) {
      final lastUpdated = doc['lastUpdatedAt'] as Timestamp?;
      return {
        'id': doc.id,
        'name': doc['name'],
        'lastUpdatedAt': lastUpdated,
        'updatedByName': doc['updatedByName'] ?? 'Someone',
        'updatedBy': doc['updatedBy'] ?? '',
        'ownerId': doc['owner'] ?? '',
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F7),
      appBar: AppBar(
        title: const Text('Shared Calendars'),
        backgroundColor: const Color(0xFFDBE2EF),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        elevation: 2,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchJoinedCalendars(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final calendars = snapshot.data ?? [];

          if (calendars.isEmpty) {
            return const Center(
              child: Text(
                'No shared calendars yet.',
                style: TextStyle(fontSize: 16, color: Colors.black),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: calendars.length,
            itemBuilder: (context, index) {
              final calendar = calendars[index];
              final lastUpdated = calendar['lastUpdatedAt'] as Timestamp?;
              final formattedTime =
                  lastUpdated != null
                      ? DateFormat('hh:mm a').format(
                        lastUpdated.toDate(),
                      ) // 12-hour format with AM/PM
                      : 'N/A';

              final updatedBy = calendar['updatedByName'] ?? 'Someone';
              final updatedById = calendar['updatedBy'] ?? '';
              final ownerId = calendar['ownerId'] ?? '';
              final isOwner = updatedById == ownerId;

              final subtitleText =
                  'Updated on $formattedTime by $updatedBy${isOwner ? ' (Owner)' : ''}';

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  title: Text(
                    calendar['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF112D4E),
                    ),
                  ),
                  subtitle: Text(
                    subtitleText,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF3F72AF),
                  ),
                  onTap:
                      () => widget.onSelect(calendar['id'], calendar['name']),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateCalendarDialog(context),
        label: const Text('Create'),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFFDBE2EF),
      ),
    );
  }
}
