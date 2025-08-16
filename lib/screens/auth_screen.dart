import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:shared_calendar/screens/join_calendar_screen.dart';

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
  bool isLogin = false;
  String? error;

  /// 🔍 Check Firestore for seenTutorial flag
  Future<bool> _getServerSeenTutorialIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      return (snap.data()?['seenTutorial'] == true);
    } catch (_) {
      return false;
    }
  }

  /// 🔁 Post-auth redirect (Invite takes precedence)
  Future<void> _handlePostLoginRedirect() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingInviteId = prefs.getString('pendingInviteId');
    final pendingSharedCalendarId = prefs.getString('pendingSharedCalendarId');

    final inviteId =
        (pendingInviteId?.isNotEmpty ?? false)
            ? pendingInviteId
            : (pendingSharedCalendarId?.isNotEmpty ?? false)
            ? pendingSharedCalendarId
            : null;

    if (inviteId != null) {
      await prefs.remove('pendingInviteId');
      await prefs.remove('pendingSharedCalendarId');

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => JoinCalendarScreen(sharedLinkId: inviteId),
        ),
      );
      return;
    }

    if (!mounted) return;
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

  /// Convenience: check if an invite is pending right now
  Future<bool> _hasPendingInvite() async {
    final prefs = await SharedPreferences.getInstance();
    final a = prefs.getString('pendingInviteId');
    final b = prefs.getString('pendingSharedCalendarId');
    return (a != null && a.isNotEmpty) || (b != null && b.isNotEmpty);
  }

  void _checkCurrentIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final guestId = prefs.getString('guestId');
    final hasContinuedAsGuest = prefs.getBool('hasContinuedAsGuest') ?? false;
    bool seenTutorialLocal = prefs.getBool('seenTutorial') ?? false;

    // If logged in, consult server flag and sync local cache.
    bool seenTutorialServer = false;
    if (user != null && !user.isAnonymous) {
      seenTutorialServer = await _getServerSeenTutorialIfAny();
      if (seenTutorialServer && !seenTutorialLocal) {
        await prefs.setBool('seenTutorial', true);
        seenTutorialLocal = true;
      }
    }

    final isAuthed = (user != null) || (guestId != null && hasContinuedAsGuest);
    if (isAuthed) {
      setState(() => isLogin = true);

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 🚨 Invite should always take precedence over onboarding
        if (await _hasPendingInvite()) {
          await _handlePostLoginRedirect();
          return;
        }

        final shouldSkip =
            (user != null && !user.isAnonymous)
                ? seenTutorialServer
                : seenTutorialLocal;

        if (shouldSkip) {
          await _handlePostLoginRedirect();
        } else {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/onboarding');
        }
      });
    } else {
      setState(() => isLogin = false);
    }
  }

  Future<void> _loginOrSignUp() async {
    bool justSignedUp = false;
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
          justSignedUp = true;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            final methods = await FirebaseAuth.instance
                .fetchSignInMethodsForEmail(email);
            final msg =
                methods.contains('google.com')
                    ? "This email is registered via Google. Use Google Sign-In."
                    : "Email already in use. Try Google Sign-In.";
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
            setState(() => isLoading = false);
            return;
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

      // ✅ Brand-new account → onboarding (no server flag yet)
      if (justSignedUp) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/onboarding');
        setState(() => isLoading = false);
        return;
      }

      // 🚨 If we came from an invite, ALWAYS skip onboarding and go to Join
      if (await _hasPendingInvite()) {
        await _handlePostLoginRedirect();
        setState(() => isLoading = false);
        return;
      }

      // Otherwise, use server flag to decide onboarding
      final serverSeen = await _getServerSeenTutorialIfAny();
      if (serverSeen) {
        await prefs.setBool('seenTutorial', true); // keep local in sync
        await _handlePostLoginRedirect();
      } else {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/onboarding');
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Auth Error: ${e.message}")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're already signed in.")),
      );
      return;
    }

    String? guestId = prefs.getString('guestId');
    if (guestId == null) {
      guestId = const Uuid().v4();
      await prefs.setString('guestId', guestId);
    }
    await prefs.setBool('hasContinuedAsGuest', true);

    // 🚨 Invite still takes precedence
    if (await _hasPendingInvite()) {
      await _handlePostLoginRedirect();
      return;
    }

    final seenTutorial = prefs.getBool('seenTutorial') ?? false;
    if (seenTutorial) {
      await _handlePostLoginRedirect();
    } else {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignIn googleUser = GoogleSignIn();
      final GoogleSignInAccount? account = await googleUser.signIn();
      if (account == null) return;

      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);

      // 🚨 If we came from an invite, ALWAYS skip onboarding and go to Join
      if (await _hasPendingInvite()) {
        await _handlePostLoginRedirect();
        return;
      }

      // Otherwise use server flag
      final prefs = await SharedPreferences.getInstance();
      final serverSeen = await _getServerSeenTutorialIfAny();
      if (serverSeen) {
        await prefs.setBool('seenTutorial', true);
        await _handlePostLoginRedirect();
      } else {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/onboarding');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google Sign-In failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      body:
          isMobile
              ? _buildFormLayout()
              : Row(
                children: [
                  Expanded(child: _buildFormLayout()),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
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
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo_final.png', height: 170),
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
            isLogin ? 'Welcome Back' : 'Let’s Get Started',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isLogin
                ? 'Login to continue using Link Up Calendar.'
                : 'Create your account to start collaborating.',
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
                    const SizedBox(width: 10),
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
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return 'Email is required';
              final emailRegex = RegExp(
                r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
              );
              if (!emailRegex.hasMatch(trimmed)) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            validator:
                (value) =>
                    value == null || value.length < 6
                        ? 'Minimum 6 characters'
                        : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: isLoading ? null : _loginOrSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCBDCEB),
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child:
                isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(isLogin ? 'Login' : 'Sign Up'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _signInWithGoogle,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCBDCEB),
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Row(
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
            child: Text(
              isLogin
                  ? "Don't have an account? Sign up"
                  : "Already have an account? Login",
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _continueAsGuest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCBDCEB),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('Continue as Guest'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.grey),
                tooltip: "About Guest Login",
                onPressed: () {
                  showDialog(
                    context: context,
                    builder:
                        (ctx) => AlertDialog(
                          title: const Text("⚠️ About Guest Login"),
                          content: const Text(
                            "Guest Login is stored only on this browser.\n\n"
                            "• If you clear your browser cache, switch devices, or use incognito mode, "
                            "your guest calendars and events may be lost.\n\n"
                            "• To keep your data safe across devices, sign up with Email or Google instead.",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("Got it"),
                            ),
                          ],
                        ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
