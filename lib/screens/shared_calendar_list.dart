// lib/screens/shared_calendar_list.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:linkup_calendar/screens/calendar_create_screen.dart';

import '../theme/theme_controller.dart';
import '../widgets/glass.dart';

class SharedCalendarList extends StatefulWidget {
  final void Function(String calendarId, String calendarName) onSelect;
  final ThemeController theme;

  const SharedCalendarList({
    super.key,
    required this.onSelect,
    required this.theme,
  });

  @override
  State<SharedCalendarList> createState() => _SharedCalendarListState();
}

class _SharedCalendarListState extends State<SharedCalendarList> {
  String? _uid; // signed-in Firebase UID only
  late Future<List<Map<String, dynamic>>> _futureCalendars;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
        }
      });
    } else {
      _uid = u.uid;
      _futureCalendars = _fetchJoinedCalendars();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchJoinedCalendars() async {
    final uid = _uid!;
    final col = FirebaseFirestore.instance.collection('calendars');

    final byMemberIds = await col
        .where('isShared', isEqualTo: true)
        .where('memberIds', arrayContains: uid)
        .get();

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = byMemberIds.docs;

    if (docs.isEmpty) {
      final allShared = await col.where('isShared', isEqualTo: true).get();
      docs = allShared.docs.where((d) {
        final raw = d.data()['members'] ?? [];
        final members = (raw as List)
            .map<String>((m) {
              if (m is String) return m;
              if (m is Map && m['id'] != null) return m['id'].toString();
              return '';
            })
            .where((e) => e.isNotEmpty)
            .toList();
        return members.contains(uid);
      }).toList();
    }

    return docs.map((doc) {
      final data = doc.data();
      final ts = data['lastUpdatedAt'] as Timestamp?;
      return {
        'id': doc.id,
        'name': (data['name'] ?? 'Untitled') as String,
        'lastUpdatedAt': ts,
        'updatedByName': (data['updatedByName'] ?? 'Unknown') as String,
        'updatedBy': (data['updatedBy'] ?? '') as String,
        'ownerId': (data['owner'] ?? '') as String,
      };
    }).toList();
  }

  Future<void> _confirmAndDeleteCalendar(
    BuildContext context,
    String calendarId,
    String? calendarName,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('Delete calendar?'),
        content: Text(
          'This will permanently delete "$calendarName" and all its events for everyone. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _deleteCalendarAndEvents(calendarId);

      final refreshed = _fetchJoinedCalendars();
      if (!mounted) return;
      setState(() => _futureCalendars = refreshed);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calendar deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
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

  Future<void> _confirmAndLeaveCalendar(
    BuildContext context,
    String calendarId,
    String? calendarName,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final uid = _uid;
    if (uid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('Leave this calendar?'),
        content: Text(
          'You will be removed from "$calendarName". '
          'You can rejoin later if you receive a new invite link.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _leaveCalendar(calendarId, uid);

      final refreshed = _fetchJoinedCalendars();
      if (!mounted) return;
      setState(() => _futureCalendars = refreshed);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You left this calendar')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to leave: $e')));
    }
  }

  Future<void> _leaveCalendar(String calendarId, String memberUid) async {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('calendars').doc(calendarId);

    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data()!;
      final raw = (data['members'] ?? []) as List<dynamic>;
      final newMembers = <Map<String, dynamic>>[];

      for (final m in raw) {
        if (m is Map && (m['id']?.toString() ?? '') != memberUid) {
          newMembers.add({'id': m['id'], 'name': m['name']});
        } else if (m is String && m != memberUid) {
          newMembers.add({'id': m, 'name': ''});
        }
      }

      tx.update(ref, {
        'members': newMembers,
        'memberIds': FieldValue.arrayRemove([memberUid]),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'updatedBy': memberUid,
        'updatedByName': FirebaseAuth.instance.currentUser?.displayName ??
            FirebaseAuth.instance.currentUser?.email ??
            'User',
      });
    });
  }

  // ---------- Empty state (theme aware) ----------
  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassPanel(
                radius: const BorderRadius.all(Radius.circular(48)),
                padding: const EdgeInsets.all(20),
                blur: Theme.of(context).brightness == Brightness.dark ? 18 : 28,
                opacity: Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.05,
                accentBorder: true,
                accentOpacity: 0.18,
                child: Icon(Icons.group_add_rounded, size: 56, color: cs.primary),
              ),
              const SizedBox(height: 18),
              Text(
                'No shared calendars yet',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a shared calendar for your group, or join one using an invite link.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => showCreateCalendarDialog(context, widget.theme),
                    icon: const Icon(Icons.add),
                    label: const Text('Create calendar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: cs.surface,
                          title: const Text('Join with a link'),
                          content: const Text(
                            'Got an invite link? Paste it in your browser. We’ll detect it and guide you to join.',
                          ),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
                        ),
                      );
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('How to join'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: cs.surface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(backgroundColor: Colors.transparent, body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futureCalendars,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(backgroundColor: Colors.transparent, body: Center(child: CircularProgressIndicator()));
        }

        final calendars = snapshot.data ?? [];
        final isEmpty = calendars.isEmpty;

        return Scaffold(
          backgroundColor: Colors.transparent, // let wallpaper show
          body: isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: calendars.length,
                  itemBuilder: (context, index) {
                    final calendar = calendars[index];
                    final ts = calendar['lastUpdatedAt'] as Timestamp?;
                    final when = ts != null ? DateFormat('MMM d • hh:mm a').format(ts.toDate()) : 'N/A';
                    final updatedBy = (calendar['updatedByName'] ?? 'Unknown') as String;

                    final ownerId = (calendar['ownerId'] as String? ?? '');
                    final isOwnerView = _uid == ownerId;

                    final subtitleText = 'Updated $when by $updatedBy${isOwnerView ? ' • Owner' : ''}';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: GlassPanel(
                        radius: const BorderRadius.all(Radius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        blur: isDark ? 18 : 28,
                        opacity: isDark ? 0.10 : 0.05,
                        accentBorder: true,
                        accentOpacity: isDark ? 0.16 : 0.20,
                        borderWidth: 0.9,
                        child: ListTile(
                          dense: false,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          title: Text(
                            calendar['name'] as String,
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
                          ),
                          subtitle: Text(
                            subtitleText,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isOwnerView)
                                IconButton(
                                  tooltip: 'Delete calendar',
                                  icon: Icon(Icons.delete_outline, color: cs.error),
                                  onPressed: () => _confirmAndDeleteCalendar(
                                    context,
                                    calendar['id'] as String,
                                    calendar['name'] as String?,
                                  ),
                                )
                              else
                                IconButton(
                                  tooltip: 'Leave calendar',
                                  icon: Icon(Icons.logout, color: cs.onSurfaceVariant),
                                  onPressed: () => _confirmAndLeaveCalendar(
                                    context,
                                    calendar['id'] as String,
                                    calendar['name'] as String?,
                                  ),
                                ),
                              Icon(Icons.arrow_forward_ios_rounded, color: cs.primary, size: 18),
                            ],
                          ),
                          onTap: () => widget.onSelect(calendar['id'] as String, calendar['name'] as String),
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => showCreateCalendarDialog(context, widget.theme),
                  label: const Text('Create'),
                  icon: const Icon(Icons.add),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  elevation: 4,
                ),
        );
      },
    );
  }
}
