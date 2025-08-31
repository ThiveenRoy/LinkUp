// lib/screens/shared_calendar_screen.dart
// Shared calendar with:
//  - Add Event button → opens manual dialog directly
//  - Google button → opens a card-style AlertDialog with actions
//  - Quiet Google auth (no auto popup)
//  - Day/Month agenda, real-time stream, member toasts, creator labels

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../utils/guest_helper.dart';
import '../common/event_crud.dart';
import '../services/google_sync.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

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
  _AgendaView _agendaView = _AgendaView.day;

  String? _currentUserId;
  Map<String, dynamic>? _calendarData;
  bool _canEdit = false;
  List<Map<String, String>> _participants = [];

  // Google state (from Firestore; auth is checked quietly on demand)
  bool _googleSyncEnabled = false;
  String? _linkedCalendarSummary;
  bool _googleSignedIn = false;

  // Build the same unique key used by your import dedupe
  String _keyForLocal(Map<String, dynamic> m) {
    final ts1 = (m['startTime'] as Timestamp).toDate();
    final ts2 = (m['endTime'] as Timestamp).toDate();
    final iCal = (m['iCalUID'] ?? '') as String;
    final gid  = (m['googleEventId'] ?? '') as String;
    final title = (m['title'] ?? '') as String;
    return '$iCal|$gid|$title|$ts1|$ts2';
  }

  String _keyForMapped(Map<String, dynamic> m) => _keyForLocal(m);

  // Standard sync window: last 6 months → next 12 months
  ({DateTime from, DateTime to}) _syncWindow() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 6, now.day);
    final to   = DateTime(now.year + 1, now.month, now.day);
    return (from: from, to: to);
  }


  // Live member listener
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _memberSub;
  bool _membersInitialized = false;
  Set<String> _seenMemberIds = {};

  // theme
  final Color bgColor = const Color(0xFFF9F7F7);
  final Color lightCard = const Color(0xFFDBE2EF);
  final Color buttonColor = const Color(0xFF3F72AF);
  final Color textDark = const Color(0xFF112D4E);

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _userIdFuture = getCurrentUserId();
    _userIdFuture.then((id) async {
      _currentUserId = id;
      if (widget.calendarId != null) {
        await _loadPermissions();
        await _loadCalendarDetails();
        await _loadGoogleCfg(); // Firestore only; no auth popup
        await _loadMembers();
        _startMemberListener(widget.calendarId!);
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  // --------- helpers ---------
  void _toast(String msg, {IconData? icon, Color? color}) {
  final c = color ?? buttonColor;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: c,
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
        ],
      ),
    ),
  );
}


  Future<bool> _ensureGoogleSession() async {
    final svc = GoogleCalendarService.instance;

    // Quiet path first (no popup)
    final has = await svc.hasSession();
    if (has) {
      if (mounted) setState(() => _googleSignedIn = true);
      return true;
    }

    // Fallback to interactive popup only if needed
    try {
      await svc.ensureSignedInInteractive();
      if (mounted) setState(() => _googleSignedIn = true);
      return true;
    } catch (_) {
      return false;
    }
  }


  /// Upsert non-cancelled events by googleEventId/iCalUID; delete cancelled ones.
  /// Returns (added, updated, deleted) counts.
  Future<({int added, int updated, int deleted})> _applyGoogleDelta({
    required String calendarId,
    required List<gcal.Event> upserts,
    required List<gcal.Event> deletes,
  }) async {
    final col = FirebaseFirestore.instance
        .collection('calendars')
        .doc(calendarId)
        .collection('events');

    int added = 0, updated = 0, deleted = 0;

    // --- handle deletions (status == 'cancelled') ---
    for (final e in deletes) {
      final id = e.id;
      final uid = e.iCalUID;

      // delete by googleEventId
      if (id != null) {
        final q1 = await col.where('googleEventId', isEqualTo: id).limit(20).get();
        if (q1.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (final d in q1.docs) {
            batch.delete(d.reference);
            deleted++;
          }
          await batch.commit();
        }
      }
      // fallback delete by iCalUID (some calendars rely on this)
      if (uid != null) {
        final q2 = await col.where('iCalUID', isEqualTo: uid).limit(20).get();
        if (q2.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (final d in q2.docs) {
            batch.delete(d.reference);
            deleted++;
          }
          await batch.commit();
        }
      }
    }

    // --- upsert non-cancelled events ---
    for (final e in upserts) {
      final m = _mapGoogleEventToLocalDoc(e);
      if (m == null) continue;
      final id = e.id;
      final uid = e.iCalUID;

      QuerySnapshot<Map<String, dynamic>> found = await col
          .where('googleEventId', isEqualTo: id)
          .limit(1)
          .get();

      // If not found by googleEventId, try iCalUID
      if (found.docs.isEmpty && uid != null) {
        found = await col.where('iCalUID', isEqualTo: uid).limit(1).get();
      }

      if (found.docs.isEmpty) {
        // insert
        await col.add(m);
        added++;
      } else {
        // update key fields
        final ref = found.docs.first.reference;
        await ref.update({
          'title': m['title'],
          'description': m['description'],
          'startTime': m['startTime'],
          'endTime': m['endTime'],
          'isAllDay': m['isAllDay'],
          'updatedAt': FieldValue.serverTimestamp(),
        });
        updated++;
      }
    }

    return (added: added, updated: updated, deleted: deleted);
  }


  Future<T> _withLoading<T>({
    required String message,
    required Future<T> Function() task,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
              SizedBox(width: 12),
              Flexible(child: Text('Working…', style: TextStyle(fontSize: 14))),
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
    }
  }

  // --------- members ---------
  void _startMemberListener(String calendarId) {
    _memberSub?.cancel();
    _memberSub = FirebaseFirestore.instance
        .collection('calendars')
        .doc(calendarId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return;

      final List rawMembers = (data['members'] ?? []) as List;
      final current = rawMembers.map<Map<String, String>>((e) {
        if (e is Map) {
          return {'id': (e['id'] ?? '').toString(), 'name': (e['name'] ?? 'Anonymous').toString()};
        } else {
          return {'id': e.toString(), 'name': 'Anonymous'};
        }
      }).toList();

      if (mounted) setState(() => _participants = current);

      final currIds = current.map((p) => p['id']!).toSet();
      if (!_membersInitialized) {
        _seenMemberIds = currIds;
        _membersInitialized = true;
        return;
      }
      final left = _seenMemberIds.difference(currIds);
      final joined = currIds.difference(_seenMemberIds);
      if (left.isNotEmpty) {
        _toast('A member left the calendar', icon: Icons.logout, color: Colors.redAccent);
      }
      if (joined.isNotEmpty) {
        final names = current.where((p) => joined.contains(p['id'])).map((p) => p['name']).join(', ');
        _toast('$names joined the calendar 🎉', icon: Icons.person_add_alt_1, color: buttonColor);
      }
      _seenMemberIds = currIds;
    });
  }

  Future<void> _loadMembers() async {
    final doc = await FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).get();
    final data = doc.data();
    if (data == null) return;
    final members = (data['members'] ?? []) as List<dynamic>;
    setState(() {
      _participants = members.map<Map<String, String>>((e) {
        if (e is Map) {
          return {'id': (e['id'] ?? '').toString(), 'name': (e['name'] ?? 'Anonymous').toString()};
        } else {
          return {'id': e.toString(), 'name': 'Anonymous'};
        }
      }).toList();
    });
  }

  // --------- permissions/meta ---------
  Future<void> _loadPermissions() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId');
    final currentId = user?.uid ?? guestId;

    final doc = await FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).get();
    final data = doc.data();
    if (data == null || currentId == null) return;

    final ownerId = (data['owner'] ?? '').toString();
    final allowEdit = data['allowEdit'] ?? false;
    final isOwner = currentId == ownerId;
    final hasGuestEditAccess = prefs.getBool('editAccess_${widget.calendarId}') ?? false;

    setState(() {
      _canEdit = isOwner || (allowEdit && hasGuestEditAccess);
    });
  }

  Future<void> _loadCalendarDetails() async {
    final doc = await FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).get();
    if (doc.exists) setState(() => _calendarData = doc.data());
  }

  // --------- google cfg ---------
  Future<void> _loadGoogleCfg() async {
    final id = widget.calendarId;
    if (id == null) return;
    final cfg = await loadGoogleCfgForCalendar(id);
    setState(() {
      _googleSyncEnabled = cfg.enabled;
      _linkedCalendarSummary = cfg.calendarSummary;
    });
  }

  // --------- UI helpers ---------
  String _formatEventTime(DateTime? selectedDate, DateTime? start, DateTime? end) {
    if (start == null || end == null || selectedDate == null) return '';
    final sd = DateFormat('d MMM yyyy').format(selectedDate);
    final st = DateFormat('h:mm a').format(start);
    final et = DateFormat('h:mm a').format(end);
    return '$sd, $st – $et';
  }

  Color _colorForId(String id) {
    int hash = id.codeUnits.fold(0, (h, c) => 0x1fffffff & (h * 31 + c));
    final r = 50 + (hash & 0x7F);
    final g = 50 + ((hash >> 7) & 0x7F);
    final b = 50 + ((hash >> 14) & 0x7F);
    return Color.fromARGB(255, r, g, b);
  }

  Future<CollectionReference<Map<String, dynamic>>> _sharedEventsCol() async {
    return FirebaseFirestore.instance
        .collection('calendars')
        .doc(widget.calendarId)
        .collection('events');
  }

  Future<void> _touchCalendar({String? byId, String? byName}) async {
    return FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).update({
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      if (byId != null) 'updatedBy': byId,
      if (byName != null) 'updatedByName': byName,
    });
  }

  // --------- Add Event (manual) ---------
  Future<void> _openManualAdd() async {
    final editorName = await _resolveDisplayName();
    await EventCrud.showAddOrEditDialog(
      context: context,
      getEventsCollection: _sharedEventsCol,
      canEdit: _canEdit,
      disallowPastDates: true,
      existingEvent: null,
      creatorId: _currentUserId,
      creatorName: editorName,
      initialSelectedDay: _selectedDay,
      onAfterWrite: () => _touchCalendar(byId: _currentUserId, byName: editorName),
      buttonColor: buttonColor,
      textDark: textDark,
    );
  }

  // --------- Google actions CARD (AlertDialog) ---------
  Future<void> _openGoogleCard() async {
  // Quiet session check (NO popup)
    _googleSignedIn = await GoogleCalendarService.instance.hasSession();
    if (!mounted) return;

    final bool isLinked =
        _googleSyncEnabled && (_linkedCalendarSummary ?? '').isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),

        // ===== Title =====
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                Text(
                  'Add event via Google calendar',
                  style: TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 12)
          ],
        ),

        // ===== Content (actions) =====
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isLinked) // hide once linked
                _GoogleActionTile(
                  icon: Icons.cloud_sync,
                  text: 'Link a Google calendar',
                  onTap: !_canEdit
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _onAddGoogleSync();
                        },
                ),

              if (isLinked)
                _GoogleActionTile(
                  icon: Icons.sync,
                  text: 'Sync now',
                  onTap: !_canEdit
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _syncNow();
                        },
                ),

              if (isLinked)
                _GoogleActionTile(
                  icon: Icons.event_available,
                  text: 'Choose Google calendar',
                  onTap: !_canEdit
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _chooseAnotherCalendar();
                        },
                ),

              if (_googleSignedIn || isLinked)
                _GoogleActionTile(
                  icon: Icons.account_circle,
                  text: 'Switch Google account',
                  onTap: !_canEdit
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _switchGoogleAccount();
                        },
                ),

              if (isLinked)
                _GoogleActionTile(
                  icon: Icons.link_off,
                  text: 'Disconnect & remove Google events',
                  destructive: true,
                  onTap: !_canEdit
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _onToggleGoogleSync(false);
                        },
                ),
            ],
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }



  // --------- Google logic ---------
  Future<void> _onAddGoogleSync() async {
    if (!_canEdit) { _toast('You need edit access to manage Google sync', icon: Icons.lock, color: Colors.grey); return; }
    if (!await _ensureGoogleSession()) return;
    final id = widget.calendarId!;
    final cfg = await loadGoogleCfgForCalendar(id);
    if (cfg.enabled && (cfg.calendarId ?? '').isNotEmpty) {
      await _syncNow();
    } else {
      await _pickCalendarAndImport();
    }
  }

  Future<void> _onToggleGoogleSync(bool enable) async {
    final id = widget.calendarId;
    if (id == null) return;
    if (!_canEdit) {
      _toast('You need edit access to manage Google sync', icon: Icons.lock, color: Colors.grey);
      return;
    }

    if (!enable) {
      await saveGoogleCfgForCalendar(id, GoogleIntegrationConfig(enabled: false));
      final removed = await _withLoading<int>(
        message: 'Removing Google events…',
        task: () => _purgeGoogleEventsForThisCalendar(id),
      );
      try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
      setState(() {
        _googleSyncEnabled = false;
        _linkedCalendarSummary = null;
        _googleSignedIn = false;
      });
      _toast('Google sync off • removed $removed events', icon: Icons.link_off, color: Colors.deepOrange);
      return;
    }

    await _pickCalendarAndImport();
  }

  Future<int> _purgeGoogleEventsForThisCalendar(String calendarId) async {
    final col = FirebaseFirestore.instance.collection('calendars').doc(calendarId).collection('events');
    Query<Map<String, dynamic>> q = col.where('source', isEqualTo: 'google');

    int deleted = 0;
    while (true) {
      final page = await q.limit(400).get();
      if (page.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
        deleted++;
      }
      await batch.commit();
      if (page.docs.length < 400) break;
    }
    return deleted;
  }

  Future<void> _switchGoogleAccount() async {
    try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
    setState(() {
      _googleSyncEnabled = false;
      _linkedCalendarSummary = null;
      _googleSignedIn = false;
    });
    await _pickCalendarAndImport();
  }

  Future<void> _chooseAnotherCalendar() async {
    if (!await _ensureGoogleSession()) return;
    await _pickCalendarAndImport();
  }

  Future<void> _pickCalendarAndImport() async {
    if (!await _ensureGoogleSession()) return;
    final id = widget.calendarId!;
    final svc = GoogleCalendarService.instance;

    if (!_canEdit) {
      _toast('You need edit access to import from Google', icon: Icons.lock, color: Colors.grey);
      return;
    }

    final calendars = await _withLoading<List<gcal.CalendarListEntry>>(
      message: 'Connecting to Google…',
      task: () => svc.listCalendars(),
    );
    if (calendars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Google calendars found.')));
      return;
    }

    final chosen = await showModalBottomSheet<gcal.CalendarListEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CalendarPicker(calendars: calendars),
    );
    if (chosen == null) return;

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

    final preview = <Map<String, dynamic>>[];
    for (final e in pulled.events) {
      final m = _mapGoogleEventToLocalDoc(e);
      if (m != null) preview.add(m);
    }
    preview.sort((a, b) =>
        (a['startTime'] as Timestamp).toDate().compareTo((b['startTime'] as Timestamp).toDate()));

    final selected = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PreviewSelectSheet(
        events: preview,
        calendarName: chosen.summary ?? chosen.id!,
        buttonColor: buttonColor,
        textDark: textDark,
      ),
    );
    if (selected == null || selected.isEmpty) return;

    final imported = await _importEventsToShared(calendarId: id, events: selected);

    final cfg = GoogleIntegrationConfig(
      enabled: true,
      calendarId: chosen.id,
      calendarSummary: chosen.summary,
      syncToken: pulled.nextSyncToken,
      lastSyncAt: DateTime.now(),
    );
    await saveGoogleCfgForCalendar(id, cfg);

    setState(() {
      _googleSyncEnabled = true;
      _linkedCalendarSummary = chosen.summary;
      _googleSignedIn = true;
    });

    _toast('Imported $imported events from Google.', icon: Icons.cloud_done, color: buttonColor);
  }

  Future<void> _syncNow() async {
    if (!await _ensureGoogleSession()) return;

    final id = widget.calendarId!;
    final cfg = await loadGoogleCfgForCalendar(id);
    final gCalId = cfg.calendarId;
    if (gCalId == null) {
      _toast('No linked Google calendar to sync.', color: Colors.grey);
      return;
    }

    final svc = GoogleCalendarService.instance;
    final win = _syncWindow();

    // 1) Pull the full window from Google (not incremental)
    final pulled = await _withLoading(
      message: 'Syncing…',
      task: () => svc.listEvents(
        calendarId: gCalId,
        syncToken: null,                       // <-- full refresh
        timeMin: win.from,
        timeMax: win.to,
      ),
    );

    // 2) Map Google → local format
    final googleMapped = <Map<String, dynamic>>[];
    for (final e in pulled.events) {
      final m = _mapGoogleEventToLocalDoc(e);
      if (m != null) googleMapped.add(m);
    }

    // Build set of keys from Google
    final googleKeys = <String>{ for (final m in googleMapped) _keyForMapped(m) };

    // 3) Read existing local Google events in the same window
    final col = FirebaseFirestore.instance
        .collection('calendars')
        .doc(id)
        .collection('events');

    final existingSnap = await col
        .where('source', isEqualTo: 'google')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(win.from))
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(win.to))
        .limit(3000)
        .get();

    final existingByDoc = <String, Map<String, dynamic>>{};
    final existingKeys = <String, String>{}; // key -> docId
    for (final d in existingSnap.docs) {
      final m = d.data();
      final key = _keyForLocal(m);
      existingByDoc[d.id] = m;
      existingKeys[key] = d.id;
    }

    // 4) Diff
    final toAdd = <Map<String, dynamic>>[];
    for (final m in googleMapped) {
      final key = _keyForMapped(m);
      if (!existingKeys.containsKey(key)) toAdd.add(m);
    }

    final toDelete = <String>[]; // docIds
    for (final entry in existingKeys.entries) {
      if (!googleKeys.contains(entry.key)) {
        toDelete.add(entry.value);
      }
    }

    // 5) Apply (batched)
    int added = 0, deleted = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();

    for (final m in toAdd) {
      batch.set(col.doc(), m);
      added++;
      if (added % 400 == 0) { await batch.commit(); batch = FirebaseFirestore.instance.batch(); }
    }

    for (final docId in toDelete) {
      batch.delete(col.doc(docId));
      deleted++;
      if (deleted % 400 == 0) { await batch.commit(); batch = FirebaseFirestore.instance.batch(); }
    }

    await batch.commit();

    // 6) Save metadata (keep token fresh if provided; not essential for our full refresh)
    await saveGoogleCfgForCalendar(
      id,
      cfg.copyWith(
        syncToken: pulled.nextSyncToken ?? cfg.syncToken,
        lastSyncAt: DateTime.now(),
      ),
    );

    // 7) Toast result (plain text)
    _toast('Sync complete: added $added, deleted $deleted');
  }



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

  Future<int> _importEventsToShared({
    required String calendarId,
    required List<Map<String, dynamic>> events,
  }) async {
    if (events.isEmpty) return 0;

    final ref = FirebaseFirestore.instance
        .collection('calendars')
        .doc(calendarId)
        .collection('events');

    // De-dupe: last year by composite key
    final now = DateTime.now();
    final from = DateTime(now.year - 1);
    final existingSnap = await ref
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

    // Who is importing?
    final importerName = await _resolveDisplayName();
    final importerId = _currentUserId ?? 'guest';

    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (final raw in events) {
      // copy so we can augment
      final ev = Map<String, dynamic>.from(raw);

      // ensure creator meta exists
      ev['creatorId']   ??= importerId;
      ev['creatorName'] ??= importerName;

      final ts1 = (ev['startTime'] as Timestamp).toDate();
      final ts2 = (ev['endTime'] as Timestamp).toDate();
      final k = '${ev['iCalUID'] ?? ''}|${ev['googleEventId'] ?? ''}|${ev['title']}|$ts1|$ts2';
      if (seen.contains(k)) continue;

      batch.set(ref.doc(), ev);
      count++;
      if (count % 400 == 0) await batch.commit();
    }

    if (count % 400 != 0) await batch.commit();
    return count;
  }


  // --------- build ---------
  @override
  Widget build(BuildContext context) {
    if (widget.calendarId == null) {
      return const Scaffold(body: Center(child: Text('No calendar selected.')));
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => widget.onBackToList?.call()),
        title: Text(widget.calendarName ?? 'Shared Calendar'),
        actions: [
          // participants/guest chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: () {
                const maxAvatars = 5;
                final visible = _participants.take(maxAvatars).toList();
                final extra = _participants.length - visible.length;

                String _initial(String s) =>
                    (s.isNotEmpty ? s[0] : '?').toUpperCase();

                return [
                  ...visible.map((user) {
                    final name = (user['name'] ?? 'Guest').toString();
                    final isGuest = name.toLowerCase().contains('guest') ||
                        name.toLowerCase().contains('anonymous');
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message: name,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: isGuest ? Colors.grey[500] : buttonColor,
                          child: Text(
                            _initial(name),
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (extra > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.grey[600],
                        child: Text(
                          '+$extra',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ];
              }(),
            ),
          ),

          if (_calendarData != null && _calendarData!['owner'] == _currentUserId)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Collaborative Calendar'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _showShareModal(widget.calendarId!),
              ),
            ),
        ]
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
                final normalizedEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);

                final displayTitle = (ownerId != _currentUserId) ? '${data['title']}' : (data['title'] ?? '');
                colors[d.id] = _colorForId(d.id);

                for (DateTime dt = start; !dt.isAfter(normalizedEnd); dt = dt.add(const Duration(days: 1))) {
                  final key = DateTime(dt.year, dt.month, dt.day);
                  (byDay[key] ??= []).add({
                    ...data,
                    'id': d.id,
                    'calendarId': widget.calendarId,
                    'title': displayTitle,
                    'calendarName': calendarName,
                  });
                }
              }
            }

            List<Map<String, dynamic>> eventsForDay(DateTime day) =>
                byDay[DateTime(day.year, day.month, day.day)] ?? [];

            Widget buildEventCard(Map<String, dynamic> event, {DateTime? displayDate}) {
              // -------- FIX: robust creator display (Guest → GUEST-xxxx) --------
              String resolveCreatorName() {
                final storedCreator = (event['creatorName'] as String?)?.trim() ?? '';
                if (storedCreator.isNotEmpty) return storedCreator;

                final creatorId = (event['creatorId'] ?? '').toString();
                String fromMembers = _participants
                        .firstWhere(
                          (p) => p['id'] == creatorId,
                          orElse: () => const {'name': 'Guest'},
                        )['name'] ??
                    'Guest';

                final lower = fromMembers.toLowerCase();
                if (lower == 'guest' || lower == 'anonymous' || fromMembers.trim().isEmpty) {
                  if (creatorId.isNotEmpty) {
                    final suffix = creatorId.length >= 4
                        ? creatorId.substring(creatorId.length - 4)
                        : creatorId;
                    return 'GUEST-${suffix.toUpperCase()}';
                  }
                  return 'Guest';
                }
                return fromMembers;
              }

              final creatorName = resolveCreatorName();
              final calendarName = (event['calendarName'] ?? '').toString().trim();

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
                              Text('${event['title']}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                              if (creatorName.isNotEmpty || calendarName.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    [
                                      if (creatorName.isNotEmpty) 'by $creatorName',
                                      if (calendarName.isNotEmpty) 'on $calendarName',
                                    ].join(' '),
                                    style: TextStyle(fontSize: 13, color: textDark.withOpacity(0.7), fontStyle: FontStyle.italic),
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
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textDark),
                                  ),
                                ),
                              if ((event['description'] ?? '').toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    event['description'],
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, fontFamily: 'Roboto', color: textDark.withOpacity(0.85)),
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
                            onPressed: () async {
                              final editorName = await _resolveDisplayName();
                              final startDate = (event['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                              if (_startOfDay(startDate).isBefore(_startOfDay(DateTime.now()))) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You can't edit events in the past.")));
                                return;
                              }
                              await EventCrud.showAddOrEditDialog(
                                context: context,
                                getEventsCollection: _sharedEventsCol,
                                canEdit: _canEdit,
                                disallowPastDates: true,
                                existingEvent: event,
                                updatedById: _currentUserId,
                                updatedByName: editorName,
                                onAfterWrite: () => _touchCalendar(byId: _currentUserId, byName: editorName),
                                buttonColor: buttonColor,
                                textDark: textDark,
                              );
                            },
                            child: const Text('Edit'),
                          ),
                        if (_canEdit)
                          TextButton(
                            onPressed: () => EventCrud.confirmAndDelete(
                              context: context,
                              getEventsCollection: _sharedEventsCol,
                              eventId: event['id'],
                              onAfterDelete: _touchCalendar,
                            ),
                            child: const Text('Delete'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }

            Widget buildMonthAgenda() {
              final first = DateTime(_focusedDay.year, _focusedDay.month, 1);
              final last = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
              final items = <Widget>[];
              for (int i = 0; i < last.day; i++) {
                final day = DateTime(first.year, first.month, first.day + i);
                final evs = eventsForDay(day);
                if (evs.isEmpty) continue;

                items.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text(
                      DateFormat('EEE, d MMM yyyy').format(day),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textDark.withOpacity(0.8)),
                    ),
                  ),
                );
                items.addAll(evs.map((e) => buildEventCard(e, displayDate: day)));
              }
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text('No events this month.'),
                );
              }
              return Column(children: items);
            }

            final calendarWidget = TableCalendar(
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
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                  final carry = _selectedDay.day;
                  final lastDay = DateTime(focusedDay.year, focusedDay.month + 1, 0).day;
                  final newDay = min(carry, lastDay);
                  _selectedDay = DateTime(focusedDay.year, focusedDay.month, newDay);
                });
              },
              eventLoader: eventsForDay,
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                headerPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              calendarBuilders: CalendarBuilders(
                headerTitleBuilder: (context, day) => Material(
                  color: Colors.transparent,
                  child: InkWell(
                    splashColor: Colors.transparent,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _focusedDay,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDatePickerMode: DatePickerMode.year,
                        initialEntryMode: DatePickerEntryMode.calendarOnly,
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today, size: 20, color: textDark),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('MMMM yyyy').format(_focusedDay),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark),
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
                      final color = colors[event['id']] ?? Colors.purple;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 0.5, vertical: 1.5),
                        width: 6, height: 6,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      );
                    }).toList(),
                  );
                },
              ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  calendarWidget,
                  const SizedBox(height: 12),

                  // Toolbar: chips + Google button + Add Event
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
                                  onPressed: _canEdit ? _openGoogleCard : null,
                                  icon: const Icon(Icons.cloud_sync, size: 18),
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 210),
                                    child: Text(
                                      _googleSyncEnabled
                                          ? (_linkedCalendarSummary?.isNotEmpty == true
                                              ? 'Google: ${_linkedCalendarSummary!}'
                                              : 'Google linked')
                                          : 'Import Google Calendar',
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
                                  onPressed: _canEdit ? _openManualAdd : null,
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
                                  if (_canEdit)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [googleBtn(), addBtn()],
                                    ),
                                ],
                              );
                            } else {
                              return Row(
                                children: [
                                  Expanded(child: chips),
                                  const SizedBox(width: 8),
                                  if (_canEdit) ...[
                                    googleBtn(),
                                    const SizedBox(width: 8),
                                    addBtn(),
                                  ],
                                ],
                              );
                            }
                          },
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

                  if (snap.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (snap.hasError)
                    const Center(child: Text('Failed to load events.'))
                  else ...[
                    if (_agendaView == _AgendaView.day)
                      Builder(builder: (_) {
                        final dayEvents = eventsForDay(_selectedDay);
                        if (dayEvents.isEmpty) return const Center(child: Text('No events found.'));
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: dayEvents.length,
                          itemBuilder: (context, index) => buildEventCard(dayEvents[index]),
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

  // --------- share modal ---------
  void _showShareModal(String calendarId) async {
    final calendarDoc = await FirebaseFirestore.instance.collection('calendars').doc(calendarId).get();
    final data = calendarDoc.data();
    if (data == null ||
        (!data.containsKey('sharedLinkEdit') && !data.containsKey('sharedLinkView'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to generate invite link.')));
      return;
    }

    bool allowEdit = data['allowEdit'] ?? false;
    String editLink = 'https://linkupcalendar.app/#/cal/${data['sharedLinkEdit']}';
    String viewLink = 'https://linkupcalendar.app/#/cal/${data['sharedLinkView']}';

    final TextEditingController linkController = TextEditingController(text: allowEdit ? editLink : viewLink);

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
                    onTap: () => linkController.selection = TextSelection(baseOffset: 0, extentOffset: linkController.text.length),
                    decoration: InputDecoration(
                      labelText: 'Invite Link',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: linkController.text));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied to clipboard'), duration: Duration(seconds: 5)),
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
                      await FirebaseFirestore.instance.collection('calendars').doc(calendarId).update({'allowEdit': value});
                      setModalState(() {
                        allowEdit = value;
                        linkController.text = value ? editLink : viewLink;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  Future<String> _resolveDisplayName() async {
    // Helper to build/read a stable guest tag
    Future<String> _guestFromPrefs() async {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('guestName');
      if (cached != null && cached.trim().isNotEmpty) return cached;

      final guestId = prefs.getString('guestId') ?? 'guest';
      final suffix = guestId.length >= 4
          ? guestId.substring(guestId.length - 4)
          : guestId;
      final generated = 'GUEST-${suffix.toUpperCase()}';
      await prefs.setString('guestName', generated);
      return generated;
    }

    final user = FirebaseAuth.instance.currentUser;

    // If there is no Firebase user, you are a guest
    if (user == null) {
      return _guestFromPrefs();
    }

    // Anonymous Firebase user → treat as guest
    if (user.isAnonymous) {
      return _guestFromPrefs();
    }

    // Real account: try displayName, then email
    final name = (user.displayName ?? '').trim();
    if (name.isNotEmpty) return name;

    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) return email;

    // Providerless/unknown profile → treat as guest
    if (user.providerData.isEmpty) {
      return _guestFromPrefs();
    }

    // Last resort (should not hit): still prefer guest tag over "User"
    return _guestFromPrefs();
  }

}

// ===== helpers/widgets =====
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
    return ListTile(
      leading: Icon(icon, color: disabled ? Colors.grey : (destructive ? Colors.red : Colors.black87)),
      title: Text(
        text,
        style: TextStyle(
          color: disabled ? Colors.grey : (destructive ? Colors.red : Colors.black87),
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      dense: true,
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
  final Color buttonColor;
  final Color textDark;

  const _PreviewSelectSheet({
    required this.events,
    required this.calendarName,
    required this.buttonColor,
    required this.textDark,
  });

  @override
  State<_PreviewSelectSheet> createState() => _PreviewSelectSheetState();
}

class _PreviewSelectSheetState extends State<_PreviewSelectSheet> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {for (int i = 0; i < widget.events.length; i++) i};
  }

  String _line(Map<String, dynamic> m) {
    final s = (m['startTime'] as Timestamp).toDate();
    final e = (m['endTime'] as Timestamp).toDate();
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('HH:mm');
    return sameDay
        ? '${df.format(s)}  ${tf.format(s)}–${tf.format(e)}'
        : '${df.format(s)} ${tf.format(s)} → ${df.format(e)} ${df.format(e)}';
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
            Text('Import from "${widget.calendarName}"', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('${widget.events.length} events found (last 6 months → next 12 months)'),
            const Divider(height: 16),
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
                    onChanged: (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i)),
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
