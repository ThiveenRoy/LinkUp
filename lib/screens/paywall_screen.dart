// lib/screens/paywall_screen.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

class PaywallScreen extends StatelessWidget {
  final VoidCallback? onPurchased; // call after successful purchase if you want

  const PaywallScreen({super.key, this.onPurchased});

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    // Platform-aware copy
    final String ctaText =
        kIsWeb
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
                // Header
                Row(
                  children: [
                    Icon(Icons.workspace_premium, color: Colors.amber.shade600),
                    const SizedBox(width: 8),
                    Text(
                      'Premium',
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlock unlimited shared calendars, notifications, and all themes.',
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),

                // Plans row (Monthly / Lifetime). Hook these to Stripe/Play later.
                // Plans row (Monthly / Lifetime)
LayoutBuilder(
  builder: (ctx, c) {
    final isNarrow = c.maxWidth < 760;

    final row = Flex(
      direction: isNarrow ? Axis.vertical : Axis.horizontal,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          isNarrow ? CrossAxisAlignment.stretch : CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: isNarrow ? 0 : 1,
          child: _PlanCard(
            title: 'Monthly',
            price: '\$2.99',
            subtext: 'Billed monthly, cancel anytime',
            highlight: false,
            features: const [
              'Unlimited shared calendars',
              'Notifications & reminders',
              'All themes & accent colors',
              'Future AI summaries & exports',
            ],
            onPressed: () => _handleUpgrade(context, plan: 'monthly'),
            ctaText: kIsWeb
                ? 'Continue to Checkout'
                : _isAndroid
                    ? 'Upgrade with Google Play'
                    : _isIOS
                        ? 'Upgrade with App Store'
                        : 'Upgrade',
          ),
        ),
        SizedBox(width: isNarrow ? 0 : 16, height: isNarrow ? 16 : 0),
        Expanded(
          flex: isNarrow ? 0 : 1,
          child: _PlanCard(
            title: 'Lifetime',
            price: '\$14.99',
            subtext: 'One-time purchase',
            highlight: true,
            ribbon: 'Most Popular',
            features: const [
              'One payment, premium forever',
              'Unlimited shared calendars',
              'Notifications & reminders',
              'All themes & accent colors',
            ],
            onPressed: () => _handleUpgrade(context, plan: 'lifetime'),
            ctaText: kIsWeb
                ? 'Continue to Checkout'
                : _isAndroid
                    ? 'Upgrade with Google Play'
                    : _isIOS
                        ? 'Upgrade with App Store'
                        : 'Upgrade',
          ),
        ),
      ],
    );

    // Force both children to share tallest height in horizontal layout
    return isNarrow ? row : IntrinsicHeight(child: row);
  },
),


                const SizedBox(height: 28),

                // Comparison table (Free vs Premium)
                _Comparison(),

                const SizedBox(height: 24),

                // Restore + legal
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Restore purchases'),
                      onPressed: () {
                        // TODO:
                        // - Web: open Stripe Customer Portal OR re-check Firestore entitlement
                        // - Android/iOS: in_app_purchase.restorePurchases()
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Restore coming soon.')),
                        );
                      },
                    ),
                    TextButton(
                      onPressed: () {
                        // TODO: open your TOS/Privacy URLs
                      },
                      child: const Text('Terms'),
                    ),
                    TextButton(
                      onPressed: () {
                        // TODO: open your TOS/Privacy URLs
                      },
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

  void _handleUpgrade(BuildContext context, {required String plan}) async {
    // Wire these later:
    // - Web: call Cloud Function createCheckoutSession(priceId) -> redirect to Stripe
    // - Android: in_app_purchase flow
    // - iOS: in_app_purchase flow
    // For now: just show a placeholder.
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Upgrade'),
            content: Text(
              kIsWeb
                  ? 'Web checkout (Stripe) placeholder for "$plan".'
                  : _isAndroid
                  ? 'Google Play Billing placeholder for "$plan".'
                  : _isIOS
                  ? 'App Store placeholder for "$plan".'
                  : 'Upgrade placeholder for "$plan".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}

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
      // Optional: pick a sensible floor so ultra-short content still looks nice
      constraints: const BoxConstraints(minHeight: 320),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight ? cs.primary : cs.outlineVariant, width: 1),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(0.18),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ribbon != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ribbon!,
                style: tt.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (ribbon != null) const SizedBox(height: 8),

          Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(subtext, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Features block
          ...features.map((f) => _FeatLine(text: f)),

          // Push the CTA to the bottom
          const Spacer(),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            height: 44, // consistent button height across cards
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
          Icon(Icons.check_circle, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    TableRow row(String feature, String free, String pro) => TableRow(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(feature)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            free,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            pro,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.0),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.2),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withOpacity(0.35),
            ),
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Feature',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Free',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Premium',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          row('Shared calendars', 'Up to 2', 'Unlimited'),
          row('Notifications & reminders', '—', '✓'),
          row('Themes & accent colors', 'Blue only', 'All colors + custom'),
          row('AI summaries & exports', '—', '✓'),
        ],
      ),
    );
  }
}
