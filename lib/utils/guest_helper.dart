import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Call this once at app start (and before any Firestore reads).
/// - Sets LOCAL persistence on web
/// - Ensures there's a Firebase session (anonymous if needed)
/// - Ensures a friendly guest displayName (and caches it)

Future<void> bootstrapAuth() async {
  final auth = FirebaseAuth.instance;

  // ✅ Web only: persist session so the anonymous UID survives reloads
  if (kIsWeb) {
    try {
      await auth.setPersistence(Persistence.LOCAL);
    } catch (_) {
      // ignore
    }
  }

  // ✅ Reuse existing session; otherwise create one anon
  if (auth.currentUser == null) {
    await ensureAuthSession();                // your existing function
  } else {
    await _ensureGuestName(auth.currentUser); // idempotent name
  }

  // ✅ Help your _computeInitialRoute() logic
  await _persistGuestRoutingFlags();
}

Future<void> _persistGuestRoutingFlags() async {
  final prefs = await SharedPreferences.getInstance();
  final u = FirebaseAuth.instance.currentUser;
  if (u != null) {
    await prefs.setString('guestId', u.uid);
    if (u.isAnonymous && !(prefs.getBool('hasContinuedAsGuest') ?? false)) {
      await prefs.setBool('hasContinuedAsGuest', true);
    }
  }
}

/// Ensure a Firebase auth session (anonymous if none).
/// Returns the current Firebase user (or null if we had to fall back).
Future<User?> ensureAuthSession() async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser != null) {
    await _ensureGuestName(auth.currentUser);
    return auth.currentUser;
  }

  try {
    final cred = await auth.signInAnonymously();
    await _ensureGuestName(cred.user);
    return cred.user;
  } catch (_) {
    // Ultimate fallback: local-only identity (no Firebase session => rules requiring
    // request.auth will fail, so prefer fixing auth over relying on this)
    await _ensureLocalGuestId();
    return null;
  }
}

/// Get the current user id. If there's no session, we create an anonymous one.
/// If Firebase is unavailable, we fall back to a locally-stored guestId.
Future<String> getCurrentUserId({bool createAuthIfMissing = true}) async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser == null && createAuthIfMissing) {
    await ensureAuthSession();
  }

  final user = auth.currentUser;
  if (user != null) {
    // Keep a local copy for legacy code paths
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('guestId', user.uid);
    return user.uid;
  }

  // Pure local fallback (try to avoid if your rules need request.auth != null)
  return _ensureLocalGuestId();
}

/// Friendly display name for UI:
/// - Signed-in: displayName > email > cached guestName > 'Anonymous'
/// - Guest/anon: generates stable 'Guest-XXXX' and caches it; also sets Firebase displayName when possible.
Future<String?> getCurrentUserName() async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser != null) {
    final u = auth.currentUser!;
    if ((u.displayName ?? '').trim().isNotEmpty) return u.displayName;
    if ((u.email ?? '').trim().isNotEmpty) return u.email;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('guestName') ?? 'Anonymous';
  } else {
    // Not signed-in: ensure and return a cached guest name
    return await _ensureGuestName();
  }
}

/// Ensure we have a readable guest name (e.g., 'Guest-1A2B').
/// - Caches in SharedPreferences ('guestName').
/// - If there's an anonymous Firebase user, sets their displayName too.
Future<String> _ensureGuestName([User? maybeUser]) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString('guestName');
  if (cached != null && cached.trim().isNotEmpty) return cached;

  final auth = FirebaseAuth.instance;
  final user = maybeUser ?? auth.currentUser;

  // Prefer Firebase uid as basis; if no user, use local guestId
  final basis = user?.uid ?? await _ensureLocalGuestId();

  final suffix = basis.length >= 4 ? basis.substring(basis.length - 4) : basis;
  final generated = 'Guest-${suffix.toUpperCase()}';

  await prefs.setString('guestName', generated);

  if (user != null) {
    try {
      await user.updateDisplayName(generated);
    } catch (_) {
      // ignore – name is still cached locally
    }
  }
  return generated;
}

/// Ensure there's a local guestId in SharedPreferences; return it.
Future<String> _ensureLocalGuestId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString('guestId');
  if (existing != null && existing.isNotEmpty) return existing;

  final id = const Uuid().v4();
  await prefs.setString('guestId', id);
  return id;
}

/* -----------------------------------------------------------------------------
   Helpers for Firestore membership (to satisfy security rules that check
   `memberIds` contains the caller's uid). Call these when someone joins/leaves.
------------------------------------------------------------------------------*/

/// Ensure the current user is listed as a member of the calendar in both
/// 'members' (for UI) and 'memberIds' (for rules).
Future<void> ensureCalendarMembership(String calendarId, {String? name}) async {
  final uid = await getCurrentUserId();
  final display = name ?? (await getCurrentUserName()) ?? 'Guest';

  final ref = FirebaseFirestore.instance.collection('calendars').doc(calendarId);
  await ref.set({
    'members': FieldValue.arrayUnion([{'id': uid, 'name': display}]),
    'memberIds': FieldValue.arrayUnion([uid]),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}


/// Remove the current user from the calendar's members (both arrays).
Future<void> removeCalendarMembership(String calendarId, {String? name}) async {
  final uid = await getCurrentUserId(createAuthIfMissing: false);
  final display = name ?? (await getCurrentUserName()) ?? 'Guest';

  final ref = FirebaseFirestore.instance.collection('calendars').doc(calendarId);
  await ref.set({
    'members': FieldValue.arrayRemove([{'id': uid, 'name': display}]),
    'memberIds': FieldValue.arrayRemove([uid]),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Clear ONLY ephemeral UI/local state for guests.
/// IMPORTANT: do NOT delete 'guestId' or 'guestName' – those keep the UID/name stable.
Future<void> clearGuestUiStateOnly() async {
  final prefs = await SharedPreferences.getInstance();

  // 👉 Clear transient flags / selections your app uses.
  // (Keep guestId / guestName so anon identity persists.)
  await prefs.remove('pendingInviteId');
  await prefs.remove('pendingSharedCalendarId');

  // If you cache selected calendar, filters, tab index, etc. clear them here:
  await prefs.remove('selectedCalendarId');
  await prefs.remove('selectedTabIndex');

  // Keep onboarding status unless you want to re-show it:
  // await prefs.remove('seenTutorial'); // (leave commented out)
}

/// App-wide logout:
/// - If user is anonymous: DO NOT sign out. Just clear UI state & go to landing.
/// - If user is real (Google/email): sign out, then go to landing.
Future<void> appLogout(BuildContext context) async {
  final auth = FirebaseAuth.instance;
  final u = auth.currentUser;

  if (u != null && u.isAnonymous) {
    // keep anon UID alive; do NOT signOut
    await clearGuestUiStateOnly();

    // ⬇️ tell AuthLandingScreen not to auto-redirect this time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('forceLanding', true);

    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
    return;
  }

  try { await GoogleSignIn().signOut(); } catch (_) {}
  try { await auth.signOut(); } catch (_) {}

  await clearGuestUiStateOnly();

  if (context.mounted) {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }
}

