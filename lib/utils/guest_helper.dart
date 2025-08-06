import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

Future<String> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      print("🔒 Firebase user UID: ${user.uid}");
      return user.uid;
    }

    final existingGuestId = prefs.getString('guestId');
    if (existingGuestId != null) {
      print("👤 Reusing existing guest ID: $existingGuestId");
      return existingGuestId;
    }

    // 🔁 Generate new only if guestId is truly missing
    final newGuestId = const Uuid().v4();
    await prefs.setString('guestId', newGuestId);
    print("🆕 Guest session started with ID: $newGuestId");
    return newGuestId;
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
