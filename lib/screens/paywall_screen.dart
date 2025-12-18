// lib/screens/paywall_screen.dart

import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallScreen extends StatelessWidget {
  final VoidCallback? onPurchased;

  const PaywallScreen({super.key, this.onPurchased});

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static const String kFunctionsBaseUrl =
      'https://asia-southeast1-shared-calendar-5958a.cloudfunctions.net';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final String ctaText = kIsWeb
        ? 'Continue to Checkout'
        : _isAndroid
            ? 'Upgrade with Google Play'
            : _isIOS
                ? 'Upgrade with App Store'
                : 'Upgrade';

    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.workspace_premium,
                        color: Colors.amber.shade600),
                    const SizedBox(width: 8),
                    Text(
                      'Premium',
                      style: tt.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlock unlimited shared calendars, notifications, and all themes.',
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),

                // =========================
                // RESPONSIVE PLAN CARDS
                // =========================
                LayoutBuilder(
                  builder: (_, c) {
                    final isNarrow = c.maxWidth < 760;

                    final monthly = _PlanCard(
                      title: 'Monthly',
                      price: '\$2.99',
                      subtext: 'Billed monthly, cancel anytime',
                      features: const [
                        'Unlimited shared calendars',
                        'Notifications & reminders',
                        'All themes & accent colors',
                        'Future AI summaries & exports',
                      ],
                      onPressed: () =>
                          _handleUpgrade(context, plan: 'monthly'),
                      ctaText: ctaText,
                    );

                    final yearly = _PlanCard(
                      title: 'Yearly',
                      price: '\$29.99',
                      subtext: 'One-time yearly billing',
                      highlight: true,
                      ribbon: 'Best Value',
                      features: const [
                        'Unlimited shared calendars',
                        'Notifications & reminders',
                        'All themes & accent colors',
                      ],
                      onPressed: () =>
                          _handleUpgrade(context, plan: 'yearly'),
                      ctaText: ctaText,
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          monthly,
                          const SizedBox(height: 16),
                          yearly,
                        ],
                      );
                    }

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: monthly),
                          const SizedBox(width: 16),
                          Expanded(child: yearly),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),
                const _Comparison(),
                const SizedBox(height: 24),

                // =========================
                // FOOTER
                // =========================
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: Icon(Icons.refresh, color: cs.primary),
                      label: const Text('Restore purchases'),
                      onPressed: () => _onRestore(context),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/terms'),
                      child: const Text('Terms'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/privacy'),
                      child: const Text('Privacy'),
                    ),
                  
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================================
  // WEB CHECKOUT
  // ================================
  Future<void> _handleUpgrade(BuildContext context,
    {required String plan}) async {
  if (!kIsWeb) {
    // mobile placeholder unchanged
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('Upgrade'),
        content: Text('Mobile billing coming soon.'),
      ),
    );
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please sign in first.')),
    );
    return;
  }

  try {
    debugPrint('🟡 Checkout clicked ($plan)');

    final idToken = await user.getIdToken(true);
    final origin = Uri.base.origin;

    final resp = await http.post(
      Uri.parse('$kFunctionsBaseUrl/createCheckoutSession'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'plan': plan,
        'successUrl': '$origin/billing/success',
        'cancelUrl': '$origin/billing/cancel',
      }),
    );

    debugPrint('🟢 Status: ${resp.statusCode}');
    debugPrint('🟢 Body: ${resp.body}');

    if (resp.statusCode != 200) {
      throw Exception('Server error ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body);
    final url = data['url'];

    if (url == null) {
      throw Exception('No checkout URL returned');
    }

    final uri = Uri.parse(url);

    final launched = await launchUrl(
      uri,
      webOnlyWindowName: '_self',
      mode: LaunchMode.platformDefault,
    );

    if (!launched) {
      throw Exception('Failed to launch checkout URL');
    }
  } catch (e, st) {
    debugPrint('🔴 Checkout failed');
    debugPrint(e.toString());
    debugPrintStack(stackTrace: st);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Checkout failed: $e'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}


  // ================================
  // RESTORE
  // ================================
  Future<void> _onRestore(BuildContext context) async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore coming soon on mobile.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (snap.data()?['premium'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Premium restored.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No purchases found.')),
      );
    }
  }
}

/* ================================
   PLAN CARD
================================ */

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String subtext;
  final List<String> features;
  final VoidCallback onPressed;
  final String ctaText;
  final bool highlight;
  final String? ribbon;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.subtext,
    required this.features,
    required this.onPressed,
    required this.ctaText,
    this.highlight = false,
    this.ribbon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? cs.primary : cs.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ribbon != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(ribbon!,
                  style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold)),
            ),
          if (ribbon != null) const SizedBox(height: 8),

          Text(title,
              style: tt.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),

          Text('$price • $subtext',
              style:
                  tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),

          const SizedBox(height: 16),
          ...features.map((f) => _FeatLine(text: f)),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: onPressed,
              child: Text(ctaText),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatLine extends StatelessWidget {
  final String text;
  const _FeatLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/* ================================
   COMPARISON
================================ */

class _Comparison extends StatelessWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    TableRow row(String feature, String free, String premium) => TableRow(
          children: [
            _cell(feature),
            _cell(free),
            _cell(premium, bold: true),
          ],
        );

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1.5),
        },
        children: [
          row('Shared calendars', 'Up to 2', 'Unlimited'),
          row('Themes', 'Default only', 'All + custom themes'),
          row(
            'Future features',
            '—',
            'Premium only',
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
}

