// lib/screens/auth_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/join_calendar_screen.dart';

class AuthLandingScreen extends StatefulWidget {
  const AuthLandingScreen({super.key});

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

  // ---------- helper: themed asset (adds _dark before extension in dark mode) ----------
  String _themedAsset(BuildContext context, String path) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return path;
    final dot = path.lastIndexOf('.');
    if (dot <= 0) return path;
    return '${path.substring(0, dot)}_dark${path.substring(dot)}';
  }

  /// 🔍 Check Firestore for seenTutorial flag
  Future<bool> _getServerSeenTutorialIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

    final inviteId = (pendingInviteId?.isNotEmpty ?? false)
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
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    bool seenTutorialLocal = prefs.getBool('seenTutorial') ?? false;

    // If logged in, consult server flag and sync local cache.
    bool seenTutorialServer = false;
    if (user != null) {
      seenTutorialServer = await _getServerSeenTutorialIfAny();
      if (seenTutorialServer && !seenTutorialLocal) {
        await prefs.setBool('seenTutorial', true);
        seenTutorialLocal = true;
      }
    }

    final isAuthed = (user != null);

    if (isAuthed) {
      setState(() => isLogin = true);

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 🚨 Invite should always take precedence over onboarding
        if (await _hasPendingInvite()) {
          await _handlePostLoginRedirect();
          return;
        }

        final shouldSkip = seenTutorialServer || seenTutorialLocal;

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
            final methods =
                await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
            final msg = methods.contains('google.com')
                ? "This email is registered via Google. Use Google Sign-In."
                : "Email already in use. Try Google Sign-In.";
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Auth Error: ${e.message}")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Google sign-in (links if a legacy anonymous session somehow exists)
  Future<void> _signInWithGoogle() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      final account = await GoogleSignIn().signIn();
      if (account == null) {
        setState(() => isLoading = false);
        return;
      }
      final gAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      if (auth.currentUser?.isAnonymous == true) {
        // Legacy upgrade path: keep the same UID
        await auth.currentUser!.linkWithCredential(credential);
      } else {
        await auth.signInWithCredential(credential);
      }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Sign-In failed')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
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
                        image:
                        AssetImage('assets/bg_login.png'),
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
              // 🔄 uses logo_final_dark.png automatically in dark theme
              Image.asset(
                _themedAsset(context, 'assets/logo_final.png'),
                height: 170,
              ),
              const SizedBox(height: 32),
              _buildLoginForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isLogin ? 'Welcome Back' : 'Let’s Get Started',
            style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ) ??
                const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isLogin
                ? 'Login to continue using Link Up Calendar.'
                : 'Create your account to start collaborating.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
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
            validator: (value) =>
                value == null || value.length < 6 ? 'Minimum 6 characters' : null,
          ),
          const SizedBox(height: 24),

          // Buttons styled from theme for better dark-mode contrast
          ElevatedButton(
            onPressed: isLoading ? null : _loginOrSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: isLoading
                ? CircularProgressIndicator(color: cs.onPrimary)
                : Text(isLogin ? 'Login' : 'Sign Up'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: isLoading ? null : _signInWithGoogle,
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
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
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white : Colors.black,
            ),
            onPressed: () => setState(() => isLogin = !isLogin),
            child: Text(
              isLogin
                  ? "Don't have an account? Sign up"
                  : "Already have an account? Login",
            ),
          ),
        ],
      ),
    );
  }
}
