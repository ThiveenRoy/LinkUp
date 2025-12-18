import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: const Text(
          '''
LinkUp Calendar – Privacy Policy

Your privacy matters to us.

• We store only necessary account and calendar data.
• We do not sell or share your personal data.
• Authentication is handled via Firebase.
• Payments are processed securely by Stripe.

We may collect anonymous usage data to improve the app.

Last updated: January 2025
Contact: linkupcalendar@gmail.com
          ''',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
      ),
    );
  }
}
