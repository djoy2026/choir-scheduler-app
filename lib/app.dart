import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/auth_page.dart';
import 'pages/home_page.dart';
import 'pages/splash_page.dart';
import 'theme/app_branding.dart';

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppBranding.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppBranding.primary),
        scaffoldBackgroundColor: AppBranding.surface,
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: Colors.grey.shade900,
          displayColor: Colors.grey.shade900,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const SplashPage(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      debugPrint('SESSION_CHECK_START');
      final session = supabase.auth.currentSession;
      debugPrint('SESSION_CHECK_COMPLETE');

      if (session != null) {
        debugPrint('ROUTE_HOME');
        return const HomePage();
      }

      debugPrint('ROUTE_LOGIN');
      return const AuthPage();
    } catch (error, stackTrace) {
      debugPrint('AUTH_GATE_EXCEPTION: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
