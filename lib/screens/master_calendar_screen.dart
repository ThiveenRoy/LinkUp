import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../utils/guest_helper.dart';
import '../common/event_crud.dart';

import '../services/google_sync.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

class MasterCalendarScreen extends StatefulWidget {
  const MasterCalendarScreen({super.key});

  @override
  State<MasterCalendarScreen> createState() => _MasterCalendarScreenState();
}

enum _AgendaView { day, month }

class _MasterCalendarScreenState extends State<MasterCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  _AgendaView _agendaView = _AgendaView.day;

  // Rendering data
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  Map<String, Color> _eventColors = {};
  bool _loading = true;

  // Working dialog guard
  bool _busy = false;

  // Theme
  final Color bgColor = const Color(0xFFF9F7F7);
  final Color lightCard = const Color(0xFFDBE2EF);
  final Color buttonColor = const Color(0xFF3F72AF);
  final Color textDark = const Color(0xFF112D4E);

  String? _masterCalendarId; // calendars/{id}

  // ---------- Google state (same behavior as shared) ----------
  bool _googleSyncEnabled = false;
  String? _linkedCalendarSummary;
  bool _googleSignedIn = false;

  @override
  void initState() {
    super.initState();
    ensureUserHasMasterCalendar().then((_) async {
      await _initMasterId();
      await _loadGoogleCfg();
      await _loadEvents();
    });
  }

  // Create user's master calendar if missing
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

  // Find master id
  Future<void> _initMasterId() async {
    final userId = await getCurrentUserId();
    final q = await FirebaseFirestore.instance
        .collection('calendars')
        .where('owner', isEqualTo: userId)
        .where('isShared', isEqualTo: false)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) _masterCalendarId = q.docs.first.id;
  }

  Future<void> _loadGoogleCfg() async {
    if (_masterCalendarId == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('calendars')
        .doc(_masterCalendarId)
        .collection('integrations')
        .doc('google')
        .get();

    final d = snap.data();
    if (!mounted) return;
    setState(() {
      _googleSyncEnabled = (d?['enabled'] ?? false) == true;
      _linkedCalendarSummary = d?['calendarSummary'] as String?;
    });
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

  /// Events collection for the user's personal (master) calendar.
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

  /// Master aggregates:
  /// - Personal calendar: include all events (including Google ones).
  /// - Shared calendars: include ONLY events the current user created manually
  ///   (creatorId == me) and EXCLUDE any with source == 'google'.
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
      final isShared = (doc['isShared'] ?? false) == true;

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

        // Filtering rules for shared calendars
        if (isShared) {
          final src = (data['source'] ?? '').toString();
          final creatorId = (data['creatorId'] ?? '').toString();
          if (src == 'google') continue; // ignore Google in shared
          if (creatorId.isNotEmpty && creatorId != currentUserId) continue; // only mine
        }

        final Timestamp? st = data['startTime'] as Timestamp?;
        final Timestamp? et = data['endTime'] as Timestamp?;
        if (st == null || et == null) continue;

        final start = st.toDate();
        final end = et.toDate();
        final normalizedEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);

        final title = (data['title'] ?? '').toString();
        final creatorName = ((data['creatorName'] ?? '') as String).trim();

        final color = Color.fromARGB(
          255,
          random.nextInt(200),
          random.nextInt(200),
          random.nextInt(200),
        );
        tempColors[eventDoc.id] = color;

        for (DateTime d = start; !d.isAfter(normalizedEnd); d = d.add(const Duration(days: 1))) {
          final dateOnly = DateTime(d.year, d.month, d.day);
          (tempEvents[dateOnly] ??= []).add({
            ...data,
            'id': eventDoc.id,
            'calendarId': calendarId,
            'title': title,
            'creatorName': creatorName,
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

  // ---------- Tiny modal progress while doing Google calls ----------
  Future<T> _withLoading<T>({
    required String message,
    required Future<T> Function() task,
  }) async {
    setState(() => _busy = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
              const SizedBox(width: 12),
              Flexible(child: Text(message, style: const TextStyle(fontSize: 14))),
            ],
          ),
        ),
      ),
    );
    try {
      final res = await task();
      return res;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Manual Add ----------
  Future<void> _openManualAdd() async {
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
  }

  // ================= GOOGLE SYNC =================

  Future<bool> _ensureGoogleSession() async {
    final svc = GoogleCalendarService.instance;
    if (await svc.hasSession()) {
      if (mounted) setState(() => _googleSignedIn = true);
      return true;
    }
    try {
      await svc.ensureSignedInInteractive();
      if (mounted) setState(() => _googleSignedIn = true);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Card UI (same as shared)
  Future<void> _openGoogleCard() async {
    _googleSignedIn = await GoogleCalendarService.instance.hasSession(); // quiet check
    if (!mounted) return;

    final bool isLinked = _googleSyncEnabled && (_linkedCalendarSummary ?? '').isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),

        // Title
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Add event via Google calendar',
              style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],
        ),

        // Actions
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isLinked)
                _GoogleActionTile(
                  icon: Icons.cloud_sync,
                  text: 'Link a Google calendar',
                  onTap: () async {
                    Navigator.pop(context);
                    await _onAddGoogleSync();
                    await _loadGoogleCfg();
                  },
                ),
              if (isLinked)
                _GoogleActionTile(
                  icon: Icons.sync,
                  text: 'Sync now',
                  onTap: () async {
                    Navigator.pop(context);
                    await _syncNow();
                    await _loadGoogleCfg();
                  },
                ),
              if (isLinked)
                _GoogleActionTile(
                  icon: Icons.event_available,
                  text: 'Choose Google calendar',
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickCalendarAndImport();
                    await _loadGoogleCfg();
                  },
                ),
              if (_googleSignedIn || isLinked)
                _GoogleActionTile(
                  icon: Icons.account_circle,
                  text: 'Switch Google account',
                  onTap: () async {
                    Navigator.pop(context);
                    try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
                    setState(() {
                      _googleSyncEnabled = false;
                      _linkedCalendarSummary = null;
                      _googleSignedIn = false;
                    });
                    await _pickCalendarAndImport();
                    await _loadGoogleCfg();
                  },
                ),
              if (isLinked)
                _GoogleActionTile(
                  icon: Icons.link_off,
                  text: 'Disconnect & remove Google events',
                  destructive: true,
                  onTap: () async {
                    Navigator.pop(context);
                    await _onToggleGoogleSync(false);
                    await _loadGoogleCfg();
                  },
                ),
            ],
          ),
        ),

        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _onToggleGoogleSync(bool enable) async {
    if (!enable) {
      final removed = await _purgeGoogleEventsFromMaster();
      if (_masterCalendarId != null) {
        await FirebaseFirestore.instance
            .collection('calendars')
            .doc(_masterCalendarId)
            .collection('integrations')
            .doc('google')
            .set({'enabled': false, 'calendarId': null, 'calendarSummary': null}, SetOptions(merge: true));
      }
      try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _googleSyncEnabled = false;
        _linkedCalendarSummary = null;
        _googleSignedIn = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sync off • removed $removed event(s).')),
      );
    }
  }

  Future<int> _purgeGoogleEventsFromMaster() async {
    final col = await _personalEventsCol();
    int deleted = 0;
    while (true) {
      final page = await col.where('source', isEqualTo: 'google').limit(400).get();
      if (page.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in page.docs) { batch.delete(d.reference); deleted++; }
      await batch.commit();
      if (page.docs.length < 400) break;
    }
    return deleted;
  }

  /// Entry point (used by menu and by card’s “Link a Google calendar”)
  Future<void> _onAddGoogleSync() async {
    if (_masterCalendarId == null) await _initMasterId();
    if (_masterCalendarId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master calendar not found.')),
      );
      return;
    }

    if (!await _ensureGoogleSession()) return;

    final cfgSnap = await FirebaseFirestore.instance
        .collection('calendars')
        .doc(_masterCalendarId)
        .collection('integrations')
        .doc('google')
        .get();

    final cfg = cfgSnap.data();
    if (cfg != null && (cfg['calendarId'] as String?) != null) {
      await _syncNow(); // already linked → sync
    } else {
      await _pickCalendarAndImport(); // first-time
    }
    await _loadEvents();
  }

  Future<void> _pickCalendarAndImport() async {
    if (!await _ensureGoogleSession()) return;

    final svc = GoogleCalendarService.instance;

    // 1) Connect / fetch calendars with feedback
    final calendars = await _withLoading<List<gcal.CalendarListEntry>>(
      message: 'Connecting to Google…',
      task: () => svc.listCalendars(),
    );
    if (calendars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Google calendars found.')));
      return;
    }

    // 2) Choose calendar
    final chosen = await showModalBottomSheet<gcal.CalendarListEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CalendarPicker(calendars: calendars),
    );
    if (chosen == null) return;

    // 3) Fetch events (last 6m → next 12m)
    final now = DateTime.now();
    final pulled = await _withLoading(
      message: 'Fetching events…',
      task: () => svc.listEvents(
        calendarId: chosen.id!,
        syncToken: null,
        timeMin: DateTime(now.year, now.month - 6, now.day),
        timeMax: DateTime(now.year + 1, now.month, now.day),
      ),
    );

    // 4) Map → local + preview select
    final currentUserId = await getCurrentUserId();
    final preview = <Map<String, dynamic>>[];
    for (final e in pulled.events) {
      final m = _mapGoogleEventToLocalDoc(e);
      if (m == null) continue;
      m['googleCalendarId'] = chosen.id;
      m['iCalUID'] = e.iCalUID;
      m['importedByUserId'] = currentUserId;
      preview.add(m);
    }
    preview.sort((a, b) =>
        (a['startTime'] as Timestamp).toDate().compareTo((b['startTime'] as Timestamp).toDate()));

    final selected = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PreviewSelectSheet(events: preview, calendarName: chosen.summary ?? chosen.id!),
    );
    if (selected == null || selected.isEmpty) return;

    // 5) Import selected
    final imported = await _importEventsToMaster(selected);

    // 6) Save config
    if (_masterCalendarId != null) {
      await FirebaseFirestore.instance
          .collection('calendars')
          .doc(_masterCalendarId)
          .collection('integrations')
          .doc('google')
          .set({
        'enabled': true,
        'calendarId': chosen.id,
        'calendarSummary': chosen.summary,
        'syncToken': pulled.nextSyncToken,
        'lastSyncAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $imported event(s) from Google.')),
    );

    await _loadGoogleCfg();
    await _loadEvents();
  }

  Future<void> _syncNow() async {
    if (_masterCalendarId == null) return;
    if (!await _ensureGoogleSession()) return;

    final cfgSnap = await FirebaseFirestore.instance
        .collection('calendars')
        .doc(_masterCalendarId)
        .collection('integrations')
        .doc('google')
        .get();
    final cfg = cfgSnap.data() ?? {};
    final String? gCalId = cfg['calendarId'] as String?;
    String? syncToken = cfg['syncToken'] as String?;

    if (gCalId == null) return;

    final svc = GoogleCalendarService.instance;
    final now = DateTime.now();

    final pulled = await _withLoading(
      message: 'Syncing…',
      task: () => svc.listEvents(
        calendarId: gCalId,
        syncToken: syncToken, // incremental if token exists
        timeMin: DateTime(now.year, now.month - 6, now.day),
        timeMax: DateTime(now.year + 1, now.month, now.day),
      ),
    );

    final currentUserId = await getCurrentUserId();
    final locals = <Map<String, dynamic>>[];
    for (final e in pulled.events) {
      final m = _mapGoogleEventToLocalDoc(e);
      if (m == null) continue;
      m['googleCalendarId'] = gCalId;
      m['iCalUID'] = e.iCalUID;
      m['importedByUserId'] = currentUserId;
      locals.add(m);
    }

    final imported = await _importEventsToMaster(locals);

    await FirebaseFirestore.instance
        .collection('calendars')
        .doc(_masterCalendarId)
        .collection('integrations')
        .doc('google')
        .set({
      'syncToken': pulled.nextSyncToken ?? syncToken,
      'lastSyncAt': Timestamp.now(),
    }, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sync complete. Imported $imported event(s).')),
    );

    await _loadEvents();
  }

  // Map Google event → local schema
  Map<String, dynamic>? _mapGoogleEventToLocalDoc(gcal.Event e) {
    if (e.status == 'cancelled') return null;

    final title = e.summary ?? '(No title)';
    final desc = e.description;

    DateTime? start;
    DateTime? end;

    if (e.start?.dateTime != null && e.end?.dateTime != null) {
      start = e.start!.dateTime!.toLocal();
      end = e.end!.dateTime!.toLocal();
    } else if (e.start?.date != null && e.end?.date != null) {
      // All-day: end is exclusive → convert to inclusive end-of-day
      final s = e.start!.date!;
      final t = e.end!.date!;
      start = DateTime(s.year, s.month, s.day, 0, 0, 0);
      final endExclusive = DateTime(t.year, t.month, t.day, 0, 0, 0);
      end = endExclusive.subtract(const Duration(seconds: 1));
    } else {
      return null;
    }

    if (end.isBefore(start)) return null;

    return {
      'title': title,
      'description': desc,
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'isAllDay': e.start?.date != null,
      'googleEventId': e.id,
      'iCalUID': e.iCalUID,
      'source': 'google',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Import with de-dupe into current user's Master calendar events
  Future<int> _importEventsToMaster(List<Map<String, dynamic>> toImport) async {
    if (toImport.isEmpty) return 0;

    final eventsCol = await _personalEventsCol();

    // Fetch recent existing to dedupe (1 year)
    final now = DateTime.now();
    final from = DateTime(now.year - 1);
    final existingSnap = await eventsCol
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .limit(3000)
        .get();

    final seen = <String>{};
    for (final d in existingSnap.docs) {
      final m = d.data();
      final ts1 = (m['startTime'] as Timestamp?)?.toDate();
      final ts2 = (m['endTime'] as Timestamp?)?.toDate();
      final k = '${m['iCalUID'] ?? ''}|${m['googleEventId'] ?? ''}|${m['title']}|$ts1|$ts2';
      seen.add(k);
    }

    final batch = FirebaseFirestore.instance.batch();
    int count = 0;
    for (final ev in toImport) {
      final ts1 = (ev['startTime'] as Timestamp).toDate();
      final ts2 = (ev['endTime'] as Timestamp).toDate();
      final k = '${ev['iCalUID'] ?? ''}|${ev['googleEventId'] ?? ''}|${ev['title']}|$ts1|$ts2';
      if (seen.contains(k)) continue;
      batch.set(eventsCol.doc(), ev);
      count++;
      if (count % 400 == 0) await batch.commit();
    }
    if (count % 400 != 0) await batch.commit();
    return count;
  }

  // ---------- UI ----------

  Widget _buildEventCard(Map<String, dynamic> event, {DateTime? displayDate}) {
    final String creator = (event['creatorName'] ?? '').toString().trim();
    final String calendarName = (event['calendarName'] ?? '').toString().trim();
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
                child: Text('•', style: TextStyle(fontSize: 20, height: 1.2, color: textDark)),
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
                    if (isSharedEvent && creator.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          calendarName.isNotEmpty ? 'by $creator on $calendarName' : 'by $creator',
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
          final lastDay = DateTime(focusedDay.year, focusedDay.month + 1, 0).day;
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
                margin: const EdgeInsets.symmetric(horizontal: 0.5, vertical: 1.5),
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
                    MediaQuery.of(context).size.width < 500
                        ? SizedBox(height: 440, child: calendarWidget)
                        : calendarWidget,
                    const SizedBox(height: 12),

                    // ===== Toolbar (chips + Google button + Add Event) =====
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 480;

                              final chips = Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Day'),
                                    selected: _agendaView == _AgendaView.day,
                                    onSelected: (_) => setState(() => _agendaView = _AgendaView.day),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Month'),
                                    selected: _agendaView == _AgendaView.month,
                                    onSelected: (_) => setState(() => _agendaView = _AgendaView.month),
                                  ),
                                ],
                              );

                              Widget googleBtn() => ElevatedButton.icon(
                                    onPressed: _openGoogleCard,
                                    icon: const Icon(Icons.cloud_sync, size: 18),
                                    label: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 210),
                                      child: Text(
                                        _googleSyncEnabled
                                            ? (_linkedCalendarSummary?.isNotEmpty == true
                                                ? 'Google: ${_linkedCalendarSummary!}'
                                                : 'Google linked')
                                            : 'Google Calendar',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: lightCard,
                                      foregroundColor: textDark,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      textStyle: const TextStyle(fontSize: 13),
                                    ),
                                  );

                              Widget addBtn() => ElevatedButton.icon(
                                    onPressed: _openManualAdd,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add Event'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: lightCard,
                                      foregroundColor: textDark,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      textStyle: const TextStyle(fontSize: 13),
                                    ),
                                  );

                              if (narrow) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    chips,
                                    const SizedBox(height: 10),
                                    Wrap(spacing: 8, runSpacing: 8, children: [googleBtn(), addBtn()]),
                                  ],
                                );
                              } else {
                                return Row(
                                  children: [
                                    Expanded(child: chips),
                                    const SizedBox(width: 8),
                                    googleBtn(),
                                    const SizedBox(width: 8),
                                    addBtn(),
                                  ],
                                );
                              }
                            },
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

                    if (_agendaView == _AgendaView.day)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8),
                        itemCount: _getEventsForDay(_selectedDay).length,
                        itemBuilder: (context, index) => _buildEventCard(_getEventsForDay(_selectedDay)[index]),
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

