import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;
  String? error;

  Future<void> _login() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      Navigator.pushNamed(
        context,
        '/calendarHome',
        arguments: {
          'calendarId': null,
          'calendarName': 'LinkUp Calendar',
          'tabIndex': 0,
        },
      );
    } catch (e) {
      setState(() => error = "Login failed. ${e.toString()}");
    }

    setState(() => isLoading = false);
  }

  Future<void> _signUp() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      Navigator.pushNamed(
        context,
        '/calendarHome',
        arguments: {
          'calendarId': null,
          'calendarName': 'LinkUp Calendar',
          'tabIndex': 0,
        },
      );
    } catch (e) {
      setState(() => error = "Sign up failed. ${e.toString()}");
    }

    setState(() => isLoading = false);
  }

  Future<void> _continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    String? guestId = prefs.getString('guestId');

    if (guestId == null) {
      guestId = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString('guestId', guestId);
    }

    // ✅ Navigate to calendar list instead of /calendar to prevent auto jump to create
    Navigator.pushNamed(
      context,
      '/calendarHome',
      arguments: {
        'calendarId': null,
        'calendarName': 'LinkUp Calendar',
        'tabIndex': 0,
      },
    );

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login or Continue as Guest')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(error!, style: TextStyle(color: Colors.red)),
              ),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _login,
              child: isLoading ? CircularProgressIndicator() : Text('Login'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: isLoading ? null : _signUp,
              child: Text('Sign Up'),
            ),
            const SizedBox(height: 20),
            Divider(),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _continueAsGuest,
              child: Text('Continue as Guest'),
            ),
          ],
        ),
      ),
    );
  }
}
