// 🔄 Full updated SharedCalendarScreen with UI synced from MasterCalendarScreen

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../utils/guest_helper.dart';

class SharedCalendarScreen extends StatefulWidget {
  final String? calendarId;
  final String? calendarName;
  final String? sharedLinkId;
  final VoidCallback? onBackToList;

  const SharedCalendarScreen({
    super.key,
    this.calendarId,
    this.calendarName,
    this.sharedLinkId,
    this.onBackToList,
  });

  @override
  State<SharedCalendarScreen> createState() => _SharedCalendarScreenState();
}

class _SharedCalendarScreenState extends State<SharedCalendarScreen> {
  late Future<String> _userIdFuture;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _eventsByDay = {};
  Map<String, Color> _eventColors = {};
  String? _currentUserId;
  Map<String, dynamic>? _calendarData;
  bool _canEdit = false;
  List<Map<String, String>> _participants = [];

  final Color bgColor = const Color(0xFFF9F7F7);
  final Color lightCard = const Color(0xFFDBE2EF);
  final Color buttonColor = const Color(0xFF3F72AF);
  final Color textDark = const Color(0xFF112D4E);

  @override
  void initState() {
    super.initState();
    _userIdFuture = getCurrentUserId();
    _userIdFuture.then((id) {
      _currentUserId = id;
      if (widget.calendarId != null) {
        _loadPermissions();
        _loadCalendarDetails();
        _loadEvents();
        _loadMembers();
      }
    });
  }

  Future<void> _loadMembers() async {
    final doc =
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(widget.calendarId)
            .get();
    final data = doc.data();
    if (data == null) return;

    List<dynamic> members = data['members'] ?? [];
    setState(() {
      _participants =
          members.map<Map<String, String>>((e) {
            return {'id': e['id'] ?? '', 'name': e['name'] ?? 'Anonymous'};
          }).toList();
    });
  }

  Future<bool> getSyncToMasterPreference(
    String calendarId,
    String userId,
  ) async {
    final doc =
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(calendarId)
            .collection('memberPrefs')
            .doc(userId)
            .get();
    return doc.data()?['syncToMaster'] ?? false;
  }

  Future<void> setSyncToMasterPreference(
    String calendarId,
    String userId,
    bool value,
  ) async {
    await FirebaseFirestore.instance
        .collection('calendars')
        .doc(calendarId)
        .collection('memberPrefs')
        .doc(userId)
        .set({'syncToMaster': value}, SetOptions(merge: true));
  }

  Future<void> _loadPermissions() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId');
    final currentId = user?.uid ?? guestId;

    final doc =
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(widget.calendarId)
            .get();
    final data = doc.data();
    if (data == null || currentId == null) return;

    final ownerId = data['owner'];
    final allowEdit = data['allowEdit'] ?? false;
    final isOwner = currentId == ownerId;
    final hasGuestEditAccess =
        prefs.getBool('editAccess_${widget.calendarId}') ?? false;

    // === 🔁 Convert members list and check if current user exists ===
    final members = List<Map<String, dynamic>>.from(data['members'] ?? []);
    final isAlreadyMember = members.any(
      (m) => m['id'].toString() == currentId.toString(),
    );

    if (!isAlreadyMember) {
      members.add({'id': currentId, 'name': user?.email ?? 'Anonymous'});
      await FirebaseFirestore.instance
          .collection('calendars')
          .doc(widget.calendarId)
          .update({'members': members});
    }

