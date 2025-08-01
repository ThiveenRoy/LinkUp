
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_calendar/utils/guest_helper.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MasterCalendarScreen extends StatefulWidget {
  const MasterCalendarScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MasterCalendarScreenState createState() => _MasterCalendarScreenState();
}

class _MasterCalendarScreenState extends State<MasterCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ensureUserHasMasterCalendar().then((_) => _loadEvents());
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
  final confirmed = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Event'),
      content: const Text('Are you sure you want to delete this event?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await FirebaseFirestore.instance
        .collection('calendars')
        .doc(event['calendarId'])
        .collection('events')
        .doc(event['id'])
        .delete();
    _loadEvents();
  }
}

  Future<void> ensureUserHasMasterCalendar() async {
    final userId = await getCurrentUserId();
    final query = await FirebaseFirestore.instance
        .collection('calendars')
        .where('owner', isEqualTo: userId)
        .where('isShared', isEqualTo: false)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      await FirebaseFirestore.instance.collection('calendars').add({
        'name': 'My Calendar',
        'owner': userId,
        'members': [userId],
        'isShared': false,
        'createdAt': Timestamp.now(),
      });
    }
  }


  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = user?.uid ?? prefs.getString('guestId');

    final calendarQuery = await FirebaseFirestore.instance
        .collection('calendars')
        .get();

    Map<DateTime, List<Map<String, dynamic>>> tempEvents = {};

    for (final doc in calendarQuery.docs) {
      final calendarId = doc.id;
      final isShared = doc['isShared'] ?? false;
      final calendarName = doc['name'] ?? 'Shared Calendar';
      final members = List<String>.from(doc['members'] ?? []);
      final isOwner = doc['owner'] == currentUserId;

      // ✅ Skip calendars the user isn't a member of
      if (!members.contains(currentUserId)) continue;

      final eventsSnap = await FirebaseFirestore.instance
          .collection('calendars')
          .doc(calendarId)
          .collection('events')
          .get();

      for (final eventDoc in eventsSnap.docs) {
        final data = eventDoc.data();
        final date = (data['startTime'] as Timestamp).toDate();
        final dateOnly = DateTime(date.year, date.month, date.day);

        // ✅ NEW: Only filter if it's NOT shared
        if (!isShared && !isOwner) continue;

        // ✅ Add calendar name to title for clarity
        final title = isShared
            ? '${data['title']} ($calendarName)'
            : data['title'];

        tempEvents[dateOnly] ??= [];
        tempEvents[dateOnly]!.add({
          ...data,
          'id': eventDoc.id,
          'calendarId': calendarId,
          'title': title,
        });
      }
    }

    setState(() {
      _events = tempEvents;
      _loading = false;
    });
  }




  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _showEventDialog({Map<String, dynamic>? event}) {
    DateTime selectedStart = event?['startTime']?.toDate() ?? _selectedDay;
    DateTime selectedEnd = event?['endTime']?.toDate() ?? _selectedDay;


    final TextEditingController titleController =
        TextEditingController(text: event?['title'] ?? '');
    final TextEditingController descriptionController =
        TextEditingController(text: event?['description'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(event == null ? 'Add Event' : 'Edit Event'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      title: const Text('Start Date'),
                      subtitle: Text(selectedStart.toString()),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedStart,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setModalState(() => selectedStart = picked);
                        }
                      },
                    ),
                    ListTile(
                      title: const Text('End Date'),
                      subtitle: Text(selectedEnd.toString()),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedEnd,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setModalState(() => selectedEnd = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    final prefs = await SharedPreferences.getInstance();
                    final currentUserId = user?.uid ?? prefs.getString('guestId');

                    // 🔧 Try to find existing personal calendar
                    var calendarsSnap = await FirebaseFirestore.instance
                        .collection('calendars')
                        .where('owner', isEqualTo: currentUserId)
                        .where('isShared', isEqualTo: false)
                        .get();

                    String personalCalendarId;

                    if (calendarsSnap.docs.isEmpty) {
                      // ✅ Auto-create personal calendar
                      final doc = await FirebaseFirestore.instance.collection('calendars').add({
                        'name': 'My Calendar',
                        'owner': currentUserId,
                        'members': [currentUserId],
                        'isShared': false,
                        'createdAt': Timestamp.now(),
                      });
                      personalCalendarId = doc.id;
                    } else {
                      personalCalendarId = calendarsSnap.docs.first.id;
                    }

                    if (event == null) {
                      // Add new event
                      await FirebaseFirestore.instance
                          .collection('calendars')
                          .doc(personalCalendarId)
                          .collection('events')
                          .add({
                        'title': titleController.text,
                        'description': descriptionController.text,
                        'startTime': Timestamp.fromDate(selectedStart),
                        'endTime': Timestamp.fromDate(selectedEnd),
                      });
                    } else {
                      // Update existing event
                      await FirebaseFirestore.instance
                          .collection('calendars')
                          .doc(event['calendarId'])
                          .collection('events')
                          .doc(event['id'])
                          .update({
                        'title': titleController.text,
                        'description': descriptionController.text,
                        'startTime': Timestamp.fromDate(selectedStart),
                        'endTime': Timestamp.fromDate(selectedEnd),
                      });
                    }

                    Navigator.pop(context);
                    _loadEvents();
                  },

                  child: const Text('Save'),
                ),

              ],
            );
          },
        );
      },
    );

  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2000),
                lastDay: DateTime.utc(2100),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                calendarFormat: CalendarFormat.month,
                eventLoader: _getEventsForDay,
              ),
              const SizedBox(height: 16),
              Text(
                'Events On: ${_selectedDay.toLocal().toString().split(' ')[0]}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () => _showEventDialog(),
                child: const Text('Add Event'),
              ),
              ..._getEventsForDay(_selectedDay).map((event) => ListTile(
                    title: Text(event['title'] ?? 'No Title'),
                    subtitle: Text(event['description'] ?? ''),
                   trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEventDialog(event: event),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteEvent(event),
                      ),
                    ],
                  ),
                  )),
            ],
          );
  }
}
