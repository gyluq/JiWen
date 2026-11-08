String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Formats a timestamp for the note list, following the format frozen in
/// requirement R-05: relative within a day, absolute beyond it.
String formatListTime(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final diff = now.difference(time);

  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';

  final isSameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  if (isSameDay) return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';

  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday = time.year == yesterday.year &&
      time.month == yesterday.month &&
      time.day == yesterday.day;
  if (isYesterday) {
    return '昨天 ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
  }

  if (time.year == now.year) return '${time.month}月${time.day}日';
  return '${time.year}年${time.month}月${time.day}日';
}

/// Formats a timestamp for the editor header.
String formatFullTime(int millis) {
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${time.year}-${_twoDigits(time.month)}-${_twoDigits(time.day)} '
      '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
}
