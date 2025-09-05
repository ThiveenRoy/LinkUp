// lib/screens/master_calendar_screen.dart
//
// Master calendar with:
//  - Add Event button → opens manual dialog directly
//  - Google button → opens a glass-card Dialog (same as Shared)
//  - Quiet Google auth (no auto popup)
//  - Full-refresh Google sync (diff add/delete) identical to Shared
//  - Theming: no hardcoded colors; uses ColorScheme/TextTheme
//  - Transparent Scaffold so ThemeBg wallpaper can show
//  - GlassPanel applied to calendar frame and event cards

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../common/event_crud.dart';
import '../services/google_sync.dart';
import '../widgets/glass.dart';

enum _AgendaView { day, month }

// ----- shared glass tuning (kept identical to Shared screen)
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
    opacity: isDark ? 0.11 : 0.042,
    accentOpacity: isDark ? 0.18 : 0.16,
    borderWidth: 0.9,
    shadowOpacity: isDark ? 0.25 : 0.10,
  );
}

class MasterCalendarScreen extends StatefulWidget {
  const MasterCalendarScreen({super.key});

  @override
  State<MasterCalendarScreen> createState() => _MasterCalendarScreenState();
}

class _MasterCalendarScreenState extends State<MasterCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  _AgendaView _agendaView = _AgendaView.day;

  // Rendering data
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  Map<String, Color> _eventColors = {};
  bool _loading = true;

  String? _masterCalendarId; // calendars/{id}

  // ---------- Google state ----------
  bool _googleSyncEnabled = false;
  String? _linkedCalendarSummary;
  bool _googleSignedIn = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      return;
    }
    await _ensureUserHasMasterCalendar();
    await _initMasterId();
    await _loadGoogleCfg(); // Firestore only; no auth popup
    await _loadEvents();
  }

  // ---------- helpers ----------
  void _toast(String msg, {IconData? icon, Color? color}) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.primary;
    final on = cs.onPrimary;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: bg,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: on),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(msg, style: TextStyle(color: on))),
          ],
        ),
      ),
    );
  }

  Future<T> _withLoading<T>({
    required String message,
    required Future<T> Function() task,
  }) async {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
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
              Flexible(
                child: Text(
                  message.isEmpty ? 'Working…' : message,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                ),
              ),
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

  String _keyForLocal(Map<String, dynamic> m) {
    final ts1 = (m['startTime'] as Timestamp?)?.toDate();
    final ts2 = (m['endTime'] as Timestamp?)?.toDate();
    final iCal = (m['iCalUID'] ?? '') as String;
    final gid  = (m['googleEventId'] ?? '') as String;
    final title = (m['title'] ?? '') as String;
    return '$iCal|$gid|$title|$ts1|$ts2';
  }
  String _keyForMapped(Map<String, dynamic> m) => _keyForLocal(m);

  ({DateTime from, DateTime to}) _syncWindow() {
    final now = DateTime.now();
    return (from: DateTime(now.year, now.month - 6, now.day),
            to:   DateTime(now.year + 1, now.month, now.day));
  }

  String _formatEventTime(DateTime? selectedDate, DateTime? start, DateTime? end) {
    if (start == null || end == null || selectedDate == null) return '';
    final sd = DateFormat('d MMM yyyy').format(selectedDate);
    final st = DateFormat('h:mm a').format(start);
    final et = DateFormat('h:mm a').format(end);
    return '$sd, $st – $et';
  }

  // ---------- master calendar bootstrap ----------
  Future<void> _ensureUserHasMasterCalendar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final q = await FirebaseFirestore.instance
        .collection('calendars')
        .where('owner', isEqualTo: user.uid)
        .where('isShared', isEqualTo: false)
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      final displayName =
          (user.displayName?.trim().isNotEmpty == true)
              ? user.displayName!.trim()
              : (user.email?.trim().isNotEmpty == true ? user.email!.trim() : 'User');

      await FirebaseFirestore.instance.collection('calendars').add({
        'name': 'My Calendar',
        'owner': user.uid,
        'ownerName': displayName,
        'ownerEmail': user.email,
        'members': [
          {'id': user.uid, 'name': displayName}
        ],
        'memberIds': [user.uid],
        'isShared': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
        'updatedByName': displayName,
      });
    }
  }

  Future<void> _initMasterId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final q = await FirebaseFirestore.instance
        .collection('calendars')
        .where('owner', isEqualTo: user.uid)
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

  Future<CollectionReference<Map<String, dynamic>>> _personalEventsCol() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not authenticated');

    final q = await FirebaseFirestore.instance
        .collection('calendars')
        .where('owner', isEqualTo: user.uid)
        .where('isShared', isEqualTo: false)
        .limit(1)
        .get();

    String calId;
    if (q.docs.isEmpty) {
      final displayName =
          (user.displayName?.trim().isNotEmpty == true)
              ? user.displayName!.trim()
              : (user.email?.trim().isNotEmpty == true ? user.email!.trim() : 'User');

      calId = (await FirebaseFirestore.instance.collection('calendars').add({
        'name': 'My Calendar',
        'owner': user.uid,
        'ownerName': displayName,
        'ownerEmail': user.email,
        'members': [
          {'id': user.uid, 'name': displayName}
        ],
        'memberIds': [user.uid],
        'isShared': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
        'updatedByName': displayName,
      })).id;
    } else {
      calId = q.docs.first.id;
    }

    return FirebaseFirestore.instance
        .collection('calendars')
        .doc(calId)
        .collection('events');
  }

  /// Master aggregates:
  /// - Personal calendar: include all events (including Google).
  /// - Shared calendars: include ONLY events I created manually (exclude 'google').
  Future<void> _loadEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final calendarQuery = await FirebaseFirestore.instance.collection('calendars').get();

    final Map<DateTime, List<Map<String, dynamic>>> tempEvents = {};
    final random = Random();

    for (final doc in calendarQuery.docs) {
      final calendarId = doc.id;
      final calendarName = (doc['name'] ?? 'Shared Calendar').toString();
      final isShared = (doc['isShared'] ?? false) == true;

      // membership
      List<String> memberIds = [];
      final rawMemberIds = doc.data()['memberIds'];
      if (rawMemberIds is List) {
        memberIds = rawMemberIds.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
      } else {
        final rawMembers = doc['members'] ?? [];
        memberIds = (rawMembers as List<dynamic>).map<String>((m) {
          if (m is String) return m;
          if (m is Map && m['id'] != null) return m['id'].toString();
          return '';
        }).where((e) => e.isNotEmpty).toList();
      }

      if (!memberIds.contains(user.uid)) continue;

      final eventsSnap = await FirebaseFirestore.instance
          .collection('calendars')
          .doc(calendarId)
          .collection('events')
          .get();

      for (final eventDoc in eventsSnap.docs) {
        final data = eventDoc.data();

        if (isShared) {
          final src = (data['source'] ?? '').toString(); // 'google' for google-imported
          final creatorId = (data['creatorId'] ?? data['createdById'] ?? '').toString();

            // ❌ Hide my own Google-imported events from shared calendars
            if (src == 'google' && creatorId == user.uid) continue;

            // ✅ Show my manual events in shared calendars
            // (i.e., do nothing here; let them pass through)

            // ✅ Show friend's Google events (and manual) by default
          }


        final Timestamp? st = data['startTime'] as Timestamp?;
        final Timestamp? et = data['endTime'] as Timestamp?;
        if (st == null || et == null) continue;

        final start = st.toDate();
        final end = et.toDate();
        final normalizedEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);

        final color = Color.fromARGB(255, random.nextInt(200), random.nextInt(200), random.nextInt(200));
        _eventColors[eventDoc.id] = color;

        for (DateTime d = start; !d.isAfter(normalizedEnd); d = d.add(const Duration(days: 1))) {
          final dateOnly = DateTime(d.year, d.month, d.day);
          (tempEvents[dateOnly] ??= []).add({
            ...data,
            'id': eventDoc.id,
            'calendarId': calendarId,
            'calendarName': calendarName,
            'isShared': isShared,
          });
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _events = tempEvents;
      _loading = false;
    });
  }

  // ---------- GOOGLE: session / actions ----------

  Future<bool> _ensureGoogleSession() async {
    final svc = GoogleCalendarService.instance;

    final has = await svc.hasSession(); // quiet path
    if (has) {
      if (mounted) setState(() => _googleSignedIn = true);
      return true;
    }

    try {
      await svc.ensureSignedInInteractive();
      if (mounted) setState(() => _googleSignedIn = true);
      return true;
    } catch (_) {
      if (mounted) setState(() => _googleSignedIn = false);
      return false;
    }
  }

  Future<void> _switchGoogleAccount() async {
    try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
    if (!mounted) return;
    setState(() {
      _googleSyncEnabled = false;
      _linkedCalendarSummary = null;
      _googleSignedIn = false;
    });
    await _pickCalendarAndImport();
    await _loadGoogleCfg();
  }

  // === Google glass-card (same as Shared) ===
  Future<void> _openGoogleCard() async {
    _googleSignedIn = await GoogleCalendarService.instance.hasSession();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent, // keep page bright behind
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
                          await _chooseAnotherCalendar();
                          await _loadGoogleCfg();
                        },
                      ),
                    if (_googleSignedIn || isLinked)
                      _GoogleActionTile(
                        icon: Icons.account_circle,
                        text: 'Switch Google account',
                        onTap: () async {
                          Navigator.pop(context);
                          await _switchGoogleAccount();
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

    _googleSignedIn = await GoogleCalendarService.instance.hasSession();
    if (mounted) setState(() {});
  }

  Future<void> _onAddGoogleSync() async {
    if (_masterCalendarId == null) await _initMasterId();
    if (_masterCalendarId == null) {
      _toast('Master calendar not found.', icon: Icons.error, color: Colors.redAccent);
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
      await _syncNow();
    } else {
      await _pickCalendarAndImport();
    }
    await _loadEvents();
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
            .set({
          'enabled': false,
          'calendarId': null,
          'calendarSummary': null,
          'syncToken': null,
          'lastSyncAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      try { await GoogleCalendarService.instance.signOut(); } catch (_) {}
      if (!mounted) return;
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

  Future<int> _purgeGoogleEventsFromMaster() async {
    final col = await _personalEventsCol();
    int deleted = 0;
    while (true) {
      final page = await col.where('source', isEqualTo: 'google').limit(400).get();
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

  Future<void> _chooseAnotherCalendar() async {
    if (!await _ensureGoogleSession()) return;
    await _pickCalendarAndImport();
  }

  Future<void> _pickCalendarAndImport() async {
    if (!await _ensureGoogleSession()) return;
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
    for (final e in (pulled.items ?? const <gcal.Event>[])) {
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
      ),
    );
    if (selected == null || selected.isEmpty) return;

    final imported = await _importEventsToMaster(selected);

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
        'lastSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    setState(() {
      _googleSyncEnabled = true;
      _linkedCalendarSummary = chosen.summary;
      _googleSignedIn = true;
    });

    _toast('Imported $imported events from Google.', icon: Icons.cloud_done);
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
    if (gCalId == null) {
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
    for (final e in (pulled.items ?? const <gcal.Event>[])) {
      final m = _mapGoogleEventToLocalDoc(e);
      if (m != null) googleMapped.add(m);
    }
    final googleKeys = <String>{ for (final m in googleMapped) _keyForMapped(m) };

    final col = await _personalEventsCol();
    final existingSnap = await col
        .where('source', isEqualTo: 'google')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(win.from))
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(win.to))
        .limit(3000)
        .get();

    final existingKeys = <String, String>{}; // key -> docId
    for (final d in existingSnap.docs) {
      final key = _keyForLocal(d.data());
      existingKeys[key] = d.id;
    }

    final toAdd = <Map<String, dynamic>>[];
    for (final m in googleMapped) {
      final key = _keyForMapped(m);
      if (!existingKeys.containsKey(key)) toAdd.add(m);
    }
    final toDelete = <String>[];
    for (final entry in existingKeys.entries) {
      if (!googleKeys.contains(entry.key)) toDelete.add(entry.value);
    }

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

    await FirebaseFirestore.instance
        .collection('calendars')
        .doc(_masterCalendarId!)
        .collection('integrations')
        .doc('google')
        .set({
      'syncToken': pulled.nextSyncToken ?? cfg['syncToken'],
      'lastSyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _toast('Sync complete: added $added, deleted $deleted');
    await _loadEvents();
  }

  // ---------- mapping / import ----------
  Map<String, dynamic>? _mapGoogleEventToLocalDoc(gcal.Event e) {
    if (e.status == 'cancelled') return null;

    final title = e.summary ?? '(No title)';
    final desc = e.description;

    DateTime? start;
    DateTime? end;

    if (e.start?.dateTime != null && e.end?.dateTime != null) {
      start = e.start!.dateTime!.toLocal();
      end   = e.end!.dateTime!.toLocal();
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

  Future<int> _importEventsToMaster(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return 0;

    final ref = await _personalEventsCol();

    final now = DateTime.now();
    final from = DateTime(now.year - 1);
    final existingSnap = await ref
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .limit(3000)
        .get();

    final seen = <String>{};
    for (final d in existingSnap.docs) {
      final m = d.data();
      seen.add(_keyForLocal(m));
    }

    final batch = FirebaseFirestore.instance.batch();
    int count = 0;
    for (final ev in events) {
      final k = _keyForLocal(ev);
      if (seen.contains(k)) continue;
      batch.set(ref.doc(), ev);
      count++;
      if (count % 400 == 0) await batch.commit();
    }
    if (count % 400 != 0) await batch.commit();
    return count;
  }

  // ---------- UI ----------

  Widget _buildEventCard(Map<String, dynamic> event, {DateTime? displayDate}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final gv = _glassVars(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String creator = (event['creatorName'] ?? '').toString().trim();
    final String calendarName = (event['calendarName'] ?? '').toString().trim();
    final bool isSharedEvent = event['isShared'] == true;

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
          radius: const BorderRadius.all(Radius.circular(16)),
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
                        Text(
                          '${event['title']}',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                            height: 1.2,
                          ),
                        ),
                        if (isSharedEvent && creator.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              calendarName.isNotEmpty ? 'by $creator on $calendarName' : 'by $creator',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.8),
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
                              style: tt.bodyMedium?.copyWith(
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
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.9),
                                fontWeight: FontWeight.w300,
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
                        buttonColor: cs.primary,
                        textDark: cs.onPrimary,
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
        ),
      ),
    );
  }

  Widget _buildMonthAgenda() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final first = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final last = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    final items = <Widget>[];
    for (int i = 0; i < last.day; i++) {
      final day = DateTime(first.year, first.month, first.day + i);
      final events = _events[DateTime(day.year, day.month, day.day)] ?? [];
      if (events.isEmpty) continue;

      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            DateFormat('EEE, d MMM yyyy').format(day),
            style: tt.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withOpacity(0.8),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gv = _glassVars(context);

    final calendarCore = TableCalendar(
      firstDay: DateTime.utc(2000),
      lastDay: DateTime.utc(2100),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay  = focusedDay;
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
      eventLoader: (d) => _events[DateTime(d.year, d.month, d.day)] ?? [],
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: tt.titleSmall!.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
        headerPadding: const EdgeInsets.symmetric(vertical: 8),
        leftChevronIcon: Icon(Icons.chevron_left, color: cs.onSurface),
        rightChevronIcon: Icon(Icons.chevron_right, color: cs.onSurface),
      ),
      calendarStyle: CalendarStyle(
        selectedDecoration: const BoxDecoration(shape: BoxShape.circle).copyWith(color: cs.primary),
        selectedTextStyle: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700),
        todayDecoration: const BoxDecoration(shape: BoxShape.circle).copyWith(color: cs.secondaryContainer),
        todayTextStyle: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700),
        defaultTextStyle: tt.bodyMedium!.copyWith(color: cs.onSurface),
        weekendTextStyle: tt.bodyMedium!.copyWith(color: cs.onSurface),
        outsideTextStyle: tt.bodyMedium!.copyWith(color: cs.onSurface.withOpacity(0.40)),
        markerDecoration: BoxDecoration(color: cs.tertiary, shape: BoxShape.circle),
        outsideDaysVisible: true,
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
                  style: tt.titleLarge?.copyWith(
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
              final color = _eventColors[event['id']] ?? cs.tertiary;
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

    // glassed calendar frame
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

    ButtonStyle _pillBtn() => ElevatedButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: tt.labelLarge,
    );

    final titleText = _agendaView == _AgendaView.day
        ? 'Your schedule for ${DateFormat('EEE, d MMM yyyy').format(_selectedDay)}'
        : 'Your schedule for ${DateFormat('MMMM yyyy').format(_focusedDay)}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MediaQuery.of(context).size.width < 500
                        ? SizedBox(height: 440, child: calendarPanel)
                        : calendarPanel,
                    const SizedBox(height: 12),

                    // Toolbar
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
                                  buildModeChip(context, label: 'Day', selected: _agendaView == _AgendaView.day, onTap: () => setState(() => _agendaView = _AgendaView.day)),
                                  buildModeChip(context, label: 'Month', selected: _agendaView == _AgendaView.month, onTap: () => setState(() => _agendaView = _AgendaView.month)),
                                ],
                              );

                              Widget googleBtn() => ElevatedButton.icon(
                                    onPressed: _openGoogleCard,
                                    icon: const Icon(Icons.cloud_sync, size: 18),
                                    label: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 220),
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
                                    onPressed: _openManualAdd,
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
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
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
                        itemCount: (_events[DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day)] ?? []).length,
                        itemBuilder: (context, index) =>
                            _buildEventCard((_events[DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day)] ?? [])[index]),
                      )
                    else
                      _buildMonthAgenda(),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- Manual Add ----------
  Future<void> _openManualAdd() async {
    final cs = Theme.of(context).colorScheme;
    await EventCrud.showAddOrEditDialog(
      context: context,
      getEventsCollection: _personalEventsCol,
      canEdit: true,
      disallowPastDates: true,
      existingEvent: null,
      initialSelectedDay: _selectedDay,
      onAfterWrite: _loadEvents,
      buttonColor: cs.primary,
      textDark: cs.onPrimary,
    );
  }
}

// ===== Reusable tiles/sheets (identical styling to Shared) =====

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
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
          title: Text(widget.text, style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
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
  const _PreviewSelectSheet({required this.events, required this.calendarName});

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
