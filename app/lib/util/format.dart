import 'package:intl/intl.dart';

/// Short time label used in the chat list ("14:32", "Yesterday", "12/11").
String listTime(int unixSeconds, String language) {
  if (unixSeconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final now = DateTime.now();
  final locale = language == 'ar' ? 'ar' : 'en';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return DateFormat.Hm(locale).format(date);
  if (difference == 1) return language == 'ar' ? 'أمس' : 'Yesterday';
  if (difference < 7) return DateFormat.E(locale).format(date);
  return DateFormat.yMd(locale).format(date);
}

/// Time inside a bubble.
String bubbleTime(int unixSeconds, String language) {
  if (unixSeconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return DateFormat.Hm(language == 'ar' ? 'ar' : 'en').format(date);
}

/// Day separator label ("Today", "Yesterday", or a date).
String dayLabel(DateTime date, String language) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return language == 'ar' ? 'اليوم' : 'Today';
  if (difference == 1) return language == 'ar' ? 'أمس' : 'Yesterday';
  return DateFormat.yMMMMd(language == 'ar' ? 'ar' : 'en').format(date);
}

DateTime dateOf(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);

/// Human readable size for file bubbles.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// mm:ss (or h:mm:ss) used by the call screen timer.
String formatCallDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$mm:$ss'
      : '$mm:$ss';
}
