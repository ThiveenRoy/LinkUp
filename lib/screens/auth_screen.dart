import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthLandingScreen extends StatefulWidget {
  @override
  _AuthLandingScreenState createState() => _AuthLandingScreenState();
  
}

class _AuthLandingScreenState extends State<AuthLandingScreen> {
   @override
    void initState() {
      super.initState();
      _checkCurrentIdentity();
    }

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;
  bool isLogin = true;
  String? error;

  // 🔁 Check for shared calendar and navigate accordingly
  Future<void> _handlePostLoginRedirect() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingSharedCalendarId = prefs.getString('pendingSharedCalendarId');

    if (pendingSharedCalendarId != null) {
      await prefs.remove('pendingSharedCalendarId');

      // 🔍 Fetch calendar name
      final doc = await FirebaseFirestore.instance
          .collection('calendars')
          .doc(pendingSharedCalendarId)
          .get();
      final calendarName = doc.data()?['name'] ?? 'Shared Calendar';

      // ✅ Redirect to CalendarHomeScreen (tabIndex 1)
      Navigator.pushNamed(context, '/calendarHome', arguments: {
        'calendarId': pendingSharedCalendarId,
        'calendarName': calendarName,
        'tabIndex': 1,
        'fromInvite': true,
      });
      return;
    }

    // Default to CalendarHome tab 0
    Navigator.pushNamed(context, '/calendarHome', arguments: {
      'calendarId': null,
      'calendarName': 'LinkUp Calendar',
      'tabIndex': 0,
    });
  }

  void _checkCurrentIdentity() async {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final guestId = prefs.getString('guestId');

      if (user != null) {
        print("👤 Logged in user: ${user.uid}");
      } else if (guestId != null) {
        print("👤 Guest ID in SharedPrefs: $guestId");
      } else {
        print("🆕 No user found, will generate guest on continue");
      }
    }


  Future<void> _loginOrSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
            if (methods.contains('google.com')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("This email is already registered via Google. Please sign in using Google."),
                ),
              );
              setState(() => isLoading = false);
              return;
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Email is already in use. Try Google Sign")),
              );
              setState(() => isLoading = false);
              return;
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Signup Error: ${e.message}")),
            );
            setState(() => isLoading = false);
            return;
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final guestId = prefs.getString('guestId');
      print("👤 Retained guest ID after login: $guestId");

      // 🔁 Redirect based on shared calendar presence
      await _handlePostLoginRedirect();

    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Auth Error: ${e.message}")),
      );
    } catch (e) {
      print("Unexpected error: $e");
      setState(() => error = isLogin
          ? "Login failed. Please check your credentials."
          : "Sign up failed. Please try again.");
    }

    setState(() => isLoading = false);
  }

  Future<void> _continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = FirebaseAuth.instance.currentUser;

    // 🔒 Don't allow guest if user is still signed in
    if (currentUser != null) {
      print("⚠️ Cannot continue as guest. Firebase user still signed in: ${currentUser.uid}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You're already signed in. Please logout first.")),
      );
      return;
    }

    // ✅ Only create new guest ID if not exists
    String? guestId = prefs.getString('guestId');
    if (guestId == null) {
      guestId = const Uuid().v4();
      await prefs.setString('guestId', guestId);
      print("🆕 Guest session started with ID: $guestId");
    } else {
      print("♻️ Reusing existing guest ID: $guestId");
    }

    await _handlePostLoginRedirect();
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignIn googleUser = GoogleSignIn();
      final GoogleSignInAccount? account = await googleUser.signIn();
      if (account == null) return;

      final GoogleSignInAuthentication auth = await account.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      final prefs = await SharedPreferences.getInstance();
      final guestId = prefs.getString('guestId');
      print("👤 Retained guest ID after login: $guestId");
      // 🔁 Redirect based on shared calendar presence
      await _handlePostLoginRedirect();

    } catch (e) {
      print('Google Sign-In failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google Sign-In failed')),
      );
    }
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
              if (trimmed.isEmpty) return 'Email is required';
              final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(trimmed)) return 'Enter a valid email';
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
            onPressed: _signInWithGoogle,
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
                Text('Login with Google'),
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
