// lib/screens/shared_calendar_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../common/event_crud.dart';
import '../services/google_sync.dart';
import '../widgets/glass.dart';

enum _AgendaView { day, month }

// ----- shared glass tuning (used by calendar frame, event cards, google card)
class _GlassVars {
  final double blur, opacity, accentOpacity, borderWidth, shadowOpacity;
  const _GlassVars({
    required this.blur,
    required this.opacity,
    required this.accentOpacity,
    required this.borderWidth,
    required this.shadowOpacity,
  });
}

_GlassVars _glassVars(BuildContext c) {
  final isDark = Theme.of(c).brightness == Brightness.dark;
  return _GlassVars(
    blur: isDark ? 22 : 36,
    opacity: isDark ? 0.11 : 0.042, // lighter fill on light, crisp on dark
    accentOpacity: isDark ? 0.18 : 0.16,
    borderWidth: 0.9,
    shadowOpacity: isDark ? 0.25 : 0.10, // soft lift on light
  );
}

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
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  _AgendaView _agendaView = _AgendaView.day;

  String? _currentUserId;
  Map<String, dynamic>? _calendarData;
  bool _canEdit = false;
  List<Map<String, String>> _participants = [];

  // Google (per-user)
  bool _googleSyncEnabled = false;
  String? _linkedCalendarSummary;
  String? _linkedCalendarId;
  bool _googleSignedIn = false;

  // Member stream
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _memberSub;
  bool _membersInitialized = false;
  Set<String> _seenMemberIds = {};

  // ---- helpers / keying ----
  String _keyForLocal(Map<String, dynamic> m) {
    final ts1 = (m['startTime'] as Timestamp).toDate();
    final ts2 = (m['endTime'] as Timestamp).toDate();
    final iCal = (m['iCalUID'] ?? '') as String;
    final gid = (m['googleEventId'] ?? '') as String;
    final title = (m['title'] ?? '') as String;
    return '$iCal|$gid|$title|$ts1|$ts2';
  }

  String _keyForMapped(Map<String, dynamic> m) => _keyForLocal(m);

  ({DateTime from, DateTime to}) _syncWindow() {
    final now = DateTime.now();
    return (from: DateTime(now.year, now.month - 6, now.day),
            to:   DateTime(now.year + 1, now.month, now.day));
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      });
      return;
    }
    _currentUserId = user.uid;
    if (widget.calendarId != null) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadPermissions();
    await _loadCalendarDetails();
    await _loadGoogleCfgPerUser();
    await _loadMembers();
    _startMemberListener(widget.calendarId!);
    if (mounted) setState(() {});
  }

  // ---------- toast ----------
  void _toast(String msg, {IconData? icon, Color? color}) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
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

  // ---------- google session ----------
  Future<bool> _ensureGoogleSession() async {
    final svc = GoogleCalendarService.instance;
    final has = await svc.hasSession();
    if (has) {
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
    }
  }

  // ---------- members ----------
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
        if (e is Map) return {'id': (e['id'] ?? '').toString(), 'name': (e['name'] ?? 'User').toString()};
        return {'id': e.toString(), 'name': 'User'};
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
        _toast('$names joined the calendar 🎉', icon: Icons.person_add_alt_1);
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
        if (e is Map) return {'id': (e['id'] ?? '').toString(), 'name': (e['name'] ?? 'User').toString()};
        return {'id': e.toString(), 'name': 'User'};
      }).toList();
    });
  }

  Future<void> _loadPermissions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).get();
    final data = doc.data();
    if (data == null) return;
    final ownerId = (data['owner'] ?? '').toString();
    final allowEdit = data['allowEdit'] == true;
    setState(() {
      _canEdit = (user.uid == ownerId) || allowEdit;
    });
  }

  Future<void> _loadCalendarDetails() async {
    final doc = await FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).get();
    if (doc.exists) setState(() => _calendarData = doc.data());
  }

  Future<void> _loadGoogleCfgPerUser() async {
    final calId = widget.calendarId;
    final uid = _currentUserId;
    if (calId == null || uid == null) return;
    final cfg = await loadGoogleCfgForCalendar(calId, uid);
    setState(() {
      _googleSyncEnabled     = cfg.enabled;
      _linkedCalendarSummary = cfg.calendarSummary;
      _linkedCalendarId      = cfg.calendarId;
    });
  }

  // ---------- small helpers ----------
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

  Future<void> _touchCalendar({String? byId, String? byName}) {
    return FirebaseFirestore.instance.collection('calendars').doc(widget.calendarId).update({
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      if (byId != null) 'updatedBy': byId,
      if (byName != null) 'updatedByName': byName,
    });
  }

  // ---------- add event (manual) ----------
  Future<void> _openManualAdd() async {
    final editorName = await _resolveDisplayName();
    final cs = Theme.of(context).colorScheme;
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
      buttonColor: cs.primary,
      textDark: cs.onSurface,
    );
  }

  // ---------- Google card (glass)
  Future<void> _openGoogleCard() async {
    _googleSignedIn = await GoogleCalendarService.instance.hasSession();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent, // keep page bright
      builder: (_) {
        final theme  = Theme.of(context);
        final cs     = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final gv     = _glassVars(context);
        final bool isLinked = _googleSyncEnabled && (_linkedCalendarSummary ?? '').isNotEmpty;

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(boxShadow: [
              BoxShadow(
                blurRadius: isDark ? 18 : 22,
                offset: const Offset(0, 6),
                color: Colors.black.withOpacity(gv.shadowOpacity),
              ),
            ]),
            child: GlassPanel(
              radius: const BorderRadius.all(Radius.circular(18)),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              blur: gv.blur,
              opacity: gv.opacity,
              accentBorder: true,
              accentOpacity: gv.accentOpacity,
              borderWidth: gv.borderWidth,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add event via Google Calendar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),

                    if (!isLinked)
                      _GoogleActionTile(
                        icon: Icons.cloud_sync,
                        text: 'Link a Google calendar',
                        onTap: !_canEdit ? null : () async {
                          Navigator.pop(context);
                          await _onAddGoogleSync();
                        },
                      ),
                    if (isLinked)
                      _GoogleActionTile(
                        icon: Icons.sync,
                        text: 'Sync now',
                        onTap: !_canEdit ? null : () async {
                          Navigator.pop(context);
                          await _syncNow();
                        },
                      ),
                    if (isLinked)
                      _GoogleActionTile(
                        icon: Icons.event_available,
                        text: 'Choose Google calendar',
                        onTap: !_canEdit ? null : () async {
                          Navigator.pop(context);
                          await _chooseAnotherCalendar();
                        },
                      ),
                    if (_googleSignedIn || isLinked)
                      _GoogleActionTile(
                        icon: Icons.account_circle,
                        text: 'Switch Google account',
                        onTap: !_canEdit ? null : () async {
                          Navigator.pop(context);
                          await _switchGoogleAccount();
                        },
                      ),
                    if (isLinked)
                      _GoogleActionTile(
                        icon: Icons.link_off,
                        text: 'Disconnect & remove my Google events',
                        destructive: true,
                        onTap: !_canEdit ? null : () async {
                          Navigator.pop(context);
                          await _onToggleGoogleSync(false);
                        },
                      ),

                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: cs.primary,
                          overlayColor: cs.primary.withOpacity(0.08),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- Google logic (unchanged)
  Future<void> _onAddGoogleSync() async {
    if (!_canEdit) { _toast('You need edit access to manage Google sync', icon: Icons.lock, color: Colors.grey); return; }
    if (!await _ensureGoogleSession()) return;

    final calId = widget.calendarId!;
    final uid = _currentUserId!;

    final cfg = await loadGoogleCfgForCalendar(calId, uid);
    if (cfg.enabled && (cfg.calendarId ?? '').isNotEmpty) {
      setState(() {
        _googleSyncEnabled = true;
        _linkedCalendarSummary = cfg.calendarSummary;
        _linkedCalendarId = cfg.calendarId;
      });
      await _syncNow();
    } else {
      await _pickCalendarAndImport();
    }
  }

  Future<void> _onToggleGoogleSync(bool enable) async {
    final calId = widget.calendarId;
    final uid = _currentUserId!;
    if (calId == null) return;
    if (!_canEdit) { _toast('You need edit access to manage Google sync', icon: Icons.lock, color: Colors.grey); return; }

    if (!enable) {
      final removed = await _withLoading<int>(
        message: 'Removing your Google imports…',
        task: () => _purgeMyGoogleEventsForThisCalendar(calId, uid),
      );
      await saveGoogleCfgForCalendar(
        calId,
        uid,
        GoogleIntegrationConfig(
          enabled: false,
          calendarId: null,
          calendarSummary: null,
          syncToken: null,
          lastSyncAt: DateTime.now(),
        ),
      );
      try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
      setState(() {
        _googleSyncEnabled = false;
        _linkedCalendarSummary = null;
        _linkedCalendarId = null;
        _googleSignedIn = false;
      });
      _toast('Disconnected. Removed $removed of your Google events.', icon: Icons.link_off, color: Colors.deepOrange);
      return;
    }
    await _pickCalendarAndImport();
  }

  Future<int> _purgeMyGoogleEventsForThisCalendar(String calendarId, String uid) async {
    final col = FirebaseFirestore.instance.collection('calendars').doc(calendarId).collection('events');
    Query<Map<String, dynamic>> q = col
        .where('source', isEqualTo: 'google')
        .where('importOwners', arrayContains: uid);

    int affected = 0;
    while (true) {
      final page = await q.limit(400).get();
      if (page.docs.isEmpty) break;

      for (final d in page.docs) {
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(d.reference);
          if (!snap.exists) return;
          final owners = List<String>.from((snap.data()?['importOwners'] ?? []) as List);
          owners.remove(uid);
          if (owners.isEmpty) {
            tx.delete(d.reference);
          } else {
            tx.update(d.reference, {'importOwners': owners, 'updatedAt': FieldValue.serverTimestamp()});
          }
        });
        affected++;
      }
      if (page.docs.length < 400) break;
    }
    return affected;
  }

  Future<void> _switchGoogleAccount() async {
    try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
    setState(() {
      _googleSyncEnabled = false;
      _linkedCalendarSummary = null;
      _linkedCalendarId = null;
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
    if (!_canEdit) { _toast('You need edit access to import from Google', icon: Icons.lock, color: Colors.grey); return; }

    final calId = widget.calendarId!;
    final uid = _currentUserId!;
    final svc = GoogleCalendarService.instance;

    final calendars = await _withLoading<List<gcal.CalendarListEntry>>(
      message: 'Connecting to Google…',
      task: () => svc.listCalendars(),
    );
    if (calendars.isEmpty) {
      _toast('No Google calendars found.', color: Colors.grey);
      return;
    }

    final chosen = await showModalBottomSheet<gcal.CalendarListEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CalendarPicker(calendars: calendars),
    );
    if (chosen == null || chosen.id == null) return;

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
    for (final e in pulled.items ?? const <gcal.Event>[]) {
      final m = _mapGoogleEventToLocalDoc(e, googleCalendarId: chosen.id);
      if (m != null) preview.add(m);
    }
    preview.sort((a, b) => (a['startTime'] as Timestamp).toDate().compareTo((b['startTime'] as Timestamp).toDate()));

    final cs = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PreviewSelectSheet(
        events: preview,
        calendarName: chosen.summary ?? chosen.id!,
        buttonColor: cs.primary,
        textDark: cs.onSurface,
      ),
    );
    if (selected == null || selected.isEmpty) return;

    final imported = await _importEventsToShared(calendarId: calId, events: selected);

    await saveGoogleCfgForCalendar(
      calId,
      uid,
      GoogleIntegrationConfig(
        enabled: true,
        calendarId: chosen.id,
        calendarSummary: chosen.summary,
        syncToken: pulled.nextSyncToken,
        lastSyncAt: DateTime.now(),
      ),
    );

    setState(() {
      _googleSyncEnabled = true;
      _linkedCalendarSummary = chosen.summary;
      _linkedCalendarId = chosen.id;
      _googleSignedIn = true;
    });

    _toast('Imported $imported events from Google.', icon: Icons.cloud_done);
  }

  Future<void> _syncNow() async {
    if (!await _ensureGoogleSession()) return;

    final calId = widget.calendarId!;
    final uid = _currentUserId!;
    final cfg = await loadGoogleCfgForCalendar(calId, uid);
    final String? gCalId = cfg.calendarId;
    if (gCalId == null || gCalId.isEmpty) {
      _toast('No linked Google calendar to sync.', color: Colors.grey);
      return;
    }

    final svc = GoogleCalendarService.instance;
    final win = _syncWindow();

    final pulled = await _withLoading(
      message: 'Syncing…',
      task: () => svc.listEvents(
        calendarId: gCalId,
        syncToken: null,
        timeMin: win.from,
        timeMax: win.to,
      ),
    );

    final googleMapped = <Map<String, dynamic>>[];
    for (final e in pulled.items ?? const <gcal.Event>[]) {
      final m = _mapGoogleEventToLocalDoc(e, googleCalendarId: gCalId);
      if (m != null) googleMapped.add(m);
    }
    final googleKeys = <String>{ for (final m in googleMapped) _keyForMapped(m) };

    final col = FirebaseFirestore.instance
        .collection('calendars')
        .doc(calId)
        .collection('events');

    final existingSnap = await col
        .where('source', isEqualTo: 'google')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(win.from))
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(win.to))
        .limit(3000)
        .get();

    final byGid = <String, String>{};
    final byIcal = <String, String>{};
    final byKey = <String, String>{};

    for (final d in existingSnap.docs) {
      final m = d.data();
      final gid = (m['googleEventId'] ?? '') as String;
      final uidKey = (m['iCalUID'] ?? '') as String;
      if (gid.isNotEmpty) byGid[gid] = d.id;
      if (uidKey.isNotEmpty) byIcal[uidKey] = d.id;
      byKey[_keyForLocal(m)] = d.id;
    }

    int added = 0;
    int touched = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();

    for (final m in googleMapped) {
      final gid = (m['googleEventId'] ?? '') as String;
      final ical = (m['iCalUID'] ?? '') as String;
      final key  = _keyForMapped(m);

      String? docId = gid.isNotEmpty ? byGid[gid] : null;
      docId ??= ical.isNotEmpty ? byIcal[ical] : null;
      docId ??= byKey[key];

      if (docId == null) {
        final docRef = col.doc();
        batch.set(docRef, {...m, 'importOwners': [uid]});
        added++;
      } else {
        final ref = col.doc(docId);
        batch.update(ref, {
          'title': m['title'],
          'description': m['description'],
          'startTime': m['startTime'],
          'endTime': m['endTime'],
          'isAllDay': m['isAllDay'],
          'googleCalendarId': m['googleCalendarId'],
          'updatedAt': FieldValue.serverTimestamp(),
          'importOwners': FieldValue.arrayUnion([uid]),
        });
        touched++;
      }

      if ((added + touched) % 400 == 0) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
      }
    }

    if ((added + touched) % 400 != 0) await batch.commit();

    int pruned = 0;
    for (final d in existingSnap.docs) {
      final data = d.data();
      final owners = List<String>.from((data['importOwners'] ?? []) as List);
      if (!owners.contains(uid)) continue;

      final key = _keyForLocal(data);
      if (googleKeys.contains(key)) continue;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(d.reference);
        if (!snap.exists) return;
        final currOwners = List<String>.from((snap.data()?['importOwners'] ?? []) as List);
        currOwners.remove(uid);
        if (currOwners.isEmpty) {
          tx.delete(d.reference);
        } else {
          tx.update(d.reference, {'importOwners': currOwners, 'updatedAt': FieldValue.serverTimestamp()});
        }
      });
      pruned++;
    }

    await saveGoogleCfgForCalendar(
      calId,
      uid,
      cfg.copyWith(
        syncToken: pulled.nextSyncToken ?? cfg.syncToken,
        lastSyncAt: DateTime.now(),
      ),
    );

    _toast('Sync complete: added $added, updated $touched, pruned $pruned of your events.');
  }

  Map<String, dynamic>? _mapGoogleEventToLocalDoc(gcal.Event e, {String? googleCalendarId}) {
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
      'googleCalendarId': googleCalendarId,
      'source': 'google',
      'importedById': _currentUserId,
      'importedVia': 'google',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<int> _importEventsToShared({
    required String calendarId,
    required List<Map<String, dynamic>> events,
  }) async {
    if (events.isEmpty) return 0;

    final uid = _currentUserId!;
    final ref = FirebaseFirestore.instance
        .collection('calendars')
        .doc(calendarId)
        .collection('events');

    final now = DateTime.now();
    final from = DateTime(now.year - 1);
    final existingSnap = await ref
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .limit(3000)
        .get();

    final existingByKey = <String, String>{};
    for (final d in existingSnap.docs) {
      final m = d.data();
      existingByKey[_keyForLocal(m)] = d.id;
    }

    int count = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();

    final importerName = await _resolveDisplayName();
    final importerId = uid;

    for (final raw in events) {
      final ev = Map<String, dynamic>.from(raw);
      ev['creatorId']   ??= importerId;
      ev['creatorName'] ??= importerName;

      final key = _keyForMapped(ev);
      final existingId = existingByKey[key];

      if (existingId == null) {
        batch.set(ref.doc(), {...ev, 'importOwners': [uid]});
        count++;
      } else {
        batch.update(ref.doc(existingId), {
          'title': ev['title'],
          'description': ev['description'],
          'startTime': ev['startTime'],
          'endTime': ev['endTime'],
          'isAllDay': ev['isAllDay'],
          'updatedAt': FieldValue.serverTimestamp(),
          'importOwners': FieldValue.arrayUnion([uid]),
        });
        count++;
      }

      if (count % 400 == 0) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
      }
    }

    if (count % 400 != 0) await batch.commit();
    return count;
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (widget.calendarId == null) {
      return const Scaffold(body: Center(child: Text('No calendar selected.')));
    }

    if (FirebaseAuth.instance.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final gv = _glassVars(context);

    // Pretty, crisp chips with consistent outlines
    Widget buildModeChip(
      BuildContext context, {
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final cs = Theme.of(context).colorScheme;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: cs.surface,
        selectedColor: cs.secondaryContainer,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? cs.onSecondaryContainer : cs.onSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.25 : 1.0,
          ),
        ),
        onSelected: (_) => onTap(),
      );
    }

    // Tonal pill buttons (Google / Add)
    ButtonStyle _pillBtn() => ElevatedButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: const TextStyle(fontSize: 13),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => widget.onBackToList?.call()),
        title: Text(widget.calendarName ?? 'Shared Calendar'),
        actions: [
          // participants
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: () {
                const maxAvatars = 5;
                final visible = _participants.take(maxAvatars).toList();
                final extra = _participants.length - visible.length;
                String _initial(String s) => (s.isNotEmpty ? s[0] : '?').toUpperCase();

                return [
                  ...visible.map((user) {
                    final name = (user['name'] ?? 'User').toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message: name,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: cs.primary,
                          child: Text(_initial(name), style: TextStyle(fontSize: 12, color: cs.onPrimary)),
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
                        child: const Text('+', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
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
                  foregroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

            // ---- Event card (Glass) ----
            Widget buildEventCard(Map<String, dynamic> event, {DateTime? displayDate}) {
              String resolveCreatorName() {
                final storedCreator = (event['creatorName'] as String?)?.trim() ?? '';
                if (storedCreator.isNotEmpty) return storedCreator;

                final creatorId = (event['creatorId'] ?? '').toString();
                if (creatorId.isEmpty) return 'Unknown';

                final fromMembers = _participants
                        .firstWhere((p) => p['id'] == creatorId,
                            orElse: () => const {'name': 'Unknown'})['name'] ??
                    'Unknown';

                return (fromMembers.trim().isEmpty) ? 'Unknown' : fromMembers;
              }

              final creatorName = resolveCreatorName();
              final calendarName = (event['calendarName'] ?? '').toString().trim();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: [
                    BoxShadow(
                      blurRadius: isDark ? 16 : 18,
                      offset: const Offset(0, 3),
                      color: Colors.black.withOpacity(gv.shadowOpacity * 0.8),
                    ),
                  ]),
                  child: GlassPanel(
                    radius: const BorderRadius.all(Radius.circular(14)),
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
                    blur: gv.blur,
                    opacity: gv.opacity,
                    accentBorder: true,
                    accentOpacity: gv.accentOpacity,
                    borderWidth: gv.borderWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('•', style: TextStyle(fontSize: 20, height: 1.2, color: cs.onSurface)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${event['title']}',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface,
                                      )),
                                  if (creatorName.isNotEmpty || calendarName.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        [
                                          if (creatorName.isNotEmpty) 'by $creatorName',
                                          if (calendarName.isNotEmpty) 'on $calendarName',
                                        ].join(' '),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
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
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ),
                                  if ((event['description'] ?? '').toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        event['description'],
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withOpacity(0.85),
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
                                onPressed: () async {
                                  final editorName = await _resolveDisplayName();
                                  final startDate = (event['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                                  if (_startOfDay(startDate).isBefore(_startOfDay(DateTime.now()))) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("You can't edit events in the past.")),
                                    );
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
                                    buttonColor: cs.primary,
                                    textDark: cs.onSurface,
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
                  ),
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
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(0.8),
                      ),
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

            // ----- Calendar core -----
            final calendarCore = TableCalendar(
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

              // Keep everything on-theme (no default blue)
              calendarStyle: CalendarStyle(
                selectedDecoration: const BoxDecoration(shape: BoxShape.circle).copyWith(color: cs.primary),
                selectedTextStyle: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700),

                todayDecoration: const BoxDecoration(shape: BoxShape.circle).copyWith(color: cs.secondaryContainer),
                todayTextStyle: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700),

                defaultTextStyle: TextStyle(color: cs.onSurface),
                weekendTextStyle: TextStyle(color: cs.onSurface),
                outsideTextStyle: TextStyle(color: cs.onSurface.withOpacity(0.45)),

                markerDecoration: BoxDecoration(color: cs.tertiary, shape: BoxShape.circle),

                isTodayHighlighted: true,
                outsideDaysVisible: true,
              ),

              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: theme.textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
                headerPadding: const EdgeInsets.symmetric(vertical: 8),
                leftChevronIcon: Icon(Icons.chevron_left, color: cs.onSurface),
                rightChevronIcon: Icon(Icons.chevron_right, color: cs.onSurface),
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
                        Icon(Icons.calendar_today, size: 20, color: cs.onSurface),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('MMMM yyyy').format(_focusedDay),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
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
                      final color = colors[event['id']] ?? cs.tertiary; // not blue
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

            // —— Glass panel around calendar (shared vars) ——
            final calendarPanel = GlassPanel(
              radius: const BorderRadius.all(Radius.circular(20)),
              padding: const EdgeInsets.all(12),
              blur: gv.blur,
              opacity: gv.opacity,
              accentBorder: true,
              accentOpacity: gv.accentOpacity,
              borderWidth: gv.borderWidth,
              child: calendarCore,
            );

            Widget _chip(String label, bool selected, VoidCallback onTap) => buildModeChip(
              context,
              label: label,
              selected: selected,
              onTap: onTap,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MediaQuery.of(context).size.width < 500
                      ? SizedBox(height: 440, child: calendarPanel)
                      : calendarPanel,
                  const SizedBox(height: 12),

                  // Toolbar: chips + Google + Add
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
                                _chip('Day', _agendaView == _AgendaView.day, () {
                                  setState(() => _agendaView = _AgendaView.day);
                                }),
                                _chip('Month', _agendaView == _AgendaView.month, () {
                                  setState(() => _agendaView = _AgendaView.month);
                                }),
                              ],
                            );

                            Widget googleBtn() => ElevatedButton.icon(
                                  onPressed: _canEdit ? _openGoogleCard : null,
                                  icon: const Icon(Icons.cloud_sync, size: 18),
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 240),
                                    child: Text(
                                      _googleSyncEnabled
                                          ? (_linkedCalendarSummary?.isNotEmpty == true
                                              ? 'Google: ${_linkedCalendarSummary!}'
                                              : 'Google linked')
                                          : 'Import Google Calendar',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  style: _pillBtn(),
                                );

                            Widget addBtn() => ElevatedButton.icon(
                                  onPressed: _canEdit ? _openManualAdd : null,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Event'),
                                  style: _pillBtn(),
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
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
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

  // ---------- share modal ----------
  void _showShareModal(String calendarId) async {
    final calendarDoc = await FirebaseFirestore.instance.collection('calendars').doc(calendarId).get();
    final data = calendarDoc.data();
    if (data == null ||
        (!data.containsKey('sharedLinkEdit') && !data.containsKey('sharedLinkView'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to generate invite link.')));
      return;
    }

    bool allowEdit = data['allowEdit'] ?? false;
    String editLink = 'https://www.linkupcalendar.app/#/cal/${data['sharedLinkEdit']}';
    String viewLink = 'https://www.linkupcalendar.app/#/cal/${data['sharedLinkView']}';

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
                    onTap: () => linkController.selection = TextSelection(
                      baseOffset: 0, extentOffset: linkController.text.length),
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'User';
    final name = (user.displayName ?? '').trim();
    if (name.isNotEmpty) return name;
    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) return email;
    return 'User';
  }
}

// ===== helpers/widgets =====
class _GoogleActionTile extends StatefulWidget {
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
  State<_GoogleActionTile> createState() => _GoogleActionTileState();
}

class _GoogleActionTileState extends State<_GoogleActionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final disabled = widget.onTap == null;
    final accent = widget.destructive ? Colors.red : cs.primary;
    final baseFg = widget.destructive ? Colors.red : cs.onSurface;

    final fg = disabled ? cs.outline : (_hover ? accent : baseFg);
    final bg = _hover
        ? (widget.destructive
            ? Colors.red.withOpacity(isDark ? 0.14 : 0.10)
            : cs.primary.withOpacity(isDark ? 0.12 : 0.08))
        : Colors.transparent;
    final border = _hover
        ? accent.withOpacity(isDark ? 0.50 : 0.60)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1),
        ),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(widget.icon, color: fg),
          title: Text(widget.text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
          onTap: widget.onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
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
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('HH:mm');
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    return sameDay
        ? '${df.format(s)}  ${tf.format(s)}–${tf.format(e)}'
        : '${df.format(s)} ${tf.format(s)} → ${df.format(e)} ${tf.format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
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