// ===== Reusable tiles/sheets (same style as shared) =====

class _GoogleActionTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool destructive;
  final VoidCallback? onTap;

  const _GoogleActionTile({
    required this.icon,
    required this.text,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled ? Colors.grey : (destructive ? Colors.red : Colors.black87);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}

class _CalendarPicker extends StatelessWidget {
  final List<gcal.CalendarListEntry> calendars;
  const _CalendarPicker({required this.calendars});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Choose a Google Calendar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: calendars.length,
                itemBuilder: (_, i) {
                  final c = calendars[i];
                  return ListTile(
                    leading: const Icon(Icons.event),
                    title: Text(c.summary ?? c.id ?? 'Unnamed'),
                    subtitle: Text(c.id ?? ''),
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSelectSheet extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final String calendarName;
  const _PreviewSelectSheet({required this.events, required this.calendarName});

  @override
  State<_PreviewSelectSheet> createState() => _PreviewSelectSheetState();
}

class _PreviewSelectSheetState extends State<_PreviewSelectSheet> {
  late final Set<int> _selected; // indices

  @override
  void initState() {
    super.initState();
    _selected = { for (int i = 0; i < widget.events.length; i++) i }; // default: all
  }

  String _line(Map<String, dynamic> m) {
    final s = (m['startTime'] as Timestamp).toDate();
    final e = (m['endTime'] as Timestamp).toDate();
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('HH:mm');
    return sameDay
        ? '${df.format(s)}  ${tf.format(s)}–${tf.format(e)}'
        : '${df.format(s)} ${df.format(s)} → ${df.format(e)} ${df.format(e)}';
  }

  bool? _masterCheckValue() {
    if (_selected.isEmpty) return false;
    if (_selected.length == widget.events.length) return true;
    return null; // indeterminate
  }

  void _toggleMaster(bool? v) {
    setState(() {
      if (v == true) {
        _selected.addAll(List.generate(widget.events.length, (i) => i));
      } else {
        _selected.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import from "${widget.calendarName}"',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('${widget.events.length} events found (last 6 months → next 12 months)'),

            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _masterCheckValue(),
                  onChanged: _toggleMaster,
                  tristate: true,
                ),
                const SizedBox(width: 4),
                const Text('Select all'),
                const Spacer(),
                Text('${_selected.length} selected'),
              ],
            ),
            const Divider(height: 1),

            Expanded(
              child: ListView.separated(
                controller: controller,
                itemCount: widget.events.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = widget.events[i];
                  final checked = _selected.contains(i);
                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(i);
                        } else {
                          _selected.remove(i);
                        }
                      });
                    },
                    title: Text(m['title'] ?? '(No title)'),
                    subtitle: Text(_line(m)),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text('Import (${_selected.length})'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final chosen = _selected.map((i) => widget.events[i]).toList(growable: false);
                            Navigator.of(context).pop(chosen);
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
