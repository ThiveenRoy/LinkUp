// lib/screens/join_calendar_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JoinCalendarScreen extends StatefulWidget {
  final String sharedLinkId;

  const JoinCalendarScreen({super.key, required this.sharedLinkId});

  @override
  State<JoinCalendarScreen> createState() => _JoinCalendarScreenState();
}

class _JoinCalendarScreenState extends State<JoinCalendarScreen> {
  String? calendarName;
  String? calendarId;
  String? ownerName;
  int memberCount = 0;
  bool isLoading = true;
  bool isAlreadyJoined = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;

    // Not signed in: stash invite & send to Auth
    if (user == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingInviteId', widget.sharedLinkId);
      // (calendarId will be filled after auth when we re-enter)
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
      return;
    }

    await fetchCalendarInfo();
    await _clearPendingInvite();
  }

  Future<void> fetchCalendarInfo() async {
    final user = FirebaseAuth.instance.currentUser!;
    final prefs = await SharedPreferences.getInstance();

    // Look up the calendar by link (try edit first, then view)
    final col = FirebaseFirestore.instance.collection('calendars');
    QueryDocumentSnapshot<Map<String, dynamic>>? doc;

    try {
      final q1 =
          await col
              .where('sharedLinkEdit', isEqualTo: widget.sharedLinkId)
              .limit(1)
              .get();
      if (q1.docs.isNotEmpty) {
        doc = q1.docs.first;
      } else {
        final q2 =
            await col
                .where('sharedLinkView', isEqualTo: widget.sharedLinkId)
                .limit(1)
                .get();
        if (q2.docs.isNotEmpty) doc = q2.docs.first;
      }
    } catch (_) {
      // ignore and fall through to "not found"
    }

    if (doc == null) {
      if (mounted) {
        setState(() {
          calendarName = null;
          isLoading = false;
        });
      }
      return;
    }

    final data = doc.data();
    final isEdit = (data['sharedLinkEdit'] == widget.sharedLinkId);
    final rawMembers = (data['members'] ?? []) as List<dynamic>;

    calendarId = doc.id;
    calendarName = (data['name'] ?? '').toString();

    // ---------- Owner name resolution ----------
    final ownerId = (data['owner'] ?? data['ownerId'])?.toString();
    String? resolvedOwnerName = (data['ownerName'] as String?)?.trim();

    if ((resolvedOwnerName == null || resolvedOwnerName.isEmpty) &&
        ownerId != null &&
        ownerId.isNotEmpty) {
      try {
        final ownerMember = rawMembers
            .map<Map<String, dynamic>?>(
              (m) => (m is Map<String, dynamic>) ? m : null,
            )
            .firstWhere(
              (m) => (m?['id']?.toString() ?? '') == ownerId,
              orElse: () => null,
            );
        if (ownerMember != null) {
          resolvedOwnerName = (ownerMember['name'] as String?)?.trim();
        }
      } catch (_) {}

      if (resolvedOwnerName == null || resolvedOwnerName.isEmpty) {
        try {
          final ownerDoc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(ownerId)
                  .get();
          if (ownerDoc.exists) {
            resolvedOwnerName =
                (ownerDoc.data()?['displayName'] as String?)?.trim() ??
                (ownerDoc.data()?['email'] as String?)?.trim();
          }
        } catch (_) {}
      }
    }

    ownerName =
        (resolvedOwnerName == null || resolvedOwnerName.isEmpty)
            ? 'User'
            : resolvedOwnerName;
    // ---------- /owner name resolution ----------

    // Membership check (supports members: [string] or [{id,name}])
    final normalized =
        rawMembers
            .map<String>((m) {
              if (m is String) return m;
              if (m is Map && m['id'] != null) return m['id'].toString();
              return '';
            })
            .where((e) => e.isNotEmpty)
            .toList();

    isAlreadyJoined = normalized.contains(user.uid);
    memberCount = rawMembers.length;

    // Cache whether this link grants edit access
    await prefs.setBool('editAccess_${calendarId!}', isEdit);

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _clearPendingInvite() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingInviteId');
    await prefs.remove('pendingSharedCalendarId');
  }

  /// Join as a member (auth-only)
  Future<void> _joinCalendarInternal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingInviteId', widget.sharedLinkId);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
      return;
    }
    if (calendarId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Missing calendar ID.')));
      return;
    }

    final uid = user.uid;
    final displayName =
        (user.displayName?.trim().isNotEmpty == true)
            ? user.displayName!.trim()
            : (user.email?.trim().isNotEmpty == true
                ? user.email!.trim()
                : 'User');

    final ref = FirebaseFirestore.instance
        .collection('calendars')
        .doc(calendarId);

    try {
      // Only update membership + bookkeeping fields (what rules allow)
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('Calendar not found');

        tx.update(ref, {
          'members': FieldValue.arrayUnion([
            {'id': uid, 'name': displayName},
          ]),
          'memberIds': FieldValue.arrayUnion([uid]),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
          'updatedByName': displayName,
        });
      });

      if (!mounted) return;
      await _clearPendingInvite();
      Navigator.pushReplacementNamed(
        context,
        '/calendarHome',
        arguments: {
          'calendarId': calendarId,
          'calendarName': calendarName,
          'tabIndex': 1,
          'fromInvite': true,
        },
      );
    } catch (e) {
      debugPrint('❌ Failed to join: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error joining calendar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Join Calendar"),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        foregroundColor: Colors.black,
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : calendarName == null
              ? const Center(
                child: Text(
                  "Invalid calendar link.",
                  style: TextStyle(fontSize: 16, color: Colors.redAccent),
                ),
              )
              : Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        size: 48,
                        color: Color(0xFF3F72AF),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isAlreadyJoined
                            ? "You're already a member of"
                            : "You've been invited to join",
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          Text(
                            '"$calendarName"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF112D4E),
                            ),
                          ),
                          if (ownerName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Created by $ownerName',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "$memberCount member${memberCount > 1 ? 's' : ''} in this calendar",
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Greeting / context
                      Text(
                        user != null
                            ? "Welcome, ${(user.displayName ?? user.email ?? 'User')}!"
                            : "Please sign in to join.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 30),

                      // === Buttons ===
                      if (isAlreadyJoined) ...[
                        ElevatedButton.icon(
                          onPressed: () async{
                            await _clearPendingInvite();
                            Navigator.pushReplacementNamed(
                              context,
                              '/calendarHome',
                              arguments: {
                                'calendarId': calendarId,
                                'calendarName': calendarName,
                                'tabIndex': 1,
                                'fromInvite': true,
                              },
                            );
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Show Calendar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3F72AF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ] else ...[
                        ElevatedButton.icon(
                          onPressed:
                              user == null ? null : _joinCalendarInternal,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text("Join Calendar"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3F72AF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (user == null)
                          OutlinedButton(
                            onPressed: () async {
                              // Stash invite so we return here after login
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString(
                                'pendingInviteId',
                                widget.sharedLinkId,
                              );
                              if (calendarId != null) {
                                await prefs.setString(
                                  'pendingSharedCalendarId',
                                  calendarId!,
                                );
                              }
                              if (!mounted) return;
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/',
                                (_) => false,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF3F72AF),
                              side: const BorderSide(color: Color(0xFF3F72AF)),
                              backgroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Log in to join",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3F72AF),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }
}
