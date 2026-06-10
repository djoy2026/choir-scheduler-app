import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_branding.dart';
import '../utils/error_messages.dart';

final supabase = Supabase.instance.client;

class SignUpPage extends StatefulWidget {
  final VoidCallback onSwitchToLogin;

  const SignUpPage({super.key, required this.onSwitchToLogin});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _message;
  bool _isSuccessMessage = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _message = null;
      _isSuccessMessage = false;
    });

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
          'role': 'volunteer',
        },
      );

      final user = authResponse.user;

      if (user != null) {
        await _upsertProfile(
          userId: user.id,
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
        );
      }

      setState(() {
        _isSuccessMessage = true;
        _message = 'Check your email to verify your account before signing in.';
      });
    } on AuthException catch (e, stackTrace) {
      logTechnicalError('SignUpPage._signUp auth failed', e, stackTrace);
      setState(() {
        _message = _friendlyAuthMessage(e);
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _upsertProfile({
    required String userId,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) async {
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone.isEmpty ? null : phone,
        'role': 'volunteer',
        'status': 'active',
      });
    } catch (e, stackTrace) {
      logTechnicalError('SignUpPage._upsertProfile failed', e, stackTrace);
    }
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }

    return null;
  }

  String? _emailValidator(String? value) {
    final trimmedValue = value?.trim() ?? '';

    if (trimmedValue.isEmpty) {
      return 'Email is required';
    }

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!emailPattern.hasMatch(trimmedValue)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must include an uppercase letter';
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must include a number';
    }

    return null;
  }

  String? _confirmPasswordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Confirm your password';
    }

    if (value != _passwordController.text) {
      return 'Passwords must match';
    }

    return null;
  }

  String _friendlyAuthMessage(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('user already')) {
      return 'An account with this email already exists.';
    }

    if (message.contains('password')) {
      return 'Please choose a stronger password.';
    }

    return 'Unable to create account. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppBranding.primaryDark,
              AppBranding.primary,
              AppBranding.primaryLight,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildSignUpCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
          ),
          child: const Icon(
            Icons.event_available,
            color: Colors.white,
            size: 38,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          AppBranding.appName,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Create your volunteer account',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .84),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    validator: (value) =>
                        _requiredValidator(value, 'First name'),
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(
                      label: 'First Name',
                      icon: Icons.person_outline,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    validator: (value) =>
                        _requiredValidator(value, 'Last name'),
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(
                      label: 'Last Name',
                      icon: Icons.person_outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emailController,
              validator: _emailValidator,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration(
                label: 'Email',
                icon: Icons.email_outlined,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: _inputDecoration(
                label: 'Phone Number (optional)',
                icon: Icons.phone_outlined,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              validator: _passwordValidator,
              obscureText: _obscurePassword,
              decoration: _inputDecoration(
                label: 'Password',
                icon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              validator: _confirmPasswordValidator,
              obscureText: _obscureConfirmPassword,
              decoration: _inputDecoration(
                label: 'Confirm Password',
                icon: Icons.lock_outline,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            _buildCreateButton(),
            const SizedBox(height: 18),
            TextButton(
              onPressed: _isLoading ? null : widget.onSwitchToLogin,
              child: const Text(
                'Already have an account? Login',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isSuccessMessage
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppBranding.primary, width: 1.4),
      ),
    );
  }

  Widget _buildCreateButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _signUp,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: _isLoading
                ? [Colors.grey.shade400, Colors.grey.shade500]
                : [AppBranding.primaryDark, AppBranding.primary],
          ),
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Create Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
