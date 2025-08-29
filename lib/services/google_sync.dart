// lib/services/google_sync.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;

import '../config/google_oauth.dart'; // kGoogleWebClientId

// ---------- Google API client ----------
class GoogleCalendarService {
  GoogleCalendarService._();
  static final instance = GoogleCalendarService._();

  static const _scopes = <String>[gcal.CalendarApi.calendarScope];
  final GoogleSignIn _gsi = GoogleSignIn(
    clientId: kGoogleWebClientId,
    scopes: _scopes,
  );

  /// Quick check used by UI. NO silent sign-in here (prevents one-tap popup).
    Future<bool> hasSession() async {
    try {
      // Purely local checks – no network, no popup.
      if (_gsi.currentUser != null) return true;

      // isSignedIn() is cheap and does not prompt.
      return await _gsi.isSignedIn();
    } catch (_) {
      return false;
    }
  }

  /// Call this right before a user-initiated Google action.
  /// It will prompt only if there's no session; otherwise it no-ops.
    Future<void> ensureSignedInInteractive() async {
    if (await hasSession()) return;
    final acc = await _gsi.signIn(); // user-initiated → popup allowed
    if (acc == null) throw Exception('Google sign-in cancelled.');
  }

  /// DO NOT trigger sign-in here. Only use the existing session.
  Future<http.Client> _authedClient() async {
    final acc = _gsi.currentUser;
    if (acc == null) throw Exception('NO_GOOGLE_SESSION');
    final headers = await acc.authHeaders;
    return _AuthClient(headers);
  }

  Future<List<gcal.CalendarListEntry>> listCalendars() async {
    final c = await _authedClient();
    final api = gcal.CalendarApi(c);
    final res = await api.calendarList.list();
    return res.items ?? <gcal.CalendarListEntry>[];
  }

  Future<({List<gcal.Event> events, String? nextSyncToken})> listEvents({
    required String calendarId,
    String? syncToken,
    DateTime? timeMin,
    DateTime? timeMax,
  }) async {
    final c = await _authedClient();
    final api = gcal.CalendarApi(c);
    final result = await api.events.list(
      calendarId,
      syncToken: syncToken,
      timeMin: syncToken == null ? timeMin?.toUtc() : null,
      timeMax: syncToken == null ? timeMax?.toUtc() : null,
      singleEvents: true,
      showDeleted: true,
      maxResults: 2500,
    );
    return (events: result.items ?? <gcal.Event>[], nextSyncToken: result.nextSyncToken);
  }

  Future<void> signOut() async {
    try { await _gsi.disconnect(); } catch (_) {}
  }

  /// (Optional) Legacy helper kept for completeness.
  Future<bool> isSignedIn() async {
    try {
      final current = _gsi.currentUser ?? await _gsi.signInSilently();
      return current != null;
    } catch (_) {
      return false;
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

// ---------- Firestore paths ----------
DocumentReference<Map<String, dynamic>> calendarDoc(String calendarId) =>
    FirebaseFirestore.instance.collection('calendars').doc(calendarId);

CollectionReference<Map<String, dynamic>> calendarEventsRef(String calendarId) =>
    calendarDoc(calendarId).collection('events');

DocumentReference<Map<String, dynamic>> googleCfgRef(String calendarId) =>
    calendarDoc(calendarId).collection('integrations').doc('google');

// ---------- Config model ----------
class GoogleIntegrationConfig {
  final bool enabled;
  final String? calendarId;        // Google calendar id
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
  }) =>
      GoogleIntegrationConfig(
        enabled: enabled ?? this.enabled,
        calendarId: calendarId ?? this.calendarId,
        calendarSummary: calendarSummary ?? this.calendarSummary,
        syncToken: syncToken ?? this.syncToken,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );
}

Future<GoogleIntegrationConfig> loadGoogleCfgForCalendar(String calendarId) async {
  final s = await googleCfgRef(calendarId).get();
  return GoogleIntegrationConfig.fromMap(s.data());
}

Future<void> saveGoogleCfgForCalendar(
  String calendarId,
  GoogleIntegrationConfig cfg,
) async {
  await googleCfgRef(calendarId).set(cfg.toMap(), SetOptions(merge: true));
}

// ---------- Mapping: Google -> your event doc (startTime/endTime) ----------
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
    // Google all-day uses exclusive end -> make it inclusive end-of-day
    final s = e.start!.date!;
    final t = e.end!.date!;
    start = DateTime(s.year, s.month, s.day, 0, 0, 0);
    final endExclusive = DateTime(t.year, t.month, t.day, 0, 0, 0);
    end = endExclusive.subtract(const Duration(seconds: 1)); // 23:59:59 prev day
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
    'source': 'google',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

// ---------- Import into calendars/{calendarId}/events ----------
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
    final k =
        '${m['title']}|${(m['startTime'] as Timestamp?)?.toDate()}|${(m['endTime'] as Timestamp?)?.toDate()}';
    seen.add(k);
  }

  final batch = FirebaseFirestore.instance.batch();
  int count = 0;
  for (final ev in events) {
    final k =
        '${ev['title']}|${(ev['startTime'] as Timestamp).toDate()}|${(ev['endTime'] as Timestamp).toDate()}';
    if (seen.contains(k)) continue;
    batch.set(ref.doc(), ev);
    count++;
    if (count % 400 == 0) await batch.commit();
  }
  if (count % 400 != 0) await batch.commit();
  return count;
}

// ---------- Utility: find user's Master calendar id ----------
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

// ---------- Delete all Google-imported events for a calendar ----------
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

// ---------- Pretty range for previews ----------
String humanDateRange(DateTime s, DateTime e) {
  String two(int n) => n.toString().padLeft(2, '0');
  final sd = '${two(s.day)}-${two(s.month)}-${s.year}';
  final ed = '${two(e.day)}-${two(e.month)}-${e.year}';
  return (sd == ed) ? sd : '$sd → $ed';
}
