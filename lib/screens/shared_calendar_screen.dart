// 🔄 SharedCalendarScreen with Day/Month agenda, real-time stream,
//     and visible creator names for guests & users

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../utils/guest_helper.dart';

enum _AgendaView { day, month }

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

  // Day / Month agenda
  _AgendaView _agendaView = _AgendaView.day;

  String? _currentUserId;
  Map<String, dynamic>? _calendarData;
  bool _canEdit = false;
  List<Map<String, String>> _participants = [];
  bool _isMember = false;

  final Color bgColor = const Color(0xFFF9F7F7);
  final Color lightCard = const Color(0xFFDBE2EF);
  final Color buttonColor = const Color(0xFF3F72AF);
  final Color textDark = const Color(0xFF112D4E);

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isBeforeToday(DateTime d) =>
      _startOfDay(d).isBefore(_startOfDay(DateTime.now()));

  @override
  void initState() {
    super.initState();
    _userIdFuture = getCurrentUserId();
    _userIdFuture.then((id) async {
      _currentUserId = id;
      if (widget.calendarId != null) {
        await _loadPermissions(); // ensure membership first (with proper name)
        _loadCalendarDetails();
        _loadMembers();
        setState(() {});
      }
    });
  }

  Future<void> _loadMembers() async {
    final doc = await FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .get();
    final data = doc.data();
    if (data == null) return;

    final members = (data['members'] ?? []) as List<dynamic>;
    setState(() {
      _participants = members.map<Map<String, String>>((e) {
        if (e is Map) {
          return {
            'id': (e['id'] ?? '').toString(),
            'name': (e['name'] ?? 'Anonymous').toString(),
          };
        } else {
          // legacy string-only member entry
          return {'id': e.toString(), 'name': 'Anonymous'};
        }
      }).toList();
    });
  }


  // 👇 Determine a user-visible name: real user -> displayName/email; guest -> sticky nickname
  Future<String> _resolveDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if ((user.displayName ?? '').trim().isNotEmpty) return user.displayName!;
      if ((user.email ?? '').trim().isNotEmpty) return user.email!;
      return 'User';
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('guestName');
    if (cached != null && cached.trim().isNotEmpty) return cached;

    final guestId = prefs.getString('guestId') ?? 'guest';
    final suffix =
        guestId.length >= 4 ? guestId.substring(guestId.length - 4) : guestId;
    final generated = 'GUEST-$suffix'.toUpperCase(); // e.g., GUEST-1A2B
    await prefs.setString('guestName', generated);
    return generated;
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
    if (data == null || currentId == null) return;

    final ownerId = (data['owner'] ?? '').toString();
    final allowEdit = data['allowEdit'] ?? false;
    final isOwner = currentId.toString() == ownerId;
    final hasGuestEditAccess =
        prefs.getBool('editAccess_${widget.calendarId}') ?? false;

    // ✅ Check membership without mutating Firestore
    final rawMembers = (data['members'] ?? []) as List<dynamic>;
    final isMember = rawMembers.any((m) {
      if (m is Map && m['id'] != null) return m['id'].toString() == currentId.toString();
      if (m is String) return m.toString() == currentId.toString(); // legacy shape
      return false;
    });

    setState(() {
      _isMember = isMember;
      _canEdit = isOwner || (allowEdit && hasGuestEditAccess);
    });
  }


  void _loadCalendarDetails() async {
    final doc = await FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .get();
    if (doc.exists) {
      setState(() => _calendarData = doc.data());
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

  // Stable color per event id (for markers)
  Color _colorForId(String id) {
    int hash = id.codeUnits.fold(0, (h, c) => 0x1fffffff & (h * 31 + c));
    final r = 50 + (hash & 0x7F);
    final g = 50 + ((hash >> 7) & 0x7F);
    final b = 50 + ((hash >> 14) & 0x7F);
    return Color.fromARGB(255, r, g, b);
  }

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
          onPressed: () => widget.onBackToList?.call(),
        ),
        title: Text(widget.calendarName ?? 'Shared Calendar'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: _participants.take(10).map((user) {
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
                      backgroundColor: isGuest ? Colors.grey[400] : buttonColor,
                      child: Text(
                        name.substring(0, 1).toUpperCase(),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _showShareModal(widget.calendarId!),
              ),
            ),
        ],
      ),

      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('calendars')
              .doc(widget.calendarId)
              .collection('events')
              .orderBy('startTime')
              .snapshots(),
          builder: (context, snap) {
            // Build a map of events per day for the calendar & agenda
            final byDay = <DateTime, List<Map<String, dynamic>>>{};
            final colors = <String, Color>{};

            if (snap.hasData) {
              final docs = snap.data!.docs;
              final calendarName = _calendarData?['name'] ?? 'Shared Calendar';
              final ownerId = _calendarData?['owner'];

              for (final d in docs) {
                final data = d.data();
                final startTs = data['startTime'] as Timestamp?;
                final endTs = data['endTime'] as Timestamp?;
                if (startTs == null || endTs == null) continue;

                final start = startTs.toDate();
                final end = endTs.toDate();
                final normalizedEnd =
                    DateTime(end.year, end.month, end.day, 23, 59, 59);

                final displayTitle = (ownerId != _currentUserId)
                    ? '${data['title']} ($calendarName)'
                    : (data['title'] ?? '');

                colors[d.id] = _colorForId(d.id);

                for (DateTime dt = start;
                    !dt.isAfter(normalizedEnd);
                    dt = dt.add(const Duration(days: 1))) {
                  final key = DateTime(dt.year, dt.month, dt.day);
                  (byDay[key] ??= []).add({
                    ...data,
                    'id': d.id,
                    'calendarId': widget.calendarId,
                    'title': displayTitle,
                    // keep any stored creatorName/creatorId
                  });
                }
              }
            }

            List<Map<String, dynamic>> eventsForDay(DateTime day) =>
                byDay[DateTime(day.year, day.month, day.day)] ?? [];

            // reusable event card (includes "by <creatorName>")
            Widget buildEventCard(Map<String, dynamic> event,
                {DateTime? displayDate}) {
              final storedCreator =
                  (event['creatorName'] as String?)?.trim() ?? '';
              final fallbackFromMembers = _participants
                  .firstWhere(
                    (p) => p['id'] == (event['creatorId'] ?? ''),
                    orElse: () => const {'name': 'Guest'},
                  )['name'] ??
                  'Guest';
              final creatorName =
                  storedCreator.isNotEmpty ? storedCreator : fallbackFromMembers;

              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: lightCard,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(blurRadius: 4, color: Colors.black12)
                  ],
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
                              style: TextStyle(
                                  fontSize: 20,
                                  height: 1.2,
                                  color: textDark)),
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
                              // creator line
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'by $creatorName',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textDark.withOpacity(0.7),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                              if (event['calendarName'] != null &&
                                  event['calendarName']
                                      .toString()
                                      .isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    event['calendarName'],
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Roboto',
                                      color: textDark.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                              if (event['startTime'] != null &&
                                  event['endTime'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _formatEventTime(
                                      displayDate ?? _selectedDay,
                                      (event['startTime'] as Timestamp?)
                                          ?.toDate(),
                                      (event['endTime'] as Timestamp?)
                                          ?.toDate(),
                                    ),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: textDark,
                                    ),
                                  ),
                                ),
                              if ((event['description'] ?? '')
                                  .toString()
                                  .isNotEmpty)
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
                        if (_canEdit)
                          TextButton(
                            onPressed: () {
                              final startDate =
                                  (event['startTime'] as Timestamp?)
                                          ?.toDate() ??
                                      DateTime.now();
                              if (_startOfDay(startDate)
                                  .isBefore(_startOfDay(DateTime.now()))) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "You can't edit events in the past.",
                                    ),
                                  ),
                                );
                                return;
                              }
                              _editEvent(event);
                            },
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
            }

            // Month agenda (group by day, only days with events)
            Widget buildMonthAgenda() {
              final first = DateTime(_focusedDay.year, _focusedDay.month, 1);
              final last = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

              final items = <Widget>[];
              for (int i = 0; i < last.day; i++) {
                final day =
                    DateTime(first.year, first.month, first.day + i);
                final evs = eventsForDay(day);
                if (evs.isEmpty) continue;

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
                items.addAll(
                    evs.map((e) => buildEventCard(e, displayDate: day)));
              }
              if (items.isEmpty) {
                return const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text('No events this month.'),
                );
              }
              return Column(children: items);
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TableCalendar(
                    firstDay: DateTime.utc(2000),
                    lastDay: DateTime.utc(2100),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) =>
                        isSameDay(_selectedDay, day),
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDay = selected;
                        _focusedDay = focused;
                      });
                    },
                    onPageChanged: (focusedDay) {
                      setState(() {
                        _focusedDay = focusedDay;
                        // carry same day number; clamp to last day of target month
                        final carry = _selectedDay.day;
                        final lastDay = DateTime(
                                focusedDay.year, focusedDay.month + 1, 0)
                            .day;
                        final newDay = min(carry, lastDay);
                        _selectedDay = DateTime(
                            focusedDay.year, focusedDay.month, newDay);
                      });
                    },
                    eventLoader: eventsForDay,
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                      headerPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                    calendarBuilders: CalendarBuilders(
                      headerTitleBuilder: (context, day) => Material(
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
                              initialEntryMode:
                                  DatePickerEntryMode.calendarOnly,
                            );
                            if (picked != null) {
                              final carry = _selectedDay.day;
                              final lastDay = DateTime(
                                      picked.year, picked.month + 1, 0)
                                  .day;
                              final newDay = min(carry, lastDay);
                              setState(() {
                                _focusedDay = picked;
                                _selectedDay = DateTime(
                                    picked.year, picked.month, newDay);
                              });
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 20, color: textDark),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('MMMM yyyy')
                                    .format(_focusedDay),
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
                          children: events.map((e) {
                            final event = e as Map<String, dynamic>;
                            final color =
                                colors[event['id']] ?? Colors.purple;
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 0.5, vertical: 1.5),
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

                  const SizedBox(height: 12),

                  // Responsive toolbar (chips + add button, then title on its own line)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8.0),
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
                                    selected:
                                        _agendaView == _AgendaView.day,
                                    onSelected: (_) => setState(() =>
                                        _agendaView = _AgendaView.day),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Month'),
                                    selected:
                                        _agendaView == _AgendaView.month,
                                    onSelected: (_) => setState(() =>
                                        _agendaView = _AgendaView.month),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_canEdit)
                              Builder(builder: (context) {
                                final compact =
                                    MediaQuery.of(context).size.width <
                                        360;
                                return ElevatedButton.icon(
                                  onPressed: () => _addEventDialog(),
                                  icon:
                                      const Icon(Icons.add, size: 18),
                                  label: Text(
                                      compact ? 'Add' : 'Add Event'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: lightCard,
                                    foregroundColor: textDark,
                                    elevation: 0,
                                    shape:
                                        RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(30),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    textStyle:
                                        const TextStyle(fontSize: 13),
                                  ),
                                );
                              }),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _agendaView == _AgendaView.day
                              ? 'Your schedule for ${DateFormat('EEE, d MMM yyyy').format(_selectedDay)}'
                              : 'Your schedule for ${DateFormat('MMMM yyyy').format(_focusedDay)}',
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
                  if (snap.connectionState ==
                      ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (snap.hasError)
                    const Center(
                        child: Text('Failed to load events.'))
                  else ...[
                    if (_agendaView == _AgendaView.day)
                      Builder(builder: (_) {
                        final dayEvents = eventsForDay(_selectedDay);
                        if (dayEvents.isEmpty) {
                          return const Center(
                              child: Text("No events found."));
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: dayEvents.length,
                          itemBuilder: (context, index) =>
                              buildEventCard(dayEvents[index]),
                        );
                      })
                    else
                      buildMonthAgenda(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ===== Share / Add / Edit / Delete =====

  void _showShareModal(String calendarId) async {
    final calendarDoc = await FirebaseFirestore.instance
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
    String editLink = 'localhost:5000/#/cal/${data['sharedLinkEdit']}';
    String viewLink = 'localhost:5000/#/cal/${data['sharedLinkView']}';

    final TextEditingController linkController =
        TextEditingController(text: allowEdit ? editLink : viewLink);

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
                    onTap: () => linkController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: linkController.text.length,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Invite Link',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: linkController.text));
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
    TimeOfDay startTime = const TimeOfDay(hour: 0, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 0, minute: 0);

    final titleController = TextEditingController(text: event?['title'] ?? '');
    final descriptionController =
        TextEditingController(text: event?['description'] ?? '');

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
                width: MediaQuery.of(context).size.width > 500
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
                        "Start:",
                        style:
                            TextStyle(color: textDark, fontWeight: FontWeight.w600),
                      ),
                      Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              DateFormat('dd-MM-yyyy').format(selectedStart),
                              style: TextStyle(color: textDark),
                            ),
                            trailing:
                                Icon(Icons.calendar_today, color: buttonColor),
                            onTap: () async {
                              final today0 = _startOfDay(DateTime.now());
                              final init = _startOfDay(selectedStart).isBefore(today0)
                                  ? today0
                                  : selectedStart;

                              final picked = await showDatePicker(
                                context: context,
                                initialDate: init,
                                firstDate: today0,
                                lastDate: DateTime(2100),
                                selectableDayPredicate: (d) => !_isBeforeToday(d),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  selectedStart = picked;
                                  if (_startOfDay(selectedEnd)
                                      .isBefore(_startOfDay(selectedStart))) {
                                    selectedEnd = _startOfDay(selectedStart);
                                  }
                                });
                              }
                            },
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(startTime.format(context),
                                style: TextStyle(color: textDark)),
                            trailing:
                                Icon(Icons.access_time, color: buttonColor),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: startTime,
                              );
                              if (picked != null) setModalState(() => startTime = picked);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Text(
                        "End:",
                        style:
                            TextStyle(color: textDark, fontWeight: FontWeight.w600),
                      ),
                      Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              DateFormat('dd-MM-yyyy').format(selectedEnd),
                              style: TextStyle(color: textDark),
                            ),
                            trailing:
                                Icon(Icons.calendar_today, color: buttonColor),
                            onTap: () async {
                              final today0 = _startOfDay(DateTime.now());
                              final floor = _startOfDay(selectedStart).isBefore(today0)
                                  ? today0
                                  : _startOfDay(selectedStart);
                              final initEnd = _startOfDay(selectedEnd).isBefore(floor)
                                  ? floor
                                  : selectedEnd;

                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initEnd,
                                firstDate: floor,
                                lastDate: DateTime(2100),
                                selectableDayPredicate: (d) =>
                                    !_isBeforeToday(d) && !d.isBefore(floor),
                              );
                              if (picked != null) {
                                setModalState(() => selectedEnd = picked);
                              }
                            },
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(endTime.format(context),
                                style: TextStyle(color: textDark)),
                            trailing:
                                Icon(Icons.access_time, color: buttonColor),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: endTime,
                              );
                              if (picked != null) setModalState(() => endTime = picked);
                            },
                          ),
                        ],
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
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final description = descriptionController.text.trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a title.')),
                          );
                          return;
                        }
                        if (selectedEnd.isBefore(selectedStart)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('End date must be after start date.')),
                          );
                          return;
                        }

                        final startDateTime = DateTime(
                          selectedStart.year,
                          selectedStart.month,
                          selectedStart.day,
                          startTime.hour,
                          startTime.minute,
                        );
                        final endDateTime = DateTime(
                          selectedEnd.year,
                          selectedEnd.month,
                          selectedEnd.day,
                          endTime.hour,
                          endTime.minute,
                        );

                        final today0 = _startOfDay(DateTime.now());
                        if (_startOfDay(selectedStart).isBefore(today0) ||
                            _startOfDay(selectedEnd).isBefore(today0)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Events can’t be created on past dates.")),
                          );
                          return;
                        }
                        if (!endDateTime.isAfter(startDateTime)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('End time must be after start time.')),
                          );
                          return;
                        }

                        await _saveSharedEvent(
                          title: title,
                          description: description,
                          start: startDateTime,
                          end: endDateTime,
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
    final creatorName = await _resolveDisplayName(); // 👈 add creator name

    final eventData = {
      'title': title,
      'description': description,
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'creatorId': _currentUserId,
      'creatorName': creatorName,             // ✅ stored on event
      'createdAt': Timestamp.now(),
      'lastUpdated': Timestamp.now(),
    };

    final eventsRef = FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .collection('events');

    if (event == null) {
      await eventsRef.add(eventData);
    } else {
      await eventsRef.doc(event['id']).update(eventData);
    }

    await FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .update({'lastUpdatedAt': Timestamp.now()});

    Navigator.pop(context); // stream updates UI
  }

  Future<void> _editEvent(Map<String, dynamic> event) async {
    DateTime selectedStart =
        (event['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime selectedEnd =
        (event['endTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    TimeOfDay startTime = TimeOfDay.fromDateTime(selectedStart);
    TimeOfDay endTime = TimeOfDay.fromDateTime(selectedEnd);

    if (_selectedDay.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't edit events in the past.")),
      );
      return;
    }

    final titleController =
        TextEditingController(text: event['title'] ?? '');
    final descriptionController =
        TextEditingController(text: event['description'] ?? '');

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
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
                width: MediaQuery.of(context).size.width > 500
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
                        title:
                            Text(DateFormat('dd-MM-yyyy').format(selectedStart)),
                        trailing: const Icon(Icons.calendar_today,
                            color: Color(0xFF3F72AF)),
                        onTap: () async {
                          final today0 = _startOfDay(DateTime.now());
                          final init =
                              _startOfDay(selectedStart).isBefore(today0)
                                  ? today0
                                  : selectedStart;

                          final picked = await showDatePicker(
                            context: context,
                            initialDate: init,
                            firstDate: today0,
                            lastDate: DateTime(2100),
                            selectableDayPredicate: (d) => !_isBeforeToday(d),
                          );
                          if (picked != null) {
                            setModalState(() => selectedStart = picked);
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(startTime.format(context),
                            style: const TextStyle(color: Color(0xFF112D4E))),
                        trailing: const Icon(Icons.access_time,
                            color: Color(0xFF3F72AF)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: startTime,
                          );
                          if (picked != null) {
                            setModalState(() => startTime = picked);
                          }
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
                        title:
                            Text(DateFormat('dd-MM-yyyy').format(selectedEnd)),
                        trailing: const Icon(Icons.calendar_today,
                            color: Color(0xFF3F72AF)),
                        onTap: () async {
                          final today0 = _startOfDay(DateTime.now());
                          final floor =
                              _startOfDay(selectedStart).isBefore(today0)
                                  ? today0
                                  : _startOfDay(selectedStart);
                          final initEnd =
                              _startOfDay(selectedEnd).isBefore(floor)
                                  ? floor
                                  : selectedEnd;

                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initEnd,
                            firstDate: floor,
                            lastDate: DateTime(2100),
                            selectableDayPredicate: (d) =>
                                !_isBeforeToday(d) && !d.isBefore(floor),
                          );
                          if (picked != null) {
                            setModalState(() => selectedEnd = picked);
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(endTime.format(context),
                            style: const TextStyle(color: Color(0xFF112D4E))),
                        trailing: const Icon(Icons.access_time,
                            color: Color(0xFF3F72AF)),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: endTime,
                          );
                          if (picked != null) {
                            setModalState(() => endTime = picked);
                          }
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
                              content: Text('Title cannot be empty.')),
                        );
                        return;
                      }

                      final startDateTime = DateTime(
                        selectedStart.year,
                        selectedStart.month,
                        selectedStart.day,
                        startTime.hour,
                        startTime.minute,
                      );
                      final endDateTime = DateTime(
                        selectedEnd.year,
                        selectedEnd.month,
                        selectedEnd.day,
                        endTime.hour,
                        endTime.minute,
                      );

                      if (!endDateTime.isAfter(startDateTime)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('End time must be after start time.'),
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
                        'startTime': Timestamp.fromDate(startDateTime),
                        'endTime': Timestamp.fromDate(endDateTime),
                        'updatedAt': FieldValue.serverTimestamp(),
                        'updatedBy': _currentUserId,
                      });

                      await FirebaseFirestore.instance
                          .collection('calendars')
                          .doc(widget.calendarId)
                          .update({'lastUpdatedAt': Timestamp.now()});

                      Navigator.pop(context);
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
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content:
            const Text('Are you sure you want to delete this event?'),
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

      await FirebaseFirestore.instance
          .collection('calendars')
          .doc(widget.calendarId)
          .update({'lastUpdatedAt': Timestamp.now()});
    }
  }
}
