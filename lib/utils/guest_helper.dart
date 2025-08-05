import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

Future<String> getCurrentUserId() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    print("🔒 Firebase user UID: ${user.uid}");
    return user.uid;
  }

  final prefs = await SharedPreferences.getInstance();
  String? guestId = prefs.getString('guestId');
  if (guestId == null) {
    guestId = const Uuid().v4();
    await prefs.setString('guestId', guestId);
    print("👤 New guest ID generated: $guestId");
  } else {
    print("👤 Existing guest ID loaded: $guestId");
  }
  return guestId;
}

Future<String?> getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();

    if (user != null) {
      return user.email ?? 'User';
    } else {
      return prefs.getString('guestName') ?? 'Anonymous';
    }
  }
