import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'homePage.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    try {
      // Replace with your actual Supabase OAuth client IDs
      const webClientId =
          '72296187665-qfadnqtsc13t7bho3lhclt6ackl9b8d1.apps.googleusercontent.com';
      const iosClientId =
          '72296187665-mesv40b58u30d3cj8cdtqfapvaesijas.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn(
        clientId: iosClientId,
        serverClientId: webClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return; // user canceled

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw 'Missing Google auth tokens.';
      }

      // Sign in to Supabase using OAuth ID token
      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final user = response.user;
      if (user == null) throw 'Login failed: no user returned.';

      // Navigate to HomePage
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomePage(user: user)),
        );
      }
    } catch (e) {
      debugPrint('Login error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login failed: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 2,
          ),
          icon: Image.asset(
            'lib/assets/images/google_logo.jpg',
            height: 24,
          ),
          label: const Text("Sign in with Google"),
          onPressed: () => _handleGoogleSignIn(context),
        ),
      ),
    );
  }
}