    setState(() {
      _canEdit = isOwner || (allowEdit && hasGuestEditAccess);
    });
  }

  void _loadCalendarDetails() async {
    final doc =
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(widget.calendarId)
            .get();
    if (doc.exists) {
      setState(() {
        _calendarData = doc.data();
      });
    }
  }

  void _loadEvents() async {
    final random = Random();
    if (widget.calendarId == null) return;

    final eventsRef = FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .collection('events');

    try {
      final query = await eventsRef.get();
      final tempEvents = <DateTime, List<Map<String, dynamic>>>{};
      final tempColors = <String, Color>{};

      final calendarSnap =
          await FirebaseFirestore.instance
              .collection('calendars')
              .doc(widget.calendarId)
              .get();
      final calendarData = calendarSnap.data();
      final calendarName = calendarData?['name'] ?? 'Shared Calendar';
      final ownerId = calendarData?['owner'];

      for (var doc in query.docs) {
        final data = doc.data();
        final startTime = (data['startTime'] as Timestamp).toDate();
        final endTime = (data['endTime'] as Timestamp).toDate();
        final normalizedEnd = DateTime(
          endTime.year,
          endTime.month,
          endTime.day,
          23,
          59,
          59,
        );

        final title =
            ownerId != _currentUserId
                ? '${data['title']} ($calendarName)'
                : data['title'];

        final color = Color.fromARGB(
          255,
          random.nextInt(200),
          random.nextInt(200),
          random.nextInt(200),
        );
        tempColors[doc.id] = color;

        for (
          DateTime d = startTime;
          !d.isAfter(normalizedEnd);
          d = d.add(const Duration(days: 1))
        ) {
          final dateOnly = DateTime(d.year, d.month, d.day);
          tempEvents[dateOnly] ??= [];
          tempEvents[dateOnly]!.add({
            ...data,
            'id': doc.id,
            'calendarId': widget.calendarId,
            'title': title,
          });
        }
      }

      setState(() {
        _eventsByDay = tempEvents;
        _eventColors = tempColors;
      });
    } catch (_) {
      setState(() => _eventsByDay = {});
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) =>
      _eventsByDay[DateTime(day.year, day.month, day.day)] ?? [];

  @override
  Widget build(BuildContext context) {
    if (widget.calendarId == null) {
      return const Scaffold(body: Center(child: Text("No calendar selected.")));
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.onBackToList != null) {
              widget.onBackToList!(); // Navigate back to calendar list
            }
          },
        ),
        title: Text(widget.calendarName ?? 'Shared Calendar'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children:
                  _participants.take(10).map((user) {
                    final name = user['name'] ?? 'Anonymous';
                    final id = user['id'] ?? '';
                    final isOwner = id == _calendarData?['owner'];
                    final isGuest = name.toLowerCase().contains('anonymous');

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message: isOwner ? '$name (Owner)' : name,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor:
                              isGuest ? Colors.grey[400] : buttonColor,
                          child: Text(
                            name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          if (_calendarData != null &&
              _calendarData!['owner'] == _currentUserId)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Collaborative Calendar'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: () => _showShareModal(widget.calendarId!),
              ),
            ),
        ],
      ),

      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2000),
            lastDay: DateTime.utc(2100),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
            },
            onPageChanged:
                (focusedDay) => setState(() => _focusedDay = focusedDay),
            eventLoader: _getEventsForDay,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
              headerPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            calendarBuilders: CalendarBuilders(
              headerTitleBuilder:
                  (context, day) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _focusedDay,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDatePickerMode: DatePickerMode.year,
                          initialEntryMode: DatePickerEntryMode.calendarOnly,
                        );
                        if (picked != null)
                          setState(() => _focusedDay = _selectedDay = picked);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today, size: 20, color: textDark),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('MMMM yyyy').format(_focusedDay),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return const SizedBox();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children:
                      events.map((e) {
                        final event = e as Map<String, dynamic>;
                        final color =
                            _eventColors[event['id']] ?? Colors.purple;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 0.5,
                            vertical: 1.5,
                          ),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        );
                      }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your schedule for ${_selectedDay.day}-${_selectedDay.month}-${_selectedDay.year}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: buttonColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (_canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _addEventDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Event'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: lightCard,
                      foregroundColor: textDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child:
                _getEventsForDay(_selectedDay).isEmpty
                    ? const Center(child: Text("No events found."))
                    : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children:
                          _getEventsForDay(_selectedDay).map((event) {
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: lightCard,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 4,
                                    color: Colors.black12,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event['title'] ?? '',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: textDark,
                                    ),
                                  ),
                                  if (event['calendarName'] != null &&
                                      event['calendarName']
                                          .toString()
                                          .isNotEmpty)
                                    Text(
                                      event['calendarName'],
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: textDark.withOpacity(0.7),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    event['description'] ?? '',
                                    style: TextStyle(
                                      color: textDark.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (_canEdit)
                                        TextButton(
                                          onPressed: () => _editEvent(event),
                                          child: const Text('Edit'),
                                        ),
                                      if (_canEdit)
                                        TextButton(
                                          onPressed: () => _deleteEvent(event),
                                          child: const Text('Delete'),
                                        ),
                                    ],
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

  void _showShareModal(String calendarId) async {
    final calendarDoc =
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(calendarId)
            .get();

    final data = calendarDoc.data();
    if (data == null ||
        (!data.containsKey('sharedLinkEdit') &&
            !data.containsKey('sharedLinkView'))) {
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
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Share Calendar'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: linkController,
                    readOnly: true,
                    onTap:
                        () =>
                            linkController.selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: linkController.text.length,
                            ),
                    decoration: InputDecoration(
                      labelText: 'Invite Link',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: linkController.text));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link copied to clipboard'),
                              duration: Duration(seconds: 5),
                            ),
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
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addEventDialog({Map<String, dynamic>? event}) {
    if (_selectedDay.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't create events in the past.")),
      );
      return;
    }

    DateTime selectedStart = event?['startTime']?.toDate() ?? _selectedDay;
    DateTime selectedEnd = event?['endTime']?.toDate() ?? _selectedDay;

    final titleController = TextEditingController(text: event?['title'] ?? '');
    final descriptionController = TextEditingController(
      text: event?['description'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              title: Text(
                event == null ? 'Add Event' : 'Edit Event',
                style: TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              content: SizedBox(
                width:
                    MediaQuery.of(context).size.width > 500
                        ? 400
                        : double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Start Date:",
                        style: TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('dd-MM-yyyy').format(selectedStart),
                        ),
                        trailing: Icon(
                          Icons.calendar_today,
                          color: buttonColor,
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedStart,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null)
                            setModalState(() => selectedStart = picked);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "End Date:",
                        style: TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('dd-MM-yyyy').format(selectedEnd),
                        ),
                        trailing: Icon(
                          Icons.calendar_today,
                          color: buttonColor,
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedEnd,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null)
                            setModalState(() => selectedEnd = picked);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final title = titleController.text.trim();
                        final description = descriptionController.text.trim();

                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a title.'),
                            ),
                          );
                          return;
                        }

                        if (selectedEnd.isBefore(selectedStart)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'End date must be after start date.',
                              ),
                            ),
                          );
                          return;
                        }

                        _saveSharedEvent(
                          title: title,
                          description: description,
                          start: selectedStart,
                          end: selectedEnd,
                          event: event,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveSharedEvent({
    required String title,
    required String description,
    required DateTime start,
    required DateTime end,
    Map<String, dynamic>? event,
  }) async {
    final eventData = {
      'title': title,
      'description': description,
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'creatorId': _currentUserId,
      'createdAt': Timestamp.now(),
      'lastUpdated': Timestamp.now(),
    };

    final eventsRef = FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .collection('events');

    if (event == null) {
      // 🔹 Create new event
      await eventsRef.add(eventData);
    } else {
      // 🔄 Update existing event
      await eventsRef.doc(event['id']).update(eventData);
    }

    await FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .update({'lastUpdatedAt': Timestamp.now()});

    Navigator.pop(context); // Close dialog
    _loadEvents(); // Refresh event list
  }

  Future<void> _editEvent(Map<String, dynamic> event) async {
    if (_selectedDay.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't edit events in the past.")),
      );
      return;
    }

    final titleController = TextEditingController(text: event['title'] ?? '');
    final descriptionController = TextEditingController(
      text: event['description'] ?? '',
    );
    DateTime selectedStart = (event['startTime'] as Timestamp).toDate();
    DateTime selectedEnd = (event['endTime'] as Timestamp).toDate();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              title: const Text(
                'Edit Event',
                style: TextStyle(
                  color: Color(0xFF112D4E),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              content: SizedBox(
                width:
                    MediaQuery.of(context).size.width > 500
                        ? 400
                        : double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Start Date:",
                        style: TextStyle(
                          color: Color(0xFF112D4E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('dd-MM-yyyy').format(selectedStart),
                        ),
                        trailing: const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF3F72AF),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedStart,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null)
                            setModalState(() => selectedStart = picked);
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "End Date:",
                        style: TextStyle(
                          color: Color(0xFF112D4E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('dd-MM-yyyy').format(selectedEnd),
                        ),
                        trailing: const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF3F72AF),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedEnd,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null)
                            setModalState(() => selectedEnd = picked);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                if (_canEdit)
                  ElevatedButton(
                    onPressed: () async {
                      final title = titleController.text.trim();
                      final description = descriptionController.text.trim();

                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Title cannot be empty.'),
                          ),
                        );
                        return;
                      }

                      if (selectedEnd.isBefore(selectedStart)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('End date must be after start date.'),
                          ),
                        );
                        return;
                      }

                      await FirebaseFirestore.instance
                          .collection('calendars')
                          .doc(widget.calendarId)
                          .collection('events')
                          .doc(event['id'])
                          .update({
                            'title': title,
                            'description': description,
                            'startTime': Timestamp.fromDate(selectedStart),
                            'endTime': Timestamp.fromDate(selectedEnd),
                            'updatedAt': FieldValue.serverTimestamp(),
                            'updatedBy': _currentUserId,
                          });

                      await FirebaseFirestore.instance
                          .collection('calendars')
                          .doc(widget.calendarId)
                          .update({'lastUpdatedAt': Timestamp.now()});

                      Navigator.pop(context);
                      _loadEvents();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F72AF),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final confirmed = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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

    await FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .update({'lastUpdatedAt': Timestamp.now()}); // 🔁 added here
  }
}
