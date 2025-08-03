import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthLandingScreen extends StatefulWidget {
  @override
  _AuthLandingScreenState createState() => _AuthLandingScreenState();
}

class _AuthLandingScreenState extends State<AuthLandingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;
  bool isLogin = true;
  String? error;

  Future<void> _loginOrSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
      Navigator.pushNamed(context, '/calendarHome', arguments: {
        'calendarId': null,
        'calendarName': 'LinkUp Calendar',
        'tabIndex': 0,
      });
    } catch (e) {
      setState(() => error = isLogin
          ? "Login failed. Please check your credentials."
          : "Sign up failed. Please try again.");
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

    Navigator.pushNamed(context, '/calendarHome', arguments: {
      'calendarId': null,
      'calendarName': 'LinkUp Calendar',
      'tabIndex': 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      body: isMobile
          ? _buildFormLayout()
          : Row(
              children: [
                Expanded(child: _buildFormLayout()),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/bg_login.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFormLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo_final.png', height: 170, fit: BoxFit.contain),
              const SizedBox(height: 32),
              _buildLoginForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isLogin ? 'Welcome Back to LinkUp Calendar' : 'Create Your LinkUp Account',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isLogin
                ? 'Login to continue using Link Up'
                : 'Sign up to start collaborating',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (error != null)
            Card(
              color: Colors.red[100],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[700]),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
           validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return 'Email is required';
              }
              final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(trimmed)) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'Minimum 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: isLoading ? null : _loginOrSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFCBDCEB),
              foregroundColor: Colors.black87,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: isLoading
                ? CircularProgressIndicator(color: Colors.black)
                : Text(isLogin ? 'Login' : 'Sign Up'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFCBDCEB),
              foregroundColor: Colors.black87,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.g_mobiledata),
                SizedBox(width: 8),
                Text('Login with Google (coming soon)'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => isLogin = !isLogin),
            child: Text(isLogin
                ? "Don't have an account? Sign up"
                : "Already have an account? Login"),
          ),
          const SizedBox(height: 24),
          Divider(),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _continueAsGuest,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFCBDCEB),
              foregroundColor: Colors.black87,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Text('Continue as Guest'),
          ),
        ],
      ),
    );
  }
}
