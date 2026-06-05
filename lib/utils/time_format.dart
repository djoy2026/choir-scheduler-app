String formatTime(String? rawTime) {
  if (rawTime == null || rawTime.trim().isEmpty) {
    return '';
  }

  final parts = rawTime.trim().split(':');

  if (parts.length < 2) {
    return rawTime;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);

  if (hour == null || minute == null) {
    return rawTime;
  }

  final displayHour = hour > 12
      ? hour - 12
      : hour == 0
      ? 12
      : hour;
  final period = hour >= 12 ? 'PM' : 'AM';

  return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
}

String formatTimeRange(String? startTime, String? endTime) {
  final start = formatTime(startTime);
  final end = formatTime(endTime);

  if (start.isEmpty) {
    return end;
  }

  if (end.isEmpty) {
    return start;
  }

  return '$start - $end';
}

DateTime? parseServiceDate(String? rawDate) {
  if (rawDate == null || rawDate.trim().isEmpty) {
    return null;
  }

  final trimmed = rawDate.trim();
  final isoDate = DateTime.tryParse(trimmed);

  if (isoDate != null) {
    return isoDate;
  }

  final slashParts = trimmed.split('/');

  if (slashParts.length == 3) {
    final month = int.tryParse(slashParts[0]);
    final day = int.tryParse(slashParts[1]);
    final year = int.tryParse(slashParts[2]);

    if (month != null && day != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  return null;
}

String formatNumericDate(String? rawDate) {
  final parsedDate = parseServiceDate(rawDate);

  if (parsedDate == null) {
    return rawDate ?? '';
  }

  return '${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.year}';
}

String formatServiceHeading(String? serviceDate, String? startTime) {
  final parsedDate = parseServiceDate(serviceDate);
  final formattedTime = formatTime(startTime);

  if (parsedDate == null) {
    return formattedTime;
  }

  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final formattedDate =
      '${weekdays[parsedDate.weekday - 1]}, ${months[parsedDate.month]} ${parsedDate.day}';

  if (formattedTime.isEmpty) {
    return formattedDate;
  }

  return '$formattedDate • $formattedTime';
}

String removeServiceSuffix(String title) {
  return title.replaceFirst(RegExp(r'\s+Service$', caseSensitive: false), '');
}
