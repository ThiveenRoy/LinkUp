import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Create a Firebase auth session if none exists (sign in anonymously).
/// Also ensures there's a nice guest display name.
/// Returns the current Firebase user if available (null if we had to fall back).
Future<User?> ensureAuthSession() async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser != null) {
    await _ensureGuestName(); // also cache a readable name locally
    return auth.currentUser;
  }

  try {
    final cred = await auth.signInAnonymously();
    await _ensureGuestName(cred.user); // set displayName + cache
    return cred.user;
  } catch (e) {
    // Fall back to local guest-only identity (no Firebase user)
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
    // Keep a local copy too for legacy uses
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('guestId', user.uid);
    return user.uid;
  }

  // Pure local fallback
  return _ensureLocalGuestId();
}

/// Get a friendly display name:
/// - Signed-in user: displayName > email > cached guestName > 'Anonymous'
/// - Guest: generates/returns stable 'Guest-XXXX' and caches it
Future<String?> getCurrentUserName() async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser != null) {
    final u = auth.currentUser!;
    if ((u.displayName ?? '').trim().isNotEmpty) return u.displayName;
    if ((u.email ?? '').trim().isNotEmpty) return u.email;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('guestName') ?? 'Anonymous';
  } else {
    // Not signed in: ensure and return a cached guest name
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
  String basis = user?.uid ?? await _ensureLocalGuestId();

  final suffix = basis.length >= 4 ? basis.substring(basis.length - 4) : basis;
  final generated = 'Guest-${suffix.toUpperCase()}';

  await prefs.setString('guestName', generated);

  if (user != null && user.isAnonymous) {
    try {
      await user.updateDisplayName(generated);
    } catch (_) {
      // ignore; name is still cached locally
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
