import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_branding.dart';
import 'auth_page.dart';
import 'home_page.dart';

final supabase = Supabase.instance.client;

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _showSplash();
  }

  Future<void> _showSplash() async {
    await _controller.forward();
    await Future.delayed(const Duration(milliseconds: 550));
    await _controller.reverse();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          final session = supabase.auth.currentSession;

          return FadeTransition(
            opacity: animation,
            child: session == null ? const AuthPage() : const HomePage(),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppBranding.primaryDark, AppBranding.primary],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SplashBrandMark(),
                const SizedBox(height: 20),
                const Text(
                  AppBranding.appName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Volunteer Scheduling Platform',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .78),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashBrandMark extends StatelessWidget {
  const _SplashBrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: .2)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.calendar_month, size: 54, color: Colors.white),
          Positioned(
            right: 24,
            bottom: 24,
            child: Icon(
              Icons.music_note,
              size: 25,
              color: Colors.amber.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
