import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:js' as js;

class StripeService {
  static const String _baseUrl =
      "https://asia-southeast1-shared-calendar-5958a.cloudfunctions.net/createPortalSession";


  /// Opens Stripe customer billing portal
  static Future<void> openStripePortal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final url = Uri.parse("$_baseUrl/createPortalSession");

    final res = await http.post(
      url,
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"returnUrl": kIsWeb ? windowLocation() : "app://return"}),
    );

    final data = jsonDecode(res.body);
    final portalUrl = data["url"];

    if (kIsWeb) {
      // ignore: undefined_prefixed_name
      return launchUrlWeb(portalUrl);
    }
  }

  /// Restore subscription/purchase → Cloud Function checks Stripe & updates Firestore
  static Future<bool> restorePurchase(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final token = await user.getIdToken();
    final url = Uri.parse("$_baseUrl/restorePurchase");

    final res = await http.post(
      url,
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"uid": uid}),
    );

    return res.statusCode == 200;
  }

  /// Helper to read browser URL for web redirects
  static String windowLocation() {
    try {
      // ignore: undefined_prefixed_name
      return Uri.base.toString();
    } catch (_) {
      return "https://linkupcalendar.app";
    }
  }
}

/// Web URL launcher polyfill
void launchUrlWeb(String url) {
  // ignore: undefined_prefixed_name
  js.context.callMethod('open', [url]);
}
