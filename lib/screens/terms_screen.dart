import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: const Text(
          '''
LinkUp Calendar – Terms of Service

By using LinkUp Calendar, you agree to the following terms.

• LinkUp Calendar is provided "as is" without warranties.
• Premium purchases unlock additional features.
• Subscriptions can be canceled at any time.
• We may update features or pricing in future versions.

Payments are securely handled by Stripe.
We do not store your card information.

Last updated: January 2025
Contact: linkupcalendar@gmail.com
          ''',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
      ),
    );
  }
}
