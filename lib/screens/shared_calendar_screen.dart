import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../utils/guest_helper.dart';

class SharedCalendarScreen extends StatefulWidget {
  final String? calendarId;
  final String? calendarName;
  final String? sharedLinkId;
  final VoidCallback? onBackToList;

  const SharedCalendarScreen({super.key, this.calendarId, this.calendarName,this.sharedLinkId,this.onBackToList,});

  @override
  State<SharedCalendarScreen> createState() => _SharedCalendarScreenState();
}

class _SharedCalendarScreenState extends State<SharedCalendarScreen> {
  late Future<String> _userIdFuture;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _eventsByDay = {};
  String? _currentUserId;
  Map<String, dynamic>? _calendarData;
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _userIdFuture = getCurrentUserId();
    _selectedDay = _focusedDay;
    _loadPermissions();

    _userIdFuture.then((id) {
      _currentUserId = id;
      if (widget.calendarId != null) {
        _loadEvents();
        _loadCalendarDetails();
      }
    });
  }

  Future<void> _loadPermissions() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId');
    final currentId = user?.uid ?? guestId;

    final doc = await FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .get();

    final data = doc.data();
    if (data == null) return;

    final ownerId = data['owner'];
    final allowEdit = data['allowEdit'] ?? false;

    final isOwner = currentId == ownerId;
    final hasGuestEditAccess = prefs.getBool('editAccess_${widget.calendarId}') ?? false;

    setState(() {
      _canEdit = isOwner || (allowEdit && hasGuestEditAccess);
    });
  }


  void _loadCalendarDetails() async {
    final doc = await FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).get();
    if (doc.exists) {
      setState(() {
        _calendarData = doc.data();
      });
    }
  }

  void _loadEvents() async {
    if (widget.calendarId == null) return;

    final eventsRef = FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .collection('events');

    try {
      final query = await eventsRef.get();

      final tempEvents = <DateTime, List<Map<String, dynamic>>>{};

      for (var doc in query.docs) {
        final data = doc.data();
        if (data.containsKey('startTime')) {
          final startTime = (data['startTime'] as Timestamp).toDate();
          final dateOnly = DateTime(startTime.year, startTime.month, startTime.day);
          final calendarSnap = await FirebaseFirestore.instance
              .collection('calendars')
              .doc(widget.calendarId)
              .get();

          final calendarData = calendarSnap.data();
          final calendarName = calendarData?['name'] ?? 'Shared';
          final ownerId = calendarData?['owner'];

          final isFromOther = ownerId != _currentUserId;

          tempEvents.putIfAbsent(dateOnly, () => []).add({
            ...data,
            'id': doc.id,
            'calendarName': isFromOther ? calendarName : '',
          });
        }
      }

      setState(() {
        _eventsByDay = tempEvents;
      });
    } catch (e) {
      setState(() {
        _eventsByDay = {}; // still allow calendar to render
      });
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _eventsByDay[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _showShareModal(String calendarId) async {
    final calendarDoc =
        await FirebaseFirestore.instance.collection('calendars').doc(calendarId).get();

    final data = calendarDoc.data();
    if (data == null ||
        (!data.containsKey('sharedLinkEdit') && !data.containsKey('sharedLinkView'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to generate invite link.')),
      );
      return;
    }

    bool allowEdit = data['allowEdit'] ?? false;
    String editLink = 'http://localhost:5000/#/cal/${data['sharedLinkEdit']}';
    String viewLink = 'http://localhost:5000/#/cal/${data['sharedLinkView']}';

    final TextEditingController linkController = TextEditingController(
      text: allowEdit ? editLink : viewLink,
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Share Calendar'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: linkController,
                  readOnly: true,
                  onTap: () => linkController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: linkController.text.length,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Invite Link',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: linkController.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied to clipboard')),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('Allow collaborators to edit'),
                  value: allowEdit,
                  onChanged: (value) async {
                    await FirebaseFirestore.instance
                        .collection('calendars')
                        .doc(calendarId)
                        .update({'allowEdit': value});
                    setModalState(() {
                      allowEdit = value;
                      linkController.text = value ? editLink : viewLink;
                    });
                  },
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        });
      },
    );
  }


      @override
    Widget build(BuildContext context) {
      if (widget.calendarId != null) {
        return Scaffold(
          appBar: AppBar(
            leading: widget.onBackToList != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBackToList,
              )
            : null,
            title: Text(widget.calendarName ?? 'Shared Calendar'),
            actions: [
              if (_canEdit)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addEventDialog,
                ),
              if (_calendarData != null && _calendarData!['owner'] == _currentUserId)
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => _showShareModal(widget.calendarId!),
                ),
            ],
          ),
          body: Column(
            children: [
              TableCalendar(
                firstDay: DateTime(2000),
                lastDay: DateTime(2100),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                eventLoader: _getEventsForDay,
                calendarStyle: const CalendarStyle(
                  markerDecoration: BoxDecoration(color: Colors.purple, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Events On: ${_selectedDay!.toLocal().toString().split(' ')[0]}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _getEventsForDay(_selectedDay!).isEmpty
                    ? const Center(child: Text("No events found."))
                    : ListView(
                        children: _getEventsForDay(_selectedDay!).map((event) {
                          return ListTile(
                            title: Text(
                              (event['calendarName'] != null &&
                                      event['calendarName'].toString().isNotEmpty)
                                  ? '${event['title']} (${event['calendarName']})'
                                  : event['title'],
                            ),
                            subtitle: Text((event['startTime'] as Timestamp).toDate().toString()),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_canEdit)
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editEvent(event),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteEvent(event),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      }

      // ✅ Fallback return if calendarId is null
      return const Scaffold(
        body: Center(
          child: Text("No calendar selected."),
        ),
      );
    }


  Future<void> _addEventDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime startTime = _selectedDay ?? DateTime.now();
    DateTime endTime = startTime;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Add Event'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    ListTile(
                      title: const Text('Start Date'),
                      subtitle: Text(startTime.toString()),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startTime,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setModalState(() => startTime = picked);
                      },
                    ),
                    ListTile(
                      title: const Text('End Date'),
                      subtitle: Text(endTime.toString()),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endTime,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setModalState(() => endTime = picked);
                      },
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('calendars')
                        .doc(widget.calendarId)
                        .collection('events')
                        .add({
                      'title': titleController.text,
                      'description': descriptionController.text,
                      'startTime': startTime,
                      'endTime': endTime,
                    });
                    Navigator.pop(context);
                    _loadEvents();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editEvent(Map<String, dynamic> event) async {
    final titleController = TextEditingController(text: event['title'] ?? '');
    final descriptionController = TextEditingController(text: event['description'] ?? '');
    DateTime startTime = (event['startTime'] as Timestamp).toDate();
    DateTime endTime = (event['endTime'] as Timestamp).toDate();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Event'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              ListTile(
                title: const Text('Start Date'),
                subtitle: Text(startTime.toLocal().toString().split(' ')[0]),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startTime,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      startTime = picked;
                    });
                  }
                },
              ),
              ListTile(
                title: const Text('End Date'),
                subtitle: Text(endTime.toLocal().toString().split(' ')[0]),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: endTime,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      endTime = picked;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (_canEdit)
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('calendars')
                    .doc(widget.calendarId)
                    .collection('events')
                    .doc(event['id'])
                    .update({
                  'title': titleController.text.trim(),
                  'description': descriptionController.text.trim(),
                  'startTime': Timestamp.fromDate(startTime),
                  'endTime': Timestamp.fromDate(endTime),
                  'creatorId': _currentUserId,
                });
                Navigator.pop(context);
                _loadEvents();
              },
              child: const Text('Save'),
            ),
        ],
      ),
    );
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
          .doc(widget.calendarId)
          .collection('events')
          .doc(event['id'])
          .delete();
      _loadEvents();
    }
  }
}
