// lib/utils/guest_helper.dart
//
// Minimal auth helpers after removing guest/anonymous mode.
// - No anonymous sessions
// - No local guestId/guestName
// - Requires a real Firebase user
//
// Keep the same function names so existing code compiles.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional: keep LOCAL persistence on web (helps regular logins persist).
Future<void> bootstrapAuth() async {
  if (kIsWeb) {
    try { await FirebaseAuth.instance.setPersistence(Persistence.LOCAL); } catch (_) {}
  }
}

/// Do NOT create anonymous sessions anymore. Just return the current user.
/// If you need to enforce auth, check for null at the call site.
Future<User?> ensureAuthSession() async {
  return FirebaseAuth.instance.currentUser;
}

/// Returns the signed-in user's uid. Throws if no user is signed in.
Future<String> getCurrentUserId({bool createAuthIfMissing = true}) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) {
    throw StateError('No signed-in user. Authentication required.');
  }
  return u.uid;
}

/// Display name helper for real accounts.
Future<String?> getCurrentUserName() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return null;
  final dn = (u.displayName ?? '').trim();
  if (dn.isNotEmpty) return dn;
  final em = (u.email ?? '').trim();
  if (em.isNotEmpty) return em;
  return 'User';
}

/* --------------------------------------------------------------------------
   Firestore membership helpers (still useful without guests)
---------------------------------------------------------------------------*/

Future<void> ensureCalendarMembership(String calendarId, {String? name}) async {
  final uid = await getCurrentUserId();
  final display = name ?? (await getCurrentUserName()) ?? 'User';

  final ref = FirebaseFirestore.instance.collection('calendars').doc(calendarId);
  await ref.set({
    'members': FieldValue.arrayUnion([{'id': uid, 'name': display}]),
    'memberIds': FieldValue.arrayUnion([uid]),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> removeCalendarMembership(String calendarId, {String? name}) async {
  final uid = await getCurrentUserId();
  final display = name ?? (await getCurrentUserName()) ?? 'User';

  final ref = FirebaseFirestore.instance.collection('calendars').doc(calendarId);
  await ref.set({
    'members': FieldValue.arrayRemove([{'id': uid, 'name': display}]),
    'memberIds': FieldValue.arrayRemove([uid]),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/* --------------------------------------------------------------------------
   UI state helpers
---------------------------------------------------------------------------*/

/// Clear transient UI flags you may have used earlier. Safe to keep.
Future<void> clearGuestUiStateOnly() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('pendingInviteId');
  await prefs.remove('pendingSharedCalendarId');
  await prefs.remove('selectedCalendarId');
  await prefs.remove('selectedTabIndex');
  // We intentionally do NOT manage onboarding here; your app can decide.
}

/* --------------------------------------------------------------------------
   Logout (no guest branch)
---------------------------------------------------------------------------*/

Future<void> appLogout(BuildContext context) async {
  try { await GoogleSignIn().signOut(); } catch (_) {}
  try { await FirebaseAuth.instance.signOut(); } catch (_) {}

  await clearGuestUiStateOnly();

  if (context.mounted) {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }
}
