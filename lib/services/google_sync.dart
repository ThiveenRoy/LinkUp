// lib/services/google_sync.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;

import '../config/google_oauth.dart'; // define kGoogleWebClientId

/* ──────────────────────────────────────────────────────────────────────────
   Google auth & Calendar client (web + mobile)
   - No gapi usage; we call Google APIs with Bearer http.Client
   - listEvents returns gcal.Events (use .items / .nextSyncToken)
   - hasSession() never prompts; ensureSignedInInteractive() can prompt
   ────────────────────────────────────────────────────────────────────────── */

class GoogleCalendarService {
  GoogleCalendarService._();
  static final GoogleCalendarService instance = GoogleCalendarService._();

  static const _scopes = <String>[
    gcal.CalendarApi.calendarScope,
    'openid',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  final GoogleSignIn _gsi = GoogleSignIn(
    clientId: kGoogleWebClientId, // OK to be null on mobile
    scopes: _scopes,
  );

  /// Quick status for UI. Never prompts.
  Future<bool> hasSession() async {
    try {
      if (_gsi.currentUser != null) return true;
      final signed = await _gsi.isSignedIn();
      if (!signed) return false;
      try {
        await _gsi.signInSilently(); // no popup
      } catch (_) {}
      return _gsi.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Call right before a user-initiated Google action (button tap).
  Future<void> ensureSignedInInteractive() async {
    if (await hasSession()) return;
    final acc = await _gsi.signIn(); // popup allowed (user initiated)
    if (acc == null) throw Exception('NO_GOOGLE_SESSION');
  }

  Future<void> signOut() async {
    try {
      await _gsi.disconnect();
    } catch (_) {}
  }

  /// Build an http.Client that injects OAuth headers.
  /// Assumes a session exists—does NOT trigger sign-in.
  Future<http.Client> _authedClient() async {
    final acc = _gsi.currentUser;
    if (acc == null) throw Exception('NO_GOOGLE_SESSION');
    final headers = await acc.authHeaders; // includes Authorization: Bearer …
    return _AuthClient(headers);
  }

  Future<List<gcal.CalendarListEntry>> listCalendars() async {
    final client = await _authedClient();
    try {
      final api = gcal.CalendarApi(client);
      final res = await api.calendarList.list(
        showHidden: true,
        minAccessRole: 'reader',
      );
      return res.items ?? <gcal.CalendarListEntry>[];
    } finally {
      client.close();
    }
  }

  /// Returns the raw Events response (use .items and .nextSyncToken).
  Future<gcal.Events> listEvents({
    required String calendarId,
    String? syncToken,
    DateTime? timeMin,
    DateTime? timeMax,
  }) async {
    final client = await _authedClient();
    try {
      final api = gcal.CalendarApi(client);
      final res = await api.events.list(
        calendarId,
        singleEvents: true,
        orderBy: 'startTime',
        showDeleted: true, // enables proper diffing with token
        timeMin: syncToken == null ? timeMin?.toUtc() : null,
        timeMax: syncToken == null ? timeMax?.toUtc() : null,
        maxResults: 2500,
        syncToken: syncToken,
      );
      return res;
    } finally {
      client.close();
    }
  }
}

class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/* ──────────────────────────────────────────────────────────────────────────
   Firestore helpers (PER-USER integration doc)
   Path key style used here: calendars/{calId}/integrations/google_{uid}
   ────────────────────────────────────────────────────────────────────────── */

DocumentReference<Map<String, dynamic>> calendarDoc(String calendarId) =>
    FirebaseFirestore.instance.collection('calendars').doc(calendarId);

CollectionReference<Map<String, dynamic>> calendarEventsRef(String calendarId) =>
    calendarDoc(calendarId).collection('events');

DocumentReference<Map<String, dynamic>> googleCfgRef(String calendarId, String uid) =>
    calendarDoc(calendarId).collection('integrations').doc('google_$uid');

class GoogleIntegrationConfig {
  final bool enabled;
  final String? calendarId;       // Google Calendar ID
  final String? calendarSummary;
  final String? syncToken;
  final DateTime? lastSyncAt;

  GoogleIntegrationConfig({
    required this.enabled,
    this.calendarId,
    this.calendarSummary,
    this.syncToken,
    this.lastSyncAt,
  });

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'calendarId': calendarId,
        'calendarSummary': calendarSummary,
        'syncToken': syncToken,
        'lastSyncAt': lastSyncAt == null ? null : Timestamp.fromDate(lastSyncAt!),
      };

  static GoogleIntegrationConfig fromMap(Map<String, dynamic>? m) {
    m ??= {};
    return GoogleIntegrationConfig(
      enabled: (m['enabled'] as bool?) ?? false,
      calendarId: m['calendarId'] as String?,
      calendarSummary: m['calendarSummary'] as String?,
      syncToken: m['syncToken'] as String?,
      lastSyncAt: (m['lastSyncAt'] is Timestamp)
          ? (m['lastSyncAt'] as Timestamp).toDate()
          : null,
    );
  }

  GoogleIntegrationConfig copyWith({
    bool? enabled,
    String? calendarId,
    String? calendarSummary,
    String? syncToken,
    DateTime? lastSyncAt,
  }) {
    return GoogleIntegrationConfig(
      enabled: enabled ?? this.enabled,
      calendarId: calendarId ?? this.calendarId,
      calendarSummary: calendarSummary ?? this.calendarSummary,
      syncToken: syncToken ?? this.syncToken,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

Future<GoogleIntegrationConfig> loadGoogleCfgForCalendar(
  String calendarId,
  String uid,
) async {
  final s = await googleCfgRef(calendarId, uid).get();
  return GoogleIntegrationConfig.fromMap(s.data());
}

Future<void> saveGoogleCfgForCalendar(
  String calendarId,
  String uid,
  GoogleIntegrationConfig cfg,
) async {
  await googleCfgRef(calendarId, uid).set(cfg.toMap(), SetOptions(merge: true));
}

/* ──────────────────────────────────────────────────────────────────────────
   Mapping helpers
   ────────────────────────────────────────────────────────────────────────── */

Map<String, dynamic>? googleEventToLocal(gcal.Event e) {
  if (e.status == 'cancelled') return null;

  final title = e.summary ?? '(No title)';
  final desc = e.description;

  DateTime? start;
  DateTime? end;
  bool isAllDay = false;

  if (e.start?.dateTime != null && e.end?.dateTime != null) {
    start = e.start!.dateTime!.toLocal();
    end = e.end!.dateTime!.toLocal();
  } else if (e.start?.date != null && e.end?.date != null) {
    isAllDay = true;
    // Google all-day uses exclusive end; convert to inclusive 23:59:59
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
    'isAllDay': isAllDay,
    'googleEventId': e.id,
    'iCalUID': e.iCalUID,
    'source': 'google',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

Future<int> importGoogleEventsToCalendar({
  required String calendarId, // target calendar (Master or Shared)
  required List<Map<String, dynamic>> events,
}) async {
  if (events.isEmpty) return 0;
  final ref = calendarEventsRef(calendarId);

  // De-dupe: title + start + end within 1y window
  final now = DateTime.now();
  final from = DateTime(now.year - 1);
  final existingSnap = await ref
      .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .limit(3000)
      .get();

  final seen = <String>{};
  for (final d in existingSnap.docs) {
    final m = d.data();
    final k = '${m['title']}|${(m['startTime'] as Timestamp?)?.toDate()}|${(m['endTime'] as Timestamp?)?.toDate()}';
    seen.add(k);
  }

  int count = 0;
  WriteBatch batch = FirebaseFirestore.instance.batch();
  for (final ev in events) {
    final k = '${ev['title']}|${(ev['startTime'] as Timestamp).toDate()}|${(ev['endTime'] as Timestamp).toDate()}';
    if (seen.contains(k)) continue;

    batch.set(ref.doc(), ev);
    count++;
    if (count % 400 == 0) {
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
    }
  }
  await batch.commit();
  return count;
}

Future<String?> findMasterCalendarIdForUser(String uid) async {
  final q = await FirebaseFirestore.instance
      .collection('calendars')
      .where('owner', isEqualTo: uid)
      .where('isShared', isEqualTo: false)
      .limit(1)
      .get();
  if (q.docs.isEmpty) return null;
  return q.docs.first.id;
}

Future<int> deleteGoogleEventsFromCalendar(String calendarId) async {
  final ref = calendarEventsRef(calendarId);
  final snap = await ref.where('source', isEqualTo: 'google').limit(3000).get();
  if (snap.docs.isEmpty) return 0;

  int count = 0;
  WriteBatch batch = FirebaseFirestore.instance.batch();
  for (final d in snap.docs) {
    batch.delete(d.reference);
    count++;
    if (count % 400 == 0) {
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
    }
  }
  await batch.commit();
  return count;
}

String humanDateRange(DateTime s, DateTime e) {
  String two(int n) => n.toString().padLeft(2, '0');
  final sd = '${two(s.day)}-${two(s.month)}-${s.year}';
  final ed = '${two(e.day)}-${two(e.month)}-${e.year}';
  return (sd == ed) ? sd : '$sd → $ed';
}
