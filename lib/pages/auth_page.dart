import 'package:flutter/material.dart';

import 'login_page.dart';
import 'signup_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _showLogin = true;

  void _toggleMode() {
    setState(() {
      _showLogin = !_showLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _showLogin
        ? LoginPage(onSwitchToSignUp: _toggleMode)
        : SignUpPage(onSwitchToLogin: _toggleMode);
  }
}
