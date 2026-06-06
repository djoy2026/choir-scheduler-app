import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void logTechnicalError(String context, Object error, [StackTrace? stackTrace]) {
  debugPrint('$context: $error');

  if (stackTrace != null) {
    debugPrintStack(stackTrace: stackTrace);
  }
}

String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is AuthException) {
    return error.message;
  }

  if (error is PostgrestException) {
    final message = error.message.toLowerCase();
    final details = error.details?.toString().toLowerCase() ?? '';
    final combined = '$message $details';

    if (combined.contains('ux_service_slots_one_user_per_service')) {
      return 'This volunteer is already assigned to another role in this service.';
    }

    if (combined.contains('duplicate') ||
        combined.contains('unique constraint')) {
      return 'A matching record already exists.';
    }

    if (combined.contains('permission denied') ||
        combined.contains('row-level security') ||
        combined.contains('rls')) {
      return 'You do not have permission to complete this action.';
    }

    if (combined.contains('foreign key')) {
      return 'This item is connected to other records and cannot be changed right now.';
    }

    if (combined.contains('network') || combined.contains('connection')) {
      return 'Network connection problem. Please try again.';
    }

    return fallback;
  }

  return fallback;
}
