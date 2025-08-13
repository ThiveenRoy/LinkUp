import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'calendar_create_screen.dart';

class SharedCalendarList extends StatefulWidget {
  final Function(String calendarId, String calendarName) onSelect;

  const SharedCalendarList({super.key, required this.onSelect});

  @override
  State<SharedCalendarList> createState() => _SharedCalendarListState();
}

class _SharedCalendarListState extends State<SharedCalendarList> {
  String? _viewerId; // current user uid or guestId
  late Future<List<Map<String, dynamic>>> _futureCalendars;

  @override
  void initState() {
    super.initState();
    _futureCalendars = fetchJoinedCalendars();
    _resolveViewerId(); // resolves and rebuilds to show proper owner/leave buttons
  }

  Future<void> _resolveViewerId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _viewerId = user.uid);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    setState(() => _viewerId = prefs.getString('guestId'));
  }

  Future<List<Map<String, dynamic>>> fetchJoinedCalendars() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId');
    final currentId = user?.uid ?? guestId;

    final allCalendars = await FirebaseFirestore.instance
        .collection('calendars')
        .where('isShared', isEqualTo: true)
        .get();

    final joinedCalendars = allCalendars.docs.where((doc) {
      final members = List<Map<String, dynamic>>.from(
        (doc['members'] ?? []).map((e) => Map<String, dynamic>.from(e)),
      );
      return members.any((m) => (m['id'] ?? '') == currentId);
    }).toList();

    return joinedCalendars.map((doc) {
      final lastUpdated = doc['lastUpdatedAt'] as Timestamp?;
      return {
        'id': doc.id,
        'name': (doc['name'] ?? 'Untitled') as String,
        'lastUpdatedAt': lastUpdated,
        'updatedByName': doc['updatedByName'] ?? 'Someone',
        'updatedBy': doc['updatedBy'] ?? '',
        // your schema uses "owner"
        'ownerId': doc['owner'] ?? '',
      };
    }).toList();
  }

  /// -------- Owner: DELETE calendar (with all events) --------

  Future<void> _confirmAndDeleteCalendar(
    BuildContext context,
    String calendarId,
    String? calendarName,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete calendar?'),
        content: Text(
          'This will permanently delete "$calendarName" and all its events for everyone. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _deleteCalendarAndEvents(calendarId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calendar deleted')),
      );
      setState(() {
        _futureCalendars = fetchJoinedCalendars();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _deleteCalendarAndEvents(String calendarId) async {
    final db = FirebaseFirestore.instance;
    const pageSize = 200;

    Query<Map<String, dynamic>> q = db
        .collection('calendars')
        .doc(calendarId)
        .collection('events')
        .orderBy(FieldPath.documentId)
        .limit(pageSize);

    while (true) {
      final snap = await q.get();
      if (snap.docs.isEmpty) break;

      final batch = db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();

      final last = snap.docs.last;
      q = db
          .collection('calendars')
          .doc(calendarId)
          .collection('events')
          .orderBy(FieldPath.documentId)
          .startAfter([last.id])
          .limit(pageSize);
    }

    await db.collection('calendars').doc(calendarId).delete();
  }

  /// -------- Non-owner: LEAVE calendar (remove self from members) --------

  Future<void> _confirmAndLeaveCalendar(
    BuildContext context,
    String calendarId,
    String? calendarName,
  ) async {
    if (_viewerId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this calendar?'),
        content: Text(
          'You will be removed from "$calendarName". '
          'You can rejoin later if you receive a new invite link.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _leaveCalendar(calendarId, _viewerId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left this calendar')),
      );
      setState(() {
        _futureCalendars = fetchJoinedCalendars();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave: $e')),
      );
    }
  }

  Future<void> _leaveCalendar(String calendarId, String memberId) async {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('calendars').doc(calendarId);

    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final membersRaw = snap.data()?['members'] ?? [];
      final members = List<Map<String, dynamic>>.from(
        (membersRaw as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final newMembers =
          members.where((m) => (m['id'] ?? '') != memberId).toList();

      if (newMembers.length == members.length) return; // no change
      tx.update(ref, {'members': newMembers});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F7),
      appBar: AppBar(
        title: const Text('Shared Calendars'),
        backgroundColor: const Color(0xFFDBE2EF),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        elevation: 2,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureCalendars,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final calendars = snapshot.data ?? [];

          if (calendars.isEmpty) {
            return const Center(
              child: Text(
                'No shared calendars yet.',
                style: TextStyle(fontSize: 16, color: Colors.black),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: calendars.length,
            itemBuilder: (context, index) {
              final calendar = calendars[index];
              final lastUpdated = calendar['lastUpdatedAt'] as Timestamp?;
              final formattedTime = lastUpdated != null
                  ? DateFormat('hh:mm a').format(lastUpdated.toDate())
                  : 'N/A';

              final updatedBy = calendar['updatedByName'] ?? 'Someone';
              final ownerId = (calendar['ownerId'] as String? ?? '');
              final isOwnerView = (_viewerId ?? '') == ownerId;

              final subtitleText = 'Updated on $formattedTime by $updatedBy'
                  '${isOwnerView ? ' (Owner)' : ''}';

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  title: Text(
                    calendar['name'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF112D4E),
                    ),
                  ),
                  subtitle: Text(
                    subtitleText,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isOwnerView)
                        IconButton(
                          tooltip: 'Delete calendar',
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _confirmAndDeleteCalendar(
                            context,
                            calendar['id'] as String,
                            calendar['name'] as String?,
                          ),
                        )
                      else
                        IconButton(
                          tooltip: 'Leave calendar',
                          icon: const Icon(Icons.logout),
                          onPressed: () => _confirmAndLeaveCalendar(
                            context,
                            calendar['id'] as String,
                            calendar['name'] as String?,
                          ),
                        ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Color(0xFF3F72AF),
                      ),
                    ],
                  ),
                  onTap: () => widget.onSelect(
                    calendar['id'] as String,
                    calendar['name'] as String,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateCalendarDialog(context),
        label: const Text('Create'),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFFDBE2EF),
      ),
    );
  }
}
