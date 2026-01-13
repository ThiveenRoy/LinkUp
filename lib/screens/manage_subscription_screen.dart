import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../services/stripe_service.dart';
import '../widgets/glass.dart';

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

    // Accent ONLY for borders (as requested)
    final accent = cs.primary;

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

          final status =
              premium ? "Active • Premium subscription" : "Inactive";

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassPanel(
                radius: const BorderRadius.all(Radius.circular(16)),
                padding: const EdgeInsets.all(20),
                blur: 20,
                opacity: 0.08,
                borderWidth: 1.3,
                accentBorder: true,
                accentOpacity: 0.30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ================= HEADER =================
                    Row(
                      children: [
                        Icon(
                          Icons.workspace_premium,
                          size: 32,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Premium",
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // ================= DETAILS =================
                    _detailRow(
                      context,
                      "Status",
                      status,
                    ),
                    _detailRow(
                      context,
                      "Premium since",
                      since,
                    ),
                    _detailRow(
                      context,
                      "Customer ID",
                      customerId,
                    ),

                    const SizedBox(height: 24),
                    Divider(color: cs.outlineVariant),
                    const SizedBox(height: 24),

                    // ================= MANAGE PAYMENTS =================
                    _actionButton(
                      context,
                      icon: Icons.payment,
                      text: "Manage payments",
                      borderColor: accent,
                      onTap: () => StripeService.openStripePortal(),
                    ),

                    const SizedBox(height: 14),

                    // ================= RESTORE =================
                    _actionButton(
                      context,
                      icon: Icons.refresh,
                      text: "Restore purchase",
                      borderColor: accent,
                      onTap: () async {
                        final ok =
                            await StripeService.restorePurchase(uid);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? "Subscription restored!"
                                    : "No purchase found.",
                              ),
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
                  "cancellation are handled securely via Stripe.",
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
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

  Widget _detailRow(
    BuildContext context,
    String label,
    String value,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ★ Button with ONLY BORDER accent
  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.3),
          color: cs.surface.withOpacity(0.08),
        ),
        child: Row(
          children: [
            Icon(icon, color: cs.onSurface, size: 20),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
