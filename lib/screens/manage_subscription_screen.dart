import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/stripe_service.dart';
import '../widgets/glass.dart';
import 'package:intl/intl.dart';

class ManageSubscriptionScreen extends StatelessWidget {
  const ManageSubscriptionScreen({super.key});

  String _fmt(dynamic ts) {
    if (ts == null) return "-";
    try {
      DateTime d;
      if (ts is Timestamp) d = ts.toDate();
      else if (ts is DateTime) d = ts;
      else return "-";
      return DateFormat("dd MMM yyyy, HH:mm").format(d);
    } catch (_) {
      return "-";
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = cs.secondary; // ★ Accent color used ONLY for borders

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Manage Subscription")),
        body: const Center(child: Text("Please sign in.")),
      );
    }

    final uid = user.uid;
    final userStream =
        FirebaseFirestore.instance.collection("users").doc(uid).snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text("Manage Subscription")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userStream,
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};

          final premium = data["premium"] == true;
          final since = _fmt(data["premiumSince"]);
          final customerId = data["stripeCustomerId"] ?? "-";

          final status = premium ? "Active • Yearly subscription" : "Inactive";

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassPanel(
                radius: const BorderRadius.all(Radius.circular(16)),
                padding: const EdgeInsets.all(20),
                blur: 20,
                opacity: 0.07,
                borderWidth: 1.3,
                accentBorder: true,
                accentOpacity: 0.28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---------------- HEADER ----------------
                    Row(
                      children: [
                        Icon(Icons.workspace_premium,
                            size: 32, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          "Premium", // ★ Only Premium, no (yearly)
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // ---------------- DETAILS ----------------
                    _detailRow("Status", status),
                    _detailRow("Premium since", since),
                    _detailRow("Customer ID", customerId),

                    const SizedBox(height: 25),
                    Divider(color: Colors.white.withOpacity(0.15)),
                    const SizedBox(height: 25),

                    // ---------------- MANAGE PAYMENTS ----------------
                    _actionButton(
                      context,
                      icon: Icons.payment,
                      text: "Manage Payments",
                      borderColor: accent, // ★ Only border accent
                      onTap: () => StripeService.openStripePortal(),
                    ),

                    const SizedBox(height: 14),

                    // ---------------- RESTORE PURCHASE ----------------
                    _actionButton(
                      context,
                      icon: Icons.refresh,
                      text: "Restore Purchase",
                      borderColor: accent, // ★ Only border accent
                      onTap: () async {
                        final ok = await StripeService.restorePurchase(uid);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? "Subscription restored!"
                                  : "No purchase found."),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              Center(
                child: Text(
                  "Changes such as updating payment method or\n"
                  "cancellation will be handled through Stripe.",
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ================================================================
  // REUSABLE UI COMPONENTS
  // ================================================================

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Text(value, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  // ★ Button with ONLY BORDER using accent color
  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.3),
          color: Colors.white.withOpacity(0.05), // glassy but subtle
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20), // ★ White icon
            const SizedBox(width: 12),
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white, // ★ White text
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
