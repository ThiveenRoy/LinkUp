// lib/screens/shared_calendar_list.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/theme_controller.dart';
import '../widgets/glass.dart';
import '../screens/calendar_create_screen.dart';

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
  String? _uid;
  bool isPremiumUser = false;

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
      _loadPremiumStatus();
    }
  }

  // ------------------------------------------------------
  // Load premium status (FIXED)
  // ------------------------------------------------------
  Future<void> _loadPremiumStatus() async {
    final uid = _uid;
    if (uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (!mounted) return;

    setState(() {
      // ✅ MUST match Firestore + SettingsScreen
      isPremiumUser = snap.data()?['premium'] == true;
    });
  }

  // ------------------------------------------------------
  // Fetch joined / owned calendars
  // ------------------------------------------------------
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

      final ownerField = data['owner'];
      final resolvedOwnerId = ownerField is String
          ? ownerField
          : (ownerField is Map && ownerField['id'] != null)
              ? ownerField['id'].toString()
              : '';

      final resolvedOwnerName = (data['ownerName'] ??
              (ownerField is Map ? (ownerField['name'] ?? '') : ''))
          .toString();

      return {
        'id': doc.id,
        'name': (data['name'] ?? 'Untitled') as String,
        'lastUpdatedAt': ts,
        'updatedByName': (data['updatedByName'] ?? 'Unknown') as String,
        'updatedBy': (data['updatedBy'] ?? '') as String,
        'ownerId': resolvedOwnerId,
        'ownerName': resolvedOwnerName,
      };
    }).toList();
  }

  // ------------------------------------------------------
  // Helpers
  // ------------------------------------------------------
  int _ownedSharedCalendarCount(List<Map<String, dynamic>> calendars) {
    final uid = _uid;
    if (uid == null) return 0;
    return calendars.where((c) => c['ownerId'] == uid).length;
  }

  String _subtitleForCalendar(Map<String, dynamic> calendar) {
    final ts = calendar['lastUpdatedAt'] as Timestamp?;
    final when =
        ts != null ? DateFormat('MMM d • hh:mm a').format(ts.toDate()) : 'N/A';

    final updatedByUid = calendar['updatedBy'] ?? '';
    final updatedByName = calendar['updatedByName'] ?? '';
    final ownerId = calendar['ownerId'] ?? '';
    final ownerName = calendar['ownerName'] ?? '';

    final isOwnerUpdate = updatedByUid == ownerId;
    final baseName = updatedByName.isNotEmpty
        ? updatedByName
        : ownerName.isNotEmpty
            ? ownerName
            : 'Unknown';

    return 'Updated $when by ${isOwnerUpdate ? '$baseName (Owner)' : baseName}';
  }

  // ------------------------------------------------------
  // Empty state
  // ------------------------------------------------------
  Widget _buildEmptyState(BuildContext context, int ownedCount) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassPanel(
              radius: const BorderRadius.all(Radius.circular(48)),
              padding: const EdgeInsets.all(20),
              blur: Theme.of(context).brightness == Brightness.dark ? 18 : 28,
              opacity:
                  Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.05,
              accentBorder: true,
              accentOpacity: 0.18,
              child: Icon(Icons.group_add_rounded, size: 56, color: cs.primary),
            ),
            const SizedBox(height: 18),
            Text(
              'No shared calendars yet',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a shared calendar for your group, or join one using an invite link.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => showCreateCalendarDialog(
                context,
                widget.theme,
                isPremium: isPremiumUser,
                ownedSharedCalendarCount: ownedCount,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Create calendar'),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------
  // Build
  // ------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futureCalendars,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final calendars = snapshot.data!;
        final ownedCount = _ownedSharedCalendarCount(calendars);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: calendars.isEmpty
              ? _buildEmptyState(context, ownedCount)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: calendars.length,
                  itemBuilder: (context, index) {
                    final c = calendars[index];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: GlassPanel(
                        radius: const BorderRadius.all(Radius.circular(16)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        blur: 22,
                        opacity: 0.06,
                        accentBorder: true,
                        accentOpacity: 0.18,
                        child: ListTile(
                          title: Text(c['name']),
                          subtitle: Text(_subtitleForCalendar(c)),
                          trailing: Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: cs.primary,
                            size: 18,
                          ),
                          onTap: () =>
                              widget.onSelect(c['id'], c['name']),
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: calendars.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => showCreateCalendarDialog(
                    context,
                    widget.theme,
                    isPremium: isPremiumUser,
                    ownedSharedCalendarCount: ownedCount,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
        );
      },
    );
  }
}
