import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_calendar/utils/guest_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

// ✅ shared CRUD helper
import '../common/event_crud.dart';

class MasterCalendarScreen extends StatefulWidget {
  const MasterCalendarScreen({super.key});

  @override
  State<MasterCalendarScreen> createState() => _MasterCalendarScreenState();
}

enum _AgendaView { day, month }

class _MasterCalendarScreenState extends State<MasterCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  // Agenda mode
  _AgendaView _agendaView = _AgendaView.day;

  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  Map<String, Color> _eventColors = {};
  bool _loading = true;

  // Colors
  final Color bgColor = const Color(0xFFF9F7F7);
  final Color lightCard = const Color(0xFFDBE2EF);
  final Color buttonColor = const Color(0xFF3F72AF);
  final Color textDark = const Color(0xFF112D4E);

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  // ignore: unused_element
  bool _isBeforeToday(DateTime d) =>
      _startOfDay(d).isBefore(_startOfDay(DateTime.now()));

  @override
  void initState() {
    super.initState();
    ensureUserHasMasterCalendar().then((_) => _loadEvents());
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

  /// 🔧 Returns the Events collection for the user's personal (master) calendar.
  /// If it doesn't exist, it creates it (same logic as your _saveEvent before).
  Future<CollectionReference<Map<String, dynamic>>> _personalEventsCol() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = user?.uid ?? prefs.getString('guestId');

    final calendarsSnap = await FirebaseFirestore.instance
        .collection('calendars')
        .where('owner', isEqualTo: currentUserId)
        .where('isShared', isEqualTo: false)
        .limit(1)
        .get();

    final String personalCalendarId;
    if (calendarsSnap.docs.isEmpty) {
      personalCalendarId =
          (await FirebaseFirestore.instance.collection('calendars').add({
        'name': 'My Calendar',
        'owner': currentUserId,
        'members': [currentUserId],
        'isShared': false,
        'createdAt': Timestamp.now(),
      }))
              .id;
    } else {
      personalCalendarId = calendarsSnap.docs.first.id;
    }

    return FirebaseFirestore.instance
        .collection('calendars')
        .doc(personalCalendarId)
        .collection('events');
  }

  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = user?.uid ?? prefs.getString('guestId');

    final calendarQuery =
        await FirebaseFirestore.instance.collection('calendars').get();

    final Map<DateTime, List<Map<String, dynamic>>> tempEvents = {};
    final Map<String, Color> tempColors = {};
    final random = Random();

    for (final doc in calendarQuery.docs) {
      final calendarId = doc.id;
      final calendarName = (doc['name'] ?? 'Shared Calendar').toString();
      final isShared = doc['isShared'] ?? false;

      final rawMembers = doc['members'] ?? [];
      final members = rawMembers.map<String>((m) {
        if (m is String) return m;
        if (m is Map && m.containsKey('id')) return m['id'] as String;
        return '';
      }).toList();

      if (!members.contains(currentUserId)) continue;

      final eventsSnap = await FirebaseFirestore.instance
          .collection('calendars')
          .doc(calendarId)
          .collection('events')
          .get();

      for (final eventDoc in eventsSnap.docs) {
        final data = eventDoc.data();
        final start = (data['startTime'] as Timestamp).toDate();
        final end = (data['endTime'] as Timestamp).toDate();
        final normalizedEnd =
            DateTime(end.year, end.month, end.day, 23, 59, 59);

        final title = (data['title'] ?? '').toString();
        final creatorName = ((data['creatorName'] ?? '') as String).trim();

        final color = Color.fromARGB(
          255,
          random.nextInt(200),
          random.nextInt(200),
          random.nextInt(200),
        );
        tempColors[eventDoc.id] = color;

        for (DateTime d = start;
            !d.isAfter(normalizedEnd);
            d = d.add(const Duration(days: 1))) {
          final dateOnly = DateTime(d.year, d.month, d.day);
          (tempEvents[dateOnly] ??= []).add({
            ...data,
            'id': eventDoc.id,
            'calendarId': calendarId,
            'title': title,
            'creatorName': creatorName, // for the card line
            'calendarName': calendarName,
            'isShared': isShared,
          });
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _events = tempEvents;
      _eventColors = tempColors;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  // —— UI ——

  Widget _buildEventCard(Map<String, dynamic> event, {DateTime? displayDate}) {
  final String creator = (event['creatorName'] ?? '').toString().trim();
  final String calendarName = (event['calendarName'] ?? '').toString().trim();

  // ✅ Only treat as shared if explicitly marked so by _loadEvents()
  final bool isSharedEvent = event['isShared'] == true;

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: lightCard,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('•',
                  style:
                      TextStyle(fontSize: 20, height: 1.2, color: textDark)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${event['title']}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                        height: 1.2,
                      )),

                  // ✅ Show this ONLY for shared events AND only when we have a creator
                  if (isSharedEvent && creator.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        calendarName.isNotEmpty
                            ? 'by $creator on $calendarName'
                            : 'by $creator',
                        style: TextStyle(
                          fontSize: 13,
                          color: textDark.withOpacity(0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                  if (event['startTime'] != null && event['endTime'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _formatEventTime(
                          displayDate ?? _selectedDay,
                          (event['startTime'] as Timestamp?)?.toDate(),
                          (event['endTime'] as Timestamp?)?.toDate(),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textDark,
                        ),
                      ),
                    ),
                  if ((event['description'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        event['description'],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                          fontFamily: 'Roboto',
                          color: textDark.withOpacity(0.85),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () async {
                await EventCrud.showAddOrEditDialog(
                  context: context,
                  getEventsCollection: () async => FirebaseFirestore.instance
                      .collection('calendars')
                      .doc(event['calendarId'])
                      .collection('events'),
                  canEdit: true,
                  disallowPastDates: true,
                  existingEvent: event,
                  buttonColor: buttonColor,
                  textDark: textDark,
                  onAfterWrite: _loadEvents,
                );
              },
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () => EventCrud.confirmAndDelete(
                context: context,
                getEventsCollection: () async => FirebaseFirestore.instance
                    .collection('calendars')
                    .doc(event['calendarId'])
                    .collection('events'),
                eventId: event['id'],
                onAfterDelete: _loadEvents,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ],
    ),
  );
}


  Widget _buildMonthAgenda() {
    final first = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final last = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    final items = <Widget>[];
    for (int i = 0; i < last.day; i++) {
      final day = DateTime(first.year, first.month, first.day + i);
      final events = _getEventsForDay(day);
      if (events.isEmpty) continue;

      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            DateFormat('EEE, d MMM yyyy').format(day),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textDark.withOpacity(0.8),
            ),
          ),
        ),
      );
      items.addAll(events.map((e) => _buildEventCard(e, displayDate: day)));
    }

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text('No events for this month.'),
      );
    }
    return Column(children: items);
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
          final carry = _selectedDay.day;
          final lastDay =
              DateTime(focusedDay.year, focusedDay.month + 1, 0).day;
          final newDay = min(carry, lastDay);
          _selectedDay = DateTime(focusedDay.year, focusedDay.month, newDay);
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
          final carry = _selectedDay.day;
          final lastDay = DateTime(picked.year, picked.month + 1, 0).day;
          final newDay = min(carry, lastDay);
          setState(() {
            _focusedDay = picked;
            _selectedDay = DateTime(picked.year, picked.month, newDay);
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
                final carry = _selectedDay.day;
                final lastDay = DateTime(picked.year, picked.month + 1, 0).day;
                final newDay = min(carry, lastDay);
                setState(() {
                  _focusedDay = picked;
                  _selectedDay = DateTime(picked.year, picked.month, newDay);
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
            children: events.map((e) {
              final event = e as Map<String, dynamic>;
              final color = _eventColors[event['id']] ?? Colors.purple;
              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 0.5, vertical: 1.5),
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

    final titleText = _agendaView == _AgendaView.day
        ? 'Your schedule for ${DateFormat('EEE, d MMM yyyy').format(_selectedDay)}'
        : 'Your schedule for ${DateFormat('MMMM yyyy').format(_focusedDay)}';

    return Scaffold(
      backgroundColor: bgColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    isMobile ? SizedBox(height: 440, child: calendarWidget) : calendarWidget,
                    const SizedBox(height: 12),

                    // Toolbar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Day'),
                                      selected: _agendaView == _AgendaView.day,
                                      onSelected: (_) =>
                                          setState(() => _agendaView = _AgendaView.day),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Month'),
                                      selected: _agendaView == _AgendaView.month,
                                      onSelected: (_) =>
                                          setState(() => _agendaView = _AgendaView.month),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Builder(builder: (context) {
                                final compact =
                                    MediaQuery.of(context).size.width < 360;
                                return ElevatedButton.icon(
                                  onPressed: () async {
                                    // 👉 Seed Add dialog with the currently selected day
                                    await EventCrud.showAddOrEditDialog(
                                      context: context,
                                      getEventsCollection: _personalEventsCol,
                                      canEdit: true,
                                      disallowPastDates: true,
                                      existingEvent: null,
                                      initialSelectedDay: _selectedDay,
                                      onAfterWrite: _loadEvents,
                                      buttonColor: buttonColor,
                                      textDark: textDark,
                                    );
                                  },
                                  icon: const Icon(Icons.add, size: 18),
                                  label: Text(compact ? 'Add' : 'Add Event'),
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
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            titleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
                              color: buttonColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Agenda content
                    if (_agendaView == _AgendaView.day)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8),
                        itemCount: _getEventsForDay(_selectedDay).length,
                        itemBuilder: (context, index) =>
                            _buildEventCard(_getEventsForDay(_selectedDay)[index]),
                      )
                    else
                      _buildMonthAgenda(),
                  ],
                ),
              ),
            ),
    );
  }
}
