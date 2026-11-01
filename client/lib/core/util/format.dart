/// 12-hour clock text such as "8:05 AM" (matches the design's `fmt`).
String fmtTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ap = t.hour >= 12 ? 'PM' : 'AM';
  return '$h:${t.minute.toString().padLeft(2, '0')} $ap';
}

String fmtHm(String hhmm) {
  final p = hhmm.split(':');
  return fmtTime(DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1])));
}

String fmtDuration(Duration d) {
  final m = d.inMinutes < 0 ? 0 : d.inMinutes;
  if (m < 60) return '$m min';
  final r = m % 60;
  return '${m ~/ 60} h${r == 0 ? '' : ' $r min'}';
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String weekdayShort(DateTime d) => _wd[d.weekday - 1];
String fmtDate(DateTime d) => '${weekdayShort(d)}, ${d.day} ${_mo[d.month - 1]}';

String greeting(DateTime now, String name) {
  final part = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
  return '$part, $name';
}

String initialsOf(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}
