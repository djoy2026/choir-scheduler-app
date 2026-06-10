import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  try {
    debugPrint('APP_START');

    WidgetsFlutterBinding.ensureInitialized();

    await dotenv.load(fileName: '.env');

    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
    debugPrint('SUPABASE_INIT_COMPLETE');

    runApp(const MyApp());
  } catch (error, stackTrace) {
    debugPrint('APP_STARTUP_EXCEPTION: $error');
    debugPrintStack(stackTrace: stackTrace);
    rethrow;
  }
}
