import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_calendar/utils/guest_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:math';
import 'package:intl/intl.dart';

class MasterCalendarScreen extends StatefulWidget {
  const MasterCalendarScreen({super.key});

  @override
  State<MasterCalendarScreen> createState() => _MasterCalendarScreenState();
}

class _MasterCalendarScreenState extends State<MasterCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  Map<String, Color> _eventColors = {};
  bool _loading = true;

  final Color bgColor = const Color(0xFFF9F7F7);
  final Color lightCard = const Color(0xFFDBE2EF);
  final Color buttonColor = const Color(0xFF3F72AF);
  final Color textDark = const Color(0xFF112D4E);

  @override
  void initState() {
    super.initState();
    ensureUserHasMasterCalendar().then((_) => _loadEvents());
  }

  Future<void> ensureUserHasMasterCalendar() async {
    final userId = await getCurrentUserId();
    final query =
        await FirebaseFirestore.instance
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

  String _formatEventTime(
    DateTime? selectedDate,
    DateTime? start,
    DateTime? end,
  ) {
    if (start == null || end == null || selectedDate == null) return '';

    final selectedDateFormatted = DateFormat('d MMM yyyy').format(selectedDate);
    final startTime = DateFormat('h:mm a').format(start);
    final endTime = DateFormat('h:mm a').format(end);

    return '$selectedDateFormatted, $startTime – $endTime';
  }

  Future<void> _saveEvent({
    required String title,
    required String description,
    required DateTime start,
    required DateTime end,
    Map<String, dynamic>? event,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = user?.uid ?? prefs.getString('guestId');

    final calendarsSnap =
        await FirebaseFirestore.instance
            .collection('calendars')
            .where('owner', isEqualTo: currentUserId)
            .where('isShared', isEqualTo: false)
            .get();

    final personalCalendarId =
        calendarsSnap.docs.isEmpty
            ? (await FirebaseFirestore.instance.collection('calendars').add({
              'name': 'My Calendar',
              'owner': currentUserId,
              'members': [currentUserId],
              'isShared': false,
              'createdAt': Timestamp.now(),
            })).id
            : calendarsSnap.docs.first.id;

    final data = {
      'title': title,
      'description': description,
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
    };

    if (event == null) {
      await FirebaseFirestore.instance
          .collection('calendars')
          .doc(personalCalendarId)
          .collection('events')
          .add(data);
    } else {
      await FirebaseFirestore.instance
          .collection('calendars')
          .doc(event['calendarId'])
          .collection('events')
          .doc(event['id'])
          .update(data);
    }

    Navigator.pop(context);
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = user?.uid ?? prefs.getString('guestId');

    final calendarQuery =
        await FirebaseFirestore.instance.collection('calendars').get();

    Map<DateTime, List<Map<String, dynamic>>> tempEvents = {};
    Map<String, Color> tempColors = {};
    final random = Random();

    for (final doc in calendarQuery.docs) {
      final calendarId = doc.id;
      final isShared = doc['isShared'] ?? false;
      final calendarName = doc['name'] ?? 'Shared Calendar';
      final rawMembers = doc['members'] ?? [];
      final members =
          rawMembers.map<String>((m) {
            if (m is String) return m;
            if (m is Map && m.containsKey('id')) return m['id'] as String;
            return ''; // fallback to skip invalid
          }).toList();

      if (!members.contains(currentUserId)) continue;

      final eventsSnap =
          await FirebaseFirestore.instance
              .collection('calendars')
              .doc(calendarId)
              .collection('events')
              .get();

      for (final eventDoc in eventsSnap.docs) {
        final data = eventDoc.data();
        final start = (data['startTime'] as Timestamp).toDate();
        final end = (data['endTime'] as Timestamp).toDate();
        final normalizedEnd = DateTime(
          end.year,
          end.month,
          end.day,
          23,
          59,
          59,
        );

        final rawTitle = data['title'] ?? '';
        final title =
            isShared && !rawTitle.contains(calendarName)
                ? '$rawTitle ($calendarName)'
                : rawTitle;

        final color = Color.fromARGB(
          255,
          random.nextInt(200),
          random.nextInt(200),
          random.nextInt(200),
        );
        tempColors[eventDoc.id] = color;

        for (
          DateTime d = start;
          !d.isAfter(normalizedEnd);
          d = d.add(const Duration(days: 1))
        ) {
          final dateOnly = DateTime(d.year, d.month, d.day);
          tempEvents[dateOnly] ??= [];
          tempEvents[dateOnly]!.add({
            ...data,
            'id': eventDoc.id,
            'calendarId': calendarId,
            'title': title,
          });
        }
      }
    }

    setState(() {
      _events = tempEvents;
      _eventColors = tempColors;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _showEventDialog({Map<String, dynamic>? event}) {
    if (_selectedDay.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't create events in the past.")),
      );
      return;
    }

    DateTime selectedStart =
        event?['startTime']?.toDate() ??
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 0, 0);
    DateTime selectedEnd =
        event?['endTime']?.toDate() ??
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 0, 0);

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
                      // === Start Date & Time ===
                      Text(
                        "Start:",
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
                          if (picked != null) {
                            setModalState(() {
                              selectedStart = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                selectedStart.hour,
                                selectedStart.minute,
                              );
                            });
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          DateFormat('hh:mm a').format(selectedStart),
                        ),
                        trailing: Icon(Icons.access_time, color: buttonColor),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 0, minute: 0),
                          );
                          if (time != null) {
                            setModalState(() {
                              selectedStart = DateTime(
                                selectedStart.year,
                                selectedStart.month,
                                selectedStart.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // === End Date & Time ===
                      Text(
                        "End:",
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
                          if (picked != null) {
                            setModalState(() {
                              selectedEnd = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                selectedEnd.hour,
                                selectedEnd.minute,
                              );
                            });
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(DateFormat('hh:mm a').format(selectedEnd)),
                        trailing: Icon(Icons.access_time, color: buttonColor),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 0, minute: 0),
                          );
                          if (time != null) {
                            setModalState(() {
                              selectedEnd = DateTime(
                                selectedEnd.year,
                                selectedEnd.month,
                                selectedEnd.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          }
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
                                'End time must be after start time.',
                              ),
                            ),
                          );
                          return;
                        }

                        _saveEvent(
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
                      child: Text(event == null ? 'Add' : 'Update'),
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

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 500;

    final calendarWidget = TableCalendar(
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
      onPageChanged: (focusedDay) {
        setState(() {
          _focusedDay = focusedDay;
        });
      },
      onHeaderTapped: (date) async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _focusedDay,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialEntryMode: DatePickerEntryMode.calendarOnly,
          initialDatePickerMode: DatePickerMode.year,
        );
        if (picked != null) {
          setState(() {
            _focusedDay = picked;
            _selectedDay = picked;
          });
        }
      },
      calendarFormat: CalendarFormat.month,
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
        headerTitleBuilder: (context, day) {
          return InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _focusedDay,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialEntryMode: DatePickerEntryMode.calendarOnly,
                initialDatePickerMode: DatePickerMode.year,
              );
              if (picked != null) {
                setState(() {
                  _focusedDay = picked;
                  _selectedDay = picked;
                });
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
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
          );
        },
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return const SizedBox();
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children:
                events.map((e) {
                  final event = e as Map<String, dynamic>;
                  final color = _eventColors[event['id']] ?? Colors.purple;
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
    );

    return Scaffold(
      backgroundColor: bgColor,
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      isMobile
                          ? SizedBox(height: 440, child: calendarWidget)
                          : calendarWidget,
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Your schedule for ${_selectedDay.day}-${_selectedDay.month}-${_selectedDay.year}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Roboto',
                                  color: buttonColor,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _showEventDialog(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Event'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: lightCard,
                                foregroundColor: textDark,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                textStyle: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8),
                        itemCount: _getEventsForDay(_selectedDay).length,
                        itemBuilder: (context, index) {
                          final event = _getEventsForDay(_selectedDay)[index];
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
                                BoxShadow(blurRadius: 4, color: Colors.black12),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Bullet + Title
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '•',
                                        style: TextStyle(
                                          fontSize: 20,
                                          height: 1.2,
                                          color: textDark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${event['title']}',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: textDark,
                                              height: 1.2,
                                            ),
                                          ),
                                          if (event['calendarName'] != null &&
                                              event['calendarName']
                                                  .toString()
                                                  .isNotEmpty &&
                                              !(event['title'] ?? '')
                                                  .toString()
                                                  .contains(
                                                    event['calendarName'],
                                                  ))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: Text(
                                                event['calendarName'],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Roboto',
                                                  color: textDark.withOpacity(
                                                    0.7,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (event['startTime'] != null &&
                                              event['endTime'] != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Text(
                                                _formatEventTime(
                                                  _selectedDay,
                                                  event['startTime']?.toDate(),
                                                  event['endTime']?.toDate(),
                                                ),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: textDark,
                                                ),
                                              ),
                                            ),
                                          if (event['description'] != null &&
                                              event['description']
                                                  .toString()
                                                  .isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Text(
                                                event['description'],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w300,
                                                  fontFamily: 'Roboto',
                                                  color: textDark.withOpacity(
                                                    0.85,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // Buttons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed:
                                          () => _showEventDialog(event: event),
                                      child: const Text('Edit'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        await FirebaseFirestore.instance
                                            .collection('calendars')
                                            .doc(event['calendarId'])
                                            .collection('events')
                                            .doc(event['id'])
                                            .delete();
                                        _loadEvents();
                                      },
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
