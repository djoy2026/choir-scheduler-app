import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_messages.dart';

final supabase = Supabase.instance.client;

class SignUpPage extends StatefulWidget {
  final VoidCallback onSwitchToLogin;

  const SignUpPage({super.key, required this.onSwitchToLogin});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  bool _isLoading = false;

  String? _message;

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      setState(() {
        _message = 'Signup successful';
      });
    } on AuthException catch (e, stackTrace) {
      logTechnicalError('SignUpPage._signUp auth failed', e, stackTrace);
      setState(() {
        _message = friendlyErrorMessage(e);
      });
    } catch (e, stackTrace) {
      logTechnicalError('SignUpPage._signUp failed', e, stackTrace);
      setState(() {
        _message = friendlyErrorMessage(
          e,
          fallback: 'Unable to create account. Please try again.',
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Create Account'),
            ),

            TextButton(
              onPressed: widget.onSwitchToLogin,
              child: const Text('Already have an account? Login'),
            ),

            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_message!),
              ),
          ],
        ),
      ),
    );
  }
}
